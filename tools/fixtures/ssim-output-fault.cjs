const fs = require("node:fs");
const { syncBuiltinESMExports } = require("node:module");
const { resolve, sep } = require("node:path");

const directory = resolve(process.env.SSIM_TEST_OUTPUT_DIR);
const stage = process.env.SSIM_TEST_OUTPUT_FAULT;
const descriptors = new Set();
const open = fs.openSync;
const close = fs.closeSync;
const write = fs.writeFileSync;
const rename = fs.renameSync;

function in_test_directory(path) {
  return typeof path === "string" && resolve(path).startsWith(directory + sep);
}

function injected_failure() {
  throw Object.assign(new Error("injected " + stage + " failure"), { code: "EIO" });
}

fs.openSync = function (path, ...args) {
  const descriptor = open(path, ...args);
  if (in_test_directory(path)) {
    descriptors.add(descriptor);
  }
  return descriptor;
};

fs.closeSync = function (descriptor) {
  close(descriptor);
  descriptors.delete(descriptor);
};

fs.writeFileSync = function (file, bytes, ...args) {
  if (stage === "write" && (in_test_directory(file) || descriptors.has(file))) {
    // Simulate a device error after part of a real PNG has been written.
    write(file, Buffer.from(bytes).subarray(0, 8), ...args);
    injected_failure();
  }
  return write(file, bytes, ...args);
};

fs.renameSync = function (source, destination) {
  if (stage === "rename" && in_test_directory(destination)) {
    injected_failure();
  }
  return rename(source, destination);
};

syncBuiltinESMExports();
