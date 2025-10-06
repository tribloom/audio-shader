extends SceneTree
# Godot 4.4.1 — offline exporter (main viewport). Minimal logs.
# Tracklist line format:
# mm:ss Title | shader=NAME | set={...}

# ---------- CLI ----------
var scene_path := ""
var tracklist_path := ""
var track_index := 0
var fps := 60
var width := 1920
var height := 1080
var out_dir := "C:/Renders/frames"
var use_jpg := false
var jpg_quality := 0.9
var max_frames := -1

# ---------- Internals ----------
var instance_root: Node
const LOG_PREFIX := "[ExportRenderer] "

# ================= ENTRY =================
func _initialize() -> void:
	_parse_args()

	DisplayServer.window_set_size(Vector2i(width, height))
	if not OS.has_feature("headless"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

	if not _load_scene_as_current():
		_quit(1); return

	# Parse tracklist in FILE ORDER
	var items := _read_tracklist_ordered(tracklist_path)
	var sel := _select_track_and_duration(items, track_index)

	# Let SetsLoader finish its own init first
	await self.process_frame

	# Apply overrides from selected line
	var title_count := _apply_title_to_labels(sel.title)
	var shader_path := _apply_shader_by_name_everywhere(sel.shader)
	var uniforms_applied := _apply_uniforms_everywhere(sel.settings)

	# Prepare output
	if not _ensure_out_dir():
		_quit(1); return

	var total_frames := int(round(float(sel.duration_sec) * float(fps)))
	if total_frames <= 0:
		total_frames = 10 * fps
	if max_frames > 0 and max_frames < total_frames:
		total_frames = max_frames

	print("%sUsing track #%d: \"%s\"  shader=%s  shader_path=%s  uniforms_applied=%d  title_labels_set=%d  start=%s  duration=%ds  frames=%d  out=%s"
		% [LOG_PREFIX, sel.index, sel.title, (sel.shader if sel.shader != "" else "(none)"),
		   (shader_path if shader_path != "" else "(not found)"),
		   uniforms_applied, title_count, _format_ts(sel.start_sec),
		   sel.duration_sec, total_frames, _abs(out_dir)])

	# Warm up
	await self.process_frame
	await self.process_frame

	for i in range(total_frames):
		# advance scene
		await self.process_frame
		await self.process_frame

		# capture main viewport
		var vp := get_root()
		var tex := vp.get_texture()
		if tex == null:
			push_error("%sRoot viewport has no texture at frame %d" % [LOG_PREFIX, i]); _quit(1); return
		var img := tex.get_image()
		if img == null:
			push_error("%sFailed to capture image at frame %d" % [LOG_PREFIX, i]); _quit(1); return

		# save
		var ext := "png"
		if use_jpg:
			ext = "jpg"
		var abs_path := _abs(out_dir) + "/frame_%06d.%s" % [i, ext]

		var err := OK
		if use_jpg:
			err = img.save_jpg(abs_path, jpg_quality)
		else:
			err = img.save_png(abs_path)
		if err != OK:
			push_error("%sFailed to save %s (err=%d)" % [LOG_PREFIX, abs_path, err]); _quit(1); return

	print("%sDone. Wrote %d frames to %s" % [LOG_PREFIX, total_frames, _abs(out_dir)])
	_quit(0)

# ================= ARGS =================
func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
		var dd := args.find("--")
		if dd >= 0:
			args = args.slice(dd + 1, args.size())

	var i := 0
	while i < args.size():
		match args[i]:
			"--scene":
				i += 1; if i < args.size(): scene_path = args[i]
			"--tracklist":
				i += 1; if i < args.size(): tracklist_path = args[i]
			"--track":
				i += 1; if i < args.size(): track_index = int(args[i])
			"--fps":
				i += 1; if i < args.size(): fps = int(args[i])
			"--w":
				i += 1; if i < args.size(): width = int(args[i])
			"--h":
				i += 1; if i < args.size(): height = int(args[i])
			"--out":
				i += 1; if i < args.size(): out_dir = args[i]
			"--jpg":
				i += 1; if i < args.size():
					var v := args[i].to_lower()
					use_jpg = (v == "1" or v == "true" or v == "yes")
			"--quality":
				i += 1; if i < args.size(): jpg_quality = clamp(float(args[i]), 0.0, 1.0)
			"--max_frames":
				i += 1; if i < args.size(): max_frames = int(args[i])
			_:
				pass
		i += 1

	if scene_path.is_empty():
		push_error("%sMissing --scene <path_to_tscn>" % LOG_PREFIX)

# ============= SCENE LOAD (main viewport) =============
func _load_scene_as_current() -> bool:
	if scene_path.is_empty():
		return false
	var packed := load(scene_path)
	if packed == null:
		push_error("%sFailed to load scene: %s" % [LOG_PREFIX, scene_path]); return false
	instance_root = packed.instantiate()
	if instance_root == null:
		push_error("%sFailed to instantiate scene: %s" % [LOG_PREFIX, scene_path]); return false
	get_root().add_child(instance_root)
	self.current_scene = instance_root
	instance_root.process_mode = Node.PROCESS_MODE_ALWAYS
	instance_root.propagate_call("set_process", [true], true)
	instance_root.propagate_call("set_physics_process", [true], true)
	return true

# ================= TRACKLIST =================
# Keep file order. Compute duration from next line.
class_name _TLChoice
var start_sec := 0
var title := ""
var shader := ""
var settings := {}
var index := 0
var duration_sec := 10

func _read_tracklist_ordered(path: String) -> Array:
	var out: Array = []
	if path == "" or not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		var item := _parse_tracklist_line(line)
		if item != null:
			out.append(item)
	f.close()
	# durations by next item in FILE ORDER
	for i in range(out.size()):
		var cur := out[i] as _TLChoice
		if i < out.size() - 1:
			var nxt := out[i + 1] as _TLChoice
			cur.duration_sec = max(nxt.start_sec - cur.start_sec, 1)
		else:
			cur.duration_sec = max(cur.duration_sec, 10)
		out[i] = cur
	return out

func _parse_tracklist_line(line: String) -> _TLChoice:
	var L := line.strip_edges()
	if L == "" or L.begins_with("#"):
		return null

	var parts := L.split("|", false)
	if parts.size() == 0:
		return null

	var head := parts[0].strip_edges()
	var sp := head.find(" ")

	var it := _TLChoice.new()
	if sp > 0:
		it.start_sec = _parse_ts(head.substr(0, sp))
		it.title = head.substr(sp + 1, head.length() - sp - 1).strip_edges()
	else:
		it.title = head

	for i in range(1, parts.size()):
		var seg := parts[i].strip_edges()
		var eq := seg.find("=")
		if eq <= 0:
			continue
		var key := seg.substr(0, eq).strip_edges().to_lower()
		var val := seg.substr(eq + 1, seg.length() - eq - 1).strip_edges()
		if key == "shader":
			it.shader = val
		elif key == "set":
			if val.begins_with("{") and val.ends_with("}"):
				var parsed := JSON.parse_string(val)
				if typeof(parsed) == TYPE_DICTIONARY:
					it.settings = parsed
	return it

func _select_track(items: Array, idx: int) -> _TLChoice:
	if items.is_empty():
		var d := _TLChoice.new()
		d.title = "(no tracklist)"
		d.index = 0
		d.start_sec = 0
		d.duration_sec = 10
		return d
	var i := clamp(idx, 0, items.size() - 1)
	var sel := items[i] as _TLChoice
	sel.index = i
	return sel

func _select_track_and_duration(items: Array, idx: int) -> _TLChoice:
	return _select_track(items, idx)

# ============= TITLE / SHADER / UNIFORMS =============
func _apply_title_to_labels(title: String) -> int:
	if title == "":
		return 0
	var count := 0
	var stack := [instance_root]
	while stack.size() > 0:
		var n := stack.pop_back()
		for c in n.get_children():
			if c is Node:
				stack.push_back(c)
		if (n is Label) or (n is RichTextLabel):
			var nm := n.name.to_lower()
			if nm.find("title") != -1:
				if n is Label:
					(n as Label).text = title
					count += 1
				elif n is RichTextLabel:
					(n as RichTextLabel).text = title
					count += 1
	return count

# Find a shader by name in common folders, case-insensitive.
# Returns resource path used ("" if not found). Applies to every ShaderMaterial in the scene.
func _apply_shader_by_name_everywhere(name: String) -> String:
	if name == "":
		return ""
	var cand := _find_shader_resource_path(name)
	if cand == "":
		return ""
	var shader_mat: ShaderMaterial = null
	var shader_res: Shader = null
	var res := load(cand)
	if res is ShaderMaterial:
		shader_mat = res
	elif res is Shader:
		shader_res = res

	var changed := 0
	var stack := [instance_root]
	while stack.size() > 0:
		var n := stack.pop_back()
		for c in n.get_children():
			if c is Node:
				stack.push_back(c)
		if n is CanvasItem:
			var ci := n as CanvasItem
			if ci.material and ci.material is ShaderMaterial:
				if shader_mat:
					ci.material = shader_mat.duplicate()
					changed += 1
				elif shader_res:
					var m := ci.material as ShaderMaterial
					m.shader = shader_res
					changed += 1
	return cand

func _find_shader_resource_path(name: String) -> String:
	var lower := name.to_lower()
	var roots := ["res://materials", "res://shaders"]
	var exts := [".tres", ".res", ".gdshader", ".shader"]
	for root in roots:
		var path := _scan_for_name(root, lower, exts)
		if path != "":
			return path
	return ""

func _scan_for_name(root: String, lower: String, exts: Array) -> String:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)):
		return ""
	var d := DirAccess.open(root)
	if d == null:
		return ""
	d.list_dir_begin()
	while true:
		var fn := d.get_next()
		if fn == "":
			break
		if fn == "." or fn == "..":
			continue
		var p := root + "/" + fn
		if d.current_is_dir():
			var sub := _scan_for_name(p, lower, exts)
			if sub != "":
				return sub
		else:
			var fnl := fn.to_lower()
			var ok_ext := false
			for e in exts:
				if fnl.ends_with(String(e)):
					ok_ext = true
					break
			if ok_ext and fnl.find(lower) != -1:
				return p
	d.list_dir_end()
	return ""

