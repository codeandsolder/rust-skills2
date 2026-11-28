// Host filesystem enumeration and output publication for the Rust/WASI packer.
// The guest does not depend on WASI directory iteration (unsupported on some
// Windows Node releases) and receives the complete explicit input inventory.
import { WASI } from 'node:wasi';
import { createHash } from 'node:crypto';
import {
  closeSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync,
  readdirSync, realpathSync, renameSync, rmSync, writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export function packagePaths(root) {
  const files = [];
  function visit(relative, directory) {
    const file = path.join(root, relative);
    const info = lstatSync(file);
    if (info.isSymbolicLink()) throw new Error('package paths must not be symlinks: ' + relative);
    if (info.isFile() && !directory) {
      files.push(relative);
    } else if (info.isDirectory() && directory !== false) {
      for (const name of readdirSync(file)) visit(relative + '/' + name);
    } else {
      throw new Error('unexpected package path type: ' + relative);
    }
  }
  visit('SKILL.md', false);
  visit('LICENSE', false);
  visit('rules', true);
  if (!files.some(name => name.startsWith('rules/'))) throw new Error('package contains no rule files');
  return files;
}

function inside(parent, child) {
  const relative = path.relative(parent, child);
  return !path.isAbsolute(relative) && relative !== '..' && !relative.startsWith('..' + path.sep);
}

function publish(stage, output) {
  const names = readdirSync(stage).sort();
  const zip = names.find(name => /^[A-Za-z0-9][A-Za-z0-9_-]*\.zip$/.test(name));
  if (!zip) throw new Error('packer did not produce a ZIP archive');
  const skill = zip.slice(0, -4) + '.skill';
  if (names.length !== 3 || !names.includes(skill) || !names.includes('SHA256SUMS')) {
    throw new Error('unexpected packer output: ' + names.join(', '));
  }
  for (const name of names) {
    if (!lstatSync(path.join(stage, name)).isFile()) throw new Error('unexpected non-file output: ' + name);
  }
  const bytes = readFileSync(path.join(stage, zip));
  const digest = createHash('sha256').update(bytes).digest('hex');
  if (!bytes.equals(readFileSync(path.join(stage, skill))) ||
      readFileSync(path.join(stage, 'SHA256SUMS'), 'utf8') !== digest + '  ' + zip + '\n' + digest + '  ' + skill + '\n') {
    throw new Error('package copies or checksums differ');
  }
  // Validate all destinations before replacing any existing file.
  for (const name of names) {
    const destination = path.join(output, name);
    try {
      if (!lstatSync(destination).isFile()) throw new Error('refusing to overwrite non-file: ' + destination);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  for (const name of [zip, skill, 'SHA256SUMS']) renameSync(path.join(stage, name), path.join(output, name));
  return [zip, skill, 'SHA256SUMS'].map(name => path.join(output, name));
}

export async function pack(module, root, output) {
  root = realpathSync(root);
  const files = packagePaths(root);
  // Do not create directories inside the input corpus, including through
  // existing symlinks in output ancestors.
  const resolvedOutput = path.resolve(output);
  let ancestor = resolvedOutput;
  for (;;) {
    try {
      const canonical = realpathSync(ancestor);
      if (inside(path.join(root, 'rules'), path.resolve(canonical, path.relative(ancestor, resolvedOutput)))) {
        throw new Error('output directory must not sit within package inputs');
      }
      break;
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      ancestor = path.dirname(ancestor);
    }
  }
  mkdirSync(resolvedOutput, {recursive: true});
  output = realpathSync(resolvedOutput);
  const stage = mkdtempSync(path.join(output, '.skill-pack-'));
  try {
    const manifest = path.join(stage, 'input.json');
    writeFileSync(manifest, JSON.stringify(files), {flag: 'wx'});
    const stdin = openSync(manifest, 'r');
    try {
      const wasi = new WASI({
        version: 'preview1', args: ['skill-pack'],
        preopens: {'/workspace': root, '/out': stage},
        stdin, returnOnExit: true,
      });
      const compiled = await WebAssembly.compile(readFileSync(module));
      const instance = await WebAssembly.instantiate(compiled, wasi.getImportObject());
      const status = wasi.start(instance);
      if (status !== 0) throw new Error('skill packer failed: ' + status);
    } finally {
      closeSync(stdin);
    }
    rmSync(manifest);
    return publish(stage, output);
  } finally {
    rmSync(stage, {recursive: true, force: true});
  }
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  const [module, root, output] = process.argv.slice(2);
  if (!module || !root || !output || process.argv.length !== 5) {
    throw new Error('usage: node skill-pack/run.mjs MODULE.wasm ROOT OUTPUT_DIRECTORY');
  }
  for (const file of await pack(module, root, output)) console.log(file);
}
