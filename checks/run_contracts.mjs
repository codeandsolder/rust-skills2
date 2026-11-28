// Native process orchestration for generated examples.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, realpathSync, rmSync, rmdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const checks = fileURLToPath(new URL('.', import.meta.url));
const root = realpathSync(path.join(checks, '..'));

function run(bin, args, cwd, capture = false, timeout) {
  const result = spawnSync(bin, args, {
    cwd, encoding: 'utf8', timeout,
    stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit',
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(bin + ' failed: ' + args.join(' '));
  return result.stdout;
}

function fixtures(manifest, target, ciTool) {
  const names = [...new Set(Object.values(manifest)
    .map(info => info.expect)
    .filter(expect => expect.startsWith('fixture:'))
    .map(expect => expect.slice('fixture:'.length)))].sort();
  for (const name of names) {
    if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error('invalid fixture name: ' + name);
    const verifier = path.join(checks, 'fixtures', name, 'verify.sh');
    if (!existsSync(verifier)) throw new Error('fixture lacks verifier: ' + name);
    console.log('==> fixture contract: ' + name);
    run('bash', [verifier, root, target, ciTool], root);
  }
  console.log('OK: ' + names.length + ' fixture contract(s)');
}

function examples(manifest, mode, target) {
  const nightly = mode === 'nightly';
  const directory = nightly ? path.join(checks, 'nightly') : checks;
  const selected = Object.entries(manifest).filter(([, info]) => nightly ? info.expect === 'nightly' : info.stable_run);
  if (!selected.length) throw new Error('no ' + mode + ' examples selected');
  const names = new Set(selected.map(([name]) => name));
  const args = ['build'];
  if (nightly) {
    const generated = readdirSync(path.join(directory, 'examples'))
      .filter(file => file.endsWith('.rs')).map(file => path.basename(file, '.rs'));
    if (generated.length !== names.size || generated.some(name => !names.has(name))) {
      throw new Error('nightly example inventory differs from generated sources');
    }
    args.push('--examples', '--all-features');
  } else {
    for (const name of names) args.push('--example', name);
  }

  args.push('--target', target, '--locked', '--message-format=json-render-diagnostics');
  const stdout = run('cargo', args, directory, true);
  const executables = new Map();
  for (const line of stdout.trim().split('\n')) {
    const message = JSON.parse(line);
    if (message.reason === 'compiler-artifact' && message.target.kind.includes('example') && message.executable !== null) {
      executables.set(message.target.name, message.executable);
    }
  }
  if (executables.size !== names.size || [...names].some(name => !executables.has(name))) {
    throw new Error('Cargo did not report an executable for every selected example');
  }
  let ran = 0;
  for (const [name, info] of selected) {
    if (info[mode + '_run']) {
      run(executables.get(name), [], directory, false, 30_000);
      ran++;
    }
  }
  console.log('OK: ' + names.size + ' ' + mode + ' examples built; ' + ran + ' executable contracts passed');
}

function cancellation(target, ciTool) {
  const name = 'cancel_contract_generated';
  const directory = path.join(checks, 'tests');
  const createdDir = !existsSync(directory);
  const file = 'checks/tests/' + name + '.rs';
  if (existsSync(path.join(root, file))) throw new Error("refusing to overwrite existing cancellation fixture");
  try {
    run(ciTool, [root, 'cancellation', path.join(root, file)], root);
    run('cargo', ['test', '--locked', '--test', name, '--target', target], checks);
  } finally {
    rmSync(path.join(root, file), {force:true});
    if (createdDir && existsSync(directory)) rmdirSync(directory);
  }
}

const [ciToolOption, target] = process.argv.slice(2);
if (!ciToolOption || !target || process.argv.length !== 4) throw new Error('usage: node run_contracts.mjs CI_TOOL TARGET');
const ciTool = realpathSync(ciToolOption);
const manifest = JSON.parse(readFileSync(path.join(checks, 'manifest.json'), 'utf8'));
fixtures(manifest, target, ciTool);
examples(manifest, 'stable', target);
examples(manifest, 'nightly', target);
cancellation(target, ciTool);
