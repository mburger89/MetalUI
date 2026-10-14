// The instanced triangle set of Backends/SDL/Tests (rulings GA-H, GA-F): one
// triangle drawn three times, instance i shifted by shifts[i], at depth
// depths[i], flat-coloured colors[i] (red, green, blue). The instance index
// reaches the fragment stage as a flat uint for the ID pass (spec G2).
struct VSOutput {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
    nointerpolation uint instance : TEXCOORD1;
};

static const float2 corners[3] = { float2(-0.9, -0.9), float2(0.1, -0.9), float2(-0.9, 0.1) };
static const float2 shifts[3] = { float2(0.0, 0.0), float2(0.25, 0.25), float2(0.5, 0.5) };
static const float depths[3] = { 0.5, 0.3, 0.7 };
static const float4 colors[3] = { float4(1, 0, 0, 1), float4(0, 1, 0, 1), float4(0, 0, 1, 1) };

VSOutput main(uint vertex : SV_VertexID, uint instance : SV_InstanceID) {
    VSOutput output;
    output.position = float4(corners[vertex] + shifts[instance], depths[instance], 1.0);
    output.color = colors[instance];
    output.instance = instance;
    return output;
}
