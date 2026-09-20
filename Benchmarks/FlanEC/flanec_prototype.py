# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "huggingface-hub==0.36.0",
#   "numpy<2",
#   "safetensors==0.4.2",
#   "torch==2.2.2",
#   "transformers==4.38.2",
# ]
# ///
"""PROTOTYPE: evaluate immutable FlanEC checkpoints against Textify cases."""

import argparse
import time
from dataclasses import dataclass

import torch
from huggingface_hub import snapshot_download
from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

from flanec_logic import (
    BUILT_IN_CASES,
    EvaluationCase,
    format_prompt,
    repeated_one_best,
)


@dataclass(frozen=True)
class Checkpoint:
    repo_id: str
    revision: str
    download_bytes: int


CHECKPOINTS = {
    "base": Checkpoint(
        repo_id="morenolq/flanec-base-cd",
        revision="e3c8a1ea702dfb2e47ce77733a31123ea18dbe56",
        download_bytes=992_800_000,
    ),
    "large": Checkpoint(
        repo_id="morenolq/flanec-large-cd",
        revision="f86eb6dbc8de5b8f2612e49ddae2db4114ef8aed",
        download_bytes=3_135_100_000,
    ),
}

MODEL_FILES = (
    "README.md",
    "config.json",
    "generation_config.json",
    "model.safetensors",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer_config.json",
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the real FlanEC checkpoint on Textify's fixed evaluation cases "
            "or on one custom transcript."
        )
    )
    parser.add_argument("--checkpoint", choices=CHECKPOINTS, default="base")
    parser.add_argument(
        "--one-best",
        help="Custom Textify-style one-best transcript; duplicated into five hypotheses.",
    )
    parser.add_argument(
        "--expected",
        help="Expected correction for --one-best; defaults to the input text.",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Require the exact checkpoint to exist in the local Hugging Face cache.",
    )
    return parser.parse_args()


def synchronize(device: str) -> None:
    if device == "mps":
        torch.mps.synchronize()


def generate(model, tokenizer, device: str, case: EvaluationCase) -> tuple[str, float]:
    inputs = tokenizer(
        format_prompt(case.hypotheses),
        return_tensors="pt",
        truncation=True,
        max_length=512,
    ).to(device)
    started = time.perf_counter()
    with torch.inference_mode():
        output_ids = model.generate(
            **inputs,
            max_new_tokens=128,
            num_beams=3,
            do_sample=False,
        )
    synchronize(device)
    latency = time.perf_counter() - started
    return tokenizer.decode(output_ids[0], skip_special_tokens=True), latency


def print_case(case: EvaluationCase, output: str, latency: float) -> None:
    print(f"\nCASE {case.name}")
    for index, hypothesis in enumerate(case.hypotheses, start=1):
        print(f"  hypothesis_{index}: {hypothesis}")
    print(f"  expected: {case.expected}")
    print(f"  corrected: {output}")
    print(f"  exact_match: {output == case.expected}")
    print(f"  latency_seconds: {latency:.3f}")


def main() -> None:
    arguments = parse_arguments()
    checkpoint = CHECKPOINTS[arguments.checkpoint]
    device = "mps" if torch.backends.mps.is_available() else "cpu"

    print("FLANEC PROTOTYPE — NOT PART OF THE TEXTIFY APP")
    print(f"checkpoint: {arguments.checkpoint}")
    print(f"repo_id: {checkpoint.repo_id}")
    print(f"revision: {checkpoint.revision}")
    print(f"declared_download_bytes: {checkpoint.download_bytes}")
    print(f"device: {device}")
    print("generation: beam_search_3, max_new_tokens_128")

    download_started = time.perf_counter()
    model_path = snapshot_download(
        repo_id=checkpoint.repo_id,
        revision=checkpoint.revision,
        allow_patterns=MODEL_FILES,
        local_files_only=arguments.offline,
    )
    print(f"checkpoint_resolution_seconds: {time.perf_counter() - download_started:.3f}")

    load_started = time.perf_counter()
    tokenizer = AutoTokenizer.from_pretrained(model_path, local_files_only=True)
    model = AutoModelForSeq2SeqLM.from_pretrained(
        model_path,
        local_files_only=True,
    ).to(device).eval()
    synchronize(device)
    print(f"model_load_seconds: {time.perf_counter() - load_started:.3f}")

    if arguments.one_best:
        cases = (
            EvaluationCase(
                name="custom_one_best",
                hypotheses=repeated_one_best(arguments.one_best),
                expected=arguments.expected or arguments.one_best,
            ),
        )
    else:
        cases = BUILT_IN_CASES

    # MPS compiles lazily. Warm once so individual case timings are comparable.
    _, warmup_seconds = generate(model, tokenizer, device, BUILT_IN_CASES[0])
    print(f"warmup_seconds: {warmup_seconds:.3f}")

    passed = 0
    for case in cases:
        output, latency = generate(model, tokenizer, device, case)
        print_case(case, output, latency)
        passed += int(output == case.expected)

    print("\nSUMMARY")
    print(f"passed: {passed}")
    print(f"total: {len(cases)}")
    print(f"pass_rate: {passed / len(cases):.3f}")


if __name__ == "__main__":
    main()
