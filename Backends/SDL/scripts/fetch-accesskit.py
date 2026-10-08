#!/usr/bin/env python3
"""Fetches AccessKit's C bindings for this host (rulings AX-A, PX-I, PX-Q).

Downloads the accesskit-c 0.23.0 release and checks its SHA-256. The release
ships prebuilt static libraries for macOS, Linux x86_64 and Windows x64; on any
other host (Linux aarch64) the library is built from the Rust sources in the
same archive with cargo, which must then be installed.

  fetch-accesskit.py --prefix DIR
      Stages the download in a temporary directory (or $ACCESSKIT_DIR when set)
      and copies only accesskit.h to DIR/include and the static library to
      DIR/lib — with DIR /usr, the compiler's default paths, so a build needs
      no flags. Writes nothing beside this script (a SwiftPM checkout).

  fetch-accesskit.py [--print-flags]
      Keeps the files in $ACCESSKIT_DIR (default: Backends/SDL/.accesskit) and
      prints the SwiftPM flags that reach them, one per line:
      -Xcc -I<include> -Xlinker -L<lib> (-Xswiftc -L<lib> on Windows). On macOS
      Homebrew's include and lib directories come first, for SDL3.
      Progress goes to standard error, so `$(fetch-accesskit.py --print-flags)`
      is the flags alone.

No pkg-config file is written: the root package declares no pkgConfig (PX-H).
"""
import argparse, hashlib, os, platform, shutil, subprocess, sys, tempfile, urllib.request, zipfile

VERSION = "0.23.0"
URL = f"https://github.com/AccessKit/accesskit-c/releases/download/{VERSION}/accesskit-c-{VERSION}.zip"
SHA256 = "dd2f84f51bea0bcf01270a7505b2b85a7945d40d703b6f479d64963accb4b95d"

parser = argparse.ArgumentParser(description="Fetch AccessKit's C bindings (accesskit-c %s)." % VERSION)
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--prefix", metavar="DIR", help="install accesskit.h and the library under DIR/include and DIR/lib")
mode.add_argument("--print-flags", action="store_true", help="print the SwiftPM flags (the default)")
args = parser.parse_args()


def log(message):
    print(message, file=sys.stderr)


def fetch(root):
    """Unpacks the release under `root` (building the library if needed);
    returns (include directory, static library path)."""
    root = os.path.normpath(root)
    source = os.path.join(root, f"accesskit-c-{VERSION}")
    archive = os.path.join(root, "accesskit.zip")
    os.makedirs(root, exist_ok=True)
    if not os.path.isdir(source):
        if not os.path.exists(archive):
            log(f"downloading {URL}")
            urllib.request.urlretrieve(URL, archive)
        digest = hashlib.sha256(open(archive, "rb").read()).hexdigest()
        if digest != SHA256:
            os.remove(archive)
            sys.exit(f"accesskit-c checksum mismatch: {digest}")
        with zipfile.ZipFile(archive) as z:
            z.extractall(root)

    system, machine = platform.system(), platform.machine().lower()
    arch = {"amd64": "x86_64", "x86_64": "x86_64", "arm64": "arm64", "aarch64": "aarch64"}.get(machine, machine)
    if system == "Darwin":
        prebuilt = os.path.join(source, "lib", "macos", arch, "static", "libaccesskit.a")
    elif system == "Linux":
        prebuilt = os.path.join(source, "lib", "linux", arch, "static", "libaccesskit.a")
    elif system == "Windows":
        prebuilt = os.path.join(source, "lib", "windows", arch, "msvc", "static", "accesskit.lib")
    else:
        sys.exit(f"unsupported host {system}")

    lib_dir = os.path.join(root, "lib")
    os.makedirs(lib_dir, exist_ok=True)
    name = os.path.basename(prebuilt)
    library = os.path.join(lib_dir, name)
    if not os.path.exists(library):
        if os.path.exists(prebuilt):
            shutil.copy(prebuilt, library)
        else:
            log(f"no prebuilt AccessKit for {system} {arch}; building from source with cargo")
            subprocess.run(["cargo", "build", "--release", "--locked"], cwd=source, check=True,
                           stdout=sys.stderr)
            shutil.copy(os.path.join(source, "target", "release", name), library)
    return os.path.join(source, "include"), library


if args.prefix:
    staging = os.environ.get("ACCESSKIT_DIR")
    temporary = None if staging else tempfile.mkdtemp(prefix="accesskit-")
    try:
        include, library = fetch(staging or temporary)
        prefix = os.path.abspath(args.prefix)
        os.makedirs(os.path.join(prefix, "include"), exist_ok=True)
        os.makedirs(os.path.join(prefix, "lib"), exist_ok=True)
        shutil.copy(os.path.join(include, "accesskit.h"), os.path.join(prefix, "include", "accesskit.h"))
        shutil.copy(library, os.path.join(prefix, "lib", os.path.basename(library)))
        log(f"installed accesskit.h in {prefix}/include and {os.path.basename(library)} in {prefix}/lib")
    finally:
        if temporary:
            shutil.rmtree(temporary, ignore_errors=True)
else:
    root = os.environ.get("ACCESSKIT_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".accesskit")
    include, library = fetch(root)
    lib_dir = os.path.dirname(library)
    flags = []
    if platform.system() == "Darwin":
        # SDL3 from Homebrew, which is not on the compiler's default paths (PX-I item 3).
        try:
            brew = subprocess.run(["brew", "--prefix"], capture_output=True, text=True, check=True).stdout.strip()
            flags += ["-Xcc", f"-I{brew}/include", "-Xlinker", f"-L{brew}/lib"]
        except (OSError, subprocess.CalledProcessError):
            log("no Homebrew: pass SDL3's -Xcc -I<prefix>/include -Xlinker -L<prefix>/lib yourself")
    flags += ["-Xcc", f"-I{include}"]
    flags += ["-Xswiftc", f"-L{lib_dir}"] if platform.system() == "Windows" else ["-Xlinker", f"-L{lib_dir}"]
    print("\n".join(flags))
