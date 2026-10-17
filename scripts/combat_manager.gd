class_name CombatManager
extends Node3D

## Manages all 360-degree combined-arms enemies, friendly C-130 supply drops,
## shootable parachute crates, and ballistic/homing projectiles.

const UnitFactoryScript = preload("res://scripts/unit_factory.gd")

signal enemy_killed(unit_type: String, world_pos: Vector3, points: int, bonus_label: String)
signal armor_ricochet(world_pos: Vector3)
signal hull_deflected(world_pos: Vector3)
signal air_armor_deflected(world_pos: Vector3)
signal air_raid_incoming(world_pos: Vector3)
signal supply_claimed(world_pos: Vector3, is_golden: bool)
signal supply_lost(world_pos: Vector3)
signal supply_plane_inbound()
signal paratrooper_Alert(world_pos: Vector3)
signal bunker_damaged(amount: float, source_pos: Vector3)
signal wave_quota_updated(killed: int, total: int)
signal wave_completed()

enum UnitType {
	INFANTRY,
	PARATROOPER,
	APC,
	TANK,
	LANDING_CRAFT,
	ATTACK_HELI,
	TRANSPORT_HELI,
	FIGHTER_JET
}

const BUNKER_TARGET_POS := Vector3(0.0, UnitFactoryScript.HILL_TOP_Y + 1.5, 0.0)

var sfx: Node
var fx: Node3D

var units: Array[Dictionary] = []
var supply_planes: Array[Dictionary] = []
var supply_crates: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var smoke_puffs: Array[Dictionary] = []

# Wave state
var wave_active: bool = false
var current_wave: int = 1
var aggression: float = 1.0 # 1.0 to 9.0, scales enemy speed and fire rate
var wave_quota_total: int = 20
var wave_kills: int = 0
var wave_spawned: int = 0
var _spawn_timer: float = 0.0

# Wave plan: each wave is a fixed list of formations attacking from ONE heading.
# Heading 0 = straight in from the sea (-Z); negative = west, positive = east.
const WAVE_HEADINGS_DEG: Array[float] = [0.0, -30.0, 30.0, 0.0, -30.0, 30.0, 0.0, -75.0, 75.0, 180.0]
const SEA_HEADING_LIMIT_DEG := 40.0
var wave_heading: float = 0.0
var _wave_plan: Array[Dictionary] = []
var _hp_mult: float = 1.0

# Landing craft hulls ("naval" armor) shrug off everything until the player
# buys the 155mm Coastal Gun, which replaces the 105mm cannon
var heavy_gun_installed: bool = false
const LC_RAMP_CLOSED_DEG := -6.0
const LC_RAMP_OPEN_DEG := 98.0
var _supply_timer: float = 14.0
var _rng := RandomNumberGenerator.new()

# Shared projectile meshes/materials for fast instancing
var _tracer_mesh: BoxMesh
var _shell_mesh: SphereMesh
var _missile_mesh: CylinderMesh
var _puff_mesh: SphereMesh
var _mat_tracer_mg: StandardMaterial3D
var _mat_tracer_ciws: StandardMaterial3D
var _mat_shell: StandardMaterial3D
var _mat_sam: StandardMaterial3D
var _mat_enemy_proj: StandardMaterial3D
var _mat_smoke: StandardMaterial3D

func _ready() -> void:
	_rng.randomize()
	_init_shared_resources()

func _init_shared_resources() -> void:
	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3(0.16, 0.16, 3.8)

	_shell_mesh = SphereMesh.new()
	_shell_mesh.radius = 0.36
	_shell_mesh.height = 0.72

	_missile_mesh = CylinderMesh.new()
	_missile_mesh.top_radius = 0.12
	_missile_mesh.bottom_radius = 0.24
	_missile_mesh.height = 2.2

	_puff_mesh = SphereMesh.new()
	_puff_mesh.radius = 0.45
	_puff_mesh.height = 0.9

	_mat_tracer_mg = UnitFactoryScript.make_mat(Color(1.0, 0.88, 0.28), 0.1, 0.0, true)
	_mat_tracer_ciws = UnitFactoryScript.make_mat(Color(0.35, 0.95, 1.0), 0.1, 0.0, true)
	_mat_shell = UnitFactoryScript.make_mat(Color(1.0, 0.52, 0.12), 0.1, 0.0, true)
	_mat_sam = UnitFactoryScript.make_mat(Color(0.95, 0.95, 0.95), 0.4, 0.2, false)
	_mat_enemy_proj = UnitFactoryScript.make_mat(Color(1.0, 0.22, 0.15), 0.1, 0.0, true)

	_mat_smoke = StandardMaterial3D.new()
	_mat_smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_smoke.albedo_color = Color(0.85, 0.85, 0.82, 0.55)

func clear_all() -> void:
	wave_active = false
	for u in units:
		if is_instance_valid(u["node"]):
			u["node"].queue_free()
	units.clear()
	for sp in supply_planes:
		if is_instance_valid(sp["node"]):
			sp["node"].queue_free()
	supply_planes.clear()
	for sc in supply_crates:
		if is_instance_valid(sc["node"]):
			sc["node"].queue_free()
	supply_crates.clear()
	for p in projectiles:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	projectiles.clear()
	for sm in smoke_puffs:
		if is_instance_valid(sm["node"]):
			sm["node"].queue_free()
	smoke_puffs.clear()

func start_wave(wave_num: int) -> void:
	clear_all()
	current_wave = wave_num
	aggression = clampf(1.0 + float(wave_num - 1) * 0.65, 1.0, 9.0)
	_hp_mult = 1.0 + float(wave_num - 1) * 0.12
	wave_kills = 0
	wave_spawned = 0
	_spawn_timer = 2.5
	_supply_timer = 16.0
	_pick_wave_heading(wave_num)
	_build_wave_plan(wave_num)
	wave_active = true
	wave_quota_updated.emit(wave_kills, wave_quota_total)

