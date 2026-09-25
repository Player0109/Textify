#!/usr/bin/env python3
"""Reproduce the 42-second Textify promo audio using synthetic service voices.

Requires curl, ffmpeg, Python 3, and NumPy. Use --service-guide for generation,
or --takes-dir to reuse six service-generated {id}.wav files without a request.
The private service URL is read at runtime and never placed in command arguments,
payload files, logs, or metadata. Music is synthesized locally without samples.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

import numpy as np

RATE = 48000
DURATION = 42.0
CUES = [
    {"id": "01_intro", "role": "narrator", "voice": "announcer_kenney_male", "start": 0.65, "deadline": 6.0, "text": "An email to finish. A document to shape. Start with what you want to say."},
    {"id": "02_email", "role": "dictation", "voice": "announcer_kenney_female", "start": 6.15, "deadline": 9.6, "text": "Hi Maya, I have added my comments to the draft."},
    {"id": "03_workflow", "role": "narrator", "voice": "announcer_kenney_male", "start": 12.15, "deadline": 19.5, "text": "With Textify, hold your shortcut, speak, and release. Your words arrive at the cursor, ready to edit."},
    {"id": "04_document", "role": "dictation", "voice": "announcer_kenney_female", "start": 20.15, "deadline": 23.3, "text": "The next step is to review the proposal together."},
    {"id": "05_privacy", "role": "narrator", "voice": "announcer_kenney_male", "start": 26.6, "deadline": 34.5, "text": "Speech recognition happens on your device. No account. No speech upload."},
    {"id": "06_outro", "role": "narrator", "voice": "announcer_kenney_male", "start": 36.4, "deadline": 40.5, "text": "Textify. Your voice, in your writing."},
]


def service_url(guide: Path) -> str:
    try:
        match = re.search(r"https://[^\s`]+/k/[^\s`]+", guide.read_text())
    except (OSError, UnicodeError):
        raise RuntimeError("Could not read the private service guide.") from None
    if not match:
        raise RuntimeError("The private service guide has no matching service URL.")
    return match.group(0).rstrip("/")


def service_request(base: str, endpoint: str, payload: dict | None = None) -> bytes:
    # curl receives the credential-bearing URL only through its stdin config.
    config = [
        f"url = {json.dumps(base + endpoint)}", "silent", "location",
        'proto = "=https"', 'proto-redir = "=https"', "max-time = 600",
        'write-out = "\\n%{http_code}"',
    ]
    if payload is not None:
        config += ['header = "Content-Type: application/json"', f"data = {json.dumps(json.dumps(payload))}"]
    request = ("\n".join(config) + "\n").encode()
    for attempt in range(2):
        try:
            response = subprocess.run(["curl", "--config", "-"], input=request, capture_output=True, timeout=605)
        except subprocess.TimeoutExpired:
            if attempt == 0:
                continue
            raise RuntimeError("The speech service connection timed out.") from None
        except OSError:
            raise RuntimeError("Could not run curl for the speech service.") from None
        body, _, status_bytes = response.stdout.rpartition(b"\n")
        status = int(status_bytes) if status_bytes.isdigit() else 0
        connection_error = response.returncode in {5, 6, 7, 28, 52, 55, 56}
        if attempt == 0 and (connection_error or 500 <= status <= 599):
            continue
        if response.returncode != 0:
            raise RuntimeError(f"Speech service transport failed (curl code {response.returncode}).")
        if not 200 <= status <= 299:
            raise RuntimeError(f"Speech service request failed (HTTP {status}).")
        return body
    raise RuntimeError("Speech service request failed.")


def confirm_voices(base: str) -> None:
    try:
        inventory = json.loads(service_request(base, "/v1/voices"))
        available = {row["name"] for row in inventory["voices"]}
    except (ValueError, UnicodeError, KeyError, TypeError):
        raise RuntimeError("The speech service returned an invalid voice inventory.") from None
    missing = {cue["voice"] for cue in CUES} - available
    if missing:
        raise RuntimeError("Selected speech voices are unavailable: " + ", ".join(sorted(missing)))


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=True, capture_output=True)


def read_mono(path: Path) -> np.ndarray:
    result = run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"])
    return np.frombuffer(result.stdout, dtype="<f4").copy()


def save_audio(path: Path, data: np.ndarray) -> None:
    channels = 1 if data.ndim == 1 else data.shape[1]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", str(channels), "-i", "-", "-c:a", "pcm_s24le", str(path)], input=np.asarray(data, dtype="<f4").tobytes(), check=True)


def loudness(path: Path, target: float, peak: float) -> dict:
    result = run(["ffmpeg", "-hide_banner", "-i", str(path), "-af", f"loudnorm=I={target}:TP={peak}:LRA=7:print_format=json", "-f", "null", "-"])
    return json.loads(re.findall(r"\{[^{}]+\}", result.stderr.decode())[-1])


def normalize(source: Path, destination: Path, target: float, peak: float) -> dict:
    measured = loudness(source, target, peak)
    filt = (
        f"loudnorm=I={target}:TP={peak}:LRA=7:"
        f"measured_I={measured['input_i']}:measured_TP={measured['input_tp']}:"
        f"measured_LRA={measured['input_lra']}:measured_thresh={measured['input_thresh']}:"
        f"offset={measured['target_offset']}:linear=true:print_format=json"
    )
    run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-af", filt, "-ar", str(RATE), "-c:a", "pcm_s24le", str(destination)])
    return measured


def midi(number: int) -> float:
    return 440 * 2 ** ((number - 69) / 12)


def music() -> np.ndarray:
    """Original D-major composition: Dmaj9, Bm7, Gmaj7, Aadd9, D/F#, Dmaj9."""
    result = np.zeros((round(DURATION * RATE), 2), dtype=np.float64)
    chords = [(50, 54, 57, 61, 64), (47, 54, 57, 62), (43, 50, 54, 59), (45, 52, 57, 59, 62), (42, 50, 57, 61), (50, 54, 57, 61, 64)]
    for index, notes in enumerate(chords):
        start = index * 7.0
        length = min(10.0, DURATION - start)
        t = np.arange(round(length * RATE)) / RATE
        envelope = np.minimum(t / 1.8, 1.0) * np.minimum((length - t) / 3.4, 1.0)
        envelope = np.sin(np.clip(envelope, 0, 1) * np.pi / 2) ** 2
        signal = np.zeros((len(t), 2))
        for number in notes:
            for channel, cents in enumerate((-3.0, 3.0)):
                frequency = midi(number) * 2 ** (cents / 1200)
                phase = 2 * np.pi * frequency * t
                tone = np.sin(phase) + 0.16 * np.sin(phase * 2) + 0.04 * np.sin(phase * 3)
                signal[:, channel] += tone * envelope * (1 + 0.035 * np.sin(2 * np.pi * 0.12 * t + index)) / len(notes)
        begin = round(start * RATE)
        result[begin:begin + len(t)] += signal * 0.68

    # Sparse, synthesized felt-piano notes. No recorded or sampled instrument.
    notes = [(1.8, 62), (4.3, 69), (8.6, 66), (11.2, 74), (15.8, 67), (18.5, 71), (22.4, 64), (25.3, 69), (29.1, 66), (32.3, 73), (36.6, 69), (39.0, 74)]
    for index, (start, number) in enumerate(notes):
        length = min(4.0, DURATION - start)
        t = np.arange(round(length * RATE)) / RATE
        envelope = (1 - np.exp(-t / 0.018)) * np.exp(-t / 1.15)
        frequency = midi(number)
        signal = envelope * (np.sin(2 * np.pi * frequency * t) + 0.23 * np.exp(-t / 0.42) * np.sin(2 * np.pi * frequency * 2.002 * t) + 0.07 * np.exp(-t / 0.23) * np.sin(2 * np.pi * frequency * 3.004 * t))
        pan = -0.2 if index % 2 == 0 else 0.2
        begin = round(start * RATE)
        stereo = np.column_stack((signal * math.sqrt((1 - pan) / 2), signal * math.sqrt((1 + pan) / 2))) * 0.28
        result[begin:begin + len(t)] += stereo

    dry = result.copy()
    for delay, amount in ((0.109, 0.09), (0.237, 0.05), (0.401, 0.025)):
        n = round(delay * RATE)
        result[n:] += dry[:-n, ::-1] * amount
    clock = np.arange(len(result)) / RATE
    envelope = np.sin(np.minimum(clock / 1.4, 1) * np.pi / 2) ** 2
    envelope *= np.sin(np.clip((DURATION - clock) / 2.1, 0, 1) * np.pi / 2) ** 2
    result *= envelope[:, None]
    result *= 10 ** (-20.0 / 20) / np.max(np.abs(result))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service-guide", type=Path, help="Private guide containing the service base URL; only used for generation")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--takes-dir", type=Path, help="Reuse service-generated {id}.wav takes without network requests")
    args = parser.parse_args()
    if args.takes_dir is None and args.service_guide is None:
        parser.error("--service-guide is required unless --takes-dir is supplied")
    output = args.output_dir.resolve()
    segments = output / "segments"
    if args.takes_dir is not None and args.takes_dir.resolve() == segments:
        parser.error("--takes-dir must differ from the output segments directory")
    segments.mkdir(parents=True, exist_ok=True)
    base = None
    if args.takes_dir is None:
        base = service_url(args.service_guide)
        confirm_voices(base)
    voice_mix = np.zeros(round(DURATION * RATE), dtype=np.float64)
    timings = []
    for cue in CUES:
        raw = segments / f"{cue['id']}-raw.wav"
        trimmed = segments / f"{cue['id']}-trimmed.wav"
        final = segments / f"{cue['id']}.wav"
        if args.takes_dir is not None:
            shutil.copyfile(args.takes_dir / f"{cue['id']}.wav", raw)
        else:
            raw.write_bytes(service_request(base, "/v1/tts", {"text": cue["text"], "voice": cue["voice"], "language": "English", "format": "wav"}))
        samples = read_mono(raw)
        raw_duration = len(samples) / RATE
        # Preserve a short natural breath margin while removing export padding.
        active = np.flatnonzero(np.abs(samples) > 10 ** (-48 / 20))
        if len(active) == 0:
            raise RuntimeError(f"No speech rendered for {cue['id']}")
        samples = samples[max(0, active[0] - round(0.025 * RATE)):min(len(samples), active[-1] + round(0.085 * RATE))]
        fade = min(round(0.008 * RATE), len(samples) // 2)
        samples[:fade] *= np.linspace(0, 1, fade)
        samples[-fade:] *= np.linspace(1, 0, fade)
        save_audio(trimmed, samples)
        trimmed_duration = len(samples) / RATE
        available = cue["deadline"] - cue["start"]
        tempo = 1.0
        ready = trimmed
        if trimmed_duration >= available:
            tempo = trimmed_duration / (available - 0.04)
            if tempo > 1.18:
                raise RuntimeError(f"Cue {cue['id']} needs {tempo:.3f}x tempo; maximum is 1.18x. Supply a shorter take or revise the script.")
            ready = segments / f"{cue['id']}-paced.wav"
            run(["ffmpeg", "-v", "error", "-y", "-i", str(trimmed), "-af", f"atempo={tempo:.9f}", "-ar", str(RATE), "-c:a", "pcm_s24le", str(ready)])
        normalize(ready, final, -18.0, -3.5)
        samples = read_mono(final)
        duration = len(samples) / RATE
        if cue["start"] + duration >= cue["deadline"]:
            raise RuntimeError(f"Cue {cue['id']} overruns: {duration:.3f}s, available {available:.3f}s. Supply a shorter take; no words were cut.")
        begin = round(cue["start"] * RATE)
        voice_mix[begin:begin + len(samples)] += samples
        row = {**cue, "raw_duration": round(raw_duration, 6), "trimmed_duration": round(trimmed_duration, 6), "duration": round(duration, 6), "end": round(cue["start"] + duration, 6), "tempo": round(tempo, 9), "file": str(final.relative_to(output)), "raw_file": str(raw.relative_to(output)), "synthetic_voice": True, "voice_source": "service_saved_preset"}
        timings.append(row)
        print(f"{cue['id']}: {cue['start']:.3f}–{cue['start'] + duration:.3f} seconds ({duration:.3f}s), {cue['voice']}", flush=True)

    bed = music()
    save_audio(output / "music.wav", bed)
    clock = np.arange(len(bed)) / RATE
    duck = np.ones(len(bed))
    for cue in timings:
        attack = np.clip((clock - (cue["start"] - 0.24)) / 0.24, 0, 1)
        release = np.clip((cue["end"] + 0.6 - clock) / 0.6, 0, 1)
        weight = np.minimum(attack, release)
        duck = np.minimum(duck, 10 ** ((-10.0 * weight) / 20))
    ducked = bed * duck[:, None]
    save_audio(output / "music-ducked.wav", ducked)
    save_audio(output / "voiceover.wav", np.column_stack((voice_mix, voice_mix)))
    save_audio(output / "mix-premaster.wav", ducked + voice_mix[:, None])
    normalize(output / "mix-premaster.wav", output / "finalmix.wav", -16.0, -1.7)
    check = loudness(output / "finalmix.wav", -16.0, -1.6)
    (output / "loudness.json").write_text(json.dumps(check, indent=2) + "\n")
    if abs(float(check["input_i"]) + 16) > 0.5 or float(check["input_tp"]) > -1.6:
        raise RuntimeError(f"Final loudness outside requested limits: {check}")
    metadata = {"duration": DURATION, "sample_rate": RATE, "channels": 2, "pcm_bits": 24, "voices": "Speech service saved preset voices; synthetic speech", "input_mode": "reused_takes" if args.takes_dir is not None else "service_generation", "music": "Original programmatic D-major ambient pad and synthesized piano; no third-party samples or stock recording", "disclosure": "Synthetic voiceover and dictation examples; illustrative timing, not a recognition-speed measurement", "segments": timings, "final_loudness": check}
    (output / "timing.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"final_loudness": check, "finalmix": str(output / "finalmix.wav")}, indent=2))


if __name__ == "__main__":
    main()
