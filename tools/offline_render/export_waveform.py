#!/usr/bin/env python3
"""
Export a signed mono waveform at a low sample rate to a compact binary.
- Input: MP3/WAV
- Output: waveform_2048.f32 (float32 little-endian), waveform_2048.json
"""
import argparse
import json
import os
from typing import Tuple

import librosa
import numpy as np


def _load_audio(path: str, sr_in: int) -> Tuple[np.ndarray, int]:
    y, sr = librosa.load(path, sr=sr_in, mono=True)
    y = y / (np.max(np.abs(y)) + 1e-9)
    return y, sr


def main() -> None:
    parser = argparse.ArgumentParser(description="Export a compact downsampled waveform for offline rendering")
    parser.add_argument("audio", help="Input audio file")
    parser.add_argument("--sr_in", type=int, default=48000, help="Resample the source to this rate before processing")
    parser.add_argument("--sr_out", type=int, default=2048, help="Output sample rate for the compact waveform")
    parser.add_argument(
        "--out_base",
        default="tools/offline_render/waveform_2048",
        help="Base path for output files (without extension)",
    )
    args = parser.parse_args()

    y, sr_in = _load_audio(args.audio, args.sr_in)
    y_ds = librosa.resample(y, orig_sr=sr_in, target_sr=args.sr_out, res_type="polyphase").astype(np.float32)

    base = args.out_base
    os.makedirs(os.path.dirname(base) or ".", exist_ok=True)
    bin_path = base + ".f32"
    meta_path = base + ".json"

    with open(bin_path, "wb") as f:
        f.write(y_ds.tobytes())

    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump({"sample_rate": args.sr_out, "length": int(y_ds.shape[0])}, f)

    print(f"wrote {bin_path} ({y_ds.shape[0]} samples), meta: {meta_path}")


if __name__ == "__main__":
    main()
