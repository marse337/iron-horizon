class_name GameManager
extends Node3D

## Main Game Coordinator for Iron Horizon
## Orchestrates Dawn / Day / Dusk / Night cycles, Turret, CombatManager, HUD,
## Audio Synthesizer, and Web-friendly Mouse Capture / Pause state.

const UnitFactoryScript = preload("res://scripts/unit_factory.gd")
const SfxSynthScript = preload("res://scripts/sfx_synth.gd")
const ExplosionManagerScript = preload("res://scripts/explosion_manager.gd")
const CombatManagerScript = preload("res://scripts/combat_manager.gd")
const BunkerTurretScript = preload("res://scripts/bunker_turret.gd")
const HudControllerScript = preload("res://scripts/hud_controller.gd")
const TouchControlsScript = preload("res://scripts/touch_controls.gd")

enum GameState {
	TITLE,
	PLAYING,
	SHOP,
	PAUSED,
	GAMEOVER
}

const SAVE_PATH: String = "user://beachhead_save.cfg"

var state: int = GameState.TITLE
var sfx: Node
var fx: Node3D
var combat: Node3D
var turret: Node3D
var hud: Control
var touch: Control

var world_env: WorldEnvironment
var sun_light: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var shoreline_foam: MeshInstance3D
var ocean_mat: StandardMaterial3D

var bunker_hp: float = 100.0
var bunker_max_hp: float = 100.0
var score: int = 0
var high_score: int = 0
var streak: int = 0
var multiplier: int = 1
var current_wave: int = 1

var _sam_queued: bool = false
var _flare_queued: bool = false
# Real (non-touch-emulated) left mouse button, so touching the screen never fires
var _mouse_fire_held: bool = false
# Web test hook (open the page with ?test=1): publishes game state to window.__ih
# for the automated device tests in tools/mobile-test. Off for normal players.
var _test_hooks: bool = false
var _test_hook_timer: float = 0.0
var _wave_time: float = 0.0

func _ready() -> void:
	_load_high_score()
	if OS.has_feature("web"):
		_test_hooks = str(JavaScriptBridge.eval("location.search", true)).contains("test=1")
		# Let web/diag.js know the game actually started (its watchdog explains failures)
		get_tree().process_frame.connect(func() -> void:
			JavaScriptBridge.eval("window.__ihGameStarted && window.__ihGameStarted()", true),
			CONNECT_ONE_SHOT)
	if OS.has_feature("web_ios") or OS.has_feature("web_android"):
		# Phones run this at 2-3x pixel density; drop MSAA and halve the shadow map
		# to ease GPU memory pressure (iOS Safari is strict about it)
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		RenderingServer.directional_shadow_atlas_set_size(1024, true)
	_setup_environment()

	var env_refs: Dictionary = UnitFactoryScript.build_battlefield(self)
	shoreline_foam = env_refs.get("shoreline_foam", null)
	ocean_mat = env_refs.get("ocean_mat", null)

	sfx = SfxSynthScript.new()
	sfx.name = "SfxSynth"
	add_child(sfx)

	fx = ExplosionManagerScript.new()
	fx.name = "ExplosionManager"
	add_child(fx)

	combat = CombatManagerScript.new()
	combat.name = "CombatManager"
	combat.sfx = sfx
	combat.fx = fx
	add_child(combat)

	turret = BunkerTurretScript.new()
	turret.name = "BunkerTurret"
	turret.combat = combat
	turret.sfx = sfx
	turret.fx = fx
	add_child(turret)

	var canvas := CanvasLayer.new()
	canvas.name = "HUDCanvas"
	add_child(canvas)

	hud = HudControllerScript.new()
	hud.name = "HudController"
	hud.turret = turret
	hud.combat = combat
	hud.high_score = high_score
	canvas.add_child(hud)

	touch = TouchControlsScript.new()
	touch.name = "TouchControls"
	touch.turret = turret
	touch.touch_mode_enabled.connect(_on_touch_mode_enabled)
	touch.pause_pressed.connect(func() -> void:
		if state == GameState.PLAYING:
			_enter_state(GameState.PAUSED))
	canvas.add_child(touch)

	_connect_signals()
	_apply_time_of_day(1)
	_enter_state(GameState.TITLE)

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0018
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_max_distance = 220.0
	add_child(sun_light)

