class_name HudController
extends Control

## Draws the military arcade HUD:
## - 360-degree Top Compass Tape & Bottom-Right Phosphor Radar Scope
## - Dynamic Weapon Crosshairs (30mm Twin Autocannon, 105mm Ballistic Sight, CIWS, Sidearm)
## - 3D-Projected SAM Lock-On Diamond & Parachute Supply Crate Target Brackets
## - Floating Kill Score Popups, Hitmarkers, Directional Damage Arcs, and Menus

signal start_mission_requested()
signal next_wave_requested()
signal upgrade_purchased(upgrade_id: String, cost: int)
signal resume_requested()
signal sensitivity_changed(new_sens: float)

var turret: Node3D
var combat: Node3D

# Live HUD state
var bunker_hp: float = 100.0
var bunker_max_hp: float = 100.0
var score: int = 0
var high_score: int = 0
var streak: int = 0
var multiplier: int = 1
var current_wave: int = 1
var time_of_day_name: String = "0600 HRS - DAWN ASSAULT"
var wave_killed: int = 0
var wave_total: int = 20
# Set when a touchscreen is detected: radar moves top-right to make room for touch buttons
var touch_mode: bool = false: set = _set_touch_mode
var _menu_state: String = "none"

# Transient HUD feedback timers
var _hitmarker_timer: float = 0.0
var _ricochet_warn_timer: float = 0.0
var _hull_warn_timer: float = 0.0
var _air_hint_timer: float = 0.0
var _coastal_gun_btn: Button
# Exposed for the web test hook (tools/mobile-test)
var start_button: Button
var resume_button: Button
var _banner_text: String = ""
var _banner_color: Color = Color(1.0, 0.88, 0.25)
var _banner_timer: float = 0.0
var _damage_flash: float = 0.0
var _damage_angle: float = 0.0
var _radar_sweep_angle: float = 0.0
var _floating_texts: Array[Dictionary] = []

# Interactive Menu Panels
var title_panel: PanelContainer
var shop_panel: PanelContainer
var pause_panel: PanelContainer
var gameover_panel: PanelContainer
var shop_score_label: Label
var gameover_stats_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_menus()

func show_banner(text: String, color: Color = Color(1.0, 0.88, 0.25), duration: float = 3.0) -> void:
	_banner_text = text
	_banner_color = color
	_banner_timer = duration

func trigger_hitmarker() -> void:
	_hitmarker_timer = 0.14

func trigger_ricochet_warning() -> void:
	_ricochet_warn_timer = 1.4

func trigger_hull_warning() -> void:
	_hull_warn_timer = 1.8

func trigger_air_armor_hint() -> void:
	_air_hint_timer = 1.8

## 8-point compass name for a world position (N = out to sea, -Z)
func bearing_name(world_pos: Vector3) -> String:
	var ang: float = atan2(world_pos.x, -world_pos.z)
	var names: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[posmod(roundi(ang / (PI / 4.0)), 8)]

## Jets still on their attack run, with seconds until they can fire
func _inbound_jets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in combat.units:
		if u["type_name"] != "STRIKE FIGHTER" or u.get("escaped", false) or u["unloaded"] or not is_instance_valid(u["node"]):
			continue
		var p: Vector3 = u["node"].global_position
		var eta: float = maxf(0.0, (Vector2(p.x, p.z).length() - combat.JET_ATTACK_DIST) / maxf(u["speed"], 1.0))
		out.append({"pos": p, "eta": eta})
	return out

func trigger_damage_indicator(source_pos: Vector3) -> void:
	_damage_flash = 0.65
	if turret != null:
		var world_angle: float = atan2(source_pos.x, -source_pos.z)
		_damage_angle = wrapf(world_angle + turret.yaw, -PI, PI)

func add_floating_popup(world_pos: Vector3, text: String, color: Color = Color(1.0, 0.92, 0.35)) -> void:
	_floating_texts.append({
		"world_pos": world_pos,
		"text": text,
		"color": color,
		"age": 0.0,
		"duration": 1.35
	})

func set_menu_state(state: String) -> void:
	_menu_state = state
	title_panel.visible = (state == "title")
	shop_panel.visible = (state == "shop")
	pause_panel.visible = (state == "pause")
	gameover_panel.visible = (state == "gameover")
	if state == "shop" and is_instance_valid(_coastal_gun_btn) and turret != null:
		_coastal_gun_btn.disabled = turret.heavy_gun
		var coastal: Dictionary = _upgrade_defs().filter(func(u: Dictionary) -> bool: return u["id"] == "coastal_gun")[0]
		if turret.heavy_gun:
			_coastal_gun_btn.text = "155MM GUN\nINSTALLED" if touch_mode else "155MM COASTAL GUN — INSTALLED"
		else:
			_coastal_gun_btn.text = coastal["short"] if touch_mode else coastal["title"]
	if state == "shop" and is_instance_valid(shop_score_label):
		if touch_mode:
			shop_score_label.text = "SCORE %d   ·   ARMOR %d%%" % [score, int(round(bunker_hp))]
		else:
			shop_score_label.text = "WAVE %d CLEARED!   |   AVAILABLE COMMAND POINTS (SCORE): %d   |   BUNKER INTEGRITY: %d%%" % [
				current_wave, score, int(round(bunker_hp))
			]
	elif state == "gameover" and is_instance_valid(gameover_stats_label):
		if touch_mode:
			gameover_stats_label.text = "Wave %d\nScore %d   ·   Best %d" % [current_wave, score, high_score]
		else:
			gameover_stats_label.text = "BUNKER OVERRUN ON WAVE %d\nFINAL SCORE: %d   |   HIGH SCORE: %d" % [
				current_wave, score, high_score
			]

