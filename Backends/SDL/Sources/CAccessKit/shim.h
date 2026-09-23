// AccessKit's C API (ruling AX-A): fetched by scripts/fetch-accesskit.py,
// found through pkg-config (Linux, macOS) or -Xcc -I (Windows).
#ifdef _WIN32
// accesskit.h includes <windows.h>, but under Clang modules `HWND` is only
// visible once <windef.h> is named here (measured on the Windows runner:
// "missing '#include <windef.h>'; 'HWND' must be declared before it is used").
#include <windows.h>
#include <windef.h>
#endif
#include <accesskit.h>
