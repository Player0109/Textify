#!/usr/bin/env python3
"""Reproduce the 42-second Textify promo audio using installed macOS voices.

Requires macOS `say`, ffmpeg, ffprobe, Python 3, and NumPy. No network access,
downloaded music, sampled instruments, or external speech services are used.
Run this file with a Python interpreter that has NumPy installed.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import re
import subprocess

import numpy as np

ROOT = Path(__file__).resolve().parent
RATE = 48000
DURATION = 42.0
CUES = [
    # say's nominal rate is voice-dependent; these are paced from rendered files.
    {"id": "01_intro", "role": "narrator", "voice": "Aman (English (India))", "start": 0.65, "deadline": 6.0, "rate": 128, "text": "An email to finish. A document to shape. Start with what you want to say."},
    {"id": "02_email", "role": "dictation", "voice": "Samantha", "start": 6.15, "deadline": 10.3, "rate": 140, "text": "Hi Maya, I have added my comments to the draft."},
    {"id": "03_workflow", "role": "narrator", "voice": "Aman (English (India))", "start": 12.15, "deadline": 19.5, "rate": 176, "text": "With Textify, hold your shortcut, speak, and release. Your words arrive at the cursor, ready to edit."},
    {"id": "04_document", "role": "dictation", "voice": "Samantha", "start": 20.15, "deadline": 24.3, "rate": 140, "text": "The next step is to review the proposal together."},
    {"id": "05_privacy", "role": "narrator", "voice": "Aman (English (India))", "start": 26.6, "deadline": 34.5, "rate": 174, "text": "Speech recognition happens on your device. No account. No speech upload."},
    {"id": "06_outro", "role": "narrator", "voice": "Aman (English (India))", "start": 36.4, "deadline": 40.5, "rate": 174, "text": "Textify. Your voice, in your writing."},
]


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
    (ROOT / "segments").mkdir(parents=True, exist_ok=True)
    voice_mix = np.zeros(round(DURATION * RATE), dtype=np.float64)
    timings = []
    for cue in CUES:
        raw = ROOT / "segments" / f"{cue['id']}.aiff"
        trimmed = ROOT / "segments" / f"{cue['id']}-trimmed.wav"
        final = ROOT / "segments" / f"{cue['id']}.wav"
        run(["say", "-v", cue["voice"], "-r", str(cue["rate"]), "-o", str(raw), cue["text"]])
        samples = read_mono(raw)
        # Preserve a short natural breath margin while removing export padding.
        active = np.flatnonzero(np.abs(samples) > 10 ** (-48 / 20))
        if len(active) == 0:
            raise RuntimeError(f"No speech rendered for {cue['id']}")
        samples = samples[max(0, active[0] - round(0.025 * RATE)):min(len(samples), active[-1] + round(0.085 * RATE))]
        fade = min(round(0.008 * RATE), len(samples) // 2)
        samples[:fade] *= np.linspace(0, 1, fade)
        samples[-fade:] *= np.linspace(1, 0, fade)
        save_audio(trimmed, samples)
        normalize(trimmed, final, -18.0, -3.5)
        samples = read_mono(final)
        duration = len(samples) / RATE
        if cue["start"] + duration >= cue["deadline"]:
            raise RuntimeError(f"Cue {cue['id']} overruns: {duration:.3f}s, available {cue['deadline'] - cue['start']:.3f}s. Adjust this cue's say rate deliberately.")
        begin = round(cue["start"] * RATE)
        voice_mix[begin:begin + len(samples)] += samples
        row = {**cue, "duration": round(duration, 6), "end": round(cue["start"] + duration, 6), "file": str(final.relative_to(ROOT)), "synthetic_voice": True}
        timings.append(row)
        print(f"{cue['id']}: {cue['start']:.3f}–{cue['start'] + duration:.3f} seconds ({duration:.3f}s), {cue['voice']}", flush=True)

    bed = music()
    save_audio(ROOT / "music.wav", bed)
    clock = np.arange(len(bed)) / RATE
    duck = np.ones(len(bed))
    for cue in timings:
        attack = np.clip((clock - (cue["start"] - 0.24)) / 0.24, 0, 1)
        release = np.clip((cue["end"] + 0.6 - clock) / 0.6, 0, 1)
        weight = np.minimum(attack, release)
        duck = np.minimum(duck, 10 ** ((-10.0 * weight) / 20))
    ducked = bed * duck[:, None]
    save_audio(ROOT / "music-ducked.wav", ducked)
    save_audio(ROOT / "voiceover.wav", np.column_stack((voice_mix, voice_mix)))
    save_audio(ROOT / "mix-premaster.wav", ducked + voice_mix[:, None])
    normalize(ROOT / "mix-premaster.wav", ROOT / "finalmix.wav", -16.0, -1.6)
    check = loudness(ROOT / "finalmix.wav", -16.0, -1.5)
    (ROOT / "loudness.json").write_text(json.dumps(check, indent=2) + "\n")
    if abs(float(check["input_i"]) + 16) > 0.5 or float(check["input_tp"]) > -1.5:
        raise RuntimeError(f"Final loudness outside requested limits: {check}")
    metadata = {"duration": DURATION, "sample_rate": RATE, "channels": 2, "pcm_bits": 24, "voices": "macOS say, installed system voices; synthetic speech", "music": "Original programmatic D-major ambient pad and synthesized piano; no third-party samples or stock recording", "disclosure": "Synthetic voiceover and dictation examples; illustrative timing, not a recognition-speed measurement", "segments": timings, "final_loudness": check}
    (ROOT / "timing.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"final_loudness": check, "finalmix": str(ROOT / "finalmix.wav")}, indent=2))


if __name__ == "__main__":
    main()
