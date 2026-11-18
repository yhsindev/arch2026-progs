"""Measure the actual C BF16 routines against independent host arithmetic.

Run from the repository; cc builds a temporary native library. No target
source or official test is modified. The report's published run used macOS.
"""
from pathlib import Path
import ctypes
import json
import math
import subprocess
import sys
import tempfile

assets = Path(__file__).resolve().parent
repo = assets.parents[1]


def value(bits):
    exponent = (bits >> 7) & 255
    fraction = bits & 127
    if exponent == 0:
        return math.ldexp(fraction / 128.0, -126)
    return math.ldexp(1 + fraction / 128.0, exponent - 127)


with tempfile.TemporaryDirectory(prefix="arch2026-bf16-error-") as work:
    library = Path(work) / "bf16.so"
    flags = ["-dynamiclib"] if sys.platform == "darwin" else ["-shared", "-fPIC"]
    subprocess.run(["cc", *flags, "-O2", str(repo / "src/bf16/bf16.c"),
                    "-o", str(library)], check=True)
    lib = ctypes.CDLL(str(library))
    lib.bf16_sqrt.argtypes = [ctypes.c_uint16]
    lib.bf16_sqrt.restype = ctypes.c_uint16
    lib.bf16_mul.argtypes = [ctypes.c_uint16, ctypes.c_uint16]
    lib.bf16_mul.restype = ctypes.c_uint16
    root_max = (0.0, 0, 0)
    for a in range(0x0080, 0x7F80):
        result = lib.bf16_sqrt(a)
        reference = math.sqrt(value(a))
        error = abs(value(result) - reference) / reference
        if error > root_max[0]:
            root_max = error, a, result
    product_max = (0.0, 0, 0, 0)
    for fa in range(128):
        for fb in range(128):
            a, b = 0x3F80 | fa, 0x3F80 | fb
            result = lib.bf16_mul(a, b)
            reference = value(a) * value(b)
            error = abs(value(result) - reference) / reference
            if error > product_max[0]:
                product_max = error, a, b, result

summary = {
    "sqrt_positive_normals": {
        "inputs": 0x7F80 - 0x0080,
        "relative_error_max": root_max[0],
        "input_hex": f"0x{root_max[1]:04X}",
        "result_hex": f"0x{root_max[2]:04X}",
    },
    "mul_unit_binade_mantissas": {
        "pairs": 128 * 128,
        "relative_error_max": product_max[0],
        "a_hex": f"0x{product_max[1]:04X}",
        "b_hex": f"0x{product_max[2]:04X}",
        "result_hex": f"0x{product_max[3]:04X}",
    },
}
(assets / "numerical-error.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
