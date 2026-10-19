///|
/// The MCK transport envelope has a 3-MiB budget for hex model evidence. HTTP frames retain
/// their production 1-MiB validation path and the trace input has its own budget.
fn mck_json(source : String) -> Json {
  if source.length() > 3145728 || @utf8.encode(source).length() > 3145728 {
    return { "ok": false, "code": "workbench.mck_frame_limit" }
  }
  { "ok": true, "value": @wire.parse(source) } catch {
    _ => { "ok": false, "code": "workbench.invalid_json" }
  }
}

///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirWorkbenchMckJson = handler; }

///|
fn main {
  expose(source => mck_json(source).stringify())
}
