class_name Polygonise
extends Node
var lookup = Lookup.new()

func VertexInterp(isolevel: float, p1: Vector3, p2: Vector3, valp1: float, valp2: float) -> Vector3:
	var mu: float
	var p: Vector3
	
	if abs(isolevel - valp1) < 0.00001:
		return p1
	if abs(isolevel - valp2) < 0.00001:
		return p2
	if abs(valp1 - valp2) < 0.00001:
		return p1
	mu = (isolevel - valp1) / (valp2 - valp1)
	p = p1 + mu * (p2 - p1)
	return p

class TRIANGLE:
	var p: PackedVector3Array
	var n: PackedVector3Array

class GRIDCELL:
	var p: PackedVector3Array
	var val: PackedFloat32Array
	var norm: PackedVector3Array

func Polygonize(grid: GRIDCELL, isolevel: float, triangles) -> int:
	var i: int
	var ntriang: int
	var cubeindex: int
	var vertlist: PackedVector3Array
	var normlist: PackedVector3Array
	vertlist.resize(12)
	normlist.resize(12)
	
	#Determine the index into the edge table
	cubeindex = 0
	if grid.val[0] < isolevel:
		cubeindex |= 1
	if grid.val[1] < isolevel:
		cubeindex |= 2
	if grid.val[2] < isolevel:
		cubeindex |= 4
	if grid.val[3] < isolevel:
		cubeindex |= 8
	if grid.val[4] < isolevel:
		cubeindex |= 16
	if grid.val[5] < isolevel:
		cubeindex |= 32
	if grid.val[6] < isolevel:
		cubeindex |= 64
	if grid.val[7] < isolevel:
		cubeindex |= 128
	
	# Cube is entirely in/out of the surface
	if lookup.edgeTables.get_int(cubeindex) == 0:
		return 0
	
	# Find the vertices where the surface intersects the cube
	if lookup.edgeTables.get_int(cubeindex) & 1:
		vertlist[0] = VertexInterp(isolevel, grid.p[0], grid.p[1], grid.val[0], grid.val[1])
		normlist[0] = VertexInterp(isolevel, grid.norm[0], grid.norm[1], grid.val[0], grid.val[1])
	if lookup.edgeTables.get_int(cubeindex) & 2:
		vertlist[1] = VertexInterp(isolevel, grid.p[1], grid.p[2], grid.val[1], grid.val[2])
		normlist[1] = VertexInterp(isolevel, grid.norm[1], grid.norm[2], grid.val[1], grid.val[2])
	if lookup.edgeTables.get_int(cubeindex) & 4:
		vertlist[2] = VertexInterp(isolevel, grid.p[2], grid.p[3], grid.val[2], grid.val[3])
		normlist[2] = VertexInterp(isolevel, grid.norm[2], grid.norm[3], grid.val[2], grid.val[3])
	if lookup.edgeTables.get_int(cubeindex) & 8:
		vertlist[3] = VertexInterp(isolevel, grid.p[3], grid.p[0], grid.val[3], grid.val[0])
		normlist[3] = VertexInterp(isolevel, grid.norm[3], grid.norm[0], grid.val[3], grid.val[0])
	if lookup.edgeTables.get_int(cubeindex) & 16:
		vertlist[4] = VertexInterp(isolevel, grid.p[4], grid.p[5], grid.val[4], grid.val[5])
		normlist[4] = VertexInterp(isolevel, grid.norm[4], grid.norm[5], grid.val[4], grid.val[5])
	if lookup.edgeTables.get_int(cubeindex) & 32:
		vertlist[5] = VertexInterp(isolevel, grid.p[5], grid.p[6], grid.val[5], grid.val[6])
		normlist[5] = VertexInterp(isolevel, grid.norm[5], grid.norm[6], grid.val[5], grid.val[6])
	if lookup.edgeTables.get_int(cubeindex) & 64:
		vertlist[6] = VertexInterp(isolevel, grid.p[6], grid.p[7], grid.val[6], grid.val[7])
		normlist[6] = VertexInterp(isolevel, grid.norm[6], grid.norm[7], grid.val[6], grid.val[7])
	if lookup.edgeTables.get_int(cubeindex) & 128:
		vertlist[7] = VertexInterp(isolevel, grid.p[7], grid.p[4], grid.val[7], grid.val[4])
		normlist[7] = VertexInterp(isolevel, grid.norm[7], grid.norm[4], grid.val[7], grid.val[4])
	if lookup.edgeTables.get_int(cubeindex) & 256:
		vertlist[8] = VertexInterp(isolevel, grid.p[0], grid.p[4], grid.val[0], grid.val[4])
		normlist[8] = VertexInterp(isolevel, grid.norm[0], grid.norm[4], grid.val[0], grid.val[4])
	if lookup.edgeTables.get_int(cubeindex) & 512:
		vertlist[9] = VertexInterp(isolevel, grid.p[1], grid.p[5], grid.val[1], grid.val[5])
		normlist[9] = VertexInterp(isolevel, grid.norm[1], grid.norm[5], grid.val[1], grid.val[5])
	if lookup.edgeTables.get_int(cubeindex) & 1024:
		vertlist[10] = VertexInterp(isolevel, grid.p[2], grid.p[6], grid.val[2], grid.val[6])
		normlist[10] = VertexInterp(isolevel, grid.norm[2], grid.norm[6], grid.val[2], grid.val[6])
	if lookup.edgeTables.get_int(cubeindex) & 2048:
		vertlist[11] = VertexInterp(isolevel, grid.p[3], grid.p[7], grid.val[3], grid.val[7])
		normlist[11] = VertexInterp(isolevel, grid.norm[3], grid.norm[7], grid.val[3], grid.val[7])
	
	# Create the traingle
	ntriang = 0
	i = 0
	triangles.clear()
	triangles.resize(5)
	while lookup.triTable.get_int(cubeindex, i) != -1:
		triangles[ntriang] = TRIANGLE.new()
		triangles[ntriang].p.resize(3)
		triangles[ntriang].n.resize(3)
		triangles[ntriang].p[0] = vertlist[lookup.triTable.get_int(cubeindex, i)]
		triangles[ntriang].p[1] = vertlist[lookup.triTable.get_int(cubeindex, i+1)]
		triangles[ntriang].p[2] = vertlist[lookup.triTable.get_int(cubeindex, i+2)]
		triangles[ntriang].n[0] = normlist[lookup.triTable.get_int(cubeindex, i)]
		triangles[ntriang].n[1] = normlist[lookup.triTable.get_int(cubeindex, i+1)]
		triangles[ntriang].n[2] = normlist[lookup.triTable.get_int(cubeindex, i+2)]
		i += 3
		ntriang += 1
	
	return ntriang
