#[compute]
#version 450

// #------ SIMPLEX NOISE ------#
// Description : Array and textureless GLSL 2D/3D/4D simplex 
//               noise functions.
//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : stegu
//     Lastmod : 20201014 (stegu)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise
//               https://github.com/stegu/webgl-noise

vec3 mod289(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
	return mod289(((x*34.0)+10.0)*x);
}

vec4 taylorInvSqrt(vec4 r)
{
	return 1.79284291400159 - 0.85373472095314 * r;
}

vec4 snoise(vec3 v)
{
    const vec2  C = vec2(1.0/6.0, 1.0/3.0);
    const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;

    i = mod289(i);
    vec4 p = permute(permute(permute(
             i.z + vec4(0.0, i1.z, i2.z, 1.0))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0))
           + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);

    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0)*2.0 + 1.0;
    vec4 s1 = floor(b1)*2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww;

    vec3 p0 = vec3(a0.xy,h.x);
    vec3 p1 = vec3(a0.zw,h.y);
    vec3 p2 = vec3(a1.xy,h.z);
    vec3 p3 = vec3(a1.zw,h.w);

    vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    // --- CHANGE STARTS HERE ---
    vec4 m = max(0.5 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    vec4 m2 = m * m;
    vec4 m4 = m2 * m2; // Quartic falloff to match Implementation 2
    vec4 m3 = m2 * m;  // Needed for the gradient calculation

    float noise = dot(m4, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));

    vec3 grad =
        -8.0 * ( // Derivative of (0.5 - x^2)^4 involves an 8x factor
            m3.x * dot(p0,x0) * x0 +
            m3.y * dot(p1,x1) * x1 +
            m3.z * dot(p2,x2) * x2 +
            m3.w * dot(p3,x3) * x3
        )
        +
        m4.x * p0 +
        m4.y * p1 +
        m4.z * p2 +
        m4.w * p3;
    // --- CHANGE ENDS HERE ---

    return 105.0 * vec4(noise, grad);
}

const float noise_scale = 2;
const vec3 noise_offset = vec3(0, 0, 0);
const vec3 player_pos = vec3(0, 0, 0);

vec4 evaluate(vec3 coord)
{   
	float cellSize = 1.0 / 8 * noise_scale;
	float cx = int(player_pos.x / cellSize + 0.5 * sign(player_pos.x)) * cellSize;
	float cy = int(player_pos.y / cellSize + 0.5 * sign(player_pos.y)) * cellSize;
	float cz = int(player_pos.z / cellSize + 0.5 * sign(player_pos.z)) * cellSize;
	vec3 centreSnapped = vec3(cx, cy, cz);

	vec3 posNorm = coord / vec3(8) - vec3(0.5);
	vec3 worldPos = posNorm * noise_scale + centreSnapped;
	vec3 noiseOffset = vec3(noise_offset.x, noise_offset.y, noise_offset.z);
	vec3 samplePos = (worldPos + noiseOffset) * noise_scale / noise_scale;

	float sum = 0;
	float amplitude = 1;
	float weight = 1;
	
	for (int i = 0; i < 6; i ++)
	{
		float noise = snoise(samplePos).x * 2 - 1;
		noise = 1 - abs(noise);
		noise *= noise;
		noise *= weight;
		weight = max(0, min(1, noise * 10));
		sum += noise * amplitude;
		samplePos *= 2;
		amplitude *= 0.5;
	}
	float density = sum;
	density = -(worldPos.y+100)/300 + density;

	return vec4(worldPos, density);
}

layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer VerticesBuffer{
	vec4 pos[];
}
vertices_buffer;

layout(set = 0, binding = 1, std430) restrict buffer NormalsBuffer{
	vec4 normals[];
}
normals_buffer;

layout(set = 0, binding = 2, std430) restrict buffer ValuesBuffer{
	float values[];
}
values_buffer;

layout(push_constant) uniform Params {
	uint size;
}
params;

vec4 sphere_sdf(vec3 p){
    vec3 o = vec3(5, 5, 5);
    float l = length(p - o);
    vec3 n = normalize(p - o);
    return vec4(l, n.x, n.y, n.z);
}

void main()
{
    uint idx = gl_GlobalInvocationID.x;
    uint size = params.size;

    if (idx >= size){
        return;
    }

    vec3 pos = vertices_buffer.pos[idx].xyz;

    vec4 noise_value = snoise(pos * 4);
    float density = evaluate(pos).w;

    values_buffer.values[idx] = density;
    normals_buffer.normals[idx] = vec4(-1);
}