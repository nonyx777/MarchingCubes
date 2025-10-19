extends Node

var isolevel: float = 2

# grid
var grid_size: Vector3i = Vector3i(10, 10, 10)
var spacing: float = 1
var points: PackedVector3Array = []
var gridcells: Array = []
var triangles: Array = []

@onready var meshInstance: MeshInstance3D = $MeshInstance3D


func sphere_sdf(p: Vector3, r: float):
	return (p - Vector3(5, 5, 5)).length() - r

func generate_points(sx: int, sy: int, sz: int, spacing_: float):
	points.clear()
	for z in range(sz + 1):
		for y in range(sy + 1):
			for x in range(sx + 1):
				points.append(Vector3(x * spacing_, y * spacing_, z * spacing_))

func get_point_index(x: int, y: int, z: int, sx: int, sy: int):
	return z * (sy + 1) * (sx + 1) + y * (sx + 1) + x

func get_cell(x, y, z) -> Polygonise.GRIDCELL:
	var sx = grid_size.x
	var sy = grid_size.y
	var sz = grid_size.z
	var i0 = get_point_index(x, y, z, sx, sy)
	var i1 = i0 + 1
	var i2 = i0 + (sx + 1)
	var i3 = i2 + 1
	var i4 = i0 + (sy + 1) * (sx + 1)
	var i5 = i4 + 1
	var i6 = i4 + (sx + 1)
	var i7 = i6 + 1
	
	var grid: Polygonise.GRIDCELL = Polygonise.GRIDCELL.new()
	grid.p = PackedVector3Array([points[i0], points[i1], points[i3], points[i2], points[i4], points[i5], points[i7], points[i6]])
	grid.val = PackedFloat32Array([sphere_sdf(points[i0], isolevel), sphere_sdf(points[i1], isolevel), sphere_sdf(points[i3], isolevel), sphere_sdf(points[i2], isolevel), sphere_sdf(points[i4], isolevel), sphere_sdf(points[i5], isolevel), sphere_sdf(points[i7], isolevel), sphere_sdf(points[i6], isolevel)])
	grid.norm = PackedVector3Array()
	grid.norm.resize(grid.p.size())
	
	# Computer normal using centeral difference
	for i in range(grid.p.size()):
		var g = grid.p[i]
		var g_x = sphere_sdf(Vector3(g.x + 1, g.y, g.z) - Vector3(g.x-1, g.y, g.z), isolevel) / sx
		var g_y = sphere_sdf(Vector3(g.x, g.y + 1, g.z) - Vector3(g.x, g.y-1, g.z), isolevel) / sy
		var g_z = sphere_sdf(Vector3(g.x, g.y, g.z + 1) - Vector3(g.x, g.y, g.z - 1), isolevel) / sz
		grid.norm[i] = Vector3(g_x, g_y, g_z)
	
	return grid

func _ready() -> void:
	# initialize surface array
	var surface_array = Array()
	surface_array.resize(Mesh.ARRAY_MAX)
	var verts: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var normals: PackedVector3Array = PackedVector3Array()
	
	var polygonize: Polygonise = Polygonise.new()
	triangles.resize(5)
	
	generate_points(grid_size.x, grid_size.y, grid_size.z, spacing)
	for z in range(grid_size.z):
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				gridcells.append(get_cell(x, y, z))
	
	var n = 0
	for cell in gridcells:
		var ntri: int = 0
		ntri = polygonize.Polygonize(cell, isolevel, triangles)
		n += ntri
		for i in range(ntri):
			for vert in triangles[i].p:
				verts.append(vert)
			for norm in triangles[i].n:
				normals.append(norm)
	
	for i in range(n*3):
		indices.append(i)
	
	surface_array[Mesh.ARRAY_VERTEX] = verts
	surface_array[Mesh.ARRAY_INDEX] = indices
	surface_array[Mesh.ARRAY_NORMAL] = normals
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
	
	
	print("Points: ", points.size())
	print("GridCells: ", gridcells.size())
	print("Number of Triangles: ", n)
	print("Number of Vertices: ", verts.size())
	print("Number of Indices: ", indices.size())
	#print("Center GridCell: ", gridcells[555].p)
