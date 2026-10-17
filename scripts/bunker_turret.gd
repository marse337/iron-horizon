class_name BunkerTurret
extends Node3D

## 360-Degree First-Person Coastal Defense Bunker Turret
## Features alternating Dual 30mm Autocannons, 105mm Anti-Tank Howitzer,
## SAM Radar Lock-On Pod, 9mm Backup Pistol, Night Searchlight, and Illumination Flares.

const UnitFactoryScript = preload("res://scripts/unit_factory.gd")

signal ammo_changed()
signal weapon_switched(weapon_name: String)

enum PrimaryWeapon {
	MG_30MM,
	AT_CANNON,
	BACKUP_PISTOL
}

var combat: Node3D
var sfx: Node
var fx: Node3D

var pitch_pivot: Node3D
var camera: Camera3D
var gun_rig: Node3D
var barrel_left: Node3D
var barrel_right: Node3D
var barrel_cannon: Node3D
var muzzle_light: OmniLight3D
var searchlight: SpotLight3D

# Rotation & sensitivity
var yaw: float = 0.0
var pitch: float = -0.06
var mouse_sensitivity: float = 0.0024
var recoil_kick: float = 0.0
var camera_shake: float = 0.0

# Weapons & Ammo State
var current_weapon: int = PrimaryWeapon.MG_30MM
var mg_ammo: int = 900
var max_mg_ammo: int = 1200
var cannon_ammo: int = 55
var max_cannon_ammo: int = 75
var sam_ammo: int = 4
var max_sam_ammo: int = 8
var flare_ammo: int = 4
var max_flare_ammo: int = 6

# Upgrades & Overdrive
var mg_fire_rate_mult: float = 1.0
var cannon_reload_mult: float = 1.0
var sam_lock_speed_mult: float = 1.0
var overdrive_timer: float = 0.0
# 155mm Coastal Gun (shop upgrade) replaces the 105mm and can hole landing craft
var heavy_gun: bool = false

# Cooldowns & barrel animation
var _fire_cooldown: float = 0.0
var _cannon_cooldown: float = 0.0
var _cannon_cooldown_max: float = 1.05
var _sam_cooldown: float = 0.0
var _muzzle_flash_timer: float = 0.0
var _use_left_barrel: bool = true
var _left_recoil: float = 0.0
var _right_recoil: float = 0.0
var _cannon_recoil: float = 0.0

# SAM Lock-on state
var lock_target: Dictionary = {}
var lock_progress: float = 0.0
var _lock_beep_timer: float = 0.0

func _ready() -> void:
	# Eye 3.6 above the hilltop pad: high enough that the emplacement rim
	# (pad +0.5, r=4.2) never hides the slope or beach below.
	position = Vector3(0.0, UnitFactoryScript.HILL_TOP_Y + 3.6, 0.0)
	_build_turret_cockpit()

