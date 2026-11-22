// Differential source-token check: native Git/read, independent Zipp Python
// oracle, production Rust/WASI scanner. Never run native Python for this check.
import { spawnSync } from 'node:child_process';
import { readFileSync, realpathSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual, parseArgs } from 'node:util';
import { performance } from 'node:perf_hooks';

const checks = fileURLToPath(new URL('.', import.meta.url));
const provider = realpathSync(path.join(checks, '..'));
const {values, positionals} = parseArgs({
  options: {module: {type: 'string', multiple: true}, root: {type: 'string', multiple: true}},
  allowPositionals: true,
});
if (positionals.length !== 1 || !values.module?.length || !values.root?.length) {
  throw new Error('usage: node checks/compare_source_tokens.mjs ZIPP_RUNNER --module MODULE [--module MODULE...] --root ROOT [--root ROOT...]');
}
const [runner] = positionals;
const {runTask} = await import(pathToFileURL(realpathSync(runner)).href);
const spec = JSON.parse(readFileSync(path.join(checks, 'zipp-tasks.json'), 'utf8')).source_corpus;
const modules = values.module.map(module => path.resolve(module));
const decoder = new TextDecoder('utf-8', {fatal: true});

function command(bin, args, input) {
  const result = spawnSync(bin, args, {input, maxBuffer: 64 * 1024 * 1024});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(bin + ' failed: ' + result.stderr.toString());
  return result.stdout;
}

function* batches(root, names) {
  let batch = [], bytes = 2;
  // Keep VM instruction usage and input transfer bounded independently of
  // total repository size. A large single file is never split mid-token.
  const batchLimit = 128 * 1024;
  for (const name of names) {
    const source = decoder.decode(readFileSync(path.join(root, name))).replace(/\r\n?/g, '\n');
    const entry = ['/workspace/' + name, source];
    const size = Buffer.byteLength(JSON.stringify(entry)) + 1;
    if (batch.length && bytes + size > batchLimit) {
      yield batch;
      batch = [];
      bytes = 2;
    }
    batch.push(entry);
    bytes += size;
  }
  if (batch.length) yield batch;
}

let failed = false;
for (const argument of values.root) {
  const root = realpathSync(argument);
  const tracked = decoder.decode(command('git', ['-C', root, 'ls-files', '-z', '--', '*.rs']));
  const names = [...new Set(tracked.split('\0').filter(name => {
    if (!name) return false;
    try { return statSync(path.join(root, name)).isFile(); }
    catch (error) { if (error.code === 'ENOENT') return false; throw error; }
  }))].sort();
  let referenceTime = 0, fileCount = 0, attributeCount = 0, byteCount = 0;
  const results = modules.map(module => ({module, time: 0, mismatches: 0}));
  for (const batch of batches(root, names)) {
    const lines = [];
    const input = Buffer.from(JSON.stringify(batch));
    let start = performance.now();
    await runTask(provider, spec, ['corpus'], row => {
      if (row.stream === 'stderr') console.error(row.text);
      else lines.push(row.text);
    }, input);
    const expected = JSON.parse(lines.join('\n'));
    referenceTime += performance.now() - start;
    if (expected.length !== batch.length) throw new Error('incomplete reference scan');
    for (const [i, [, source]] of batch.entries()) {
      byteCount += Buffer.byteLength(source);
      attributeCount += expected[i][1].length;
      fileCount++;
    }
    const paths = Buffer.from(JSON.stringify(batch.map(([name]) => name)));
    for (const result of results) {
      start = performance.now();
      const actual = JSON.parse(command('node', [path.join(provider, 'policy-wasm/run.mjs'), result.module, root, 'scan'], paths));
      result.time += performance.now() - start;
      if (actual.length !== batch.length) throw new Error('incomplete WASI scan: ' + result.module);
      for (let i = 0; i < batch.length; i++) {
        if (!isDeepStrictEqual(expected[i], actual[i])) {
          if (result.mismatches < 5) console.error('expected:', JSON.stringify(expected[i]), '\nactual:', JSON.stringify(actual[i]));
          result.mismatches++;
        }
      }
    }
  }
  console.log(root + ': ' + fileCount + ' files, ' + byteCount + ' bytes, ' + attributeCount + ' attributes; Zipp ' + (referenceTime/1000).toFixed(3) + 's');
  for (const result of results) {
    console.log(result.module + ': WASI ' + (result.time/1000).toFixed(3) + 's; ' + result.mismatches + ' disagreements');
    failed ||= result.mismatches !== 0;
  }
}
process.exitCode = failed ? 1 : 0;
