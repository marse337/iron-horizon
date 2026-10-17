class_name ExplosionManager
extends Node3D

## Spawns multi-layered 3D arcade visual effects:
## - Armored fireball explosions + shockwave rings + flying olive-drab debris
## - Water plumes when shells hit the ocean
## - Sand plumes when rounds strike the beach
## - Metallic sparks on 30mm ricochets off heavy armor
## - Active parachute illumination flares for Dusk/Night operations

var _effects: Array[Dictionary] = []
var _debris_chunks: Array[Dictionary] = []
var _flares: Array[Dictionary] = []

var _sphere_mesh: SphereMesh
var _ring_mesh: TorusMesh
var _box_mesh: BoxMesh
var _cyl_mesh: CylinderMesh

func _ready() -> void:
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radial_segments = 12
	_sphere_mesh.rings = 6

	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.72
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 16
	_ring_mesh.ring_segments = 8

	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.45, 0.35, 0.55)

	_cyl_mesh = CylinderMesh.new()
	_cyl_mesh.top_radius = 0.15
	_cyl_mesh.bottom_radius = 0.65
	_cyl_mesh.height = 1.0

func clear_all() -> void:
	for fx in _effects:
		if is_instance_valid(fx["node"]):
			fx["node"].queue_free()
	_effects.clear()
	for d in _debris_chunks:
		if is_instance_valid(d["node"]):
			d["node"].queue_free()
	_debris_chunks.clear()
	for fl in _flares:
		if is_instance_valid(fl["node"]):
			fl["node"].queue_free()
	_flares.clear()

func spawn_explosion(pos: Vector3, scale_factor: float = 1.0, is_heavy: bool = false) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	# Core fireball
	var core := MeshInstance3D.new()
	core.mesh = _sphere_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.albedo_color = Color(1.0, 0.78, 0.22, 0.95)
	core.material_override = core_mat
	root.add_child(core)

	# Outer smoke/flame shell
	var outer := MeshInstance3D.new()
	outer.mesh = _sphere_mesh
	var outer_mat := StandardMaterial3D.new()
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.albedo_color = Color(0.95, 0.35, 0.08, 0.75)
	outer.material_override = outer_mat
	root.add_child(outer)

	# Expanding shockwave ring
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1.0, 0.85, 0.45, 0.8)
	ring.material_override = ring_mat
	root.add_child(ring)

	# Dynamic flash OmniLight3D for night/dusk drama
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.65, 0.2)
	flash.light_energy = 4.5 * scale_factor
	flash.omni_range = 28.0 * scale_factor
	root.add_child(flash)

	_effects.append({
		"node": root,
		"core": core,
		"outer": outer,
		"ring": ring,
		"flash": flash,
		"core_mat": core_mat,
		"outer_mat": outer_mat,
		"ring_mat": ring_mat,
		"age": 0.0,
		"duration": 0.55 if not is_heavy else 0.85,
		"scale": scale_factor
	})

	var debris_count: int = 8 if is_heavy else 3
	for i in range(debris_count):
		_spawn_debris_chunk(pos, scale_factor)

func _spawn_debris_chunk(origin: Vector3, scale_factor: float) -> void:
	var chunk := MeshInstance3D.new()
	chunk.mesh = _box_mesh
	chunk.scale = Vector3.ONE * randf_range(0.5, 1.35) * clampf(scale_factor * 0.5, 0.5, 1.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.27, 0.18) if randf() < 0.65 else Color(0.18, 0.18, 0.18)
	chunk.material_override = mat
	chunk.position = origin + Vector3(randf_range(-0.8, 0.8), randf_range(0.2, 1.2), randf_range(-0.8, 0.8))
	add_child(chunk)

	var vel := Vector3(
		randf_range(-16.0, 16.0),
		randf_range(10.0, 24.0),
		randf_range(-16.0, 16.0)
	) * clampf(scale_factor * 0.65, 0.6, 1.5)

	_debris_chunks.append({
		"node": chunk,
		"vel": vel,
		"rot_vel": Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)),
		"age": 0.0,
		"max_age": randf_range(0.7, 1.35)
	})

func spawn_surface_impact(pos: Vector3, is_water: bool, scale_factor: float = 1.0) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var plume := MeshInstance3D.new()
	plume.mesh = _cyl_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_water:
		mat.albedo_color = Color(0.82, 0.94, 1.0, 0.85)
	else:
		mat.albedo_color = Color(0.76, 0.64, 0.42, 0.85)
	plume.material_override = mat
	plume.position = Vector3(0.0, 0.5 * scale_factor, 0.0)
	root.add_child(plume)

	_effects.append({
		"node": root,
		"core": plume,
		"outer": null,
		"ring": null,
		"flash": null,
		"core_mat": mat,
		"outer_mat": null,
		"ring_mat": null,
		"age": 0.0,
		"duration": 0.42,
		"scale": scale_factor,
		"is_plume": true
	})

func spawn_ricochet_spark(pos: Vector3) -> void:
	var spark := MeshInstance3D.new()
	spark.mesh = _sphere_mesh
	spark.scale = Vector3.ONE * 0.35
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.92, 0.45, 1.0)
	spark.material_override = mat
	spark.position = pos
	add_child(spark)

	_debris_chunks.append({
		"node": spark,
		"vel": Vector3(randf_range(-9.0, 9.0), randf_range(6.0, 14.0), randf_range(4.0, 12.0)),
		"rot_vel": Vector3.ZERO,
		"age": 0.0,
		"max_age": 0.25
	})