func _build_turret_cockpit() -> void:
	pitch_pivot = Node3D.new()
	pitch_pivot.name = "PitchPivot"
	add_child(pitch_pivot)

	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.15
	camera.far = 650.0
	pitch_pivot.add_child(camera)

	gun_rig = Node3D.new()
	gun_rig.name = "GunRig"
	pitch_pivot.add_child(gun_rig)

	var mat_gunmetal := UnitFactoryScript.make_mat(Color(0.20, 0.22, 0.20), 0.45, 0.65)
	var mat_olive_armor := UnitFactoryScript.make_mat(Color(0.27, 0.33, 0.20), 0.72, 0.25)
	var mat_brass := UnitFactoryScript.make_mat(Color(0.85, 0.68, 0.22), 0.35, 0.7)
	var mat_muzzle := UnitFactoryScript.make_mat(Color(1.0, 0.78, 0.25), 0.1, 0.0, true)

	# Yaw pedestal from the traverse ring (pad +1.0) up to the gun rig; top stays below
	# the cannon housing so it doesn't clip at full down-pitch
	UnitFactoryScript.add_cyl(self, 0.3, 0.6, 1.3, Vector3(0.0, -1.95, 0.0), mat_gunmetal)

	# Left 30mm Autocannon assembly
	barrel_left = Node3D.new()
	barrel_left.position = Vector3(-0.62, -0.42, -0.95)
	gun_rig.add_child(barrel_left)
	UnitFactoryScript.add_box(barrel_left, Vector3(0.14, 0.16, 0.42), Vector3(0.0, 0.0, -0.05), mat_olive_armor)
	UnitFactoryScript.add_cyl(barrel_left, 0.048, 0.055, 1.35, Vector3(0.0, 0.02, -0.65), mat_gunmetal, Vector3(90, 0, 0))
	UnitFactoryScript.add_cyl(barrel_left, 0.065, 0.065, 0.45, Vector3(0.0, 0.02, -0.35), mat_brass, Vector3(90, 0, 0))
	UnitFactoryScript.add_cyl(barrel_left, 0.065, 0.050, 0.16, Vector3(0.0, 0.02, -1.35), mat_muzzle, Vector3(90, 0, 0))

	# Right 30mm Autocannon assembly
	barrel_right = Node3D.new()
	barrel_right.position = Vector3(0.62, -0.42, -0.95)
	gun_rig.add_child(barrel_right)
	UnitFactoryScript.add_box(barrel_right, Vector3(0.14, 0.16, 0.42), Vector3(0.0, 0.0, -0.05), mat_olive_armor)
	UnitFactoryScript.add_cyl(barrel_right, 0.048, 0.055, 1.35, Vector3(0.0, 0.02, -0.65), mat_gunmetal, Vector3(90, 0, 0))
	UnitFactoryScript.add_cyl(barrel_right, 0.065, 0.065, 0.45, Vector3(0.0, 0.02, -0.35), mat_brass, Vector3(90, 0, 0))
	UnitFactoryScript.add_cyl(barrel_right, 0.065, 0.050, 0.16, Vector3(0.0, 0.02, -1.35), mat_muzzle, Vector3(90, 0, 0))

	# Center 105mm Anti-Tank Howitzer Barrel
	barrel_cannon = Node3D.new()
	barrel_cannon.position = Vector3(0.0, -0.62, -1.0)
	gun_rig.add_child(barrel_cannon)
	UnitFactoryScript.add_box(barrel_cannon, Vector3(0.30, 0.22, 0.5), Vector3(0.0, 0.0, 0.0), mat_olive_armor)
	UnitFactoryScript.add_cyl(barrel_cannon, 0.105, 0.125, 1.65, Vector3(0.0, 0.02, -0.82), mat_gunmetal, Vector3(90, 0, 0))
	UnitFactoryScript.add_cyl(barrel_cannon, 0.145, 0.135, 0.28, Vector3(0.0, 0.02, -1.68), mat_olive_armor, Vector3(90, 0, 0))

	# Muzzle flash dynamic light
	muzzle_light = OmniLight3D.new()
	muzzle_light.position = Vector3(0.0, -0.15, -2.2)
	muzzle_light.light_color = Color(1.0, 0.78, 0.32)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 18.0
	pitch_pivot.add_child(muzzle_light)

	# Bunker Night Searchlight
	searchlight = SpotLight3D.new()
	searchlight.position = Vector3(0.0, 0.35, -0.8)
	searchlight.light_color = Color(1.0, 0.96, 0.84)
	searchlight.light_energy = 0.0
	searchlight.spot_range = 175.0
	searchlight.spot_angle = 22.0
	searchlight.spot_attenuation = 0.75
	pitch_pivot.add_child(searchlight)

func reset_for_new_game() -> void:
	yaw = 0.0
	pitch = -0.05
	rotation.y = yaw
	pitch_pivot.rotation.x = pitch
	max_mg_ammo = 1200
	max_cannon_ammo = 75
	max_sam_ammo = 8
	max_flare_ammo = 6
	mg_ammo = 900
	cannon_ammo = 55
	sam_ammo = 4
	flare_ammo = 4
	mg_fire_rate_mult = 1.0
	cannon_reload_mult = 1.0
	sam_lock_speed_mult = 1.0
	overdrive_timer = 0.0
	set_heavy_gun(false)
	current_weapon = PrimaryWeapon.MG_30MM
	ammo_changed.emit()
	weapon_switched.emit(get_current_weapon_name())

func set_heavy_gun(enabled: bool) -> void:
	heavy_gun = enabled
	if combat:
		combat.heavy_gun_installed = enabled
	# Visibly heavier barrel once the coastal gun is fitted
	barrel_cannon.scale = Vector3(1.3, 1.3, 1.25) if enabled else Vector3.ONE
	weapon_switched.emit(get_current_weapon_name())

