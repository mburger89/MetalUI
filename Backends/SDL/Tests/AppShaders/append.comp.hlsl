// The append kernel of Backends/SDL/Tests (rulings GA-F, GA-G): a thread whose
// `v = i * 7 % 13` is below 5 claims a slot with InterlockedAdd on word 0 of a
// read-write byte-address buffer and writes its index to word 1 + slot.
// Binding: read-write storage buffers are space1, uniform buffers space2
// (SDL_GPU's compute convention).
RWByteAddressBuffer output : register(u0, space1);

cbuffer Params : register(b0, space2) {
    uint threadCount;
    uint3 padding;
};

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint i = id.x;
    if (i >= threadCount) {
        return;
    }
    uint v = (i * 7) % 13;
    if (v < 5) {
        uint slot;
        output.InterlockedAdd(0, 1, slot);
        output.Store((1 + slot) * 4, i);
    }
}
