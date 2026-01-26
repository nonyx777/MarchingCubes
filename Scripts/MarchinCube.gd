extends Node

var isolevel: float = 2

# grid
var grid_size: Vector3i = Vector3i(10, 10, 10)
var spacing: float = 1
# grid cell related
var grid_pos: PackedVector3Array
var grid_norm: PackedVector3Array
var grid_val: PackedFloat32Array
# triangle related
var tri_pos: PackedVector3Array
var tri_norm: PackedVector3Array

# surface
var surface_array = Array()
var indices: PackedInt32Array = PackedInt32Array()

@onready var meshInstance: MeshInstance3D = $MeshInstance3D

func sphere_sdf(p: Vector3, r: float):
	return (p - Vector3(5, 5, 5)).length() - r

func generate_points(sx: int, sy: int, sz: int, spacing_: float):
	grid_pos.clear()
	for z in range(sz):
		for y in range(sy):
			for x in range(sx):
				grid_pos.append(Vector3(x * spacing_, y * spacing_, z * spacing_))

func get_point_index(x: int, y: int, z: int, sx: int, sy: int):
	return z * (sy + 1) * (sx + 1) + y * (sx + 1) + x

func setup_cells(i: int, sx: int, sy: int, sz: int) -> void:
	var i0 = i
	var i1 = i0 + 1
	var i2 = i0 + (sx + 1)
	var i3 = i2 + 1
	var i4 = i0 + (sy + 1) * (sx + 1)
	var i5 = i4 + 1
	var i6 = i4 + (sx + 1)
	var i7 = i6 + 1
	
	if i7 >= (sx * sx * sx):
		return
	
	grid_val[i0] = sphere_sdf(grid_pos[i0], isolevel)
	grid_val[i1] = sphere_sdf(grid_pos[i1], isolevel)
	grid_val[i2] = sphere_sdf(grid_pos[i2], isolevel)
	grid_val[i3] = sphere_sdf(grid_pos[i3], isolevel)
	grid_val[i4] = sphere_sdf(grid_pos[i4], isolevel)
	grid_val[i5] = sphere_sdf(grid_pos[i5], isolevel)
	grid_val[i6] = sphere_sdf(grid_pos[i6], isolevel)
	grid_val[i7] = sphere_sdf(grid_pos[i7], isolevel)
	
	# Computer normal using central difference
	for idx in [i0, i1, i2, i3, i4, i5, i6, i7]:
		var pos: Vector3 = grid_pos[idx]
		var n_x = sphere_sdf(Vector3(pos.x + 1, pos.y, pos.z) - Vector3(pos.x-1, pos.y, pos.z), isolevel) / sx
		var n_y = sphere_sdf(Vector3(pos.x, pos.y + 1, pos.z) - Vector3(pos.x, pos.y-1, pos.z), isolevel) / sy
		var n_z = sphere_sdf(Vector3(pos.x, pos.y, pos.z + 1) - Vector3(pos.x, pos.y, pos.z - 1), isolevel) / sz
		grid_norm[idx] = Vector3(n_x, n_y, n_z)

func construct_grid() -> void:
	generate_points(grid_size.x, grid_size.y, grid_size.z, spacing)
	grid_val.clear()
	grid_norm.clear()
	grid_val.resize(grid_pos.size())
	grid_norm.resize(grid_pos.size())
	for i in range(grid_pos.size()):
		setup_cells(i, grid_size.x, grid_size.y, grid_size.z)

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
	
	var polygonize: Polygonise = Polygonise.new()
	var n = polygonize.Polygonize(grid_pos, grid_norm, grid_val, isolevel, grid_size.x, grid_size.y, tri_pos, tri_norm)
	
	
	for i in range(n*3):
		indices.append(i)
	
	surface_array[Mesh.ARRAY_VERTEX] = tri_pos
	surface_array[Mesh.ARRAY_INDEX] = indices
	surface_array[Mesh.ARRAY_NORMAL] = tri_norm
	meshInstance.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
	# Sphere instances for testing
	#var multi_mesh_instance = MultiMeshInstance3D.new()
	#var multi_mesh = MultiMesh.new()
	#
	#var sphere = SphereMesh.new()
	#sphere.radius = 0.1
	#sphere.height = 0.1 * 2
	#multi_mesh.mesh = sphere
	#multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	#multi_mesh.instance_count = points.size()
	#
	#for i in range(multi_mesh.instance_count):
		#var transform = Transform3D()
		#transform.origin = points[i]
		#multi_mesh.set_instance_transform(i, transform)
	#
	#multi_mesh_instance.multimesh = multi_mesh
	#add_child(multi_mesh_instance)
	
	
	print("Points: ", grid_pos.size())
	print("Number of Triangles: ", n)
	print("Number of Vertices: ", tri_pos.size())
	print("Number of Indices: ", indices.size())
	print("Number of Normals: ", tri_norm.size())

func _ready() -> void:
	construct_grid()
	main_march()

func _on_h_slider_value_changed(value: float) -> void:
	isolevel = value
	main_march()
