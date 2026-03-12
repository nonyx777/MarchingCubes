extends Node

var isolevel: float = 0.2
var torus_parameter: Vector2 = Vector2(2, 0.5)
var noise := FastNoiseLite.new()

var sphere_radius: float = 2
var torus_radius: float = 2
var noise_randomness: float = 5

var polygonize: Polygonise

# grid
var grid_size: Vector3i = Vector3i(15, 15, 15)
var total_point_count: int
var spacing: float = 0.5
# grid cell related
var grid_pos: PackedVector4Array
var grid_norm: PackedVector4Array
var grid_val: PackedFloat32Array
# triangle related
var tri_pos: PackedVector4Array
var tri_norm: PackedVector4Array
var tri_mask: PackedInt32Array
var tri_prefixsum: PackedInt32Array
var tri_compact: PackedVector4Array
# border element indices
var border_indices: PackedInt32Array

# result triangle array
var final_tri_vert: PackedVector3Array
var final_tri_norm: PackedVector3Array
var final_tri_ind: PackedInt32Array

# surface
var surface_array = Array()

# Compute shader related variables
var rd: RenderingDevice
var compute_list: int
var populate_shaderfile: Resource
var populate_shaderfile_spirv: RDShaderSPIRV
var populate_shader
var mask_shaderfile: Resource
var mask_shaderfile_spirv: RDShaderSPIRV
var mask_shader
var prefixsum_shaderfile: Resource
var prefixsum_shaderfile_spirv: RDShaderSPIRV
var prefixsum_shader
var compact_shaderfile: Resource
var compact_shaderfile_spirv: RDShaderSPIRV
var compact_shader
var setupcells_shaderfile: Resource
var setupcells_shaderfile_spirv: RDShaderSPIRV
var setupcells_shader

# Buffer RIDs
var vertices_buffer: RID
var normals_buffer: RID
var values_buffer: RID
var border_indices_buffer: RID
var tri_pos_buffer: RID
var tri_norm_buffer: RID
var tri_mask_buffer: RID
var tri_prefixsum_buffer: RID
var tri_compact_vertex_buffer: RID
var tri_compact_normal_buffer: RID

# Uniform set RIDs
var uniform_setupcells_set: RID
var uniform_populate_set: RID
var uniform_mask_set: RID
var uniform_prefixsum_set: RID
var uniform_compact_set: RID

# Pipeline RIDs
var setupcells_pipeline: RID
var populate_pipeline: RID
var mask_pipeline: RID
var prefixsum_pipeline: RID
var compact_pipeline: RID


@onready var meshInstance: MeshInstance3D = $MeshInstance3D

func sphere_sdf(p: Vector3, r: float):
	return p.length() - r

func torus_sdf(p: Vector3, t: Vector2):
	var q = Vector2(Vector2(p.x, p.z).length() - t.x, p.y)
	return q.length() - t.y

func noise_sdf(p: Vector4, r: float):
	var amplitude = 10
	
	var height = noise.get_noise_3d(
		p.x * r,
		p.y * r,
		p.z * r
	) * amplitude
	return height

func sphere_density(p: Vector3, r: float) -> float:
	var center = Vector3(5, 5, 5)
	return sphere_sdf(p - center, r)

func torus_density(p: Vector3, t: Vector2) -> float:
	var center = Vector3(5, 5, 5)
	return torus_sdf(p - center, t)

func noise_density(p: Vector4, r: float) -> float:
	return noise_sdf(p, r)

func generate_points(sx: int, sy: int, sz: int, spacing_: float):
	grid_pos.clear()
	for z in range(sz):
		for y in range(sy):
			for x in range(sx):
				grid_pos.append(Vector4(x * spacing_, y * spacing_, z * spacing_, -1))

func get_point_index(x: int, y: int, z: int, sx: int, sy: int):
	return z * (sy) * (sx) + y * (sx) + x

func setup_cells(i: int, sx: int, sy: int, sz: int) -> void:
	var i0 = i
	grid_val[i0] = noise_density(grid_pos[i0], noise_randomness)
	var pos: Vector4 = grid_pos[i0]
	var n_x = (noise_density(Vector4(pos.x + 1, pos.y, pos.z, 0.0), noise_randomness) - noise_density(Vector4(pos.x-1, pos.y, pos.z, 0.0), noise_randomness)) / 2 * sx
	var n_y = (noise_density(Vector4(pos.x, pos.y + 1, pos.z, 0.0), noise_randomness) - noise_density(Vector4(pos.x, pos.y-1, pos.z, 0.0), noise_randomness)) / 2 * sy
	var n_z = (noise_density(Vector4(pos.x, pos.y, pos.z + 1, 0.0), noise_randomness) - noise_density(Vector4(pos.x, pos.y, pos.z-1, 0.0), noise_randomness)) / 2 * sz
	var n_w = -1
	grid_norm[i0] = Vector4(n_x, n_y, n_z, n_w).normalized()