func _process(delta: float) -> void:
	_radar_sweep_angle = wrapf(_radar_sweep_angle + delta * 2.8, 0.0, TAU)
	if _hitmarker_timer > 0.0:
		_hitmarker_timer = maxf(0.0, _hitmarker_timer - delta)
	if _ricochet_warn_timer > 0.0:
		_ricochet_warn_timer = maxf(0.0, _ricochet_warn_timer - delta)
	if _hull_warn_timer > 0.0:
		_hull_warn_timer = maxf(0.0, _hull_warn_timer - delta)
	if _air_hint_timer > 0.0:
		_air_hint_timer = maxf(0.0, _air_hint_timer - delta)
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
	if _damage_flash > 0.0:
		_damage_flash = maxf(0.0, _damage_flash - delta * 1.4)

	for i in range(_floating_texts.size() - 1, -1, -1):
		_floating_texts[i]["age"] += delta
		_floating_texts[i]["world_pos"] += Vector3(0.0, 4.5 * delta, 0.0)
		if _floating_texts[i]["age"] >= _floating_texts[i]["duration"]:
			_floating_texts.remove_at(i)

	queue_redraw()

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var center: Vector2 = vp * 0.5
	var font: Font = ThemeDB.fallback_font

	if _damage_flash > 0.0:
		var alpha: float = _damage_flash * 0.35
		draw_rect(Rect2(0, 0, vp.x, 18), Color(0.95, 0.12, 0.08, alpha), true)
		draw_rect(Rect2(0, vp.y - 18, vp.x, 18), Color(0.95, 0.12, 0.08, alpha), true)
		draw_rect(Rect2(0, 0, 18, vp.y), Color(0.95, 0.12, 0.08, alpha), true)
		draw_rect(Rect2(vp.x - 18, 0, 18, vp.y), Color(0.95, 0.12, 0.08, alpha), true)
		var arc_dir := Vector2(sin(_damage_angle), -cos(_damage_angle))
		var indicator_pos: Vector2 = center + arc_dir * 135.0
		draw_circle(indicator_pos, 14.0, Color(1.0, 0.18, 0.12, _damage_flash))

	if turret == null or combat == null or turret.camera == null:
		return

	_draw_3d_target_overlays(font, vp)
	_draw_crosshair(center, font)
	_draw_top_compass_and_wave(vp, font)
	_draw_bottom_left_status(vp, font)
	_draw_radar_scope(vp, font)

	if _banner_timer > 0.0:
		var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
		var b_rect := Rect2(center.x - 310.0, 96.0, 620.0, 38.0)
		draw_rect(b_rect, Color(0.06, 0.10, 0.06, 0.82), true)
		draw_rect(b_rect, Color(_banner_color.r, _banner_color.g, _banner_color.b, pulse), false, 2.0)
		# Shrink long banners to fit the box instead of clipping them
		var b_size: int = 18
		var b_w: float = font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, b_size).x
		if b_w > 590.0:
			b_size = maxi(11, int(floor(b_size * 590.0 / b_w)))
		draw_string(font, Vector2(center.x - 295.0, 121.0), _banner_text, HORIZONTAL_ALIGNMENT_CENTER, 590.0, b_size, _banner_color)

	if _ricochet_warn_timer > 0.0:
		var r_col := Color(1.0, 0.42, 0.15, clampf(_ricochet_warn_timer, 0.0, 1.0))
		draw_string(font, Vector2(center.x - 220.0, center.y + 82.0), "ARMOR DEFLECTED 30MM! PRESS [SPACE] FOR 105MM CANNON!", HORIZONTAL_ALIGNMENT_CENTER, 440.0, 15, r_col)

	if _hull_warn_timer > 0.0:
		var h_col := Color(0.75, 0.82, 0.95, clampf(_hull_warn_timer, 0.0, 1.0))
		draw_string(font, Vector2(center.x - 260.0, center.y + 104.0), "LANDING CRAFT HULL TOO THICK! BUY THE 155MM COASTAL GUN BETWEEN WAVES", HORIZONTAL_ALIGNMENT_CENTER, 520.0, 15, h_col)

	if _air_hint_timer > 0.0:
		var a_col := Color(1.0, 0.45, 0.3, clampf(_air_hint_timer, 0.0, 1.0))
		var a_txt: String = "JET ARMOR SHRUGS OFF 30MM: TAP SAM!" if touch_mode else "JET ARMOR SHRUGS OFF 30MM: FIRE A SAM (RIGHT-CLICK / E)!"
		draw_string_outline(font, Vector2(center.x - 260.0, center.y + 126.0), a_txt, HORIZONTAL_ALIGNMENT_CENTER, 520.0, 17, 4, Color(0, 0, 0, a_col.a * 0.8))
		draw_string(font, Vector2(center.x - 260.0, center.y + 126.0), a_txt, HORIZONTAL_ALIGNMENT_CENTER, 520.0, 17, a_col)

