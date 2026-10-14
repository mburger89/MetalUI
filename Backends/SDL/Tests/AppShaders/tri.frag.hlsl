// Passes the flat colour through (rulings GA-H, GA-F): the colour pass of the
// triangle set (spec G1, G4).
struct PSInput {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
    nointerpolation uint instance : TEXCOORD1;
};

float4 main(PSInput input) : SV_Target0 {
    return input.color;
}
