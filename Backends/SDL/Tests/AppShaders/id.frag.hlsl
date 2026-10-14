// Writes instance + 1 into an R32_UINT target (rulings GA-H, GA-F): the ID
// pass of picking (spec G2), so the cleared background 0 is no instance.
struct PSInput {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
    nointerpolation uint instance : TEXCOORD1;
};

uint main(PSInput input) : SV_Target0 {
    return input.instance + 1;
}
