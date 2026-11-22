// Real Cargo metadata is collected natively. The independent resolver runs
// inside Zipp; the production Rust/WASI policy remains independent.
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const [runner, toolchain, ...modules] = process.argv.slice(2);
if (!runner || !/^nightly-\d{4}-\d{2}-\d{2}$/.test(toolchain ?? '') || !modules.length) {
  throw new Error('usage: node checks/compare_workspace_policy.mjs ZIPP_RUNNER NIGHTLY MODULE...');
}
const {runTask} = await import(pathToFileURL(realpathSync(runner)).href);
const spec = JSON.parse(readFileSync(path.join(root, 'checks/zipp-tasks.json'), 'utf8')).workspace_oracle;
const fixture = name => path.join(root, 'checks/fixtures', name);

function run(cwd, command, args) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  if (result.error) throw result.error;
  if (result.status === null) throw new Error(command + ' terminated: ' + result.signal);
  return result;
}

function cargo(cwd, ...args) {
  const result = run(cwd, 'cargo', ['+' + toolchain, ...args]);
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

const cases = [
  ['strict-ci-pass', false, []],
  ['strict-ci-pass', true, ['--workspace']],
  ['strict-ci-workspace-overrides', false, []],
  ['strict-ci-workspace-overrides', false, ['--workspace']],
  ['strict-ci-workspace-overrides', true, ['--workspace']],
  ['strict-ci-workspace-overrides', false, ['--package=legacy-member']],
  ['strict-ci-workspace-overrides', false, ['-p', 'strict-member@0.1.0']],
  ['strict-ci-workspace-overrides', false, ['--workspace', '--exclude', 'legacy-member']],
  ['strict-ci-workspace-overrides', false, ['-p', 'missing']],
  ['strict-ci-workspace-overrides', false, ['--workspace', '--exclude=missing']],
  ['strict-ci-workspace-default-panics', false, ['--workspace']],
  ['strict-ci-workspace-default-panics', true, ['--workspace']],
];

const metadata = new Map();
for (const [name] of cases) {
  if (!metadata.has(name)) metadata.set(name, cargo(fixture(name), 'metadata', '--no-deps', '--format-version', '1'));
}
const requests = cases.map(([name, defaultPolicy, selectors]) => ({
  metadata: metadata.get(name), default: defaultPolicy, selectors,
}));
const lines = [];
await runTask(root, spec, [], row => {
  if (row.stream === 'stderr') console.error(row.text);
  else lines.push(row.text);
}, Buffer.from(JSON.stringify(requests)));
const expected = JSON.parse(lines.join('\n'));
assert.equal(expected.length, cases.length);
assert.equal(expected.filter(row => row.status === 2).length, 2);

const name = 'strict-ci-workspace-overrides';
const selectors = ['--workspace', '-p', 'strict-member'];
const graph = cargo(fixture(name), 'check', ...selectors, '--locked', '--all-targets', '--unit-graph', '-Z', 'unstable-options');
const selected = new Set(graph.roots.map(index => graph.units[index].pkg_id));
const expectedGraph = metadata.get(name).packages.filter(pkg => selected.has(pkg.id))
  .map(pkg => pkg.name + '@' + pkg.version).sort();

function check(module, name, defaultPolicy, selectors) {
  const result = run(fixture(name), 'node', [
    path.join(root, 'policy-wasm/check.mjs'), path.resolve(module), toolchain,
    String(defaultPolicy), ...selectors,
  ]);
  return {status: result.status, rows: result.stdout.trimEnd().split(/\r?\n/).filter(Boolean), stderr: result.stderr};
}

for (const module of modules) {
  for (const [index, [name, defaultPolicy, selectors]] of cases.entries()) {
    const actual = check(module, name, defaultPolicy, selectors);
    assert.deepEqual({status: actual.status, rows: actual.rows}, expected[index],
      name + ' ' + selectors.join(' ') + ': ' + actual.stderr);
  }
  // Cargo --workspace overrides explicit package selection. The old
  // reference resolver narrows it incorrectly; check real Cargo instead.
  const actual = check(module, name, false, selectors);
  assert.equal(actual.status, 0, actual.stderr);
  assert.deepEqual(actual.rows.map(row => row.split('\t')[1]).sort(), expectedGraph);
  assert.deepEqual(actual.rows.sort(), ['relaxed\tlegacy-member@0.1.0', 'strict\tstrict-member@0.1.0']);
  console.log(module + ': ' + cases.length + ' Zipp differential cases and actual Cargo unit-graph parity passed');
}
