extends SceneTree
## Deterministic offline renderer (no live audio)
## Usage (Windows):
##   godot4 --headless --path . --script scripts/ExportRenderer.gd -- ^
##     --scene scenes/AudioViz.tscn ^
##     --features tools/offline_render/features.csv ^
##     --fps 60 --w 1920 --h 1080 ^
##     --out export/frames --jpg 1 --quality 0.9

var args = {}
var svp: SubViewport
var root_node: Node
var fps: int = 60
var width: int = 1920
var height: int = 1080
var out_dir: String = "export/frames"
var out_dir_fs: String = ""
var save_jpg: bool = false
var jpg_quality: float = 0.9
var duration_s: float = 0.0
var waveform_base: String = ""
var frame_post_draw_supported: bool = true
var overlay_enabled: bool = true

# Tracklist overrides for headless mode
var tracklist_path: String = ""
var track_index: int = 1
var track_index_specified: bool = false
var tracklist_inline: PackedStringArray = PackedStringArray()
var selected_track_entry: Dictionary = {}
var track_start_time: float = 0.0
var track_end_time: float = -1.0
var track_source_start_time: float = 0.0
var track_source_end_time: float = -1.0
var render_start_override: float = -1.0
var render_start_source: String = ""
var render_duration_override: float = -1.0
var render_start_time: float = -1.0
var render_end_time: float = -1.0

