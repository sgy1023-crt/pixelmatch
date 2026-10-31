///|
/// A normalized Gaussian window. Inputs are RGBA8, composited over white and
/// converted to the existing pixelmatch Y luminance. Covariance is population
/// covariance; the score excludes a border of window_size / 2 pixels.
pub(all) struct SsimOptions {
  window_size : Int32
  sigma : Double
} derive(Debug)

///|
pub extend SsimOptions with @debug.Debug::{to_repr}

///|
pub fn SsimOptions::default() -> SsimOptions {
  { window_size: 11, sigma: 1.5, }
}

///|
pub suberror SsimError {
  InvalidImage(String)
  InvalidOptions(String)
} derive(Debug)

///|
pub extend SsimError with @debug.Debug::{to_repr}

///|
pub extend SsimError with Show::{to_string, output}

///|
pub impl Show for SsimError with fn output(self, logger) {
  match self {
    InvalidImage(message) | InvalidOptions(message) =>
      logger.write_string(message)
  }
}

///|
/// Full-resolution, row-major raw SSIM. Negative values are retained.
/// Fields are readable; values must not be mutated when using the result score.
pub struct SsimMap {
  width : Int32
  height : Int32
  values : FixedArray[Double]
}

///|
/// Component fields are means over the same interior as score. Their product
/// need not equal score: score is the mean of the per-pixel products.
pub struct SsimResult {
  score : Double
  luminance : Double
  contrast : Double
  structure : Double
  map : SsimMap
  options : SsimOptions
}

///|
/// Clamp only for presentation; score and map retain the original signed SSIM.
pub fn SsimResult::display_score(self : SsimResult) -> Double {
  self.score.clamp(min=0.0, max=1.0)
}

///|
/// White is similar, black is dissimilar. Values <= 0 display as black.
/// This allocates an Image; it does not change the numeric map.
pub fn SsimMap::to_image(self : SsimMap) -> Image {
  let image = Image::new(self.width, self.height)
  for i in 0..<self.values.length() {
    let gray = (self.values[i].clamp(min=0.0, max=1.0) * 255.0).round().to_int()
    let base = i * 4
    image.data[base] = gray
    image.data[base + 1] = gray
    image.data[base + 2] = gray
    image.data[base + 3] = 255
  }
  image
}

///|
fn ssim_validate_image(image : Image) -> Unit raise SsimError {
  if image.width <= 0 || image.height <= 0 {
    raise InvalidImage("SSIM requires positive image dimensions")
  }
  let count = image.width.to_int64() * image.height.to_int64()
  if count > 536870911L || count * 4L != image.data.length().to_int64() {
    raise InvalidImage("SSIM requires width * height * 4 RGBA values")
  }
}

///|
fn ssim_kernel(options : SsimOptions) -> FixedArray[Double] {
  let radius = options.window_size / 2
  let kernel = FixedArray::make(options.window_size, 0.0)
  let mut total = 0.0
  for i in 0..<options.window_size {
    let distance = (i - radius).to_double() / options.sigma
    let weight = @math.exp(-0.5 * distance * distance)
    kernel[i] = weight
    total += weight
  }
  for i in 0..<options.window_size {
    kernel[i] = kernel[i] / total
  }
  kernel
}

///|
/// Half-sample symmetric extension (SciPy's reflect, not mirror).
/// The window fits the image, so at most one reflection is needed.
fn ssim_reflect(index : Int32, size : Int32) -> Int32 {
  if index < 0 {
    -index - 1
  } else if index >= size {
    size - 1 - (index - size)
  } else {
    index
  }
}

///|
priv struct SsimRows {
  width : Int32
  first_origin : Double
  second_origin : Double
  kernel : FixedArray[Double]
  moments : FixedArray[Double]
  first : FixedArray[Double]
  second : FixedArray[Double]
}

///|
fn ssim_read_row(
  image : Image,
  row : Int32,
  output : FixedArray[Double],
  origin : Double,
) -> Unit raise SsimError {
  for x in 0..<image.width {
    let base = (row * image.width + x) * 4
    output[x] = ssim_luminance(image.data, base) - origin
  }
}

///|
fn ssim_luminance(
  data : FixedArray[Int32],
  base : Int32,
) -> Double raise SsimError {
  for channel in 0..<4 {
    let value = data[base + channel]
    if value < 0 || value > 255 {
      raise InvalidImage("SSIM requires RGBA channel values in 0..255")
    }
  }
  let y = opaque_luminance(data[base], data[base + 1], data[base + 2])
  let alpha = data[base + 3].to_double() / 255.0
  255.0 + (y - 255.0) * alpha
}

