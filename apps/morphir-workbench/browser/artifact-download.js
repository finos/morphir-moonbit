import { strToU8, zipSync } from 'fflate';

// Keep original relative project paths; reject ambiguous or escaping paths.
export function artifactBytes(artifacts) {
  if (!Array.isArray(artifacts) || !artifacts.length) throw new Error('There are no generated files to download.');
  const files = Object.create(null);
  const names = new Set();
  for (const artifact of artifacts) {
    const { path, content, binary } = artifact ?? {};
    if (typeof path !== 'string' || !path || /[\\:\0]/.test(path) || path.startsWith('/') ||
        path.split('/').some(part => !part || part === '.' || part === '..')) {
      throw new Error('A generated file has an invalid project path.');
    }
    const folded = path.toLowerCase();
    if (names.has(folded) || [...names].some(name => name.startsWith(folded + '/') || folded.startsWith(name + '/'))) {
      throw new Error('Generated file paths conflict.');
    }
    if (typeof content !== 'string' || typeof binary !== 'boolean') throw new Error('A generated file has invalid content.');
    if (binary) throw new Error('This host does not declare an encoding for binary file downloads.');
    names.add(folded);
    files[path] = strToU8(content);
  }
  return files;
}

export function projectArchive(artifacts) {
  return zipSync(artifactBytes(artifacts), { level: 0, mtime: new Date(1980, 0, 1) });
}

export function downloadArtifacts(artifacts, project) {
  try {
    const files = artifactBytes(artifacts);
    const name = project ? 'morphir-project.zip' : Object.keys(files)[0].split('/').at(-1);
    const bytes = project ? projectArchive(artifacts) : Object.values(files)[0];
    const url = URL.createObjectURL(new Blob([bytes], { type: project ? 'application/zip' : 'application/octet-stream' }));
    const link = document.createElement('a');
    link.href = url; link.download = name; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    return '';
  } catch (error) { return error.message || 'Generated file download failed.'; }
}
