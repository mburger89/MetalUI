#!/usr/bin/env python3
"""Compile the four HLSL stages and reflect the exact bindings used by SDL."""
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
for kind in ("rect", "glyph"):
    for stage in ("vertex", "fragment"):
        name = f"{kind}.{stage}"
        defines = (["-DVERTEX_STAGE"] if stage == "vertex" else []) + (["-DGLYPH_STAGE"] if kind == "glyph" else [])
        spirv = out / f"{name}.spv"
        subprocess.run([compiler, str(root / "Shaders/replay.hlsl"), "-s", "HLSL", "-d", "SPIRV", "-t", stage, *defines, "-o", str(spirv)], check=True)
        # Derive all backend formats from the same intermediate representation.
        for fmt, extension in (("MSL", "msl"), ("DXIL", "dxil"), ("JSON", "json")):
            subprocess.run([compiler, str(spirv), "-s", "SPIRV", "-d", fmt, "-t", stage, "-o", str(out / f"{name}.{extension}")], check=True)
        reflection = json.loads((out / f"{name}.json").read_text())
        print(name, reflection)
# CI compares this with the source, so a stale compiled/ fails loudly.
(out / "SOURCE.sha256").write_text(hashlib.sha256((root / "Shaders/replay.hlsl").read_bytes()).hexdigest() + "  replay.hlsl\n")
print("Compiled four stages to SPIR-V, DXIL, MSL, and reflection JSON:", out)