func _pick_wave_heading(wave_num: int) -> void:
	var deg: float
	if wave_num <= WAVE_HEADINGS_DEG.size():
		deg = WAVE_HEADINGS_DEG[wave_num - 1]
	else:
		# After the scripted sequence, any heading except a repeat of the last one
		var prev: float = rad_to_deg(wave_heading)
		deg = prev
		while is_equal_approx(deg, prev):
			deg = WAVE_HEADINGS_DEG[_rng.randi_range(0, WAVE_HEADINGS_DEG.size() - 1)]
	wave_heading = deg_to_rad(deg)

func is_sea_heading() -> bool:
	return absf(rad_to_deg(wave_heading)) <= SEA_HEADING_LIMIT_DEG

func get_heading_label() -> String:
	var deg: int = roundi(rad_to_deg(wave_heading))
	match deg:
		0: return "THE SEA"
		-30: return "THE NORTH-WEST"
		30: return "THE NORTH-EAST"
		-75: return "THE WEST FLANK"
		75: return "THE EAST FLANK"
		180: return "THE REAR"
	return "BEARING %d" % deg

## Outward unit vector from the bunker along the wave heading (and its perpendicular)
func _heading_out(jitter_deg: float = 0.0) -> Vector3:
	var h: float = wave_heading + deg_to_rad(_rng.randf_range(-jitter_deg, jitter_deg))
	return Vector3(sin(h), 0.0, -cos(h))

func _heading_side() -> Vector3:
	return Vector3(cos(wave_heading), 0.0, sin(wave_heading))

## Builds the wave from a point budget. Enemy types unlock one per wave so each
## wave introduces at most one new threat; heavier types get likelier later on.
func _build_wave_plan(w: int) -> void:
	_wave_plan.clear()
	var sea: bool = is_sea_heading()
	# type, cost, first wave, weight
	var roster: Array = [
		[UnitType.INFANTRY, 3, 1, maxf(1.5, 6.0 - w * 0.6)],
		[UnitType.APC, 4, 2, 2.0],
		[UnitType.ATTACK_HELI, 4, 4, 1.5 + w * 0.1],
		[UnitType.TANK, 6, 5, 1.0 + w * 0.15],
		[UnitType.TRANSPORT_HELI, 5, 6, 1.2],
		[UnitType.FIGHTER_JET, 4, 3, 1.0 + w * 0.1],
	]
	var budget: int = 12 + w * 5
	var intro: Dictionary = {}
	for entry in roster:
		if entry[2] == w and entry[3] > 0.0:
			intro = _make_formation(entry[0], w)
			budget -= entry[1]
	while budget >= 3:
		var total_weight: float = 0.0
		for entry in roster:
			if entry[2] <= w and entry[1] <= budget:
				total_weight += entry[3]
		if total_weight <= 0.0:
			break
		var roll: float = _rng.randf() * total_weight
		for entry in roster:
			if entry[2] <= w and entry[1] <= budget:
				roll -= entry[3]
				if roll <= 0.0:
					_wave_plan.append(_make_formation(entry[0], w))
					budget -= entry[1]
					break
	_wave_plan.shuffle()
	# Always open with an infantry squad as a warm-up, then the new threat
	if not intro.is_empty():
		_wave_plan.insert(mini(1, _wave_plan.size()), intro)
	_wave_plan.push_front(_make_formation(UnitType.INFANTRY, w))

	# Landing craft themselves don't count toward the wave total (early on they
	# can't be sunk); only the troops and tanks they carry do
	wave_quota_total = 0
	for f in _wave_plan:
		wave_quota_total += f["cargo"] if f["type"] == UnitType.LANDING_CRAFT else f["count"] + f["count"] * f["cargo"]

## On sea headings, infantry squads and tanks are delivered by landing craft
## instead of appearing on the beach
func _make_formation(t: int, w: int) -> Dictionary:
	var f: Dictionary = {"type": t, "count": 1, "cargo": 0, "cargo_list": []}
	var squad: int = 3 + mini(int(w / 3.0), 2)
	match t:
		UnitType.INFANTRY:
			if is_sea_heading():
				f["type"] = UnitType.LANDING_CRAFT
				for k in range(squad):
					f["cargo_list"].append(UnitType.INFANTRY)
			else:
				f["count"] = squad
		UnitType.TANK:
			if is_sea_heading():
				f["type"] = UnitType.LANDING_CRAFT
				f["cargo_list"].append(UnitType.TANK)
				for k in range(2 + int(w >= 8)):
					f["cargo_list"].append(UnitType.INFANTRY)
		UnitType.APC:
			f["cargo"] = 3 + mini(w - 1, 3)
		UnitType.TRANSPORT_HELI:
			f["cargo"] = 2 + mini(int(w / 3.0), 3)
	if f["type"] == UnitType.LANDING_CRAFT:
		f["cargo"] = f["cargo_list"].size()
	return f

func process_combat(delta: float) -> void:
	if wave_active:
		_update_spawner(delta)
	_update_units(delta)
	_update_supply_planes(delta)
	_update_supply_crates(delta)
	_update_projectiles(delta)
	_update_smoke_puffs(delta)

func _update_spawner(delta: float) -> void:
	_spawn_timer -= delta
	_supply_timer -= delta

	if _supply_timer <= 0.0:
		_supply_timer = _rng.randf_range(20.0, 28.0)
		spawn_supply_plane()

	# Wave clears once every planned formation is out and nothing hostile remains
	if _wave_plan.is_empty() and not _any_hostiles_remaining():
		wave_active = false
		if sfx:
			sfx.play("wave_clear", 0.0, 1.0)
		wave_completed.emit()
		return

	var max_simultaneous: int = clampi(6 + current_wave * 2, 8, 28)
	if _spawn_timer <= 0.0 and not _wave_plan.is_empty() and units.size() < max_simultaneous:
		_spawn_formation(_wave_plan.pop_front())
		var base_interval: float = lerpf(4.5, 1.8, clampf(float(current_wave - 1) / 11.0, 0.0, 1.0))
		_spawn_timer = _rng.randf_range(base_interval * 0.8, base_interval * 1.2)

func _any_hostiles_remaining() -> bool:
	for u in units:
		if not u.get("escaped", false):
			return true
	return false

