///|
/// Working directory under `moon test` is the module root, `apps/morphir-site`, so
/// "fixtures/content", "assets" and "_build/fixture-site" are relative to it.
async test "generate the fixture site" {
  let out = "_build/fixture-site"
  if @fs.exists(out) {
    @fs.rmdir(out, recursive=true)
  }
  let warnings = generate("fixtures/content", out, true)
  assert_eq(warnings, [])
  let files = list_files(out)
  assert_eq(files, [
    "assets/morphir-mark.svg", "assets/site.css", "blog/atom.xml", "blog/first/index.html",
    "blog/index.html", "docs/diagram/index.html", "docs/guide/index.html", "docs/index.html",
    "index.html", "search-index.json",
  ])
  let guide = @fs.read_file("\{out}/docs/guide/index.html").text()
  assert_true(guide.contains("<h2 id=\"install\">Install</h2>"))
  assert_true(guide.contains("class=\"language-moonbit\""))
  let readme = @fs.read_file("\{out}/docs/index.html").text()
  assert_true(readme.contains("href=\"/fixture/docs/guide/#install\""))
  let diagram = @fs.read_file("\{out}/docs/diagram/index.html").text()
  assert_true(diagram.contains("<figure class=\"diagram\"><svg"))
  let home = @fs.read_file("\{out}/index.html").text()
  assert_true(home.contains("href=\"/fixture/blog/first/\""))
}
