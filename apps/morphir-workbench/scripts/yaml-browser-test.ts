import assert from 'node:assert/strict';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';
import type { AddressInfo } from 'node:net';
import { chromium } from 'playwright';
import { createWorkbenchServer } from './server.ts';

const server = createWorkbenchServer();
let browser;
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ acceptDownloads: true });
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}`);
  await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  await page.evaluate(() => {
    const request = globalThis.morphirWorkbench.request;
    globalThis.morphirWorkbench.request = (input, receive) => request(input, raw => {
      const result = JSON.parse(raw);
      if (result.originalArtifact) Object.assign(globalThis, { yamlImportedName: result.originalArtifact.path });
      receive(raw);
    });
  });
  const source = Buffer.from('\ufeff# retained\r\nformatVersion: 4\r\ndistribution: {Library: {packageName: yaml-browser, dependencies: {}, def: {modules: {}}}}\r\n');
  for (const [name, format] of [['model.yaml', ''], ['model.yml', 'morphir-yaml'], ['unknown.txt', 'morphir-yaml']]) {
    await page.getByLabel('Model format', { exact: true }).selectOption(format!);
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: 'Import model', exact: true }).click();
    await (await chooser).setFiles({ name: name!, mimeType: 'application/yaml', buffer: source });
    await page.waitForFunction(name => (globalThis as unknown as { yamlImportedName: string }).yamlImportedName === name, name);
    await page.getByRole('button', { name: 'Original file', exact: true }).waitFor();
    const details = page.locator('details').filter({ has: page.getByText('Original YAML', { exact: true }) });
    if (await details.getAttribute('open') === null) await page.getByText('Original YAML', { exact: true }).click();
    assert.equal(await page.locator('#model-original').getAttribute('data-language'), 'yaml');
    assert.match(await page.locator('#model-original').evaluate(node => (node as HTMLElement & { value: string }).value), /# retained/);
    const download = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Original file', exact: true }).click();
    const saved = await download;
    assert.deepEqual(await readFile((await saved.path())!), source);
    assert.equal(saved.suggestedFilename(), name);
  }
  assert.deepEqual(errors, []);
  console.log('YAML browser file picker passed: .yaml/.yml, explicit format, local worker, YAML preview and byte-exact original download.');
} finally {
  await browser?.close();
  server.closeAllConnections();
  await new Promise<void>(resolve => server.close(() => resolve()));
}