func _spawn_formation(f: Dictionary) -> void:
	var out: Vector3 = _heading_out()
	var side: Vector3 = _heading_side()
	var lateral: float = _rng.randf_range(-35.0, 35.0)
	var u: Dictionary = {}
	match f["type"]:
		UnitType.INFANTRY:
			# From the sea they appear at the waterline; overland they march in from range
			var dist: float = 150.0
			if is_sea_heading():
				dist = -UnitFactoryScript.SHORELINE_Z / maxf(-out.z, 0.2) - 2.0
			var center: Vector3 = out * dist + side * lateral
			if is_sea_heading():
				center.z = UnitFactoryScript.SHORELINE_Z + 3.0
			for k in range(f["count"]):
				spawn_unit(UnitType.INFANTRY, center + side * _rng.randf_range(-6.0, 6.0) + out * _rng.randf_range(0.0, 5.0))
		UnitType.APC:
			u = spawn_unit(UnitType.APC, out * _rng.randf_range(150.0, 170.0) + side * lateral)
		UnitType.LANDING_CRAFT:
			u = spawn_unit(UnitType.LANDING_CRAFT, out * _rng.randf_range(210.0, 240.0) + side * lateral)
			u["cargo_list"] = f["cargo_list"].duplicate()
			u["untallied"] = true
		UnitType.TANK:
			u = spawn_unit(UnitType.TANK, out * _rng.randf_range(125.0, 145.0) + side * lateral)
		UnitType.ATTACK_HELI:
			u = spawn_unit(UnitType.ATTACK_HELI, _heading_out(15.0) * _rng.randf_range(190.0, 230.0) + Vector3(0.0, _rng.randf_range(30.0, 52.0), 0.0))
		UnitType.TRANSPORT_HELI:
			u = spawn_transport_run(f["cargo"])
		UnitType.FIGHTER_JET:
			u = spawn_fighter_jet_pass()
	if not u.is_empty():
		u["cargo"] = f["cargo"]

## Transport flies in along the wave heading, over the bunker, and out the far side,
## dropping paratroopers on the way
func spawn_transport_run(drops: int) -> Dictionary:
	var out: Vector3 = _heading_out()
	var start_pos: Vector3 = out * 220.0 + _heading_side() * _rng.randf_range(-40.0, 40.0)
	start_pos.y = _rng.randf_range(58.0, 76.0)
	var u: Dictionary = spawn_unit(UnitType.TRANSPORT_HELI, start_pos)
	u["fly_dir"] = (-out + _heading_side() * _rng.randf_range(-0.12, 0.12)).normalized()
	u["drops_left"] = drops
	u["drop_timer"] = _rng.randf_range(2.2, 3.5)
	return u

## Jets start far out so they're visible crossing the sky, and the radar raises
## an air-raid warning the moment they appear (~7 s before they can attack)
const JET_SPAWN_DIST := 520.0
const JET_ATTACK_DIST := 165.0

func spawn_fighter_jet_pass() -> Dictionary:
	var start_pos: Vector3 = _heading_out(12.0) * JET_SPAWN_DIST
	start_pos.y = _rng.randf_range(70.0, 100.0)
	var u: Dictionary = spawn_unit(UnitType.FIGHTER_JET, start_pos)
	# Swing in on a curve (not dead-on) so the contrail draws an arc across the sky
	u["aim_offset"] = _heading_side() * (_rng.randf_range(90.0, 140.0) * (-1.0 if _rng.randf() < 0.5 else 1.0))
	air_raid_incoming.emit(start_pos)
	return u

## Unarmed/departing units (empty transports, retreating landing craft, jets climbing
## out) no longer count toward the wave. Any cargo they never delivered is dropped
## from the wave total too.
func _mark_escaped(u: Dictionary) -> void:
	if u.get("escaped", false):
		return
	u["escaped"] = true
	wave_quota_total -= (0 if u.get("untallied", false) else 1) + _undelivered_cargo(u)
	wave_quota_updated.emit(wave_kills, wave_quota_total)

func _undelivered_cargo(u: Dictionary) -> int:
	match u["type"]:
		UnitType.APC:
			return 0 if u["unloaded"] else u.get("cargo", 0)
		UnitType.LANDING_CRAFT:
			return u.get("cargo_list", []).size()
		UnitType.TRANSPORT_HELI:
			return u.get("drops_left", 0)
	return 0

