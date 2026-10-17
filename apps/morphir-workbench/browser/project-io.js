// File and network access of the project editor. Replies are JSON text so the MoonBit side parses them at the
// boundary; nothing here throws.
export async function fetchText(path, receive) {
  try {
    const response = await fetch(path);
    if (!response.ok) {
      receive(JSON.stringify({ ok: false, message: `${path}: HTTP ${response.status}` }));
      return;
    }
    receive(JSON.stringify({ ok: true, text: await response.text() }));
  } catch (error) {
    receive(JSON.stringify({ ok: false, message: `${path}: ${error?.message ?? 'network error'}` }));
  }
}

export const LIMITS = { files: 2000, bytes: 16 * 1024 * 1024 };
const FILE_LIMIT = 1024 * 1024;
const TOOL_FOLDERS = new Set(['.git', 'node_modules', 'elm-stuff', '_build']);

function inToolFolder(path) {
  return path.split('/').slice(0, -1).some(segment => TOOL_FOLDERS.has(segment));
}

/**
 * Reads the text files of a folder selection. Returns `{ ok: true, files: [{path, content}], skipped }` or
 * `{ ok: false, message }`. Files over 1 MiB, files that are not UTF-8 text and files in tool folders are skipped
 * and counted. Nothing is read once a limit would be crossed.
 */
export async function readFiles(fileList, limits = LIMITS) {
  const entries = Array.from(fileList).map(file => ({ file, path: file.webkitRelativePath || file.name }));
  const candidates = entries.filter(entry => !inToolFolder(entry.path));
  let skipped = entries.length - candidates.length;
  if (candidates.length > limits.files) {
    return { ok: false, message: `Select a folder with at most ${limits.files.toLocaleString('en-US')} files.` };
  }
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const files = [];
  let total = 0;
  for (const { file, path } of candidates) {
    if (file.size > FILE_LIMIT) { skipped++; continue; }
    if (total + file.size > limits.bytes) {
      return { ok: false, message: `Select a folder with at most ${Math.round(limits.bytes / 1048576 * 100) / 100} MiB of text.` };
    }
    total += file.size;
    try {
      files.push({ path, content: decoder.decode(await file.arrayBuffer()) });
    } catch {
      skipped++;
    }
  }
  return { ok: true, files, skipped };
}

/** Opens the folder picker and reports the files as JSON text; a cancelled picker reports nothing. */
export function pickFolder(receive) {
  const input = document.createElement('input');
  input.type = 'file';
  input.webkitdirectory = true;
  input.addEventListener('change', async () => {
    if (!input.files || input.files.length === 0) return;
    receive(JSON.stringify(await readFiles(input.files, LIMITS)));
  });
  input.click();
}

async function readEntries(directory) {
  const reader = directory.createReader();
  const all = [];
  for (;;) {
    const batch = await new Promise((resolve, reject) => reader.readEntries(resolve, reject));
    if (batch.length === 0) return all;
    all.push(...batch);
  }
}

// A dropped folder as File-like objects with their relative paths; stops past the file limit.
async function walk(entry, out, limits) {
  if (out.length > limits.files) return;
  if (entry.isFile) {
    const file = await new Promise((resolve, reject) => entry.file(resolve, reject));
    out.push({
      name: file.name, webkitRelativePath: entry.fullPath.replace(/^\//, ''), size: file.size,
      arrayBuffer: () => file.arrayBuffer(),
    });
  } else if (entry.isDirectory && !TOOL_FOLDERS.has(entry.name)) {
    for (const child of await readEntries(entry)) await walk(child, out, limits);
  }
}

/**
 * Reads every dropped folder or file. All entries are taken from the items before the first await, because the
 * browser empties the items once the event handler yields.
 */
export async function readDropped(items, limits = LIMITS) {
  const entries = Array.from(items).map(item => item.webkitGetAsEntry?.()).filter(Boolean);
  const out = [];
  for (const entry of entries) await walk(entry, out, limits);
  return readFiles(out, limits);
}

/** Accepts a folder dropped on the element that matches `selector`, and reports it like `pickFolder`. */
export function watchDrop(selector, receive) {
  const target = event => event.target instanceof Element ? event.target.closest(selector) : null;
  document.addEventListener('dragover', event => {
    const zone = target(event);
    if (!zone) return;
    event.preventDefault();
    zone.classList.add('drop-active');
  });
  document.addEventListener('dragleave', event => target(event)?.classList.remove('drop-active'));
  document.addEventListener('drop', async event => {
    const zone = target(event);
    if (!zone) return;
    event.preventDefault();
    zone.classList.remove('drop-active');
    try {
      receive(JSON.stringify(await readDropped(event.dataTransfer?.items ?? [], LIMITS)));
    } catch (error) {
      receive(JSON.stringify({ ok: false, message: `The dropped folder could not be read: ${error?.message ?? 'error'}` }));
    }
  });
}

/** Browser storage as a per-browser convenience: every call returns `null` or `false` instead of throwing. */
export const storage = {
  load(key) {
    try { return globalThis.localStorage.getItem(key); } catch { return null; }
  },
  save(key, text) {
    try { globalThis.localStorage.setItem(key, text); return true; } catch { return false; }
  },
  remove(key) {
    try { globalThis.localStorage.removeItem(key); return true; } catch { return false; }
  },
};
