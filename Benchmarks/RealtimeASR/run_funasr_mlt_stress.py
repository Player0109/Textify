#!/usr/bin/env python3
"""Run focused robustness checks for Textify's promoted Fun-ASR languages."""

import argparse
import json
import platform
import subprocess
import tempfile
from pathlib import Path

import run_funasr_mlt_sample as common


PROMOTED_LANGUAGES = ["ar", "en", "id", "ja", "ko", "ms", "th", "tl", "vi", "yue", "zh"]
ONE_WORD_CASES = {
    "ar": ("قمر صناعي", "one-word-ar.wav"),
    "en": ("satellite", "one-word-en.wav"),
    "id": ("satelit", "one-word-id.wav"),
    "ja": ("衛星", "one-word-ja.wav"),
    "ko": ("위성", "one-word-ko.wav"),
    "ms": ("satelit", "one-word-ms.wav"),
    "th": ("ดาวเทียม", "one-word-th.wav"),
    "vi": ("vệ tinh", "one-word-vi.wav"),
    "yue": ("衛星", "one-word-yue.wav"),
    "zh": ("卫星", "one-word-zh.wav"),
}


def run_case(cli: Path, model: Path, case: dict) -> dict:
    audio = case["audio"].resolve()
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as batch:
        batch.write(str(audio) + "\n")
        batch.flush()
        completed = subprocess.run(
            [
                str(cli), "-q", "--batch", batch.name, "--batch-jsonl",
                "--batch-size", "1", "--backend", "metal", "--n-ctx", "4096",
                "--language", case["language"], "--itn", "-m", str(model),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    combined_log = completed.stdout + "\n" + completed.stderr
    records = [
        json.loads(line)
        for line in combined_log.splitlines()
        if line.startswith("{") and "\"file\"" in line
    ]
    if len(records) != 1:
        raise RuntimeError(f"unexpected transcribe.cpp output for {case['id']}")
    if "using metal backend" not in combined_log or "GPU name:" not in combined_log:
        raise RuntimeError(f"no Metal execution evidence for {case['id']}")
    record = records[0]
    latency = record["mel_ms"] + record["encode_ms"] + record["decode_ms"]
    result = {
        "id": case["id"],
        "category": case["category"],
        "language": case["language"],
        "audio": str(audio),
        "audioSha256": common.sha256(audio),
        "durationMs": round(common.audio_duration_ms(audio), 1),
        "hypothesis": record["text"],
        "releaseToFinalMs": round(latency, 1),
    }
    reference = case.get("reference")
    if reference is not None:
        reference_words = common.folded_words(reference)
        hypothesis_words = common.folded_words(record["text"])
        reference_characters = common.folded_characters(reference)
        hypothesis_characters = common.folded_characters(record["text"])
        result.update(
            {
                "reference": reference,
                "wordErrors": common.edit_distance(reference_words, hypothesis_words),
                "referenceWords": len(reference_words),
                "characterErrors": common.edit_distance(
                    reference_characters, hypothesis_characters
                ),
                "referenceCharacters": len(reference_characters),
            }
        )
    if case["category"] == "silence":
        result.update(
            {
                "audioHasAudibleSignalAtTextifyThreshold": False,
                "textifyNoSpeechProbability": 1,
                "textifyWouldDiscardTranscript": True,
                "textifyWouldSkipInference": True,
                "textifyExpectedInferenceDurationMs": 0,
            }
        )
    return result


def main() -> None:
    script_directory = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--cli", required=True, type=Path)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument(
        "--stress-directory",
        type=Path,
        default=script_directory / ".benchmark-data/funasr-mlt-stress",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=script_directory / "results/funasr-mlt-nano-2512-q8_0-metal-stress.json",
    )
    arguments = parser.parse_args()
    cli = arguments.cli.resolve()
    model = arguments.model.resolve()
    stress_directory = arguments.stress_directory.resolve()
    runtime = common.verify_runtime(cli)
    model_metadata = common.verify_model(model)
    if model_metadata["quantization"] != "Q8_0":
        raise RuntimeError("the production stress gate requires the pinned Q8_0 model")

    corpus = json.loads(
        (script_directory / "Corpus/fleurs-funasr-mlt-31-sample.json").read_text(
            encoding="utf-8"
        )
    )
    first_fleurs_rows = {
        language: next(item for item in corpus["items"] if item["language"] == language)
        for language in PROMOTED_LANGUAGES
    }

    cases = []
    for language, (reference, filename) in ONE_WORD_CASES.items():
        cases.append(
            {
                "id": f"one-word-{language}",
                "category": "one-word",
                "language": language,
                "audio": stress_directory / filename,
                "reference": reference,
            }
        )
    for language in PROMOTED_LANGUAGES:
        cases.extend(
            [
                {
                    "id": f"noisy-{language}",
                    "category": "white-noise",
                    "language": language,
                    "audio": stress_directory / f"noisy-{language}.wav",
                    "reference": first_fleurs_rows[language]["reference"],
                },
                {
                    "id": f"silence-{language}",
                    "category": "silence",
                    "language": language,
                    "audio": stress_directory / "silence.wav",
                },
            ]
        )
    cases.extend(
        [
            {
                "id": "technical-en",
                "category": "technical-terms",
                "language": "en",
                "audio": stress_directory / "technical.wav",
                "reference": "Please review the Swift package, verify the SHA 256 checksum, and keep transcription entirely offline.",
            },
            {
                "id": "numerals-en",
                "category": "punctuation-and-numerals",
                "language": "en",
                "audio": stress_directory / "numerals.wav",
                "reference": "Textify version 2 point 1 costs 42 dollars and 50 cents on July 19th, 2026.",
            },
            *[
                {
                    "id": f"accent-{accent}",
                    "category": "accented-English",
                    "language": "en",
                    "audio": stress_directory / f"accent-{accent}.wav",
                    "reference": "Textify should return the final transcript quickly after I release the key.",
                }
                for accent in ["india", "britain", "australia"]
            ],
            {
                "id": "code-switch-en-zh",
                "category": "code-switch",
                "language": "en",
                "audio": stress_directory / "code-switch.wav",
                "reference": "The meeting starts at nine thirty. 请打开项目并检查最新版本。",
            },
            {
                "id": "maximum-duration-en",
                "category": "maximum-duration",
                "language": "en",
                "audio": stress_directory / "max-duration.wav",
            },
        ]
    )

    for case in cases:
        if not case["audio"].is_file():
            raise RuntimeError(f"missing stress audio: {case['audio']}")
    results = []
    for case in cases:
        print(f"Running {case['id']}", flush=True)
        results.append(run_case(cli, model, case))

    output = {
        "schemaVersion": 1,
        "engine": "funasr-mlt-nano-2512",
        "computeBackend": "Metal",
        "fullyOffline": True,
        "session": {"nCtx": 4096},
        "noisePreparation": {
            "speechLoudnessTargetLUFS": -23,
            "speechTruePeakTargetDBTP": -2,
            "whiteNoiseLinearAmplitude": 0.02,
        },
        "runtime": runtime,
        "model": model_metadata,
        "host": {
            "chip": common.command_output("sysctl", "-n", "machdep.cpu.brand_string"),
            "architecture": platform.machine(),
            "operatingSystem": common.command_output("sw_vers", "-productVersion"),
            "operatingSystemBuild": common.command_output("sw_vers", "-buildVersion"),
        },
        "cases": results,
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {arguments.output}")


if __name__ == "__main__":
    main()
