///|
fn ssim_solid(
  width : Int32,
  height : Int32,
  color : @pixelmatch.Color,
) -> @pixelmatch.Image {
  let image = @pixelmatch.Image::new(width, height)
  for y in 0..<height {
    for x in 0..<width {
      image.set_pixel(x, y, color)
    }
  }
  image
}

///|
fn ssim_close(actual : Double, expected : Double) -> Unit raise {
  assert_true((actual - expected).abs() < 1.0e-9)
}

///|
fn ssim_rejects(
  first : @pixelmatch.Image,
  second : @pixelmatch.Image,
  options~ : @pixelmatch.SsimOptions = @pixelmatch.SsimOptions::default(),
) -> Bool {
  try {
    ignore(@pixelmatch.ssim(first, second, options~))
    false
  } catch {
    _ => true
  }
}

///|
test "ssim identical constant images and white visualization" {
  let image = ssim_solid(13, 15, @pixelmatch.Color::rgb(128, 128, 128))
  let result = @pixelmatch.ssim(image, image)
  ssim_close(result.score, 1.0)
  ssim_close(result.luminance, 1.0)
  ssim_close(result.contrast, 1.0)
  ssim_close(result.structure, 1.0)
  assert_eq(result.map.width, 13)
  assert_eq(result.map.height, 15)
  assert_eq(result.map.values.length(), 195)
  for value in result.map.values {
    ssim_close(value, 1.0)
  }
  let image = result.map.to_image()
  assert_eq(image.get_pixel(0, 0), @pixelmatch.Color::rgb(255, 255, 255))
  ssim_close(result.display_score(), 1.0)
}

///|
test "ssim black versus white and pure brightness" {
  let black = ssim_solid(11, 11, @pixelmatch.Color::rgb(0, 0, 0))
  let white = ssim_solid(11, 11, @pixelmatch.Color::rgb(255, 255, 255))
  let result = @pixelmatch.ssim(black, white)
  // Existing Y coefficients sum to 1.00000001, not exactly 1.
  let white_y = 255.0 * 1.00000001
  ssim_close(result.score, 6.5025 / (white_y * white_y + 6.5025))
  ssim_close(result.contrast, 1.0)
  ssim_close(result.structure, 1.0)
  ssim_close(result.score, result.luminance)
}

///|
test "ssim map aggregation and input symmetry" {
  let first = ssim_solid(19, 17, @pixelmatch.Color::rgb(40, 80, 120))
  let second = ssim_solid(19, 17, @pixelmatch.Color::rgb(40, 80, 120))
  for y in 5..<10 {
    for x in 7..<13 {
      second.set_pixel(x, y, @pixelmatch.Color::rgb(220, 100, 60))
    }
  }
  let result = @pixelmatch.ssim(first, second)
  let reverse = @pixelmatch.ssim(second, first)
  let mut sum = 0.0
  for y in 5..<12 {
    for x in 5..<14 {
      sum += result.map.values[y * 19 + x]
    }
  }
  ssim_close(result.score, sum / 63.0)
  ssim_close(reverse.score, result.score)
  for i in 0..<result.map.values.length() {
    ssim_close(result.map.values[i], reverse.map.values[i])
  }
  assert_true(result.score < 1.0)
}

///|
test "ssim single pixel affects only nearby windows" {
  let first = ssim_solid(25, 25, @pixelmatch.Color::rgb(100, 100, 100))
  let second = ssim_solid(25, 25, @pixelmatch.Color::rgb(100, 100, 100))
  second.set_pixel(12, 12, @pixelmatch.Color::rgb(250, 0, 0))
  let result = @pixelmatch.ssim(first, second)
  ssim_close(result.map.values[0], 1.0)
  ssim_close(result.map.values[6 * 25 + 12], 1.0)
  assert_true(result.map.values[12 * 25 + 12] < 1.0)
}

///|
test "ssim negative anticorrelation stays raw" {
  let first = @pixelmatch.Image::new(15, 15)
  let second = @pixelmatch.Image::new(15, 15)
  for y in 0..<15 {
    for x in 0..<15 {
      let value = if (x + y) % 2 == 0 { 0 } else { 255 }
      first.set_pixel(x, y, @pixelmatch.Color::rgb(value, value, value))
      let inverse = 255 - value
      second.set_pixel(x, y, @pixelmatch.Color::rgb(inverse, inverse, inverse))
    }
  }
  let result = @pixelmatch.ssim(first, second)
  assert_true(result.score < -0.9)
  assert_true(result.structure < 0.0)
  assert_true(result.map.values[0] < 0.0)
  ssim_close(result.display_score(), 0.0)
  let visualization = result.map.to_image()
  assert_eq(visualization.get_pixel(0, 0), @pixelmatch.Color::rgb(0, 0, 0))
  assert_true(result.map.values[0] < 0.0)
}

