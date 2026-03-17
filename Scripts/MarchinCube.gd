extends Node

var isolevel: float = 1
var torus_parameter: Vector2 = Vector2(2, 0.5)
var noise := FastNoiseLite.new()

var sphere_radius: float = 2
var torus_radius: float = 2
var noise_randomness: float = 5

var polygonize: Polygonise

# grid
var grid_size: Vector3i = Vector3i(20, 20, 20)
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
var tri_count: PackedInt32Array
# border element indices
var border_indices: PackedInt32Array

# result triangle array
var final_tri_vert: PackedVector3Array
var final_tri_norm: PackedVector3Array
var final_tri_ind: PackedInt32Array

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
var tri_count_buffer: RID

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

# Uniforms
var uniform_vertices: RDUniform
var uniform_normals: RDUniform
var uniform_values: RDUniform
var uniform_border_indices: RDUniform
var uniform_tri_pos: RDUniform
var uniform_tri_norm: RDUniform
var uniform_tri_mask: RDUniform
var uniform_tri_prefixsum: RDUniform
var uniform_tri_compact_vertex: RDUniform
var uniform_tri_compact_normal: RDUniform
var uniform_tri_count: RDUniform

# State
var frame: int
var time: float
var last_compute_dispatch_frame: int
var waiting_for_compute: bool
var num_waitframes_gpusync: int = 12
var last_meshthread_start_frame: int
var waiting_for_meshthread: bool
var num_waitframes_meshthread: int = 5
var task_id: int
var array_mesh: ArrayMesh
var mesh: MeshInstance3D

var counter_display_bytes: PackedByteArray
var compact_vertex_display_bytes: PackedByteArray
var compact_normal_display_bytes: PackedByteArray

var counter_display: int
var compact_vertex_display: PackedFloat32Array
var compact_normal_display: PackedFloat32Array

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
	
	tri_count = PackedInt32Array([0])
	
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
	uniform_vertices = RDUniform.new()
	uniform_vertices.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_vertices.binding = 0
	uniform_vertices.add_id(vertices_buffer)
	
	# NormalsBuffer
	var grid_norm_bytes: PackedByteArray = grid_norm.to_byte_array()
	normals_buffer = rd.storage_buffer_create(grid_norm_bytes.size(), grid_norm_bytes)
	uniform_normals = RDUniform.new()
	uniform_normals.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_normals.binding = 1
	uniform_normals.add_id(normals_buffer)
	
	# ValuesBuffer
	var grid_val_bytes: PackedByteArray = grid_val.to_byte_array()
	values_buffer = rd.storage_buffer_create(grid_val_bytes.size(), grid_val_bytes)
	uniform_values = RDUniform.new()
	uniform_values.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_values.binding = 2
	uniform_values.add_id(values_buffer)
	
	# BorderElementsBuffer
	var border_indices_bytes: PackedByteArray = border_indices.to_byte_array()
	border_indices_buffer = rd.storage_buffer_create(border_indices_bytes.size(), border_indices_bytes)
	uniform_border_indices = RDUniform.new()
	uniform_border_indices.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_border_indices.binding = 3
	uniform_border_indices.add_id(border_indices_buffer)
	
	# TriangleVertexBuffer
	var tri_pos_bytes: PackedByteArray = tri_pos.to_byte_array()
	tri_pos_buffer = rd.storage_buffer_create(tri_pos_bytes.size(), tri_pos_bytes)
	uniform_tri_pos = RDUniform.new()
	uniform_tri_pos.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_pos.binding = 4
	uniform_tri_pos.add_id(tri_pos_buffer)
	
	# TriangleNormalBuffer
	var tri_norm_bytes: PackedByteArray = tri_norm.to_byte_array()
	tri_norm_buffer = rd.storage_buffer_create(tri_norm_bytes.size(), tri_norm_bytes)
	uniform_tri_norm = RDUniform.new()
	uniform_tri_norm.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_norm.binding = 5
	uniform_tri_norm.add_id(tri_norm_buffer)
	
	# TriangleMaskBuffer
	var tri_mask_bytes: PackedByteArray = tri_mask.to_byte_array()
	tri_mask_buffer = rd.storage_buffer_create(tri_mask_bytes.size(), tri_mask_bytes)
	uniform_tri_mask = RDUniform.new()
	uniform_tri_mask.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_mask.binding = 6
	uniform_tri_mask.add_id(tri_mask_buffer)
	
	# TrianglePrefixSumBuffer
	var tri_prefixsum_bytes: PackedByteArray = tri_prefixsum.to_byte_array()
	tri_prefixsum_buffer = rd.storage_buffer_create(tri_prefixsum_bytes.size(), tri_prefixsum_bytes)
	uniform_tri_prefixsum = RDUniform.new()
	uniform_tri_prefixsum.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_prefixsum.binding = 7
	uniform_tri_prefixsum.add_id(tri_prefixsum_buffer)
	
	# TriangleCompactVertexBuffer
	var tri_compact_vertex_bytes: PackedByteArray = tri_compact.to_byte_array()
	tri_compact_vertex_buffer = rd.storage_buffer_create(tri_compact_vertex_bytes.size(), tri_compact_vertex_bytes)
	uniform_tri_compact_vertex = RDUniform.new()
	uniform_tri_compact_vertex.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_compact_vertex.binding = 8
	uniform_tri_compact_vertex.add_id(tri_compact_vertex_buffer)
	
	# TriangleCompactNormalBuffer
	var tri_compact_normal_bytes: PackedByteArray = tri_compact.to_byte_array()
	tri_compact_normal_buffer = rd.storage_buffer_create(tri_compact_normal_bytes.size(), tri_compact_normal_bytes)
	uniform_tri_compact_normal = RDUniform.new()
	uniform_tri_compact_normal.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_compact_normal.binding = 9
	uniform_tri_compact_normal.add_id(tri_compact_normal_buffer)
	
	# TriangleCountBuffer
	var tri_count_bytes: PackedByteArray = tri_count.to_byte_array()
	tri_count_buffer = rd.storage_buffer_create(tri_count_bytes.size(), tri_count_bytes)
	uniform_tri_count = RDUniform.new()
	uniform_tri_count.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_count.binding = 10
	uniform_tri_count.add_id(tri_count_buffer)