func construct_grid() -> void:
	total_point_count = grid_size.x * grid_size.y * grid_size.z
	generate_points(grid_size.x, grid_size.y, grid_size.z, spacing)
	get_border()
	grid_val.clear()
	grid_norm.clear()
	grid_val.resize(grid_pos.size())
	grid_norm.resize(grid_pos.size())

func get_border() -> void:
	var size: int = grid_size.z
	var start_idx: int = (size * size) - size
	var end_idx: int = size * size * size - size
	var step: int = size * size
	for i in range(start_idx, end_idx, step):
		for j in range(size):
			border_indices.append(i + j)

func setup_compute() -> void:
	var tri_size: int = grid_pos.size() * 15
	tri_pos.resize(tri_size)
	tri_norm.resize(tri_size)
	tri_mask.resize(tri_size)
	tri_prefixsum.resize(tri_size)
	tri_compact.resize(tri_size)
	tri_pos.fill(Vector4(-1, -1, -1, -1))
	tri_norm.fill(Vector4(-1, -1, -1, -1))
	tri_mask.fill(0)
	tri_prefixsum.fill(0)
	tri_compact.fill(Vector4(-1, -1, -1, -1))
	
	rd = RenderingServer.create_local_rendering_device()
	
	# Shaders
	populate_shaderfile = load("res://Scripts/populate_triangles.glsl")
	populate_shaderfile_spirv = populate_shaderfile.get_spirv()
	populate_shader = rd.shader_create_from_spirv(populate_shaderfile_spirv)
	
	mask_shaderfile = load("res://Scripts/mask_triangles.glsl")
	mask_shaderfile_spirv = mask_shaderfile.get_spirv()
	mask_shader = rd.shader_create_from_spirv(mask_shaderfile_spirv)
	
	prefixsum_shaderfile = load("res://Scripts/prefixsum_triangles.glsl")
	prefixsum_shaderfile_spirv = prefixsum_shaderfile.get_spirv()
	prefixsum_shader = rd.shader_create_from_spirv(prefixsum_shaderfile_spirv)
	
	compact_shaderfile = load("res://Scripts/compact_triangles.glsl")
	compact_shaderfile_spirv = compact_shaderfile.get_spirv()
	compact_shader = rd.shader_create_from_spirv(compact_shaderfile_spirv)
	
	setupcells_shaderfile = load("res://Scripts/setup_cells.glsl")
	setupcells_shaderfile_spirv = setupcells_shaderfile.get_spirv()
	setupcells_shader = rd.shader_create_from_spirv(setupcells_shaderfile_spirv)
	
	#initializing storage buffers
	# VerticesBuffer
	var grid_pos_bytes: PackedByteArray = grid_pos.to_byte_array()
	vertices_buffer = rd.storage_buffer_create(grid_pos_bytes.size(), grid_pos_bytes)
	var uniform_vertices := RDUniform.new()
	uniform_vertices.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_vertices.binding = 0
	uniform_vertices.add_id(vertices_buffer)
	
	# NormalsBuffer
	var grid_norm_bytes: PackedByteArray = grid_norm.to_byte_array()
	normals_buffer = rd.storage_buffer_create(grid_norm_bytes.size(), grid_norm_bytes)
	var uniform_normals := RDUniform.new()
	uniform_normals.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_normals.binding = 1
	uniform_normals.add_id(normals_buffer)
	
	# ValuesBuffer
	var grid_val_bytes: PackedByteArray = grid_val.to_byte_array()
	values_buffer = rd.storage_buffer_create(grid_val_bytes.size(), grid_val_bytes)
	var uniform_values := RDUniform.new()
	uniform_values.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_values.binding = 2
	uniform_values.add_id(values_buffer)
	
	# BorderElementsBuffer
	var border_indices_bytes: PackedByteArray = border_indices.to_byte_array()
	border_indices_buffer = rd.storage_buffer_create(border_indices_bytes.size(), border_indices_bytes)
	var uniform_border_indices := RDUniform.new()
	uniform_border_indices.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_border_indices.binding = 3
	uniform_border_indices.add_id(border_indices_buffer)
	
	# TriangleVertexBuffer
	var tri_pos_bytes: PackedByteArray = tri_pos.to_byte_array()
	tri_pos_buffer = rd.storage_buffer_create(tri_pos_bytes.size(), tri_pos_bytes)
	var uniform_tri_pos := RDUniform.new()
	uniform_tri_pos.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_pos.binding = 4
	uniform_tri_pos.add_id(tri_pos_buffer)
	
	# TriangleNormalBuffer
	var tri_norm_bytes: PackedByteArray = tri_norm.to_byte_array()
	tri_norm_buffer = rd.storage_buffer_create(tri_norm_bytes.size(), tri_norm_bytes)
	var uniform_tri_norm := RDUniform.new()
	uniform_tri_norm.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_norm.binding = 5
	uniform_tri_norm.add_id(tri_norm_buffer)
	
	# TriangleMaskBuffer
	var tri_mask_bytes: PackedByteArray = tri_mask.to_byte_array()
	tri_mask_buffer = rd.storage_buffer_create(tri_mask_bytes.size(), tri_mask_bytes)
	var uniform_tri_mask := RDUniform.new()
	uniform_tri_mask.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_mask.binding = 6
	uniform_tri_mask.add_id(tri_mask_buffer)
	
	# TrianglePrefixSumBuffer
	var tri_prefixsum_bytes: PackedByteArray = tri_prefixsum.to_byte_array()
	tri_prefixsum_buffer = rd.storage_buffer_create(tri_prefixsum_bytes.size(), tri_prefixsum_bytes)
	var uniform_tri_prefixsum := RDUniform.new()
	uniform_tri_prefixsum.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_prefixsum.binding = 7
	uniform_tri_prefixsum.add_id(tri_prefixsum_buffer)
	
	# TriangleCompactVertexBuffer
	var tri_compact_vertex_bytes: PackedByteArray = tri_compact.to_byte_array()
	tri_compact_vertex_buffer = rd.storage_buffer_create(tri_compact_vertex_bytes.size(), tri_compact_vertex_bytes)
	var uniform_tri_compact_vertex := RDUniform.new()
	uniform_tri_compact_vertex.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_compact_vertex.binding = 8
	uniform_tri_compact_vertex.add_id(tri_compact_vertex_buffer)
	
	var tri_compact_normal_bytes: PackedByteArray = tri_compact.to_byte_array()
	tri_compact_normal_buffer = rd.storage_buffer_create(tri_compact_normal_bytes.size(), tri_compact_normal_bytes)
	var uniform_tri_compact_normal := RDUniform.new()
	uniform_tri_compact_normal.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_compact_normal.binding = 9
	uniform_tri_compact_normal.add_id(tri_compact_normal_buffer)
	
	compute_list = rd.compute_list_begin()
	
	# Setup Shader.....................................................................................
	uniform_setupcells_set = rd.uniform_set_create([uniform_vertices, uniform_normals, uniform_values], setupcells_shader, 0)
	setupcells_pipeline = rd.compute_pipeline_create(setupcells_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, setupcells_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_setupcells_set, 0)
	
	var setupcells_params: PackedByteArray = PackedInt32Array([total_point_count, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, setupcells_params, setupcells_params.size())
	rd.compute_list_dispatch(compute_list, ceil(total_point_count / 64.0), 1, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Populate Shader....................................................................................
	uniform_populate_set = rd.uniform_set_create([uniform_vertices, uniform_normals, uniform_values, uniform_border_indices, uniform_tri_pos, uniform_tri_norm], populate_shader, 0)
	populate_pipeline = rd.compute_pipeline_create(populate_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, populate_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_populate_set, 0)
	
	var populate_params: PackedByteArray = PackedInt32Array([grid_size.x, border_indices.size(), int(isolevel), 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, populate_params, populate_params.size())
	rd.compute_list_dispatch(compute_list, ceil(total_point_count / 64.0), 1, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Mask Shader......................................................................................
	uniform_mask_set = rd.uniform_set_create([uniform_tri_pos, uniform_tri_mask], mask_shader, 0)
	mask_pipeline = rd.compute_pipeline_create(mask_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, mask_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_mask_set, 0)
	
	var mask_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, mask_params, mask_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 64.0), 1, 1)
	
	# Prefixsum Shader...................................................................................
	uniform_prefixsum_set = rd.uniform_set_create([uniform_tri_pos, uniform_tri_mask, uniform_tri_prefixsum], prefixsum_shader, 0)
	prefixsum_pipeline = rd.compute_pipeline_create(prefixsum_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, prefixsum_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_prefixsum_set, 0)
	
	var prefixsum_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, prefixsum_params, prefixsum_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 64.0), 1, 1)
	
	# Compact Shader.....................................................................................
	uniform_compact_set = rd.uniform_set_create([uniform_tri_pos, uniform_tri_norm, uniform_tri_mask, uniform_tri_prefixsum, uniform_tri_compact_vertex, uniform_tri_compact_normal], compact_shader, 0)
	compact_pipeline = rd.compute_pipeline_create(compact_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, compact_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_compact_set, 0)
	
	var compact_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, compact_params, compact_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 64.0), 1, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	var compact_vertex_display_bytes := rd.buffer_get_data(tri_compact_vertex_buffer)
	var compact_vertex_display := compact_vertex_display_bytes.to_float32_array()
	#print("Compact: ", compact_vertex_display)
	
	var compact_normal_display_bytes := rd.buffer_get_data(tri_compact_normal_buffer)
	var compact_normal_display := compact_normal_display_bytes.to_float32_array()
	#print("Compact: ", compact_normal_display)
	
	for i in range(0, compact_vertex_display.size(), 4):
		if compact_vertex_display[i] == -1:
			break
		final_tri_vert.append(Vector3(compact_vertex_display[i], compact_vertex_display[i+1], compact_vertex_display[i+2]))
		final_tri_norm.append(Vector3(compact_normal_display[i], compact_normal_display[i+1], compact_normal_display[i+2]))
	
	for i in range(final_tri_vert.size()):
		final_tri_ind.append(i)

