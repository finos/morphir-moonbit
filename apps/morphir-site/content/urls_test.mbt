///|
test "map href and src values" {
  let html = "<a href=\"a.md#x\">a</a> <img src=\"i.png\" alt=\"\"> <a class=\"c\" href=\"b&amp;c\">b</a>"
  let mapped = @content.map_urls(html, url => "[" + url + "]")
  assert_eq(
    mapped, "<a href=\"[a.md#x]\">a</a> <img src=\"[i.png]\" alt=\"\"> <a class=\"c\" href=\"[b&amp;c]\">b</a>",
  )
}

///|
test "escaped code is not a link" {
  let html = "<code>&lt;a href=&quot;x&quot;&gt;</code>"
  assert_eq(@content.map_urls(html, _ => "changed"), html)
}
