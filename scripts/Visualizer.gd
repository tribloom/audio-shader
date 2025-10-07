# Visualizer.gd (Godot 4.4+)
extends Node2D
##
## Modes:
## - CHROMA, CIRCLE
## - BARS, LINE, WATERFALL
## - AURORA (onset-driven nebula)
## - UNIVERSE (perspective fractal, audio-reactive)
## - UNIVERSE_ALT (ported variant, audio-reactive)
## - BASIC_AUDIO (Shadertoy-style audio shader: spectrum + optional waterfall amps)
## - SONIC_FUSION (torus/lightning shader)
##

# ---------- Dynamic shader registry ----------
@export var extra_shader_names: PackedStringArray = [
	"HEXAGONE",
	"ARC_STORM",
	"ELECTRON_SURGE",
	"HEX_TERRAIN",
	"KALEIDOSCOPE_BLOOM",
	"PARTICLE_CONSTELLATIONS",
	"VORONOI_PULSE_GRID",
	"VOXEL_CITYSCAPE",
	"RIBBON_TRAILS",
	"ATANS_BEGONE",
	"OVERSATURATED_WEB",
	"JASZ_UNIVERSE","BARS_PLUS",
	"FALLING_STRIPES",
	"MANDELBOX_SWEEPER",
	"AUDIO_VISUALIZER",
	"ABSTRACT_MUSIC",
	"RAYMARCH_AUDIO",
	"COMPLICATING"
]      # e.g. ["ARCS", "STARFIELD"]
@export var extra_shader_materials: Array[ShaderMaterial] = []  # same length as names

var _name_to_mode: Dictionary = {}          # "CHROMA" -> Mode.CHROMA
var _name_to_material: Dictionary = {}      # "ARCS"   -> ShaderMaterial
var _custom_active_material: ShaderMaterial = null

@export var target_bus_name: String = "Music"
@export var analyzer_slot: int = 0

@export var capture_slot: int = -1 # slot index of 'Capture' (AudioEffectCapture) on the target bus; -1 disables
@export var enable_waveform_capture: bool = true
@export var waveform_width: int = 1024 # will clamp to spectrum_bar_count
var capture: AudioEffectCapture = null
var _wave_img: Image
var _wave_tex: ImageTexture

# Offline rendering support
var _offline_mode: bool = false
var _offline_playhead: float = 0.0
var _offline_features: Array = []              # Array of {"frame": int, "t": float, "level": float, "kick": float, "bands": PackedFloat32Array}
var _offline_fps: float = 60.0
var _offline_dt: float = 1.0 / 60.0
var _offline_last_index: int = 0
var _offline_wave_samples: PackedFloat32Array = PackedFloat32Array()
var _offline_wave_rate: float = 0.0
var _offline_wave_duration: float = 0.0

# Normalization
@export var db_min: float = -80.0
@export var db_max: float =  -6.0

# Smoothing
@export var level_lerp: float = 0.15
@export var bass_lerp:  float = 0.25
@export var treb_lerp:  float = 0.25
@export var tone_lerp:  float = 0.15

# Boosts
@export var level_boost: float = 1.4
@export var kick_boost:  float = 1.8

# Materials
@export var material_chromatic:    ShaderMaterial
@export var material_circle:       ShaderMaterial
@export var material_bars:         ShaderMaterial
@export var material_line:         ShaderMaterial
@export var material_waterfall:    ShaderMaterial
@export var material_aurora:       ShaderMaterial
@export var material_universe:     ShaderMaterial
@export var material_universe_alt: ShaderMaterial
@export var material_basic_audio_shader: ShaderMaterial  
@export var material_sonic_fusion:     ShaderMaterial    
@export var material_power_particle: ShaderMaterial 
@export var material_fractal_colors: ShaderMaterial 
@export var material_bubbles: ShaderMaterial 

enum Mode {
	CHROMA, CIRCLE, BARS, LINE, WATERFALL, AURORA, UNIVERSE, UNIVERSE_ALT,
	BASIC_AUDIO,
	POWER_PARTICLE,
	SONIC_FUSION,
	FRACTAL_COLORS,
	BUBBLES, 
	CUSTOM # used only when a non-enum shader is selected by name
}

@export var start_mode: Mode = Mode.CHROMA

@onready var player: AudioStreamPlayer = $AudioStreamPlayer
@onready var color_rect: ColorRect = $CanvasLayer/ColorRect

@export_group("Window")
@export var landscape_resolution: Vector2i = Vector2i(1920, 1080)
@export var portrait_resolution: Vector2i = Vector2i(1080, 1920)
@export var start_in_portrait: bool = false

@export_group("")

var _is_portrait: bool = false
var _forced_aspect: float = 0.0

var analyzer: AudioEffectSpectrumAnalyzerInstance
var bus_idx: int = -1
var started := false
var mode: Mode

var _last_play_pos: float = 0.0
var _resume_from_pos: float = 0.0

# Cache shader uniform names for quick lookups when binding parameters.
var _shader_uniform_cache: Dictionary = {}

# Smoothed signals
var level_sm := 0.0
var kick_sm  := 0.0
var bass_sm  := 0.0
var treb_sm  := 0.0
var tone_sm  := 0.0

# Spectrum bins/texture
@export var spectrum_bar_count: int = 64
@export var spectrum_min_hz: float = 50.0
@export var spectrum_max_hz: float = 12000.0
@export var spectrum_attack: float = 0.55
@export var spectrum_decay: float = 0.03
@export var spectrum_peak_decay: float = 0.01

var _edges: PackedFloat32Array
var _bin_raw: PackedFloat32Array
var _bin_vis: PackedFloat32Array
var _peak_hold: PackedFloat32Array
var _spec_img: Image
var _spec_tex: ImageTexture

	# Waterfall
@export var waterfall_rows: int = 256
var _wf_img: Image
var _wf_tex: ImageTexture
var _wf_head: int = 0

# Onset envelope + ring (used by AURORA/UNIVERSE variants)
@export var kick_thresh_on: float  = 0.55
@export var kick_min_interval: float = 0.12
@export var kick_env_decay: float   = 2.5
@export var ring_speed: float       = 1.0

var _kick_prev := 0.0
var _kick_env  := 0.0
var _ring_age  := 1.0
var _since_kick := 999.0

# -----------------------------------------------------------------------------------
# Tracklist Overlay (NEW)
# -----------------------------------------------------------------------------------
@export var tracklist_path: String = ""               # "res://tracklist.txt" or "user://..."
@export var tracklist_lines: PackedStringArray = []   # alternative inline source

