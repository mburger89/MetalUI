#!/usr/bin/env python3
"""Compile the eleven HLSL stages and reflect the exact bindings used by SDL."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--shadercross", required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = root / "Shaders" / "compiled"
out.mkdir(parents=True, exist_ok=True)
compiler = str(args.shadercross.resolve())
# (file name, stage, defines): the six stages of the three drawable kinds, then
# the five of the backdrop blur (rulings BB-A, BB-D): the material's quad in
# both stages, the shared full-target triangle and the two pass fragments.
KINDS = {"rect": [], "glyph": ["-DGLYPH_STAGE"], "image": ["-DIMAGE_STAGE"], "backdrop": ["-DBACKDROP_STAGE"]}
STAGES = [(f"{kind}.{stage}", stage, (["-DVERTEX_STAGE"] if stage == "vertex" else []) + defines)
          for kind, defines in KINDS.items() for stage in ("vertex", "fragment")]
STAGES += [("pass.vertex", "vertex", ["-DVERTEX_STAGE", "-DPASS_STAGE"]),
           ("downsample.fragment", "fragment", ["-DPASS_STAGE", "-DDOWNSAMPLE_STAGE"]),
           ("gaussian.fragment", "fragment", ["-DPASS_STAGE", "-DGAUSSIAN_STAGE"])]
for name, stage, defines in STAGES:
    spirv = out / f"{name}.spv"
    subprocess.run([compiler, str(root / "Shaders/replay.hlsl"), "-s", "HLSL", "-d", "SPIRV", "-t", stage, *defines, "-o", str(spirv)], check=True)
    # Derive all backend formats from the same intermediate representation.
    for fmt, extension in (("MSL", "msl"), ("DXIL", "dxil"), ("JSON", "json")):
        subprocess.run([compiler, str(spirv), "-s", "SPIRV", "-d", fmt, "-t", stage, "-o", str(out / f"{name}.{extension}")], check=True)
    reflection = json.loads((out / f"{name}.json").read_text())
    print(name, reflection)
# CI compares this with the source, so a stale compiled/ fails loudly.
(out / "SOURCE.sha256").write_text(hashlib.sha256((root / "Shaders/replay.hlsl").read_bytes()).hexdigest() + "  replay.hlsl\n")
print("Compiled eleven stages to SPIR-V, DXIL, MSL, and reflection JSON:", out)
