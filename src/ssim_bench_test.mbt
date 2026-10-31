///|
fn ssim_benchmark_images(
  width : Int32,
  height : Int32,
) -> (@pixelmatch.Image, @pixelmatch.Image) {
  let first = @pixelmatch.Image::new(width, height)
  let second = @pixelmatch.Image::new(width, height)
  for y in 0..<height {
    for x in 0..<width {
      let value = (x * 13 + y * 7) % 256
      first.set_pixel(x, y, @pixelmatch.Color::rgb(value, value, value))
      let changed = if x >= width / 3 && x < width / 2 {
        (value + 10) % 256
      } else {
        value
      }
      second.set_pixel(x, y, @pixelmatch.Color::rgb(changed, changed, changed))
    }
  }
  (first, second)
}

///|
fn ssim_benchmark_run(
  first : @pixelmatch.Image,
  second : @pixelmatch.Image,
) -> @pixelmatch.SsimResult {
  @pixelmatch.ssim(first, second) catch {
    error => abort("SSIM benchmark failed: \{error}")
  }
}

///|
test "ssim 200x200 Gaussian 11" (b : @bench.T) {
  let (first, second) = ssim_benchmark_images(200, 200)
  b.bench(() => b.keep(ssim_benchmark_run(first, second)))
}

///|
test "ssim 1920x1080 Gaussian 11" (b : @bench.T) {
  let (first, second) = ssim_benchmark_images(1920, 1080)
  b.bench(() => b.keep(ssim_benchmark_run(first, second)))
}

///|
test "ssim 3840x2160 Gaussian 11" (b : @bench.T) {
  let (first, second) = ssim_benchmark_images(3840, 2160)
  b.bench(() => b.keep(ssim_benchmark_run(first, second)))
}
