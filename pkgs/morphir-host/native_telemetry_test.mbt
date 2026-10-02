///|
test "native endpoint roots reject malformed authorities before optional export" {
  for
    endpoint in [
      "http://localhost", "http://127.0.0.1:4318", "https://metrics.example.com:443",
      "http://host:1", "http://host:65535", "https://xn--example-9d0b.test",
    ] {
    assert_true(@host.native_telemetry_endpoint(endpoint), msg=endpoint)
  }
  for
    endpoint in [
      "http://", "https://?token=x", "http://#fragment", "http://:4318", "http://host:",
      "http://host:0", "http://host:65536", "http://host:abc", "http://bad host",
      "http://user@host", "http://host/path", "http://host/", "http://host?query",
      "http://host#fragment", "http://999.1.2.3", "http://01.2.3.4", "http://[::1]:4318",
      "http://-host", "http://host..test", "ftp://host",
    ] {
    assert_false(@host.native_telemetry_endpoint(endpoint), msg=endpoint)
  }
}
