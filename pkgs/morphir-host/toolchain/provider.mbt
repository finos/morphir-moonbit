///|
/// A versioned request boundary for acquired or embedded host implementations.
/// Capabilities must describe the host's actual operations and targets.
pub(all) struct Provider {
  describe : () -> Json raise
  request : (Json) -> Json raise
}

///|
pub fn Host::provider(self : Host) -> Provider {
  {
    describe: fn() raise {
      self.request(object([("operation", Json::string("info"))]))
    },
    request: fn(request) raise { self.request(request) },
  }
}
