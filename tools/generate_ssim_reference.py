#!/usr/bin/env python3
"""Regenerate independent SSIM fixtures; no MoonBit runtime or network required.

Install numpy==2.2.4 scipy==1.17.0 scikit-image==0.26.0 and put the
MoonBit 2026-10-28 moonfmt on PATH, then run:
    python tools/generate_ssim_reference.py
    python tools/generate_ssim_reference.py --check

The complete map comes from SciPy's float64 Gaussian filter. Components come
from direct, two-dimensional weighted central moments, independently of the
production implementation's separable raw-moment calculation. scikit-image
cross-checks fixtures whose explicit radius matches its truncate=3.5 radius.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
import scipy
from scipy.ndimage import gaussian_filter
import skimage
from skimage.metrics import structural_similarity


ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "docs" / "ssim-reference.json"
TEST_PATH = ROOT / "src" / "ssim_reference_test.mbt"
VERSIONS = {"numpy": "2.2.4", "scipy": "1.17.0", "scikit-image": "0.26.0"}
SSIM_TOLERANCE = 1e-9
COMPONENT_TOLERANCE = 1e-8
C1 = 6.5025
C2 = 58.5225


def texture(width: int, height: int, phase: int = 0, alpha: bool = False) -> np.ndarray:
    """Integer-only input formula avoids RNG and image-decoder dependencies."""
    y, x = np.indices((height, width), dtype=np.int64)
    rgba = np.empty((height, width, 4), dtype=np.int64)
    rgba[..., 0] = (37 * x + 17 * y + 13 * x * y + 29 * phase) % 256
    rgba[..., 1] = (11 * x + 53 * y + 7 * x * y + 61 * phase) % 256
    rgba[..., 2] = (73 * x + 19 * y + 3 * x * y + 43 * phase) % 256
    rgba[..., 3] = (31 * x + 47 * y + 17 * phase) % 256 if alpha else 255
    if alpha:
        rgba[0, 0, 3] = 0
        rgba[-1, -1, 3] = 255
    return rgba


def gray(width: int, height: int, value: int) -> np.ndarray:
    rgba = np.full((height, width, 4), value, dtype=np.int64)
    rgba[..., 3] = 255
    return rgba


def luminance(rgba: np.ndarray) -> np.ndarray:
    pixels = rgba.astype(np.float64)
    opaque = (
        0.29889531 * pixels[..., 0]
        + 0.58662247 * pixels[..., 1]
        + 0.11448223 * pixels[..., 2]
    )
    return 255.0 + (opaque - 255.0) * (pixels[..., 3] / 255.0)


def interior(values: np.ndarray, radius: int) -> np.ndarray:
    height, width = values.shape
    return values[radius : height - radius, radius : width - radius]


def scipy_ssim(first: np.ndarray, second: np.ndarray, size: int, sigma: float) -> np.ndarray:
    def filtered(values: np.ndarray) -> np.ndarray:
        return gaussian_filter(
            values, sigma=sigma, radius=size // 2, mode="reflect", output=np.float64
        )

    ux, uy = filtered(first), filtered(second)
    vx = filtered(first * first) - ux * ux
    vy = filtered(second * second) - uy * uy
    covariance = filtered(first * second) - ux * uy
    return ((2 * ux * uy + C1) * (2 * covariance + C2)) / (
        (ux * ux + uy * uy + C1) * (vx + vy + C2)
    )


def central_moments(first: np.ndarray, second: np.ndarray, size: int, sigma: float) -> dict:
    radius = size // 2
    offsets = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(offsets * offsets) / (2.0 * sigma * sigma))
    kernel /= kernel.sum()
    weights = np.outer(kernel, kernel)

    def windows(values: np.ndarray) -> np.ndarray:
        # NumPy symmetric, unlike NumPy reflect, repeats the boundary sample.
        padded = np.pad(values, radius, mode="symmetric")
        return np.lib.stride_tricks.sliding_window_view(padded, (size, size))

    a, b = windows(first), windows(second)
    ux = np.sum(a * weights, axis=(-2, -1))
    uy = np.sum(b * weights, axis=(-2, -1))
    dx, dy = a - ux[..., None, None], b - uy[..., None, None]
    vx = np.sum(weights * dx * dx, axis=(-2, -1))
    vy = np.sum(weights * dy * dy, axis=(-2, -1))
    covariance = np.sum(weights * dx * dy, axis=(-2, -1))
    deviation_product = np.sqrt(vx * vy)
    l = (2 * ux * uy + C1) / (ux * ux + uy * uy + C1)
    c = (2 * deviation_product + C2) / (vx + vy + C2)
    s = (covariance + C2 / 2) / (deviation_product + C2 / 2)
    return {"luminance": l, "contrast": c, "structure": s, "map": l * c * s}


def fixture_inputs() -> list[dict]:
    fixtures = []

    def add(name, first, second, size=11, sigma=1.5, default=False):
        fixtures.append(
            dict(name=name, first=first, second=second, window_size=size, sigma=sigma,
                 use_default_options=default)
        )

    first, second = texture(13, 12), texture(13, 12, phase=1)
    add("default_texture", first, second, default=True)
    add("sigma_narrow", first, second, sigma=0.65)
    add("sigma_wide", first, second, sigma=2.4)
    add("window_five", texture(9, 8), texture(9, 8, phase=2), size=5, sigma=1.1)
    add("window_one", texture(4, 3), texture(4, 3, phase=1), size=1, sigma=0.8)
    add("minimum_extent", texture(11, 11), texture(11, 11, phase=2))
    add("alpha_texture", texture(13, 12, alpha=True), texture(13, 12, phase=2, alpha=True))

    checker = gray(12, 13, 0)
    y, x = np.indices((13, 12))
    checker[..., :3] = (((x + y) % 2) * 255)[..., None]
    inverse = checker.copy()
    inverse[..., :3] = 255 - inverse[..., :3]
    add("anticorrelated_checkerboard", checker, inverse)

    boundary = first.copy()
    for y, x in [(0, 0), (0, 6), (4, 0), (11, 12), (11, 5), (6, 12)]:
        boundary[y, x] = [255, 0, 17, 255]
    add("boundary_impulses", first, boundary)
    add("constant_different", gray(11, 11, 64), gray(11, 11, 128))
    add("constant_against_texture", gray(13, 12, 96), first)
    transparent_a, transparent_b = texture(11, 11), texture(11, 11, phase=2)
    transparent_a[..., 3] = 0
    transparent_b[..., 3] = 0
    add("transparent_hidden_rgb", transparent_a, transparent_b)
    return fixtures


def make_fixture(spec: dict) -> dict:
    first_rgba, second_rgba = spec["first"], spec["second"]
    assert first_rgba.shape == second_rgba.shape
    assert np.all((first_rgba >= 0) & (first_rgba <= 255))
    assert np.all((second_rgba >= 0) & (second_rgba <= 255))
    height, width, _ = first_rgba.shape
    size, sigma = spec["window_size"], spec["sigma"]
    first, second = luminance(first_rgba), luminance(second_rgba)
    values = scipy_ssim(first, second, size, sigma)
    central = central_moments(first, second, size, sigma)
    np.testing.assert_allclose(values, central["map"], rtol=0, atol=SSIM_TOLERANCE)
    score = float(interior(values, size // 2).mean(dtype=np.float64))
    skimage_checked = size == 2 * int(3.5 * sigma + 0.5) + 1
    skimage_error = None
    if skimage_checked:
        skimage_score, skimage_map = structural_similarity(
            first, second, gaussian_weights=True, sigma=sigma,
            use_sample_covariance=False, data_range=255, full=True,
        )
        np.testing.assert_allclose(values, skimage_map, rtol=0, atol=SSIM_TOLERANCE)
        np.testing.assert_allclose(score, skimage_score, rtol=0, atol=SSIM_TOLERANCE)
        skimage_error = {
            "score_absolute_error": float(abs(score - skimage_score)),
            "map_max_absolute_error": float(np.max(np.abs(values - skimage_map))),
        }
    components = {
        key: float(interior(central[key], size // 2).mean(dtype=np.float64))
        for key in ("luminance", "contrast", "structure")
    }
    if spec["name"] == "anticorrelated_checkerboard":
        assert score < 0
    if spec["name"] == "transparent_hidden_rgb":
        np.testing.assert_allclose(values, 1.0, rtol=0, atol=SSIM_TOLERANCE)
    return {
        "name": spec["name"], "width": width, "height": height,
        "options": {"window_size": size, "sigma": sigma},
        "use_default_options": spec["use_default_options"],
        "check_components": True,
        "skimage_cross_checked": skimage_checked,
        "skimage_cross_check_error": skimage_error,
        "first_rgba": first_rgba.ravel().tolist(),
        "second_rgba": second_rgba.ravel().tolist(),
        "expected": {"score": score, **components, "map": values.ravel().tolist()},
    }


def moon_float(value: float) -> str:
    text = format(value, ".17g")
    if "e" in text:
        mantissa, exponent = text.split("e")
        return (mantissa if "." in mantissa else mantissa + ".0") + "e" + exponent
    return text if "." in text else text + ".0"


def moon_array(values: list, floating: bool = False) -> str:
    items = [moon_float(value) if floating else str(value) for value in values]
    per_line = 4 if floating else 16
    return "[\n" + "\n".join(
        "    " + ", ".join(items[i : i + per_line]) + ","
        for i in range(0, len(items), per_line)
    ) + "\n  ]"


def moon_tests(fixtures: list[dict]) -> str:
    blocks = [
        "// Generated by tools/generate_ssim_reference.py; do not edit by hand.\n"
        "// SciPy float64 full maps; independent weighted-central-moment components.\n"
        "// Every boundary pixel is checked, not only the cropped score.\n\n"
        "///|\n"
        "fn ssim_reference_image(\n"
        "  width : Int,\n  height : Int,\n  rgba : Array[Int],\n"
        ") -> @pixelmatch.Image {\n"
        "  let image = @pixelmatch.Image::new(width, height)\n"
        "  for i in 0..<rgba.length() {\n    image.data[i] = rgba[i]\n  }\n"
        "  image\n}"
    ]
    for fixture in fixtures:
        width, height = fixture["width"], fixture["height"]
        size, sigma = fixture["options"].values()
        expected = fixture["expected"]
        lines = [f'///|\ntest "SSIM independent reference: {fixture["name"]}" {{']
        lines.append("  let first_rgba : Array[Int] = " + moon_array(fixture["first_rgba"]))
        lines.append("  let second_rgba : Array[Int] = " + moon_array(fixture["second_rgba"]))
        lines.append(f"  let first = ssim_reference_image({width}, {height}, first_rgba)")
        lines.append(f"  let second = ssim_reference_image({width}, {height}, second_rgba)")
        if fixture["use_default_options"]:
            lines.append("  let result = @pixelmatch.ssim(first, second)")
        else:
            lines.append(
                "  let result = @pixelmatch.ssim(first, second, options={ "
                f"window_size: {size}, sigma: {moon_float(sigma)} " + "})"
            )
        lines.extend([
            f"  assert_eq(result.map.width, {width})",
            f"  assert_eq(result.map.height, {height})",
            f"  assert_eq(result.options.window_size, {size})",
            f"  assert_eq(result.options.sigma, {moon_float(sigma)})",
            f"  let score_error = (result.score - ({moon_float(expected['score'])})).abs()",
            "  assert_true(score_error <= 1.0e-9)",
        ])
        for key in ("luminance", "contrast", "structure"):
            lines.append(
                f"  let {key}_error = (result.{key} - ({moon_float(expected[key])})).abs()"
            )
            if fixture["check_components"]:
                lines.append(
                    f"  assert_true({key}_error <= 1.0e-8)"
                )
        lines.append("  let component_error = luminance_error.max(contrast_error).max(structure_error)")
        lines.append("  let expected_map : Array[Double] = " + moon_array(expected["map"], True))
        lines.extend([
            "  assert_eq(result.map.values.length(), expected_map.length())",
            "  let mut map_error = 0.0",
            "  for i in 0..<expected_map.length() {",
            "    let error = (result.map.values[i] - expected_map[i]).abs()",
            "    assert_true(error <= 1.0e-9)",
            "    map_error = map_error.max(error)",
            "  }",
        ])
        if fixture["name"] == "anticorrelated_checkerboard":
            lines.append("  assert_true(result.score < 0.0)")
        checked = "true" if fixture["check_components"] else "false"
        lines.append(
            '  println("SSIM_REFERENCE ' + fixture["name"]
            + r' score_error=\{score_error} map_error=\{map_error}'
            + r' components_error=\{component_error} components_checked='
            + checked + '")'
        )
        lines.append("}")
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks) + "\n"


def fixture_summary(fixture: dict) -> dict:
    summary = {
        key: value for key, value in fixture.items()
        if key not in ("first_rgba", "second_rgba", "expected")
    }
    expected = fixture["expected"]
    values = np.asarray(expected["map"], dtype="<f8")
    summary["expected"] = {
        key: value for key, value in expected.items() if key != "map"
    }
    summary["expected"]["map"] = {
        "length": len(values),
        "sha256": hashlib.sha256(values.tobytes()).hexdigest(),
        "encoding": "little-endian float64, row-major; complete values in src/ssim_reference_test.mbt",
    }
    return summary


def outputs() -> dict[Path, str]:
    installed = {"numpy": np.__version__, "scipy": scipy.__version__,
                 "scikit-image": skimage.__version__}
    if installed != VERSIONS:
        raise RuntimeError(f"Fixture dependency versions must be {VERSIONS}; got {installed}")
    fixtures = [make_fixture(spec) for spec in fixture_inputs()]
    reference = {
        "schema_version": 1,
        "provenance": {
            "generator": "tools/generate_ssim_reference.py",
            "versions": installed,
            "input": "Deterministic RGBA8 arrays; row-major, no image decoding or RNG.",
            "preprocessing": "Y = 255 + (0.29889531*r + 0.58662247*g + 0.11448223*b - 255) * (a / 255); float64, no quantization.",
            "map": "scipy.ndimage.gaussian_filter; explicit radius=window_size//2; reflect; population covariance; K1=.01, K2=.03, data_range=255; signed values retained.",
            "components": "Direct 2D normalized Gaussian windows, NumPy symmetric padding, weighted central moments, C3=C2/2. All fixtures assert all three components, including constant inputs and one-pixel windows.",
            "aggregation": "Mean of map and components after cropping window_size//2 from every edge. Score is mean(l*c*s), not mean(l)*mean(c)*mean(s).",
            "cross_check": "skimage.metrics.structural_similarity(full=True, gaussian_weights=True, use_sample_covariance=False, data_range=255), only when its implicit truncate=3.5 radius matches the explicit window.",
            "sources": [
                "https://scikit-image.org/docs/0.26.x/api/skimage.metrics.html#skimage.metrics.structural_similarity",
                "https://docs.scipy.org/doc/scipy-1.17.0/reference/generated/scipy.ndimage.gaussian_filter.html",
                "https://ece.uwaterloo.ca/~z70wang/publications/ssim.pdf",
            ],
        },
        "absolute_tolerance": {"score_and_map": SSIM_TOLERANCE,
                               "nonconstant_components": COMPONENT_TOLERANCE},
        "fixtures": [fixture_summary(fixture) for fixture in fixtures],
    }
    return {
        JSON_PATH: json.dumps(reference, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        TEST_PATH: subprocess.run(
            ["moonfmt", "-"], input=moon_tests(fixtures), text=True,
            encoding="utf-8", stdout=subprocess.PIPE, check=True, timeout=60,
        ).stdout,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify committed outputs without writing")
    args = parser.parse_args()
    generated = outputs()
    for path, content in generated.items():
        if args.check:
            if path.read_text(encoding="utf-8") != content:
                raise AssertionError(f"Generated output differs: {path.relative_to(ROOT)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    fixtures = json.loads(generated[JSON_PATH])["fixtures"]
    pixels = sum(item["width"] * item["height"] for item in fixtures)
    cross_checks = sum(item["skimage_cross_checked"] for item in fixtures)
    action = "Verified" if args.check else "Generated"
    print(f"{action} {len(fixtures)} fixtures, {pixels} map pixels, {cross_checks} skimage cross-checks.")


if __name__ == "__main__":
    main()
