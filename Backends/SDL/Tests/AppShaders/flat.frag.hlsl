// Flat red (GB-J; spec W1): the fragment of a depth-only prepass drawn with
// fullscreen.vert. GA-Q: the stage keeps the vertex stage's TEXCOORD0 as an
// input, read by a test no uv (0...2) can pass, which the compiler cannot fold.
float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 {
    return float4(1.0, 0.0, 0.0, uv.x > 1.0e30 ? 0.0 : 1.0);
}
