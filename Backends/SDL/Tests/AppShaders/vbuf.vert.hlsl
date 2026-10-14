// One triangle from an interleaved vertex buffer (rulings GA-H, GA-F; spec G6):
// location 0 is a float2 position, location 1 a premultiplied float4 colour.
struct VSInput {
    float2 position : TEXCOORD0;
    float4 color : TEXCOORD1;
};

struct VSOutput {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
    nointerpolation uint instance : TEXCOORD1;
};

VSOutput main(VSInput input, uint instance : SV_InstanceID) {
    VSOutput output;
    output.position = float4(input.position, 0.5, 1.0);
    output.color = input.color;
    output.instance = instance;
    return output;
}
