import './code-editor.js';
import { LocalAdapter, localCatalog, connect } from './transport.js';

const local = new LocalAdapter();
const requestedMode = new URLSearchParams(location.search).get('mode');
const connected = requestedMode === 'connected' || (!requestedMode && document.querySelector('meta[name="morphir-host-mode"]')?.content === 'connected');
let adapter = local;
let generation = 0;

globalThis.morphirWorkbench = {
  connected,
  async request(request, receive) {
    const current = ++generation;
    try {
      let result;
      if (request.operation === 'initialize') {
        if (connected) {
          adapter = await connect(location, local);
          result = await adapter.initialize();
        } else result = { success: true, operation: 'initialize', connected: false, catalog: localCatalog, projects: [], message: 'Browser local · ready to compile' };
      } else result = await adapter.execute(request);
      if (current === generation) receive(JSON.stringify(result));
    } catch (error) {
      if (request.operation === 'initialize' && connected) adapter.dispose?.();
      if (current === generation) receive(JSON.stringify({ success: false, message: error.message || 'Host request failed' }));
    }
  },
  cancel() { ++generation; adapter.cancel(); },
  importModel(receive) {
    const input = document.createElement('input');
    input.type = 'file'; input.accept = '.json,application/json';
    input.addEventListener('change', async () => {
      const file = input.files[0];
      if (!file) return;
      // The worker also enforces its input bound, so this guard is only an early hint.
      if (file.size > 16 * 1024 * 1024) { receive('{"oversizedImport":true}'); return; }
      try { receive(await file.text()); } catch { receive('{"unreadableImport":true}'); }
    });
    input.click();
  },
  download(text) {
    const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url; link.download = 'morphir-ir.json'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  },
};
window.addEventListener('pagehide', () => { ++generation; adapter.dispose?.(); local.cancel(); });
await import('./browser.js');