func refill_for_wave() -> void:
	mg_ammo = mini(max_mg_ammo, mg_ammo + 550)
	cannon_ammo = mini(max_cannon_ammo, cannon_ammo + 28)
	sam_ammo = mini(max_sam_ammo, sam_ammo + 2)
	flare_ammo = mini(max_flare_ammo, flare_ammo + 2)
	if current_weapon == PrimaryWeapon.BACKUP_PISTOL and (mg_ammo > 0 or cannon_ammo > 0):
		current_weapon = PrimaryWeapon.MG_30MM if mg_ammo > 0 else PrimaryWeapon.AT_CANNON
		weapon_switched.emit(get_current_weapon_name())
	ammo_changed.emit()

func grant_supply_crate(is_golden: bool) -> void:
	mg_ammo = mini(max_mg_ammo, mg_ammo + 320)
	cannon_ammo = mini(max_cannon_ammo, cannon_ammo + 18)
	sam_ammo = mini(max_sam_ammo, sam_ammo + 1)
	flare_ammo = mini(max_flare_ammo, flare_ammo + 1)
	if is_golden:
		overdrive_timer = 8.5
	if current_weapon == PrimaryWeapon.BACKUP_PISTOL:
		current_weapon = PrimaryWeapon.MG_30MM
		weapon_switched.emit(get_current_weapon_name())
	ammo_changed.emit()

func set_searchlight_enabled(enabled: bool) -> void:
	if is_instance_valid(searchlight):
		searchlight.light_energy = 6.5 if enabled else 0.0

func apply_mouse_delta(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, deg_to_rad(-40.0), deg_to_rad(72.0))

func add_shake(amount: float) -> void:
	camera_shake = clampf(camera_shake + amount, 0.0, 1.0)

func toggle_primary_weapon() -> void:
	if current_weapon == PrimaryWeapon.MG_30MM:
		if cannon_ammo > 0:
			current_weapon = PrimaryWeapon.AT_CANNON
		elif mg_ammo == 0:
			current_weapon = PrimaryWeapon.BACKUP_PISTOL
	elif current_weapon == PrimaryWeapon.AT_CANNON:
		if mg_ammo > 0:
			current_weapon = PrimaryWeapon.MG_30MM
		elif cannon_ammo == 0:
			current_weapon = PrimaryWeapon.BACKUP_PISTOL
	else:
		if mg_ammo > 0:
			current_weapon = PrimaryWeapon.MG_30MM
		elif cannon_ammo > 0:
			current_weapon = PrimaryWeapon.AT_CANNON
	weapon_switched.emit(get_current_weapon_name())

func get_current_weapon_name() -> String:
	if overdrive_timer > 0.0:
		return "CIWS VULCAN OVERDRIVE"
	match current_weapon:
		PrimaryWeapon.MG_30MM:
			return "DUAL 30MM AUTOCANNON"
		PrimaryWeapon.AT_CANNON:
			return "155MM COASTAL GUN" if heavy_gun else "105MM AT HOWITZER"
		PrimaryWeapon.BACKUP_PISTOL:
			return "9MM BACKUP SIDEARM"
	return "DUAL 30MM AUTOCANNON"

func get_cannon_reload_ratio() -> float:
	if _cannon_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - (_cannon_cooldown / (_cannon_cooldown_max / cannon_reload_mult)), 0.0, 1.0)

