import { Decoration } from '@codemirror/view';

// Problem marks: `[{line, column, endLine, endColumn, message}]` with one-based lines and columns. Bad JSON or a
// mark outside the document gives no mark; an empty range covers one character.
export function position(doc, line, column) {
  const row = doc.line(Math.min(Math.max(Math.trunc(line), 1), doc.lines));
  return row.from + Math.min(Math.max(Math.trunc(column) - 1, 0), row.length);
}
export function markSet(doc, raw) {
  let list;
  try { list = raw ? JSON.parse(raw) : []; } catch { return Decoration.none; }
  if (!Array.isArray(list)) return Decoration.none;
  const ranges = [];
  for (const mark of list) {
    if (![mark?.line, mark?.column, mark?.endLine, mark?.endColumn].every(Number.isFinite)) continue;
    let from = position(doc, mark.line, mark.column);
    let to = position(doc, mark.endLine, mark.endColumn);
    if (to < from) [from, to] = [to, from];
    if (to === from) {
      if (to < doc.length && doc.lineAt(from).to > from) to = from + 1;
      else if (from > doc.lineAt(from).from) from -= 1;
      else continue;
    }
    ranges.push(Decoration.mark({ class: 'cm-morphir-problem', attributes: { title: String(mark.message ?? '') } }).range(from, to));
  }
  return Decoration.set(ranges, true);
}
