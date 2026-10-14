// One oversized triangle covering the target, with the texture coordinate of
// each pixel (rulings GA-H, GA-F; spec G5). Draw it with three vertices.
struct VSOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOutput main(uint vertex : SV_VertexID) {
    VSOutput output;
    float2 uv = float2((vertex << 1) & 2, vertex & 2);
    output.uv = uv;
    output.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    return output;
}
