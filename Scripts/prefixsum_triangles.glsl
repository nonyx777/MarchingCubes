#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 4, std430) restrict readonly buffer TrianglesVertexBuffer{
    vec4 points[];
}
triangles_vertex_buffer;

layout(set = 0, binding = 6, std430) restrict readonly buffer MaskBuffer{
    uint mask[];
}
mask_buffer;

layout(set = 0, binding = 7, std430) restrict buffer PrefixSumBuffer{
    uint prefixsum[];
}
prefixsum_buffer;

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

    if (idx == 0){
        prefixsum_buffer.prefixsum[idx] = 0;
    }
    else{
        uint sum = 0;
        for (uint i = 0; i < idx; i++){
            sum += mask_buffer.mask[i];
        }
        prefixsum_buffer.prefixsum[idx] = sum;
    }
}