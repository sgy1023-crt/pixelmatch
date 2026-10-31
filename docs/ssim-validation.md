# SSIM delivery evidence

Validation date: 2026-10-31. P0 engineering implementation is complete.
This records local evidence, not GitHub CI results, maintainer approval,
publication, competition submission or organizer acceptance.

## Baseline and scope

- Upstream: `https://github.com/mizchi/pixelmatch`, main
  `aab5b0a23e0be7fb71d250c742f5644cf6c7acc7`, module version 0.6.2.
- Initial workspace was empty; repository was cloned without overwriting user files.
  Development branch: `codex/local-gaussian-ssim`.
- GitHub repository / Issue #6 / open PR page checked at development start:
  Issue open, zero open PRs, no extra maintainer requirement beyond the issue body.
  Remote main still matched the reviewed baseline; five remote branches were present.
  GitHub API supplementary requests hit rate limiting; the public web pages and
  direct Git remote queries were used as the evidence.
- Existing dependencies retained: `mizchi/image@0.4.3`, `mizchi/zlib@0.4.10`.
  No compiler/runtime/source patch, C stub change, codec or CLI implementation.
- New production logic is confined to `src/ssim.mbt` and one core math import.
  Public interfaces were generated with `moon info`. The generator also refreshes
  existing `Int` spellings to `Int32`, reflecting source types already in baseline;
  no existing signature behavior was changed.

## Toolchain and environment

Windows x64, Intel Core i5-12450H; Node v24.22.1. Native tool selected MSVC
Build Tools 2022, version 14.44.35207.

The preinstalled compiler (moonc 0.10.12, 2026-09-07) could not resolve the
upstream baseline's existing `Int32` type. Official current tools were installed
in an isolated directory outside the repository, preserving the global install
and Windows execution policy:

```text
moon 0.1.20261028 (e1e1f15 2026-10-28)
moonc v0.10.18+6c83a7f62 (2026-10-28)
moonrun 0.1.20261028 (e1e1f15 2026-10-28)
```

Python fixture tooling: Python 3.13, NumPy 2.2.4, SciPy 1.17.0, skimage 0.26.0.
These are development references only; library consumers and MoonBit tests
have no Python or scientific-package dependency.

## Results

All unit-test commands were subject to a hard 60-second subprocess timeout.
No timeout, failed test, ignored test or removed test was needed for final results.

| Check | JS | Wasm-GC | Native |
| --- | --- | --- | --- |
| `moon check --target ... --deny-warn` | Pass | Pass | Pass |
| New SSIM tests + independent reference | 26/26 | 26/26 | 26/26 |
| Complete `moon test --target ... --deny-warn` | 59/59 | 59/59 | 59/59 |
| Root `moon build --target ... --deny-warn` | Pass | Pass | Baseline failure, below |
| Independent consumer build, `--deny-warn` | Pass | Pass | Pass |
| Independent consumer execution, `--deny-warn` | Pass | Pass | Pass |

`moon fmt --check`, `moon info`, reference regeneration `--check`, and
`git diff --check` also passed. The 26 new tests comprise 14 behavior/invalid-input
tests and 12 independently generated numeric fixtures; the 3 benchmark cases
are executed by `moon bench`, separately from the unit-test counts.

The independent consumer uses public API only, including result fields,
parameter metadata, signed raw map access, display score, error rendering and
map-to-Image conversion. Its example score is approximately `0.24444666865`.

### Existing native root-build failure

The root package and e2e package have no `main`; the current Windows build path
tries to link executable artifacts, failing with MSVC `LNK2019` (missing main) /
`LNK1120`. Existing `-lz` is also reported as unrecognized by the MSVC linker
(`LNK4044`). This was independently reproduced from `git archive` of the exact
unmodified baseline SHA, with the same isolated toolchain. It is **not** counted
as a successful root native build and was not hidden by changing package settings.

