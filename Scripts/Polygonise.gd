class_name Polygonise
extends Node
var lookup = Lookup.new()
var edgeTable = lookup.edgeTables
var triTable = lookup.triTable

func VertexInterp(isolevel: float, p1: Vector3, p2: Vector3, valp1: float, valp2: float) -> Vector3:
	var mu: float = (isolevel - valp1) / (valp2 - valp1)
	return p1 + mu * (p2 - p1)

# polygonize function should work on all the array instead of processing a single gridcell at a time
# it should take in p, val, and norm separately
func Polygonize(gc_pos: PackedVector3Array, gc_norm: PackedVector3Array, gc_val: PackedFloat32Array, isolevel: float, sx: int, sy:int, tri_pos: PackedVector3Array, tri_norm: PackedVector3Array, border_indices: PackedInt32Array) -> int:
	var i: int
	var ntriang: int = 0
	
	var vertlist: PackedVector3Array
	var normlist: PackedVector3Array
	vertlist.resize(12)
	normlist.resize(12)
	# after this everything should happen in a forloop
	# this means every neighbouring element should be computed everytime
	var total_size: int = sx * sx * sx
	for idx in range(gc_pos.size()):
		if idx in border_indices or (idx + 1) % sx == 0:
			continue
		
		# Calculate neighbours
		var i0: int = idx
		var i1: int = i0 + 1
		var i2: int = i0 + (sx)
		var i3: int = i2 + 1
		var i4: int = i0 + (sy) * (sx)
		var i5: int = i4 + 1
		var i6: int = i4 + (sx)
		var i7: int = i6 + 1
		
		if i7 >= total_size:
			continue
		
		# swap for correct triangle orientation
		var temp_x: int = i2
		i2 = i3
		i3 = temp_x
		temp_x = i6
		i6 = i7
		i7 = temp_x
		
		#Determine the index into the edge table
		var cubeindex: int = 0
		if gc_val[i0] < isolevel:
			cubeindex |= 1
		if gc_val[i1] < isolevel:
			cubeindex |= 2
		if gc_val[i2] < isolevel:
			cubeindex |= 4
		if gc_val[i3] < isolevel:
			cubeindex |= 8
		if gc_val[i4] < isolevel:
			cubeindex |= 16
		if gc_val[i5] < isolevel:
			cubeindex |= 32
		if gc_val[i6] < isolevel:
			cubeindex |= 64
		if gc_val[i7] < isolevel:
			cubeindex |= 128
	
		# Cube is entirely in/out of the surface
		if edgeTable.get_int(cubeindex) == 0:
			continue
			
		# Find the vertices where the surface intersects the cube
		if edgeTable.get_int(cubeindex) & 1:
			vertlist[0] = VertexInterp(isolevel, gc_pos[i0], gc_pos[i1], gc_val[i0], gc_val[i1])
			normlist[0] = VertexInterp(isolevel, gc_norm[i0], gc_norm[i1], gc_val[i0], gc_val[i1])
		if edgeTable.get_int(cubeindex) & 2:
			vertlist[1] = VertexInterp(isolevel, gc_pos[i1], gc_pos[i2], gc_val[i1], gc_val[i2])
			normlist[1] = VertexInterp(isolevel, gc_norm[i1], gc_norm[i2], gc_val[i1], gc_val[i2])
		if edgeTable.get_int(cubeindex) & 4:
			vertlist[2] = VertexInterp(isolevel, gc_pos[i2], gc_pos[i3], gc_val[i2], gc_val[i3])
			normlist[2] = VertexInterp(isolevel, gc_norm[i2], gc_norm[i3], gc_val[i2], gc_val[i3])
		if edgeTable.get_int(cubeindex) & 8:
			vertlist[3] = VertexInterp(isolevel, gc_pos[i3], gc_pos[i0], gc_val[i3], gc_val[i0])
			normlist[3] = VertexInterp(isolevel, gc_norm[i3], gc_norm[i0], gc_val[i3], gc_val[i0])
		if edgeTable.get_int(cubeindex) & 16:
			vertlist[4] = VertexInterp(isolevel, gc_pos[i4], gc_pos[i5], gc_val[i4], gc_val[i5])
			normlist[4] = VertexInterp(isolevel, gc_norm[i4], gc_norm[i5], gc_val[i4], gc_val[i5])
		if edgeTable.get_int(cubeindex) & 32:
			vertlist[5] = VertexInterp(isolevel, gc_pos[i5], gc_pos[i6], gc_val[i5], gc_val[i6])
			normlist[5] = VertexInterp(isolevel, gc_norm[i5], gc_norm[i6], gc_val[i5], gc_val[i6])
		if edgeTable.get_int(cubeindex) & 64:
			vertlist[6] = VertexInterp(isolevel, gc_pos[i6], gc_pos[i7], gc_val[i6], gc_val[i7])
			normlist[6] = VertexInterp(isolevel, gc_norm[i6], gc_norm[i7], gc_val[i6], gc_val[i7])
		if edgeTable.get_int(cubeindex) & 128:
			vertlist[7] = VertexInterp(isolevel, gc_pos[i7], gc_pos[i4], gc_val[i7], gc_val[i4])
			normlist[7] = VertexInterp(isolevel, gc_norm[i7], gc_norm[i4], gc_val[i7], gc_val[i4])
		if edgeTable.get_int(cubeindex) & 256:
			vertlist[8] = VertexInterp(isolevel, gc_pos[i0], gc_pos[i4], gc_val[i0], gc_val[i4])
			normlist[8] = VertexInterp(isolevel, gc_norm[i0], gc_norm[i4], gc_val[i0], gc_val[i4])
		if edgeTable.get_int(cubeindex) & 512:
			vertlist[9] = VertexInterp(isolevel, gc_pos[i1], gc_pos[i5], gc_val[i1], gc_val[i5])
			normlist[9] = VertexInterp(isolevel, gc_norm[i1], gc_norm[i5], gc_val[i1], gc_val[i5])
		if edgeTable.get_int(cubeindex) & 1024:
			vertlist[10] = VertexInterp(isolevel, gc_pos[i2], gc_pos[i6], gc_val[i2], gc_val[i6])
			normlist[10] = VertexInterp(isolevel, gc_norm[i2], gc_norm[i6], gc_val[i2], gc_val[i6])
		if edgeTable.get_int(cubeindex) & 2048:
			vertlist[11] = VertexInterp(isolevel, gc_pos[i3], gc_pos[i7], gc_val[i3], gc_val[i7])
			normlist[11] = VertexInterp(isolevel, gc_norm[i3], gc_norm[i7], gc_val[i3], gc_val[i7])
	
		# Create the traingles
		i = 0
		while triTable.get_int(cubeindex, i) != -1:
			tri_pos.append(vertlist[triTable.get_int(cubeindex, i)])
			tri_pos.append(vertlist[triTable.get_int(cubeindex, i+1)])
			tri_pos.append(vertlist[triTable.get_int(cubeindex, i+2)])
			tri_norm.append(normlist[triTable.get_int(cubeindex, i)])
			tri_norm.append(normlist[triTable.get_int(cubeindex, i+1)])
			tri_norm.append(normlist[triTable.get_int(cubeindex, i+2)])
			i += 3
			ntriang += 1
	
	# Ultimately I want to processs and populate the elements inside the tri_p and tri_n
	return ntriang
