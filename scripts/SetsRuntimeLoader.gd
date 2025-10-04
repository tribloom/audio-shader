extends Node
## Autoload this script as "SetsLoader".
## It dynamically loads audio from ./sets without requiring a Stream set on the AudioStreamPlayer.

@export var also_check_exe_sets: bool = true               # prefer ./sets beside the exe
@export var auto_sets_root: String = "user://sets"         # fallback if ./sets not present
@export var autoplay_on_apply: bool = false                # start playback when applying a set

var _player: AudioStreamPlayer = null
var _sets: Array = []      # [{name, audio, tracklist}]
var _idx: int = -1
var _paused_pos: float = 0.0

func _ready() -> void:
	# Defer until the main scene is ready so we can find the AudioStreamPlayer reliably.
	call_deferred("_init_after_scene_ready")

func _init_after_scene_ready() -> void:
	_player = _find_player(get_tree().root)
	if _player == null:
		push_warning("[SetsLoader] No AudioStreamPlayer found in the active scene.")
	else:
		print("[SetsLoader] Found player: ", _player.get_path())
	# Scan & auto-apply first set (optional)
	_scan_sets()
	if _sets.size() > 0 and _player != null:
		_apply_set(0)

# -------------------- Input (doesn't touch your _input) --------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F8:
				_scan_sets()
				if _sets.size() > 0 and _idx >= 0 and _idx < _sets.size():
					_apply_set(_idx)
				elif _sets.size() > 0:
					_apply_set(0)
			KEY_F6:
				if _sets.size() > 0:
					_apply_set((_idx - 1 + _sets.size()) % _sets.size())
			KEY_F7:
				if _sets.size() > 0:
					_apply_set((_idx + 1) % _sets.size())
			KEY_SPACE, KEY_P:
				_toggle_play_pause()
			KEY_S:
				_stop_playback()

# -------------------- Player discovery --------------------
func _find_player(n: Node) -> AudioStreamPlayer:
	# Depth-first search for the first AudioStreamPlayer in the active scene tree.
	if n is AudioStreamPlayer:
		return n as AudioStreamPlayer
	for c in n.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null

# -------------------- Root and scanning --------------------
func _sets_root() -> String:
	if also_check_exe_sets:
		var exe_sets := OS.get_executable_path().get_base_dir().path_join("sets")
		if DirAccess.dir_exists_absolute(exe_sets):
			return exe_sets
	return auto_sets_root

func _is_audio_file(lower: String) -> bool:
	return lower.ends_with(".mp3") or lower.ends_with(".wav") or lower.ends_with(".ogg") \
		or lower.ends_with(".m4a") or lower.ends_with(".flac")

func _scan_sets() -> void:
	_sets.clear()
	var root := _sets_root()
	if root.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(root)
	print("[SetsLoader] scan root: ", root)

	var da := DirAccess.open(root)
	if da == null:
		print("[SetsLoader] no sets dir")
		return

	da.list_dir_begin()
	while true:
		var name := da.get_next()
		if name == "": break
		if name.begins_with("."): continue
		var full := root.path_join(name)
		if !DirAccess.dir_exists_absolute(full): continue

		var audio := ""
		var tlist := ""
		var da2 := DirAccess.open(full)
		if da2:
			da2.list_dir_begin()
			while true:
				var f := da2.get_next()
				if f == "": break
				if f.begins_with("."): continue
				var fp := full.path_join(f)
				if !FileAccess.file_exists(fp): continue
				var low := f.to_lower()
				if audio == "" and _is_audio_file(low):
					audio = fp
				elif tlist == "" and (low.ends_with(".txt") or low.ends_with(".json")):
					tlist = fp
			da2.list_dir_end()

		if audio != "" and tlist != "":
			_sets.append({"name": name, "audio": audio, "tracklist": tlist})
	da.list_dir_end()

	_sets.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(b["name"]) < 0)
	for s in _sets:
		print("[SetsLoader] found set: %s | %s | %s" % [s["name"], s["audio"], s["tracklist"]])
	# keep current index if possible
	if _idx >= _sets.size(): _idx = -1

# -------------------- Apply set (assigns stream at runtime) --------------------
func _apply_set(i: int) -> void:
	if _player == null: return
	if i < 0 or i >= _sets.size(): return
	_idx = i
	var s = _sets[i]
	print("[SetsLoader] apply set: ", s["name"])

	# 1) Audio (no preloaded stream required)
	var stream := _load_audio_any(s["audio"])
	if stream:
		_player.stop()
		_player.stream = stream
		_paused_pos = 0.0
		if autoplay_on_apply:
			_player.play()
	else:
		push_warning("[SetsLoader] failed to load audio: " + String(s["audio"]))

	# 2) Tracklist: set Visualizer's tracklist_path and call _parse_tracklist(), if present
	var vis := _find_visualizer_owner()
	if vis != null:
		if vis.has_method("set") and _has_property_on(vis, "tracklist_path"):
			vis.set("tracklist_path", s["tracklist"])
		if vis.has_method("_parse_tracklist"):
			vis._parse_tracklist()
		if vis.has_method("set_paused_playback_position"):
			vis.set_paused_playback_position(0.0)
	else:
		print("[SetsLoader] NOTE: couldn't find Visualizer node for tracklist parsing")

func _find_visualizer_owner() -> Node:
	# Try the player's parent chain; adapt if your Visualizer lives elsewhere.
	var n := _player as Node
	while n and n.get_parent():
		if n.has_method("_parse_tracklist") or _has_property_on(n, "tracklist_path"):
			return n
		n = n.get_parent()
	return _player.get_parent()

func _has_property_on(n: Object, prop: String) -> bool:
	for p in n.get_property_list():
		if String(p.name) == prop:
			return true
	return false

# -------------------- Audio loading --------------------
func _load_audio_any(path: String) -> AudioStream:
	var lower := path.to_lower()
	if lower.ends_with(".mp3"):
		if !FileAccess.file_exists(path):
			return null
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return null
		var s := AudioStreamMP3.new()
		s.data = bytes
		return s
	var res := ResourceLoader.load(path)
	return res as AudioStream

# -------------------- Playback helpers --------------------
func _toggle_play_pause() -> void:
	if _player == null: return
	var vis := _find_visualizer_owner()
	if _player.playing:
		_paused_pos = 0.0
		if _player.has_method("get_playback_position"):
			_paused_pos = _player.get_playback_position()
		_player.stop()
		if _paused_pos > 0.0:
			_player.seek(_paused_pos)
		if vis != null and vis.has_method("set_paused_playback_position"):
			vis.set_paused_playback_position(_paused_pos)
	else:
		if _player.stream == null:
			print("[SetsLoader] no stream; choose a set with F6/F7 or rescan F8")
			return
		_player.play()
		if _paused_pos > 0.0:
			_player.seek(_paused_pos)
		_paused_pos = 0.0

func _stop_playback() -> void:
	if _player == null:
		return

	var vis := _find_visualizer_owner()
	var cue_pos := 0.0
	if vis != null and vis.has_method("get_current_cue_start_time"):
		cue_pos = vis.get_current_cue_start_time()
	elif _player.has_method("get_playback_position"):
		cue_pos = _player.get_playback_position()

	_paused_pos = cue_pos
	_player.stop()
	if cue_pos > 0.0:
		_player.seek(cue_pos)

	if vis != null and vis.has_method("set_paused_playback_position"):
		vis.set_paused_playback_position(cue_pos)
