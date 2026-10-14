// Rabbita prevents the default action of every `<a>` click that it renders and sends the URL to
// the app's router. The site islands and the workbench (served at /try/) have no router, so a link
// without `escape=true` does nothing when clicked. This test fails on such a link in their client
// MoonBit sources. The server-rendered views are not checked: Rabbita does not run on those pages.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

// The `@html.a(...)` calls in MoonBit source that do not pass `escape=true`, as line numbers.
export function unescapedLinks(source) {
  const lines = [];
  let at = source.indexOf('@html.a(');
  while (at >= 0) {
    let depth = 0;
    let end = at + '@html.a'.length;
    let quoted = false;
    for (; end < source.length; end++) {
      const c = source[end];
      if (quoted) {
        if (c === '\\') end++;
        else if (c === '"') quoted = false;
      } else if (c === '"') quoted = true;
      else if (c === '(') depth++;
      else if (c === ')' && --depth === 0) break;
    }
    if (!/\bescape\s*=\s*true\b/.test(source.slice(at, end))) {
      lines.push(source.slice(0, at).split('\n').length);
    }
    at = source.indexOf('@html.a(', end);
  }
  return lines;
}

function mbtFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const path = join(dir, e.name);
    if (e.isDirectory()) return e.name === '_build' ? [] : mbtFiles(path);
    return e.name.endsWith('.mbt') ? [path] : [];
  });
}

test('the scanner finds links without escape=true', () => {
  assert.deepEqual(unescapedLinks('@html.a(href="x", "A")\n@html.a(href="y", [text("(")], escape=true)'), [1]);
  assert.deepEqual(unescapedLinks('@html.a(\n  href="a)b",\n  escape=true,\n)'), []);
  assert.deepEqual(unescapedLinks('let x = 1\n\n@html.a(href=f(x), "B")'), [3]);
});

for (const [name, dir] of [['site island', '../islands'], ['workbench', '../../morphir-workbench/browser']]) {
  test(`${name} links skip Rabbita link capture`, () => {
    const root = fileURLToPath(new URL(dir, import.meta.url));
    const found = mbtFiles(root).flatMap((file) =>
      unescapedLinks(readFileSync(file, 'utf8')).map((line) => `${file}:${line}`));
    assert.deepEqual(found, [], `add escape=true to these @html.a calls: the ${name} has no router`);
  });
}