# Overlay appearance & behavior
@export var overlay_enabled: bool = true
@export var overlay_font_size: int = 24
@export var overlay_margin: int = 120
@export var overlay_color: Color = Color(1,1,1,0.95)
@export var overlay_outline_color: Color = Color(0,0,0,0.85)
@export var overlay_outline_size: int = 2
@export var overlay_gap: int = 4 # vertical spacing between stacked labels

enum PlaytimeCorner { UPPER_RIGHT, LOWER_LEFT }
@export var playtime_corner: PlaytimeCorner = PlaytimeCorner.UPPER_RIGHT

# Credit label
@export var credit_enabled: bool = true
@export var credit_text: String = "@PartialToTrance"
@export var credit_font_size: int = 18
@export var credit_color: Color = Color(1, 1, 1, 0.90)
@export var credit_outline_color: Color = Color(0, 0, 0, 0.85)
@export var credit_outline_size: int = 2


# Internal overlay nodes/resources
var _title_label: Label
var _time_label: Label
var _credit_label: Label
var _label_settings: LabelSettings
var _credit_settings: LabelSettings
var _cues: Array = []       # Array of { "t": float, "title": String }
var _current_cue_idx: int = -1

# -----------------------------------------------------------------------------------

func _ready() -> void:
        mode = start_mode
        _build_shader_registry()

        _setup_spectrum_resources()
        _setup_waterfall_resources()
        _setup_waveform_resources()

        _apply_mode_material()

        _is_portrait = start_in_portrait
        _apply_window_orientation()

	player.bus = target_bus_name
	bus_idx = AudioServer.get_bus_index(target_bus_name)
	if bus_idx == -1:
		push_error("Bus '%s' not found." % target_bus_name)
		return

	call_deferred("_init_analyzer")

	call_deferred("_init_capture")

        _bind_all_material_textures()
        _update_aspect()

	_build_overlay()
	_parse_tracklist()
	_update_overlay_visibility()



func _register_shader(name: String, mat: ShaderMaterial, mode_opt = null) -> void:
	if name == "" or mat == null:
		return
	_name_to_material[name.to_upper()] = mat
	if mode_opt != null:
		_name_to_mode[name.to_upper()] = mode_opt

func _build_shader_registry() -> void:
	# Built-ins: names match your enum for easy use in tracklist
	_register_shader("CHROMA",          material_chromatic,       Mode.CHROMA)
	_register_shader("CIRCLE",          material_circle,          Mode.CIRCLE)
	_register_shader("BARS",            material_bars,            Mode.BARS)
	_register_shader("LINE",            material_line,            Mode.LINE)
	_register_shader("WATERFALL",       material_waterfall,       Mode.WATERFALL)
	_register_shader("AURORA",          material_aurora,          Mode.AURORA)
	_register_shader("UNIVERSE",        material_universe,        Mode.UNIVERSE)
	_register_shader("UNIVERSE_ALT",    material_universe_alt,    Mode.UNIVERSE_ALT)
	_register_shader("BASIC_AUDIO",     material_basic_audio_shader, Mode.BASIC_AUDIO)
	_register_shader("POWER_PARTICLE",  material_power_particle,  Mode.POWER_PARTICLE)
	_register_shader("SONIC_FUSION",    material_sonic_fusion,    Mode.SONIC_FUSION)
	_register_shader("FRACTAL_COLORS",  material_fractal_colors,  Mode.FRACTAL_COLORS)
	_register_shader("BUBBLES",         material_bubbles,         Mode.BUBBLES)

	# Extras from Inspector (names + materials arrays)
	var n = min(extra_shader_names.size(), extra_shader_materials.size())
	for i in range(n):
		_register_shader(extra_shader_names[i], extra_shader_materials[i]) # no enum on purpose

func set_shader_by_name(name: String) -> bool:
	var key := name.to_upper()
	if _name_to_mode.has(key):
		mode = _name_to_mode[key]
		_apply_mode_material()
		_update_aspect()
		return true
	if _name_to_material.has(key):
		_custom_active_material = _name_to_material[key]
		mode = Mode.CUSTOM
		_apply_mode_material()
		_update_aspect()
		return true
	push_warning("Shader name not found: %s" % name)
	return false

func _apply_shader_params(params: Dictionary) -> void:
		var mat := color_rect.material as ShaderMaterial
		if mat == null: return
		for k in params.keys():
				var v = params[k]
				# Coerce arrays to Godot vectors/colors
				if v is Array:
						var a := v as Array
						if a.size() == 2: v = Vector2(a[0], a[1])
						elif a.size() == 3: v = Color(a[0], a[1], a[2], 1.0) # works for vec3/color
						elif a.size() == 4: v = Color(a[0], a[1], a[2], a[3])
				# Try to set; ignore unknown
				mat.set_shader_parameter(k, v)

func set_offline_mode(enable: bool) -> void:
		_offline_mode = enable
		if enable:
				started = true
				if player:
						player.stop()
				analyzer = null
				capture = null
				_offline_last_index = 0
		else:
				_offline_playhead = 0.0

func set_aspect(aspect: float) -> void:
		if aspect <= 0.0:
				return
		_forced_aspect = aspect
		_update_aspect()

func set_playhead(t: float) -> void:
		_offline_playhead = max(t, 0.0)
		_last_play_pos = _offline_playhead
		if _offline_features.size() > 0:
				var idx_time := 0.0
				if _offline_last_index >= 0 and _offline_last_index < _offline_features.size():
						idx_time = float(_offline_features[_offline_last_index].get("t", 0.0))
				if _offline_playhead <= idx_time:
						_offline_last_index = 0