# Apply all uniforms from settings to every ShaderMaterial that has them; return count
func _apply_uniforms_everywhere(settings: Dictionary) -> int:
	if settings == null or settings.size() == 0:
		return 0
	var total := 0
	var stack := [instance_root]
	while stack.size() > 0:
		var n := stack.pop_back()
		for c in n.get_children():
			if c is Node:
				stack.push_back(c)
		if n is CanvasItem:
			var ci := n as CanvasItem
			if ci.material and ci.material is ShaderMaterial:
				total += _apply_uniforms_to_material(ci.material as ShaderMaterial, settings)
	return total

func _apply_uniforms_to_material(mat: ShaderMaterial, settings: Dictionary) -> int:
	if mat == null or mat.shader == null:
		return 0
	var count := 0
	for k in settings.keys():
		var v := _coerce_uniform_value(settings[k])
		if _shader_has_uniform(mat, k):
			mat.set_shader_parameter(k, v); count += 1
		elif _shader_has_uniform(mat, "u_" + k):
			mat.set_shader_parameter("u_" + k, v); count += 1
		elif _shader_has_uniform(mat, "_" + k):
			mat.set_shader_parameter("_" + k, v); count += 1
	return count

func _shader_has_uniform(mat: ShaderMaterial, uname: String) -> bool:
	if mat == null or mat.shader == null:
		return false
	for u in mat.shader.get_shader_uniform_list():
		if typeof(u) == TYPE_DICTIONARY and u.has("name") and String(u["name"]) == uname:
			return true
	return false

