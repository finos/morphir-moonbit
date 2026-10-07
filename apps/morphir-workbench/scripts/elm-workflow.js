import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { unzipSync, strFromU8 } from 'fflate';

// The same generated-file component and worker run in Chromium and packaged CEF.
export async function elmWorkflow(page, { nativeDownloads = true } = {}) {
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('button', { name: 'Compile & inspect', exact: true }).click();
  await page.getByRole('button', { name: 'Elm constant', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('select[aria-label="Target"]')?.value === 'elm');
  const target = page.getByRole('combobox', { name: 'Target', exact: true });
  assert.equal(await target.inputValue(), 'elm');
  const inputs = await page.getByRole('combobox', { name: 'Language', exact: true }).locator('option').evaluateAll(items => items.map(item => item.value));
  assert.ok(!inputs.includes('elm'), 'Elm generation does not advertise an Elm compiler');
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('42');
  await page.getByRole('button', { name: 'Compile & run (Scheme)', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  assert.equal(await page.locator('.run-value strong').textContent(), '42');
  await page.getByRole('button', { name: 'Elm constant', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('#source')?.value.includes('(define answer 42)'));
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  const ir = JSON.parse(await page.locator('#output').evaluate(editor => editor.value));
  assert.ok(ir.distribution);
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  const selector = page.getByRole('navigation', { name: 'Generated files', exact: true });
  await selector.waitFor();
  const paths = await selector.locator('.artifact-file').evaluateAll(items => items.map(item => item.getAttribute('aria-label')));
  assert.deepEqual(paths, ['src/User/Main.elm', 'elm.json', 'morphir.json']);
  const artifacts = {};
  for (const path of paths) {
    await selector.getByRole('button', { name: path, exact: true }).click();
    await page.waitForFunction(path => document.querySelector('#output')?.dataset.document === 'generated|' + path, path);
    artifacts[path] = await page.locator('#output').evaluate(editor => editor.value);
    assert.equal(await page.getByRole('textbox', { name: 'Generated output', exact: true }).getAttribute('aria-readonly'), 'true');
    assert.ok(await page.locator('#output .cm-line span').count() > 0, 'Elm and JSON files have highlighting');
  }
  assert.match(artifacts[paths[0]], /module User.Main/);
  assert.match(artifacts[paths[0]], /answer : Int/);
  assert.match(artifacts[paths[0]], /answer =\s+42/);
  assert.equal(JSON.parse(artifacts['elm.json']).type, 'package');
  assert.ok(JSON.parse(artifacts['morphir.json']).name);
  await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('#output')?.dataset.document === 'generated|src/User/Main.elm');
  async function download(button, expectedName) {
    if (nativeDownloads) {
      const pending = page.waitForEvent('download');
      await page.getByRole('button', { name: button, exact: true }).click();
      const download = await pending;
      assert.equal(download.suggestedFilename(), expectedName);
      return new Uint8Array(await readFile(await download.path()));
    }
    // CEF owns native download presentation. Verify the emitted bytes at its
    // application origin without depending on an OS save dialog.
    await page.evaluate(() => {
      window.artifactDownload = null;
      document.addEventListener('click', async function capture(event) {
        const link = event.target.closest('a[download]');
        if (!link) return;
        event.preventDefault();
        document.removeEventListener('click', capture, true);
        window.artifactDownload = { name: link.download, bytes: Array.from(new Uint8Array(await (await fetch(link.href)).arrayBuffer())) };
      }, true);
    });
    await page.getByRole('button', { name: button, exact: true }).click();
    await page.waitForFunction(() => window.artifactDownload !== null);
    const result = await page.evaluate(() => window.artifactDownload);
    assert.equal(result.name, expectedName);
    return new Uint8Array(result.bytes);
  }
  assert.equal(strFromU8(await download('Download file', 'Main.elm')), artifacts[paths[0]]);
  const archive = await download('Download project', 'morphir-project.zip');
  const unpacked = unzipSync(archive);
  assert.deepEqual(Object.keys(unpacked), paths);
  for (const path of paths) assert.equal(strFromU8(unpacked[path]), artifacts[path]);
  if (process.env.MORPHIR_WORKBENCH_ELM_PROJECT) {
    const directory = process.env.MORPHIR_WORKBENCH_ELM_PROJECT;
    await mkdir(directory, { recursive: true });
    await writeFile(join(directory, 'morphir-project.zip'), archive);
    for (const path of paths) {
      await mkdir(join(directory, path, '..'), { recursive: true });
      await writeFile(join(directory, path), unpacked[path]);
    }
  }
  await target.selectOption('scheme');
  assert.equal(await page.locator('#output').evaluate(editor => editor.value), artifacts[paths[0]], 'Target changes retain the previous generated files');
  await target.selectOption('elm');
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('9223372036854775808');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'elm.int_literal' }).waitFor();
  await page.getByText(/Elm generation failed: elm.int_literal at user:main#main/).first().waitFor();
  assert.equal(await selector.count(), 0);
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  assert.ok(JSON.parse(await page.locator('#output').evaluate(editor => editor.value)).distribution, 'Backend refusal retains the compiled model');
  await page.getByRole('button', { name: 'Elm constant', exact: true }).click();
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await selector.waitFor();
  assert.equal(await selector.locator('.artifact-file').count(), 3, 'Generation recovers after refusal');
  await selector.getByRole('button', { name: 'Collapse src/User/', exact: true }).click();
  await selector.getByRole('button', { name: 'Expand src/User/', exact: true }).waitFor();
  assert.equal(await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).isVisible(), false);
  await selector.getByRole('button', { name: 'Expand src/User/', exact: true }).focus();
  await page.keyboard.press('Enter');
  await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).waitFor();
  await selector.getByRole('button', { name: 'elm.json', exact: true }).focus();
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.querySelector('#output')?.dataset.document === 'generated|elm.json');
  assert.equal(await selector.getByRole('button', { name: 'elm.json', exact: true }).getAttribute('aria-pressed'), 'true');
  assert.equal(await page.locator('.artifact-breadcrumb').textContent(), 'elm.json');
  await page.getByRole('button', { name: 'Hide generated files', exact: true }).click();
  await page.getByRole('button', { name: 'Show generated files', exact: true }).waitFor();
  assert.equal(await selector.isVisible(), false);
  await page.getByRole('button', { name: 'Morphir IR', exact: true }).click();
  await page.getByRole('textbox', { name: 'Morphir IR', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Generated', exact: true }).click();
  await page.getByRole('button', { name: 'Show generated files', exact: true }).click();
  await selector.waitFor();
  assert.equal(await selector.getByRole('button', { name: 'elm.json', exact: true }).getAttribute('aria-pressed'), 'true', 'IR navigation retains the selected file');
  const wasCollapsed = await page.locator('.workbench').evaluate(element => element.classList.contains('collapsed'));
  const controlIcon = page.locator('.artifact-toolbar-title .artifact-icon');
  const iconTransform = await controlIcon.evaluate(element => getComputedStyle(element).transform);
  await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  await page.waitForFunction(previous => document.querySelector('.workbench').classList.contains('collapsed') !== previous, wasCollapsed);
  assert.equal(await controlIcon.evaluate(element => getComputedStyle(element).transform), iconTransform, 'Global sidebar changes do not reverse the generated-file control');
  assert.equal(await page.getByRole('button', { name: 'Hide generated files', exact: true }).getAttribute('aria-expanded'), 'true');
  await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  await page.waitForFunction(previous => document.querySelector('.workbench').classList.contains('collapsed') === previous, wasCollapsed);
  const source = await page.locator('#source').evaluate(editor => editor.value);
  await page.getByRole('button', { name: 'Expand generated files', exact: true }).click();
  await page.locator('.editor-grid.output-expanded').waitFor();
  assert.equal(await page.locator('.source-panel').isVisible(), false);
  assert.equal(await page.locator('#source').evaluate(editor => editor.value), source, 'Focus layout retains the mounted source editor');
  if (process.env.MORPHIR_WORKBENCH_OUTPUT_FOCUS_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_OUTPUT_FOCUS_SCREENSHOT, fullPage: true });
  await page.getByRole('button', { name: 'Restore split view', exact: true }).click();
  await page.locator('.source-panel').waitFor();
  assert.equal(await page.locator('#source').evaluate(editor => editor.value), source);
  await selector.getByRole('button', { name: 'src/User/Main.elm', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('#output')?.dataset.document === 'generated|src/User/Main.elm');
  if (process.env.MORPHIR_WORKBENCH_ELM_SCREENSHOT) await page.screenshot({ path: process.env.MORPHIR_WORKBENCH_ELM_SCREENSHOT, fullPage: true });
  const viewport = page.viewportSize();
  if (viewport) {
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Generated files fit mobile width');
    await page.getByRole('button', { name: 'Toggle sidebar' }).click();
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await selector.getByRole('button', { name: 'elm.json', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('#output')?.dataset.document === 'generated|elm.json');
    assert.equal(JSON.parse(await page.locator('#output').evaluate(editor => editor.value)).type, 'package');
    await page.setViewportSize(viewport);
  }
  console.log(JSON.stringify({ elmTarget: true, elmInput: false, files: paths, fileWorkspace: true, keyboardSelection: true, independentNavigation: true, focusRetainsSource: true, exactFileAndZipBytes: true, nativeDownloads, refusalRetainsIR: true, schemeEvaluation: true }));
}
