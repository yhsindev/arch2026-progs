#!/usr/bin/env python3
"""Isolate Rubik's inline terminal precheck; keep submitted sources unchanged.

Run from the repository root after sourcing notes/activate.sh:
    python3 mytests/rubik_hotspot.py
"""
import csv
from datetime import datetime, timezone
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/rubik-hotspot"
OUT = ROOT / "notes/report-assets/rubik-hotspot"
SOURCE = ROOT / "src/rubik/rubik.S"
FIELDS = [
    "search_entries", "prefix_nodes", "terminal_attempts", "terminal_probes",
    "terminal_hits", "terminal_misses", "terminal_wraps", "pdb_prunes",
    "finish_entries", "lookup_entries", "lookup_probes", "transition_steps",
    "bound_iterations",
]
COMMANDS = []


def run(args, *, log=None, timeout=120):
    args = [str(x) for x in args]
    COMMANDS.append(args)
    p = subprocess.run(args, cwd=ROOT, text=True, capture_output=True,
                       timeout=timeout, check=False)
    output = p.stdout + p.stderr
    if log:
        log.write_text(output)
    if p.returncode:
        raise RuntimeError(f"exit {p.returncode}: {args}\n{output[-4000:]}")
    return output


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"expected one source anchor: {old[:100]!r}")
    return source.replace(old, new, 1)


def instrument(source):
    macro = r"""
    .macro HS_COUNT offset
    addi sp, sp, -16
    sw t5, 0(sp)
    sw t6, 4(sp)
    la t6, hs_counts
    lw t5, \offset(t6)
    addi t5, t5, 1
    sw t5, \offset(t6)
    lw t5, 0(sp)
    lw t6, 4(sp)
    addi sp, sp, 16
    .endm
"""
    source = once(source, "    .text\n", "    .text\n" + macro)

    def count(name):
        return f"    HS_COUNT {4 * FIELDS.index(name)}\n"

    labels = {
        ".Lrubik_search": "search_entries",
        ".Lrubik_search_prefix": "prefix_nodes",
        ".Lrubik_search_probe": "terminal_probes",
        ".Lrubik_search_found": "terminal_hits",
        ".Lrubik_finish": "finish_entries",
        ".Lrubik_lookup": "lookup_entries",
        ".Lrubik_probe": "lookup_probes",
        ".Lrubik_search_turn": "transition_steps",
        ".Lrubik_deepen": "bound_iterations",
    }
    for label, name in labels.items():
        source = once(source, label + ":\n", label + ":\n" + count(name))
    boundary = "    bltu    t0, a2, .Lrubik_search_prefix\n"
    source = once(source, boundary, boundary + count("terminal_attempts"))
    prune = "    bltu    a2, t0, .Lrubik_search_fail"
    if source.count(prune) != 2:
        raise ValueError("expected exactly two PDB rejection branches")
    source = source.replace(prune, "    bltu    a2, t0, .Lhs_pruned")
    source = once(source,
                  "    beq     t3, t4, .Lrubik_search_fail",
                  "    beq     t3, t4, .Lhs_miss")
    wrap = "    bne     t1, t5, .Lrubik_search_probe\n"
    source = once(source, wrap, wrap + count("terminal_wraps"))
    extra = (
        "\n.Lhs_pruned:\n" + count("pdb_prunes") +
        "    j .Lrubik_search_fail\n.Lhs_miss:\n" +
        count("terminal_misses") + "    j .Lrubik_search_fail\n"
    )
    source = once(source, "    .section .rodata\n",
                  extra + "    .section .rodata\n")
    return source + (
        "\n    .section .bss\n    .balign 4\n"
        "    .globl hs_counts\n    .type hs_counts, @object\n"
        f"hs_counts:\n    .space {4 * len(FIELDS)}\n"
        f"    .size hs_counts, {4 * len(FIELDS)}\n"
    )


