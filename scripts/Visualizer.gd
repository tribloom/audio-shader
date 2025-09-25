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

@export var target_bus_name: String = "Music"
@export var analyzer_slot: int = 0

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
@export var material_basic_audio_shader: ShaderMaterial   # NEW
@export var material_sonic_fusion:     ShaderMaterial     # NEW
@export var material_power_particle: ShaderMaterial # NEW
@export var material_fractal_colors: ShaderMaterial # NEW
@export var material_bubbles: ShaderMaterial # NEW

enum Mode {
	CHROMA, CIRCLE, BARS, LINE, WATERFALL, AURORA, UNIVERSE, UNIVERSE_ALT,
	BASIC_AUDIO,
	POWER_PARTICLE, # NEW
	SONIC_FUSION,
	FRACTAL_COLORS,
	BUBBLES
}

@export var start_mode: Mode = Mode.CHROMA

@onready var player: AudioStreamPlayer = $AudioStreamPlayer
@onready var color_rect: ColorRect = $CanvasLayer/ColorRect

var analyzer: AudioEffectSpectrumAnalyzerInstance
var bus_idx: int = -1
var started := false
var mode: Mode

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
	_apply_mode_material()

	player.bus = target_bus_name
	bus_idx = AudioServer.get_bus_index(target_bus_name)
	if bus_idx == -1:
		push_error("Bus '%s' not found." % target_bus_name)
		return

	call_deferred("_init_analyzer")

	_setup_spectrum_resources()
	_setup_waterfall_resources()
	_bind_all_material_textures()
	_update_aspect()

	_build_overlay()
	_parse_tracklist()
	_update_overlay_visibility()

func _init_analyzer() -> void:
	analyzer = AudioServer.get_bus_effect_instance(bus_idx, analyzer_slot) as AudioEffectSpectrumAnalyzerInstance
	if analyzer == null:
		push_error("No SpectrumAnalyzer on bus '%s' slot %d." % [target_bus_name, analyzer_slot])

func _input(event: InputEvent) -> void:
	if !started and event is InputEventMouseButton and event.pressed:
		if player.stream:
			player.play()
			started = true
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		_toggle_mode()

func _toggle_mode() -> void:
	match mode:
		Mode.CHROMA:        mode = Mode.CIRCLE
		Mode.CIRCLE:        mode = Mode.BARS
		Mode.BARS:          mode = Mode.LINE
		Mode.LINE:          mode = Mode.WATERFALL
		Mode.WATERFALL:     mode = Mode.AURORA
		Mode.AURORA:        mode = Mode.UNIVERSE
		Mode.UNIVERSE:      mode = Mode.UNIVERSE_ALT
		Mode.UNIVERSE_ALT:  mode = Mode.BASIC_AUDIO
		Mode.BASIC_AUDIO:   mode = Mode.POWER_PARTICLE   # NEW
		Mode.POWER_PARTICLE:mode = Mode.SONIC_FUSION     # NEW
		Mode.SONIC_FUSION:  mode = Mode.FRACTAL_COLORS
		Mode.FRACTAL_COLORS:mode = Mode.BUBBLES
		Mode.BUBBLES:      mode = Mode.CHROMA
	_apply_mode_material()
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
		Mode.POWER_PARTICLE:    color_rect.material = material_power_particle   # NEW
		Mode.SONIC_FUSION:      color_rect.material = material_sonic_fusion
		Mode.FRACTAL_COLORS:    color_rect.material = material_fractal_colors
		Mode.BUBBLES:           color_rect.material = material_bubbles
	_bind_all_material_textures()


func _process(dt: float) -> void:
	if analyzer == null or color_rect.material == null:
		_update_track_overlay(0.0)
		return

	if !started:
		_update_track_overlay(0.0)
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

	_update_aspect()

	# Overlay time is total elapsed
	var play_pos := player.get_playback_position()
	_update_track_overlay(play_pos)

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
	var s := get_viewport_rect().size
	if s.y <= 0.0: return
	var aspect := s.x / s.y

	var active := color_rect.material as ShaderMaterial
	if active:
		active.set_shader_parameter("aspect", aspect)

	for m in [
		material_bars, material_line, material_waterfall, material_aurora,
		material_universe, material_universe_alt,
		material_basic_audio_shader, material_sonic_fusion
	]:
		if m:
			m.set_shader_parameter("aspect", aspect)
			m.set_shader_parameter("bar_count", spectrum_bar_count)
	if material_waterfall:
		material_waterfall.set_shader_parameter("rows", waterfall_rows)
	if material_basic_audio_shader:
		material_basic_audio_shader.set_shader_parameter("wf_rows", waterfall_rows)

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
		material_basic_audio_shader,
		material_sonic_fusion, material_fractal_colors,
		material_bubbles		
	]:
		if m:
			m.set_shader_parameter("spectrum_tex", _spec_tex)
			m.set_shader_parameter("bar_count", spectrum_bar_count)
	if material_waterfall:
		material_waterfall.set_shader_parameter("waterfall_tex", _wf_tex)
		material_waterfall.set_shader_parameter("bar_count", spectrum_bar_count)
		material_waterfall.set_shader_parameter("rows", waterfall_rows)
	if material_basic_audio_shader:
		material_basic_audio_shader.set_shader_parameter("waterfall_tex", _wf_tex)
		material_basic_audio_shader.set_shader_parameter("wf_rows", waterfall_rows)
		# head_norm set per-frame in _process()

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
		# Split on first space only (titles may contain " - " etc.)
		var sp := line.find(" ")
		if sp < 0:
			continue
		var ts := line.substr(0, sp).strip_edges()
		var title := line.substr(sp + 1).strip_edges()
		var sec := _parse_timestamp_to_seconds(ts)
		if sec < 0.0:
			continue
		_cues.append({ "t": sec, "title": title })

	_cues.sort_custom(func(a, b): return a["t"] < b["t"])
	_current_cue_idx = -1

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

func _update_track_overlay(now_sec: float) -> void:
	_update_overlay_visibility()
	if not overlay_enabled:
		return
	if _title_label == null or _time_label == null:
		return

	if _cues.is_empty():
		_title_label.text = ""
	else:
		var idx := _find_current_cue_index(now_sec)
		if idx != _current_cue_idx:
			_current_cue_idx = idx
			_title_label.text = String(_cues[idx]["title"])

	_time_label.text = _format_clock(now_sec)

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
