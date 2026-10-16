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