func _apply_time_of_day(wave_num: int) -> void:
	var cycle: int = (wave_num - 1) % 4
	var env: Environment = world_env.environment

	match cycle:
		0:
			hud.time_of_day_name = "0600 HRS - DAWN ASSAULT"
			sky_mat.sky_top_color = Color(0.18, 0.32, 0.52)
			sky_mat.sky_horizon_color = Color(0.92, 0.58, 0.32)
			sky_mat.ground_horizon_color = Color(0.65, 0.42, 0.28)
			sky_mat.ground_bottom_color = Color(0.15, 0.18, 0.14)
			sun_light.rotation_degrees = Vector3(-18.0, -32.0, 0.0)
			sun_light.light_color = Color(1.0, 0.78, 0.52)
			sun_light.light_energy = 1.25
			env.ambient_light_color = Color(0.45, 0.42, 0.46)
			env.ambient_light_energy = 0.65
			env.fog_light_color = Color(0.75, 0.55, 0.40)
			env.fog_density = 0.0018
			if ocean_mat:
				ocean_mat.albedo_color = Color(0.09, 0.24, 0.34)
			turret.set_searchlight_enabled(false)

		1:
			hud.time_of_day_name = "1200 HRS - HIGH NOON"
			sky_mat.sky_top_color = Color(0.16, 0.44, 0.78)
			sky_mat.sky_horizon_color = Color(0.62, 0.80, 0.94)
			sky_mat.ground_horizon_color = Color(0.52, 0.66, 0.74)
			sky_mat.ground_bottom_color = Color(0.18, 0.22, 0.16)
			sun_light.rotation_degrees = Vector3(-56.0, 18.0, 0.0)
			sun_light.light_color = Color(1.0, 0.98, 0.92)
			sun_light.light_energy = 1.45
			env.ambient_light_color = Color(0.58, 0.66, 0.72)
			env.ambient_light_energy = 0.80
			env.fog_light_color = Color(0.62, 0.76, 0.88)
			env.fog_density = 0.0012
			if ocean_mat:
				ocean_mat.albedo_color = Color(0.06, 0.28, 0.44)
			turret.set_searchlight_enabled(false)

		2:
			hud.time_of_day_name = "1830 HRS - CRIMSON DUSK"
			sky_mat.sky_top_color = Color(0.14, 0.12, 0.30)
			sky_mat.sky_horizon_color = Color(0.88, 0.34, 0.20)
			sky_mat.ground_horizon_color = Color(0.55, 0.24, 0.18)
			sky_mat.ground_bottom_color = Color(0.10, 0.10, 0.12)
			sun_light.rotation_degrees = Vector3(-12.0, 42.0, 0.0)
			sun_light.light_color = Color(1.0, 0.52, 0.28)
			sun_light.light_energy = 0.95
			env.ambient_light_color = Color(0.36, 0.28, 0.38)
			env.ambient_light_energy = 0.50
			env.fog_light_color = Color(0.58, 0.30, 0.24)
			env.fog_density = 0.0022
			if ocean_mat:
				ocean_mat.albedo_color = Color(0.08, 0.16, 0.26)
			turret.set_searchlight_enabled(true)

		3:
			hud.time_of_day_name = "0100 HRS - NIGHT SIEGE"
			sky_mat.sky_top_color = Color(0.02, 0.04, 0.09)
			sky_mat.sky_horizon_color = Color(0.06, 0.11, 0.18)
			sky_mat.ground_horizon_color = Color(0.05, 0.08, 0.12)
			sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.04)
			sun_light.rotation_degrees = Vector3(-38.0, -15.0, 0.0)
			sun_light.light_color = Color(0.45, 0.62, 0.88)
			sun_light.light_energy = 0.32
			env.ambient_light_color = Color(0.14, 0.20, 0.30)
			env.ambient_light_energy = 0.34
			env.fog_light_color = Color(0.05, 0.09, 0.15)
			env.fog_density = 0.0024
			if ocean_mat:
				ocean_mat.albedo_color = Color(0.02, 0.07, 0.13)
			turret.set_searchlight_enabled(true)
			fx.spawn_illumination_flare(Vector3(0.0, 62.0, -68.0))
			hud.show_banner("NIGHT SIEGE! PRESS [F] TO LAUNCH ILLUMINATION FLARES!", Color(1.0, 0.90, 0.35), 4.2)

