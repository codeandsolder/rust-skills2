import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';

const provider = fileURLToPath(new URL('.', import.meta.url));
const golden = JSON.parse(readFileSync(new URL('./tests/golden/source-tokens.json', import.meta.url), 'utf8'));

test('bundled Rust/WASI token scanner matches frozen independent source corpus', t => {
  assert.equal(golden.schema, 1);
  assert.equal(golden.cases.length, 213);
  const repo = mkdtempSync(path.join(tmpdir(), 'policy-token-goldens-'));
  t.after(() => rmSync(repo, {recursive: true, force: true}));
  const names = golden.cases.map((entry, i) => {
    const name = `${String(i).padStart(3, '0')}.rs`;
    writeFileSync(path.join(repo, name), entry.source, 'utf8');
    return '/workspace/' + name;
  });
  const result = spawnSync(process.execPath,
    [path.join(provider, 'run.mjs'), path.join(provider, 'module.json'), repo, 'scan'],
    {input: JSON.stringify(names), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024});
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stderr);
  const found = JSON.parse(result.stdout);
  assert.equal(found.length, golden.cases.length);
  for (let i = 0; i < found.length; i++) {
    assert.deepEqual(found[i], [names[i], golden.cases[i].attributes], golden.cases[i].id);
  }
});