///|
test "ssim alpha composites over white" {
  let hidden_red = ssim_solid(11, 11, @pixelmatch.Color::rgba(255, 0, 0, 0))
  let hidden_blue = ssim_solid(11, 11, @pixelmatch.Color::rgba(0, 0, 255, 0))
  ssim_close(@pixelmatch.ssim(hidden_red, hidden_blue).score, 1.0)
  let translucent = ssim_solid(11, 11, @pixelmatch.Color::rgba(0, 0, 0, 128))
  let solid = ssim_solid(11, 11, @pixelmatch.Color::rgb(127, 127, 127))
  ssim_close(@pixelmatch.ssim(translucent, solid).score, 1.0)
}

///|
test "ssim explicit default equals implicit default" {
  let first = ssim_solid(11, 11, @pixelmatch.Color::rgb(12, 34, 56))
  let second = ssim_solid(11, 11, @pixelmatch.Color::rgb(65, 43, 21))
  let implicit = @pixelmatch.ssim(first, second)
  let explicit = @pixelmatch.ssim(
    first,
    second,
    options=@pixelmatch.SsimOptions::default(),
  )
  assert_eq(implicit.score, explicit.score)
  for i in 0..<121 {
    assert_eq(implicit.map.values[i], explicit.map.values[i])
  }
}

///|
test "ssim one pixel image with one pixel window" {
  let first = ssim_solid(1, 1, @pixelmatch.Color::rgb(40, 40, 40))
  let second = ssim_solid(1, 1, @pixelmatch.Color::rgb(90, 90, 90))
  let result = @pixelmatch.ssim(first, second, options={
    window_size: 1,
    sigma: 1.5,
  })
  ssim_close(result.score, result.map.values[0])
  ssim_close(result.contrast, 1.0)
  ssim_close(result.structure, 1.0)
}

///|
test "ssim rejects empty unequal and malformed image dimensions" {
  let good = ssim_solid(11, 11, @pixelmatch.Color::rgb(0, 0, 0))
  assert_true(ssim_rejects(@pixelmatch.Image::new(0, 0), good))
  assert_true(ssim_rejects(@pixelmatch.Image::new(12, 11), good))
  let negative : @pixelmatch.Image = { width: -1, height: 11, data: [], }
  assert_true(ssim_rejects(negative, good))
  let malformed : @pixelmatch.Image = { width: 11, height: 11, data: [0], }
  assert_true(ssim_rejects(malformed, good))
  let overflow : @pixelmatch.Image = {
    width: 2147483647,
    height: 2147483647,
    data: [],
  }
  assert_true(ssim_rejects(overflow, good))
}

///|
test "ssim rejects invalid RGBA even at the last pixel" {
  let first = ssim_solid(11, 11, @pixelmatch.Color::rgb(0, 0, 0))
  let second = ssim_solid(11, 11, @pixelmatch.Color::rgb(0, 0, 0))
  first.data[483] = -1
  assert_true(ssim_rejects(first, second))
  first.data[483] = 256
  assert_true(ssim_rejects(first, second))
}

///|
test "ssim rejects invalid window and sigma" {
  let good = ssim_solid(11, 11, @pixelmatch.Color::rgb(0, 0, 0))
  for size in [-1, 0, 2, 12, 13, 2147483647] {
    assert_true(
      ssim_rejects(good, good, options={ window_size: size, sigma: 1.5, }),
    )
  }
  for sigma in [0.0, -1.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(ssim_rejects(good, good, options={ window_size: 11, sigma, }))
  }
  assert_true(
    ssim_rejects(@pixelmatch.Image::new(10, 13), @pixelmatch.Image::new(10, 13)),
  )
}

///|
test "ssim finite extreme positive sigma" {
  let image = ssim_solid(11, 11, @pixelmatch.Color::rgb(40, 50, 60))
  for sigma in [1.0e-300, 1.0e300] {
    ssim_close(
      @pixelmatch.ssim(image, image, options={ window_size: 11, sigma, }).score,
      1.0,
    )
  }
}

///|
test "ssim contrast change preserves structure" {
  let first = @pixelmatch.Image::new(15, 15)
  let second = @pixelmatch.Image::new(15, 15)
  for y in 0..<15 {
    for x in 0..<15 {
      let bright = (x + y) % 2 == 0
      let a = if bright { 192 } else { 64 }
      let b = if bright { 160 } else { 96 }
      first.set_pixel(x, y, @pixelmatch.Color::rgb(a, a, a))
      second.set_pixel(x, y, @pixelmatch.Color::rgb(b, b, b))
    }
  }
  let result = @pixelmatch.ssim(first, second)
  ssim_close(result.luminance, 1.0)
  ssim_close(result.structure, 1.0)
  assert_true(result.contrast < 0.9)
}

///|
test "ssim constant against texture has zero-variance structure" {
  let constant = ssim_solid(15, 15, @pixelmatch.Color::rgb(100, 100, 100))
  let texture = ssim_solid(15, 15, @pixelmatch.Color::rgb(100, 100, 100))
  texture.set_pixel(7, 7, @pixelmatch.Color::rgb(220, 180, 100))
  let result = @pixelmatch.ssim(constant, texture)
  assert_eq(result.structure, 1.0)
  assert_true(result.contrast < 1.0)
}
