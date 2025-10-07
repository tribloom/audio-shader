#!/usr/bin/env python3
"""
Per-frame audio features for deterministic shader rendering.

Usage:
  python tools/offline_render/feature_extract.py path/to/track.mp3 --fps 60 --sr 48000 --out tools/offline_render/features.csv
"""
import argparse
import csv
import os
from dataclasses import dataclass
from typing import List, Tuple

import librosa
import numpy as np


@dataclass
class FeatureFrame:
    frame: int
    time: float
    level: float
    kick: float
    bands: List[float]


# Percentile-based normalization keeps outliers from dominating the range
# while maintaining deterministic behaviour for identical inputs.
def _norm01(x: np.ndarray) -> np.ndarray:
    x = x.astype(np.float64)
    mn, mx = np.percentile(x, 5), np.percentile(x, 95)
    return np.clip((x - mn) / (mx - mn + 1e-9), 0.0, 1.0)


def _compute_features(
    audio_path: str,
    fps: int,
    sr: int,
    mel_bands: int,
    bands_out: int,
) -> Tuple[List[FeatureFrame], float]:
    y, sr_loaded = librosa.load(audio_path, sr=sr, mono=True)
    hop = int(sr_loaded / fps)
    win = 2048

    n_frames = int(np.ceil(len(y) / hop))

    rms = librosa.feature.rms(y=y, frame_length=win, hop_length=hop, center=True)[0][:n_frames]
    onset_env = librosa.onset.onset_strength(y=y, sr=sr_loaded, hop_length=hop)[:n_frames]

    mel = librosa.feature.melspectrogram(
        y=y,
        sr=sr_loaded,
        n_fft=win,
        hop_length=hop,
        n_mels=mel_bands,
        power=2.0,
    )
    mel_db = librosa.power_to_db(mel + 1e-12)[:, :n_frames]
    splits = np.array_split(mel_db, bands_out, axis=0)
    bands = np.stack([np.mean(b, axis=0) for b in splits], axis=1)

    level = _norm01(rms)
    kick = _norm01(onset_env)
    bands01 = np.stack([_norm01(bands[:, i]) for i in range(bands.shape[1])], axis=1)

    frames: List[FeatureFrame] = []
    time = 0.0
    for i in range(n_frames):
        row = FeatureFrame(
            frame=i,
            time=time,
            level=float(level[i] if i < len(level) else 0.0),
            kick=float(kick[i] if i < len(kick) else 0.0),
            bands=[float(bands01[i, j] if i < bands01.shape[0] else 0.0) for j in range(bands01.shape[1])],
        )
        frames.append(row)
        time += 1.0 / fps
    duration_seconds = float(len(y)) / float(sr_loaded)
    return frames, duration_seconds


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract deterministic per-frame audio features.")
    parser.add_argument("audio", help="Input audio file (MP3/WAV/etc)")
    parser.add_argument("--fps", type=int, default=60, help="Target frames-per-second")
    parser.add_argument("--sr", type=int, default=48000, help="Resample rate before analysis")
    parser.add_argument("--mel_bands", type=int, default=24, help="Number of Mel bins to build the coarse spectrum")
    parser.add_argument("--bands_out", type=int, default=6, help="Number of coarse bands written to the CSV")
    parser.add_argument(
        "--out",
        default="tools/offline_render/features.csv",
        help="Destination CSV path",
    )
    args = parser.parse_args()

    frames, duration_seconds = _compute_features(
        args.audio, args.fps, args.sr, args.mel_bands, args.bands_out
    )

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        header = ["frame", "t", "level", "kick"] + [f"s{i}" for i in range(args.bands_out)]
        writer.writerow(header)
        for frame in frames:
            row = [frame.frame, f"{frame.time:.6f}", f"{frame.level:.6f}", f"{frame.kick:.6f}"]
            row.extend(f"{b:.6f}" for b in frame.bands)
            writer.writerow(row)

    duration = duration_seconds
    duration_path = os.path.splitext(args.out)[0] + ".duration.txt"
    with open(duration_path, "w", encoding="utf-8") as f:
        f.write(f"{duration:.6f}")

    print(
        f"Done. Frames: {len(frames)}, duration: {duration:.2f}s, csv: {args.out}",
    )


if __name__ == "__main__":
    main()