func _connect_signals() -> void:
	hud.start_mission_requested.connect(_on_start_mission)
	hud.next_wave_requested.connect(_on_next_wave)
	hud.upgrade_purchased.connect(_on_upgrade_purchased)
	hud.resume_requested.connect(func() -> void: _enter_state(GameState.PLAYING))
	hud.sensitivity_changed.connect(func(v: float) -> void: turret.mouse_sensitivity = v)

	combat.enemy_killed.connect(_on_enemy_killed)
	combat.armor_ricochet.connect(_on_armor_ricochet)
	combat.hull_deflected.connect(func(_p: Vector3) -> void: hud.trigger_hull_warning())
	combat.supply_claimed.connect(_on_supply_claimed)
	combat.supply_lost.connect(_on_supply_lost)
	combat.supply_plane_inbound.connect(_on_supply_plane_inbound)
	combat.paratrooper_Alert.connect(_on_paratrooper_alert)
	combat.bunker_damaged.connect(_on_bunker_damaged)
	combat.wave_quota_updated.connect(_on_wave_quota_updated)
	combat.wave_completed.connect(_on_wave_completed)

func _on_touch_mode_enabled() -> void:
	hud.touch_mode = true
	# Slightly larger UI on touch screens so HUD text and menus are readable on phones
	get_tree().root.content_scale_factor = 1.15

func _enter_state(new_state: int) -> void:
	state = new_state
	_mouse_fire_held = false
	touch.set_active(state == GameState.PLAYING)
	match state:
		GameState.TITLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			hud.set_menu_state("title")
		GameState.PLAYING:
			# No pointer lock on touch devices; a touch laptop's first real mouse
			# click still captures the pointer (see _unhandled_input)
			if not touch.touch_mode:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			hud.set_menu_state("none")
		GameState.SHOP:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			hud.set_menu_state("shop")
		GameState.PAUSED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			hud.set_menu_state("pause")
		GameState.GAMEOVER:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			hud.set_menu_state("gameover")

func _on_start_mission() -> void:
	bunker_max_hp = 100.0
	bunker_hp = 100.0
	score = 0
	streak = 0
	multiplier = 1
	current_wave = 1
	hud.bunker_hp = bunker_hp
	hud.bunker_max_hp = bunker_max_hp
	hud.score = score
	hud.streak = streak
	hud.multiplier = multiplier
	hud.current_wave = current_wave

	fx.clear_all()
	turret.reset_for_new_game()
	_apply_time_of_day(current_wave)
	combat.start_wave(current_wave)
	hud.show_banner("WAVE 1: DEFEND THE BEACHHEAD! ENEMY APPROACHING FROM %s" % combat.get_heading_label(), Color(0.65, 1.0, 0.45), 3.8)
	_enter_state(GameState.PLAYING)

func _on_next_wave() -> void:
	current_wave += 1
	hud.current_wave = current_wave
	turret.refill_for_wave()
	_apply_time_of_day(current_wave)
	combat.start_wave(current_wave)
	hud.show_banner("WAVE %d INCOMING FROM %s — %s" % [current_wave, combat.get_heading_label(), hud.time_of_day_name], Color(0.65, 1.0, 0.45), 3.8)
	_enter_state(GameState.PLAYING)

func _on_upgrade_purchased(upgrade_id: String, cost: int) -> void:
	if score < cost:
		sfx.play("ricochet", -3.0, 0.8)
		return
	match upgrade_id:
		"coastal_gun":
			if turret.heavy_gun:
				return
			turret.set_heavy_gun(true)
			turret.current_weapon = 1
			turret.weapon_switched.emit(turret.get_current_weapon_name())
		"repair":
			if bunker_hp >= bunker_max_hp:
				return
			bunker_hp = minf(bunker_max_hp, bunker_hp + 35.0)
			hud.bunker_hp = bunker_hp
		"ammo_pack":
			turret.mg_ammo = mini(turret.max_mg_ammo + 400, turret.mg_ammo + 400)
			turret.cannon_ammo = mini(turret.max_cannon_ammo + 25, turret.cannon_ammo + 25)
			turret.sam_ammo = mini(turret.max_sam_ammo + 6, turret.sam_ammo + 6)
		"mg_rate":
			turret.mg_fire_rate_mult += 0.20
		"cannon_autoloader":
			turret.cannon_reload_mult += 0.22
		"sam_radar":
			turret.sam_lock_speed_mult += 0.30

	score -= cost
	hud.score = score
	sfx.play("supply_pickup", 0.0, 1.0)
	hud.set_menu_state("shop")

