// Samples level 0 of an R32_FLOAT texture and writes the float into the first
// channel of an R32_FLOAT target (GB-D; spec F2). SDL_GPU's fragment
// convention: samplers are space2.
Texture2D<float> source : register(t0, space2);
SamplerState sourceSampler : register(s0, space2);

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 {
    float value = source.SampleLevel(sourceSampler, uv, 0.0);
    return float4(value, 0.0, 0.0, 0.0);
}