func process_turret(delta: float, is_firing_primary: bool, fire_sam_pressed: bool, fire_flare_pressed: bool) -> void:
	var key_aim := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		key_aim.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		key_aim.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		key_aim.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		key_aim.y += 1.0
	if key_aim.length_squared() > 0.0:
		yaw = wrapf(yaw - key_aim.x * 1.65 * delta, -PI, PI)
		pitch = clampf(pitch - key_aim.y * 1.25 * delta, deg_to_rad(-40.0), deg_to_rad(72.0))

	recoil_kick = lerpf(recoil_kick, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	camera_shake = maxf(0.0, camera_shake - delta * 2.6)
	_left_recoil = lerpf(_left_recoil, 0.0, clampf(delta * 18.0, 0.0, 1.0))
	_right_recoil = lerpf(_right_recoil, 0.0, clampf(delta * 18.0, 0.0, 1.0))
	_cannon_recoil = lerpf(_cannon_recoil, 0.0, clampf(delta * 8.0, 0.0, 1.0))

	barrel_left.position.z = -0.95 + _left_recoil
	barrel_right.position.z = -0.95 + _right_recoil
	barrel_cannon.position.z = -1.0 + _cannon_recoil

	var shake_offset := Vector2.ZERO
	if camera_shake > 0.001:
		shake_offset = Vector2(
			randf_range(-1.0, 1.0) * camera_shake * 0.025,
			randf_range(-1.0, 1.0) * camera_shake * 0.025
		)

	rotation.y = yaw + shake_offset.x
	pitch_pivot.rotation.x = clampf(pitch + recoil_kick + shake_offset.y, deg_to_rad(-42.0), deg_to_rad(75.0))

	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta
	if _cannon_cooldown > 0.0:
		_cannon_cooldown -= delta
	if _sam_cooldown > 0.0:
		_sam_cooldown -= delta
	if overdrive_timer > 0.0:
		overdrive_timer = maxf(0.0, overdrive_timer - delta)
		if overdrive_timer == 0.0:
			weapon_switched.emit(get_current_weapon_name())

	if _muzzle_flash_timer > 0.0:
		_muzzle_flash_timer -= delta
		if _muzzle_flash_timer <= 0.0:
			muzzle_light.light_energy = 0.0

	if mg_ammo <= 0 and cannon_ammo <= 0 and current_weapon != PrimaryWeapon.BACKUP_PISTOL:
		current_weapon = PrimaryWeapon.BACKUP_PISTOL
		weapon_switched.emit(get_current_weapon_name())
	elif current_weapon == PrimaryWeapon.MG_30MM and mg_ammo <= 0 and cannon_ammo > 0:
		current_weapon = PrimaryWeapon.AT_CANNON
		weapon_switched.emit(get_current_weapon_name())
	elif current_weapon == PrimaryWeapon.AT_CANNON and cannon_ammo <= 0 and mg_ammo > 0:
		current_weapon = PrimaryWeapon.MG_30MM
		weapon_switched.emit(get_current_weapon_name())

	_update_sam_lock(delta)

	if is_firing_primary:
		_try_fire_primary()
	if fire_sam_pressed:
		_try_fire_sam()
	if fire_flare_pressed:
		_try_fire_flare()

func _try_fire_primary() -> void:
	if combat == null:
		return
	var forward_dir: Vector3 = -camera.global_transform.basis.z.normalized()

	if overdrive_timer > 0.0:
		if _fire_cooldown <= 0.0:
			_fire_cooldown = 0.045
			_fire_dual_barrels(forward_dir, "ciws", 0.004)
			if sfx:
				sfx.play("ciws_fire", -2.5, randf_range(0.96, 1.06))
		return

	match current_weapon:
		PrimaryWeapon.MG_30MM:
			if mg_ammo > 0 and _fire_cooldown <= 0.0:
				_fire_cooldown = 0.082 / mg_fire_rate_mult
				mg_ammo = maxi(0, mg_ammo - 1)
				_fire_dual_barrels(forward_dir, "mg", 0.0065)
				if sfx:
					sfx.play("mg_fire", -2.0, randf_range(0.94, 1.06))
				ammo_changed.emit()

		PrimaryWeapon.AT_CANNON:
			if cannon_ammo > 0 and _cannon_cooldown <= 0.0:
				_cannon_cooldown = _cannon_cooldown_max / cannon_reload_mult
				cannon_ammo = maxi(0, cannon_ammo - 1)
				_cannon_recoil = 0.42
				recoil_kick += 0.032
				add_shake(0.32)
				muzzle_light.light_energy = 5.5
				_muzzle_flash_timer = 0.09
				var muzzle_pos: Vector3 = barrel_cannon.global_position + forward_dir * 1.8
				combat.spawn_player_projectile("cannon", muzzle_pos, forward_dir)
				if sfx:
					sfx.play("cannon_fire", 0.0, randf_range(0.95, 1.05))
				ammo_changed.emit()

		PrimaryWeapon.BACKUP_PISTOL:
			if _fire_cooldown <= 0.0:
				_fire_cooldown = 0.20
				recoil_kick += 0.008
				muzzle_light.light_energy = 2.0
				_muzzle_flash_timer = 0.04
				var p_origin: Vector3 = camera.global_position + Vector3(0.0, -0.18, 0.0) + forward_dir * 1.1
				combat.spawn_player_projectile("pistol", p_origin, forward_dir)
				if sfx:
					sfx.play("pistol_fire", -2.0, randf_range(0.96, 1.05))

func _fire_dual_barrels(forward_dir: Vector3, proj_kind: String, spread: float) -> void:
	_use_left_barrel = not _use_left_barrel
	var active_barrel: Node3D = barrel_left if _use_left_barrel else barrel_right
	if _use_left_barrel:
		_left_recoil = 0.16
	else:
		_right_recoil = 0.16
	recoil_kick = clampf(recoil_kick + 0.004, 0.0, 0.035)
	muzzle_light.light_energy = 3.2
	_muzzle_flash_timer = 0.045

	var jitter := Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)
	var shot_dir: Vector3 = (forward_dir + jitter).normalized()
	var origin: Vector3 = active_barrel.global_position + forward_dir * 1.5
	combat.spawn_player_projectile(proj_kind, origin, shot_dir)

