# Offline Rendering Pipeline

These helper scripts turn a Godot visualizer scene into a deterministic offline renderer.

## 1. Generate feature tracks

```
python tools/offline_render/feature_extract.py path\to\track.mp3 --fps 60 --sr 48000 --out tools/offline_render/features.csv
```

This produces:

* `features.csv` – per-frame values (level, kick, coarse spectrum bands).
* `features.duration.txt` – floating-point seconds used to determine how many frames to render.

## 2. Export a compact waveform texture (optional but recommended)

```
python tools/offline_render/export_waveform.py path\to\track.mp3 --out_base tools/offline_render/waveform_2048
```

This saves a little-endian `waveform_2048.f32` with mono samples and a matching metadata JSON file. The offline renderer feeds this into shaders that expect the live waveform capture texture.

## 3. Render frames headlessly

```
Godot_v4.4-stable_win64.exe --headless --path . ^
  --script scripts/ExportRenderer.gd ^
  --scene scenes/AudioViz.tscn ^
  --features tools/offline_render/features.csv ^
  --waveform tools/offline_render/waveform_2048 ^
  --tracklist tracklist-vol1.txt ^
  --track 1 ^
  --no-overlay ^
  --fps 60 --w 1920 --h 1080 ^
  --out export/frames --jpg 1 --quality 0.9
```

`--tracklist` points to a plain-text playlist (see the `tracklist-vol*.txt` samples). Use `--track` to select the 1-based entry to render. Omit `--track` to keep the scene's default configuration while still letting the renderer resolve resources from the provided tracklist.

`--no-overlay` disables the on-screen overlay in headless exports. You can also pass `--overlay=0` or `--overlay=1` to set it explicitly.

The renderer writes one numbered frame per timestep. Combine them with FFmpeg and mux in the original audio:

```
ffmpeg -r 60 -i export/frames/%06d.jpg -i path\to\track.mp3 \
  -c:v libx264 -pix_fmt yuv420p -c:a copy final_video.mp4
```

All parameters can be adjusted to taste.
