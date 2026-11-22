import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';

const [modulePath, root, mode] = process.argv.slice(2);
if (!modulePath || !root || !['scan', 'check'].includes(mode) || process.argv.length !== 5) {
  throw new Error('usage: node run.mjs MODULE.wasm WORKSPACE_ROOT scan|check < input.json');
}
const wasi = new WASI({
  version: 'preview1',
  args: ['source-policy', mode],
  preopens: { '/workspace': root },
  returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(modulePath));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
process.exitCode = wasi.start(instance);
