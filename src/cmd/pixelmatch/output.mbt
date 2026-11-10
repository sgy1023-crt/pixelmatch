///|
extern "js" fn write_atomic_output_ffi(
  path : String,
  content : Bytes,
  on_error : (String) -> Unit,
) -> Unit =
  #| (path, content, onError) => {
  #|   const fs = process.getBuiltinModule("node:fs");
  #|   const { basename, dirname, isAbsolute, join, sep } = process.getBuiltinModule("node:path");
  #|   const { randomUUID } = process.getBuiltinModule("node:crypto");
  #|
  #|   function resolveOutput(requestedPath) {
  #|     const seen = new Set();
  #|     let target = requestedPath;
  #|     for (;;) {
  #|       const existing = fs.lstatSync(target, { throwIfNoEntry: false });
  #|       if (!existing?.isSymbolicLink()) return { target, existing };
  #|       const parent = fs.realpathSync(dirname(target));
  #|       const key = join(parent, basename(target));
  #|       if (seen.has(key)) throw new Error("symbolic link cycle at " + target);
  #|       seen.add(key);
  #|       const link = fs.readlinkSync(target);
  #|       target = isAbsolute(link) ? link : parent + sep + link;
  #|     }
  #|   }
  #|
  #|   let stagingPath;
  #|   try {
  #|     const { target, existing } = resolveOutput(path);
  #|     if (existing) {
  #|       if (!existing.isFile()) throw new Error("output must be a regular file");
  #|       fs.accessSync(target, fs.constants.W_OK);
  #|     }
  #|     const mode = existing ? existing.mode & 0o777 : 0o666;
  #|     const directory = fs.realpathSync(dirname(target));
  #|     const temporary = join(directory, ".pixelmatch-" + randomUUID() + ".tmp");
  #|     const descriptor = fs.openSync(temporary, "wx", mode);
  #|     stagingPath = temporary;
  #|     let writeFailure;
  #|     try {
  #|       if (existing && process.platform !== "win32") fs.fchmodSync(descriptor, mode);
  #|       fs.writeFileSync(descriptor, content, { flush: true });
  #|     } catch (error) {
  #|       writeFailure = error;
  #|     }
  #|     try {
  #|       fs.closeSync(descriptor);
  #|     } catch (error) {
  #|       if (!writeFailure) throw error;
  #|       throw new Error(writeFailure.message + "; close failed: " + error.message);
  #|     }
  #|     if (writeFailure) throw writeFailure;
  #|     fs.renameSync(stagingPath, target);
  #|   } catch (error) {
  #|     let message = error.message;
  #|     if (stagingPath !== undefined) {
  #|       try {
  #|         fs.unlinkSync(stagingPath);
  #|       } catch (cleanup) {
  #|         message += "; cannot remove temporary file " + stagingPath + ": " + cleanup.message;
  #|       }
  #|     }
  #|     onError(message);
  #|   }
  #| }

///|
fn write_atomic_output(path : String, content : Bytes) -> Unit raise CliError {
  let mut failure : String? = None
  write_atomic_output_ffi(path, content, message => failure = Some(message))
  if failure is Some(message) {
    raise CliError("cannot write '\{path}': \{message}")
  }
}