func _coerce_uniform_value(v: Variant) -> Variant:
	var t := typeof(v)
	if t == TYPE_ARRAY:
		var a := v as Array
		if a.size() == 3:
			return Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
		if a.size() == 4:
			return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
		return a
	return v

# ================= FS / UTILS =================
func _ensure_out_dir() -> bool:
	var abs_out := _abs(out_dir)
	var mk := DirAccess.make_dir_recursive_absolute(abs_out)
	if mk != OK and not DirAccess.dir_exists_absolute(abs_out):
		push_error("%sFailed to create directory: %s (err=%d)" % [LOG_PREFIX, abs_out, mk])
		return false
	return true

func _abs(p: String) -> String:
	var norm := p.replace("\\", "/")
	if norm.find("://") == -1 and norm.length() >= 2 and norm[1] == ":":
		return norm
	return ProjectSettings.globalize_path(norm)

func _parse_ts(s: String) -> int:
	var p := s.strip_edges().split(":")
	if p.size() == 2:
		return int(p[0]) * 60 + int(p[1])
	if p.size() == 3:
		return int(p[0]) * 3600 + int(p[1]) * 60 + int(p[2])
	return 0

func _format_ts(sec: int) -> String:
	var m := sec / 60
	var s := sec % 60
	return "%d:%02d" % [m, s]

func _quit(code: int) -> void:
	if instance_root and is_instance_valid(instance_root):
		instance_root.queue_free()
	await self.process_frame
	quit(code)
