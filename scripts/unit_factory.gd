class_name UnitFactory
extends RefCounted

## Procedural 3D Classic Military Arcade Model & Battlefield Builder
## Builds Olive Drab armor, Navy Grey landing craft, Attack & Transport Helicopters,
## Swept-Wing Fighter Jets, Paratroopers, C-130 Cargo Planes, and the Coastal Bunker.

## Bunker hilltop: flat pad at HILL_TOP_Y out to HILL_PAD_RADIUS, then a concave
## (steep-then-flattening) falloff so the whole slope and beach stay visible from the gun.
const HILL_TOP_Y := 16.0
const HILL_PAD_RADIUS := 7.0
const HILL_FALLOFF := 72.0
const SHORELINE_Z := -82.0

static func get_ground_height(x: float, z: float) -> float:
	var r: float = Vector2(x, z).length()
	var hill: float = HILL_TOP_Y
	if r > HILL_PAD_RADIUS:
		var f: float = 1.0 - clampf((r - HILL_PAD_RADIUS) / HILL_FALLOFF, 0.0, 1.0)
		hill = HILL_TOP_Y * f * f
	# Sea zone in front of beach (North = -Z)
	if z < SHORELINE_Z:
		return 0.0
	# Low ground: sandy beach rising off the shoreline, rolling hills to the flanks and rear
	var t: float = clampf((z - SHORELINE_Z) / 40.0, 0.0, 1.0)
	var low: float = lerpf(0.0, 2.2, t) + sin(x * 0.08) * 0.35 * sin(t * PI)
	var rear_factor: float = clampf((z + 18.0) / 90.0, 0.0, 1.0)
	low += (sin(x * 0.045) * cos(z * 0.045) + 0.5) * 3.8 * rear_factor
	return maxf(low, hill)

