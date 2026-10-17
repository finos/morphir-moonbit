import type { Page } from 'playwright';
import type { CodeEditor } from '../browser/editor/code-editor.ts';
import assert from 'node:assert/strict';

// Real failures can be read in the tool panel: each failed job and each diagnostic opens its details (code, stage,
// location, message, job context), copies a plain-text report and shows the reply without source content.
export async function detailsWorkflow(page: Page) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(page.url()).origin });
  const tab = (name: string) => page.getByRole('tab', { name: new RegExp(`^${name}`) });
  const body = page.locator('#tool-panel-body');
  const clipboard = () => page.evaluate(() => navigator.clipboard.readText());
  const copy = async (scope: ReturnType<Page['locator']>) => {
    await page.evaluate(() => navigator.clipboard.writeText(''));
    await scope.getByRole('button', { name: 'Copy details', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Copied the details' }).waitFor();
    return clipboard();
  };

  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('button', { name: 'Compile & inspect', exact: true }).click();
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('elm');
  await page.locator('.file-name').getByText('src/Workbench/Main.elm', { exact: true }).waitFor();
  // A real Elm syntax error.
  await page.getByRole('textbox', { name: 'Source editor', exact: true }).fill('module Workbench.Main exposing (..)\n\nbroken =');
  await page.getByRole('button', { name: 'Compile', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('[role="status"]')?.textContent?.includes('elm.'));

  // Diagnostics: the row opens its code, severity, stage, location, message and job; the location opens the file.
  await tab('Diagnostics').click();
  const row = body.locator('.tool-report.current .tool-diagnostic').first();
  await row.waitFor();
  const code = (await row.locator('.tool-code').textContent())!;
  assert.match(code, /^elm\./, 'The engine code is shown as it is');
  const disclosure = row.locator(':scope > .tool-disclosure');
  assert.equal(await disclosure.getAttribute('aria-expanded'), 'false');
  await disclosure.focus();
  await page.keyboard.press('Enter');
  const details = row.locator('.tool-details');
  await details.waitFor();
  assert.equal(await disclosure.getAttribute('aria-expanded'), 'true', 'The disclosure says it is open');
  assert.equal(await disclosure.getAttribute('aria-controls'), await details.getAttribute('id'));
  const value = (label: string) => details.locator(`dt:text-is("${label}") + dd`);
  assert.equal(await value('Code').textContent(), code);
  assert.equal(await value('Severity').textContent(), 'Error');
  assert.equal(await value('Stage').textContent(), 'frontend');
  assert.match((await value('Location').textContent())!, /^src\/Workbench\/Main\.elm line 3, column \d+elm-source-position-v1 3:/);
  assert.match((await value('Language').textContent())!, /Elm/);
  const report = await copy(details);
  assert.match(report, /^Morphir Workbench diagnostic\nSeverity: Error\nCode: elm\./);
  assert.match(report, /Location: src\/Workbench\/Main\.elm line 3/);
  assert.match(report, /Reported by: Compile \(job \d+, source revision \d+\)/);
  await details.getByRole('button', { name: 'Raw reply', exact: true }).click();
  const raw = details.locator('.tool-raw');
  await raw.waitFor();
  assert.match((await raw.textContent())!, /"success": false/);
  assert.equal((await raw.textContent())!.includes('broken ='), false, 'The raw reply leaves out source content');
  await details.getByRole('button', { name: /^Open src\/Workbench\/Main\.elm/ }).click();
  await page.waitForFunction(() => (document.querySelector<CodeEditor>('#source')?.caretLine ?? 0) === 3);
  await disclosure.click();
  await details.waitFor({ state: 'detached' });
  assert.equal(await disclosure.getAttribute('aria-expanded'), 'false', 'The disclosure closes again');

  // Logs: the failed job opens its context and failure.
  await tab('Logs').click();
  const failedLog = body.locator('.tool-log').filter({ hasText: /Job \d+ failed in/ }).first();
  await failedLog.getByRole('button', { name: /^Details of Compile job \d+$/ }).click();
  const logDetails = failedLog.locator('.tool-details');
  await logDetails.waitFor();
  const logValue = (label: string) => logDetails.locator(`dt:text-is("${label}") + dd`);
  assert.equal(await logValue('Code').textContent(), code);
  assert.equal(await logValue('Project').textContent(), 'Workbench (1 file)');
  assert.match((await logValue('Duration').textContent())!, /^\d+ ms$/);
  const logReport = await copy(logDetails);
  assert.match(logReport, /^Morphir Workbench failure\nOperation: Compile \(job \d+\)\nCode: elm\./);
  assert.match(logReport, /Reply \(source content omitted\):/);

  // Output: the failed result opens the same details.
  await tab('Output').click();
  const outcome = body.locator('.tool-outcome').filter({ hasText: 'Compile failed' }).first();
  await outcome.getByRole('button', { name: /^Details of Compile job \d+$/ }).click();
  await outcome.locator('.tool-details dt:text-is("Code") + dd').filter({ hasText: code }).waitFor();

  // Details fit a phone-width window.
  const viewport = page.viewportSize();
  if (viewport) {
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'Open details fit a narrow window');
    await page.setViewportSize(viewport);
  }

  // A model that is not valid fails with a stable code and the codec's detail, never a bare key name.
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click();
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await (await chooser).setFiles({ name: 'empty.json', mimeType: 'application/json', buffer: Buffer.from('{}') });
  await page.getByRole('status').filter({ hasText: 'The model is not valid' }).waitFor();
  await tab('Logs').click();
  const importLog = body.locator('.tool-log').filter({ hasText: 'The model is not valid' }).first();
  await importLog.locator('.tool-extra .tool-disclosure').click();
  assert.equal(await importLog.locator('.tool-details dt:text-is("Code") + dd').textContent(), 'workbench.invalid_model');
  assert.equal(await importLog.locator('.tool-details dt:text-is("Stage") + dd').textContent(), 'model');

  // Leave a clean Elm project and a closed panel.
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click();
  await page.getByRole('button', { name: 'More actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Reset project…', exact: true }).click();
  await page.getByRole('button', { name: 'Confirm reset', exact: true }).click();
  if (await body.isVisible()) await page.getByRole('button', { name: 'Collapse panel', exact: true }).click();
  console.log(JSON.stringify({ diagnosticDetails: true, logDetails: true, outputDetails: true, copyDetails: true, rawReply: true, revealFromDetails: true, invalidModelCode: true }));
}