func spawn_unit(u_type: int, pos: Vector3) -> Dictionary:
	var built: Dictionary
	var hp: float = 30.0
	var radius: float = 2.0
	var speed: float = 10.0
	var armor: String = "soft"
	var points: int = 100
	var type_name: String = "INFANTRY"
	var is_air: bool = false

	match u_type:
		UnitType.LANDING_CRAFT:
			built = UnitFactoryScript.build_landing_craft()
			hp = 420.0 * _hp_mult
			radius = 5.5
			speed = 13.5 + aggression * 0.7
			armor = "naval"
			points = 350
			type_name = "LANDING CRAFT"
		UnitType.APC:
			built = UnitFactoryScript.build_apc()
			hp = 95.0 * _hp_mult
			radius = 3.4
			speed = 15.0 + aggression * 0.8
			armor = "heavy"
			points = 300
			type_name = "AMPHIBIOUS APC"
		UnitType.TANK:
			built = UnitFactoryScript.build_tank()
			hp = 150.0 * _hp_mult
			radius = 3.8
			speed = 9.0 + aggression * 0.45
			armor = "heavy"
			points = 400
			type_name = "BATTLE TANK"
		UnitType.INFANTRY:
			built = UnitFactoryScript.build_infantry()
			hp = 18.0 * _hp_mult
			radius = 1.65
			speed = 5.8 + aggression * 0.35
			armor = "soft"
			points = 100
			type_name = "INFANTRY"
		UnitType.PARATROOPER:
			built = UnitFactoryScript.build_paratrooper()
			hp = 18.0 * _hp_mult
			radius = 1.75
			speed = 6.2
			armor = "soft"
			points = 150
			type_name = "PARATROOPER"
			is_air = true
		UnitType.ATTACK_HELI:
			built = UnitFactoryScript.build_attack_heli()
			hp = 70.0 * _hp_mult
			radius = 3.8
			speed = 24.0 + aggression * 1.1
			armor = "medium"
			points = 350
			type_name = "ATTACK CHOPPER"
			is_air = true
		UnitType.TRANSPORT_HELI:
			built = UnitFactoryScript.build_transport_heli()
			hp = 100.0 * _hp_mult
			radius = 4.6
			speed = 28.0 + aggression * 1.0
			armor = "medium"
			points = 400
			type_name = "CHINOOK TRANSPORT"
			is_air = true
		UnitType.FIGHTER_JET:
			built = UnitFactoryScript.build_fighter_jet()
			hp = 110.0 * _hp_mult
			radius = 4.2
			speed = 44.0 + aggression * 1.6
			# Armored airframe: the 30mm barely scratches it; SAMs are the answer
			armor = "air_armored"
			points = 500
			type_name = "STRIKE FIGHTER"
			is_air = true

	var node: Node3D = built["root"]
	add_child(node)
	if not is_air:
		pos.y = UnitFactoryScript.get_ground_height(pos.x, pos.z)
	node.position = pos

	var unit_data: Dictionary = {
		"type": u_type,
		"type_name": type_name,
		"node": node,
		"hp": hp,
		"max_hp": hp,
		"radius": radius,
		"speed": speed,
		"armor": armor,
		"points": points,
		"is_air": is_air,
		"state": "approach",
		"fire_timer": _rng.randf_range(2.0, 4.5),
		"stop_dist": _rng.randf_range(34.0, 58.0),
		"strafe_phase": _rng.randf() * TAU,
		"unloaded": false,
		"chute_intact": (u_type == UnitType.PARATROOPER),
		"turret": built.get("turret", null),
		"rotor": built.get("rotor", null),
		"rotor2": built.get("rotor2", null),
		"ramp_pivot": built.get("ramp_pivot", null),
		"canopy": built.get("canopy", null)
	}
	units.append(unit_data)
	wave_spawned += 1
	return unit_data