## Builds a vertex-colored heightfield mesh that exactly follows get_ground_height
static func build_terrain_mesh(x_min: float, x_max: float, z_min: float, z_max: float, step: float) -> ArrayMesh:
	var col_wet := Color(0.50, 0.43, 0.30)
	var col_sand := Color(0.76, 0.67, 0.48)
	var col_dry_grass := Color(0.52, 0.50, 0.32)
	var col_grass := Color(0.28, 0.38, 0.20)
	var nx: int = int(ceil((x_max - x_min) / step))
	var nz: int = int(ceil((z_max - z_min) / step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(nz + 1):
		for ix in range(nx + 1):
			var x: float = x_min + ix * step
			var z: float = z_min + iz * step
			var h: float = get_ground_height(x, z)
			# Sand on the beach and lower hill face, blending to grass up top and inland
			var sandiness: float = clampf((-z - 10.0) / 30.0, 0.0, 1.0) * (1.0 - clampf((h - 9.0) / 6.0, 0.0, 1.0))
			var c: Color = col_grass.lerp(col_dry_grass, clampf(h / HILL_TOP_Y, 0.0, 1.0) * 0.6).lerp(col_sand, sandiness)
			if z < SHORELINE_Z + 10.0:
				c = c.lerp(col_wet, clampf((SHORELINE_Z + 10.0 - z) / 10.0, 0.0, 1.0))
			var dhdx: float = (get_ground_height(x + 0.5, z) - get_ground_height(x - 0.5, z))
			var dhdz: float = (get_ground_height(x, z + 0.5) - get_ground_height(x, z - 0.5))
			st.set_normal(Vector3(-dhdx, 1.0, -dhdz).normalized())
			st.set_color(c)
			st.add_vertex(Vector3(x, h, z))
	for iz in range(nz):
		for ix in range(nx):
			var i0: int = iz * (nx + 1) + ix
			var i1: int = i0 + 1
			var i2: int = i0 + nx + 1
			var i3: int = i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)
	return st.commit()

static func make_mat(color: Color, roughness: float = 0.75, metallic: float = 0.1, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func add_cyl(parent: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func add_sphere(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, hemisphere: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = height
	sm.is_hemisphere = hemisphere
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

## Builds the entire 360-degree coastal battlefield environment
static func build_battlefield(world_root: Node3D) -> Dictionary:
	var env_node := Node3D.new()
	env_node.name = "BattlefieldGeometry"
	world_root.add_child(env_node)

	var mat_ocean := make_mat(Color(0.07, 0.24, 0.36), 0.25, 0.2)
	var mat_foam := make_mat(Color(0.78, 0.88, 0.92), 0.9, 0.0)
	var mat_grass := make_mat(Color(0.28, 0.38, 0.20), 0.95, 0.0)
	var mat_concrete := make_mat(Color(0.46, 0.48, 0.45), 0.88, 0.05)
	var mat_dark_concrete := make_mat(Color(0.30, 0.32, 0.30), 0.92, 0.05)
	var mat_rust_steel := make_mat(Color(0.26, 0.23, 0.20), 0.65, 0.45)
	var mat_sandbag := make_mat(Color(0.62, 0.55, 0.38), 0.95, 0.0)

	# 1. Ocean plane (-Z North invasion sea)
	var ocean := add_box(env_node, Vector3(900.0, 1.0, 420.0), Vector3(0.0, -0.5, -290.0), mat_ocean)
	var shoreline_foam := add_box(env_node, Vector3(700.0, 0.15, 5.5), Vector3(0.0, 0.05, SHORELINE_Z), mat_foam)

	# 2-3. Heightfield terrain: beach rising to the bunker hilltop, rolling hills to flanks/rear
	var mat_terrain := StandardMaterial3D.new()
	mat_terrain.vertex_color_use_as_albedo = true
	mat_terrain.roughness = 0.93
	mat_terrain.cull_mode = BaseMaterial3D.CULL_DISABLED
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = build_terrain_mesh(-360.0, 360.0, SHORELINE_Z, 320.0, 3.0)
	terrain.material_override = mat_terrain
	env_node.add_child(terrain)

	# 4. Distant Perimeter Hills & Ridge Silhouettes around Flanks & Rear
	var rng := RandomNumberGenerator.new()
	rng.seed = 19442000
	for i in range(28):
		var angle: float = lerpf(-0.15 * PI, 1.15 * PI, float(i) / 27.0) # East -> South -> West arc
		var dist: float = rng.randf_range(95.0, 185.0)
		var hx: float = cos(angle) * dist
		var hz: float = sin(angle) * dist
		var hr: float = rng.randf_range(18.0, 38.0)
		var hh: float = rng.randf_range(12.0, 28.0)
		add_sphere(env_node, hr, hh, Vector3(hx, 2.5, hz), mat_grass, true)

	# 5. Hilltop gun emplacement at (0, HILL_TOP_Y, 0): low concrete pad dug into the
	# crest so nothing rises into the gunner's forward/downward sightline
	add_cyl(env_node, 4.2, 4.8, 3.0, Vector3(0.0, HILL_TOP_Y - 1.0, 0.0), mat_concrete)
	add_cyl(env_node, 2.6, 2.9, 0.5, Vector3(0.0, HILL_TOP_Y + 0.75, 0.0), mat_dark_concrete)
	# Sandbags on the rear half only (+Z), leaving the beach-facing arc open
	for i in range(9):
		var a: float = lerpf(0.12, PI - 0.12, float(i) / 8.0)
		var sx: float = cos(a) * 5.0
		var sz: float = sin(a) * 5.0
		add_box(env_node, Vector3(1.5, 0.65, 0.85), Vector3(sx, HILL_TOP_Y + 0.33, sz), mat_sandbag, Vector3(0.0, rad_to_deg(-a) + 90.0, 0.0))

	# 6. Beach Obstacles: Czech Hedgehogs (Steel Tank Traps) & Dragon's Teeth
	var trap_positions: Array[Vector3] = [
		Vector3(-42, 0, -62), Vector3(-26, 0, -58), Vector3(-11, 0, -64),
		Vector3(9, 0, -60), Vector3(25, 0, -63), Vector3(44, 0, -57),
		Vector3(-34, 0, -40), Vector3(-16, 0, -37), Vector3(15, 0, -39), Vector3(33, 0, -42),
		Vector3(-56, 0, -48), Vector3(55, 0, -50)
	]
	for tp in trap_positions:
		var gy: float = get_ground_height(tp.x, tp.z)
		var hh := Node3D.new()
		hh.position = Vector3(tp.x, gy + 0.85, tp.z)
		hh.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 180.0), 0.0)
		env_node.add_child(hh)
		add_box(hh, Vector3(0.22, 2.4, 0.22), Vector3.ZERO, mat_rust_steel, Vector3(45, 0, 35))
		add_box(hh, Vector3(0.22, 2.4, 0.22), Vector3.ZERO, mat_rust_steel, Vector3(-45, 0, -35))
		add_box(hh, Vector3(0.22, 2.4, 0.22), Vector3.ZERO, mat_rust_steel, Vector3(0, 45, 55))

	# 7. Distant Offshore Naval Blockade Silhouettes (Horizon atmosphere)
	for i in range(3):
		var sx: float = -160.0 + float(i) * 160.0
		var sz: float = -330.0 - float(i % 2) * 35.0
		var ship := Node3D.new()
		ship.position = Vector3(sx, 0.0, sz)
		env_node.add_child(ship)
		add_box(ship, Vector3(36.0, 4.5, 8.0), Vector3(0, 2.2, 0), mat_dark_concrete)
		add_box(ship, Vector3(10.0, 6.5, 5.5), Vector3(-2.0, 6.5, 0), mat_concrete)
		add_cyl(ship, 0.8, 1.1, 5.0, Vector3(5.0, 7.5, 0), mat_rust_steel)

	return {
		"ocean": ocean,
		"shoreline_foam": shoreline_foam,
		"ocean_mat": mat_ocean
	}

## 1. Landing Craft (LCAC / Naval Assault Barge)
static func build_landing_craft() -> Dictionary:
	var root := Node3D.new()
	var mat_hull := make_mat(Color(0.28, 0.33, 0.36), 0.7, 0.2)
	var mat_deck := make_mat(Color(0.22, 0.25, 0.27), 0.85, 0.1)
	var mat_olive := make_mat(Color(0.29, 0.35, 0.21), 0.8, 0.1)
	var mat_foam := make_mat(Color(0.88, 0.95, 1.0), 0.4, 0.0, true)

	# Main barge hull & side walls
	add_box(root, Vector3(6.8, 1.4, 13.5), Vector3(0.0, 0.8, 0.0), mat_deck)
	add_box(root, Vector3(0.65, 2.4, 13.5), Vector3(-3.2, 1.6, 0.0), mat_hull)
	add_box(root, Vector3(0.65, 2.4, 13.5), Vector3(3.2, 1.6, 0.0), mat_hull)
	# Rear bridge / wheelhouse
	add_box(root, Vector3(5.6, 3.0, 3.2), Vector3(0.0, 2.6, -4.8), mat_hull)
	add_box(root, Vector3(3.4, 1.2, 1.8), Vector3(0.0, 4.3, -4.8), mat_olive)
	# Wake foam strip
	add_box(root, Vector3(7.6, 0.15, 2.2), Vector3(0.0, 0.12, 7.2), mat_foam)

	# Bow ramp (+Z faces the beach), hinged along its bottom edge: rotating the pivot
	# +X swings the top forward and down. Closed = slightly raked back.
	var ramp_pivot := Node3D.new()
	ramp_pivot.position = Vector3(0.0, 0.9, 6.7)
	ramp_pivot.rotation_degrees.x = -6.0
	root.add_child(ramp_pivot)
	add_box(ramp_pivot, Vector3(5.6, 2.3, 0.35), Vector3(0.0, 1.15, 0.0), mat_hull)
	# Cross-ribs on the inner face so the ramp reads as a ramp once it's down
	for k in range(4):
		add_box(ramp_pivot, Vector3(5.0, 0.12, 0.12), Vector3(0.0, 0.35 + k * 0.55, -0.22), mat_deck)

	return {"root": root, "ramp_pivot": ramp_pivot}

## 2. Amphibious APC (Armored Personnel Carrier)
static func build_apc() -> Dictionary:
	var root := Node3D.new()
	var mat_olive := make_mat(Color(0.31, 0.37, 0.22), 0.75, 0.15)
	var mat_dark := make_mat(Color(0.16, 0.18, 0.15), 0.9, 0.1)
	var mat_steel := make_mat(Color(0.24, 0.26, 0.22), 0.5, 0.5)

	# Sloped armored chassis
	add_box(root, Vector3(3.4, 1.7, 6.2), Vector3(0.0, 1.25, 0.0), mat_olive)
	add_box(root, Vector3(3.2, 1.0, 1.8), Vector3(0.0, 1.35, 3.2), mat_olive, Vector3(26.0, 0.0, 0.0))
	# 6 heavy wheels
	for z_off in [-2.1, 0.0, 2.1]:
		add_cyl(root, 0.65, 0.65, 0.45, Vector3(-1.75, 0.65, z_off), mat_dark, Vector3(0, 0, 90))
		add_cyl(root, 0.65, 0.65, 0.45, Vector3(1.75, 0.65, z_off), mat_dark, Vector3(0, 0, 90))
	# Top autocannon turret
	var turret := Node3D.new()
	turret.position = Vector3(0.0, 2.25, 0.6)
	root.add_child(turret)
	add_cyl(turret, 0.75, 0.95, 0.65, Vector3.ZERO, mat_olive)
	add_cyl(turret, 0.10, 0.12, 2.1, Vector3(0.0, 0.1, 1.2), mat_steel, Vector3(90, 0, 0))

	return {"root": root, "turret": turret}

## 3. Main Battle Tank (Heavy Olive Drab Armor)
static func build_tank() -> Dictionary:
	var root := Node3D.new()
	var mat_olive := make_mat(Color(0.27, 0.33, 0.18), 0.72, 0.2)
	var mat_tread := make_mat(Color(0.14, 0.15, 0.13), 0.92, 0.1)
	var mat_barrel := make_mat(Color(0.20, 0.23, 0.16), 0.55, 0.45)

	# Left & Right caterpillar treads
	add_box(root, Vector3(0.95, 1.15, 7.2), Vector3(-1.85, 0.65, 0.0), mat_tread)
	add_box(root, Vector3(0.95, 1.15, 7.2), Vector3(1.85, 0.65, 0.0), mat_tread)
	# Main armored hull
	add_box(root, Vector3(3.2, 1.25, 6.8), Vector3(0.0, 1.15, 0.0), mat_olive)
	# Rotating Turret + Long 120mm Cannon Barrel (+Z forward)
	var turret := Node3D.new()
	turret.position = Vector3(0.0, 2.05, -0.2)
	root.add_child(turret)
	add_box(turret, Vector3(2.5, 0.95, 3.4), Vector3(0.0, 0.2, 0.0), mat_olive)
	add_cyl(turret, 0.16, 0.20, 4.6, Vector3(0.0, 0.25, 2.8), mat_barrel, Vector3(90, 0, 0))

	return {"root": root, "turret": turret}

## 4. Infantry Soldier
static func build_infantry() -> Dictionary:
	var root := Node3D.new()
	var mat_uniform := make_mat(Color(0.32, 0.37, 0.22), 0.9, 0.0)
	var mat_helmet := make_mat(Color(0.22, 0.27, 0.15), 0.7, 0.1)
	var mat_skin := make_mat(Color(0.82, 0.66, 0.52), 0.85, 0.0)
	var mat_gun := make_mat(Color(0.15, 0.15, 0.15), 0.5, 0.5)

	# Legs & Torso (scaled slightly larger than real-life for crisp arcade visibility at range)
	add_box(root, Vector3(0.32, 0.95, 0.32), Vector3(-0.22, 0.48, 0.0), mat_uniform)
	add_box(root, Vector3(0.32, 0.95, 0.32), Vector3(0.22, 0.48, 0.0), mat_uniform)
	add_box(root, Vector3(0.82, 1.05, 0.48), Vector3(0.0, 1.45, 0.0), mat_uniform)
	# Head & Olive Brodie/PASGT Helmet
	add_sphere(root, 0.28, 0.56, Vector3(0.0, 2.22, 0.0), mat_skin)
	add_sphere(root, 0.34, 0.42, Vector3(0.0, 2.30, 0.0), mat_helmet, true)
	# Rifle
	add_box(root, Vector3(0.14, 0.18, 1.15), Vector3(0.32, 1.55, 0.45), mat_gun)

	return {"root": root}

## 5. Paratrooper (Infantry with Shootable Parachute Canopy)
static func build_paratrooper() -> Dictionary:
	var data: Dictionary = build_infantry()
	var root: Node3D = data["root"]

	var canopy_root := Node3D.new()
	canopy_root.position = Vector3(0.0, 4.5, 0.0)
	root.add_child(canopy_root)

	var mat_chute := make_mat(Color(0.76, 0.72, 0.54), 0.85, 0.0)
	var mat_cord := make_mat(Color(0.35, 0.35, 0.30), 0.9, 0.0)
	add_sphere(canopy_root, 2.6, 2.1, Vector3.ZERO, mat_chute, true)
	# 4 shroud lines connecting canopy to trooper
	for x_s in [-1.4, 1.4]:
		for z_s in [-1.0, 1.0]:
			add_cyl(canopy_root, 0.03, 0.03, 3.2, Vector3(x_s * 0.5, -1.4, z_s * 0.5), mat_cord, Vector3(z_s * 14.0, 0.0, -x_s * 18.0))

	data["canopy"] = canopy_root
	return data

## 6. Attack Helicopter (Cobra / Apache Gunship)
static func build_attack_heli() -> Dictionary:
	var root := Node3D.new()
	var mat_olive := make_mat(Color(0.25, 0.31, 0.18), 0.68, 0.22)
	var mat_glass := make_mat(Color(0.18, 0.28, 0.32), 0.25, 0.4)
	var mat_rotor := make_mat(Color(0.12, 0.13, 0.12), 0.6, 0.4)
	var mat_pod := make_mat(Color(0.20, 0.22, 0.18), 0.7, 0.3)

	# Narrow fuselage + nose + tail boom
	add_box(root, Vector3(1.6, 1.6, 6.2), Vector3(0.0, 0.0, 0.0), mat_olive)
	add_box(root, Vector3(1.3, 1.1, 2.4), Vector3(0.0, 0.35, 1.2), mat_glass, Vector3(16.0, 0.0, 0.0))
	add_box(root, Vector3(0.55, 0.65, 5.2), Vector3(0.0, 0.2, -5.2), mat_olive)
	add_box(root, Vector3(0.25, 1.8, 1.1), Vector3(0.0, 0.9, -7.4), mat_olive, Vector3(-18.0, 0.0, 0.0))
	# Stub wings + Hydra rocket pods
	add_box(root, Vector3(5.2, 0.25, 1.2), Vector3(0.0, -0.1, 0.4), mat_olive)
	add_cyl(root, 0.38, 0.38, 1.8, Vector3(-2.1, -0.45, 0.5), mat_pod, Vector3(90, 0, 0))
	add_cyl(root, 0.38, 0.38, 1.8, Vector3(2.1, -0.45, 0.5), mat_pod, Vector3(90, 0, 0))
	# Main spinning rotor
	var rotor := Node3D.new()
	rotor.position = Vector3(0.0, 1.25, 0.2)
	root.add_child(rotor)
	add_box(rotor, Vector3(9.6, 0.08, 0.42), Vector3.ZERO, mat_rotor)
	add_box(rotor, Vector3(0.42, 0.08, 9.6), Vector3.ZERO, mat_rotor)

	return {"root": root, "rotor": rotor}

## 7. Transport Helicopter (Twin-Rotor Chinook Paratrooper Carrier)
static func build_transport_heli() -> Dictionary:
	var root := Node3D.new()
	var mat_olive := make_mat(Color(0.29, 0.35, 0.21), 0.75, 0.15)
	var mat_glass := make_mat(Color(0.20, 0.30, 0.35), 0.3, 0.3)
	var mat_rotor := make_mat(Color(0.14, 0.14, 0.14), 0.6, 0.3)

	# Heavy fuselage & twin rotor pylons
	add_box(root, Vector3(2.8, 2.4, 9.8), Vector3(0.0, 0.0, 0.0), mat_olive)
	add_box(root, Vector3(2.5, 1.4, 2.0), Vector3(0.0, 0.2, 5.2), mat_glass, Vector3(20.0, 0.0, 0.0))
	add_box(root, Vector3(1.6, 1.4, 1.8), Vector3(0.0, 1.6, 3.6), mat_olive)
	add_box(root, Vector3(1.6, 1.8, 2.0), Vector3(0.0, 1.8, -3.8), mat_olive)

	var rotor_front := Node3D.new()
	rotor_front.position = Vector3(0.0, 2.45, 3.6)
	root.add_child(rotor_front)
	add_box(rotor_front, Vector3(10.5, 0.09, 0.48), Vector3.ZERO, mat_rotor)
	add_box(rotor_front, Vector3(0.48, 0.09, 10.5), Vector3.ZERO, mat_rotor)

	var rotor_rear := Node3D.new()
	rotor_rear.position = Vector3(0.0, 2.85, -3.8)
	root.add_child(rotor_rear)
	add_box(rotor_rear, Vector3(10.5, 0.09, 0.48), Vector3.ZERO, mat_rotor)
	add_box(rotor_rear, Vector3(0.48, 0.09, 10.5), Vector3.ZERO, mat_rotor)

	return {"root": root, "rotor": rotor_front, "rotor2": rotor_rear}

## 8. Fighter Jet (High-Speed Swept-Wing Strike Fighter)
static func build_fighter_jet() -> Dictionary:
	var root := Node3D.new()
	var mat_body := make_mat(Color(0.36, 0.40, 0.38), 0.55, 0.35)
	var mat_camo := make_mat(Color(0.28, 0.33, 0.24), 0.65, 0.25)
	var mat_canopy := make_mat(Color(0.85, 0.68, 0.22), 0.2, 0.6)
	var mat_burner := make_mat(Color(1.0, 0.55, 0.12), 0.1, 0.0, true)

	# Fuselage + nose cone
	add_box(root, Vector3(1.8, 1.1, 8.6), Vector3(0.0, 0.0, 0.0), mat_body)
	add_cyl(root, 0.08, 0.75, 3.6, Vector3(0.0, 0.0, 6.0), mat_camo, Vector3(-90, 0, 0))
	add_box(root, Vector3(1.1, 0.75, 2.8), Vector3(0.0, 0.65, 2.2), mat_canopy, Vector3(8, 0, 0))
	# Swept delta wings
	add_box(root, Vector3(10.4, 0.18, 3.4), Vector3(0.0, 0.0, -0.6), mat_camo)
	# Twin angled tail fins
	add_box(root, Vector3(0.18, 2.1, 2.2), Vector3(-1.0, 1.0, -3.4), mat_body, Vector3(-16, 0, 12))
	add_box(root, Vector3(0.18, 2.1, 2.2), Vector3(1.0, 1.0, -3.4), mat_body, Vector3(-16, 0, -12))
	# Glowing twin afterburners
	add_cyl(root, 0.42, 0.32, 1.2, Vector3(-0.48, 0.0, -4.7), mat_burner, Vector3(90, 0, 0))
	add_cyl(root, 0.42, 0.32, 1.2, Vector3(0.48, 0.0, -4.7), mat_burner, Vector3(90, 0, 0))

	return {"root": root}

## 9. Friendly C-130 Hercules Supply Plane
static func build_supply_plane() -> Dictionary:
	var root := Node3D.new()
	var mat_olive := make_mat(Color(0.32, 0.38, 0.28), 0.75, 0.15)
	var mat_stripe := make_mat(Color(0.92, 0.88, 0.78), 0.8, 0.0)
	var mat_nav := make_mat(Color(0.2, 1.0, 0.45), 0.1, 0.0, true)

	# Fat cargo fuselage + high wings + tall tail
	add_cyl(root, 1.7, 1.7, 13.5, Vector3(0.0, 0.0, 0.0), mat_olive, Vector3(90, 0, 0))
	add_box(root, Vector3(19.5, 0.35, 2.8), Vector3(0.0, 1.2, 0.8), mat_olive)
	# Invasion stripes on wings
	add_box(root, Vector3(3.2, 0.38, 2.85), Vector3(-5.5, 1.2, 0.8), mat_stripe)
	add_box(root, Vector3(3.2, 0.38, 2.85), Vector3(5.5, 1.2, 0.8), mat_stripe)
	add_box(root, Vector3(0.35, 3.8, 2.8), Vector3(0.0, 2.2, -5.6), mat_olive, Vector3(-15, 0, 0))
	# Green friendly wingtip beacons
	add_sphere(root, 0.45, 0.9, Vector3(-9.8, 1.2, 0.8), mat_nav)
	add_sphere(root, 0.45, 0.9, Vector3(9.8, 1.2, 0.8), mat_nav)

	return {"root": root}

## 10. Shootable Parachute Supply Crate (Marked with Bright Yellow 'X')
static func build_supply_crate(is_golden: bool = false) -> Dictionary:
	var root := Node3D.new()
	var crate_color: Color = Color(0.34, 0.40, 0.22) if not is_golden else Color(0.95, 0.76, 0.15)
	var x_color: Color = Color(1.0, 0.88, 0.12) if not is_golden else Color(0.2, 1.0, 0.95)
	var chute_color: Color = Color(0.92, 0.48, 0.14) if not is_golden else Color(1.0, 0.90, 0.25)

	var mat_crate := make_mat(crate_color, 0.7, 0.1)
	var mat_x := make_mat(x_color, 0.2, 0.0, true)
	var mat_chute := make_mat(chute_color, 0.75, 0.0)
	var mat_cord := make_mat(Color(0.75, 0.75, 0.70), 0.9, 0.0)

	# Supply crate box (2.4m cube for satisfying mid-air shooting)
	add_box(root, Vector3(2.4, 2.4, 2.4), Vector3.ZERO, mat_crate)
	# Yellow 'X' markings on front/back/left/right faces
	for rot_y in [0.0, 90.0]:
		var face_holder := Node3D.new()
		face_holder.rotation_degrees = Vector3(0.0, rot_y, 0.0)
		root.add_child(face_holder)
		add_box(face_holder, Vector3(2.1, 0.32, 2.52), Vector3.ZERO, mat_x, Vector3(0, 0, 45))
		add_box(face_holder, Vector3(2.1, 0.32, 2.52), Vector3.ZERO, mat_x, Vector3(0, 0, -45))

	# Parachute canopy above crate
	var canopy := Node3D.new()
	canopy.position = Vector3(0.0, 4.8, 0.0)
	root.add_child(canopy)
	add_sphere(canopy, 3.2, 2.6, Vector3.ZERO, mat_chute, true)
	for x_s in [-1.5, 1.5]:
		for z_s in [-1.5, 1.5]:
			add_cyl(canopy, 0.04, 0.04, 3.8, Vector3(x_s * 0.5, -1.8, z_s * 0.5), mat_cord)

	return {"root": root, "canopy": canopy}

