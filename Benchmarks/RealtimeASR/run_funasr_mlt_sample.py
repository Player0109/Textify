#!/usr/bin/env python3
"""Benchmark the pinned Fun-ASR MLT Q4 GGUF over its 31 claimed languages."""

import argparse
import hashlib
import json
import math
import platform
import re
import struct
import subprocess
import tempfile
import unicodedata
from pathlib import Path


RUNTIME_COMMIT = "5a5a49664a8ea1f0e5b3be1dfc544730d1b62561"
MODEL_REPOSITORY = "handy-computer/Fun-ASR-MLT-Nano-2512-gguf"
MODEL_REVISION = "0b8f9c7bc545a219658aeb1dd4eeaa55d1cf89f3"
MODEL_VARIANTS = {
    "Fun-ASR-MLT-Nano-2512-Q4_K_M.gguf": {
        "sizeBytes": 556_975_168,
        "sha256": "9232584a27a7dcbcaf13640de8f9c2e7375178ea11e587f90a5328ecf06d58a1",
        "quantization": "Q4_K_M",
    },
    "Fun-ASR-MLT-Nano-2512-Q8_0.gguf": {
        "sizeBytes": 891_271_232,
        "sha256": "d12476d8d9f2baa0ebf738fa955fa05ed33a654f1567289033a810c45d9d9002",
        "quantization": "Q8_0",
    },
}
CER_PRIMARY_LANGUAGES = {"zh", "yue", "ja", "th"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def folded_characters(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKD", text).lower()
    return [
        character
        for character in normalized
        if unicodedata.category(character) != "Mn" and character.isalnum()
    ]


def folded_words(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKD", text).lower()
    normalized = "".join(
        character
        for character in normalized
        if unicodedata.category(character) != "Mn"
    )
    return re.findall(r"[^\W_]+", normalized, flags=re.UNICODE)


def edit_distance(reference: list[str], hypothesis: list[str]) -> int:
    previous = list(range(len(hypothesis) + 1))
    for reference_index, reference_value in enumerate(reference, start=1):
        current = [reference_index]
        for hypothesis_index, hypothesis_value in enumerate(hypothesis, start=1):
            current.append(
                min(
                    previous[hypothesis_index - 1]
                    + (reference_value != hypothesis_value),
                    current[hypothesis_index - 1] + 1,
                    previous[hypothesis_index] + 1,
                )
            )
        previous = current
    return previous[-1]


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def median(values: list[float]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def command_output(*command: str) -> str:
    return subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def audio_duration_ms(path: Path) -> float:
    byte_rate = None
    data_size = None
    with path.open("rb") as audio:
        header = audio.read(12)
        if header[:4] != b"RIFF" or header[8:] != b"WAVE":
            raise RuntimeError(f"unsupported WAV container: {path}")
        while chunk_header := audio.read(8):
            if len(chunk_header) != 8:
                raise RuntimeError(f"truncated WAV chunk: {path}")
            chunk_id, chunk_size = struct.unpack("<4sI", chunk_header)
            if chunk_id == b"fmt ":
                chunk = audio.read(chunk_size)
                if len(chunk) < 16:
                    raise RuntimeError(f"truncated WAV format: {path}")
                byte_rate = struct.unpack("<HHIIHH", chunk[:16])[3]
            elif chunk_id == b"data":
                data_size = chunk_size
                audio.seek(chunk_size, 1)
            else:
                audio.seek(chunk_size, 1)
            if chunk_size % 2:
                audio.seek(1, 1)
            if byte_rate is not None and data_size is not None:
                break
    if not byte_rate or data_size is None:
        raise RuntimeError(f"missing WAV duration metadata: {path}")
    return data_size * 1000 / byte_rate


def verify_runtime(cli: Path) -> dict:
    source = cli.parents[2]
    if command_output("git", "-C", str(source), "rev-parse", "HEAD") != RUNTIME_COMMIT:
        raise RuntimeError("transcribe.cpp source commit does not match the benchmark pin")
    source_diff = subprocess.run(
        [
            "git",
            "-C",
            str(source),
            "diff",
            "--",
            "src/arch/funasr_nano/model.cpp",
        ],
        check=True,
        capture_output=True,
    ).stdout
    if b"publisher_prompt_language" not in source_diff:
        raise RuntimeError("required Fun-ASR language-prompt patch is absent")
    return {
        "name": "transcribe.cpp",
        "version": "0.1.3",
        "revision": RUNTIME_COMMIT,
        "license": "MIT",
        "executableSha256": sha256(cli),
        "sourceDiffSha256": hashlib.sha256(source_diff).hexdigest(),
        "localPatches": [
            "Map ISO language codes to the publisher's documented prompt-language names"
        ],
    }


def verify_model(model: Path) -> dict:
    variant = MODEL_VARIANTS.get(model.name)
    if variant is None:
        raise RuntimeError("Fun-ASR MLT filename does not match a benchmark pin")
    if model.stat().st_size != variant["sizeBytes"] or sha256(model) != variant["sha256"]:
        raise RuntimeError("Fun-ASR MLT model does not match the benchmark pin")
    return {
        "repository": MODEL_REPOSITORY,
        "revision": MODEL_REVISION,
        "filename": model.name,
        **variant,
        "baseModel": "FunAudioLLM/Fun-ASR-MLT-Nano-2512",
        "baseModelLicense": "Apache-2.0",
    }


def verify_corpus(corpus_path: Path, data_directory: Path) -> dict:
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    if len(corpus["languages"]) != 31 or len(corpus["items"]) != 310:
        raise RuntimeError("expected 31 languages and 310 corpus items")
    for item in corpus["items"]:
        audio = data_directory / item["audio"]
        if audio.stat().st_size != item["sizeBytes"] or sha256(audio) != item["sha256"]:
            raise RuntimeError(f"corpus audio changed: {audio}")
    return corpus


def benchmark_language(
    cli: Path,
    model: Path,
    language: str,
    items: list[dict],
    data_directory: Path,
) -> dict:
    audio_paths = [(data_directory / item["audio"]).resolve() for item in items]
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as batch:
        batch.write("\n".join(str(path) for path in audio_paths) + "\n")
        batch.flush()
        completed = subprocess.run(
            [
                str(cli),
                "-q",
                "--batch",
                batch.name,
                "--batch-jsonl",
                "--batch-size",
                "1",
                "--backend",
                "metal",
                "--n-ctx",
                "4096",
                "--language",
                language,
                "--itn",
                "-m",
                str(model),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    combined_log = completed.stdout + "\n" + completed.stderr
    records = []
    load_ms = None
    for line in combined_log.splitlines():
        if not line.startswith("{"):
            continue
        record = json.loads(line)
        if record.get("type") == "batch_header":
            load_ms = record["load_ms"]
        elif "file" in record:
            records.append(record)
    if load_ms is None or len(records) != len(items):
        raise RuntimeError(f"unexpected transcribe.cpp output for {language}")
    if "using metal backend" not in combined_log or "GPU name:" not in combined_log:
        raise RuntimeError(f"no Metal execution evidence for {language}")

    item_results = []
    total_word_errors = 0
    total_reference_words = 0
    total_character_errors = 0
    total_reference_characters = 0
    release_latencies = []
    for item, audio_path, record in zip(items, audio_paths, records):
        if Path(record["file"]).resolve() != audio_path:
            raise RuntimeError(f"transcribe.cpp changed batch order for {language}")
        reference_words = folded_words(item["reference"])
        hypothesis_words = folded_words(record["text"])
        reference_characters = folded_characters(item["reference"])
        hypothesis_characters = folded_characters(record["text"])
        word_errors = edit_distance(reference_words, hypothesis_words)
        character_errors = edit_distance(reference_characters, hypothesis_characters)
        release_to_final_ms = record["mel_ms"] + record["encode_ms"] + record["decode_ms"]
        duration_ms = audio_duration_ms(audio_path)
        release_latencies.append(release_to_final_ms)
        total_word_errors += word_errors
        total_reference_words += len(reference_words)
        total_character_errors += character_errors
        total_reference_characters += len(reference_characters)
        item_results.append(
            {
                "id": item["id"],
                "reference": item["reference"],
                "hypothesis": record["text"],
                "durationMs": round(duration_ms, 1),
                "releaseToFinalMs": round(release_to_final_ms, 1),
                "realTimeFactor": release_to_final_ms / duration_ms,
                "wordErrors": word_errors,
                "referenceWords": len(reference_words),
                "characterErrors": character_errors,
                "referenceCharacters": len(reference_characters),
            }
        )

    return {
        "language": language,
        "primaryMetric": "characterErrorRate" if language in CER_PRIMARY_LANGUAGES else "wordErrorRate",
        "loadMs": load_ms,
        "wordErrorRate": total_word_errors / total_reference_words,
        "wordErrors": total_word_errors,
        "referenceWords": total_reference_words,
        "characterErrorRate": total_character_errors / total_reference_characters,
        "characterErrors": total_character_errors,
        "referenceCharacters": total_reference_characters,
        "medianReleaseToFinalMs": round(median(release_latencies), 1),
        "p95ReleaseToFinalMs": round(percentile(release_latencies, 0.95), 1),
        "maximumReleaseToFinalMs": round(max(release_latencies), 1),
        "items": item_results,
    }


def main() -> None:
    script_directory = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--cli", required=True, type=Path)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument(
        "--output",
        type=Path,
    )
    arguments = parser.parse_args()
    cli = arguments.cli.resolve()
    model = arguments.model.resolve()
    corpus_path = script_directory / "Corpus/fleurs-funasr-mlt-31-sample.json"
    data_directory = script_directory / ".benchmark-data/fleurs-funasr-mlt-31-sample"
    corpus = verify_corpus(corpus_path, data_directory)
    runtime_metadata = verify_runtime(cli)
    model_metadata = verify_model(model)
    output_path = arguments.output or (
        script_directory
        / (
            "results/funasr-mlt-nano-2512-"
            f"{model_metadata['quantization'].lower()}-metal-fleurs-31-language-map.json"
        )
    )

    results = []
    for language in corpus["languages"]:
        items = [item for item in corpus["items"] if item["language"] == language]
        print(f"Benchmarking {language} ({len(items)} clips)", flush=True)
        results.append(benchmark_language(cli, model, language, items, data_directory))

    output = {
        "schemaVersion": 1,
        "engine": "funasr-mlt-nano-2512",
        "computeBackend": "Metal",
        "fullyOffline": True,
        "session": {"nCtx": 4096},
        "runtime": runtime_metadata,
        "model": model_metadata,
        "corpus": {
            **corpus["dataset"],
            "manifestSha256": sha256(corpus_path),
            "languages": len(corpus["languages"]),
            "items": len(corpus["items"]),
        },
        "host": {
            "chip": command_output("sysctl", "-n", "machdep.cpu.brand_string"),
            "architecture": platform.machine(),
            "operatingSystem": command_output("sw_vers", "-productVersion"),
            "operatingSystemBuild": command_output("sw_vers", "-buildVersion"),
        },
        "languages": results,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
