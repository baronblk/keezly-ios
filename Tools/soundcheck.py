#!/usr/bin/env python3
"""Measures Keezly's sound set.

What a machine can check about a sound, it checks here: level, offset,
brightness, and whether the thing decays like something that was struck.

What a machine cannot check is whether it sounds good. That needs ears, and
the release checklist says so rather than pretending otherwise.
"""

import cmath
import math
import sys
import wave
from pathlib import Path

RATE = 44_100


def read(path):
    with wave.open(str(path), "rb") as handle:
        frames = handle.readframes(handle.getnframes())
        rate = handle.getframerate()
    samples = []
    for index in range(0, len(frames), 2):
        value = int.from_bytes(frames[index:index + 2], "little", signed=True)
        samples.append(value / 32_768)
    return samples, rate


def fft(values):
    """Iterative radix-2 FFT, enough for a spectral centroid."""
    size = len(values)
    if size == 1:
        return values
    even = fft(values[0::2])
    odd = fft(values[1::2])
    out = [0j] * size
    for k in range(size // 2):
        twiddle = cmath.exp(-2j * math.pi * k / size) * odd[k]
        out[k] = even[k] + twiddle
        out[k + size // 2] = even[k] - twiddle
    return out


def centroid(samples, rate):
    """Where the energy sits, in hertz. Paper is bright; wood is not."""
    size = 4096
    window = samples[:size] + [0.0] * max(0, size - len(samples))
    # Hann, so the transient does not smear across the whole spectrum.
    windowed = [
        value * 0.5 * (1 - math.cos(2 * math.pi * i / (size - 1)))
        for i, value in enumerate(window)
    ]
    spectrum = fft([complex(value) for value in windowed])[: size // 2]
    magnitudes = [abs(value) for value in spectrum]
    total = sum(magnitudes)
    if total == 0:
        return 0.0
    weighted = sum(magnitude * (index * rate / size) for index, magnitude in enumerate(magnitudes))
    return weighted / total


def rms(values):
    if not values:
        return 0.0
    return math.sqrt(sum(value * value for value in values) / len(values))


def main():
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else "build/sounds")
    files = sorted(folder.glob("*.wav"))
    if not files:
        print(f"No sounds in {folder}")
        return 1

    print(f"{'cue':10} {'secs':>5} {'peak dB':>8} {'rms dB':>7} {'dc':>8} {'centroid':>9} {'decay':>7}")
    problems = []
    for path in files:
        samples, rate = read(path)
        peak = max((abs(value) for value in samples), default=0.0)
        offset = sum(samples) / len(samples)
        head = rms(samples[: len(samples) // 5])
        tail = rms(samples[-len(samples) // 5:])
        decay = head / tail if tail > 0 else float("inf")
        bright = centroid(samples, rate)

        print(
            f"{path.stem:10} {len(samples) / rate:5.2f} "
            f"{20 * math.log10(peak) if peak else -99:8.1f} "
            f"{20 * math.log10(rms(samples)) if rms(samples) else -99:7.1f} "
            f"{offset:8.5f} {bright:8.0f}Hz {decay:7.1f}"
        )

        if peak >= 0.999:
            problems.append(f"{path.stem}: clipping")
        if abs(offset) > 0.002:
            problems.append(f"{path.stem}: DC offset {offset:.4f}")
        if decay < 3:
            problems.append(f"{path.stem}: does not decay — it sustains, which nothing struck does")
        if len(samples) / rate > 2.0:
            problems.append(f"{path.stem}: {len(samples) / rate:.1f}s is too long for a cue")

    print()
    if problems:
        for problem in problems:
            print(f"  PROBLEM  {problem}")
        return 1
    print("Every cue: no clipping, no offset, decays like something struck, short enough to hear twice.")
    print("What this cannot tell you is whether they sound good. That needs ears.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
