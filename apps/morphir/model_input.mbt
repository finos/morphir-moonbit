///|
/// Capture explicit filesystem inputs before decoding. Shared codecs own model
/// semantics; the host mount owns path confinement and refuses links/specials.
fn load_local_model(cli : Cli, limits : @data.Limits) -> @data.IRUnit raise {
  let path = value(cli, "path")
  let unit_id = value(cli, "unit-id", fallback="workbench")
  if path != "-" && @platform.kind(path) == 2 {
    let explicit = value(cli, "model-format")
    if explicit != "" && !(@data.ModelFormat::from_control(explicit) is YAML) {
      raise @config.Invalid("Model directory requires the YAML tree codec")
    }
    @data.decode_model_tree(capture_model_tree(path, limits), unit_id~, limits~)
  } else {
    let format = model_input_format(path, value(cli, "model-format"))
    @data.decode_model(
      format,
      @platform.read_input(path, limits.max_bytes),
      unit_id~,
      limits~,
    )
  }
}

///|
/// Every visited directory/file and total captured bytes have finite budgets,
/// including ignored sidecars. No file is read through an unbounded text API.
fn capture_model_tree(root : String, limits : @data.Limits) -> Map[String, Bytes] raise {
  let mount = @host.Mount::filesystem(root)
  let files : Map[String, Bytes] = Map([])
  let entries = Ref(0)
  let total = Ref(0)
  fn visit(path : String, depth : Int32) -> Unit raise {
    if depth > limits.max_depth {
      raise @config.Invalid("data.tree_limit: Model input directory depth")
    }
    let names = (mount.list)(path)
    if names.length() > limits.max_values - entries.val {
      raise @config.Invalid("data.tree_limit: Model input directory entries")
    }
    names.sort()
    for name in names {
      entries.val += 1
      let child = @workspace.join(path, name)
      if child != @workspace.normalize(child) ||
        name == "" || name == "." || name == ".." || name.contains("/") || name.contains("\\") {
        raise @config.Invalid("data.invalid_path: Model input directory entry")
      }
      match (mount.kind)(child) {
        1 => {
          let remaining = limits.max_bytes - total.val
          let bytes = @platform.read_input(root + "/" + child, remaining.max(1))
          if bytes.length() > remaining {
            raise @config.Invalid("data.byte_limit: Model input directory bytes")
          }
          total.val += bytes.length()
          files[child] = bytes
        }
        2 => visit(child, depth + 1)
        _ => raise @config.Invalid("data.invalid_path: Expected regular model input")
      }
    }
  }
  visit("", 0)
  files
}
