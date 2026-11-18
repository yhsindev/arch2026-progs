# Report measurement evidence

The [final report](../ASSIGNMENT2_REPORT_FINAL.md) contains the interpretation
and limits. These files make its numerical claims inspectable.

- `cycles.csv`, `footprint.csv`: November 8 measurements of implementation
  `ef7eaee1684875372bbbde966716e17c59eca99c`; four compiler optimization levels.
- `GITHUB_CI_20261109.txt`: historical CI result for that implementation.
  It is not the status of later documentation commits.
- `measure_error.py`, `numerical-error.json`: independent host arithmetic
  comparison for the BF16 domains stated in the report; rerun November 18.
- `rubik-hotspot/`: November 18 controlled experiment. `calls.csv` holds
  uninstrumented counts; `events.csv` holds separate instrumented events.
  `summary.json` aggregates both. `metadata.json` records hashes, tools and
  commands. Logs retain test summaries; `ablation.diff` defines the generated
  counterfactual, which is not a historical implementation.

From the repository root, with the toolchain and emulator installed:

```sh
source notes/activate.sh
make cycles dump size sanitize test
python3 notes/report-assets/measure_error.py
python3 mytests/rubik_hotspot.py
```

The hotspot tool leaves submitted sources and official tests unchanged.
It generates three variants under ignored `build/rubik-hotspot/`. Only the
two uninstrumented variants are compared for performance; diagnostic event
counter overhead is excluded. Each variant independently checks the returned
moves and known shortest lengths for 66 calls. Both uninstrumented variants
also run the unchanged 52-test suite.

Guest instruction counts are not physical CPU timings. The original compiler
comparison and the diagnostic experiment have different callers, so compare
variants within each experiment. These finite workloads do not establish an
all-state worst-case result. Rerunning the tools replaces their output files.