func load_features_csv(path: String) -> void:
	_offline_features.clear()
	_offline_last_index = 0
	if path == "":
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open features CSV: %s" % path)
		return

	var header_line := f.get_line()
	var headers := header_line.split(",")
	var col_index := {}
	for i in range(headers.size()):
		col_index[headers[i].strip_edges().to_lower()] = i

	var required := ["frame", "t", "level", "kick"]
	for key in required:
		if !col_index.has(key):
			push_error("Missing column '%s' in features CSV" % key)
			f.close()
			return

	var band_columns: Array = []
	for h in headers:
		var name := h.strip_edges()
		if name.length() >= 2 and name.begins_with("s"):
			if name.substr(1).is_valid_int():
				band_columns.append(name.to_lower())
	band_columns.sort_custom(func(a, b):
		return int(String(a).substr(1)) < int(String(b).substr(1)))

	var prev_time := -1.0
	var dt_accum := 0.0
	var dt_count := 0
	var last_time := 0.0
	var last_frame := 0
	while !f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var cells := line.split(",")
		if cells.size() < headers.size():
			continue
		var frame_idx := cells[col_index["frame"]].strip_edges().to_int()
		var t_val := cells[col_index["t"]].strip_edges().to_float()
		var level_val := cells[col_index["level"]].strip_edges().to_float()
		var kick_val := cells[col_index["kick"]].strip_edges().to_float()

		var bands := PackedFloat32Array()
		bands.resize(band_columns.size())
		for bi in range(band_columns.size()):
			var cname = band_columns[bi]
			if col_index.has(cname):
				var raw := cells[col_index[cname]].strip_edges()
				bands[bi] = raw.to_float()
			else:
				bands[bi] = 0.0

		_offline_features.append({
				"frame": frame_idx,
				"t": t_val,
				"level": clamp(level_val, 0.0, 1.0),
				"kick": clamp(kick_val, 0.0, 1.0),
				"bands": bands,
		})

		if prev_time >= 0.0:
				var step = max(0.0, t_val - prev_time)
				if step > 0.0:
						dt_accum += step
						dt_count += 1
		prev_time = t_val
		last_time = t_val
		last_frame = frame_idx

	f.close()

	if dt_count > 0 and dt_accum > 0.0:
			_offline_dt = dt_accum / float(dt_count)
	elif _offline_features.size() > 1:
			var first = _offline_features[0]
			var second = _offline_features[1]
			_offline_dt = max(1.0 / 60.0, float(second["t"]) - float(first["t"]))
	else:
			_offline_dt = 1.0 / 60.0

	if _offline_dt <= 0.0:
			_offline_dt = 1.0 / 60.0
	_offline_fps = 1.0 / _offline_dt
	_offline_playhead = 0.0
	_last_play_pos = 0.0

	if _offline_features.size() > 0:
			_offline_wave_duration = last_time
	else:
			_offline_wave_duration = 0.0

func load_waveform_binary(base_path: String) -> void:
		if base_path == "":
				return
		var bin_path := base_path + ".f32"
		var json_path := base_path + ".json"
		if !FileAccess.file_exists(bin_path) or !FileAccess.file_exists(json_path):
						push_warning("Waveform files not found for base '%s'" % base_path)
						return

		var meta_file := FileAccess.open(json_path, FileAccess.READ)
		if meta_file == null:
				push_warning("Failed to open waveform meta: %s" % json_path)
				return
		var meta_text := meta_file.get_as_text()
		meta_file.close()
		var meta = JSON.parse_string(meta_text)
		if typeof(meta) != TYPE_DICTIONARY:
				push_warning("Invalid waveform metadata JSON: %s" % json_path)
				return
		_offline_wave_rate = float(meta.get("sample_rate", 0.0))
		var expected_len := int(meta.get("length", 0))

		var bin_file := FileAccess.open(bin_path, FileAccess.READ)
		if bin_file == null:
				push_warning("Failed to open waveform binary: %s" % bin_path)
				return
		bin_file.big_endian = false
		var samples := PackedFloat32Array()
		if expected_len > 0:
				samples.resize(expected_len)
				for i in range(expected_len):
						if bin_file.eof_reached():
								samples[i] = 0.0
						else:
								samples[i] = bin_file.get_float()
		else:
				while !bin_file.eof_reached():
						samples.append(bin_file.get_float())
		bin_file.close()

		_offline_wave_samples = samples
		if _offline_wave_rate > 0.0 and samples.size() > 0:
				_offline_wave_duration = float(samples.size()) / _offline_wave_rate
		elif _offline_features.size() > 0:
				_offline_wave_duration = float(_offline_features.back().get("t", 0.0))
		else:
				_offline_wave_duration = 0.0

func _init_analyzer() -> void:
		if _offline_mode:
				return
		analyzer = AudioServer.get_bus_effect_instance(bus_idx, analyzer_slot) as AudioEffectSpectrumAnalyzerInstance
		if analyzer == null:
				push_error("No SpectrumAnalyzer on bus '%s' slot %d." % [target_bus_name, analyzer_slot])

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if player.stream and !player.playing:
			player.play()
			if _resume_from_pos > 0.0:
				player.seek(_resume_from_pos)
			_resume_from_pos = 0.0
			started = true
	if event is InputEventKey and event.pressed and !event.echo:
		match event.keycode:
			KEY_C:
				_toggle_mode()
			KEY_RIGHT:
				_skip_to_next_cue()
			KEY_LEFT:
				_skip_to_previous_cue()
			KEY_O:
				overlay_enabled = !overlay_enabled
			KEY_V:
				_toggle_window_orientation()

func _toggle_mode() -> void:
	match mode:
		Mode.CHROMA:         mode = Mode.CIRCLE
		Mode.CIRCLE:         mode = Mode.BARS
		Mode.BARS:           mode = Mode.LINE
		Mode.LINE:           mode = Mode.WATERFALL
		Mode.WATERFALL:      mode = Mode.AURORA
		Mode.AURORA:         mode = Mode.UNIVERSE
		Mode.UNIVERSE:       mode = Mode.UNIVERSE_ALT
		Mode.UNIVERSE_ALT:   mode = Mode.BASIC_AUDIO
		Mode.BASIC_AUDIO:    mode = Mode.POWER_PARTICLE
		Mode.POWER_PARTICLE: mode = Mode.SONIC_FUSION
		Mode.SONIC_FUSION:   mode = Mode.FRACTAL_COLORS
		Mode.FRACTAL_COLORS: mode = Mode.BUBBLES
		Mode.BUBBLES:        mode = Mode.CHROMA
		Mode.CUSTOM:         mode = Mode.CHROMA  # never land here by cycling
	_apply_mode_material()
	_update_aspect()

func _toggle_window_orientation() -> void:
	_is_portrait = !_is_portrait
	_apply_window_orientation()

func _apply_window_orientation() -> void:
	var desired = portrait_resolution if _is_portrait else landscape_resolution
	if desired.x <= 0 or desired.y <= 0:
		return
	DisplayServer.window_set_size(desired)
	_update_aspect()
		
func _apply_mode_material() -> void:
	match mode:
		Mode.CHROMA:            color_rect.material = material_chromatic
		Mode.CIRCLE:            color_rect.material = material_circle
		Mode.BARS:              color_rect.material = material_bars
		Mode.LINE:              color_rect.material = material_line
		Mode.WATERFALL:         color_rect.material = material_waterfall
		Mode.AURORA:            color_rect.material = material_aurora
		Mode.UNIVERSE:          color_rect.material = material_universe
		Mode.UNIVERSE_ALT:      color_rect.material = material_universe_alt
		Mode.BASIC_AUDIO:       color_rect.material = material_basic_audio_shader
		Mode.POWER_PARTICLE:    color_rect.material = material_power_particle
		Mode.SONIC_FUSION:      color_rect.material = material_sonic_fusion
		Mode.FRACTAL_COLORS:    color_rect.material = material_fractal_colors
		Mode.BUBBLES:           color_rect.material = material_bubbles
		Mode.CUSTOM:            color_rect.material = _custom_active_material
	_bind_all_material_textures()