func _update_units(delta: float) -> void:
	for i in range(units.size() - 1, -1, -1):
		var u: Dictionary = units[i]
		var node: Node3D = u["node"]
		if not is_instance_valid(node):
			units.remove_at(i)
			continue

		if u["rotor"] != null and is_instance_valid(u["rotor"]):
			u["rotor"].rotation.y += 22.0 * delta
		if u["rotor2"] != null and is_instance_valid(u["rotor2"]):
			u["rotor2"].rotation.y -= 22.0 * delta

		var pos: Vector3 = node.position
		var to_bunker := Vector3(-pos.x, 0.0, -pos.z)
		var horiz_dist: float = to_bunker.length()
		var dir_to_bunker: Vector3 = to_bunker / maxf(horiz_dist, 0.001)

		match u["type"]:
			UnitType.LANDING_CRAFT:
				# approach -> ramp_down -> unload (one at a time) -> ramp_up -> retreat.
				# Troops only exist once they walk off the ramp, so a closed boat can't shoot.
				if u["state"] == "approach":
					# Ease off the throttle over the last 30 m before beaching
					var remaining: float = (UnitFactoryScript.SHORELINE_Z - 1.0) - pos.z
					pos += dir_to_bunker * u["speed"] * clampf(remaining / 30.0, 0.3, 1.0) * delta
					pos.y = UnitFactoryScript.get_ground_height(pos.x, pos.z)
					node.position = pos
					node.look_at(pos + dir_to_bunker, Vector3.UP, true)
					if remaining <= 0.0:
						u["state"] = "ramp_down"
						u["state_timer"] = 0.0
				elif u["state"] == "ramp_down" or u["state"] == "ramp_up":
					# Ramp is hinged at its bottom edge: the top swings forward and down onto the sand
					u["state_timer"] += delta
					var t: float = clampf(u["state_timer"] / 1.2, 0.0, 1.0)
					var eased: float = t * t if u["state"] == "ramp_down" else 1.0 - (1.0 - t) * (1.0 - t)
					var from_deg: float = LC_RAMP_CLOSED_DEG if u["state"] == "ramp_down" else LC_RAMP_OPEN_DEG
					var to_deg: float = LC_RAMP_OPEN_DEG if u["state"] == "ramp_down" else LC_RAMP_CLOSED_DEG
					if u["ramp_pivot"] != null and is_instance_valid(u["ramp_pivot"]):
						u["ramp_pivot"].rotation_degrees.x = lerpf(from_deg, to_deg, eased)
					if t >= 1.0:
						if u["state"] == "ramp_down":
							if fx:
								fx.spawn_surface_impact(node.global_transform * Vector3(0.0, 0.0, 8.8), false, 1.2)
							u["state"] = "unload"
							u["state_timer"] = 0.35
						else:
							u["state"] = "retreat"
							_mark_escaped(u)
				elif u["state"] == "unload":
					u["state_timer"] -= delta
					if u["state_timer"] <= 0.0:
						var cargo: Array = u["cargo_list"]
						if cargo.is_empty():
							u["state"] = "ramp_up"
							u["state_timer"] = 0.0
						else:
							_disembark_one(u, cargo.pop_front(), dir_to_bunker)
							u["state_timer"] = 0.65
				elif u["state"] == "retreat":
					pos -= dir_to_bunker * (u["speed"] * 0.8) * delta
					node.position = pos
					if pos.z < -265.0:
						node.queue_free()
						units.remove_at(i)
						continue

			UnitType.APC:
				if horiz_dist > u["stop_dist"]:
					pos += dir_to_bunker * u["speed"] * delta
					pos.y = UnitFactoryScript.get_ground_height(pos.x, pos.z)
					node.position = pos
					node.look_at(pos + dir_to_bunker, Vector3.UP, true)
				else:
					if not u["unloaded"]:
						u["unloaded"] = true
						_unload_apc_squad(u, pos, dir_to_bunker)
					_enemy_fire_check(u, delta, 3.2, 6.0, false)

			UnitType.TANK:
				if horiz_dist > u["stop_dist"] + 10.0:
					pos += dir_to_bunker * u["speed"] * delta
					pos.y = UnitFactoryScript.get_ground_height(pos.x, pos.z)
					node.position = pos
					node.look_at(pos + dir_to_bunker, Vector3.UP, true)
				if u["turret"] != null and is_instance_valid(u["turret"]):
					u["turret"].look_at(Vector3(0.0, u["turret"].global_position.y, 0.0), Vector3.UP, true)
				if horiz_dist < 120.0:
					_enemy_fire_check(u, delta, 4.2, 11.0, true)

			UnitType.INFANTRY:
				if horiz_dist > 18.0:
					u["strafe_phase"] += delta * 3.5
					var side_vec := Vector3(-dir_to_bunker.z, 0.0, dir_to_bunker.x) * sin(u["strafe_phase"]) * 0.35
					var move_dir: Vector3 = (dir_to_bunker + side_vec).normalized()
					pos += move_dir * u["speed"] * delta
					pos.y = UnitFactoryScript.get_ground_height(pos.x, pos.z)
					node.position = pos
					node.look_at(pos + dir_to_bunker, Vector3.UP, true)
				_enemy_fire_check(u, delta, 3.4, 2.5, false)

			UnitType.PARATROOPER:
				var gy: float = UnitFactoryScript.get_ground_height(pos.x, pos.z)
				if pos.y > gy + 0.15:
					var fall_speed: float = u["speed"] if u["chute_intact"] else 34.0
					pos.y -= fall_speed * delta
					pos.x += sin(Time.get_ticks_msec() * 0.002 + u["strafe_phase"]) * 1.4 * delta
					node.position = pos
					node.look_at(pos + dir_to_bunker, Vector3.UP, true)
					if pos.y <= gy + 0.15:
						if not u["chute_intact"]:
							_kill_unit_at_index(i, "CHUTE COLLAPSED!")
							continue
						pos.y = gy
						node.position = pos
						u["type"] = UnitType.INFANTRY
						u["is_air"] = false
						if u["canopy"] != null and is_instance_valid(u["canopy"]):
							u["canopy"].queue_free()
							u["canopy"] = null
						if pos.z > 8.0:
							paratrooper_Alert.emit(pos)
				else:
					u["type"] = UnitType.INFANTRY
					u["is_air"] = false

			UnitType.ATTACK_HELI:
				u["strafe_phase"] += delta * 1.15
				if horiz_dist > 78.0:
					pos += dir_to_bunker * u["speed"] * delta
				else:
					var tangent := Vector3(-dir_to_bunker.z, 0.0, dir_to_bunker.x)
					pos += tangent * sin(u["strafe_phase"]) * 14.0 * delta
				pos.y = lerpf(pos.y, 32.0 + sin(u["strafe_phase"] * 1.7) * 4.0, 2.0 * delta)
				node.position = pos
				node.look_at(Vector3(0.0, pos.y - 4.0, 0.0), Vector3.UP, true)
				if horiz_dist < 145.0:
					_enemy_fire_check(u, delta, 3.6, 9.0, true)

			UnitType.TRANSPORT_HELI:
				var fly_dir: Vector3 = u.get("fly_dir", Vector3(1.0, 0.0, 0.0))
				pos += fly_dir * u["speed"] * delta
				node.position = pos
				node.look_at(pos + fly_dir, Vector3.UP, true)
				if u.get("drops_left", 0) > 0:
					u["drop_timer"] -= delta
					if u["drop_timer"] <= 0.0 and horiz_dist < 165.0:
						u["drops_left"] -= 1
						u["drop_timer"] = _rng.randf_range(1.6, 2.4)
						var para_pos: Vector3 = pos + Vector3(0.0, -3.5, 0.0)
						spawn_unit(UnitType.PARATROOPER, para_pos)
						if para_pos.z > 5.0:
							paratrooper_Alert.emit(para_pos)
						if u["drops_left"] == 0:
							_mark_escaped(u)
				if pos.length() > 280.0:
					_mark_escaped(u)
					node.queue_free()
					units.remove_at(i)
					continue

			UnitType.FIGHTER_JET:
				# Long white contrail so incoming jets are easy to spot across the sky
				u["trail_timer"] = u.get("trail_timer", 0.0) - delta
				if u["trail_timer"] <= 0.0:
					u["trail_timer"] = 0.08
					_spawn_smoke_puff(node.position, 3.0, 5.0, 12.0)
				if u["state"] == "approach":
					var curve: float = clampf((horiz_dist - 200.0) / 320.0, 0.0, 1.0)
					var target_pt: Vector3 = Vector3(0.0, 26.0, 0.0) + u.get("aim_offset", Vector3.ZERO) * curve
					var jet_dir: Vector3 = (target_pt - pos).normalized()
					pos += jet_dir * u["speed"] * delta
					node.position = pos
					node.look_at(pos + jet_dir, Vector3.UP, true)
					if horiz_dist < JET_ATTACK_DIST and not u["unloaded"]:
						u["unloaded"] = true
						_spawn_enemy_projectile(pos + Vector3(-2.5, -0.5, 0.0), BUNKER_TARGET_POS, 92.0, 12.0)
						_spawn_enemy_projectile(pos + Vector3(2.5, -0.5, 0.0), BUNKER_TARGET_POS, 92.0, 12.0)
					if horiz_dist < 58.0:
						u["state"] = "climb_out"
						_mark_escaped(u)
						u["fly_dir"] = Vector3(dir_to_bunker.x, 0.38, dir_to_bunker.z).normalized()
				elif u["state"] == "climb_out":
					var out_dir: Vector3 = u["fly_dir"]
					pos += out_dir * (u["speed"] * 1.15) * delta
					node.position = pos
					node.look_at(pos + out_dir, Vector3.UP, true)
					if pos.length() > 360.0 or pos.y > 190.0:
						node.queue_free()
						units.remove_at(i)
						continue

## Walks one passenger out over the lowered ramp onto the beach
func _disembark_one(lc: Dictionary, unit_type: int, dir_to_bunker: Vector3) -> void:
	var node: Node3D = lc["node"]
	var exit_pos: Vector3 = node.global_transform * Vector3(_rng.randf_range(-1.6, 1.6), 0.0, 9.5)
	if unit_type == UnitType.TANK:
		exit_pos = node.global_transform * Vector3(0.0, 0.0, 11.0)
	var u: Dictionary = spawn_unit(unit_type, exit_pos)
	if is_instance_valid(u["node"]):
		u["node"].look_at(u["node"].position + dir_to_bunker, Vector3.UP, true)

