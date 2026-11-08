# Local Gaussian SSIM

`ssim` adds a local perceptual metric to the existing pixel-level comparator.
The implementation is pure MoonBit in `src/ssim.mbt`; it reuses `Image` and
`opaque_luminance`. It does not change PNG codecs, native stubs, existing diff
APIs, or dependencies. There is no separate whole-image-statistics SSIM path.

## API

```moonbit
let result = @pixelmatch.ssim(before, after)
let custom = @pixelmatch.ssim(before, after, options={ window_size: 5, sigma: 1.1 })
let raw = result.score
let display = result.display_score()
let at_xy = result.map.values[y * result.map.width + x]
let preview : @pixelmatch.Image = result.map.to_image()
```

Calls raise `SsimError::InvalidImage(String)` or `InvalidOptions(String)`;
callers must propagate or catch errors. `SsimOptions::default()` is 11 / 1.5.
`SsimResult` exposes `score`, `luminance`, `contrast`, `structure`, `map`, and
the actual `options`. `SsimMap` exposes `width`, `height`, `values`.
The three component scores are interior means, not three additional full-frame
maps. Array values are mutable MoonBit storage: treat returned values as read-only
if comparing them with the already computed score.

The separate module under `examples/ssim` imports only the public package.
With the current toolchain, its `moon.work` resolves the checkout as a workspace
member, so it cannot accidentally exercise the published pre-SSIM release:

```sh
cd examples/ssim
moon run . --target js --deny-warn
moon run . --target wasm-gc --deny-warn
moon run . --target native --deny-warn
```

## Numerical contract

1. **Luminance:** `Y = .29889531*R + .58662247*G + .11448223*B`, exactly the
   existing pixelmatch helper. These coefficients sum to `1.00000001`; no
   renormalization, gamma linearization or intermediate integer rounding occurs.
2. **Alpha:** compare `255 + (Y-255)*(A/255)` over a fixed white background.
   Fully transparent hidden RGB does not affect the result. This is deliberately
   different from the checkerboard used by the pixel-delta code, and from
   `luminance_profile`, which ignores alpha. There is one scalar luminance channel,
   not an average of per-RGB-channel SSIM or an SSIM of the alpha channel.
3. **Kernel:** a positive odd explicit `window_size`, radius `r=size/2`;
   weights `exp(-.5*(offset/sigma)^2)`, normalized to unit sum in Double.
   A separable horizontal/vertical convolution gives the normalized 2D Gaussian.
   Sigma must be finite and positive; even very small/large positive values have
   explicit mathematical behavior (a point kernel / an almost uniform kernel).
4. **Edges:** half-sample symmetric `reflect`, repeating the boundary pixel:
   `d c b a | a b c d | d c b a`. The numeric map covers every input pixel.
5. **Small/invalid inputs:** both dimensions must be positive and at least the
   requested window size. A 1×1 image is supported with `window_size=1`.
   Equal dimensions, exact RGBA storage length, index capacity and every channel
   in integer `0..255` are checked. No automatic window shrinking or zero padding.
6. **Statistics/constants:** population weighted variance and covariance
   (`use_sample_covariance=False`). `C1=(.01*255)^2=6.5025`,
   `C2=(.03*255)^2=58.5225`, `C3=C2/2=29.26125`; all exponents are one.
   The kernel is applied to five moments. Each image's first luminance is
   subtracted before computing moments and restored for the luminance term;
   covariance is invariant to this translation. Constant images then have exact
   zero centered moments rather than suffering raw-moment cancellation.
7. **Roundoff:** `variance=max(E[X²]-E[X]²,0)` removes impossible negative
   variance. Covariance and raw SSIM are never clipped. Different summation order
   from SciPy can produce a few ulps of difference, including values just above 1.
8. **Components and raw/display values:**
   `l=(2*mx*my+C1)/(mx²+my²+C1)`,
   `c=(2*sqrt(vx*vy)+C2)/(vx+vy+C2)`,
   `s=(cov+C3)/(sqrt(vx*vy)+C3)`.
   Per-pixel SSIM is algebraically `l*c*s`, evaluated in the equivalent stable
   form `l*(2*cov+C2)/(vx+vy+C2)`. Anticorrelation may produce negative `s` and
   SSIM. `display_score()` clips only the aggregate for presentation;
   `to_image()` independently clips each map value to `[0,1]`, rounds to a
   grayscale byte and uses alpha 255. Neither mutates the original numeric map.
9. **Aggregation:** `score` is the arithmetic mean of map values for
   `r <= x < width-r`, `r <= y < height-r`. Each component uses the same interior.
   `mean(l*c*s)` generally differs from `mean(l)*mean(c)*mean(s)`. Edge map values
   are available to callers but excluded from these aggregates.

