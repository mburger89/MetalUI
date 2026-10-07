// AccessKit's C API (ruling AX-A): fetched by scripts/fetch-accesskit.py,
// found on the compiler's default include paths (an install under /usr or
// /usr/local) or through -Xcc -I (PX-I).
#ifdef _WIN32
// accesskit.h includes <windows.h> and uses `HWND`. Under Clang modules the
// Windows runner reported "missing '#include <windef.h>'; 'HWND' must be
// declared before it is used" at accesskit.h's first HWND, and naming
// <windef.h> AFTER <windows.h> did not help: windows.h is imported as a module,
// its include guards come with it, and the later textual include is skipped.
// Named FIRST, windef.h is included into this module before anything imports
// WinSDK, so HWND is declared here.
#include <windef.h>
#include <windows.h>
#endif
#include <accesskit.h>