func _unload_apc_squad(u: Dictionary, pos: Vector3, dir_to_bunker: Vector3) -> void:
	for k in range(u.get("cargo", 6)):
		var spread := Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-3.5, 3.5))
		spawn_unit(UnitType.INFANTRY, pos + dir_to_bunker * 3.0 + spread)

func _enemy_fire_check(u: Dictionary, delta: float, base_cooldown: float, damage: float, is_rocket_or_shell: bool) -> void:
	u["fire_timer"] -= delta * (0.75 + aggression * 0.12)
	if u["fire_timer"] <= 0.0:
		u["fire_timer"] = _rng.randf_range(base_cooldown * 0.8, base_cooldown * 1.25)
		var origin: Vector3 = u["node"].global_position + Vector3(0.0, 2.0, 0.0)
		if is_rocket_or_shell:
			_spawn_enemy_projectile(origin, BUNKER_TARGET_POS, 64.0 + aggression * 3.0, damage)
		else:
			_spawn_enemy_projectile(origin, BUNKER_TARGET_POS + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-0.8, 0.8), 0.0), 115.0, damage, false)

func spawn_supply_plane() -> void:
	var built: Dictionary = UnitFactoryScript.build_supply_plane()
	var node: Node3D = built["root"]
	add_child(node)
	var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
	var z_line: float = _rng.randf_range(-115.0, -55.0)
	var start_pos := Vector3(side * 220.0, 72.0, z_line)
	var fly_dir := Vector3(-side, 0.0, 0.0)
	node.position = start_pos
	node.look_at(start_pos + fly_dir, Vector3.UP, true)

	supply_planes.append({
		"node": node,
		"fly_dir": fly_dir,
		"speed": 34.0,
		"drops_left": 2,
		"drop_timer": 3.2
	})
	supply_plane_inbound.emit()

func _update_supply_planes(delta: float) -> void:
	for i in range(supply_planes.size() - 1, -1, -1):
		var sp: Dictionary = supply_planes[i]
		var node: Node3D = sp["node"]
		if not is_instance_valid(node):
			supply_planes.remove_at(i)
			continue
		node.position += sp["fly_dir"] * sp["speed"] * delta
		if sp["drops_left"] > 0 and abs(node.position.x) < 85.0:
			sp["drop_timer"] -= delta
			if sp["drop_timer"] <= 0.0:
				sp["drops_left"] -= 1
				sp["drop_timer"] = 1.65
				var is_golden: bool = (_rng.randf() < 0.22)
				spawn_supply_crate(node.position + Vector3(0.0, -3.0, 0.0), is_golden)
		if abs(node.position.x) > 250.0:
			node.queue_free()
			supply_planes.remove_at(i)

func spawn_supply_crate(pos: Vector3, is_golden: bool = false) -> void:
	var built: Dictionary = UnitFactoryScript.build_supply_crate(is_golden)
	var node: Node3D = built["root"]
	node.position = pos
	add_child(node)
	supply_crates.append({
		"node": node,
		"is_golden": is_golden,
		"radius": 2.8,
		"phase": _rng.randf() * TAU,
		"speed": 5.2
	})

func _update_supply_crates(delta: float) -> void:
	for i in range(supply_crates.size() - 1, -1, -1):
		var sc: Dictionary = supply_crates[i]
		var node: Node3D = sc["node"]
		if not is_instance_valid(node):
			supply_crates.remove_at(i)
			continue
		sc["phase"] += delta * 2.4
		node.position.y -= sc["speed"] * delta
		node.position.x += sin(sc["phase"]) * 2.2 * delta
		node.rotation.z = sin(sc["phase"]) * 0.16
		node.rotation.y += 0.65 * delta

		var gy: float = UnitFactoryScript.get_ground_height(node.position.x, node.position.z)
		if node.position.y <= gy + 1.0:
			if fx:
				fx.spawn_surface_impact(node.position, node.position.z < -82.0, 1.3)
			supply_lost.emit(node.position)
			node.queue_free()
			supply_crates.remove_at(i)

func spawn_player_projectile(kind: String, origin: Vector3, dir: Vector3, locked_unit: Dictionary = {}) -> void:
	var mi := MeshInstance3D.new()
	var speed: float = 420.0
	var gravity: float = 0.0
	var dmg: float = 20.0
	var splash: float = 0.0
	var max_age: float = 2.2

	match kind:
		"mg":
			mi.mesh = _tracer_mesh
			mi.material_override = _mat_tracer_mg
			speed = 460.0
			dmg = 22.0
			max_age = 1.6
		"ciws":
			mi.mesh = _tracer_mesh
			mi.material_override = _mat_tracer_ciws
			speed = 540.0
			dmg = 38.0
			max_age = 1.6
		"pistol":
			mi.mesh = _tracer_mesh
			mi.scale = Vector3(0.7, 0.7, 0.5)
			mi.material_override = _mat_tracer_mg
			speed = 380.0
			dmg = 16.0
			max_age = 1.5
		"cannon":
			mi.mesh = _shell_mesh
			mi.material_override = _mat_shell
			speed = 215.0
			gravity = 9.8
			dmg = 155.0
			splash = 11.5
			max_age = 3.5
			if heavy_gun_installed:
				speed = 240.0
				dmg = 280.0
				splash = 13.5
				mi.scale = Vector3.ONE * 1.35
		"sam":
			mi.mesh = _missile_mesh
			mi.material_override = _mat_sam
			speed = 165.0
			dmg = 180.0
			splash = 8.0
			max_age = 4.5

	mi.position = origin
	add_child(mi)
	mi.look_at(origin + dir, Vector3.UP, true)
	if kind == "sam":
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	projectiles.append({
		"node": mi,
		"kind": kind,
		"is_player": true,
		"vel": dir.normalized() * speed,
		"speed": speed,
		"gravity": gravity,
		"damage": dmg,
		"splash": splash,
		"target": locked_unit,
		"pierces_naval": kind == "cannon" and heavy_gun_installed,
		"age": 0.0,
		"max_age": max_age,
		"smoke_timer": 0.0
	})