## Independent reference

For the default 11×11 window, preprocess RGBA with the contract above, then use:

```python
structural_similarity(y1, y2, gaussian_weights=True, sigma=1.5,
                      data_range=255, use_sample_covariance=False,
                      channel_axis=None, full=True)
```

scikit-image 0.26.0 uses `truncate=3.5`, reflect filtering, and crops radius 5
only for the mean. Its default sample covariance is **not** our covariance.
Passing raw RGB or RGBA with `channel_axis` does not implement our preprocessing.
Its explicit `win_size` does not set the Gaussian support: for custom windows
our oracle uses `scipy.ndimage.gaussian_filter(..., radius=size//2,
mode='reflect')`, then the standard SSIM equation and our crop.

`tools/generate_ssim_reference.py` fixes NumPy 2.2.4 / SciPy 1.17.0 /
scikit-image 0.26.0 and uses the MoonBit 2026-10-28 formatter. It generates 12
black-box fixtures with all 1,539 full-map values, including borders. Eight
fixtures also match skimage's implicit Gaussian support. Components are checked
independently with direct 2D weighted central moments, including constant inputs.
Absolute tolerances are `1e-9` for score/map and `1e-8` for components.
Ordinary `moon test` needs none of these Python packages.

```sh
python tools/generate_ssim_reference.py --check
python tools/validate_ssim.py
moon bench src/ssim_bench_test.mbt --target js --release --deny-warn
```

Reference metadata and checksums: `docs/ssim-reference.json`.
The algorithm is independently implemented from the mathematical definition;
no scikit-image/SciPy implementation code is copied. Existing Apache-2.0
repository licensing applies to the new sources and generated fixtures.
Sources: [Wang et al. (2004)](https://ece.uwaterloo.ca/~z70wang/publications/ssim.pdf),
[skimage API](https://scikit-image.org/docs/0.26.x/api/skimage.metrics.html#skimage.metrics.structural_similarity),
[SciPy Gaussian filter](https://docs.scipy.org/doc/scipy-1.17.0/reference/generated/scipy.ndimage.gaussian_filter.html).

## Memory and complexity

For `N=width*height`, `w=width`, `k=window_size`, typed numeric payload is:

- SSIM output: `8*N` bytes, one full-frame Double array.
- Working buffers: `8*(5*w*k + 2*w + k)` bytes, five-moment row ring, two
  reusable luminance rows and one kernel. Two scalar origins add 16 bytes.
- Existing two RGBA Int32 inputs: `32*N` bytes combined.
- Optional visualization: another `16*N` bytes for the existing `Image` format.

| Payload (MiB) | 1920×1080 | 3840×2160 |
| --- | ---: | ---: |
| Two inputs | 63.28 | 253.13 |
| Numeric map | 15.82 | 63.28 |
| Working buffers | 0.84 | 1.67 |
| Total before visualization | 79.94 | 318.08 |
| Additional visualization | 31.64 | 126.56 |

These are explainable storage estimates, **not measured process peak RSS**.
They exclude headers, allocator/GC behavior and backend runtime memory. JS
ordinary Int32 arrays can consume more than the four-byte-per-element model.
Runtime is `O(N*k)` for a fixed separable window, with `O(w*k)` working memory
plus the required `O(N)` output. Reflected halo rows are recomputed into reused
slots; no full-frame intermediates or per-pixel objects are allocated.
Measured timings and environment are recorded in `ssim-validation.md`.

## Issue #6 coverage and limits

| Requested capability | This change |
| --- | --- |
| Local 11×11 Gaussian SSIM | Implemented, explicit configurable support/sigma |
| Per-pixel numeric map and aggregate | Implemented, signed raw values retained |
| Luminance, contrast, structure | Implemented as interior aggregate component means |
| Score in 0..1 | Explicit `display_score()`; raw SSIM remains signed |
| SSIM map image | Implemented as grayscale existing `Image` |
| `pixelmatch ssim before.png after.png --output ...` | Implemented by the Node.js PNG CLI; see the README |
| Per-channel variant, MS-SSIM, component maps | Outside this luminance-only P0 |

The existing upstream comparator produces pixel differences and reports; this
adds local Gaussian statistics and a spatial floating-point similarity signal.
Compared with the global-statistics SSIM described in the prior Millow review,
the additional capability is local windows and a full spatial map. This is not
a claim to be MoonBit's first SSIM implementation. Maintainer review, merging,
publication and hackathon acceptance have not occurred.