def parse(output):
    records = []
    for match in re.finditer(r"^@@hotspot (.*)$", output, re.M):
        row = dict(token.split("=", 1) for token in match[1].split())
        for key in ("index", "distance", "instructions", *FIELDS):
            if key in row:
                row[key] = int(row[key])
        records.append(row)
    if len(records) != 66:
        raise ValueError(f"expected 6+59+1 records, got {len(records)}")
    return records


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    prefix = os.environ.get("CROSS_COMPILE", "riscv-none-elf-")
    cc, assembler, ld, nm, objdump, size_tool = [
        shutil.which(prefix + suffix)
        for suffix in ("gcc", "as", "ld", "nm", "objdump", "size")
    ]
    if not all((cc, assembler, ld, nm, objdump, size_tool)):
        raise RuntimeError("Source notes/activate.sh or set CROSS_COMPILE first")
    emu = ROOT / "third_party/rv32emu/build/rv32emu"
    if not emu.exists():
        raise RuntimeError("Build the repository's emulator first")
    names = ("start", "perf", "rt", "print", "utest", "trt", "tutest")
    common = [ROOT / f"build/common/{name}.o" for name in names]
    cimpl = ROOT / "build/rubik/O2/impl.o"
    run(["make", str(cimpl.relative_to(ROOT)), "build/rubik/impl_asm.o",
         *[str(p.relative_to(ROOT)) for p in common]], log=OUT / "build.log")
    original_hash = digest(SOURCE)
    original = SOURCE.read_text()
    start = original.index("    # Most terminal probes miss.")
    stop = original.index(".Lrubik_search_fail:", start)
    baseline = original[:start] + (
        "    # Ablation: enter finish without an inline precheck.\n"
        "    mv a3, a2\n    mv a2, a4\n    j .Lrubik_finish\n"
    ) + original[stop:]
    # Export zero-instruction aliases: this assembler drops .L names even
    # with -L. Aliases let us inspect the linked block boundaries.
    labelled = original
    for label, alias in ((".Lrubik_search", "hs_search_start"),
                         (".Lrubik_search_probe", "hs_probe_start"),
                         (".Lrubik_search_found", "hs_probe_found")):
        labelled = once(labelled, label + ":\n",
                        label + ":\n    .globl " + alias + "\n" + alias + ":\n")
    variants = {
        "final": labelled,
        "no_inline_probe": baseline,
        "profile": instrument(original),
    }
    (OUT / "ablation.diff").write_text("".join(difflib.unified_diff(
        original.splitlines(True), baseline.splitlines(True),
        fromfile="submitted/rubik.S", tofile="experiment/no_inline_probe.S")))
    records = {}
    bench = {}
    elf_hashes = {}
    sizes = {}
    flags = ["-march=rv32i_zicsr", "-mabi=ilp32"]
    for name, source in variants.items():
        print(f"Building/running {name}", flush=True)
        asm = BUILD / f"{name}.S"
        asm.write_text(source)
        impl, harness, elf = [BUILD / f"{name}{suffix}"
                              for suffix in (".o", "-main.o", ".elf")]
        run([assembler, *flags, "-g", "-L", asm, "-o", impl])
        run([cc, *flags, "-O2", "-g", "-ffreestanding", "-fno-pic",
             "-fno-stack-protector", "-Wall", "-Wextra", "-Werror", "-Wvla",
             "-iquote", ".", "-Icommon", "-Itests",
             '-DOPT_NAME="O2"', f'-DHS_VARIANT="{name}"',
             f"-DHS_PROFILE={int(name == 'profile')}",
             "-c", "mytests/rubik_hotspot.c", "-o", harness])
        run([ld, "-T", "common/linker.ld", "--no-warn-rwx-segments",
             "-o", elf, harness, impl, cimpl, *common])
        elf_hashes[name] = digest(elf)
        output = run([emu, elf], log=OUT / f"{name}.log")
        if name != "profile" and "Summary: 52 passed, 0 failed." not in output:
            raise RuntimeError(f"{name}: expected unchanged 52-test suite to pass")
        records[name] = parse(output)
        m = re.search(r"^@@bench (.*)$", output, re.M)
        if m:
            b = dict(token.split("=", 1) for token in m[1].split())
            bench[name] = {
                "calls": int(b["n"]),
                "mean": (int(b["cycles"]) - int(b["overhead"])) / int(b["n"]),
                "checksum": int(b["checksum"]),
            }
        dis = run([objdump, "-d", "-M", "no-aliases", elf])
        (BUILD / f"{name}.dis").write_text(dis)
        size_out = run([size_tool, "-A", impl])
        sizes[name] = {m[1]:int(m[2]) for m in re.finditer(
            r"^(\.text|\.rodata|\.data|\.bss)\s+(\d+)\b",size_out,re.M)}

    def text_bytes(obj):
        dump = run([objdump, "-s", "-j", ".text", obj])
        chunks = re.findall(
            r"^\s*[0-9a-f]+\s+((?:[0-9a-f]{8}\s+){1,4})",dump,re.M)
        return bytes.fromhex("".join(chunks))

    assert text_bytes(BUILD/"final.o") == text_bytes(
        ROOT/"build/rubik/impl_asm.o"), "Final text differs from submitted object"

    # The interpreter's -p report does not contain execution frequencies.
    # Count selected events in a separate, semantics-preserving diagnostic.
    # Timing above uses only uninstrumented final/baseline ELFs.
    symbols = run([nm, "-an", BUILD / "final.elf"])
    addresses = {}
    for line in symbols.splitlines():
        parts = line.split()
        if len(parts) == 3 and re.fullmatch(r"[0-9a-fA-F]+", parts[0]):
            addresses[parts[2]] = int(parts[0], 16)
    search = addresses["hs_search_start"]
    probe = addresses["hs_probe_start"]
    found = addresses["hs_probe_found"]
    # Eight instructions perform the PDB/bound tests before the setup.
    setup = (probe - search) // 4 - 8
    if setup != 13 or (found - probe) // 4 != 8:
        raise RuntimeError("Reinspect the probe block's instruction weights")
    dis = (BUILD / "final.dis").read_text()
    insns = {}
    for m in re.finditer(
            r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(\S+)\s*(.*)$", dis, re.M):
        insns[int(m[1], 16)] = m[2]
    expected_probe = ["lw", "beq", "srli", "beq", "addi", "bne", "addi", "jal"]
    if [insns[probe + 4*i] for i in range(8)] != expected_probe:
        raise RuntimeError("Probe disassembly differs from the cost model")
    profile = records["profile"]
    measured = {r["dataset"] + ":" + str(r["index"]): r
                for r in records["final"]}
    for r in profile:
        assert r["search_entries"] == (
            r["prefix_nodes"] + r["terminal_attempts"] + r["pdb_prunes"])
        assert r["terminal_attempts"] == r["terminal_hits"] + r["terminal_misses"]
        collisions = r["terminal_probes"] - r["terminal_attempts"]
        assert collisions >= r["terminal_wraps"] >= 0
        # Setup=13; miss exits after 2 probe instructions, hit after 4;
        # collision=6, plus 2 when the pointer wraps. Excludes fail returns,
        # successful reconstruction, and the initial PDB/bound checks.
        r["derived_probe_instructions"] = (
            setup * r["terminal_attempts"] + 2 * r["terminal_misses"] +
            4 * r["terminal_hits"] + 6 * collisions + 2 * r["terminal_wraps"])
        r["uninstrumented_instructions"] = measured[
            r["dataset"] + ":" + str(r["index"])]["instructions"]

    with (OUT / "calls.csv").open("w", newline="") as f:
        rows = records["no_inline_probe"] + records["final"]
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    with (OUT / "events.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(profile[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(profile)
    summary = {"bench": bench, "object_sizes":sizes,"datasets": {}}
    for dataset in ("bench6", "official59", "directed"):
        a = [r for r in records["no_inline_probe"] if r["dataset"] == dataset]
        b = [r for r in records["final"] if r["dataset"] == dataset]
        p = [r for r in profile if r["dataset"] == dataset]
        assert [(r["state"],r["distance"]) for r in a] == [
            (r["state"],r["distance"]) for r in b]
        av, bv = sum(r["instructions"] for r in a), sum(
            r["instructions"] for r in b)
        counts = {k:sum(r[k] for r in p) for k in FIELDS}
        probe_insns = sum(r["derived_probe_instructions"] for r in p)
        summary["datasets"][dataset] = {
            "calls":len(a), "baseline_total":av, "final_total":bv,
            "reduction_percent":100*(1-bv/av),
            "baseline_mean":av/len(a), "final_mean":bv/len(b),
            "events":counts,
            "terminal_miss_percent":100*counts["terminal_misses"] /
                counts["terminal_attempts"],
            "derived_probe_instructions":probe_insns,
            "derived_probe_share_percent":100*probe_insns/bv,
        }
    assert bench["final"]["checksum"] == bench["no_inline_probe"]["checksum"]
    assert digest(SOURCE) == original_hash
    metadata = {
        "created_utc":datetime.now(timezone.utc).isoformat(),
        "source_commit":run(["git","rev-parse","HEAD"]).strip(),
        "source_sha256":original_hash,
        "table_sha256":digest(ROOT/"src/rubik/rubik_tables.inc"),
        "harness_sha256":digest(ROOT/"mytests/rubik_hotspot.c"),
        "oracle_sha256":digest(ROOT/"tests/trubik.c"),
        "vectors_sha256":digest(ROOT/"tests/rubikvec.h"),
        "c_implementation_sha256":digest(ROOT/"src/rubik/rubik.c"),
        "emulator_binary_sha256":digest(emu),
        "emulator_config_sha256":digest(
            ROOT/"third_party/rv32emu/build/.effective-config"),
        "final_text_matches_submitted_object":True,
        "elf_sha256":elf_hashes,
        "compiler":run([cc,"--version"]).splitlines()[0],
        "emulator_commit":run(
            ["git","-C","third_party/rv32emu","rev-parse","HEAD"]).strip(),
        "commands":COMMANDS,
        "probe_instruction_weights":{
            "setup":setup,"miss":2,"hit":4,"collision":6,"wrap_extra":2},
    }
    (OUT/"metadata.json").write_text(json.dumps(metadata,indent=2)+"\n")
    (OUT/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
    print(json.dumps(summary,indent=2),flush=True)


if __name__ == "__main__":
    main()