func _initialize() -> void:
	_parse_args()

	var display_driver := DisplayServer.get_name()
	var rendering_method := ""
	var adapter := ""
	var using_dummy_renderer := false
	if Engine.has_singleton("RenderingServer"):
		var rendering_server: Object = Engine.get_singleton("RenderingServer")
		if rendering_server and rendering_server.has_method("get_rendering_method"):
			rendering_method = str(rendering_server.call("get_rendering_method"))
		if rendering_server and rendering_server.has_method("get_rendering_device"):
			var device: Object = rendering_server.call("get_rendering_device")
			if device and device.has_method("get_device_name"):
				adapter = str(device.call("get_device_name"))
	if rendering_method == "":
		rendering_method = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	if rendering_method == "" or rendering_method == "dummy":
		using_dummy_renderer = true

	# Godot's headless display driver never emits frame_post_draw, so fall back to
	# advancing the scene manually in that environment.

	frame_post_draw_supported = display_driver != "headless"
	print("[ExportRenderer] Display driver: %s | Rendering method: %s | Adapter: %s" % [display_driver, rendering_method, adapter])
	if using_dummy_renderer:
		var msg := "[ExportRenderer] No usable renderer detected (display driver: %s, rendering method: %s). Run without --headless or supply --rendering-driver opengl3 / use the GL Compatibility renderer." % [display_driver, rendering_method]
		push_error(msg)
		print(msg)
		quit(1)
		return

	# Create an offscreen SubViewport to render into
	svp = SubViewport.new()
	svp.disable_3d = true
	svp.transparent_bg = false
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.size = Vector2i(width, height)
	# Add under the SceneTree's root
	root.add_child(svp)

	# Load your scene into the SubViewport
	var scene_path: String = args.get("scene", "scenes/AudioViz.tscn")
	root_node = load(scene_path).instantiate()
	_apply_tracklist_properties(root_node)
	_apply_overlay_preference(root_node)

	# Force offline mode before the node enters the scene tree so _ready() picks it up.
	if root_node.has_method("set_offline_mode"):
		root_node.call("set_offline_mode", true)
	if root_node.has_method("set_frame_post_draw_supported"):
		root_node.call("set_frame_post_draw_supported", frame_post_draw_supported)

	var features_path: String = args.get("features", "")
	var feature_window_start := 0.0
	var feature_window_end := -1.0
	if track_index_specified or render_start_override >= 0.0 or render_duration_override > 0.0:
		feature_window_start = max(track_source_start_time, 0.0)
		feature_window_end = track_source_end_time
	render_start_time = track_source_start_time
	render_end_time = track_source_end_time
	if features_path != "" and root_node.has_method("load_features_csv"):
		root_node.call("load_features_csv", features_path, feature_window_start, feature_window_end)
	var waveform_path: String = args.get("waveform", "")
	if waveform_path != "" and root_node.has_method("load_waveform_binary"):
		root_node.call("load_waveform_binary", waveform_path, feature_window_start, feature_window_end)

	svp.add_child(root_node)

	await root_node.ready
	if root_node.has_method("set_offline_mode"):
		root_node.call("set_offline_mode", true)
	if root_node.has_method("set_frame_post_draw_supported"):
		root_node.call("set_frame_post_draw_supported", frame_post_draw_supported)
	_apply_overlay_preference(root_node)
	_apply_selected_track_entry()

	# Apply settings that depend on the node being ready.
	if root_node.has_method("set_aspect"):
		root_node.call("set_aspect", float(width) / float(height))

	var track_duration_hint := -1.0
	if track_index_specified and track_source_end_time > track_source_start_time:
		track_duration_hint = track_source_end_time - track_source_start_time
	if track_duration_hint < 0.0 and track_index_specified and selected_track_entry.has("duration_hint"):
		var hint_val := float(selected_track_entry.get("duration_hint", -1.0))
		if hint_val > 0.0:
			track_duration_hint = hint_val

	duration_s = _infer_duration(features_path)
	var total_duration_s := duration_s
	var offline_dur := -1.0
	if root_node.has_method("get_offline_duration"):
		offline_dur = float(root_node.call("get_offline_duration"))
		if offline_dur > 0.0:
			duration_s = offline_dur
			total_duration_s = offline_dur
	if track_index_specified:
		var relative_duration := -1.0
		if offline_dur > 0.0:
			relative_duration = offline_dur
		elif track_duration_hint > 0.0:
			relative_duration = track_duration_hint
		elif total_duration_s > 0.0:
			relative_duration = total_duration_s

		track_start_time = 0.0
		track_end_time = -1.0
		if relative_duration > 0.0:
			track_end_time = relative_duration
		elif track_duration_hint > 0.0:
			track_end_time = track_duration_hint
		elif total_duration_s > 0.0:
			track_end_time = total_duration_s
		else:
			track_end_time = -1.0

		var stop_time := track_end_time
		if stop_time <= track_start_time and relative_duration > 0.0:
			stop_time = relative_duration
		elif stop_time <= track_start_time and track_duration_hint > 0.0:
			stop_time = track_duration_hint
		elif stop_time <= track_start_time and total_duration_s > 0.0:
			stop_time = total_duration_s
		elif stop_time <= track_start_time:
			stop_time = track_start_time
		if relative_duration > 0.0:
			stop_time = clamp(stop_time, track_start_time, relative_duration)
		elif track_duration_hint > 0.0:
			stop_time = clamp(stop_time, track_start_time, track_duration_hint)
		elif total_duration_s > 0.0:
			stop_time = clamp(stop_time, track_start_time, total_duration_s)
		track_end_time = stop_time
		if relative_duration > 0.0:
			duration_s = relative_duration
		else:
			duration_s = max(track_end_time - track_start_time, 0.0)
		total_duration_s = duration_s
	else:
		track_start_time = 0.0
		track_end_time = duration_s

	if render_start_override >= 0.0:
		track_source_start_time = render_start_override
		render_start_time = render_start_override
	elif track_source_start_time >= 0.0:
		render_start_time = track_source_start_time
	else:
		render_start_time = track_start_time

	if render_duration_override > 0.0:
		duration_s = render_duration_override
		track_end_time = track_start_time + render_duration_override
		track_source_end_time = track_source_start_time + render_duration_override
		render_end_time = track_source_end_time
	else:
		if track_source_end_time > track_source_start_time:
			render_end_time = track_source_end_time
			if track_index_specified:
				var span := track_source_end_time - track_source_start_time
				if span > 0.0:
					track_end_time = track_start_time + span
					duration_s = span
			else:
				duration_s = track_end_time
		elif duration_s > 0.0 and track_source_start_time >= 0.0:
			track_source_end_time = track_source_start_time + duration_s
			render_end_time = track_source_end_time
		else:
			render_end_time = -1.0

	total_duration_s = duration_s

	var has_track_window: bool = track_index_specified or render_start_override >= 0.0 or render_duration_override > 0.0
	if track_start_time > 0.0:
		has_track_window = true

	DirAccess.make_dir_recursive_absolute(out_dir_fs)

	# Deterministic frame loop
	var frames_total: int = int(ceil(duration_s * float(fps)))
	var using_offline_frames: bool = false
	var frame_start_idx: int = 0
	if root_node.has_method("get_offline_frame_count"):
		var offline_frames: int = int(root_node.call("get_offline_frame_count"))
		if offline_frames > 0:
			using_offline_frames = true
			if has_track_window:
				frame_start_idx = _find_frame_index_for_time(track_start_time, offline_frames)
				var target_end: float = track_end_time
				if target_end <= track_start_time:
					target_end = total_duration_s
				var found_end: int = offline_frames
				if target_end > track_start_time:
					found_end = _find_frame_index_for_time(target_end, offline_frames)
				var frame_end_idx: int = clampi(found_end, frame_start_idx, offline_frames)
				frames_total = max(0, frame_end_idx - frame_start_idx)
			else:
				frame_start_idx = 0
				frames_total = offline_frames

	if frames_total <= 0:
		push_warning("No frames to render (duration=%.3fs, fps=%d)." % [duration_s, fps])
		quit()
		return
	for local_frame in range(frames_total):
		var source_frame := local_frame
		if using_offline_frames:
			source_frame = frame_start_idx + local_frame
		var t := float(local_frame) / float(fps)
		if using_offline_frames:
			t = _get_time_for_frame_index(source_frame)
		else:
			if has_track_window:
				t = track_start_time + t
		var should_log_frame := (local_frame == 0 or local_frame % 3600 == 0)
		if !using_offline_frames:
			if root_node.has_method("get_offline_time_at_index"):
				var t_override = root_node.call("get_offline_time_at_index", local_frame)
				if typeof(t_override) == TYPE_FLOAT and t_override >= 0.0:
					t = t_override
			elif root_node.has_method("get_offline_time_for_frame"):
				var frame_time = root_node.call("get_offline_time_for_frame", local_frame)
				if typeof(frame_time) == TYPE_FLOAT and frame_time >= 0.0:
					t = frame_time
				if has_track_window and t < track_start_time:
					t = track_start_time

		if has_track_window and track_end_time > track_start_time and t >= track_end_time:
			break

		if root_node.has_method("set_playhead"):
			root_node.call("set_playhead", t)

		if should_log_frame:
			print("[ExportRenderer] Awaiting process_frame for frame %d/%d (t=%.3fs)" % [local_frame, frames_total, t])

		# Advance one engine frame, then wait for the render thread to flush
		await self.process_frame
		await _await_render_sync()

		if should_log_frame:
			print("[ExportRenderer] process_frame completed for frame %d/%d" % [local_frame, frames_total])

		var img := await _capture_subviewport_image()
		if img == null:
			return

		var ext := ("jpg" if save_jpg else "png")
		var filename := "%06d.%s" % [local_frame, ext]
		var path := out_dir_fs.path_join(filename)
		if save_jpg:
			img.save_jpg(path, int(round(jpg_quality * 100.0)))
		else:
			img.save_png(path)

		if should_log_frame:
			print("[ExportRenderer] Saved frame %d/%d -> %s" % [local_frame, frames_total, path])
	quit()