func _draw_3d_target_overlays(font: Font, vp: Vector2) -> void:
	var cam: Camera3D = turret.camera

	# Landing craft hull bars: grey "armored" until the 155mm Coastal Gun can hurt them
	for u in combat.units:
		if u["type_name"] != "LANDING CRAFT" or not is_instance_valid(u["node"]):
			continue
		var bar_pos: Vector3 = u["node"].global_position + Vector3(0.0, 7.5, 0.0)
		if cam.is_position_behind(bar_pos):
			continue
		var sp: Vector2 = cam.unproject_position(bar_pos)
		if sp.x < -60 or sp.x > vp.x + 60 or sp.y < -20 or sp.y > vp.y:
			continue
		var ratio: float = clampf(u["hp"] / u["max_hp"], 0.0, 1.0)
		var fill_col: Color = Color(1.0, 0.32, 0.22) if turret.heavy_gun else Color(0.62, 0.66, 0.72)
		var bar := Rect2(sp - Vector2(36, 0), Vector2(72, 7))
		draw_rect(bar.grow(1.5), Color(0.05, 0.07, 0.05, 0.8), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), fill_col, true)
		var aboard: int = u.get("cargo_list", []).size()
		var tag: String = ("%d ABOARD" % aboard) if aboard > 0 else "EMPTY"
		if not turret.heavy_gun:
			tag += " · ARMORED"
		draw_string(font, sp + Vector2(-70, -5), tag, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 11, fill_col)

	for sc in combat.supply_crates:
		if not is_instance_valid(sc["node"]):
			continue
		var cpos: Vector3 = sc["node"].global_position
		if not cam.is_position_behind(cpos):
			var sp: Vector2 = cam.unproject_position(cpos)
			if sp.x >= 0 and sp.x <= vp.x and sp.y >= 0 and sp.y <= vp.y:
				var col: Color = Color(1.0, 0.88, 0.2) if sc["is_golden"] else Color(0.25, 1.0, 0.55)
				var box := Rect2(sp - Vector2(26, 26), Vector2(52, 52))
				draw_rect(box, col, false, 2.0)
				var lbl: String = "OVERDRIVE CRATE [SHOOT!]" if sc["is_golden"] else "SUPPLY DROP [SHOOT!]"
				draw_string(font, sp + Vector2(-85, -32), lbl, HORIZONTAL_ALIGNMENT_CENTER, 170.0, 13, col)

	var lock_u: Dictionary = turret.lock_target
	if not lock_u.is_empty() and is_instance_valid(lock_u.get("node", null)):
		var upos: Vector3 = lock_u["node"].global_position
		if not cam.is_position_behind(upos):
			var sp: Vector2 = cam.unproject_position(upos)
			var prog: float = turret.lock_progress
			var is_locked: bool = (prog >= 1.0)
			var half_sz: float = lerpf(54.0, 24.0, prog)
			var col: Color = Color(1.0, 0.18, 0.15) if is_locked else Color(1.0, 0.78, 0.18)
			draw_rect(Rect2(sp - Vector2(half_sz, half_sz), Vector2(half_sz * 2.0, half_sz * 2.0)), col, false, 2.5)
			var status_txt: String = ("SAM LOCKED: TAP SAM" if touch_mode else "SAM LOCKED [RMB / E]") if is_locked else ("LOCKING %d%%" % int(prog * 100.0))
			draw_string(font, sp + Vector2(-80, half_sz + 18), status_txt, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 13, col)

	for ft in _floating_texts:
		var wpos: Vector3 = ft["world_pos"]
		if not cam.is_position_behind(wpos):
			var sp: Vector2 = cam.unproject_position(wpos)
			var alpha: float = clampf(1.0 - (ft["age"] / ft["duration"]), 0.0, 1.0)
			var c: Color = ft["color"]
			c.a = alpha
			draw_string(font, sp - Vector2(90, 0), ft["text"], HORIZONTAL_ALIGNMENT_CENTER, 180.0, 15, c)

# Crosshair lines are drawn twice: a dark outline underneath, then the bright
# colour on top, so they stay readable against sand, sky and sea alike
const XH_OUTLINE := Color(0.0, 0.0, 0.0, 0.78)

func _xh_line(a: Vector2, b: Vector2, col: Color, w: float = 2.6) -> void:
	draw_line(a, b, XH_OUTLINE, w + 3.0)
	draw_line(a, b, col, w)

func _xh_arc(c: Vector2, r: float, col: Color, w: float = 2.4) -> void:
	draw_arc(c, r, 0.0, TAU, 40, XH_OUTLINE, w + 3.0)
	draw_arc(c, r, 0.0, TAU, 40, col, w)

func _xh_dot(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + 1.8, XH_OUTLINE)
	draw_circle(c, r, col)

func _draw_crosshair(center: Vector2, font: Font) -> void:
	var col_green := Color(0.35, 1.0, 0.25, 1.0)
	var col_amber := Color(1.0, 0.85, 0.15, 1.0)
	var col_cyan := Color(0.25, 0.95, 1.0, 1.0)

	if turret.overdrive_timer > 0.0:
		_xh_arc(center, 28.0, col_cyan)
		_xh_dot(center, 3.5, col_cyan)
		draw_string_outline(font, center + Vector2(-95, -36), "CIWS OVERDRIVE %.1fs" % turret.overdrive_timer, HORIZONTAL_ALIGNMENT_CENTER, 190.0, 14, 4, XH_OUTLINE)
		draw_string(font, center + Vector2(-95, -36), "CIWS OVERDRIVE %.1fs" % turret.overdrive_timer, HORIZONTAL_ALIGNMENT_CENTER, 190.0, 14, col_cyan)
	elif turret.current_weapon == 0:
		for sx in [-1.0, 1.0]:
			_xh_line(center + Vector2(24 * sx, -14), center + Vector2(10 * sx, -14), col_green)
			_xh_line(center + Vector2(24 * sx, -14), center + Vector2(24 * sx, 14), col_green)
			_xh_line(center + Vector2(24 * sx, 14), center + Vector2(10 * sx, 14), col_green)
		_xh_dot(center, 2.8, col_green)
	elif turret.current_weapon == 1:
		_xh_arc(center, 34.0, col_amber, 2.2)
		_xh_line(center + Vector2(-46, 0), center + Vector2(-12, 0), col_amber)
		_xh_line(center + Vector2(12, 0), center + Vector2(46, 0), col_amber)
		_xh_line(center + Vector2(0, 10), center + Vector2(0, 48), col_amber)
		for tick in [18.0, 30.0, 42.0]:
			_xh_line(center + Vector2(-7, tick), center + Vector2(7, tick), col_amber, 2.0)
		var reload_ratio: float = turret.get_cannon_reload_ratio()
		var bar_w: float = 68.0
		draw_rect(Rect2(center.x - bar_w * 0.5 - 2.0, center.y + 52.0, bar_w + 4.0, 10.0), XH_OUTLINE, true)
		var fill_col: Color = col_amber if reload_ratio >= 1.0 else Color(1.0, 0.35, 0.15)
		draw_rect(Rect2(center.x - bar_w * 0.5, center.y + 54.0, bar_w * reload_ratio, 6.0), fill_col, true)
	else:
		_xh_arc(center, 14.0, col_amber, 2.0)
		_xh_dot(center, 2.2, col_amber)

	if _hitmarker_timer > 0.0:
		var hm_col := Color(1.0, 0.95, 0.4, 1.0)
		_xh_line(center + Vector2(-11, -11), center + Vector2(-4, -4), hm_col)
		_xh_line(center + Vector2(11, -11), center + Vector2(4, -4), hm_col)
		_xh_line(center + Vector2(-11, 11), center + Vector2(-4, 4), hm_col)
		_xh_line(center + Vector2(11, 11), center + Vector2(4, 4), hm_col)

