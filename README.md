# Audio Shader Offline Renderer

The Godot scene included in this project can be rendered offline with `godot4 --headless` and the `scripts/ExportRenderer.gd` script. The options below highlight the parameters that control the render window.

## Time window arguments

| Flag | Format | Description |
| --- | --- | --- |
| `--start <seconds>` | `1042.5` | Begin rendering at an absolute timestamp measured in seconds. Fractional seconds are supported. |
| `--start-time <timestamp>` | `13:23`, `1:02:03.5` | Begin rendering at a timestamp expressed in `MM:SS` or `HH:MM:SS` (fractional seconds are allowed in the seconds component). Use this when providing minute/second style offsets. |
| `--duration <seconds_or_timestamp>` | `24`, `00:24`, `0:00:24` | Render for the specified span. Accepts either seconds or timestamp notation. |

The legacy `--timestamp` flag has been removed in favour of the clearer options above.

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

## Tracklist interaction

When a tracklist is supplied, the renderer will automatically look up the entry that spans the requested start timestamp so that the correct shader and parameter overrides are applied. `--start` and `--start-time` are absolute offsets within the supplied tracklist and can be used with or without `--track`.

* Use `--tracklist <path>` on its own to respect the timeline embedded in the file.
* Add `--start` or `--start-time` to begin rendering mid-track; the renderer will seek to that absolute time.
* Provide `--track <index>` to force a specific entry when you want to ignore timestamps; the renderer will still honour a start override if one is provided.

The CLI log now reports which tracklist entry is active and the corresponding time window so the relationship between these flags is explicit.

Tracklist `set=` payloads accept an optional `events` array when you need to change shader uniforms mid-track. Each entry contains a timestamp (`t`) expressed as `M:SS`, `H:MM:SS`, or raw seconds along with a nested `set` dictionary describing the override to apply once that playhead time is reached. For example:

```text
0:00 Cosmic Gateways | shader=ARC_STORM | set={
  "base_tint": [0.25, 0.55, 1.30],
  "glow": 1.35,
  "events": [
    { "t": "01:30", "set": { "base_tint": [0.65, 0.20, 0.95] } },
    { "t": "02:40", "set": { "base_tint": [1.10, 1.10, 1.10], "glow": 1.45 } }
  ]
}
```

When the playhead crosses 01:30 the `base_tint` uniform updates to `[0.65, 0.20, 0.95]`. At 02:40 both `base_tint` and `glow` are set to their new values. Event timestamps are relative to the cue's start time by default; set `"absolute": true` on an event when you need to schedule against the full tracklist timeline.