func _capture_subviewport_image() -> Image:
	var tex := svp.get_texture()
	if tex == null:
		push_error("SubViewport returned no texture. The renderer is likely running in dummy/headless mode. Remove --headless or force a rendering driver such as --rendering-driver opengl3.")
		quit(1)
		return null

	var img := tex.get_image()
	if img != null:
		return img

	var attempts := 0
	while attempts < 4:
		await _await_render_sync()
		img = tex.get_image()
		if img != null:
			return img
		attempts += 1

	push_error("Failed to fetch SubViewport image after waiting for the renderer. The renderer may be running in dummy/headless mode. Remove --headless or force a rendering driver such as --rendering-driver opengl3.")
	quit(1)
	return null

func _await_render_sync() -> void:
	if frame_post_draw_supported and Engine.has_singleton("RenderingServer") and RenderingServer.has_signal("frame_post_draw"):
		await RenderingServer.frame_post_draw
		return

	if Engine.has_singleton("RenderingServer"):
		var did_sync := false
		if RenderingServer.has_method("sync"):
			RenderingServer.call("sync")
			did_sync = true
		if RenderingServer.has_method("draw"):
			var frame_step := (1.0 / float(fps)) if fps > 0 else 0.0
			RenderingServer.call("draw", false, frame_step)
			return
		if did_sync:
			return

	await self.process_frame