func _process(dt: float) -> void:

	if _offline_mode:
			_process_offline()
			return

	var can_sample := player != null and player.stream != null and player.playing
	var overlay_time := _last_play_pos

	if !can_sample:
		_update_track_overlay(overlay_time)
		return

	if !started:
		started = true

	overlay_time = player.get_playback_position()
	_last_play_pos = overlay_time
	_resume_from_pos = 0.0

	if analyzer == null or color_rect.material == null:
		_update_track_overlay(overlay_time)
		return

	# Bands for CHROMA/CIRCLE smoothing
	var bass_lr   := analyzer.get_magnitude_for_frequency_range(50.0, 140.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
	var treble_lr := analyzer.get_magnitude_for_frequency_range(4000.0, 12000.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
	var wide_lr   := analyzer.get_magnitude_for_frequency_range(20.0, 18000.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)

	var bass_lin   = max(1e-7, 0.5 * (bass_lr.x + treble_lr.x)) # just to keep nonzero
	bass_lin = max(1e-7, 0.5 * (bass_lr.x + bass_lr.y))
	var treble_lin = max(1e-7, 0.5 * (treble_lr.x + treble_lr.y))
	var wide_lin   = max(1e-7, 0.5 * (wide_lr.x   + wide_lr.y))

	var bass_n   := _norm_db(linear_to_db(bass_lin))
	var treble_n := _norm_db(linear_to_db(treble_lin))
	var level_n  := _norm_db(linear_to_db(wide_lin))
	var tone_n   := _compute_tone_norm()

	kick_sm  = lerp(kick_sm,  bass_n,   bass_lerp)
	level_sm = lerp(level_sm, level_n,  level_lerp)
	bass_sm  = lerp(bass_sm,  bass_n,   bass_lerp)
	treb_sm  = lerp(treb_sm,  treble_n, treb_lerp)
	tone_sm  = lerp(tone_sm,  tone_n,   tone_lerp)

	# Shared spectrum
	_measure_bins()
	_advance_bins_visual()
	_update_spec_texture()
	_update_waveform_texture()
	_advance_waterfall()

	# Onset envelope
	_update_kick_envelope(dt)

	var mat := color_rect.material as ShaderMaterial
	match mode:
		Mode.CHROMA:
			mat.set_shader_parameter("level", clamp(level_sm * level_boost, 0.0, 1.0))
			mat.set_shader_parameter("kick",  clamp(kick_sm  * kick_boost,  0.0, 1.0))
		Mode.CIRCLE:
			mat.set_shader_parameter("bass",   clamp(bass_sm,  0.0, 1.0))
			mat.set_shader_parameter("treble", clamp(treb_sm,  0.0, 1.0))
			mat.set_shader_parameter("tone",   clamp(tone_sm,  0.0, 1.0))
		Mode.WATERFALL:
			if material_waterfall:
				var head_norm := float(_wf_head) / float(max(1, waterfall_rows))
				material_waterfall.set_shader_parameter("head_norm", head_norm)
		Mode.BARS, Mode.LINE:
			pass
		Mode.AURORA, Mode.UNIVERSE, Mode.UNIVERSE_ALT:
			mat.set_shader_parameter("kick_in",  clamp(kick_sm,   0.0, 1.0))
			mat.set_shader_parameter("kick_env", clamp(_kick_env, 0.0, 1.0))
			mat.set_shader_parameter("ring_age", clamp(_ring_age, 0.0, 1.0))
		Mode.BASIC_AUDIO:
			if material_basic_audio_shader:
				var head_norm2 := float(_wf_head) / float(max(1, waterfall_rows))
				material_basic_audio_shader.set_shader_parameter("head_norm", head_norm2)
		Mode.SONIC_FUSION:
			pass
		Mode.FRACTAL_COLORS:
			pass
		Mode.BUBBLES:
			pass

	var m := color_rect.material as ShaderMaterial
	if m:
		_set_uniform_if_present(m, "aspect", get_viewport_rect().size.x / max(1.0, get_viewport_rect().size.y))
		_set_uniform_if_present(m, "level_in", clamp(level_sm * level_boost, 0.0, 1.0))
		_set_uniform_if_present(m, "bass_in", clamp(bass_sm, 0.0, 1.0))
		_set_uniform_if_present(m, "treble_in", clamp(treb_sm, 0.0, 1.0))
		_set_uniform_if_present(m, "tone_in", clamp(tone_sm, 0.0, 1.0))
		_set_uniform_if_present(m, "kick_env", clamp(_kick_env, 0.0, 1.0))  # for “center flash” beats

	_update_aspect()

	_update_track_overlay(overlay_time)

func _process_offline() -> void:
		var overlay_time := _offline_playhead

		if color_rect == null:
				_update_track_overlay(overlay_time)
				return

		if _offline_features.is_empty():
				_update_track_overlay(overlay_time)
				return

		var sample := _sample_offline_features(_offline_playhead)
		if sample.is_empty():
				_update_track_overlay(overlay_time)
				return

		level_sm = float(sample.get("level", 0.0))
		kick_sm  = float(sample.get("kick", 0.0))

		var bands = sample.get("bands", PackedFloat32Array())
		if bands is PackedFloat32Array:
				var arr := bands as PackedFloat32Array
				if arr.size() > 0:
						bass_sm = clamp(arr[0], 0.0, 1.0)
						treb_sm = clamp(arr[arr.size() - 1], 0.0, 1.0)
						tone_sm = _estimate_tone_from_bands(arr)
						_apply_offline_spectrum(arr)
				else:
						_apply_offline_spectrum(PackedFloat32Array())
		else:
				_apply_offline_spectrum(PackedFloat32Array())

		var effective_dt := _offline_dt
		if effective_dt <= 0.0:
				effective_dt = 1.0 / max(1.0, _offline_fps)
		if effective_dt <= 0.0:
				effective_dt = 1.0 / 60.0

		_update_waveform_texture()
		_update_spec_texture()
		_advance_waterfall()
		_update_kick_envelope(effective_dt)

		var mat := color_rect.material as ShaderMaterial
		if mat:
				match mode:
						Mode.CHROMA:
								mat.set_shader_parameter("level", clamp(level_sm * level_boost, 0.0, 1.0))
								mat.set_shader_parameter("kick",  clamp(kick_sm  * kick_boost,  0.0, 1.0))
						Mode.CIRCLE:
								mat.set_shader_parameter("bass",   clamp(bass_sm,  0.0, 1.0))
								mat.set_shader_parameter("treble", clamp(treb_sm,  0.0, 1.0))
								mat.set_shader_parameter("tone",   clamp(tone_sm,  0.0, 1.0))
						Mode.WATERFALL:
								if material_waterfall:
										var head_norm := float(_wf_head) / float(max(1, waterfall_rows))
										material_waterfall.set_shader_parameter("head_norm", head_norm)
						Mode.AURORA, Mode.UNIVERSE, Mode.UNIVERSE_ALT:
								mat.set_shader_parameter("kick_in",  clamp(kick_sm,   0.0, 1.0))
								mat.set_shader_parameter("kick_env", clamp(_kick_env, 0.0, 1.0))
								mat.set_shader_parameter("ring_age", clamp(_ring_age, 0.0, 1.0))
						Mode.BASIC_AUDIO:
								if material_basic_audio_shader:
										var head_norm2 := float(_wf_head) / float(max(1, waterfall_rows))
										material_basic_audio_shader.set_shader_parameter("head_norm", head_norm2)

				_set_uniform_if_present(mat, "aspect", _get_current_aspect())
				_set_uniform_if_present(mat, "level_in", clamp(level_sm * level_boost, 0.0, 1.0))
				_set_uniform_if_present(mat, "bass_in", clamp(bass_sm, 0.0, 1.0))
				_set_uniform_if_present(mat, "treble_in", clamp(treb_sm, 0.0, 1.0))
				_set_uniform_if_present(mat, "tone_in", clamp(tone_sm, 0.0, 1.0))
				_set_uniform_if_present(mat, "kick_env", clamp(_kick_env, 0.0, 1.0))

		_update_aspect()
		_update_track_overlay(overlay_time)

func _sample_offline_features(t: float) -> Dictionary:
		if _offline_features.is_empty():
				return {}

		var idx = clamp(_offline_last_index, 0, _offline_features.size() - 1)
		var current = _offline_features[idx]
		var current_time := float(current.get("t", 0.0))

		if t < current_time and idx > 0:
				while idx > 0 and t < float(_offline_features[idx].get("t", 0.0)):
						idx -= 1
		else:
				while idx + 1 < _offline_features.size() and t >= float(_offline_features[idx + 1].get("t", 0.0)):
						idx += 1

		_offline_last_index = idx
		return _offline_features[idx]

func _apply_offline_spectrum(bands: PackedFloat32Array) -> void:
		if _spec_img == null:
				_setup_spectrum_resources()
		if bands.is_empty():
				for i in range(spectrum_bar_count):
						_bin_raw[i] = 0.0
						_bin_vis[i] = 0.0
						_peak_hold[i] = 0.0
				return

		var count := bands.size()
		for i in range(spectrum_bar_count):
				var t := 0.0
				if spectrum_bar_count > 1:
						t = float(i) / float(spectrum_bar_count - 1)
				var fpos := t * float(max(1, count - 1))
				var i0 := int(floor(fpos))
				var i1 = min(count - 1, i0 + 1)
				var frac := fpos - float(i0)
				var v = lerp(bands[i0], bands[i1], frac)
				v = clamp(v, 0.0, 1.0)
				_bin_raw[i] = v
				_bin_vis[i] = v
				_peak_hold[i] = v

func _estimate_tone_from_bands(bands: PackedFloat32Array) -> float:
		if bands.is_empty():
				return 0.0
		var num := 0.0
		var den := 0.0
		var count := bands.size()
		for i in range(count):
				var mag = max(0.0, bands[i])
				var weight := float(i) / float(max(1, count - 1))
				num += weight * mag
				den += mag
		if den <= 1e-6:
				return 0.0
		return clamp(num / den, 0.0, 1.0)

func _shader_has_uniform(m: ShaderMaterial, name: String) -> bool:
	if m == null or m.shader == null:
		return false

	if !_shader_uniform_cache.has(m.shader):
		var cache := {}
		for u in m.shader.get_shader_uniform_list():
			cache[u.name] = true
		_shader_uniform_cache[m.shader] = cache

	var uniform_map = _shader_uniform_cache[m.shader]
	return uniform_map.has(name)

func _set_uniform_if_present(m: ShaderMaterial, name: String, v) -> void:
	if _shader_has_uniform(m, name):
		m.set_shader_parameter(name, v)

func _apply_static_shader_inputs(m: ShaderMaterial) -> void:
	if m == null:
		return
	_set_uniform_if_present(m, "spectrum_tex", _spec_tex)
	_set_uniform_if_present(m, "waterfall_tex", _wf_tex)
	_set_uniform_if_present(m, "bar_count", spectrum_bar_count)
	_set_uniform_if_present(m, "rows", waterfall_rows)
	_set_uniform_if_present(m, "wf_rows", waterfall_rows)
	_set_uniform_if_present(m, "waveform_tex", _wave_tex)

func _norm_db(db_val: float) -> float:
	var dmin := db_min
	var dmax := db_max
	if dmax <= dmin: dmax = dmin + 1.0
	return clamp((db_val - dmin) / (dmax - dmin), 0.0, 1.0)

func _compute_tone_norm() -> float:
	var bands := [
		Vector2(  50.0,  100.0),
		Vector2( 100.0,  200.0),
		Vector2( 200.0,  400.0),
		Vector2( 400.0,  800.0),
		Vector2( 800.0, 1600.0),
		Vector2(1600.0, 3200.0),
		Vector2(3200.0, 6400.0),
		Vector2(6400.0,12000.0)
	]
	var num := 0.0
	var den := 0.0
	for b in bands:
		var m := analyzer.get_magnitude_for_frequency_range(b.x, b.y, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
		var mag = max(1e-7, 0.5 * (m.x + m.y))
		var center := sqrt(b.x * b.y)
		num += center * mag
		den += mag
	var centroid: float
	if den > 0.0:
		centroid = num / den
	else:
		centroid = 200.0
	var t := (log(centroid) - log(50.0)) / (log(12000.0) - log(50.0))
	return clamp(t, 0.0, 1.0)

func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_SIZE_CHANGED:
				_update_aspect()

func _update_aspect() -> void:
	var aspect := _get_current_aspect()
	var active := color_rect.material as ShaderMaterial
	if active:
		_apply_static_shader_inputs(active)
		_set_uniform_if_present(active, "aspect", aspect)

	for m in [
		material_bars, material_line, material_waterfall, material_aurora,
		material_universe, material_universe_alt,
		material_basic_audio_shader, material_sonic_fusion,
		material_fractal_colors, material_bubbles
	]:
		if m:
			_apply_static_shader_inputs(m)
			_set_uniform_if_present(m, "aspect", aspect)

	# Extras + custom
	for m in extra_shader_materials:
		if m:
			_apply_static_shader_inputs(m)
			_set_uniform_if_present(m, "aspect", aspect)
	if _custom_active_material:
		_apply_static_shader_inputs(_custom_active_material)
		_set_uniform_if_present(_custom_active_material, "aspect", aspect)

	if material_waterfall:
		_set_uniform_if_present(material_waterfall, "rows", waterfall_rows)
		if material_basic_audio_shader:
				_set_uniform_if_present(material_basic_audio_shader, "wf_rows", waterfall_rows)

func _get_current_aspect() -> float:
		if _forced_aspect > 0.0:
				return _forced_aspect
		var s := get_viewport_rect().size
		if s.y <= 0.0:
				return 1.0
		return s.x / max(1.0, s.y)


# Spectrum
func _setup_spectrum_resources() -> void:
	_edges = PackedFloat32Array()
	_edges.resize(spectrum_bar_count + 1)
	var lmin := log(max(1.0, spectrum_min_hz))
	var lmax := log(max(spectrum_min_hz + 1.0, spectrum_max_hz))
	for i in range(spectrum_bar_count + 1):
		var t := float(i) / float(spectrum_bar_count)
		_edges[i] = exp(lerp(lmin, lmax, t))

	_bin_raw   = PackedFloat32Array()
	_bin_vis   = PackedFloat32Array()
	_peak_hold = PackedFloat32Array()
	_bin_raw.resize(spectrum_bar_count)
	_bin_vis.resize(spectrum_bar_count)
	_peak_hold.resize(spectrum_bar_count)
	for i in range(spectrum_bar_count):
		_bin_raw[i] = 0.0
		_bin_vis[i] = 0.0
		_peak_hold[i] = 0.0

	_spec_img = Image.create(spectrum_bar_count, 1, false, Image.FORMAT_RG8)
	_spec_tex = ImageTexture.create_from_image(_spec_img)

func _measure_bins() -> void:
	if analyzer == null: return
	for i in range(spectrum_bar_count):
		var f0 := _edges[i]
		var f1 := _edges[i + 1]
		var m := analyzer.get_magnitude_for_frequency_range(f0, f1, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
		var lin = max(1e-7, 0.5 * (m.x + m.y))
		var v := _norm_db(linear_to_db(lin))
		_bin_raw[i] = lerp(_bin_raw[i], v, spectrum_attack)

func _advance_bins_visual() -> void:
	for i in range(spectrum_bar_count):
		_bin_vis[i] = max(_bin_raw[i], _bin_vis[i] - spectrum_decay)
		_peak_hold[i] = max(_bin_vis[i], _peak_hold[i] - spectrum_peak_decay)

func _update_spec_texture() -> void:
	for x in range(spectrum_bar_count):
		var r = clamp(_bin_vis[x], 0.0, 1.0)
		var g = clamp(_peak_hold[x], 0.0, 1.0)
		_spec_img.set_pixel(x, 0, Color(r, g, 0.0, 1.0))
	_spec_tex.update(_spec_img)

# Waterfall
func _setup_waterfall_resources() -> void:
	_wf_img = Image.create(spectrum_bar_count, max(1, waterfall_rows), false, Image.FORMAT_R8)
	_wf_tex = ImageTexture.create_from_image(_wf_img)
	_wf_head = 0

func _advance_waterfall() -> void:
	var rows = max(1, waterfall_rows)
	for x in range(spectrum_bar_count):
		var r = clamp(_bin_vis[x], 0.0, 1.0)
		_wf_img.set_pixel(x, _wf_head, Color(r, 0, 0))
	_wf_head = (_wf_head + 1) % rows
	_wf_tex.update(_wf_img)

# Onset envelope
func _update_kick_envelope(dt: float) -> void:
	_since_kick += dt
	if (_kick_prev < kick_thresh_on) and (kick_sm >= kick_thresh_on) and (_since_kick >= kick_min_interval):
		_kick_env = 1.0
		_ring_age = 0.0
		_since_kick = 0.0
	_kick_env = max(0.0, _kick_env - kick_env_decay * dt)
	_ring_age = min(1.0, _ring_age + ring_speed * dt)
	_kick_prev = kick_sm

# Bind textures once
func _bind_all_material_textures() -> void:
	for m in [
		material_bars, material_line, material_aurora,
		material_universe, material_universe_alt,
		material_basic_audio_shader, material_sonic_fusion,
		material_fractal_colors, material_bubbles
	]:
		_apply_static_shader_inputs(m)

	# Extras
	for m in extra_shader_materials:
		_apply_static_shader_inputs(m)

	# Custom active (if any)
	_apply_static_shader_inputs(_custom_active_material)

	if material_waterfall:
		_set_uniform_if_present(material_waterfall, "rows", waterfall_rows)
	if material_basic_audio_shader:
		_set_uniform_if_present(material_basic_audio_shader, "wf_rows", waterfall_rows)

# -----------------------------------------------------------------------------------
# Tracklist overlay implementation (NEW)
# -----------------------------------------------------------------------------------

func _build_overlay() -> void:
	var layer := $CanvasLayer
	if layer == null:
		push_error("CanvasLayer not found; cannot build overlay.")
		return

	# Title/time shared settings
	_label_settings = LabelSettings.new()
	_label_settings.font_size = overlay_font_size
	_label_settings.outline_size = overlay_outline_size
	_label_settings.outline_color = overlay_outline_color
	_label_settings.font_color = overlay_color
	_label_settings.shadow_color = Color(0,0,0,0.5)
	_label_settings.shadow_offset = Vector2(2,2)

	# Credit settings
	_credit_settings = LabelSettings.new()
	_credit_settings.font_size = credit_font_size
	_credit_settings.outline_size = credit_outline_size
	_credit_settings.outline_color = credit_outline_color
	_credit_settings.font_color = credit_color
	_credit_settings.shadow_color = Color(0,0,0,0.5)
	_credit_settings.shadow_offset = Vector2(2,2)

	# Credit (lower-left)
	_credit_label = Label.new()
	_credit_label.name = "Credit"
	_credit_label.label_settings = _credit_settings
	_credit_label.text = credit_text
	_credit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_credit_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_credit_label.anchor_left = 0.0;  _credit_label.anchor_right = 0.0
	_credit_label.anchor_top  = 1.0;  _credit_label.anchor_bottom = 1.0
	_credit_label.offset_left = overlay_margin
	_credit_label.offset_right = overlay_margin + 280
	_credit_label.offset_bottom = -overlay_margin
	_credit_label.offset_top = _credit_label.offset_bottom - credit_font_size
	layer.add_child(_credit_label)

	# Title (lower-left, above credit)
	_title_label = Label.new()
	_title_label.name = "TrackTitle"
	_title_label.label_settings = _label_settings
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_title_label.anchor_left = 0.0;  _title_label.anchor_right = 0.0
	_title_label.anchor_top  = 1.0;  _title_label.anchor_bottom = 1.0
	var lift := 0
	if credit_enabled:
		lift = credit_font_size + overlay_gap
	_title_label.offset_left = overlay_margin
	_title_label.offset_right = overlay_margin + 520
	_title_label.offset_bottom = -overlay_margin - lift
	_title_label.offset_top = _title_label.offset_bottom - overlay_font_size
	_title_label.text = ""
	layer.add_child(_title_label)

	# Time (corner controlled below)
	_time_label = Label.new()
	_time_label.name = "TrackElapsed"
	_time_label.label_settings = _label_settings
	_time_label.text = "00:00"
	layer.add_child(_time_label)
	_position_time_label()

func _position_time_label() -> void:
	if _time_label == null:
		return
	match playtime_corner:
		PlaytimeCorner.UPPER_RIGHT:
			_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_time_label.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
			_time_label.anchor_left = 1.0; _time_label.anchor_right = 1.0
			_time_label.anchor_top = 0.0;  _time_label.anchor_bottom = 0.0
			_time_label.offset_left = -200
			_time_label.offset_right = -overlay_margin
			_time_label.offset_top = overlay_margin
			_time_label.offset_bottom = overlay_margin + overlay_font_size
		PlaytimeCorner.LOWER_LEFT:
			# Stack: credit (bottom) → title → time
			_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_time_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
			_time_label.anchor_left = 0.0; _time_label.anchor_right = 0.0
			_time_label.anchor_top = 1.0;  _time_label.anchor_bottom = 1.0
			var lift_credit := 0
			if credit_enabled:
				lift_credit = credit_font_size + overlay_gap
			# time sits above title by gap + title height
			var lift_total := lift_credit + overlay_font_size + overlay_gap
			_time_label.offset_left = overlay_margin
			_time_label.offset_right = overlay_margin + 200
			_time_label.offset_bottom = -overlay_margin - lift_total
			_time_label.offset_top = _time_label.offset_bottom - overlay_font_size

func _update_overlay_visibility() -> void:
	var v := overlay_enabled
	if _title_label:  _title_label.visible  = v
	if _time_label:   _time_label.visible   = v
	if _credit_label: _credit_label.visible = v and credit_enabled

func _parse_tracklist() -> void:
	_cues.clear()
	var lines: PackedStringArray = []

	if tracklist_path != "":
		var f := FileAccess.open(tracklist_path, FileAccess.READ)
		if f:
			while not f.eof_reached():
				lines.append(f.get_line())
			f.close()
		else:
			push_warning("Tracklist file not found: %s. Falling back to inline lines." % tracklist_path)

	if lines.is_empty():
		lines = tracklist_lines

	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		var sp := line.find(" ")
		if sp < 0:
			continue

		var ts := line.substr(0, sp).strip_edges()
		var rest := line.substr(sp + 1).strip_edges()

		var title := rest
		var shader_name := ""
		var params := {}

		# Look for directives after '|'
		if rest.find("|") >= 0:
			var parts := rest.split("|")
			title = parts[0].strip_edges()
			for i in range(1, parts.size()):
				var seg := parts[i].strip_edges()
				if seg.begins_with("shader="):
					shader_name = seg.substr("shader=".length()).strip_edges()
				elif seg.begins_with("set="):
					var json_txt := seg.substr("set=".length()).strip_edges()
					var obj = JSON.parse_string(json_txt)
					if typeof(obj) == TYPE_DICTIONARY:
						params = obj
					else:
						push_warning("Bad JSON in set=: %s" % json_txt)

		var sec := _parse_timestamp_to_seconds(ts)
		if sec < 0.0:
			continue

		_cues.append({
			"t": sec,
			"title": title,
			"shader": shader_name,
			"params": params
		})

	_cues.sort_custom(func(a, b): return a["t"] < b["t"])
	_current_cue_idx = -1
	_last_play_pos = 0.0
	_resume_from_pos = 0.0
	_update_track_overlay(_last_play_pos)

func apply_tracklist_entry(entry: Dictionary) -> void:
	if entry == null or entry.is_empty():
		return
	if !_cues.is_empty():
		_update_track_overlay(_last_play_pos)
		return
	var shader_name := String(entry.get("shader", ""))
	if shader_name != "":
		set_shader_by_name(shader_name)
	var params = entry.get("params", {})
	if params is Dictionary and (params as Dictionary).size() > 0:
		_apply_shader_params(params)
	var title := String(entry.get("title", ""))
	if title != "" and _title_label:
		_title_label.text = title
	if _time_label:
		_time_label.text = _format_clock(_last_play_pos)

func _parse_timestamp_to_seconds(ts: String) -> float:
	# supports M:SS, MM:SS, H:MM:SS
	var parts := ts.split(":")
	if parts.is_empty():
		return -1.0
	for i in range(parts.size()):
		parts[i] = parts[i].strip_edges()
	var h := 0
	var m := 0
	var s := 0
	if parts.size() == 2:
		m = int(parts[0])
		s = int(parts[1])
	elif parts.size() == 3:
		h = int(parts[0])
		m = int(parts[1])
		s = int(parts[2])
	else:
		return -1.0
	if m < 0 or s < 0 or s >= 60:
		return -1.0
	return float(h * 3600 + m * 60 + s)

func _format_clock(sec: float) -> String:
	if sec < 0.0:
		sec = 0.0
	var total := int(sec)
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h == 0:
		return "%02d:%02d" % [m, s]
	else:
		return "%02d:%02d:%02d" % [h, m, s]


func _find_current_cue_index(now_sec: float) -> int:
	if _cues.is_empty():
		return -1
	var idx := -1
	for i in range(_cues.size()):
		if float(_cues[i]["t"]) <= now_sec:
			idx = i
		else:
			break
	return max(idx, 0)

func _get_effective_playhead_time() -> float:
	if player == null or player.stream == null:
		return _last_play_pos
	if player.playing:
		return player.get_playback_position()
	if _resume_from_pos > 0.0:
		return _resume_from_pos
	return _last_play_pos

func _update_track_overlay(now_sec: float) -> void:
	_update_overlay_visibility()
	if not overlay_enabled or _title_label == null or _time_label == null:
		return

	if _cues.is_empty():
		_title_label.text = ""
	else:
		var idx := _find_current_cue_index(now_sec)
		if idx != _current_cue_idx:
			_current_cue_idx = idx
			var cue = _cues[idx]
			_title_label.text = String(cue["title"])

			# --- NEW: apply shader + params if present ---
			var sh := String(cue.get("shader", ""))
			if sh != "":
				set_shader_by_name(sh)
			var p = cue.get("params", {})
			if p is Dictionary and (p as Dictionary).size() > 0:
				_apply_shader_params(p)

	_time_label.text = _format_clock(now_sec)


func set_paused_playback_position(pos: float) -> void:
	_last_play_pos = max(pos, 0.0)
	_resume_from_pos = _last_play_pos
	_update_track_overlay(_last_play_pos)


func get_current_cue_start_time() -> float:
	if _cues.is_empty():
		return 0.0
	var idx := _find_current_cue_index(_last_play_pos)
	if idx < 0 or idx >= _cues.size():
		return 0.0
	return float(_cues[idx]["t"])


func _notification_tracklist_restyle() -> void:
	# Re-apply settings
	if _label_settings:
		_label_settings.font_size = overlay_font_size
		_label_settings.outline_size = overlay_outline_size
		_label_settings.outline_color = overlay_outline_color
		_label_settings.font_color = overlay_color
	if _credit_settings:
		_credit_settings.font_size = credit_font_size
		_credit_settings.outline_size = credit_outline_size
		_credit_settings.outline_color = credit_outline_color
		_credit_settings.font_color = credit_color
	if _credit_label:
		_credit_label.text = credit_text
	# Reposition stacked labels
	var layer := $CanvasLayer
	if layer:
		# credit
		if _credit_label:
			_credit_label.offset_left = overlay_margin
			_credit_label.offset_right = overlay_margin + 280
			_credit_label.offset_bottom = -overlay_margin
			_credit_label.offset_top = _credit_label.offset_bottom - credit_font_size
		# title above credit
		if _title_label:
			var lift := 0
			if credit_enabled:
				lift = credit_font_size + overlay_gap
			_title_label.offset_left = overlay_margin
			_title_label.offset_right = overlay_margin + 520
			_title_label.offset_bottom = -overlay_margin - lift
			_title_label.offset_top = _title_label.offset_bottom - overlay_font_size
	_position_time_label()
	_update_overlay_visibility()


func _skip_to_next_cue() -> void:
	if _cues.is_empty() or player == null or player.stream == null:
		return

	var now := _get_effective_playhead_time()
	var idx := _find_current_cue_index(now)
	if idx == -1:
		return

	var next_idx := idx + 1
	while next_idx < _cues.size() and float(_cues[next_idx]["t"]) <= now + 0.05:
		next_idx += 1
	if next_idx >= _cues.size():
		return
	_seek_to_cue(next_idx)


func _skip_to_previous_cue() -> void:
	if _cues.is_empty() or player == null or player.stream == null:
		return

	var now := _get_effective_playhead_time()
	var idx := _find_current_cue_index(now)
	if idx == -1:
		return

	var cue_time := float(_cues[idx]["t"])
	var target_idx := idx
	if now - cue_time <= 1.0:
		target_idx = max(0, idx - 1)

	_seek_to_cue(target_idx)


func _seek_to_cue(idx: int) -> void:
	if idx < 0 or idx >= _cues.size() or player == null or player.stream == null:
		return

	var cue = _cues[idx]
	var t := float(cue["t"])
	player.seek(t)
	_last_play_pos = t
	if player.playing:
		_resume_from_pos = 0.0
	else:
		_resume_from_pos = t
	_update_track_overlay(t)

# Replace your _init_capture() with this:
func _init_capture() -> void:
	if _offline_mode:
			return
	if bus_idx < 0:
		bus_idx = AudioServer.get_bus_index(target_bus_name)

	# If you set capture_slot in the Inspector, it wins.
	if capture_slot >= 0:
		var eff := AudioServer.get_bus_effect(bus_idx, capture_slot)
		capture = eff as AudioEffectCapture
		if capture == null:
			push_warning("Slot %d on bus '%s' is not Capture. Got: %s"
				% [capture_slot, target_bus_name, str(eff)])
			return
	else:
		# Auto-detect first Capture on the bus.
		var count := AudioServer.get_bus_effect_count(bus_idx)
		for i in count:
			var eff := AudioServer.get_bus_effect(bus_idx, i)
			if eff is AudioEffectCapture:
				capture = eff
				capture_slot = i
				break
		if capture == null:
			push_warning("No Capture on bus '%s'. Add 'Capture' (last)." % target_bus_name)
			return

	# Ensure the ring buffer can actually hold audio
	# (in seconds; adjust if you want longer)
	if capture.buffer_length < 0.08:
		capture.buffer_length = 0.12

	print("Capture OK at slot %d on bus '%s' (buffer=%.3fs)"
		% [capture_slot, target_bus_name, capture.buffer_length])


func _setup_waveform_resources() -> void:
	var w = max(1, min(waveform_width, spectrum_bar_count))
	_wave_img = Image.create(w, 1, false, Image.FORMAT_R8)
	_wave_tex = ImageTexture.create_from_image(_wave_img)

# Replace your _update_waveform_texture() with this:
func _update_waveform_texture() -> void:
	if _offline_mode:
			_update_waveform_texture_offline()
			return
	if !enable_waveform_capture or capture == null:
			return
	if _wave_img == null:
		_setup_waveform_resources()
	if _wave_img == null:
		return

	var w := _wave_img.get_width()
	var frames: PackedVector2Array = capture.get_buffer(w)
	var count := frames.size()
	if count == 0:
		return

	# Write PCM [-1..1] mapped to [0..1] into row 0
	for x in range(w):
		var s
		if (x < count):
			s = frames[x].x
		else:  s =0.0
		var v = 0.5 + 0.5 * clamp(s, -1.0, 1.0)
		_wave_img.set_pixel(x, 0, Color(v, 0, 0, 1))

	_wave_tex.update(_wave_img)  # push to GPU

func _update_waveform_texture_offline() -> void:
		if _wave_img == null:
				_setup_waveform_resources()
				if _wave_img == null:
						return
		if _offline_wave_samples.is_empty() or _offline_wave_rate <= 0.0:
				return

		var w := _wave_img.get_width()
		if w <= 0:
				return

		var end_idx := int(round(_offline_playhead * _offline_wave_rate))
		var start_idx := end_idx - w + 1
		for x in range(w):
				var idx := start_idx + x
				if idx < 0:
						idx = 0
				if idx >= _offline_wave_samples.size():
						idx = _offline_wave_samples.size() - 1
				var sample := 0.0
				if idx >= 0 and idx < _offline_wave_samples.size():
					sample = _offline_wave_samples[idx]
				var v = 0.5 + 0.5 * clamp(sample, -1.0, 1.0)
				_wave_img.set_pixel(x, 0, Color(v, 0, 0, 1))

		_wave_tex.update(_wave_img)
