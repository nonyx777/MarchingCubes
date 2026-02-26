#[compute]
#version 450

// Invocations
layout(local_size_x = 10, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer VerticesBuffer{
	vec3 pos[];
}
vertices_buffer;

layout(set = 0, binding = 1, std430) restrict buffer BorderElementsBuffe{
	uint indices[];
}
border_elements_buffer;

layout(set = 0, binding = 2, std430) restrict buffer TrianglesBuffer{
	vec3 points[];
}
triangles_buffer;

layout(set = 0, binding = 3, std430) restrict buffer ValuesBuffer{
	float values[];
}
values_buffer;

layout(set = 0, binding = 4, std430) restrict buffer NormalsBuffer{
	vec3 normals[];
}
normals_buffer;

layout(push_constant) uniform Params {
	uint size;
	uint border_size;
	float isolevel;
}
params;

void main()
{
	const uint size = params.size;
	const uint total_size = size * size * size;
	const float isolevel = params.isolevel;

	uint idx = gl_GlobalInvocationID.x;

	if ((idx + 1) % params.size == 0){
		return;
	}	
	for (uint i; i < params.border_size; i++){
		if (idx == i){
			return;
		}
	}
	
	uint i0 = idx;
	uint i1 = i0 + 1;
	uint i2 = i0 + size;
	uint i3 = i2 + 1;
	uint i4 = i0 + size * size;
	uint i5 = i4 + 1;
	uint i6 = i4 + size;
	uint i7 = i6 + 1;

	if (i7 >= total_size){
		return;
	}

	// Swap for correct triangle orientation
	i2 = i2 + i3;
	i3 = i2 - i3;
	i2 -= i3;

	i6 = i6 + i7;
	i7 = i6 - i7;
	i6 -= i7;
	
	// Determine the index into the edge table
	uint cubeindex = 0;
	cubeindex |= int(values_buffer.values[i0] <= isolevel) << 0;
	cubeindex |= int(values_buffer.values[i1] <= isolevel) << 1;
	cubeindex |= int(values_buffer.values[i2] <= isolevel) << 2;
	cubeindex |= int(values_buffer.values[i3] <= isolevel) << 3;
	cubeindex |= int(values_buffer.values[i4] <= isolevel) << 4;
	cubeindex |= int(values_buffer.values[i5] <= isolevel) << 5;
	cubeindex |= int(values_buffer.values[i6] <= isolevel) << 6;
	cubeindex |= int(values_buffer.values[i7] <= isolevel) << 7;
}
