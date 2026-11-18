///|
priv enum ReviewMode {
  Orders
  SlowClose
  Diagnostics
  InventoryWork
  InlineModule
  Scratch(String)
}

///|
fn review_mode(args : Array[String]) -> ReviewMode raise {
  match args[:] {
    [_] => Orders
    [_, "deadline"] => SlowClose
    [_, "diagnostics"] => Diagnostics
    [_, "inventory"] => InventoryWork
    [_, "module"] => InlineModule
    [_, "cleanup", root] => Scratch(root)
    _ => fail("unexpected bounded guest fixture mode")
  }
}

///|
async fn review_before_message(mode : ReviewMode, message : Json) -> Unit {
  guard message is Object({ "method": String(method_name), .. }) else { return }
  match mode {
    SlowClose if method_name == "morphir.shutdown" => @async.sleep(2200)
    Scratch(root) if method_name == @access.START => {
      let siblings = @fs.readdir(root, include_hidden=true)
      let mut injected = 0
      for name in siblings {
        if name.has_prefix(".morphir-bounded-") ||
          name.has_prefix(".morphir-source-") {
          let extra = root + "/" + name + "/extra"
          @fs.mkdir(extra)
          @fs.write_file(extra + "/probe.txt", "cleanup fixture")
          injected += 1
        }
      }
      guard injected == 2 else { fail("expected both private directories") }
    }
    _ => ()
  }
}

///|
fn review_support(mode : ReviewMode) -> @access.Support raise {
  let offer = orders_support().to_json()
  let limits = @wire.object(@wire.field(offer, "limits"))
  match mode {
    SlowClose => limits["maxSessionMilliseconds"] = Json::number(300)
    Diagnostics => limits["maxHostCacheBytes"] = Json::number(32768)
    InventoryWork => limits["maxSessionWorkUnits"] = Json::number(240)
    _ => ()
  }
  @access.Support::from_json(offer)
}

///|
fn review_inventory(
  round : Int32,
  selection : String,
  size : Int32,
) -> @access.ReadRequest {
  Inventory(
    request_id="review-\{round}",
    selection~,
    page_size=size,
    cursor=None,
  )
}

///|
fn review_diagnostics() -> Array[Json] {
  [
    {
      "severity": "info",
      "code": "fixture.retained",
      "message": "x".repeat(9000),
    },
  ]
}

///|
fn review_backend(mode : ReviewMode) -> @mep.BoundedBackend raise {
  @mep.BoundedBackend::new(review_support(mode), start => {
    let complete = () => {
      @access.GenerationStep::Complete(
        session_id=start.session_id,
        artifacts=[],
        diagnostics=[],
      )
    }
    let selection = Ref("")
    let first = match mode {
      SlowClose | Scratch(_) => complete()
      Diagnostics =>
        Continue(
          session_id=start.session_id,
          round=1,
          requests=[review_inventory(1, "root", 1)],
          artifacts=[],
          diagnostics=review_diagnostics(),
        )
      _ => orders_pending(start.session_id, 1, review_inventory(1, "root", 8))
    }
    let operation = @mep.BoundedOperation::new(
      advance=request => {
        let round = request.round + 1
        match mode {
          Diagnostics if round <= 6 =>
            Continue(
              session_id=start.session_id,
              round~,
              requests=[review_inventory(round, "root", 1)],
              artifacts=[],
              diagnostics=review_diagnostics(),
            )
          InventoryWork | InlineModule if request.round == 1 => {
            guard request.deliveries is [Inventory(page)] &&
              page.entries
              .iter()
              .find_first(entry => {
                entry is Module(identity, ..) &&
                identity.module_path == "domain"
              })
              is Some(Module(identity, member_selection=Some(member_selection))) else {
              abort("fixture expected the domain module in root inventory")
            }
            selection.val = member_selection
            let read : @access.ReadRequest = if mode is InlineModule {
              Document(
                request_id="review-module",
                document_id=identity.document_id,
              )
            } else {
              review_inventory(round, member_selection, 1)
            }
            orders_pending(start.session_id, round, read)
          }
          InventoryWork if round <= 7 =>
            orders_pending(
              start.session_id,
              round,
              review_inventory(round, selection.val, 1),
            )
          InlineModule => {
            guard request.deliveries is [Document(document)] &&
              document.document_id.has_suffix("/domain/module") else {
              abort("fixture expected the raw domain module")
            }
            complete()
          }
          _ => complete()
        }
      },
      release=() => (),
    )
    (first, operation)
  })
}
