import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdir, writeFile } from 'node:fs/promises';
import type { AddressInfo } from 'node:net';
import { fileURLToPath } from 'node:url';
import { chromium, type Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import { createWorkbenchServer } from './server.ts';

interface WorksheetReport {
  source: { id: string; revision: number; text: string };
  observations: { expression: string; preview: string; range: { start: number; end: number }; outcome: unknown }[];
  completion: { status: string; failure?: { code: string } };
  diagnostic: { stage: string; range: { start: number; end: number } | null } | null;
}

export async function worksheetWorkflow(page: Page) {
  await page.getByRole('button', { name: 'Worksheet', exact: true }).click();
  // Observe the real bridge callback without replacing the worker or its result.
  await page.evaluate(() => {
    const original = globalThis.morphirWorkbench.request;
    const receipts: unknown[] = [];
    Object.assign(globalThis, { worksheetTestReceipts: receipts });
    globalThis.morphirWorkbench.request = (request, receive) => original(request, raw => {
      const reply = JSON.parse(raw);
      if (request.operation === 'worksheet' && typeof reply.worksheetReport === 'string') receipts.push(JSON.parse(reply.worksheetReport));
      receive(raw);
    });
  });
  const source = page.getByRole('textbox', { name: 'Source editor' });
  const run = page.getByRole('button', { name: 'Run worksheet', exact: true });
  const report = () => page.evaluate(() => (globalThis as unknown as { worksheetTestReceipts: WorksheetReport[] }).worksheetTestReceipts.at(-1)!);
  await source.fill('; capture 😀\r\n"😀"\r\n(+ 40 2)\r\n-0.0');
  const captured = await page.locator('#source').evaluate(node => (node as CodeEditor).value);
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
  const first = await report();
  assert.equal(first.source.text, captured);
  assert.equal(first.observations.length, 3);
  for (const row of first.observations) assert.equal(first.source.text.slice(row.range.start, row.range.end), row.expression);
  assert.deepEqual(first.observations[0]!.outcome, { status: 'returned', value: { type: 'text', units: [55357, 56832] } });
  assert.deepEqual(first.observations[1]!.outcome, { status: 'returned', value: { type: 'int', value: '42' } });
  assert.equal(first.observations[2]!.preview, '-0.0');
  await page.getByRole('button', { name: 'Show expression in source', exact: true }).nth(1).click();
  await page.waitForFunction(() => {
    const view = document.querySelector<CodeEditor>('#source')?.view;
    return view && view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to) === '(+ 40 2)';
  });
  assert.equal(await page.locator('#source').evaluate(node => {
    const view = (node as CodeEditor).view!;
    return view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to);
  }), '(+ 40 2)');
  await page.locator('.worksheet-typed summary').nth(1).click();
  assert.match(await page.locator('.worksheet-typed[open]').innerText(), /"value": "42"/);
  await source.fill('; new revision\n' + captured);
  await page.locator('.worksheet-stale').waitFor();
  assert.equal(await page.getByRole('button', { name: 'Show expression in source', exact: true }).nth(1).isDisabled(), true);
  assert.equal(await page.locator('#source').evaluate(node => (node as CodeEditor).dataset.marks), '');

  await source.fill('1\nmissing\n2');
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet stopped' }).waitFor();
  const failed = await report();
  assert.equal(failed.observations.length, 2);
  assert.equal(failed.completion.failure?.code, 'worksheet.evaluation_failed');
  assert.deepEqual(failed.diagnostic, { stage: 'evaluate', range: { start: 2, end: 9 } });
  assert.notEqual(await page.locator('#source').evaluate(node => (node as CodeEditor).dataset.marks), '');

  await source.fill('(let loop () (loop))');
  await run.click();
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Worksheet cancelled' }).waitFor();
  const cancelled = await report();
  assert.equal(cancelled.completion.status, 'cancelled');
  assert.deepEqual(cancelled.observations, []);
  assert.deepEqual(cancelled.diagnostic, { stage: 'transport', range: null });

  await source.fill('(let loop ((n 30) (x 1)) (if (= n 0) x (loop (- n 1) (vector x x))))');
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet stopped' }).waitFor();
  assert.equal((await report()).completion.failure?.code, 'worksheet.output_limit');
  await source.fill('(+ 2 2)');
  await run.click();
  await page.getByRole('status').filter({ hasText: 'Worksheet finished' }).waitFor();
  assert.deepEqual(await page.locator('.worksheet-result .value').allTextContents(), ['4']);
  return page.evaluate(() => (globalThis as unknown as { worksheetTestReceipts: WorksheetReport[] }).worksheetTestReceipts);
}

if (import.meta.main) {
  const server = createWorkbenchServer();
  let browser;
  try {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}`);
    await page.getByRole('status').filter({ hasText: 'Browser local' }).waitFor();
    const receipts = await worksheetWorkflow(page);
    assert.deepEqual(errors, []);
    const out = fileURLToPath(new URL('../../../.dev/campaign-completion/worksheet-browser/', import.meta.url));
    await mkdir(out, { recursive: true });
    await writeFile(`${out}/receipts.json`, JSON.stringify({ runtime: 'real Chromium / production worker', receipts }, null, 2));
    await page.screenshot({ path: `${out}/worksheet.png`, fullPage: true });
    console.log('Worksheet browser workflow passed.');
  } finally {
    await browser?.close();
    await new Promise<void>(resolve => server.close(() => resolve()));
  }
}
