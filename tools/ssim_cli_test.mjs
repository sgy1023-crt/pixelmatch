import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const repo = new URL("../", import.meta.url);
const cli = fileURLToPath(new URL("_build/js/release/build/cmd/pixelmatch/pixelmatch.js", repo));
const before = fileURLToPath(new URL("examples/ssim-cli/before.png", repo));
const afterImage = fileURLToPath(new URL("examples/ssim-cli/after.png", repo));
const small = fileURLToPath(new URL("tools/fixtures/ssim-16x16.png", repo));
const directory = mkdtempSync(join(tmpdir(), "pixelmatch ssim "));

after(() => {
  for (const name of readdirSync(directory)) {
    unlinkSync(join(directory, name));
  }
  rmdirSync(directory);
});

function invoke(...args) {
  const result = spawnSync(process.execPath, [cli, ...args], {
    encoding: "utf8",
    timeout: 10_000,
  });
  assert.ifError(result.error);
  return result;
}

function compare(second, output) {
  return invoke("ssim", before, second, "--output", output);
}

function read_map(path) {
  const png = readFileSync(path);
  assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  assert.equal(png.toString("ascii", 12, 16), "IHDR");
  assert.equal(png.readUInt32BE(16), 96);
  assert.equal(png.readUInt32BE(20), 64);
  return png;
}

function read_scores(result) {
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  const scores = JSON.parse(result.stdout);
  for (const key of ["ssim", "raw_ssim", "luminance", "contrast", "structure"]) {
    assert.ok(Number.isFinite(scores[key]), `invalid score field ${key}`);
  }
  return scores;
}

function assert_failure(result, message, output) {
  assert.equal(result.status, 1, result.stderr);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, message);
  assert.equal(existsSync(output), false);
}

test("same PNG scores one and produces a 96×64 map", () => {
  const output = join(directory, "same map.png");
  const scores = read_scores(compare(before, output));
  for (const value of Object.values(scores)) {
    assert.equal(value, 1);
  }
  read_map(output);
});

test("local change lowers the score and changes the map", () => {
  const output = join(directory, "changed map.png");
  const reference = join(directory, "reference map.png");
  read_scores(compare(before, reference));
  const scores = read_scores(compare(afterImage, output));
  assert.ok(scores.ssim > 0 && scores.ssim < 1);
  assert.equal(scores.ssim, scores.raw_ssim);
  assert.ok(scores.luminance < 1);
  assert.notDeepEqual(read_map(output), read_map(reference));
});

test("unequal PNG sizes report the comparison failure", () => {
  const output = join(directory, "mismatch.png");
  assert_failure(compare(small, output), /cannot compare.*ssim-16x16\.png/, output);
});

test("malformed PNG reports the input path", () => {
  const input = join(directory, "invalid.png");
  const output = join(directory, "malformed.png");
  writeFileSync(input, "this is not a PNG");
  assert_failure(compare(input, output), /cannot decode PNG.*invalid\.png/, output);
});

test("unwritable output reports the destination without printing JSON", () => {
  const output = join(directory, "missing directory", "output.png");
  assert_failure(compare(afterImage, output), /cannot write.*output\.png/, output);
});