func _draw_top_compass_and_wave(vp: Vector2, font: Font) -> void:
	var comp_w: float = 520.0
	var comp_x: float = (vp.x - comp_w) * 0.5
	var comp_rect := Rect2(comp_x, 12.0, comp_w, 42.0)
	draw_rect(comp_rect, Color(0.05, 0.09, 0.06, 0.82), true)
	draw_rect(comp_rect, Color(0.35, 0.65, 0.28, 0.85), false, 1.8)

	var cardinals: Array[Dictionary] = [
		{"label": "N (SEA)", "ang": 0.0},
		{"label": "NE", "ang": PI * 0.25},
		{"label": "E", "ang": PI * 0.5},
		{"label": "SE", "ang": PI * 0.75},
		{"label": "S (REAR)", "ang": PI},
		{"label": "SW", "ang": -PI * 0.75},
		{"label": "W", "ang": -PI * 0.5},
		{"label": "NW", "ang": -PI * 0.25}
	]
	for c in cardinals:
		var rel: float = wrapf(c["ang"] + turret.yaw, -PI, PI)
		if abs(rel) <= PI * 0.55:
			var nx: float = comp_x + (rel / (PI * 0.55) * 0.5 + 0.5) * comp_w
			draw_line(Vector2(nx, 12.0), Vector2(nx, 20.0), Color(0.55, 0.85, 0.45), 1.5)
			draw_string(font, Vector2(nx - 35.0, 35.0), c["label"], HORIZONTAL_ALIGNMENT_CENTER, 70.0, 13, Color(0.75, 0.98, 0.65))

	for u in combat.units:
		if not is_instance_valid(u["node"]):
			continue
		var upos: Vector3 = u["node"].global_position
		var world_ang: float = atan2(upos.x, -upos.z)
		var rel_ang: float = wrapf(world_ang + turret.yaw, -PI, PI)
		var clamped_ratio: float = clampf(rel_ang / (PI * 0.55), -0.96, 0.96)
		var tx: float = comp_x + (clamped_ratio * 0.5 + 0.5) * comp_w
		var blip_col: Color = Color(1.0, 0.85, 0.2) if u["is_air"] else (Color(1.0, 0.22, 0.18) if u["armor"] == "heavy" else Color(1.0, 0.55, 0.15))
		if u["type_name"] == "STRIKE FIGHTER" and not u.get("escaped", false):
			# Inbound jet: big flashing red compass marker
			var flash: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
			draw_circle(Vector2(tx, 47.0), 7.0, Color(0, 0, 0, 0.7))
			draw_circle(Vector2(tx, 47.0), 5.5, Color(1.0, 0.15, 0.1, flash))
		else:
			draw_circle(Vector2(tx, 47.0), 4.0, blip_col)

	if touch_mode:
		# Compact profile: two big lines instead of three small ones
		var tc_rect := Rect2(16.0, 12.0, 300.0, 84.0)
		draw_rect(tc_rect, Color(0.05, 0.09, 0.06, 0.82), true)
		draw_rect(tc_rect, Color(0.35, 0.65, 0.28, 0.85), false, 1.8)
		draw_string(font, Vector2(28.0, 42.0), "WAVE %d" % current_wave, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 24, Color(0.85, 1.0, 0.72))
		draw_string(font, Vector2(140.0, 42.0), "%d / %d" % [wave_killed, wave_total], HORIZONTAL_ALIGNMENT_RIGHT, 166.0, 22, Color(0.68, 0.92, 0.62))
		draw_string(font, Vector2(28.0, 80.0), "SCORE %d  x%d" % [score, multiplier], HORIZONTAL_ALIGNMENT_LEFT, 280.0, 24, Color(1.0, 0.90, 0.32))
		return

	var tl_rect := Rect2(16.0, 12.0, 310.0, 72.0)
	draw_rect(tl_rect, Color(0.05, 0.09, 0.06, 0.82), true)
	draw_rect(tl_rect, Color(0.35, 0.65, 0.28, 0.85), false, 1.8)
	draw_string(font, Vector2(28.0, 34.0), "WAVE %d  |  %s" % [current_wave, time_of_day_name], HORIZONTAL_ALIGNMENT_LEFT, 290.0, 14, Color(0.85, 1.0, 0.72))
	draw_string(font, Vector2(28.0, 55.0), "SCORE: %07d   (x%d)" % [score, multiplier], HORIZONTAL_ALIGNMENT_LEFT, 290.0, 16, Color(1.0, 0.90, 0.32))
	draw_string(font, Vector2(28.0, 74.0), "HOSTILES NEUTRALIZED: %d / %d" % [wave_killed, wave_total], HORIZONTAL_ALIGNMENT_LEFT, 290.0, 13, Color(0.68, 0.92, 0.62))

