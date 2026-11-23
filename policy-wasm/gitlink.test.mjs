import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';

const provider = fileURLToPath(new URL('.', import.meta.url));
const rootModule = path.join(provider, 'module.json');
const policy = path.join(provider, 'check.mjs');
const checkout = path.dirname(provider);

function command(binary, args, cwd) {
  const result = spawnSync(binary, args, {cwd, encoding:'utf8'});
  if (result.error) throw result.error;
  return result;
}

test('registered Git submodules cannot contribute first-party lint source', t => {
  const root = mkdtempSync(path.join(tmpdir(), 'source-policy-gitlink-'));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  assert.equal(command('git',['init','-q',root],root).status,0);
  writeFileSync(path.join(root, 'Cargo.toml'), '[package]\nname = "gitlink-test"\nversion = "0.1.0"\nedition = "2024"\n');
  mkdirSync(path.join(root,'src'));
  writeFileSync(path.join(root,'src','lib.rs'), 'pub fn valid() {}\n');
  mkdirSync(path.join(root,'dependency'));
  writeFileSync(path.join(root,'dependency','foreign.rs'), '#[allow(dead_code)]\npub fn foreign() {}\n');
  const link=command('git',['update-index','--add','--cacheinfo',
    '160000,1111111111111111111111111111111111111111,dependency'],root);
  assert.equal(link.status,0,link.stderr);
  const pin = readFileSync(path.join(checkout, 'rust-toolchain.toml'), 'utf8');
  const toolchain = /^channel\s*=\s*"(nightly-\d{4}-\d\d-\d\d)"$/m.exec(pin)?.[1];
  assert.ok(toolchain, 'missing pinned nightly');
  const checked = command(process.execPath,[policy,rootModule,toolchain],root);
  assert.equal(checked.status,0,checked.stdout+'\n'+checked.stderr);
  assert.match(checked.stdout,/\(1 Rust files, 0 generated lint boundaries, 0 suppression attributes\)/);
});