func _on_enemy_killed(unit_type: String, world_pos: Vector3, base_points: int, bonus_label: String) -> void:
	streak += 1
	multiplier = clampi(1 + int(streak / 5), 1, 5)
	var earned: int = base_points * multiplier
	score += earned
	if score > high_score:
		high_score = score
		hud.high_score = high_score
		_save_high_score()

	hud.score = score
	hud.streak = streak
	hud.multiplier = multiplier
	hud.trigger_hitmarker()

	var popup_txt: String = "+%d %s" % [earned, unit_type]
	if not bonus_label.is_empty():
		popup_txt += "\n" + bonus_label
	hud.add_floating_popup(world_pos, popup_txt, Color(1.0, 0.92, 0.32))

	if streak > 0 and streak % 12 == 0:
		turret.overdrive_timer = 7.5
		sfx.play("supply_pickup", 0.0, 1.15)
		hud.show_banner("12-KILL STREAK! CIWS VULCAN OVERDRIVE ACTIVATED!", Color(0.3, 0.95, 1.0), 3.5)

func _on_armor_ricochet(_world_pos: Vector3) -> void:
	hud.trigger_ricochet_warning()

func _on_supply_claimed(world_pos: Vector3, is_golden: bool) -> void:
	turret.grant_supply_crate(is_golden)
	bunker_hp = minf(bunker_max_hp, bunker_hp + 22.0)
	hud.bunker_hp = bunker_hp
	score += 250 * multiplier
	hud.score = score
	hud.trigger_hitmarker()
	if is_golden:
		hud.add_floating_popup(world_pos, "OVERDRIVE CRATE CLAIMED!\nCIWS VULCAN ONLINE!", Color(0.3, 0.98, 1.0))
		hud.show_banner("GOLDEN SUPPLY CLAIMED — CIWS VULCAN OVERDRIVE!", Color(0.3, 0.98, 1.0), 3.5)
	else:
		hud.add_floating_popup(world_pos, "SUPPLY CLAIMED!\n+AMMO +SHELLS +SAM +22% ARMOR", Color(0.35, 1.0, 0.55))
		hud.show_banner("SUPPLY CRATE CLAIMED! AMMO & ARMOR RESTORED!", Color(0.35, 1.0, 0.55), 2.6)

func _on_supply_lost(world_pos: Vector3) -> void:
	hud.add_floating_popup(world_pos, "SUPPLY CRATE LOST!\n(SHOOT IN MID-AIR!)", Color(1.0, 0.4, 0.3))

func _on_supply_plane_inbound() -> void:
	hud.show_banner("C-130 SUPPLY DROP INBOUND — SHOOT THE PARACHUTE CRATES!", Color(0.35, 1.0, 0.85), 3.5)

func _on_paratrooper_alert(_world_pos: Vector3) -> void:
	hud.show_banner("WARNING: PARATROOPERS DROPPING BEHIND BUNKER! CHECK 360° RADAR!", Color(1.0, 0.35, 0.22), 3.2)

func _on_bunker_damaged(amount: float, source_pos: Vector3) -> void:
	if state != GameState.PLAYING:
		return
	bunker_hp = maxf(0.0, bunker_hp - amount)
	streak = 0
	multiplier = 1
	hud.bunker_hp = bunker_hp
	hud.streak = streak
	hud.multiplier = multiplier
	hud.trigger_damage_indicator(source_pos)
	turret.add_shake(0.35)
	sfx.play("bunker_hit", 0.0, randf_range(0.92, 1.08))

	if bunker_hp <= 0.0:
		_save_high_score()
		_enter_state(GameState.GAMEOVER)

func _on_wave_quota_updated(killed: int, total: int) -> void:
	hud.wave_killed = killed
	hud.wave_total = total

