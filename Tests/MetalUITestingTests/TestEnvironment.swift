#if os(Windows)
import ucrt
#else
import Foundation
#endif

/// Sets an environment variable for this process and the children it spawns (an exit test's child inherits it).
/// `setenv` does not exist on Windows; `_putenv_s` updates the CRT's copy and the process environment both.
func setTestEnvironment(_ name: String, _ value: String) {
    #if os(Windows)
    _ = _putenv_s(name, value)
    #else
    setenv(name, value, 1)
    #endif
}

/// Removes an environment variable from this process. On Windows `_putenv_s` with an empty value removes it.
func unsetTestEnvironment(_ name: String) {
    #if os(Windows)
    _ = _putenv_s(name, "")
    #else
    unsetenv(name)
    #endif
}
