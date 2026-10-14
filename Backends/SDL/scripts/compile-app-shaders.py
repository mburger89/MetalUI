#!/usr/bin/env python3
"""Build an app's own SDL_GPU shaders from HLSL (ruling GA-F).

For every `NAME.vert.hlsl`, `NAME.frag.hlsl` and `NAME.comp.hlsl` in --source
(the stage comes from the suffix, the entry point is `main`) this runs
SDL_shadercross exactly as `compile-shaders.py` does for the renderer's own
shaders: HLSL to SPIR-V, then SPIR-V to MSL, DXIL and a reflection JSON, into
--out as `NAME.vert.spv` ... `NAME.comp.json`. It then writes `SOURCE.sha256`,
one `<sha256>  <file>` line per source, sorted by name: the file
`SDLGPUShaderLibrary` requires beside the blobs and a CI step can compare.

    compile-app-shaders.py --shadercross /path/to/shadercross --source shaders --out shaders/compiled

shadercross is the only dependency (SDL_shadercross's release binary or a
source build). A release archive keeps its shared libraries in a `lib`
directory beside `bin`; this script puts that directory on the loader path
for the child process, so the archive runs unpacked.
"""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys

STAGES = {"vert": "vertex", "frag": "fragment", "comp": "compute"}

parser = argparse.ArgumentParser()
parser.add_argument("--shadercross", required=True, type=Path)
parser.add_argument("--source", required=True, type=Path, help="directory of NAME.{vert,frag,comp}.hlsl")
parser.add_argument("--out", required=True, type=Path, help="directory the blobs and SOURCE.sha256 go to")
args = parser.parse_args()

compiler = str(args.shadercross.resolve())
env = dict(os.environ)
library_directory = args.shadercross.resolve().parent.parent / "lib"
if library_directory.is_dir():
    for variable in ("DYLD_LIBRARY_PATH", "LD_LIBRARY_PATH"):
        env[variable] = str(library_directory) + os.pathsep + env.get(variable, "")

sources = sorted(path for path in args.source.glob("*.hlsl") if path.name.split(".")[-2] in STAGES)
if not sources:
    sys.exit(f"no NAME.vert.hlsl, NAME.frag.hlsl or NAME.comp.hlsl in {args.source}")
args.out.mkdir(parents=True, exist_ok=True)

for source in sources:
    base = source.name[: -len(".hlsl")]  # "append.comp"
    stage = STAGES[base.split(".")[-1]]
    spirv = args.out / f"{base}.spv"
    subprocess.run([compiler, str(source), "-s", "HLSL", "-d", "SPIRV", "-t", stage, "-o", str(spirv)],
                   check=True, env=env)
    # Every other format derives from the same intermediate representation.
    for fmt, extension in (("MSL", "msl"), ("DXIL", "dxil"), ("JSON", "json")):
        subprocess.run([compiler, str(spirv), "-s", "SPIRV", "-d", fmt, "-t", stage,
                        "-o", str(args.out / f"{base}.{extension}")], check=True, env=env)
    print(base, (args.out / f"{base}.json").read_text().strip())

# CI (or a test) compares this with the sources, so a stale blob fails loudly.
lines = [f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in sources]
(args.out / "SOURCE.sha256").write_text("".join(lines))
print(f"Compiled {len(sources)} shader(s) to SPIR-V, MSL, DXIL and reflection JSON:", args.out)
