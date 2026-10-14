// Samples one mip level of an R8 texture and writes it as grey (rulings GA-H,
// GA-F; spec G5). SDL_GPU's fragment convention: samplers are space2, uniform
// buffers space3.
Texture2D<float> source : register(t0, space2);
SamplerState sourceSampler : register(s0, space2);

cbuffer Params : register(b0, space3) {
    float level;
    float3 padding;
};

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 {
    float value = source.SampleLevel(sourceSampler, uv, level);
    return float4(value, value, value, 1.0);
}
