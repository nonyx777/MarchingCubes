extends Node

var isolevel: float = 0
var torus_parameter: Vector2 = Vector2(2, 0.5)
var noise := FastNoiseLite.new()

var sphere_radius: float = 2
var torus_radius: float = 2
var noise_randomness: float = 5

var polygonize: Polygonise

# grid
var grid_size: Vector3i = Vector3i(10, 10, 10)
var total_point_count: int
var spacing: float = 1
# grid cell related
var grid_pos: PackedVector4Array
var grid_norm: PackedVector4Array
var grid_val: PackedFloat32Array
# triangle related
var tri_pos: PackedVector4Array
var tri_norm: PackedVector4Array
var tri_mask: PackedInt32Array
var tri_prefixsum: PackedInt32Array
# border element indices
var border_indices: PackedInt32Array

# surface
var surface_array = Array()
var indices: PackedInt32Array = PackedInt32Array()

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
	if i in border_indices:
		return
	
	var i0 = i
	var i1 = i0 + 1
	var i2 = i0 + (sx)
	var i3 = i2 + 1
	var i4 = i0 + (sy) * (sx)
	var i5 = i4 + 1
	var i6 = i4 + (sx)
	var i7 = i6 + 1
	
	if i7 >= (sx * sx * sx):
		return
	
	grid_val[i0] = noise_density(grid_pos[i0], noise_randomness)
	grid_val[i1] = noise_density(grid_pos[i1], noise_randomness)
	grid_val[i2] = noise_density(grid_pos[i2], noise_randomness)
	grid_val[i3] = noise_density(grid_pos[i3], noise_randomness)
	grid_val[i4] = noise_density(grid_pos[i4], noise_randomness)
	grid_val[i5] = noise_density(grid_pos[i5], noise_randomness)
	grid_val[i6] = noise_density(grid_pos[i6], noise_randomness)
	grid_val[i7] = noise_density(grid_pos[i7], noise_randomness)
	
	# Computer normal using central difference
	for idx in [i0, i1, i2, i3, i4, i5, i6, i7]:
		var pos: Vector4 = grid_pos[idx]
		var n_x = (noise_density(Vector4(pos.x + 1, pos.y, pos.z, 0.0), noise_randomness) - noise_density(Vector4(pos.x-1, pos.y, pos.z, 0.0), noise_randomness)) / 2 * sx
		var n_y = (noise_density(Vector4(pos.x, pos.y + 1, pos.z, 0.0), noise_randomness) - noise_density(Vector4(pos.x, pos.y-1, pos.z, 0.0), noise_randomness)) / 2 * sy
		var n_z = (noise_density(Vector4(pos.x, pos.y, pos.z + 1, 0.0), noise_randomness) - noise_density(Vector4(pos.x, pos.y, pos.z-1, 0.0), noise_randomness)) / 2 * sz
		var n_w = -1
		grid_norm[idx] = Vector4(n_x, n_y, n_z, n_w).normalized()

