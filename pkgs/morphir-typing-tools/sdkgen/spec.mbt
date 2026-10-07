///|
let scm_path : String = "pkgs/morphir-sdk-spec/sdk.scm"

///|
let data_path : String = "pkgs/morphir-sdk-spec/sdk_data.mbt"

///|
let bindings_path : String = "pkgs/morphir-sdk/conformance/bindings.json"

///|
/// A failed generate or check run.
priv suberror ToolError {
  ToolError(String)
}
