#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 4, std430) restrict readonly buffer TrianglesVertexBuffer{
    vec4 points[];
}
triangles_vertex_buffer;

layout(set = 0, binding = 5, std430) restrict buffer TrianglesNormalBuffer{
	vec4 normals[];
}
triangles_normal_buffer;

layout(set = 0, binding = 6, std430) restrict readonly buffer MaskBuffer{
    uint mask[];
}
mask_buffer;

layout(set = 0, binding = 7, std430) restrict readonly buffer PrefixSumBuffer{
    uint prefixsum[];
}
prefixsum_buffer;

layout(set = 0, binding = 8, std430) restrict buffer CompactVertexBuffer{
    vec4 compact_vertex[];
}
compact_vertex_buffer;

layout(set = 0, binding = 9, std430) restrict buffer CompactNormalBuffer{
    vec4 compact_normal[];
}
compact_normal_buffer;


layout(push_constant) uniform Params {
    uint size;
}
params;

void main()
{
    uint size = params.size;
    uint idx = gl_GlobalInvocationID.x;

    if (idx >= size){
        return;
    }

    if (mask_buffer.mask[idx] == 1){
        uint index = prefixsum_buffer.prefixsum[idx];
        compact_vertex_buffer.compact_vertex[index] = triangles_vertex_buffer.points[idx];
        compact_normal_buffer.compact_normal[index] = triangles_normal_buffer.normals[idx];
    }
}