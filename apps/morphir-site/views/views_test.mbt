///|
let config : @model.SiteConfig = {
  title: "Morphir MoonBit",
  description: "Morphir in MoonBit",
  base_path: "/m/",
  site_url: "https://x.io/m/",
  repo_url: "https://github.com/finos/morphir-moonbit",
  packages: [],
}

///|
fn meta(
  route : String,
  title : String,
  section : @model.Section,
) -> @views.PageMeta {
  { config, route, title, description: "d", section, mermaid: false, }
}

///|
let post : @model.PostSummary = {
  route: "/blog/hello/",
  title: "Hello",
  date: "2026-10-13",
  authors: ["Ada", "Zoë"],
  summary: "First post.",
}

///|
async test "layout has head, islands, nav and main" {
  let m = meta("/docs/a/", "A", Docs)
  let out = @views.render(m, @views.raw("<p>hi</p>"))
  assert_true(
    out.has_prefix("<!DOCTYPE html><html data-base=\"/m/\" lang=\"en\">"),
  )
  assert_true(out.contains("<title>A · Morphir MoonBit</title>"))
  assert_true(
    out.contains("<link href=\"/m/assets/site.css\" rel=\"stylesheet\">"),
  )
  assert_true(
    out.contains(
      "<script src=\"/m/assets/islands.js\" type=\"module\"></script>",
    ),
  )
  assert_true(out.contains("href=\"/m/blog/atom.xml\""))
  assert_true(out.contains("<div id=\"site-search\">"))
  assert_true(out.contains("<div id=\"site-theme\"></div>"))
  assert_true(out.contains("<div id=\"site-nav\"></div>"))
  assert_true(out.contains("class=\"current\""))
  assert_true(
    out.contains(
      "<main id=\"content\"><div class=\"prose\"><p>hi</p></div></main>",
    ),
  )
  assert_false(out.contains("mermaid.min.js"))
}

///|
async test "mermaid pages load the client renderer" {
  let m = { ..meta("/docs/a/", "A", Docs), mermaid: true, }
  let out = @views.render(m, @views.raw(""))
  assert_true(
    out.contains("<script src=\"/m/assets/mermaid.min.js\"></script>"),
  )
}

///|
async test "docs page has sidebar with current page and source link" {
  let nav : Array[@model.NavItem] = [
    { route: "", title: "Adr", depth: 0, },
    { route: "/docs/adr/a/", title: "First", depth: 1, },
  ]
  let m = meta("/docs/adr/a/", "First", Docs)
  let out = @views.render(
    m,
    @views.docs_page(
      m,
      nav,
      "<h1 id=\"first\">First</h1>",
      Some("https://g/x.md"),
    ),
  )
  assert_true(out.contains("<span class=\"nav-label\">Adr</span>"))
  assert_true(
    out.contains(
      "<li class=\"depth-1\"><a aria-current=\"page\" href=\"/m/docs/adr/a/\"",
    ),
  )
  assert_true(out.contains("aria-current=\"page\""))
  assert_true(out.contains("href=\"https://g/x.md\""))
}

///|
async test "post page and blog index" {
  let m = meta("/blog/hello/", "Hello", Blog)
  let page = @views.render(m, @views.post_page(m, post, "<p>body</p>"))
  assert_true(page.contains("<h1>Hello</h1>"))
  assert_true(page.contains("<time datetime=\"2026-10-13\">2026-10-13</time>"))
  assert_true(page.contains("Ada, Zoë"))
  let index = @views.render(
    meta("/blog/", "Blog", Blog),
    @views.blog_index(meta("/blog/", "Blog", Blog), [post]),
  )
  assert_true(index.contains("href=\"/m/blog/hello/\""))
  assert_true(index.contains("First post."))
}

///|
async test "home page replaces the latest posts marker" {
  let m = meta("/", "Morphir MoonBit", Home)
  let landing = "<section class=\"hero\">h</section>" +
    @views.latest_posts_marker +
    "<section>after</section>"
  let out = @views.render(m, @views.home_page(m, landing, [post]))
  assert_true(out.contains("<title>Morphir MoonBit</title>"))
  assert_true(out.contains("<section class=\"hero\">h</section>"))
  assert_true(out.contains("href=\"/m/blog/hello/\""))
  assert_true(out.contains("<section>after</section>"))
  assert_false(out.contains("data-site=\"latest-posts\""))
}