func _draw_bottom_left_status(vp: Vector2, font: Font) -> void:
	if touch_mode:
		_draw_bottom_left_status_compact(vp, font)
		return
	var panel_rect := Rect2(16.0, vp.y - 162.0, 375.0, 146.0)
	draw_rect(panel_rect, Color(0.05, 0.09, 0.06, 0.84), true)
	draw_rect(panel_rect, Color(0.35, 0.65, 0.28, 0.85), false, 1.8)

	var hp_ratio: float = clampf(bunker_hp / maxf(bunker_max_hp, 1.0), 0.0, 1.0)
	var hp_col: Color = Color(0.32, 0.95, 0.38) if hp_ratio > 0.5 else (Color(1.0, 0.75, 0.18) if hp_ratio > 0.25 else Color(1.0, 0.2, 0.15))
	draw_string(font, Vector2(28.0, vp.y - 138.0), "BUNKER ARMOR: %d%%" % int(round(bunker_hp)), HORIZONTAL_ALIGNMENT_LEFT, 200.0, 15, hp_col)
	draw_rect(Rect2(190.0, vp.y - 150.0, 185.0, 14.0), Color(0.12, 0.16, 0.12), true)
	draw_rect(Rect2(190.0, vp.y - 150.0, 185.0 * hp_ratio, 14.0), hp_col, true)

	var active_w: String = turret.get_current_weapon_name()
	draw_string(font, Vector2(28.0, vp.y - 112.0), "ACTIVE: %s" % active_w, HORIZONTAL_ALIGNMENT_LEFT, 350.0, 15, Color(1.0, 0.92, 0.35))

	var mg_col: Color = Color(0.75, 1.0, 0.68) if turret.mg_ammo > 120 else Color(1.0, 0.35, 0.25)
	var can_col: Color = Color(0.75, 1.0, 0.68) if turret.cannon_ammo > 10 else Color(1.0, 0.35, 0.25)
	var sam_col: Color = Color(0.75, 1.0, 0.68) if turret.sam_ammo > 2 else Color(1.0, 0.35, 0.25)

	draw_string(font, Vector2(28.0, vp.y - 88.0), "[1/SPACE] 30MM MG: %04d   |   [2/SPACE] %s: %02d" % [turret.mg_ammo, "155MM CG" if turret.heavy_gun else "105MM AT", turret.cannon_ammo], HORIZONTAL_ALIGNMENT_LEFT, 355.0, 14, mg_col if turret.current_weapon == 0 else can_col)
	draw_string(font, Vector2(28.0, vp.y - 66.0), "[RMB / M] HOMING SAMs: %02d   |   [F] NIGHT FLARES: %02d" % [turret.sam_ammo, turret.flare_ammo], HORIZONTAL_ALIGNMENT_LEFT, 355.0, 14, sam_col)
	draw_string(font, Vector2(28.0, vp.y - 44.0), "TOUCH: DRAG TO AIM  |  HOLD FIRE  |  SWAP / SAM / FLARE" if touch_mode else "[3] 9MM BACKUP: INF   |   [ESC] PAUSE / SENSITIVITY", HORIZONTAL_ALIGNMENT_LEFT, 355.0, 12, Color(0.58, 0.78, 0.55))
	draw_string(font, Vector2(28.0, vp.y - 24.0), "TIP: SHOOT PARACHUTE SUPPLY CRATES IN MID-AIR!", HORIZONTAL_ALIGNMENT_LEFT, 355.0, 12, Color(0.95, 0.85, 0.32))

## Phones/tablets: just armor, active weapon and main ammo, in large type
## (SAM and flare counts are already shown on their touch buttons)
func _draw_bottom_left_status_compact(vp: Vector2, font: Font) -> void:
	var panel_rect := Rect2(16.0, vp.y - 124.0, 380.0, 108.0)
	draw_rect(panel_rect, Color(0.05, 0.09, 0.06, 0.84), true)
	draw_rect(panel_rect, Color(0.35, 0.65, 0.28, 0.85), false, 1.8)

	var hp_ratio: float = clampf(bunker_hp / maxf(bunker_max_hp, 1.0), 0.0, 1.0)
	var hp_col: Color = Color(0.32, 0.95, 0.38) if hp_ratio > 0.5 else (Color(1.0, 0.75, 0.18) if hp_ratio > 0.25 else Color(1.0, 0.2, 0.15))
	draw_string(font, Vector2(28.0, vp.y - 94.0), "ARMOR %d%%" % int(round(bunker_hp)), HORIZONTAL_ALIGNMENT_LEFT, 170.0, 22, hp_col)
	draw_rect(Rect2(204.0, vp.y - 110.0, 178.0, 18.0), Color(0.12, 0.16, 0.12), true)
	draw_rect(Rect2(204.0, vp.y - 110.0, 178.0 * hp_ratio, 18.0), hp_col, true)

	draw_string(font, Vector2(28.0, vp.y - 62.0), turret.get_current_weapon_name(), HORIZONTAL_ALIGNMENT_LEFT, 356.0, 21, Color(1.0, 0.92, 0.35))
	var low: bool = (turret.mg_ammo <= 120) if turret.current_weapon == 0 else (turret.cannon_ammo <= 10)
	draw_string(font, Vector2(28.0, vp.y - 30.0), "MG %d   ·   SHELLS %d" % [turret.mg_ammo, turret.cannon_ammo], HORIZONTAL_ALIGNMENT_LEFT, 310.0, 21, Color(1.0, 0.35, 0.25) if low else Color(0.75, 1.0, 0.68))

