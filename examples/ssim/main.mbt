///|
fn main {
  let before = @pixelmatch.Image::new(15, 15)
  let after = @pixelmatch.Image::new(15, 15)
  for y in 0..<15 {
    for x in 0..<15 {
      before.set_pixel(x, y, @pixelmatch.Color::rgb(100, 100, 100))
      after.set_pixel(x, y, @pixelmatch.Color::rgb(100, 100, 100))
    }
  }
  after.set_pixel(7, 7, @pixelmatch.Color::rgb(220, 180, 100))
  let result = @pixelmatch.ssim(before, after) catch {
    error => abort("SSIM failed: \{error}")
  }
  println("raw SSIM: \{result.score}")
  println("display score: \{result.display_score()}")
  println(
    "components: \{result.luminance}, \{result.contrast}, \{result.structure}",
  )
  println(
    "map: \{result.map.width}x\{result.map.height}, center=\{result.map.values[7 * 15 + 7]}",
  )
  println(
    "window: \{result.options.window_size}, sigma=\{result.options.sigma}",
  )
  let preview = result.map.to_image()
  println("preview center: \{preview.get_pixel(7, 7)}")
}
