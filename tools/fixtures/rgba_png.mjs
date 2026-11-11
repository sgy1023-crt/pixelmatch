import { crc32, deflateSync } from "node:zlib";

function chunk(type, data) {
  const bytes = Buffer.alloc(data.length + 12);
  bytes.writeUInt32BE(data.length);
  bytes.write(type, 4, "ascii");
  data.copy(bytes, 8);
  bytes.writeUInt32BE(crc32(bytes.subarray(4, -4)), bytes.length - 4);
  return bytes;
}

export function rgba_png(width, height, rgb_at) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;

  const stride = 1 + width * 4;
  const rows = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    let offset = y * stride + 1; // The first byte selects the None filter.
    for (let x = 0; x < width; x++) {
      const rgb = rgb_at(x, y);
      rows[offset++] = (rgb >>> 16) & 255;
      rows[offset++] = (rgb >>> 8) & 255;
      rows[offset++] = rgb & 255;
      rows[offset++] = 255;
    }
  }

  return Buffer.concat([
    Buffer.from("89504e470d0a1a0a", "hex"),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}