func _parse_args() -> void:
	var raw := OS.get_cmdline_args()
	var pending_tracklist := ""
	var i := 0
	while i < raw.size():
		var current := raw[i]
		if !current.begins_with("--"):
			i += 1
			continue
		var key := current
		var value := ""
		var eq_idx := current.find("=")
		if eq_idx >= 0:
			key = current.substr(0, eq_idx)
			value = current.substr(eq_idx + 1)
		elif i + 1 < raw.size() and !raw[i + 1].begins_with("--"):
			i += 1
			value = raw[i]
		match key:
			"--scene":
				var scene_val := _sanitize_cli_path(value)
				if scene_val != "":
					args.scene = scene_val
			"--features":
				var features_val := _resolve_cli_input_path(_sanitize_cli_path(value))
				if features_val != "":
					args.features = features_val
			"--fps":
				var fps_val := _sanitize_cli_path(value)
				if fps_val != "":
					fps = int(fps_val)
			"--w":
				var width_val := _sanitize_cli_path(value)
				if width_val != "":
					width = int(width_val)
			"--h":
				var height_val := _sanitize_cli_path(value)
				if height_val != "":
					height = int(height_val)
			"--out":
				var out_val := _sanitize_cli_path(value)
				if out_val != "":
					out_dir = out_val
			"--jpg":
				var jpg_val := _sanitize_cli_path(value)
				if jpg_val == "":
					save_jpg = true
				else:
					save_jpg = int(jpg_val) != 0
			"--quality":
				var q_val := _sanitize_cli_path(value)
				if q_val != "":
					jpg_quality = float(q_val)
			"--waveform":
				var wave_val := _resolve_cli_input_path(_sanitize_cli_path(value))
				if wave_val != "":
					waveform_base = wave_val
			"--tracklist":
				var tracklist_val := _resolve_cli_input_path(_sanitize_cli_path(value))
				if tracklist_val != "":
					pending_tracklist = tracklist_val
			"--track":
				var track_val := _sanitize_cli_path(value)
				if track_val != "":
					track_index = max(1, int(track_val))
					track_index_specified = true
			"--start":
				var start_val := _sanitize_cli_path(value)
				if start_val != "":
					var parsed_start := _parse_seconds_value(start_val)
					if parsed_start >= 0.0:
						render_start_override = parsed_start
						render_start_source = "--start (seconds)"
					else:
						var parsed_timestamp := _parse_timestamp_to_seconds(start_val)
						if parsed_timestamp >= 0.0:
							render_start_override = parsed_timestamp
							render_start_source = "--start (timestamp)"
							push_warning("--start-time should be used for timestamp values. Parsed %.3fs from '%s'." % [parsed_timestamp, start_val])
			"--start-time":
				var start_time_val := _sanitize_cli_path(value)
				if start_time_val != "":
					var parsed_start_time := _parse_timestamp_to_seconds(start_time_val)
					if parsed_start_time < 0.0:
						parsed_start_time = _parse_seconds_value(start_time_val)
					if parsed_start_time >= 0.0:
							render_start_override = parsed_start_time
							render_start_source = "--start-time"
			"--duration":
				var duration_val := _sanitize_cli_path(value)
				if duration_val != "":
					var parsed_duration := _parse_duration_to_seconds(duration_val)
					if parsed_duration > 0.0:
						render_duration_override = parsed_duration
			"--overlay":
				var overlay_val := _sanitize_cli_path(value)
				if overlay_val == "":
					overlay_enabled = true
				else:
					var normalized := overlay_val.to_lower()
					if normalized in ["1", "true", "yes", "on"]:
						overlay_enabled = true
					elif normalized in ["0", "false", "no", "off"]:
						overlay_enabled = false
			"--no-overlay":
				overlay_enabled = false
		i += 1
	if waveform_base != "":
		args.waveform = waveform_base
	out_dir_fs = _resolve_output_path(out_dir)
	if pending_tracklist != "":
		tracklist_path = pending_tracklist
		_prepare_tracklist_override()
	if render_start_override >= 0.0:
		track_source_start_time = render_start_override
	if render_duration_override > 0.0 and track_source_start_time >= 0.0:
		track_source_end_time = track_source_start_time + render_duration_override
	_log_parsed_configuration(raw)

