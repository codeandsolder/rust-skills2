// Batch provider checks so the pinned engine is compiled once per stage.
import { readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const checks = fileURLToPath(new URL('.', import.meta.url));
const root = realpathSync(path.join(checks, '..'));
const manifest = JSON.parse(readFileSync(path.join(checks, 'zipp-tasks.json'), 'utf8'));
const [runner, stage] = process.argv.slice(2);
if (!runner || !['pre','analyze'].includes(stage) || process.argv.length !== 4) {
  throw new Error('usage: node checks/run_zipp.mjs RUNNER pre|analyze');
}
const {runTask} = await import(pathToFileURL(realpathSync(runner)).href);
const tasks = stage === 'pre' ? [
  ['metadata', []],
  ['evidence', []],
  ['generate', []],
] : [
  ['analyze', ['checks/check.json', '--source-dir', realpathSync(path.join(checks, 'examples')),
    '--check-baseline', 'checks/baseline.txt', '--good-exceptions', 'checks/good-exceptions.txt']],
];
for (const [name, args] of tasks) {
  console.log('==> Zipp ' + name);
  await runTask(root, manifest[name], args);
}
