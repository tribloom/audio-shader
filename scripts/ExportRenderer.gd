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
var save_jpg: bool = false
var jpg_quality: float = 0.9
var duration_s: float = 0.0
var waveform_base: String = ""

func _initialize() -> void:
	_parse_args()

	# Create an offscreen SubViewport to render into
	svp = SubViewport.new()
	svp.disable_3d = true
	svp.transparent_bg = false
	svp.update_mode = SubViewport.UPDATE_ALWAYS
	svp.size = Vector2i(width, height)
	# Add under the SceneTree's root
	root.add_child(svp)

	# Load your scene into the SubViewport
	var scene_path: String = args.get("scene", "scenes/AudioViz.tscn")
	root_node = load(scene_path).instantiate()
	svp.add_child(root_node)

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
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Deterministic frame loop
	var frames_total := int(ceil(duration_s * float(fps)))
	for i in range(frames_total):
		var t := float(i) / float(fps)
		if root_node.has_method("set_playhead"):
			root_node.call("set_playhead", t)

		# Advance one engine frame, then read pixels
		await self.process_frame

		var img: Image = svp.get_texture().get_image()
		var ext := ("jpg" if save_jpg else "png")
		var path := out_dir + "/" + ("%06d" % i) + "." + ext
		if save_jpg:
			img.save_jpg(path, int(round(jpg_quality * 100.0)))
		else:
			img.save_png(path)

	quit()

func _parse_args() -> void:
	var raw := OS.get_cmdline_args()
	for a in raw:
		if a.begins_with("--scene="):
			args.scene = a.split("=")[1]
		elif a.begins_with("--features="):
			args.features = a.split("=")[1]
		elif a.begins_with("--fps="):
			fps = int(a.split("=")[1])
		elif a.begins_with("--w="):
			width = int(a.split("=")[1])
		elif a.begins_with("--h="):
			height = int(a.split("=")[1])
		elif a.begins_with("--out="):
			out_dir = a.split("=")[1]
		elif a.begins_with("--jpg="):
			save_jpg = int(a.split("=")[1]) != 0
		elif a.begins_with("--quality="):
			jpg_quality = float(a.split("=")[1])
		elif a.begins_with("--waveform="):
			waveform_base = a.split("=")[1]
	if waveform_base != "":
		args.waveform = waveform_base

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