func _update_sam_lock(delta: float) -> void:
	if combat == null or sam_ammo <= 0:
		lock_target = {}
		lock_progress = 0.0
		return

	var cam_pos: Vector3 = camera.global_position
	var cam_fwd: Vector3 = -camera.global_transform.basis.z.normalized()

	var best_unit: Dictionary = {}
	var best_dot: float = cos(deg_to_rad(18.5))

	for u in combat.units:
		if not u["is_air"] or not is_instance_valid(u["node"]):
			continue
		var dir_to_u: Vector3 = (u["node"].global_position - cam_pos).normalized()
		var d: float = cam_fwd.dot(dir_to_u)
		if d > best_dot:
			best_dot = d
			best_unit = u

	if best_unit.is_empty():
		lock_target = {}
		lock_progress = maxf(0.0, lock_progress - delta * 2.5)
		return

	if lock_target.get("node", null) != best_unit.get("node", null):
		lock_target = best_unit
		lock_progress = 0.15

	var was_locked: bool = (lock_progress >= 1.0)
	lock_progress = clampf(lock_progress + delta * 1.75 * sam_lock_speed_mult, 0.0, 1.0)

	_lock_beep_timer -= delta
	if not was_locked and lock_progress >= 1.0:
		if sfx:
			sfx.play("sam_locked", -3.0, 1.0)
		_lock_beep_timer = 0.25
	elif _lock_beep_timer <= 0.0:
		if lock_progress >= 1.0:
			_lock_beep_timer = 0.28
			if sfx:
				sfx.play("sam_locked", -6.0, 1.0)
		else:
			_lock_beep_timer = 0.16
			if sfx:
				sfx.play("sam_lock_beep", -6.0, lerpf(0.9, 1.35, lock_progress))

func _try_fire_sam() -> void:
	if combat == null or sam_ammo <= 0 or _sam_cooldown > 0.0:
		return
	_sam_cooldown = 0.55
	sam_ammo = maxi(0, sam_ammo - 1)
	recoil_kick += 0.018
	add_shake(0.18)

	var forward_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	var launch_pos: Vector3 = global_position + camera.global_transform.basis.x * 0.85 + Vector3(0.0, 0.2, 0.0) + forward_dir * 1.2
	var target_to_pass: Dictionary = lock_target if lock_progress >= 0.35 else {}
	combat.spawn_player_projectile("sam", launch_pos, forward_dir, target_to_pass)
	if sfx:
		sfx.play("sam_launch", -1.0, randf_range(0.95, 1.05))
	ammo_changed.emit()

func _try_fire_flare() -> void:
	if fx == null or flare_ammo <= 0:
		return
	flare_ammo = maxi(0, flare_ammo - 1)
	var forward_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	var flat_fwd := Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
	if flat_fwd.length_squared() < 0.01:
		flat_fwd = Vector3(0.0, 0.0, -1.0)
	var flare_pos: Vector3 = Vector3(flat_fwd.x * 68.0, 62.0, flat_fwd.z * 68.0)
	fx.spawn_illumination_flare(flare_pos)
	if sfx:
		sfx.play("flare_launch", -1.0, 1.0)
	ammo_changed.emit()