func compute_pipeline() -> void:
	var tri_size: int = grid_pos.size() * 15
	var count_reset := PackedInt32Array([0]).to_byte_array()
	rd.buffer_update(tri_count_buffer, 0, count_reset.size(), count_reset)
	
	var tri_fill = PackedVector4Array()
	tri_fill.resize(tri_pos.size())
	tri_fill.fill(Vector4(-1, -1, -1, -1))
	var tri_reset: PackedByteArray = tri_fill.to_byte_array()
	
	rd.buffer_update(tri_pos_buffer, 0, tri_reset.size(), tri_reset)
	rd.buffer_update(tri_norm_buffer, 0, tri_reset.size(), tri_reset)
	
	compute_list = rd.compute_list_begin()
	
	# Setup Shader.....................................................................................
	uniform_setupcells_set = rd.uniform_set_create([uniform_vertices, uniform_normals, uniform_values], setupcells_shader, 0)
	setupcells_pipeline = rd.compute_pipeline_create(setupcells_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, setupcells_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_setupcells_set, 0)
	
	var setupcells_params: PackedByteArray = PackedInt32Array([total_point_count, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, setupcells_params, setupcells_params.size())
	rd.compute_list_dispatch(compute_list, ceil(total_point_count / 512.0), 1, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Populate Shader....................................................................................
	uniform_populate_set = rd.uniform_set_create([uniform_vertices, uniform_normals, uniform_values, uniform_border_indices, uniform_tri_pos, uniform_tri_norm], populate_shader, 0)
	populate_pipeline = rd.compute_pipeline_create(populate_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, populate_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_populate_set, 0)
	
	var populate_params: PackedByteArray = PackedFloat32Array([float(grid_size.x), float(border_indices.size()), isolevel, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, populate_params, populate_params.size())
	rd.compute_list_dispatch(compute_list, ceil(total_point_count / 512.0), 1, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Mask Shader......................................................................................
	uniform_mask_set = rd.uniform_set_create([uniform_tri_pos, uniform_tri_mask], mask_shader, 0)
	mask_pipeline = rd.compute_pipeline_create(mask_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, mask_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_mask_set, 0)
	
	var mask_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, mask_params, mask_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 512.0), 1, 1)
	
	# Prefixsum Shader...................................................................................
	uniform_prefixsum_set = rd.uniform_set_create([uniform_tri_pos, uniform_tri_mask, uniform_tri_prefixsum], prefixsum_shader, 0)
	prefixsum_pipeline = rd.compute_pipeline_create(prefixsum_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, prefixsum_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_prefixsum_set, 0)
	
	var prefixsum_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, prefixsum_params, prefixsum_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 512.0), 1, 1)
	
	# Compact Shader.....................................................................................
	uniform_compact_set = rd.uniform_set_create([uniform_tri_pos, uniform_tri_norm, uniform_tri_mask, uniform_tri_prefixsum, uniform_tri_compact_vertex, uniform_tri_compact_normal, uniform_tri_count], compact_shader, 0)
	compact_pipeline = rd.compute_pipeline_create(compact_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, compact_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_compact_set, 0)
	
	var compact_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, compact_params, compact_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 512.0), 1, 1)
	
	rd.compute_list_end()
	rd.submit()
	last_compute_dispatch_frame = frame
	waiting_for_compute = true