func _draw_radar_scope(vp: Vector2, font: Font) -> void:
	var r_radius: float = 82.0
	var r_center := Vector2(vp.x - r_radius - 24.0, vp.y - r_radius - 24.0)
	if touch_mode:
		# Top-left under the score panel: the right side belongs to the touch buttons
		r_radius = 70.0
		r_center = Vector2(24.0 + r_radius, 112.0 + r_radius)

	draw_circle(r_center, r_radius + 4.0, Color(0.04, 0.08, 0.05, 0.88))
	draw_arc(r_center, r_radius, 0.0, TAU, 48, Color(0.35, 0.85, 0.32, 0.9), 2.0)
	draw_arc(r_center, r_radius * 0.66, 0.0, TAU, 36, Color(0.25, 0.62, 0.22, 0.55), 1.0)
	draw_arc(r_center, r_radius * 0.33, 0.0, TAU, 24, Color(0.25, 0.62, 0.22, 0.55), 1.0)

	var fov_half: float = deg_to_rad(34.0)
	draw_line(r_center, r_center + Vector2(-sin(fov_half), -cos(fov_half)) * r_radius, Color(0.45, 0.95, 0.42, 0.45), 1.2)
	draw_line(r_center, r_center + Vector2(sin(fov_half), -cos(fov_half)) * r_radius, Color(0.45, 0.95, 0.42, 0.45), 1.2)

	var sweep_vec := Vector2(sin(_radar_sweep_angle), -cos(_radar_sweep_angle)) * r_radius
	draw_line(r_center, r_center + sweep_vec, Color(0.45, 1.0, 0.45, 0.55), 1.8)

	var max_radar_dist: float = 260.0
	for u in combat.units:
		if not is_instance_valid(u["node"]):
			continue
		var upos: Vector3 = u["node"].global_position
		var world_ang: float = atan2(upos.x, -upos.z)
		var rel_ang: float = wrapf(world_ang + turret.yaw, -PI, PI)
		var dist_ratio: float = clampf(Vector2(upos.x, upos.z).length() / max_radar_dist, 0.0, 0.95)
		var b_pos: Vector2 = r_center + Vector2(sin(rel_ang), -cos(rel_ang)) * (dist_ratio * r_radius)

		if u["is_air"]:
			draw_circle(b_pos, 3.8, Color(1.0, 0.90, 0.22))
		elif u["armor"] == "heavy":
			draw_rect(Rect2(b_pos - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), Color(1.0, 0.22, 0.18), true)
		else:
			draw_circle(b_pos, 3.0, Color(1.0, 0.58, 0.18))

	for sc in combat.supply_crates:
		if not is_instance_valid(sc["node"]):
			continue
		var cpos: Vector3 = sc["node"].global_position
		var world_ang: float = atan2(cpos.x, -cpos.z)
		var rel_ang: float = wrapf(world_ang + turret.yaw, -PI, PI)
		var dist_ratio: float = clampf(Vector2(cpos.x, cpos.z).length() / max_radar_dist, 0.0, 0.95)
		var b_pos: Vector2 = r_center + Vector2(sin(rel_ang), -cos(rel_ang)) * (dist_ratio * r_radius)
		draw_circle(b_pos, 4.5, Color(0.25, 1.0, 0.95))

	draw_circle(r_center, 3.5, Color(0.65, 1.0, 0.65))
	_draw_air_raid_warning(r_center, r_radius, font)
	if not touch_mode:
		draw_string(font, r_center + Vector2(-75.0, -r_radius - 10.0), "360° TACTICAL RADAR", HORIZONTAL_ALIGNMENT_CENTER, 150.0, 12, Color(0.65, 0.95, 0.58))

## Early warning for jets: they're picked up far beyond normal radar range, so
## show each one as a flashing red arrowhead on the radar rim at its true bearing,
## flash the rim, and print the direction + seconds until it can attack.
func _draw_air_raid_warning(r_center: Vector2, r_radius: float, font: Font) -> void:
	var jets: Array[Dictionary] = _inbound_jets()
	if jets.is_empty():
		return
	var flash: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	var red := Color(1.0, 0.15, 0.1)
	draw_arc(r_center, r_radius + 3.0, 0.0, TAU, 48, Color(red.r, red.g, red.b, 0.35 + 0.55 * flash), 3.0)
	var soonest: Dictionary = jets[0]
	for j in jets:
		if j["eta"] < soonest["eta"]:
			soonest = j
		var p: Vector3 = j["pos"]
		var rel: float = wrapf(atan2(p.x, -p.z) + turret.yaw, -PI, PI)
		var dir := Vector2(sin(rel), -cos(rel))
		var side := Vector2(-dir.y, dir.x)
		var tip: Vector2 = r_center + dir * (r_radius - 4.0)
		var base: Vector2 = r_center + dir * (r_radius - 18.0)
		var tri := PackedVector2Array([tip, base + side * 8.0, base - side * 8.0])
		draw_colored_polygon(tri, Color(red.r, red.g, red.b, 0.45 + 0.55 * flash))
		draw_polyline(PackedVector2Array([tip, base + side * 8.0, base - side * 8.0, tip]), Color(0, 0, 0, 0.8), 1.5)

	var eta: float = soonest["eta"]
	var txt: String = "AIR RAID  %s  %s" % [bearing_name(soonest["pos"]), ("%ds" % ceili(eta)) if eta > 0.0 else "NOW!"]
	var fs: int = 20 if touch_mode else 16
	# Below the radar on touch layouts (radar top-left), above it on PC (radar bottom-right)
	var y: float = r_center.y + r_radius + 26.0 if touch_mode else r_center.y - r_radius - 30.0
	var x: float = r_center.x - 110.0
	draw_string_outline(font, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_CENTER, 220.0, fs, 5, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_CENTER, 220.0, fs, Color(1.0, 0.3 + 0.3 * flash, 0.2))