func construct_grid() -> void:
	total_point_count = grid_size.x * grid_size.y * grid_size.z
	generate_points(grid_size.x, grid_size.y, grid_size.z, spacing)
	get_border()
	grid_val.clear()
	grid_norm.clear()
	grid_val.resize(grid_pos.size())
	grid_norm.resize(grid_pos.size())
	for i in range(grid_pos.size()):
		setup_cells(i, grid_size.x, grid_size.y, grid_size.z)

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
	tri_pos.fill(Vector4(-1, -1, -1, -1))
	tri_norm.fill(Vector4(-1, -1, -1, -1))
	tri_mask.fill(0)
	tri_prefixsum.fill(0)
	
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
	
	#initializing storage buffers
	# VerticesBuffer
	var grid_pos_bytes: PackedByteArray = grid_pos.to_byte_array()
	var vertices_buffer := rd.storage_buffer_create(grid_pos_bytes.size(), grid_pos_bytes)
	var uniform_vertices := RDUniform.new()
	uniform_vertices.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_vertices.binding = 0
	uniform_vertices.add_id(vertices_buffer)
	
	# NormalsBuffer
	var grid_norm_bytes: PackedByteArray = grid_norm.to_byte_array()
	var normals_buffer := rd.storage_buffer_create(grid_norm_bytes.size(), grid_norm_bytes)
	var uniform_normals := RDUniform.new()
	uniform_normals.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_normals.binding = 1
	uniform_normals.add_id(normals_buffer)
	
	# ValuesBuffer
	var grid_val_bytes: PackedByteArray = grid_val.to_byte_array()
	var values_buffer := rd.storage_buffer_create(grid_val_bytes.size(), grid_val_bytes)
	var uniform_values := RDUniform.new()
	uniform_values.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_values.binding = 2
	uniform_values.add_id(values_buffer)
	
	# BorderElementsBuffer
	var border_indices_bytes: PackedByteArray = border_indices.to_byte_array()
	var border_indices_buffer := rd.storage_buffer_create(border_indices_bytes.size(), border_indices_bytes)
	var uniform_border_indices := RDUniform.new()
	uniform_border_indices.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_border_indices.binding = 3
	uniform_border_indices.add_id(border_indices_buffer)
	
	# TriangleVertexBuffer
	var tri_pos_bytes: PackedByteArray = tri_pos.to_byte_array()
	var tri_pos_buffer := rd.storage_buffer_create(tri_pos_bytes.size(), tri_pos_bytes)
	var uniform_tri_pos := RDUniform.new()
	uniform_tri_pos.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_pos.binding = 4
	uniform_tri_pos.add_id(tri_pos_buffer)
	
	# TriangleNormalBuffer
	var tri_norm_bytes: PackedByteArray = tri_norm.to_byte_array()
	var tri_norm_buffer := rd.storage_buffer_create(tri_norm_bytes.size(), tri_norm_bytes)
	var uniform_tri_norm := RDUniform.new()
	uniform_tri_norm.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_norm.binding = 5
	uniform_tri_norm.add_id(tri_norm_buffer)
	
	# TriangleMaskBuffer
	var tri_mask_bytes: PackedByteArray = tri_mask.to_byte_array()
	var tri_mask_buffer := rd.storage_buffer_create(tri_mask_bytes.size(), tri_mask_bytes)
	var uniform_tri_mask := RDUniform.new()
	uniform_tri_mask.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_mask.binding = 6
	uniform_tri_mask.add_id(tri_mask_buffer)
	
	# TrianglePrefixSumBuffer
	var tri_prefixsum_bytes: PackedByteArray = tri_prefixsum.to_byte_array()
	var tri_prefixsum_buffer := rd.storage_buffer_create(tri_prefixsum_bytes.size(), tri_prefixsum_bytes)
	var uniform_tri_prefixsum := RDUniform.new()
	uniform_tri_prefixsum.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_tri_prefixsum.binding = 7
	uniform_tri_prefixsum.add_id(tri_prefixsum_buffer)
	
	compute_list = rd.compute_list_begin()
	
	# Populate Shader....................................................................................
	
	var uniform_populate_set := rd.uniform_set_create([uniform_vertices, uniform_normals, uniform_values, uniform_border_indices, uniform_tri_pos, uniform_tri_norm], populate_shader, 0)
	var populate_pipeline := rd.compute_pipeline_create(populate_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, populate_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_populate_set, 0)
	
	var populate_params: PackedByteArray = PackedInt32Array([grid_size.x, border_indices.size(), int(isolevel), 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, populate_params, populate_params.size())
	rd.compute_list_dispatch(compute_list, ceil(total_point_count / 64.0), 1, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Mask Shader......................................................................................
	var uniform_mask_set := rd.uniform_set_create([uniform_tri_pos, uniform_tri_mask], mask_shader, 0)
	var mask_pipeline := rd.compute_pipeline_create(mask_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, mask_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_mask_set, 0)
	
	var mask_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, mask_params, mask_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 64.0), 1, 1)
	
	# Prefixsum Shader...................................................................................
	var uniform_prefixsum_set := rd.uniform_set_create([uniform_tri_pos, uniform_tri_mask, uniform_tri_prefixsum], prefixsum_shader, 0)
	var prefixsum_pipeline := rd.compute_pipeline_create(prefixsum_shader)
	rd.compute_list_bind_compute_pipeline(compute_list, prefixsum_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_prefixsum_set, 0)
	
	var prefixsum_params: PackedByteArray = PackedInt32Array([tri_size, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, prefixsum_params, prefixsum_params.size())
	rd.compute_list_dispatch(compute_list, ceil(tri_size / 64.0), 1, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	#var tri_display_bytes := rd.buffer_get_data(tri_pos_buffer)
	#var tri_display := tri_display_bytes.to_float32_array()
	#print("Triangles: ", tri_display)
	
	#var mask_display_bytes := rd.buffer_get_data(tri_mask_buffer)
	#var mask_display := mask_display_bytes.to_int32_array()
	#print("Mask: ", mask_display)
	
	var prefixsum_display_bytes := rd.buffer_get_data(tri_prefixsum_buffer)
	var prefixsum_display := prefixsum_display_bytes.to_int32_array()
	print("Prefixsum: ", prefixsum_display)

func main_march() -> void:
	tri_pos.clear()
	tri_norm.clear()
	# initialize surface array
	meshInstance.mesh.clear_surfaces()
	surface_array.resize(Mesh.ARRAY_MAX)
	surface_array[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	surface_array[Mesh.ARRAY_INDEX] = PackedInt32Array()
	surface_array[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	
	indices.clear()
	
	for i in range(grid_pos.size()):
		setup_cells(i, grid_size.x, grid_size.y, grid_size.z)
	var n = polygonize.Polygonize(grid_pos, grid_norm, grid_val, isolevel, grid_size.x, grid_size.y, tri_pos, tri_norm, border_indices)
	
	
	for i in range(n*3):
		indices.append(i)
	
	surface_array[Mesh.ARRAY_VERTEX] = tri_pos
	surface_array[Mesh.ARRAY_INDEX] = indices
	surface_array[Mesh.ARRAY_NORMAL] = tri_norm
	meshInstance.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
	print("Points: ", grid_pos.size())
	print("Number of Triangles: ", n)
	print("Number of Vertices: ", tri_pos.size())
	print("Number of Indices: ", indices.size())
	print("Number of Normals: ", tri_norm.size())

func _ready() -> void:
	polygonize = Polygonise.new()
	construct_grid()
	setup_compute()
	print("Works")
	#main_march()

#func _on_h_slider_value_changed(value: float) -> void:
	#sphere_radius = value
	#torus_radius = value
	#noise_randomness = value * 10
	#main_march()
