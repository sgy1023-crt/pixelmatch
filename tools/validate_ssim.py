#!/usr/bin/env python3
"""Reproduce SSIM checks with moon/node/C toolchain on PATH.

Each command has a hard 60-second timeout. Failures remain failures; no tests
are removed or skipped. Raw diagnostics are saved under ignored _build/.
Python scientific dependencies are needed only by generate_ssim_reference.py.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "_build" / "ssim-validation"


def run(label: str, command: list[str], cwd: Path = ROOT) -> None:
    result = subprocess.run(
        command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", timeout=60,
    )
    (LOGS / f"{label}.log").write_text(result.stdout, encoding="utf-8")
    print(f"{label}: exit={result.returncode}", flush=True)
    if result.returncode:
        print(result.stdout)
    result.check_returncode()


def main() -> None:
    LOGS.mkdir(parents=True, exist_ok=True)
    for target in ("js", "wasm-gc", "native"):
        run(f"targeted-{target}", ["moon", "test", "src/ssim_test.mbt",
            "src/ssim_reference_test.mbt", "--target", target, "--deny-warn"])
    run("format", ["moon", "fmt", "--check"])
    for target in ("js", "wasm-gc", "native"):
        run(f"check-{target}", ["moon", "check", "--target", target, "--deny-warn"])
    for target in ("js", "wasm-gc"):
        run(f"build-{target}", ["moon", "build", "--target", target, "--deny-warn"])
    consumer = ROOT / "examples" / "ssim"
    for target in ("js", "wasm-gc", "native"):
        run(f"consumer-build-{target}", ["moon", "build", ".", "--target", target,
            "--deny-warn"], consumer)
    for target in ("js", "wasm-gc", "native"):
        run(f"test-{target}", ["moon", "test", "--target", target, "--deny-warn"])
        run(f"consumer-{target}", ["moon", "run", ".", "--target", target,
            "--deny-warn"], consumer)
    print("All SSIM checks passed. Root native library build limitation: docs/ssim-validation.md")


if __name__ == "__main__":
    main()
