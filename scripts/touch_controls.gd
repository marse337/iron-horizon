class_name TouchControls
extends Control

## On-screen controls for phones & tablets. Drag anywhere (off the buttons) to aim;
## hold FIRE for the primary weapon; tap SWAP / SAM / FLARE / pause. Multi-touch,
## so you can aim with one thumb while holding FIRE with the other. Hidden on
## devices without a touchscreen until a real touch arrives.

signal touch_mode_enabled()
signal pause_pressed()

var turret: Node3D
## True only while a wave is being played (buttons hidden in menus)
var active: bool = false
var touch_mode: bool = false
var fire_held: bool = false
var aim_sensitivity_mult: float = 1.0

var _sam_queued: bool = false
var _flare_queued: bool = false
var _touches: Dictionary = {} # touch index -> button id, or "aim"
# Last known position per touch index. The web build computes ScreenDrag.relative
# against the wrong finger's previous position when 2+ fingers are down (e.g. aiming
# while holding FIRE), which made the view jump; we derive deltas ourselves instead.
var _last_pos: Dictionary = {}
## Time of the most recent touch event; mobile browsers send imitation mouse
## events (move/down/up) just after a tap, which the game must ignore
var last_touch_msec: int = -100000

func is_recent_touch() -> bool:
	return not _touches.is_empty() or Time.get_ticks_msec() - last_touch_msec < 800
var _flash: Dictionary = {}   # button id -> remaining highlight time

const COL_FIRE := Color(0.95, 0.25, 0.18)
const COL_BTN := Color(0.45, 1.0, 0.38)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.is_touchscreen_available():
		_enable_touch_mode()

func _enable_touch_mode() -> void:
	if touch_mode:
		return
	touch_mode = true
	touch_mode_enabled.emit()

func set_active(on: bool) -> void:
	active = on
	if not on:
		_touches.clear()
		_last_pos.clear()
		fire_held = false

func consume_sam() -> bool:
	var q: bool = _sam_queued
	_sam_queued = false
	return q

func consume_flare() -> bool:
	var q: bool = _flare_queued
	_flare_queued = false
	return q

func is_portrait() -> bool:
	var vp: Vector2 = get_viewport_rect().size
	return vp.y > vp.x

func _buttons() -> Array[Dictionary]:
	var vp: Vector2 = get_viewport_rect().size
	var fire_c := Vector2(vp.x - 150.0, vp.y - 150.0)
	return [
		{"id": "fire", "pos": fire_c, "r": 92.0},
		{"id": "swap", "pos": fire_c + Vector2(-195.0, 52.0), "r": 52.0},
		{"id": "sam", "pos": fire_c + Vector2(-158.0, -128.0), "r": 52.0},
		{"id": "flare", "pos": fire_c + Vector2(0.0, -195.0), "r": 44.0},
		{"id": "pause", "pos": Vector2(vp.x - 48.0, 46.0), "r": 32.0},
	]

func _hit_button(p: Vector2) -> String:
	for b in _buttons():
		# Slightly generous hit area so thumbs don't miss
		if p.distance_to(b["pos"]) <= b["r"] * 1.15:
			return b["id"]
	return "aim"

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		last_touch_msec = Time.get_ticks_msec()
	if event is InputEventScreenTouch:
		_enable_touch_mode()
		if event.pressed:
			if not active or is_portrait():
				return
			var id: String = _hit_button(event.position)
			_touches[event.index] = id
			_last_pos[event.index] = event.position
			_flash[id] = 0.18
			match id:
				"fire":
					fire_held = true
				"swap":
					turret.toggle_primary_weapon()
				"sam":
					_sam_queued = true
				"flare":
					_flare_queued = true
				"pause":
					pause_pressed.emit()
			get_viewport().set_input_as_handled()
		else:
			var released: String = _touches.get(event.index, "")
			_touches.erase(event.index)
			_last_pos.erase(event.index)
			if released == "fire":
				fire_held = _touches.values().has("fire")
	elif event is InputEventScreenDrag and active:
		if _touches.get(event.index, "") == "aim" and _last_pos.has(event.index):
			var delta: Vector2 = event.position - _last_pos[event.index]
			turret.apply_mouse_delta(delta * aim_sensitivity_mult)
		_last_pos[event.index] = event.position
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	for id in _flash.keys():
		_flash[id] -= delta
		if _flash[id] <= 0.0:
			_flash.erase(id)
	if touch_mode:
		queue_redraw()

func _draw() -> void:
	if not touch_mode:
		return
	var vp: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font

	if is_portrait():
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.05, 0.03, 0.94), true)
		var c: Vector2 = vp * 0.5
		# Simple phone glyph turning sideways
		draw_rect(Rect2(c + Vector2(-28, -110), Vector2(56, 96)), COL_BTN, false, 3.0)
		draw_arc(c + Vector2(0, -62), 78.0, -0.4, 0.9, 16, COL_BTN, 3.0)
		draw_string(font, Vector2(0, c.y + 30.0), "ROTATE YOUR DEVICE", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 30, COL_BTN)
		draw_string(font, Vector2(0, c.y + 66.0), "Iron Horizon plays in landscape", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, Color(0.8, 0.9, 0.78))
		return

	if not active or turret == null:
		return

	for b in _buttons():
		var id: String = b["id"]
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var pressed: bool = _flash.has(id) or _touches.values().has(id)
		var col: Color = COL_FIRE if id == "fire" else COL_BTN
		draw_circle(pos, r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.55 if pressed else 0.32))
		draw_arc(pos, r, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.95 if pressed else 0.6), 3.0)

		var label: String = ""
		var sub: String = ""
		match id:
			"fire":
				label = "FIRE"
				# Cannon reload ring
				if turret.current_weapon == 1:
					var ratio: float = turret.get_cannon_reload_ratio()
					draw_arc(pos, r - 9.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 40, Color(1.0, 0.85, 0.3, 0.9), 5.0)
			"swap":
				label = "SWAP"
				match turret.current_weapon:
					0: sub = "30MM"
					1: sub = "155MM" if turret.heavy_gun else "105MM"
					_: sub = "9MM"
			"sam":
				label = "SAM"
				sub = "%d" % turret.sam_ammo
			"flare":
				label = "FLARE"
				sub = "%d" % turret.flare_ammo
			"pause":
				# Pause glyph
				draw_rect(Rect2(pos + Vector2(-10, -12), Vector2(7, 24)), COL_BTN, true)
				draw_rect(Rect2(pos + Vector2(3, -12), Vector2(7, 24)), COL_BTN, true)
		if not label.is_empty():
			var fs: int = 26 if id == "fire" else 17
			var y_off: float = 9.0 if sub.is_empty() else 2.0
			draw_string(font, pos + Vector2(-r, y_off), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, 0.92))
			if not sub.is_empty():
				draw_string(font, pos + Vector2(-r, 22.0), sub, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, Color(0.85, 0.95, 0.8, 0.9))