func spawn_illumination_flare(pos: Vector3) -> void:
	var flare_root := Node3D.new()
	flare_root.position = pos
	add_child(flare_root)

	# Glowing flare star
	var orb := MeshInstance3D.new()
	orb.mesh = _sphere_mesh
	orb.scale = Vector3.ONE * 1.3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.68)
	orb.material_override = mat
	flare_root.add_child(orb)

	# Small parachute above flare
	var canopy := MeshInstance3D.new()
	var c_mesh := SphereMesh.new()
	c_mesh.radius = 1.6
	c_mesh.height = 1.4
	c_mesh.is_hemisphere = true
	canopy.mesh = c_mesh
	canopy.position = Vector3(0.0, 2.6, 0.0)
	var c_mat := StandardMaterial3D.new()
	c_mat.albedo_color = Color(0.92, 0.88, 0.78)
	canopy.material_override = c_mat
	flare_root.add_child(canopy)

	# High-range battlefield illumination light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.92, 0.68)
	light.light_energy = 11.0
	light.omni_range = 240.0
	light.omni_attenuation = 0.65
	flare_root.add_child(light)

	_flares.append({
		"node": flare_root,
		"light": light,
		"age": 0.0,
		"duration": 18.0
	})

func get_active_flare_count() -> int:
	return _flares.size()

func _process(delta: float) -> void:
	# Update explosions & plumes
	for i in range(_effects.size() - 1, -1, -1):
		var fx: Dictionary = _effects[i]
		fx["age"] += delta
		var t: float = fx["age"] / fx["duration"]
		if t >= 1.0 or not is_instance_valid(fx["node"]):
			if is_instance_valid(fx["node"]):
				fx["node"].queue_free()
			_effects.remove_at(i)
			continue

		var sc: float = fx["scale"]
		if fx.get("is_plume", false):
			var core_plume: MeshInstance3D = fx["core"]
			core_plume.scale = Vector3(sc * lerpf(0.6, 1.8, t), sc * lerpf(0.5, 4.2, sin(t * PI)), sc * lerpf(0.6, 1.8, t))
			var pmat: StandardMaterial3D = fx["core_mat"]
			pmat.albedo_color.a = (1.0 - t) * 0.85
		else:
			var core: MeshInstance3D = fx["core"]
			var outer: MeshInstance3D = fx["outer"]
			var ring: MeshInstance3D = fx["ring"]
			var flash: OmniLight3D = fx["flash"]
			core.scale = Vector3.ONE * sc * lerpf(0.6, 2.6, pow(t, 0.45))
			outer.scale = Vector3.ONE * sc * lerpf(0.9, 4.2, pow(t, 0.55))
			ring.scale = Vector3(sc * lerpf(1.0, 6.5, t), sc * 0.35, sc * lerpf(1.0, 6.5, t))

			var cmat: StandardMaterial3D = fx["core_mat"]
			var omat: StandardMaterial3D = fx["outer_mat"]
			var rmat: StandardMaterial3D = fx["ring_mat"]
			cmat.albedo_color.a = clampf(1.0 - t * 1.25, 0.0, 1.0)
			omat.albedo_color = Color(lerpf(0.95, 0.22, t), lerpf(0.38, 0.20, t), lerpf(0.08, 0.18, t), (1.0 - t) * 0.8)
			rmat.albedo_color.a = (1.0 - t) * 0.75
			if is_instance_valid(flash):
				flash.light_energy = (1.0 - t) * 4.5 * sc

	# Update debris chunks
	for i in range(_debris_chunks.size() - 1, -1, -1):
		var d: Dictionary = _debris_chunks[i]
		d["age"] += delta
		if d["age"] >= d["max_age"] or not is_instance_valid(d["node"]):
			if is_instance_valid(d["node"]):
				d["node"].queue_free()
			_debris_chunks.remove_at(i)
			continue
		var node: Node3D = d["node"]
		d["vel"] += Vector3(0.0, -28.0 * delta, 0.0)
		node.position += d["vel"] * delta
		node.rotation += d["rot_vel"] * delta
		if node.position.y < 0.0:
			node.position.y = 0.0
			d["vel"].y = abs(d["vel"].y) * 0.35

	# Update descending night illumination flares
	for i in range(_flares.size() - 1, -1, -1):
		var fl: Dictionary = _flares[i]
		fl["age"] += delta
		var t: float = fl["age"] / fl["duration"]
		if t >= 1.0 or not is_instance_valid(fl["node"]):
			if is_instance_valid(fl["node"]):
				fl["node"].queue_free()
			_flares.remove_at(i)
			continue
		var fnode: Node3D = fl["node"]
		fnode.position.y = maxf(16.0, fnode.position.y - 2.2 * delta)
		fnode.position.x += sin(fl["age"] * 1.8) * 1.5 * delta
		var flight: OmniLight3D = fl["light"]
		var flicker: float = 0.92 + 0.08 * sin(fl["age"] * 27.0)
		var fade: float = clampf((1.0 - t) * 4.0, 0.0, 1.0)
		flight.light_energy = 11.0 * flicker * fade

