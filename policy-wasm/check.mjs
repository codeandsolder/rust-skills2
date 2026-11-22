import { spawnSync } from 'node:child_process';
import { realpathSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ignored = new Set(['.git', '.venv', 'node_modules', 'target', 'vendor']);

function capture(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
  if (result.error) throw result.error;
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    throw new Error(command + ' ' + args.join(' ') + ' exited with ' + (result.status ?? result.signal) + '\n' + result.stdout);
  }
  return result.stdout;
}

function gitRoot(cwd) {
  const result = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {encoding: 'utf8'});
  return result.status === 0 ? realpathSync(result.stdout.trim()) : null;
}

function inside(root, candidate) {
  const relative = path.relative(root, candidate);
  return !path.isAbsolute(relative) && relative !== '..' && !relative.startsWith('..' + path.sep);
}

function mapper(root) {
  return (absolute) => {
    if (!inside(root, absolute)) throw new Error('path outside checked repository: ' + absolute);
    return path.posix.join('/workspace', path.relative(root, absolute).split(path.sep).join('/'));
  };
}

function gitlinks(root) {
  if (root === null) return new Set();
  const output = capture('git', ['-C', root, 'ls-files', '--stage', '-z']);
  return new Set(output.split('\0')
    .filter((record) => record.startsWith('160000 '))
    .map((record) => path.join(root, record.slice(record.indexOf('\t') + 1))));
}

function sourceFiles(roots, submodules, guestPath) {
  const seen = new Set();
  const paths = new Set();
  const pending = [...roots];
  while (pending.length > 0) {
    const directory = pending.pop();
    if (seen.has(directory) || submodules.has(directory)) continue;
    seen.add(directory);
    for (const entry of readdirSync(directory, {withFileTypes: true})) {
      const candidate = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (!ignored.has(entry.name) && !submodules.has(candidate)) pending.push(candidate);
      } else if (entry.name.endsWith('.rs') && (entry.isFile() || entry.isSymbolicLink())) {
        const canonical = entry.isSymbolicLink() ? realpathSync(candidate) : candidate;
        if (statSync(canonical).isFile()) paths.add(guestPath(canonical));
      }
    }
  }
  return [...paths].sort();
}

function boundaryCandidate(packageRoot, relative, root, guestPath) {
  if (path.isAbsolute(relative)) return {absolute: true, exists: false, path: null};
  // Let the filesystem resolve symlink/.. interactions before checking containment.
  const source = packageRoot + path.sep + relative;
  try {
    const canonical = realpathSync(source);
    return {
      absolute: false,
      exists: statSync(canonical).isFile(),
      path: inside(root, canonical) ? guestPath(canonical) : null,
    };
  } catch (error) {
    if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error;
    return {absolute: false, exists: false, path: null};
  }
}

function packageSnapshot(pkg, root, guestPath) {
  const manifest = realpathSync(pkg.manifest_path);
  const packageRoot = path.dirname(manifest);
  const declared = pkg.metadata?.['rust-skills2']?.['generated-lint-boundaries'];
  const candidates = Object.create(null);
  if (Array.isArray(declared)) {
    for (const relative of declared) {
      if (typeof relative === 'string') candidates[relative] = boundaryCandidate(packageRoot, relative, root, guestPath);
    }
  }
  return {
    root: packageRoot,
    package: {
      manifest: guestPath(manifest),
      metadata: pkg.metadata,
      targets: pkg.targets.map((target) => {
        const canonical = realpathSync(target.src_path);
        return inside(root, canonical) ? guestPath(canonical) : null;
      }).filter((target) => target !== null),
      candidates,
    },
  };
}

function snapshot(toolchain) {
  const cargo = ['+' + toolchain];
  const metadata = JSON.parse(capture('cargo', [...cargo, 'metadata', '--no-deps', '--format-version', '1']));
  const workspaceRoot = realpathSync(metadata.workspace_root);
  const checkout = gitRoot(workspaceRoot);
  const root = checkout ?? workspaceRoot;
  const guestPath = mapper(root);
  const members = new Set(metadata.workspace_members);
  const packages = metadata.packages.filter((pkg) => members.has(pkg.id))
    .map((pkg) => packageSnapshot(pkg, root, guestPath));
  const configured = JSON.parse(capture('cargo', [...cargo, '-Z', 'unstable-options', 'config', 'get', '--format=json']));
  const rustflags = Object.fromEntries(Object.entries(process.env).filter(([name]) =>
    ['RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CARGO_BUILD_RUSTFLAGS'].includes(name)
      || (name.startsWith('CARGO_TARGET_') && name.endsWith('_RUSTFLAGS'))));
  return {
    root,
    input: {
      paths: sourceFiles(packages.map((pkg) => pkg.root), gitlinks(checkout), guestPath),
      clippy_help: capture('clippy-driver', ['+' + toolchain, '-W', 'help']),
      workspace_manifest: guestPath(path.join(workspaceRoot, 'Cargo.toml')),
      packages: packages.map((pkg) => pkg.package),
      rustflags,
      cargo_config: configured,
    },
  };
}

const [modulePath, toolchain] = process.argv.slice(2);
if (!modulePath || !/^nightly-\d{4}-\d{2}-\d{2}$/.test(toolchain ?? '') || process.argv.length !== 4) {
  throw new Error('usage: node check.mjs MODULE.wasm nightly-YYYY-MM-DD');
}
const {root, input} = snapshot(toolchain);
const runner = fileURLToPath(new URL('run.mjs', import.meta.url));
const report = JSON.parse(capture(process.execPath, [runner, path.resolve(modulePath), root, 'check'], {input: JSON.stringify(input)}));
if (report.violations.length > 0) {
  console.error('rust-skills2: source lint suppression policy violations:');
  for (const violation of report.violations) console.error('  - ' + violation.replaceAll('/workspace/', root + path.sep));
  process.exitCode = 1;
} else {
  console.log('rust-skills2: source lint suppression policy OK (' + report.files + ' Rust files, ' + report.boundaries + ' generated lint boundaries, ' + report.suppression_attributes + ' suppression attributes)');
}
