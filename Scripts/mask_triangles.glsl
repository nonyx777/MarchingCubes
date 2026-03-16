#[compute]
#version 450

layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 4, std430) restrict readonly buffer TrianglesVertexBuffer{
    vec4 points[];
}
triangles_vertex_buffer;

layout(set = 0, binding = 6, std430) restrict buffer MaskBuffer{
    uint mask[];
}
mask_buffer;

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

    float threshold = -1;
    vec4 vertex = triangles_vertex_buffer.points[idx];
    if (vertex.x != threshold){
        mask_buffer.mask[idx] = 1;
    }
    else{
        mask_buffer.mask[idx] = 0;
    }
}