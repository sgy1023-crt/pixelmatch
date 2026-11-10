///|
let usage : String = "Usage: pixelmatch ssim before.png after.png --output ssim-map.png"

///|
suberror CliError {
  CliError(String)
}

///|
extern "js" fn report_error(message : String) -> Unit =
  #| (message) => {
  #|   console.error(message);
  #|   process.exitCode = 1;
  #| }

///|
fn read_png(path : String) -> @pixelmatch_core.Image raise CliError {
  let bytes = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) => raise CliError("cannot read '\{path}': \{message}")
  }
  let decoded = @image.decode_png(bytes) catch {
    err => raise CliError("cannot decode PNG '\{path}': \{err}")
  }
  let data = FixedArray::makei(decoded.data.length(), i => {
    decoded.data[i].to_int()
  })
  { width: decoded.width, height: decoded.height, data, }
}

///|
fn write_png(
  path : String,
  image : @pixelmatch_core.Image,
) -> Unit raise CliError {
  let rgba = FixedArray::makei(image.data.length(), i => image.data[i].to_byte())
  let encoded = @image.encode_png({
    width: image.width,
    height: image.height,
    data: Bytes::from_array(rgba),
  }) catch {
    err => raise CliError("cannot encode PNG '\{path}': \{err}")
  }
  write_atomic_output(path, encoded)
}

///|
fn run(args : ArrayView[String]) -> Unit raise CliError {
  match args {
    ["--help"] | ["ssim", "--help"] => println(usage)
    ["ssim", before, after, "--output", output] => {
      let first = read_png(before)
      let second = read_png(after)
      let result = @pixelmatch_core.ssim(first, second) catch {
        err =>
          raise CliError("cannot compare '\{before}' and '\{after}': \{err}")
      }
      write_png(output, result.map.to_image())
      let report : Json = {
        "ssim": Json(result.display_score()),
        "raw_ssim": Json(result.score),
        "luminance": Json(result.luminance),
        "contrast": Json(result.contrast),
        "structure": Json(result.structure),
      }
      println(report.stringify())
    }
    _ => raise CliError(usage)
  }
}

///|
fn main {
  let args = @env.args()
  // The Node.js backend returns the executable and script as the first two arguments.
  run(args[2:]) catch {
    CliError(message) => report_error(message)
  }
}