func _on_wave_completed() -> void:
	if state == GameState.PLAYING:
		score += 500 * current_wave
		hud.score = score
		if score > high_score:
			high_score = score
			hud.high_score = high_score
			_save_high_score()
		_enter_state(GameState.SHOP)

func _unhandled_input(event: InputEvent) -> void:
	if state != GameState.PLAYING:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			if state == GameState.PAUSED:
				_enter_state(GameState.PLAYING)
		return

	# Browsers synthesize mouse events from touches; touch input is handled by
	# TouchControls instead, so drop the copies (they caused double-speed aim
	# and fired the gun whenever a finger was down)
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	# Mobile browsers also send their own imitation mouse events right after a tap
	# (not marked as emulated); they would grab pointer lock and jerk the aim
	if event is InputEventMouse and touch.is_recent_touch():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_fire_held = event.pressed

	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or _mouse_fire_held or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			turret.apply_mouse_delta(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_sam_queued = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			turret.toggle_primary_weapon()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_P:
				_enter_state(GameState.PAUSED)
			KEY_SPACE, KEY_Q:
				turret.toggle_primary_weapon()
			KEY_1:
				turret.current_weapon = 0
				turret.weapon_switched.emit(turret.get_current_weapon_name())
			KEY_2:
				turret.current_weapon = 1
				turret.weapon_switched.emit(turret.get_current_weapon_name())
			KEY_3:
				turret.current_weapon = 2
				turret.weapon_switched.emit(turret.get_current_weapon_name())
			KEY_M, KEY_E:
				_sam_queued = true
			KEY_F:
				_flare_queued = true

func _process(delta: float) -> void:
	_wave_time += delta
	if _test_hooks:
		_test_hook_timer -= delta
		if _test_hook_timer <= 0.0:
			_test_hook_timer = 0.05
			_publish_test_state()
	if is_instance_valid(shoreline_foam):
		shoreline_foam.position.z = -82.0 + sin(_wave_time * 1.6) * 2.2

	if state == GameState.PLAYING:
		var fire_tapped: bool = touch.consume_fire_tap()
		var firing_primary: bool = _mouse_fire_held or touch.fire_held or fire_tapped \
				or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)
		_sam_queued = touch.consume_sam() or _sam_queued
		_flare_queued = touch.consume_flare() or _flare_queued
		turret.process_turret(delta, firing_primary, _sam_queued, _flare_queued)
		_sam_queued = false
		_flare_queued = false
		combat.process_combat(delta)
	else:
		if state == GameState.TITLE and turret != null:
			turret.yaw = sin(_wave_time * 0.25) * 0.45
			turret.rotation.y = turret.yaw

func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("stats", "high_score", 0))

func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "high_score", high_score)
	cfg.save(SAVE_PATH)


## Positions are in canvas pixels (divide by devicePixelRatio for CSS pixels)
func _publish_test_state() -> void:
	var xf: Transform2D = get_tree().root.get_final_transform()
	var buttons: Dictionary = {}
	for b in touch._buttons():
		var p: Vector2 = xf * b["pos"]
		buttons[b["id"]] = [p.x, p.y, b["r"] * xf.x.x]
	var rects: Dictionary = {}
	for pair in [["start", hud.start_button], ["resume", hud.resume_button]]:
		var btn: Control = pair[1]
		if is_instance_valid(btn) and btn.is_visible_in_tree():
			var r: Rect2 = btn.get_global_rect()
			var c: Vector2 = xf * r.get_center()
			rects[pair[0]] = [c.x, c.y]
	var data: Dictionary = {
		"state": GameState.keys()[state],
		"yaw": turret.yaw, "pitch": turret.pitch,
		"sens": turret.mouse_sensitivity, "canvas_per_logical": xf.x.x,
		"mg": turret.mg_ammo, "cannon": turret.cannon_ammo, "sam": turret.sam_ammo, "flare": turret.flare_ammo,
		"weapon": turret.current_weapon,
		"touch_mode": touch.touch_mode, "fire_held": touch.fire_held, "mouse_fire_held": _mouse_fire_held,
		"portrait": touch.is_portrait(),
		"buttons": buttons, "menu_buttons": rects,
		"frame": Engine.get_process_frames(),
	}
	JavaScriptBridge.eval("window.__ih = " + JSON.stringify(data) + ";", true)
