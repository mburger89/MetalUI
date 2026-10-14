// One triangle whose clip-space positions come from a vertex-stage storage
// buffer (rulings GA-H, GA-F; spec G4). SDL_GPU's vertex convention: read-only
// storage buffers are space0.
StructuredBuffer<float4> positions : register(t0, space0);

struct VSOutput {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
    nointerpolation uint instance : TEXCOORD1;
};

VSOutput main(uint vertex : SV_VertexID, uint instance : SV_InstanceID) {
    VSOutput output;
    output.position = positions[vertex];
    output.color = float4(0, 1, 1, 1);
    output.instance = instance;
    return output;
}