The native tests generate test entrypoints and pass. The independent consumer
has a real `main`, builds and runs on Native successfully. Use that consumer to
reproduce the SSIM native application build; resolving root non-main artifact
linking or cross-platform upstream link flags is a separate upstream tooling task.
There are no added MoonBit compiler warnings. `--deny-warn` is a MoonBit check,
not a claim that the existing native linker flags produce no external warnings.

## Numeric comparison

Each backend executed all 12 fixtures and compared every one of 1,539 map pixels,
including boundaries. All three component means were checked for every fixture,
including zero variance and one-pixel windows. The actual maxima were identical
on the three locally tested backends:

| Absolute error | Observed maximum | Acceptance tolerance |
| --- | ---: | ---: |
| Aggregate score | 2.6922908347160046e-15 | 1e-9 |
| Full map | 8.326672684688674e-15 | 1e-9 |
| Component mean | 2.3647750424515834e-14 | 1e-8 |

Map/score oracle: SciPy Gaussian filter with explicit radius and population
covariance. Component oracle: direct 2D weighted central moments. Eight compatible
fixtures additionally cross-check skimage's Gaussian SSIM; custom-support fixtures
do not falsely claim that passing skimage `win_size` changes Gaussian support.
See `ssim-reference.json` for per-fixture reference values and provenance and
`ssim.md` for preprocessing and every numerical convention.

Tests cover identity, different constants, a single changed pixel, local changed
regions, brightness, contrast, structure/anticorrelation, transparent and partial
alpha, malformed image storage, unequal/empty/negative/overflow dimensions,
invalid channels, invalid/nonfinite parameters, different windows/sigmas,
the smallest valid extent, reflection, input symmetry, map aggregation and
visualization preserving signed raw values.

Independent read-only review also compared the ring buffer with direct 2D
convolution over all valid odd windows for widths/heights 1..15; all accesses were
in bounds. Origin translation was independently checked against central moments.

## Performance and memory

Command actually executed on the final algorithm:

```sh
moon bench src/ssim_bench_test.mbt --target js --release --deny-warn
```

| Image | Mean ± sample deviation | Observed range |
| --- | --- | --- |
| 200×200 | 4.25 ms ± 248.09 µs | 3.95–4.68 ms |
| 1920×1080 | 225.34 ms ± 11.10 ms | 215.19–252.07 ms |
| 3840×2160 | 1.40 s ± 266.65 ms | 903.03 ms–1.62 s |

Default 11×11 / sigma 1.5; deterministic nonconstant grayscale data with a modified
vertical region. Image setup is outside the timed closure. Allocation of map and
scratch, validation, all moments, components and aggregation are inside. The
MoonBit harness used 10 measurement groups (21 runs/group at 200×200 and
1 run/group for each larger size). These are measurements on this machine only,
not speedup claims or timings for Wasm-GC/Native.

No peak-RSS measurement is claimed. The independently reviewed numeric payload
estimate is 79.94 MiB at 1080p and 318.08 MiB at 4K, including two existing inputs
and the result. Scratch uses only 0.84 / 1.67 MiB, respectively; see `ssim.md`
for the formula, optional visualization allocation and runtime/GC limitations.

## Reproduction and remaining scope

With the recorded toolchain on PATH:

```sh
python tools/validate_ssim.py
python tools/generate_ssim_reference.py --check
```

The first command needs only Python and the normal MoonBit/Node/C tools. The
second additionally needs the pinned scientific dependencies and `moonfmt`.
Raw local output is saved under ignored `_build/ssim-validation/`; no personal
paths, binaries, registry caches or downloaded toolchain are included in Git.

Remaining Issue #6 scope is the P1 PNG CLI command/JSON wiring. Per-channel SSIM,
MS-SSIM and per-pixel component maps are not part of this P0. There are no new
runtime dependencies or intentionally changed existing APIs.

Engineering assessment: **Upstream PR Ready: Yes** for the documented P0 scope;
**Hackathon final engineering acceptance Ready: Yes** for the user's stated P0.
The baseline Windows root native-build limitation remains disclosed. These
judgments do not assert a maintainer's or competition organizer's approval.
No push, PR creation, publication or contest registration was performed.
