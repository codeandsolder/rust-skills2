// Verify production Rust/WASI against frozen decisions and real Cargo graph.
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const [toolchain, ...modules] = process.argv.slice(2);
if (!/^nightly-\d{4}-\d\d-\d\d$/.test(toolchain ?? '') || !modules.length) {
  throw Error('usage: node checks/compare_workspace_policy.mjs NIGHTLY MODULE...');
}
const golden = JSON.parse(readFileSync(
  path.join(root, 'policy-wasm/tests/golden/workspace-policy.json'), 'utf8'));
assert.equal(golden.schema, 1);
assert.equal(golden.historical, 12);
assert.equal(golden.cases.length, 21);

const fixture = name => path.join(root, 'checks/fixtures', name);
function run(cwd, command, args) {
  const result = spawnSync(command, args, {cwd, encoding:'utf8', maxBuffer:64*1024*1024});
  if (result.error) throw result.error;
  assert.notEqual(result.status, null, command + ': ' + result.signal);
  return result;
}
function cargo(cwd, ...args) {
  const result = run(cwd, 'cargo', ['+' + toolchain, ...args]);
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}
const packagesByFixture = new Map([
  ['strict-ci-pass', ['strict-ci-pass@0.0.0']],
  ['strict-ci-workspace-overrides', ['legacy-member@0.1.0','strict-member@0.1.0']],
  ['strict-ci-workspace-default-panics', ['legacy-member@0.1.0','strict-member@0.1.0']],
]);
const metadataByFixture = new Map();
for (const [name, expected] of packagesByFixture) {
  const metadata = cargo(fixture(name), 'metadata', '--no-deps', '--format-version', '1');
  const members = new Set(metadata.workspace_members);
  const names = metadata.packages.filter(pkg => members.has(pkg.id))
    .map(pkg => pkg.name + '@' + pkg.version).sort();
  assert.deepEqual(names, expected, name + ': fixture Cargo membership drift');
  metadataByFixture.set(name, metadata);
}
assert.deepEqual(
  [...new Set(golden.cases.map(item => item.fixture))].sort(),
  [...packagesByFixture.keys()].sort(),
  'expected fixture inventory drift'
);
function check(module, item) {
  const result = run(fixture(item.fixture), process.execPath, [
    path.join(root, 'policy-wasm/check.mjs'), path.resolve(module), toolchain,
    String(item.default), ...item.selectors,
  ]);
  return {
    status: result.status,
    rows: result.stdout.trimEnd().split(/\r?\n/).filter(Boolean),
    stderr: result.stderr,
  };
}
// Compare *every accepted selection* with Cargo's own unit graph, not just
// the --workspace / -p overlap. Cache duplicate selector combinations.
const graphSelections = new Map();
let checkedGraphs = 0;
for (const item of golden.cases) {
  if (item.status !== 0) continue;
  const key = item.fixture + '\0' + JSON.stringify(item.selectors);
  if (!graphSelections.has(key)) {
    const graph = cargo(fixture(item.fixture), 'check', ...item.selectors,
      '--all-targets', '--unit-graph', '-Z', 'unstable-options');
    const metadata = metadataByFixture.get(item.fixture);
    const byId = new Map(metadata.packages.map(pkg => [
      pkg.id, pkg.name + '@' + pkg.version,
    ]));
    const graphNames = [...new Set(graph.roots
      .map(index => byId.get(graph.units[index].pkg_id))
      .filter(Boolean))].sort();
    graphSelections.set(key, graphNames);
  }
  const expected = item.rows.map(row => row.split('\t')[1]).sort();
  assert.deepEqual(graphSelections.get(key), expected,
    item.fixture + ' ' + item.selectors.join(' ') + ': Cargo unit-graph mismatch');
  checkedGraphs++;
}
assert.equal(checkedGraphs, 15);
const overlap = golden.cases.find(item =>
  item.fixture === 'strict-ci-workspace-overrides' &&
  item.selectors.join(' ') === '--workspace -p strict-member');
assert.ok(overlap, 'missing frozen --workspace / -p precedence case');
assert.deepEqual(overlap.rows.map(row => row.split('\t')[1]).sort(),
  packagesByFixture.get('strict-ci-workspace-overrides'));

for(const module of modules) {
  for(const [i,item] of golden.cases.entries()) {
    const actual=check(module,item);
    assert.deepEqual({status:actual.status,rows:actual.rows},
      {status:item.status,rows:item.rows},
      'case '+(i+1)+' '+item.fixture+' default='+item.default+
        ' selectors='+item.selectors.join(' ')+'\n'+actual.stderr);
    if(item.status!==0) {
      assert.match(actual.stderr,/rust-skills2:/,
        'case '+(i+1)+': rejected policy must include explanatory diagnostic');
    }
  }
  console.log(module+': '+golden.cases.length+
    ' frozen workspace policy acceptances and real Cargo unit-graph parity passed');
}