## Phones and tablets get a compact menu profile: fewer words, much larger text
## and thumb-sized buttons. PC keeps the full briefing.
func _set_touch_mode(on: bool) -> void:
	if on == touch_mode:
		return
	touch_mode = on
	if is_inside_tree() and is_instance_valid(title_panel):
		for p in [title_panel, shop_panel, pause_panel, gameover_panel]:
			p.hide()
			p.queue_free()
		_build_menus()
		set_menu_state(_menu_state)

func _build_menus() -> void:
	if touch_mode:
		_build_menus_compact()
	else:
		_build_menus_full()

func _upgrade_defs() -> Array[Dictionary]:
	return [
		{"id": "repair", "cost": 800, "title": "REPAIR BUNKER ARMOR (+35% Hull Integrity) — 800 PTS", "short": "REPAIR ARMOR\n800 PTS"},
		{"id": "ammo_pack", "cost": 600, "title": "EMERGENCY ORDNANCE CRATE (+400 30mm, +25 Shells, +3 SAMs) — 600 PTS", "short": "AMMO CRATE\n600 PTS"},
		{"id": "mg_rate", "cost": 1200, "title": "HIGH-SPEED 30MM ROTARY FEED (+20% MG Fire Rate) — 1200 PTS", "short": "FASTER MG\n1200 PTS"},
		{"id": "coastal_gun", "cost": 8000, "title": "155MM COASTAL GUN (Replaces 105mm — Pierces Landing Craft Hulls) — 8000 PTS", "short": "155MM GUN · SINKS BOATS\n8000 PTS"},
		{"id": "cannon_autoloader", "cost": 1400, "title": "105MM HYDRAULIC AUTOLOADER (+22% Faster Cannon Reload) — 1400 PTS", "short": "FASTER RELOAD\n1400 PTS"},
		{"id": "sam_radar", "cost": 1100, "title": "DOPPLER SAM SEEKER UPGRADE (+30% Faster Missile Lock) — 1100 PTS", "short": "FASTER SAM LOCK\n1100 PTS"},
	]

func _build_menus_full() -> void:
	title_panel = _make_modal_panel(Vector2(680, 460))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 12)
	title_panel.add_child(tv)

	_add_label(tv, "IRON HORIZON", 28, Color(0.85, 1.0, 0.55))
	_add_label(tv, "360° COASTAL BUNKER DEFENSE  —  CLASSIC MILITARY ARCADE EDITION", 15, Color(0.95, 0.85, 0.35))
	_add_label(tv,
		"TACTICAL BRIEFING & CONTROLS:\n" +
		"• MOUSE / WASD: Rotate Turret 360° Horizontally & Pitch Up/Down\n" +
		"• TOUCH: Drag anywhere to aim, hold FIRE, tap SWAP / SAM / FLARE buttons\n" +
		"• LEFT CLICK / [ENTER] (HOLD): Fire Active Primary Weapon\n" +
		"• [SPACE] / [Q] / [1, 2]: Switch between Dual 30mm Autocannon & 105mm Anti-Tank Howitzer\n" +
		"• RIGHT CLICK / [M]: Fire Guided Surface-to-Air Missile (Wait for Red Lock-On Tone!)\n" +
		"• [F] KEY: Launch Parachute Illumination Flare (Crucial for Dusk & Night Missions)\n\n" +
		"SURVIVAL RULES:\n" +
		"1. 30mm MG shreds Infantry, Paratroopers, Aircraft & Incoming Rockets, but RICOCHETS off Tanks/Ships!\n" +
		"2. Troops & tanks land by boat: hit them as the ramp drops! Sinking boats needs the 155mm Coastal Gun\n" +
		"3. Watch your 360° Radar for Chinook Choppers dropping Paratroopers BEHIND your bunker!\n" +
		"4. Shoot friendly Yellow-'X' Parachute Supply Crates BEFORE they hit the ground to resupply!",
		14, Color(0.84, 0.92, 0.80), HORIZONTAL_ALIGNMENT_LEFT
	)
	var start_btn := _make_button("CLICK TO MAN THE BUNKER (START WAVE 1)")
	start_btn.pressed.connect(func() -> void: start_mission_requested.emit())
	tv.add_child(start_btn)
	start_button = start_btn

	shop_panel = _make_modal_panel(Vector2(660, 480))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	shop_panel.add_child(sv)
	_add_label(sv, "SECTOR SECURED — TACTICAL RESUPPLY & BUNKER UPGRADES", 22, Color(0.85, 1.0, 0.55))
	shop_score_label = _add_label(sv, "SCORE: 0", 15, Color(1.0, 0.9, 0.35))

	for upg in _upgrade_defs():
		var u_id: String = upg["id"]
		var u_cost: int = upg["cost"]
		var btn := _make_button(upg["title"])
		btn.pressed.connect(func() -> void: upgrade_purchased.emit(u_id, u_cost))
		if u_id == "coastal_gun":
			_coastal_gun_btn = btn
		sv.add_child(btn)

	var next_btn := _make_button("DEPLOY TO NEXT INVASION WAVE >>")
	next_btn.pressed.connect(func() -> void: next_wave_requested.emit())
	sv.add_child(next_btn)

	pause_panel = _make_modal_panel(Vector2(480, 280))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 14)
	pause_panel.add_child(pv)
	_add_label(pv, "COMBAT PAUSED", 24, Color(0.85, 1.0, 0.55))
	_add_label(pv, "MOUSE AIM SENSITIVITY:", 14, Color(0.85, 0.92, 0.82))
	var sens_slider := HSlider.new()
	sens_slider.min_value = 0.0008
	sens_slider.max_value = 0.0060
	sens_slider.step = 0.0002
	sens_slider.value = 0.0024
	sens_slider.value_changed.connect(func(v: float) -> void: sensitivity_changed.emit(v))
	pv.add_child(sens_slider)

	var resume_btn := _make_button("RESUME COMBAT (LOCK MOUSE)")
	resume_btn.pressed.connect(func() -> void: resume_requested.emit())
	pv.add_child(resume_btn)
	resume_button = resume_btn

	gameover_panel = _make_modal_panel(Vector2(540, 280))
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 16)
	gameover_panel.add_child(gv)
	_add_label(gv, "BUNKER DESTROYED — THE BEACH HAS FALLEN", 22, Color(1.0, 0.32, 0.22))
	gameover_stats_label = _add_label(gv, "", 16, Color(1.0, 0.9, 0.35))
	var retry_btn := _make_button("MAN A NEW BUNKER (PLAY AGAIN)")
	retry_btn.pressed.connect(func() -> void: start_mission_requested.emit())
	gv.add_child(retry_btn)

