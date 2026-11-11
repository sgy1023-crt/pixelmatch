///|
fn read_png(path : String) -> @pixelmatch.Image {
  let bytes = try! @fs.read_file_to_bytes(path)
  let image = try! @image.decode_png(bytes)
  let data = FixedArray::makei(image.data.length(), i => image.data[i].to_int())
  { width: image.width, height: image.height, data, }
}

///|
fn write_png(path : String, image : @pixelmatch.Image) -> Unit {
  let rgba = FixedArray::makei(image.data.length(), i => image.data[i].to_byte())
  let bytes = try! @image.encode_png({
    width: image.width,
    height: image.height,
    data: Bytes::from_array(rgba),
  })
  try! @fs.write_bytes_to_file(path, bytes)
}

///|
fn compare(
  before_path : String,
  after_path : String,
  diff_path : String,
  ssim_path : String,
) -> Unit {
  let before = read_png(before_path)
  let after = read_png(after_path)
  let ssim = try! @pixelmatch.ssim(before, after)
  let diff = @pixelmatch.Image::new(before.width, before.height)
  let options = @pixelmatch.Options::default()
  let diff_count = @pixelmatch.pixelmatch(before, after, Some(diff), options)
  let strict_threshold = 0.02
  let strict_count = @pixelmatch.pixelmatch(before, after, None, {
    ..options,
    threshold: strict_threshold,
  })
  let map = ssim.map.to_image()
  let mut darkest_gray = 255
  for pixel in 0..<(map.width * map.height) {
    let gray = map.data[pixel * 4]
    darkest_gray = darkest_gray.min(gray)
  }
  write_png(diff_path, diff)
  write_png(ssim_path, map)
  let result : Json = {
    "width": Json(before.width),
    "height": Json(before.height),
    "threshold": Json(options.threshold),
    "diff_count": Json(diff_count),
    "strict_threshold": Json(strict_threshold),
    "strict_count": Json(strict_count),
    "ssim": Json(ssim.display_score()),
    "raw_ssim": Json(ssim.score),
    "darkest_gray": Json(darkest_gray),
  }
  println(result.stringify())
}

///|
fn main {
  let args = @env.args()
  match args[2:] {
    [before, after, diff, ssim] => compare(before, after, diff, ssim)
    _ => abort("Usage: before.png after.png pixel-diff.png ssim-map.png")
  }
}
