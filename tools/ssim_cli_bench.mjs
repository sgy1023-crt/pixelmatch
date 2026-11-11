import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { arch, cpus, platform, release, totalmem } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { rgba_png } from "./fixtures/rgba_png.mjs";

const cli = fileURLToPath(new URL("../_build/js/release/build/cmd/pixelmatch/pixelmatch.js", import.meta.url));
const build = fileURLToPath(new URL("../_build/ssim-cli-bench-", import.meta.url));
const directory = mkdtempSync(build);
const trials = 3;

// Capture the Node child process peak without changing the CLI's JSON output.
const preload = `import { writeSync } from "node:fs";
process.once("exit", () => writeSync(2, "peak_kib=" + process.resourceUsage().maxRSS + "\\n"));`;
const import_url = "data:text/javascript," + encodeURIComponent(preload);

function fixture(width, height, changed) {
  const sidebar = width * 0.16;
  const header = height * 0.10;
  const left = width * 0.24;
  const right = width * 0.64;
  const top = height * 0.22;
  const bottom = height * 0.34;
  return rgba_png(width, height, (x, y) => {
    if (y < header) return 0x172238;
    if (x < sidebar) return 0x25354a;
    if (x >= left && x < right && y >= top && y < bottom) {
      return changed ? 0x347d6d : 0x3466a1;
    }
    const shade = 225 + ((x >>> 5) + (y >>> 4)) % 12;
    return (shade << 16) | ((shade + 4) << 8) | (shade + 8);
  });
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function measure(width, height) {
  const dimensions = `${width}x${height}`;
  const inputs = [false, true].map((changed, index) => {
    const path = join(directory, `${dimensions}-input-${index + 1}.png`);
    const bytes = fixture(width, height, changed);
    writeFileSync(path, bytes);
    return { path, bytes: bytes.length, sha256: sha256(bytes) };
  });
  const runs = Array.from({ length: trials }, (_, index) => {
    const output = join(directory, `${dimensions}-map-${index + 1}.png`);
    const start = performance.now();
    const result = spawnSync(process.execPath, [
      "--import", import_url, cli, "ssim", ...inputs.map(input => input.path),
      "--output", output,
    ], { encoding: "utf8", timeout: 60_000 });
    const wall_ms = performance.now() - start;
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    const peak = /^peak_kib=([1-9]\d*)\r?\n$/.exec(result.stderr);
    assert.ok(peak, result.stderr);
    const scores = JSON.parse(result.stdout);
    for (const key of ["ssim", "raw_ssim", "luminance", "contrast", "structure"]) {
      assert.ok(Number.isFinite(scores[key]), `invalid score field ${key}`);
    }
    assert.ok(scores.ssim > 0 && scores.ssim < 1);
    const png = readFileSync(output);
    assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
    assert.equal(png.readUInt32BE(16), width);
    assert.equal(png.readUInt32BE(20), height);
    return { wall_ms, peak_rss_kib: Number(peak[1]), output_sha256: sha256(png), scores };
  });
  assert.equal(new Set(runs.map(run => run.output_sha256)).size, 1);
  assert.equal(new Set(runs.map(run => JSON.stringify(run.scores))).size, 1);
  return { width, height, inputs, runs };
}

console.log(JSON.stringify({
  platform: platform(),
  release: release(),
  arch: arch(),
  cpu: cpus()[0].model,
  memory_bytes: totalmem(),
  node: process.version,
  fixtures: [measure(1920, 1080), measure(3840, 2160)],
}, null, 2));