func main_march() -> void:
	# initialize surface array
	meshInstance.mesh.clear_surfaces()
	surface_array.resize(Mesh.ARRAY_MAX)
	surface_array[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	surface_array[Mesh.ARRAY_INDEX] = PackedInt32Array()
	surface_array[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	
	#var n = polygonize.Polygonize(grid_pos, grid_norm, grid_val, isolevel, grid_size.x, grid_size.y, tri_pos, tri_norm, border_indices)
	
	if final_tri_vert.size() != 0:
		surface_array[Mesh.ARRAY_VERTEX] = final_tri_vert
		surface_array[Mesh.ARRAY_INDEX] = final_tri_ind
		surface_array[Mesh.ARRAY_NORMAL] = final_tri_norm
		meshInstance.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
	print("Points: ", grid_pos.size())
	#print("Number of Triangles: ", n)
	print("Number of Vertices: ", final_tri_vert.size())
	print("Number of Indices: ", final_tri_ind.size())
	print("Number of Normals: ", final_tri_norm.size())
	
	final_tri_vert.clear()
	final_tri_ind.clear()
	final_tri_norm.clear()

func _ready() -> void:
	#polygonize = Polygonise.new()
	construct_grid()
	setup_compute()
	main_march()

#func _on_h_slider_value_changed(value: float) -> void:
	#sphere_radius = value
	#torus_radius = value
	#noise_randomness = value * 10
	#main_march()
	
func _exit_tree() -> void:
	free_compute_resources()
	
func free_compute_resources() -> void:
	if rd == null:
		return
	
	# --- Uniform sets ---
	var uniform_sets = [
		uniform_setupcells_set,
		uniform_populate_set,
		uniform_mask_set,
		uniform_prefixsum_set,
		uniform_compact_set
	]
	
	for u in uniform_sets:
		if u.is_valid():
			rd.free_rid(u)
	
	# --- Pipelines ---
	var pipelines = [
		setupcells_pipeline,
		populate_pipeline,
		mask_pipeline,
		prefixsum_pipeline,
		compact_pipeline
	]
	
	for p in pipelines:
		if p.is_valid():
			rd.free_rid(p)
	
	# --- Buffers ---
	var buffers = [
		vertices_buffer,
		normals_buffer,
		values_buffer,
		border_indices_buffer,
		tri_pos_buffer,
		tri_norm_buffer,
		tri_mask_buffer,
		tri_prefixsum_buffer,
		tri_compact_vertex_buffer,
		tri_compact_normal_buffer
	]
	
	for b in buffers:
		if b.is_valid():
			rd.free_rid(b)
	
	# --- Shaders ---
	var shaders = [
		populate_shader,
		mask_shader,
		prefixsum_shader,
		compact_shader,
		setupcells_shader
	]
	
	for s in shaders:
		if s.is_valid():
			rd.free_rid(s)
	
	# --- Destroy the rendering device ---
	rd.free()
	rd = null
