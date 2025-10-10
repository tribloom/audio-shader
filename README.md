# Audio Shader Offline Renderer

The Godot scene included in this project can be rendered offline with `godot4 --headless` and the `scripts/ExportRenderer.gd` script. The options below highlight the parameters that control the render window.

## Time window arguments

| Flag | Format | Description |
| --- | --- | --- |
| `--start <seconds>` | `1042.5` | Begin rendering at an absolute timestamp measured in seconds. Fractional seconds are supported. |
| `--start-time <timestamp>` | `13:23`, `1:02:03.5` | Begin rendering at a timestamp expressed in `MM:SS` or `HH:MM:SS` (fractional seconds are allowed in the seconds component). Use this when providing minute/second style offsets. |
| `--duration <seconds_or_timestamp>` | `24`, `00:24`, `0:00:24` | Render for the specified span. Accepts either seconds or timestamp notation. |

Both `--start` and `--start-time` set the same underlying start override; `--start-time` exists to make minute/second style notation explicit. If a timestamp is accidentally provided to `--start`, it will still be parsed, but the renderer will emit a warning that suggests switching to `--start-time` for clarity.

## Example

```sh
godot4 --headless \
--path . \
--script scripts/ExportRenderer.gd \
--scene scenes/AudioViz.tscn \
--features tools/offline_render/features.csv \
--fps 60 --w 1920 --h 1080 \
--out export/frames \
--start-time 13:23 \
--duration 24
```

The example above renders 24 seconds of output starting at the 13 minute 23 second mark.
