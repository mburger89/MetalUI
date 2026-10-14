// Writes instance + 1 into an R32_UINT target (rulings GA-H, GA-F): the ID
// pass of picking (spec G2), so the cleared background 0 is no instance.
struct PSInput {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
    nointerpolation uint instance : TEXCOORD1;
};

// GA-Q: D3D12 links a fragment input to the vertex output at the same
// register, and the cross-compiled stage numbers only the inputs it reads, so a
// stage that skips TEXCOORD0 reads TEXCOORD1 at the wrong register and
// CreateGraphicsPipelineState answers E_INVALIDARG. The colour is read by a
// test no flat colour (components 0...1) can pass, which the compiler cannot
// fold, so the stage's inputs are the vertex stage's outputs, in order.
uint main(PSInput input) : SV_Target0 {
    return input.instance + 1 + (input.color.r > 2.0 ? 1u : 0u);
}