func fetch_and_process_compute_data():
	rd.sync()
	waiting_for_compute = false
	
	counter_display_bytes = rd.buffer_get_data(tri_count_buffer)
	counter_display = counter_display_bytes.to_int32_array()[0]
	#print("Counter: ", counter_display)
	
	var trim_buffer: int = counter_display * 4 * 4
	
	compact_vertex_display_bytes = rd.buffer_get_data(tri_compact_vertex_buffer, 0, trim_buffer)
	compact_vertex_display = compact_vertex_display_bytes.to_float32_array()
	#print("Compact: ", compact_vertex_display)
	
	compact_normal_display_bytes = rd.buffer_get_data(tri_compact_normal_buffer, 0, trim_buffer)
	compact_normal_display = compact_normal_display_bytes.to_float32_array()
	#print("Compact: ", compact_normal_display)
	final_tri_vert.resize(counter_display)
	final_tri_norm.resize(counter_display)
	final_tri_ind.resize(counter_display)
	task_id = WorkerThreadPool.add_group_task(process_mesh_data, counter_display, -1, true)
	waiting_for_meshthread = true
	last_meshthread_start_frame = frame

func process_mesh_data(index: int) -> void:	
	var base: int = index * 4
	var v: Vector3 = Vector3(compact_vertex_display[base], compact_vertex_display[base+1], compact_vertex_display[base+2])
	var n: Vector3 = Vector3(compact_normal_display[base], compact_normal_display[base+1], compact_normal_display[base+2])
	final_tri_vert[index] = v
	final_tri_norm[index] = n
	final_tri_ind[index] = index

func create_mesh() -> void:
	WorkerThreadPool.wait_for_group_task_completion(task_id)
	waiting_for_meshthread = false
	#print("Num tris: ", counter_display, " FPS: ", Engine.get_frames_per_second())

	#var n = polygonize.Polygonize(grid_pos, grid_norm, grid_val, isolevel, grid_size.x, grid_size.y, tri_pos, tri_norm, border_indices)
	
	if final_tri_vert.size() > 0:
		var mesh_data = []
		mesh_data.resize(Mesh.ARRAY_MAX)
		mesh_data[Mesh.ARRAY_VERTEX] = final_tri_vert
		mesh_data[Mesh.ARRAY_NORMAL] = final_tri_norm
		mesh_data[Mesh.ARRAY_INDEX] = final_tri_ind
		array_mesh.clear_surfaces()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)
		mesh.mesh = array_mesh
	
	final_tri_vert.clear()
	final_tri_ind.clear()
	final_tri_norm.clear()

func _ready() -> void:
	#polygonize = Polygonise.new()
	array_mesh = ArrayMesh.new()
	mesh = MeshInstance3D.new()
	add_child(mesh)
	mesh.mesh = array_mesh
	construct_grid()
	setup_compute()
	compute_pipeline()
	fetch_and_process_compute_data()
	create_mesh()

func _process(_delta: float) -> void:
	if (waiting_for_compute && frame - last_compute_dispatch_frame >= num_waitframes_gpusync):
		fetch_and_process_compute_data()
	elif (waiting_for_meshthread && frame - last_meshthread_start_frame >= num_waitframes_meshthread):
		create_mesh()
	elif (!waiting_for_compute && !waiting_for_meshthread):
		isolevel = cos(frame)
		compute_pipeline()
	frame += 1
	
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
