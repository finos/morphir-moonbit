///|
let digest : String = "6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6"

///|
test "a SHA-256 digest is 64 lowercase hexadecimal digits" {
  assert_eq(@worker.Sha256::parse(digest).to_string(), digest)
  for
    text in [
      "",
      "6ed5",
      digest + "0",
      digest.to_upper(),
      "g" + digest[1:].to_owned(),
    ] {
    guard (Ok(@worker.Sha256::parse(text)) catch { e => Err(e) })
      is Err(InvalidSha256(_)) else {
      fail("accepted digest \{text}")
    }
  }
}

///|
test "a SHA-256 digest can be computed from bytes" {
  assert_eq(
    @worker.Sha256::of(b"abc").to_string(),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "an artifact path must be absolute" {
  for
    text in [
      "/opt/morphir/extension", "C:\\morphir\\extension.exe", "c:/morphir/extension.exe",
      "\\\\server\\share\\extension.wasm",
    ] {
    assert_eq(@worker.ArtifactPath::parse(text).to_string(), text)
  }
  for
    text in ["", "extension.wasm", "./extension", "C:extension", "/opt/\u0000x"] {
    guard (Ok(@worker.ArtifactPath::parse(text)) catch { e => Err(e) })
      is Err(InvalidArtifactPath(_)) else {
      fail("accepted path \{text}")
    }
  }
}

///|
test "platforms and WASM ABIs have closed names" {
  for
    platform in [
      @worker.Platform::DarwinArm64,
      DarwinX64,
      LinuxArm64,
      LinuxX64,
      WindowsArm64,
      WindowsX64,
    ] {
    assert_eq(@worker.Platform::parse(platform.to_string()), platform)
  }
  assert_eq(@worker.Platform::LinuxX64.to_string(), "linux-x64")
  guard (Ok(@worker.Platform::parse("linux-x86_64")) catch { e => Err(e) })
    is Err(UnknownPlatform(_)) else {
    fail("accepted an unknown platform")
  }
  assert_eq(
    @worker.WasmAbi::parse("extism-kernel-v1"),
    @worker.WasmAbi::ExtismKernelV1,
  )
  assert_eq(@worker.WasmAbi::MorphirBytesV1.to_string(), "morphir-bytes-v1")
  guard (Ok(@worker.WasmAbi::parse("wasi-p1")) catch { e => Err(e) })
    is Err(UnknownWasmAbi(_)) else {
    fail("accepted an unknown ABI")
  }
}

///|
test "a worker specification names a verified artifact and one runtime" {
  let artifact = @worker.ArtifactRef::new(
    @worker.ArtifactPath::parse("/opt/morphir/elm"),
    @worker.Sha256::parse(digest),
  )
  let spec = @worker.WorkerSpec::new(
    artifact,
    Process(platform=LinuxX64, args=["serve", "", "--"]),
  )
  assert_eq(spec.artifact.sha256.to_string(), digest)
  guard spec.runtime is Process(platform~, args~) else { fail("not a process") }
  assert_eq(platform, LinuxX64)
  // Arguments are opaque: delimiters and empty values stay as recorded.
  assert_eq(args, ["serve", "", "--"])
  let wasm = @worker.WorkerSpec::new(artifact, Wasm(abi=None))
  assert_true(wasm.runtime is Wasm(abi=None))
}
