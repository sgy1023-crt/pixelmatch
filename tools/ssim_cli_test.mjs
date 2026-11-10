import assert from "node:assert/strict";
import { execFile, spawnSync } from "node:child_process";
import {
  existsSync,
  chmodSync,
  lstatSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmdirSync,
  statSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const repo = new URL("../", import.meta.url);
const cli = fileURLToPath(new URL("_build/js/release/build/cmd/pixelmatch/pixelmatch.js", repo));
const before = fileURLToPath(new URL("examples/ssim-cli/before.png", repo));
const afterImage = fileURLToPath(new URL("examples/ssim-cli/after.png", repo));
const small = fileURLToPath(new URL("tools/fixtures/ssim-16x16.png", repo));
const expectedMap = fileURLToPath(new URL("examples/ssim-cli/expected-map.png", repo));
const outputFault = fileURLToPath(new URL("tools/fixtures/ssim-output-fault.cjs", repo));
const directory = mkdtempSync(join(tmpdir(), "pixelmatch ssim "));
const runChild = promisify(execFile);

after(() => {
  for (const name of readdirSync(directory)) {
    unlinkSync(join(directory, name));
  }
  rmdirSync(directory);
});

function cli_args(second, output) {
  return [cli, "ssim", before, second, "--output", output];
}

function compare(second, output, { nodeArgs = [], env = process.env } = {}) {
  const result = spawnSync(process.execPath, [...nodeArgs, ...cli_args(second, output)], {
    encoding: "utf8",
    timeout: 10_000,
    env,
  });
  assert.ifError(result.error);
  return result;
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
  return parse_scores(result.stdout, result.stderr);
}

function parse_scores(stdout, stderr) {
  assert.equal(stderr, "");
  const scores = JSON.parse(stdout);
  for (const key of ["ssim", "raw_ssim", "luminance", "contrast", "structure"]) {
    assert.ok(Number.isFinite(scores[key]), `invalid score field ${key}`);
  }
  return scores;
}

async function compare_in_parallel(jobs) {
  const results = await Promise.allSettled(jobs.map(async ({ second, output }) => {
    const { stdout, stderr } = await runChild(process.execPath, cli_args(second, output), {
      timeout: 10_000,
    });
    return parse_scores(stdout, stderr);
  }));
  const failures = results.filter(result => result.status === "rejected");
  if (failures.length > 0) {
    throw new AggregateError(failures.map(result => result.reason), "parallel CLI calls failed");
  }
  return results.map(result => result.value);
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

for (const stage of ["write", "rename"]) {
  test(stage + " failure preserves existing output and cleans staging files", () => {
    const output = join(directory, stage + " failure.png");
    const previous = readFileSync(before);
    writeFileSync(output, previous);
    const entries = readdirSync(directory).sort();
    const result = compare(afterImage, output, {
      nodeArgs: ["--require", outputFault],
      env: {
        ...process.env,
        SSIM_TEST_OUTPUT_DIR: directory,
        SSIM_TEST_OUTPUT_FAULT: stage,
      },
    });
    assert.equal(result.status, 1, result.stderr);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, new RegExp("injected " + stage + " failure"));
    assert.ok(readFileSync(output).equals(previous), "existing PNG was changed");
    assert.deepEqual(readdirSync(directory).sort(), entries);
  });
}

test("eight concurrent processes write independent outputs", async () => {
  const reference = readFileSync(expectedMap);
  const entries = readdirSync(directory);
  const jobs = Array.from({ length: 8 }, (_, i) => ({
    second: afterImage,
    output: join(directory, "parallel " + i + ".png"),
  }));
  const scores = await compare_in_parallel(jobs);
  for (const [i, { output }] of jobs.entries()) {
    assert.ok(scores[i].ssim < 1);
    assert.ok(read_map(output).equals(reference));
  }
  assert.deepEqual(readdirSync(directory).sort(),
    [...entries, ...jobs.map(job => basename(job.output))].sort());
});

test("eight concurrent processes sharing a path leave one complete PNG", async () => {
  const output = join(directory, "shared.png");
  const same = join(directory, "shared reference.png");
  read_scores(compare(before, same));
  const references = [read_map(same), readFileSync(expectedMap)];
  writeFileSync(output, references[0]);
  const entries = readdirSync(directory).sort();
  const jobs = Array.from({ length: 8 }, (_, i) => ({
    second: i % 2 === 0 ? before : afterImage,
    output,
  }));
  const scores = await compare_in_parallel(jobs);
  for (const [i, { second }] of jobs.entries()) {
    assert.equal(scores[i].ssim === 1, second === before);
  }
  const actual = read_map(output);
  assert.ok(references.some(reference => actual.equals(reference)));
  assert.deepEqual(readdirSync(directory).sort(), entries);
});

test("replacement follows a relative link and preserves the target mode", {
  skip: process.platform === "win32" && "POSIX symlink and mode regression",
}, () => {
  const target = join(directory, "linked target.png");
  const output = join(directory, "linked output.png");
  symlinkSync(basename(target), output);
  read_scores(compare(before, output));
  chmodSync(target, 0o600);
  read_scores(compare(afterImage, output));
  assert.ok(lstatSync(output).isSymbolicLink());
  assert.equal(statSync(target).mode & 0o777, 0o600);
  assert.ok(read_map(target).equals(readFileSync(expectedMap)));
});
