///|
extern "js" fn listen(callback : (String) -> String) =
  #| (callback) => { self.onmessage = (event) => { self.postMessage({ id: event.data.id, result: JSON.parse(callback(JSON.stringify(event.data.request))) }); }; }

///|
fn main {
  listen(request => {
    @pipeline.execute(@json.parse(request)).stringify() catch {
      _ => "{\"success\":false,\"message\":\"Invalid worker request\"}"
    }
  })
}
