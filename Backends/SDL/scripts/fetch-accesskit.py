#!/usr/bin/env python3
"""Fetches AccessKit's C bindings for this host (ruling AX-A).

Downloads the accesskit-c 0.23.0 release, checks its SHA-256, unpacks it to
Backends/SDL/.accesskit/ (or $ACCESSKIT_DIR), and writes .accesskit/accesskit.pc for pkg-config
(Linux, macOS) — or prints the -I/-L flags a Windows build passes to SwiftPM.
The release ships prebuilt static libraries for macOS, Linux x86_64 and
Windows x64; on any other host (Linux aarch64) the library is built from the
Rust sources in the same archive with cargo.
"""
import hashlib, os, platform, shutil, subprocess, sys, urllib.request, zipfile

VERSION = "0.23.0"
URL = f"https://github.com/AccessKit/accesskit-c/releases/download/{VERSION}/accesskit-c-{VERSION}.zip"
SHA256 = "dd2f84f51bea0bcf01270a7505b2b85a7945d40d703b6f479d64963accb4b95d"

# ACCESSKIT_DIR overrides the destination — the Linux CI image bakes it into
# /opt/accesskit so the mounted checkout needs nothing.
root = os.environ.get("ACCESSKIT_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".accesskit")
root = os.path.normpath(root)
source = os.path.join(root, f"accesskit-c-{VERSION}")
archive = os.path.join(root, "accesskit.zip")

os.makedirs(root, exist_ok=True)
if not os.path.isdir(source):
    if not os.path.exists(archive):
        print(f"downloading {URL}")
        urllib.request.urlretrieve(URL, archive)
    digest = hashlib.sha256(open(archive, "rb").read()).hexdigest()
    if digest != SHA256:
        os.remove(archive)
        sys.exit(f"accesskit-c checksum mismatch: {digest}")
    with zipfile.ZipFile(archive) as z:
        z.extractall(root)

system, machine = platform.system(), platform.machine().lower()
arch = {"amd64": "x86_64", "x86_64": "x86_64", "arm64": "arm64", "aarch64": "aarch64"}.get(machine, machine)
include = os.path.join(source, "include")
lib_dir = os.path.join(root, "lib")
os.makedirs(lib_dir, exist_ok=True)

if system == "Darwin":
    prebuilt = os.path.join(source, "lib", "macos", arch, "static", "libaccesskit.a")
    libs = "-laccesskit -framework AppKit -framework Foundation -framework CoreFoundation -lobjc -lc++"
elif system == "Linux":
    prebuilt = os.path.join(source, "lib", "linux", arch, "static", "libaccesskit.a")
    libs = "-laccesskit -lm"
elif system == "Windows":
    prebuilt = os.path.join(source, "lib", "windows", arch, "msvc", "static", "accesskit.lib")
    libs = ""
else:
    sys.exit(f"unsupported host {system}")

name = os.path.basename(prebuilt)
target = os.path.join(lib_dir, name)
if not os.path.exists(target):
    if os.path.exists(prebuilt):
        shutil.copy(prebuilt, target)
    else:
        print(f"no prebuilt AccessKit for {system} {arch}; building from source with cargo")
        subprocess.run(["cargo", "build", "--release", "--locked"], cwd=source, check=True)
        shutil.copy(os.path.join(source, "target", "release", name), target)

if system == "Windows":
    print(f"-Xcc -I{include} -Xswiftc -L{lib_dir}")
else:
    with open(os.path.join(root, "accesskit.pc"), "w") as pc:
        pc.write(f"Name: accesskit\nDescription: AccessKit C bindings {VERSION}\nVersion: {VERSION}\n"
                 f"Cflags: -I{include}\nLibs: -L{lib_dir} {libs}\n")
    print(f"PKG_CONFIG_PATH={root}")