///|
/// Store horizontally filtered E[X], E[Y], E[X²], E[Y²], E[XY] together.
/// Row buffers and ring slots are reused; no full-frame moment arrays exist.
fn SsimRows::fill(
  self : SsimRows,
  first : Image,
  second : Image,
  row : Int32,
  slot : Int32,
) -> Unit raise SsimError {
  ssim_read_row(first, row, self.first, self.first_origin)
  ssim_read_row(second, row, self.second, self.second_origin)
  let radius = self.kernel.length() / 2
  for x in 0..<self.width {
    let mut mx = 0.0
    let mut my = 0.0
    let mut xx = 0.0
    let mut yy = 0.0
    let mut xy = 0.0
    for j in 0..<self.kernel.length() {
      let source = ssim_reflect(x + j - radius, self.width)
      let a = self.first[source]
      let b = self.second[source]
      let weight = self.kernel[j]
      mx += weight * a
      my += weight * b
      xx += weight * a * a
      yy += weight * b * b
      xy += weight * a * b
    }
    let base = (slot * self.width + x) * 5
    self.moments[base] = mx
    self.moments[base + 1] = my
    self.moments[base + 2] = xx
    self.moments[base + 3] = yy
    self.moments[base + 4] = xy
  }
}

///|
/// Local Gaussian SSIM, with K1=0.01, K2=0.03 and data_range=255.
/// Rejects malformed RGBA8, unequal/empty images, invalid options and images
/// smaller than the window. The full map uses reflect boundaries; score and
/// component means use only windows wholly inside the input image.
pub fn ssim(
  first : Image,
  second : Image,
  options~ : SsimOptions = SsimOptions::default(),
) -> SsimResult raise SsimError {
  ssim_validate_image(first)
  ssim_validate_image(second)
  if first.width != second.width || first.height != second.height {
    raise InvalidImage("SSIM requires equal image dimensions")
  }
  let size = options.window_size
  if size <= 0 ||
    size % 2 == 0 ||
    options.sigma <= 0.0 ||
    options.sigma.is_nan() ||
    options.sigma.is_inf() {
    raise InvalidOptions(
      "SSIM requires a positive odd window and finite positive sigma",
    )
  }
  let width = first.width
  let height = first.height
  if size > width || size > height {
    raise InvalidOptions("SSIM window must fit both image dimensions")
  }
  let ring_length = width.to_int64() * size.to_int64() * 5L
  if ring_length > 2147483647L {
    raise InvalidOptions("SSIM row buffer exceeds array index capacity")
  }
  let kernel = ssim_kernel(options)
  let rows = SsimRows::{
    width,
    first_origin: ssim_luminance(first.data, 0),
    second_origin: ssim_luminance(second.data, 0),
    kernel,
    moments: FixedArray::make(ring_length.to_int(), 0.0),
    first: FixedArray::make(width, 0.0),
    second: FixedArray::make(width, 0.0),
  }
  let radius = size / 2
  for j in 0..<size {
    rows.fill(first, second, ssim_reflect(j - radius, height), j)
  }
  let values = FixedArray::make(width * height, 0.0)
  let c1 = 6.5025 // (0.01 * 255)^2
  let c2 = 58.5225 // (0.03 * 255)^2; C3 = C2 / 2
  let mut score = 0.0
  let mut luminance = 0.0
  let mut contrast = 0.0
  let mut structure = 0.0
  for y in 0..<height {
    for x in 0..<width {
      let mut mx = 0.0
      let mut my = 0.0
      let mut xx = 0.0
      let mut yy = 0.0
      let mut xy = 0.0
      for j in 0..<size {
        let base = ((y + j) % size * width + x) * 5
        let weight = kernel[j]
        mx += weight * rows.moments[base]
        my += weight * rows.moments[base + 1]
        xx += weight * rows.moments[base + 2]
        yy += weight * rows.moments[base + 3]
        xy += weight * rows.moments[base + 4]
      }
      // Positive weighted moments cannot have negative variance analytically.
      // Clamp roundoff only; covariance and the signed SSIM remain unclipped.
      let vx = (xx - mx * mx).max(0.0)
      let vy = (yy - my * my).max(0.0)
      let covariance = xy - mx * my
      // Translation makes constant inputs exactly zero before filtering and
      // leaves covariance invariant, avoiding cancellation in their moments.
      let mx = mx + rows.first_origin
      let my = my + rows.second_origin
      let deviation_product = (vx * vy).sqrt()
      let l = (2.0 * mx * my + c1) / (mx * mx + my * my + c1)
      let c = (2.0 * deviation_product + c2) / (vx + vy + c2)
      let s = (covariance + c2 / 2.0) / (deviation_product + c2 / 2.0)
      // Algebraically l*c*s, with less cancellation near zero variance.
      let value = l * (2.0 * covariance + c2) / (vx + vy + c2)
      values[y * width + x] = value
      if x >= radius && x < width - radius && y >= radius && y < height - radius {
        score += value
        luminance += l
        contrast += c
        structure += s
      }
    }
    if y + 1 < height {
      rows.fill(first, second, ssim_reflect(y + radius + 1, height), y % size)
    }
  }
  let count = ((width - 2 * radius) * (height - 2 * radius)).to_double()
  {
    score: score / count,
    luminance: luminance / count,
    contrast: contrast / count,
    structure: structure / count,
    map: { width, height, values, },
    options,
  }
}
