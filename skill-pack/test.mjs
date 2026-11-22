import assert from 'node:assert/strict';
import { test } from 'node:test';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pack, packagePaths } from './run.mjs';

const [module] = process.argv.slice(2);
if (!module || process.argv.length !== 3) throw new Error('usage: node skill-pack/test.mjs MODULE.wasm');
const binary = path.resolve(module);

function fixture(t) {
  const directory = mkdtempSync(path.join(tmpdir(), 'skill-pack-test-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const root = path.join(directory, 'checkout');
  const output = path.join(directory, 'output');
  mkdirSync(path.join(root, 'rules', 'nested'), {recursive: true});
  writeFileSync(path.join(root, 'SKILL.md'), '---\nname: test-skill\n---\nBody\n');
  writeFileSync(path.join(root, 'LICENSE'), 'test license\n');
  writeFileSync(path.join(root, 'rules', 'ordinary.md'), 'compress me\n'.repeat(1000));
  writeFileSync(path.join(root, 'rules', 'nested', '🦀.md'), 'UTF-8 fixture\n');
  writeFileSync(path.join(root, 'ignored.txt'), 'must not be included');
  return {root, output, directory};
}

test('deterministic compressed outputs, exact copies and no leftover staging directory', async t => {
  const {root, output} = fixture(t);
  assert.deepEqual(packagePaths(root).sort(), [
    'LICENSE', 'SKILL.md', 'rules/nested/🦀.md', 'rules/ordinary.md',
  ]);
  const outputs = await pack(binary, root, output);
  const first = outputs.map(file => readFileSync(file));
  assert.ok(first[0].length < 1024);
  assert.deepEqual(first[0], first[1]);
  assert.deepEqual(readdirSync(output).sort(), ['SHA256SUMS','test-skill.skill','test-skill.zip']);
  await pack(binary, root, output);
  for (let i = 0; i < outputs.length; i++) assert.deepEqual(readFileSync(outputs[i]), first[i]);
});

test('invalid input cannot modify a previously published package', async t => {
  const {root, output} = fixture(t);
  const outputs = await pack(binary, root, output);
  const previous = outputs.map(file => readFileSync(file));
  writeFileSync(path.join(root,'SKILL.md'), 'invalid header\n');
  await assert.rejects(pack(binary, root, output), /skill packer failed/);
  for (let i = 0; i < outputs.length; i++) assert.deepEqual(readFileSync(outputs[i]), previous[i]);
  assert.equal(readdirSync(output).length, 3);
});

test('reject empty rule inventory and output nested in input corpus', async t => {
  const {root, output} = fixture(t);
  const nested = path.join(root,'rules','new-output');
  await assert.rejects(pack(binary, root, nested), /within package inputs/);
  assert.equal(existsSync(nested), false);
  rmSync(path.join(root,'rules'), {recursive: true});
  mkdirSync(path.join(root,'rules'));
  await assert.rejects(pack(binary, root, output), /no rule files/);
  assert.equal(existsSync(output), false);
});

test('reject symlinked input and output destinations', async t => {
  const {root, output, directory} = fixture(t);
  try {
    symlinkSync(path.join(root,'LICENSE'), path.join(root,'rules','link.md'),'file');
  } catch (error) {
    if (['EPERM','EACCES'].includes(error.code)) return t.skip('symlinks unavailable');
    throw error;
  }
  await assert.rejects(pack(binary,root,output), /must not be symlinks/);
  rmSync(path.join(root,'rules','link.md'));
  mkdirSync(output);
  const target = path.join(directory,'target');
  writeFileSync(target,'existing\n');
  symlinkSync(target,path.join(output,'test-skill.zip'),'file');
  await assert.rejects(pack(binary,root,output), /overwrite non-file/);
  assert.equal(readFileSync(target,'utf8'),'existing\n');
  assert.deepEqual(readdirSync(output),['test-skill.zip']);
});
