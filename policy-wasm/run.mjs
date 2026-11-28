import { loadModule } from './module.mjs';
import { WASI } from 'node:wasi';

const [modulePath, root, mode] = process.argv.slice(2);
if (!modulePath || !root || !['scan', 'check'].includes(mode) || process.argv.length !== 5) {
  throw new Error('usage: node run.mjs MODULE.wasm|module.json WORKSPACE_ROOT scan|check < input.json');
}
const wasi = new WASI({
  version: 'preview1',
  args: ['source-policy', mode],
  preopens: { '/workspace': root },
  returnOnExit: true,
});
const module = await WebAssembly.compile(await loadModule(modulePath));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
process.exitCode = wasi.start(instance);