func _build_menus_compact() -> void:
	var col_title := Color(0.85, 1.0, 0.55)
	var col_text := Color(0.88, 0.95, 0.84)

	title_panel = _make_modal_panel(Vector2(760, 0))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 14)
	title_panel.add_child(tv)
	_add_label(tv, "IRON HORIZON", 44, col_title)
	_add_label(tv, "Hold the hilltop. Stop the beach landing.", 22, Color(0.95, 0.85, 0.35))
	_add_label(tv,
		"DRAG — aim\n" +
		"FIRE — hold to shoot\n" +
		"SWAP — machine gun / cannon\n" +
		"SAM — missile for aircraft\n" +
		"FLARE — light up night waves",
		26, col_text)
	_add_label(tv, "Tanks shrug off the machine gun: use the cannon.", 20, Color(1.0, 0.75, 0.4))
	start_button = _make_button("START", 32, 80)
	start_button.pressed.connect(func() -> void: start_mission_requested.emit())
	tv.add_child(start_button)

	shop_panel = _make_modal_panel(Vector2(820, 0))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	shop_panel.add_child(sv)
	_add_label(sv, "WAVE CLEARED", 36, col_title)
	shop_score_label = _add_label(sv, "", 24, Color(1.0, 0.9, 0.35))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	sv.add_child(grid)
	for upg in _upgrade_defs():
		var u_id: String = upg["id"]
		var u_cost: int = upg["cost"]
		var btn := _make_button(upg["short"], 22, 78)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: upgrade_purchased.emit(u_id, u_cost))
		if u_id == "coastal_gun":
			_coastal_gun_btn = btn
		grid.add_child(btn)
	var next_btn := _make_button("NEXT WAVE  >>", 30, 76)
	next_btn.pressed.connect(func() -> void: next_wave_requested.emit())
	sv.add_child(next_btn)

	pause_panel = _make_modal_panel(Vector2(600, 0))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 18)
	pause_panel.add_child(pv)
	_add_label(pv, "PAUSED", 40, col_title)
	_add_label(pv, "AIM SPEED", 24, col_text)
	var sens_slider := HSlider.new()
	sens_slider.min_value = 0.0008
	sens_slider.max_value = 0.0060
	sens_slider.step = 0.0002
	sens_slider.value = turret.mouse_sensitivity if turret != null else 0.0024
	sens_slider.custom_minimum_size = Vector2(0, 48)
	sens_slider.value_changed.connect(func(v: float) -> void: sensitivity_changed.emit(v))
	pv.add_child(sens_slider)
	resume_button = _make_button("RESUME", 32, 80)
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	pv.add_child(resume_button)

	gameover_panel = _make_modal_panel(Vector2(640, 0))
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 18)
	gameover_panel.add_child(gv)
	_add_label(gv, "BUNKER DESTROYED", 40, Color(1.0, 0.32, 0.22))
	gameover_stats_label = _add_label(gv, "", 26, Color(1.0, 0.9, 0.35))
	var retry_btn := _make_button("PLAY AGAIN", 32, 80)
	retry_btn.pressed.connect(func() -> void: start_mission_requested.emit())
	gv.add_child(retry_btn)

func _make_modal_panel(sz: Vector2) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = sz
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.11, 0.07, 0.94)
	sb.border_color = Color(0.45, 0.78, 0.35, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(22)
	pc.add_theme_stylebox_override("panel", sb)
	add_child(pc)
	return pc

func _add_label(parent: Node, txt: String, font_sz: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = align
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", col)
	parent.add_child(lbl)
	return lbl

func _make_button(txt: String, font_sz: int = 15, height: float = 42.0) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, height)
	var sb_norm := StyleBoxFlat.new()
	sb_norm.bg_color = Color(0.16, 0.28, 0.14, 1.0)
	sb_norm.border_color = Color(0.58, 0.88, 0.42, 1.0)
	sb_norm.set_border_width_all(2)
	sb_norm.set_corner_radius_all(4)
	var sb_hover := sb_norm.duplicate()
	sb_hover.bg_color = Color(0.26, 0.44, 0.20, 1.0)
	btn.add_theme_stylebox_override("normal", sb_norm)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_font_size_override("font_size", font_sz)
	btn.add_theme_color_override("font_color", Color(0.95, 1.0, 0.88))
	return btn