func _spawn_enemy_projectile(origin: Vector3, target_pos: Vector3, speed: float, damage: float, shootable: bool = true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _shell_mesh if shootable else _tracer_mesh
	if not shootable:
		mi.scale = Vector3(0.8, 0.8, 0.65)
	mi.material_override = _mat_enemy_proj
	mi.position = origin
	add_child(mi)

	var dir: Vector3 = (target_pos - origin).normalized()
	mi.look_at(origin + dir, Vector3.UP, true)

	projectiles.append({
		"node": mi,
		"kind": "enemy_ordnance" if shootable else "enemy_bullet",
		"is_player": false,
		"shootable": shootable,
		"vel": dir * speed,
		"speed": speed,
		"gravity": 0.0,
		"damage": damage,
		"splash": 0.0,
		"age": 0.0,
		"max_age": 6.0,
		"smoke_timer": 0.0
	})

func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		if p.get("dead", false) or not is_instance_valid(p["node"]):
			projectiles.remove_at(i)
			continue
		var node: Node3D = p["node"]

		p["age"] += delta
		if p["age"] >= p["max_age"]:
			node.queue_free()
			projectiles.remove_at(i)
			continue

		var old_pos: Vector3 = node.position

		if p["kind"] == "sam":
			var tgt: Dictionary = p.get("target", {})
			if tgt.is_empty() or not is_instance_valid(tgt.get("node", null)):
				p["target"] = _find_nearest_air_unit(old_pos)
				tgt = p["target"]
			if not tgt.is_empty() and is_instance_valid(tgt.get("node", null)):
				var tpos: Vector3 = tgt["node"].global_position
				var desired: Vector3 = (tpos - old_pos).normalized() * p["speed"]
				p["vel"] = p["vel"].lerp(desired, clampf(delta * 6.5, 0.0, 1.0)).normalized() * p["speed"]
			p["smoke_timer"] -= delta
			if p["smoke_timer"] <= 0.0:
				p["smoke_timer"] = 0.035
				_spawn_smoke_puff(old_pos)

		if p["gravity"] != 0.0:
			p["vel"].y -= p["gravity"] * delta

		var new_pos: Vector3 = old_pos + p["vel"] * delta
		node.position = new_pos
		if p["kind"] != "sam" and p["vel"].length_squared() > 0.1:
			node.look_at(new_pos + p["vel"].normalized(), Vector3.UP, true)

		if p["is_player"]:
			if _check_player_projectile_hits(p, old_pos, new_pos):
				node.queue_free()
				projectiles.remove_at(i)
				continue
		else:
			if new_pos.distance_to(BUNKER_TARGET_POS) < 4.5:
				bunker_damaged.emit(p["damage"], old_pos - p["vel"].normalized() * 20.0)
				if fx and p["shootable"]:
					fx.spawn_explosion(new_pos, 0.75, false)
				node.queue_free()
				projectiles.remove_at(i)
				continue

		var gy: float = UnitFactoryScript.get_ground_height(new_pos.x, new_pos.z)
		if new_pos.y <= gy:
			var impact_pos := Vector3(new_pos.x, gy, new_pos.z)
			var in_sea: bool = (new_pos.z < -82.0)
			if p["kind"] == "cannon" or p["kind"] == "sam":
				_apply_aoe_damage(impact_pos, p["splash"], p["damage"] * 0.85, p.get("pierces_naval", false))
				if fx:
					fx.spawn_explosion(impact_pos, 1.85, true)
					fx.spawn_surface_impact(impact_pos, in_sea, 1.8)
				if sfx:
					sfx.play("explosion_large" if p["kind"] == "cannon" else "explosion_small", -2.0, _rng.randf_range(0.9, 1.1))
			elif p["is_player"] and fx:
				fx.spawn_surface_impact(impact_pos, in_sea, 0.55)
			node.queue_free()
			projectiles.remove_at(i)

func _check_player_projectile_hits(p: Dictionary, a: Vector3, b: Vector3) -> bool:
	var kind: String = p["kind"]

	for c_idx in range(supply_crates.size() - 1, -1, -1):
		var sc: Dictionary = supply_crates[c_idx]
		if not is_instance_valid(sc["node"]):
			continue
		var cpos: Vector3 = sc["node"].global_position
		if _segment_hits_sphere(a, b, cpos, sc["radius"]) or _segment_hits_sphere(a, b, cpos + Vector3(0.0, 4.2, 0.0), 3.0):
			var is_gold: bool = sc["is_golden"]
			if fx:
				fx.spawn_explosion(cpos, 1.1, false)
			if sfx:
				sfx.play("supply_pickup", 0.0, 1.0)
			supply_claimed.emit(cpos, is_gold)
			sc["node"].queue_free()
			supply_crates.remove_at(c_idx)
			return true

	if kind == "mg" or kind == "ciws" or kind == "pistol":
		for e_idx in range(projectiles.size() - 1, -1, -1):
			var ep: Dictionary = projectiles[e_idx]
			if ep["is_player"] or not ep.get("shootable", false) or ep.get("dead", false) or not is_instance_valid(ep["node"]):
				continue
			var epos: Vector3 = ep["node"].global_position
			if _segment_hits_sphere(a, b, epos, 2.2):
				if fx:
					fx.spawn_explosion(epos, 0.85, false)
				if sfx:
					sfx.play("explosion_small", -3.0, 1.2)
				enemy_killed.emit("MISSILE INTERCEPT", epos, 75, "MISSILE INTERCEPT!")
				# Mark dead instead of removing: we're inside _update_projectiles' loop,
				# and remove_at here would shift the caller's index.
				ep["node"].queue_free()
				ep["dead"] = true
				return true

	for u_idx in range(units.size() - 1, -1, -1):
		var u: Dictionary = units[u_idx]
		if not is_instance_valid(u["node"]):
			continue
		var upos: Vector3 = u["node"].global_position + Vector3(0.0, 1.2, 0.0)

		if u["type"] == UnitType.PARATROOPER and u["chute_intact"] and u["canopy"] != null and is_instance_valid(u["canopy"]):
			var canopy_pos: Vector3 = u["node"].global_position + Vector3(0.0, 4.5, 0.0)
			if _segment_hits_sphere(a, b, canopy_pos, 2.75):
				u["chute_intact"] = false
				u["canopy"].queue_free()
				u["canopy"] = null
				if fx:
					fx.spawn_surface_impact(canopy_pos, false, 0.9)
				return true

		if _segment_hits_sphere(a, b, upos, u["radius"]):
			if kind == "cannon" or kind == "sam":
				_apply_aoe_damage(upos, p["splash"], p["damage"], p.get("pierces_naval", false))
				if fx:
					fx.spawn_explosion(upos, 2.1, true)
				if sfx:
					sfx.play("explosion_large", 0.0, _rng.randf_range(0.92, 1.08))
				return true

			var dmg: float = p["damage"]
			if u["armor"] == "naval":
				dmg = 0.0
				if fx:
					fx.spawn_ricochet_spark(b)
				hull_deflected.emit(upos)
			elif u["armor"] == "air_armored":
				dmg *= 0.6 if kind == "ciws" else 0.25
				if fx:
					fx.spawn_ricochet_spark(b)
				air_armor_deflected.emit(upos)
			elif u["armor"] == "heavy" and kind != "ciws":
				dmg = 1.5
				if fx:
					fx.spawn_ricochet_spark(b)
				if sfx and _rng.randf() < 0.35:
					sfx.play("ricochet", -4.0, _rng.randf_range(0.9, 1.15))
				armor_ricochet.emit(upos)
			else:
				if fx:
					fx.spawn_ricochet_spark(b)

			u["hp"] -= dmg
			if u["hp"] <= 0.0:
				_kill_unit_at_index(u_idx, "")
			return true

	return false

func _apply_aoe_damage(center: Vector3, radius: float, max_dmg: float, pierces_naval: bool = false) -> void:
	for u_idx in range(units.size() - 1, -1, -1):
		var u: Dictionary = units[u_idx]
		if not is_instance_valid(u["node"]):
			continue
		if u["armor"] == "naval" and not pierces_naval:
			if u["node"].global_position.distance_to(center) <= radius + u["radius"]:
				hull_deflected.emit(u["node"].global_position)
			continue
		var upos: Vector3 = u["node"].global_position
		var dist: float = upos.distance_to(center)
		if dist <= radius + u["radius"]:
			var falloff: float = clampf(1.0 - (dist / (radius + u["radius"] + 0.1)) * 0.5, 0.35, 1.0)
			u["hp"] -= max_dmg * falloff
			if u["hp"] <= 0.0:
				_kill_unit_at_index(u_idx, "")

func _kill_unit_at_index(idx: int, custom_bonus: String) -> void:
	if idx < 0 or idx >= units.size():
		return
	var u: Dictionary = units[idx]
	var node: Node3D = u["node"]
	var pos: Vector3 = node.global_position if is_instance_valid(node) else Vector3.ZERO
	var is_heavy: bool = (u["armor"] == "heavy" or u["is_air"])

	if fx:
		fx.spawn_explosion(pos + Vector3(0.0, 1.2, 0.0), 2.0 if is_heavy else 1.0, is_heavy)
	if sfx:
		sfx.play("explosion_large" if is_heavy else "explosion_small", -1.0, _rng.randf_range(0.9, 1.1))

	var bonus: String = custom_bonus
	var pts: int = u["points"]
	if u["type"] == UnitType.APC and not u["unloaded"]:
		pts += 150
		bonus = "FULL APC DESTROYED!"
	elif u["type"] == UnitType.LANDING_CRAFT and not u.get("cargo_list", []).is_empty():
		pts += 120 * u["cargo_list"].size()
		bonus = "SUNK WITH %d ABOARD!" % u["cargo_list"].size()

	# Cargo that dies with its carrier will never spawn, so it leaves the wave total;
	# a unit that had already escaped was already taken off the total
	if not u.get("escaped", false):
		wave_quota_total -= _undelivered_cargo(u)
		if not u.get("untallied", false):
			wave_kills += 1
	enemy_killed.emit(u["type_name"], pos + Vector3(0.0, 2.0, 0.0), pts, bonus)
	wave_quota_updated.emit(wave_kills, wave_quota_total)

	if is_instance_valid(node):
		node.queue_free()
	units.remove_at(idx)

func _find_nearest_air_unit(from_pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = 999999.0
	for u in units:
		if u["is_air"] and is_instance_valid(u["node"]):
			var d: float = from_pos.distance_to(u["node"].global_position)
			if d < best_d:
				best_d = d
				best = u
	return best

func _spawn_smoke_puff(pos: Vector3, max_age: float = 0.55, start_scale: float = 0.7, end_scale: float = 2.6) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _puff_mesh
	mi.material_override = _mat_smoke
	mi.position = pos
	add_child(mi)
	smoke_puffs.append({
		"node": mi,
		"age": 0.0,
		"max_age": max_age,
		"s0": start_scale,
		"s1": end_scale
	})

func _update_smoke_puffs(delta: float) -> void:
	for i in range(smoke_puffs.size() - 1, -1, -1):
		var sm: Dictionary = smoke_puffs[i]
		sm["age"] += delta
		var t: float = sm["age"] / sm["max_age"]
		if t >= 1.0 or not is_instance_valid(sm["node"]):
			if is_instance_valid(sm["node"]):
				sm["node"].queue_free()
			smoke_puffs.remove_at(i)
			continue
		sm["node"].scale = Vector3.ONE * lerpf(sm.get("s0", 0.7), sm.get("s1", 2.6), t)

static func _segment_hits_sphere(a: Vector3, b: Vector3, center: Vector3, radius: float) -> bool:
	var ab: Vector3 = b - a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 0.00001:
		return a.distance_squared_to(center) <= radius * radius
	var t: float = clampf((center - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector3 = a + ab * t
	return closest.distance_squared_to(center) <= radius * radius

