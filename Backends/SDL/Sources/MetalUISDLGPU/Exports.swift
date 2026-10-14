// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
/// One `import MetalUISDLGPU` gives the typed layer and every `SDL_` symbol
/// (ruling GA-B): the raw module is the escape hatch (GA-A).
@_exported import CSDL
#endif
