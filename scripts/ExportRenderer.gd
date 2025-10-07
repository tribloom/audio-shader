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

# Tracklist overrides for headless mode
var tracklist_path: String = ""
var track_index: int = 1
var track_index_specified: bool = false
var tracklist_inline: PackedStringArray = PackedStringArray()
var selected_track_entry: Dictionary = {}

func _initialize() -> void:
	_parse_args()

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
	svp.add_child(root_node)

	await root_node.ready
	_apply_selected_track_entry()

	# Enable offline mode + aspect + features
	if root_node.has_method("set_offline_mode"):
		root_node.call("set_offline_mode", true)
	if root_node.has_method("set_aspect"):
		root_node.call("set_aspect", float(width) / float(height))
	var features_path: String = args.get("features", "")
	if features_path != "" and root_node.has_method("load_features_csv"):
		root_node.call("load_features_csv", features_path)
	var waveform_path: String = args.get("waveform", "")
	if waveform_path != "" and root_node.has_method("load_waveform_binary"):
		root_node.call("load_waveform_binary", waveform_path)

	duration_s = _infer_duration(features_path)
	DirAccess.make_dir_recursive_absolute(out_dir_fs)

	# Deterministic frame loop
	var frames_total := int(ceil(duration_s * float(fps)))
	for i in range(frames_total):
		var t := float(i) / float(fps)
		if root_node.has_method("set_playhead"):
			root_node.call("set_playhead", t)

				# Advance one engine frame, then read pixels
			await self.process_frame

			var img := _capture_subviewport_image()
			if img == null:
				return

			var ext := ("jpg" if save_jpg else "png")
			var filename := "%06d.%s" % [i, ext]
			var path := out_dir_fs.path_join(filename)
			if save_jpg:
				img.save_jpg(path, int(round(jpg_quality * 100.0)))
			else:
				img.save_png(path)

		quit()

func _capture_subviewport_image() -> Image:
		var tex := svp.get_texture()
		if tex == null:
				push_error("SubViewport returned no texture. The renderer is likely running in dummy/headless mode. Remove --headless or force a rendering driver such as --rendering-driver opengl3.")
				quit(1)
				return null

		var img := tex.get_image()
		if img == null:
				push_error("Failed to fetch SubViewport image. The renderer is likely running in dummy/headless mode. Remove --headless or force a rendering driver such as --rendering-driver opengl3.")
				quit(1)
				return null
		return img

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
		i += 1
	if waveform_base != "":
		args.waveform = waveform_base
	out_dir_fs = _resolve_output_path(out_dir)
	if pending_tracklist != "":
		tracklist_path = pending_tracklist
		_prepare_tracklist_override()
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
		["tracklist_path", tracklist_path],
		["track_index", track_index],
		["track_index_specified", track_index_specified],
		["tracklist_inline_size", tracklist_inline.size()],
	]
	print("[ExportRenderer] Parsed configuration:")
	for item in summary:
		print("  %s: %s" % [item[0], item[1]])

func _prepare_tracklist_override() -> void:
		selected_track_entry = {}
		tracklist_inline = PackedStringArray()
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
		if track_index_specified and (idx != track_index - 1):
				push_warning("Track index %d is out of range. Using entry %d." % [track_index, idx + 1])
		selected_track_entry = entries[idx]

		if track_index_specified:
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
				out.append({
						"timestamp": ts,
						"body": body,
						"title": title,
						"shader": shader_name,
						"params": params,
				})
		return out

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
