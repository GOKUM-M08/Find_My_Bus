"""
generate_chimes.py

Generates 6 clean, pleasant 1-second chime WAV files into
flutter_app/android/app/src/main/res/raw/ to serve as placeholder notification sounds.
Parents and developers can later replace these with recorded voice clips
(e.g., recorded in Tamil and English) by dropping replacement .wav or .mp3
files with the exact same filenames.
"""

import os
import wave
import math
import struct

CHIME_FILES = [
    ("bus_started_ta.wav", 587.33),   # D5
    ("bus_near_ta.wav", 659.25),      # E5
    ("bus_arrived_ta.wav", 880.00),   # A5
    ("bus_started_en.wav", 587.33),   # D5
    ("bus_near_en.wav", 659.25),      # E5
    ("bus_arrived_en.wav", 880.00),   # A5
]

OUTPUT_DIR = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "flutter_app",
        "android",
        "app",
        "src",
        "main",
        "res",
        "raw",
    )
)

SAMPLE_RATE = 44100
DURATION_SEC = 1.0


def generate_chime_wav(filepath: str, freq: float):
    num_samples = int(SAMPLE_RATE * DURATION_SEC)
    with wave.open(filepath, "w") as wav_file:
        # 1 channel (mono), 2 bytes per sample (16-bit), 44100 Hz
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)

        for i in range(num_samples):
            t = float(i) / SAMPLE_RATE
            # Pleasant bell-like decay envelope
            envelope = math.exp(-3.5 * t)
            # Harmonic chime: fundamental + octave
            sample = 0.7 * math.sin(2.0 * math.pi * freq * t) + 0.3 * math.sin(4.0 * math.pi * freq * t)
            sample_val = int(sample * envelope * 24000.0)
            # Clamp to 16-bit signed int
            sample_val = max(-32768, min(32767, sample_val))
            wav_file.writeframes(struct.pack("<h", sample_val))


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Generating chime sound assets in: {OUTPUT_DIR}")
    for filename, freq in CHIME_FILES:
        target = os.path.join(OUTPUT_DIR, filename)
        generate_chime_wav(target, freq)
        print(f"  Created: {filename} ({os.path.getsize(target)} bytes)")
    print("Done!")


if __name__ == "__main__":
    main()