func _infer_duration(features_path: String) -> float:
	if features_path == "":
		return 60.0
	var dur_txt := features_path.get_basename() + ".duration.txt"
	if FileAccess.file_exists(dur_txt):
		var f := FileAccess.open(dur_txt, FileAccess.READ)
		if f:
			var s := f.get_as_text()
			var val := s.to_float()
			if val > 0.0:
				return val
	# Fallback: count CSV rows (minus header) / fps
	var f2 := FileAccess.open(features_path, FileAccess.READ)
	if f2:
		var count := -1
		while not f2.eof_reached():
			f2.get_line()
			count += 1
		if count > 0:
			return float(count) / float(fps)
	return 60.0

func _sanitize_cli_path(raw: String) -> String:
	var trimmed := raw.strip_edges()
	if trimmed.length() >= 2:
			if (trimmed.begins_with("\"") and trimmed.ends_with("\"")) or (trimmed.begins_with("'") and trimmed.ends_with("'")):
					trimmed = trimmed.substr(1, trimmed.length() - 2)
	trimmed = trimmed.strip_edges()
	return trimmed.replace("\\", "/")

func _resolve_cli_input_path(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed == "":
		return trimmed

	if trimmed.is_absolute_path():
		return trimmed

	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
		return trimmed
	var res_candidate := "res://".path_join(trimmed)
	if FileAccess.file_exists(res_candidate):
		return res_candidate
	var project_root := ProjectSettings.globalize_path("res://")
	return project_root.path_join(trimmed)

func _resolve_output_path(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed == "":
		trimmed = "export/frames"
	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
		return ProjectSettings.globalize_path(trimmed)

	if trimmed.is_absolute_path():
		return trimmed

	var project_root := ProjectSettings.globalize_path("res://")
	return project_root.path_join(trimmed)

func _log_parsed_configuration(raw: PackedStringArray) -> void:
	var raw_line := "(none)"
	if raw.size() > 0:
		var builder := ""
		for idx in range(raw.size()):
			if idx > 0:
				builder += " "
			builder += raw[idx]
		raw_line = builder
	print("[ExportRenderer] Raw CLI args: %s" % raw_line)
	var summary := [
		["scene", args.get("scene", "scenes/AudioViz.tscn")],
		["features", args.get("features", "")],
		["waveform", args.get("waveform", "")],
		["fps", fps],
		["resolution", "%dx%d" % [width, height]],
		["save_jpg", save_jpg],
		["jpg_quality", jpg_quality],
		["out_dir", out_dir],
		["out_dir_fs", out_dir_fs],
		["overlay_enabled", overlay_enabled],
		["tracklist_path", tracklist_path],
		["track_index", track_index],
		["track_index_specified", track_index_specified],
		["tracklist_inline_size", tracklist_inline.size()],
		["track_start_time", track_start_time],
		["track_end_time", track_end_time],
			["track_source_start_time", track_source_start_time],
			["track_source_end_time", track_source_end_time],
			["render_start_override", render_start_override],
			["render_start_source", render_start_source],
			["render_duration_override", render_duration_override],
			["render_start_time", render_start_time],
			["render_end_time", render_end_time],
		]
	print("[ExportRenderer] Parsed configuration:")
	for item in summary:
		print("  %s: %s" % [item[0], item[1]])

func _prepare_tracklist_override() -> void:
	selected_track_entry = {}
	tracklist_inline = PackedStringArray()
	track_start_time = 0.0
	track_end_time = -1.0
	track_source_start_time = 0.0
	track_source_end_time = -1.0
	if tracklist_path == "":
		return

	var lines := _read_tracklist_lines(tracklist_path)
	if lines.is_empty():
		push_warning("Tracklist not found: %s" % tracklist_path)
		return

	var entries := _parse_tracklist_entries(lines)
	if entries.is_empty():
		push_warning("Tracklist has no valid entries: %s" % tracklist_path)
		return

	var idx = clamp(track_index - 1, 0, entries.size() - 1)
	if render_start_override >= 0.0:
		var override_idx := _find_tracklist_entry_for_time(entries, render_start_override)
		if override_idx >= 0:
			idx = override_idx
		else:
			push_warning("No tracklist entry found for start time %.3fs. Using entry %d." % [render_start_override, idx + 1])
	if track_index_specified and (idx != track_index - 1):
		push_warning("Track index %d is out of range. Using entry %d." % [track_index, idx + 1])
	selected_track_entry = entries[idx]
	var entry_timestamp := String(selected_track_entry.get("timestamp", ""))
	var entry_title := String(selected_track_entry.get("title", ""))
	var entry_shader_name := String(selected_track_entry.get("shader", ""))
	var entry_params = selected_track_entry.get("params", {})
	var entry_start := float(selected_track_entry.get("seconds", 0.0))
	var entry_end := float(selected_track_entry.get("next_seconds", -1.0))
	if entry_end <= entry_start and selected_track_entry.has("duration_hint"):
		var hint_span := float(selected_track_entry.get("duration_hint", -1.0))
		if hint_span > 0.0:
			entry_end = entry_start + hint_span
	track_source_start_time = entry_start
	track_source_end_time = entry_end
	if render_start_override >= 0.0:
		track_source_start_time = render_start_override
	if render_duration_override > 0.0 and track_source_start_time >= 0.0:
		track_source_end_time = track_source_start_time + render_duration_override
	track_start_time = track_source_start_time
	track_end_time = track_source_end_time
	var entry_label := ""
	if entry_timestamp != "" or entry_title != "":
		entry_label = "("
		if entry_timestamp != "":
			entry_label += entry_timestamp
			if entry_title != "":
				entry_label += " "
		if entry_title != "":
			entry_label += entry_title
		entry_label += ")"
	var info_parts := []
	if entry_shader_name != "":
		info_parts.append("shader=%s" % entry_shader_name)
	if entry_params is Dictionary and (entry_params as Dictionary).size() > 0:
		info_parts.append("params=%s" % JSON.stringify(entry_params))
	var info_suffix := ""
	if info_parts.size() > 0:
		info_suffix = " ["
		for info_idx in range(info_parts.size()):
			if info_idx > 0:
				info_suffix += "; "
			info_suffix += String(info_parts[info_idx])
		info_suffix += "]"
	var selection_line := "[ExportRenderer] Using tracklist entry %d" % (idx + 1)
	if entry_label != "":
		selection_line += " %s" % entry_label
	selection_line += info_suffix
	print(selection_line)
	if track_source_start_time >= 0.0:
		var end_label := "open"
		if track_source_end_time > track_source_start_time:
			end_label = "%.3fs" % track_source_end_time
		print("[ExportRenderer] Track source window: %.3fs -> %s" % [track_source_start_time, end_label])

	if track_index_specified and render_start_override < 0.0:
		var body := String(selected_track_entry.get("body", ""))
		var line := "0:00 " + body
		var inline := PackedStringArray()
		inline.append(line)
		tracklist_inline = inline

func _read_tracklist_lines(path: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
			var global_path := ProjectSettings.globalize_path(path)
			if global_path != path:
					file = FileAccess.open(global_path, FileAccess.READ)
	if file == null and (path.begins_with("res://") or path.begins_with("user://")):
					var abs := ProjectSettings.globalize_path(path)
					file = FileAccess.open(abs, FileAccess.READ)
	if file == null and !path.begins_with("res://") and !path.begins_with("user://"):
					var res_path := "res://".path_join(path)
					if FileAccess.file_exists(res_path):
							file = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
			return lines
	while not file.eof_reached():
			lines.append(file.get_line())
	file.close()
	return lines

func _parse_tracklist_entries(lines: PackedStringArray) -> Array:
	var out: Array = []
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var space_idx := line.find(" ")
		if space_idx < 0:
			continue
		var ts := line.substr(0, space_idx).strip_edges()
		var body := line.substr(space_idx + 1).strip_edges()
		if body == "":
			continue
		var title := body
		var shader_name := ""
		var params := {}
		var duration_hint := -1.0
		var explicit_end := -1.0
		if body.find("|") >= 0:
			var parts := body.split("|")
			title = parts[0].strip_edges()
			for i in range(1, parts.size()):
				var seg := String(parts[i]).strip_edges()
				if seg == "":
					continue
				if seg.begins_with("shader="):
					shader_name = seg.substr("shader=".length()).strip_edges()
				elif seg.begins_with("set="):
					var json_txt := seg.substr("set=".length()).strip_edges()
					var parsed = JSON.parse_string(json_txt)
					if typeof(parsed) == TYPE_DICTIONARY:
						params = parsed
					else:
						push_warning("Invalid JSON in tracklist set= directive: %s" % json_txt)
				elif seg.begins_with("duration="):
					duration_hint = _parse_duration_to_seconds(seg.substr("duration=".length()).strip_edges())
				elif seg.begins_with("end="):
					explicit_end = _parse_duration_to_seconds(seg.substr("end=".length()).strip_edges())
		var ts_seconds := _parse_timestamp_to_seconds(ts)
		if ts_seconds < 0.0:
			continue
		out.append({
			"timestamp": ts,
			"body": body,
			"title": title,
			"shader": shader_name,
			"params": params,
			"seconds": ts_seconds,
			"duration_hint": duration_hint,
			"explicit_end": explicit_end,
		})

	for i in range(out.size()):
		var current: Dictionary = out[i]
		var sec := float(current.get("seconds", -1.0))
		if sec < 0.0:
			continue
		var next_sec := float(current.get("explicit_end", -1.0))
		var dur_hint := float(current.get("duration_hint", -1.0))
		if next_sec <= sec and dur_hint > 0.0:
			next_sec = sec + dur_hint
		if next_sec <= sec and i + 1 < out.size():
			var subsequent: Dictionary = out[i + 1]
			var subsequent_sec := float(subsequent.get("seconds", -1.0))
			if subsequent_sec >= 0.0:
				next_sec = subsequent_sec
		current["next_seconds"] = next_sec
	return out

func _find_tracklist_entry_for_time(entries: Array, target_time: float) -> int:
	if target_time < 0.0:
		return -1
	var epsilon := 0.0005
	var last_valid := -1
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var start := float(entry.get("seconds", -1.0))
		if start < 0.0:
			continue
		var end := float(entry.get("next_seconds", -1.0))
		if end <= start:
			var hint_val := float(entry.get("duration_hint", -1.0))
			if hint_val > 0.0:
				end = start + hint_val
		if end > start:
			if target_time + epsilon < start:
				if last_valid >= 0:
					return last_valid
				return i
			if target_time <= end + epsilon:
				return i
		last_valid = i
	return last_valid

func _parse_timestamp_to_seconds(ts: String) -> float:
	var trimmed := ts.strip_edges()
	if trimmed == "":
		return -1.0
	if trimmed.find(":") < 0:
		var numeric := trimmed.to_float()
		if numeric < 0.0:
			return -1.0
		return numeric
	var parts := trimmed.split(":")
	if parts.size() < 2 or parts.size() > 3:
		return -1.0
	for i in range(parts.size()):
		parts[i] = String(parts[i]).strip_edges()
	if parts.size() == 2:
		var minutes := int(parts[0])
		var seconds := parts[1].to_float()
		if minutes < 0 or seconds < 0.0 or seconds >= 60.0:
			return -1.0
		return float(minutes * 60) + seconds
	var hours := int(parts[0])
	var minutes := int(parts[1])
	var seconds := parts[2].to_float()
	if hours < 0 or minutes < 0 or minutes >= 60 or seconds < 0.0 or seconds >= 60.0:
		return -1.0
	return float(hours * 3600 + minutes * 60) + seconds

func _parse_seconds_value(text: String) -> float:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return -1.0
	if trimmed.find(":") >= 0:
		return -1.0
	var val := trimmed.to_float()
	if val < 0.0:
		return -1.0
	return val

func _parse_duration_to_seconds(text: String) -> float:
	if text == "":
		return -1.0
	if text.find(":") >= 0:
		return _parse_timestamp_to_seconds(text)
	var val := text.to_float()
	if val < 0.0:
		return -1.0
	return val

func _get_time_for_frame_index(idx: int) -> float:
	if root_node == null or idx < 0:
		return -1.0
	if root_node.has_method("get_offline_time_at_index"):
		var t_override = root_node.call("get_offline_time_at_index", idx)
		if typeof(t_override) == TYPE_FLOAT:
			return float(t_override)
	if root_node.has_method("get_offline_time_for_frame"):
		var frame_time = root_node.call("get_offline_time_for_frame", idx)
		if typeof(frame_time) == TYPE_FLOAT:
			return float(frame_time)
	if fps > 0:
		return float(idx) / float(fps)
	return -1.0

func _find_frame_index_for_time(target_time: float, frame_count: int) -> int:
	if frame_count <= 0:
		return 0
	if target_time <= 0.0:
		return 0
	var epsilon := 0.0005
	for idx in range(frame_count):
		var t := _get_time_for_frame_index(idx)
		if t < 0.0:
			continue
		if t + epsilon >= target_time:
			return idx
	return frame_count

func _apply_tracklist_properties(node: Node) -> void:
	if node == null:
		return
	var has_path := _has_property(node, "tracklist_path")
	var has_lines := _has_property(node, "tracklist_lines")
	if track_index_specified and tracklist_inline.size() > 0:
		if has_path:
			node.set("tracklist_path", "")
		if has_lines:
			node.set("tracklist_lines", tracklist_inline)
	elif tracklist_path != "":
		if has_path:
			node.set("tracklist_path", tracklist_path)

func _apply_overlay_preference(node: Node) -> void:
	if node == null:
		return
	if _has_property(node, "overlay_enabled"):
		node.set("overlay_enabled", overlay_enabled)

func _apply_selected_track_entry() -> void:
	if selected_track_entry.is_empty() or root_node == null:
		return
	if root_node.has_method("apply_tracklist_entry"):
		root_node.call("apply_tracklist_entry", selected_track_entry)
		return
	var shader_name := String(selected_track_entry.get("shader", ""))
	if shader_name != "" and root_node.has_method("set_shader_by_name"):
		root_node.call("set_shader_by_name", shader_name)
	var params = selected_track_entry.get("params", {})
	if params is Dictionary and (params as Dictionary).size() > 0 and root_node.has_method("_apply_shader_params"):
		root_node.call("_apply_shader_params", params)

func _has_property(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	for item in obj.get_property_list():
		if String(item.name) == prop:
			return true
	return false
