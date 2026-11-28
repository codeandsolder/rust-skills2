import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const provider = /codeandsolder\/ci-workflows\/\.github\/workflows\/rust-dependency-gate\.yml@[a-f0-9]{40}/;

test('strict Rust runs metadata-only dependency validation independently of source and compilation checks', () => {
  const workflow = readFileSync('.github/workflows/strict-rust.yml', 'utf8');
  const scan = workflow.indexOf('  dependency-scan:\n');
  const strict = workflow.indexOf('  strict-rust:\n');
  assert(scan >= 0 && strict > scan);
  const dependency = workflow.slice(scan, strict);
  assert.match(dependency, provider);
  assert.match(dependency, /if: inputs\.dependency-quality/);
  assert.match(dependency, /working-directories: .*inputs\.working-directory/);
  assert.match(dependency, /checkout-submodules: .*inputs\.checkout-submodules/);
  assert.match(workflow, /      dependency-quality:\n[\s\S]*?        default: true/);
  assert.match(workflow.slice(strict), /needs: dependency-scan/);
  assert.match(workflow.slice(strict), /if: .*always\(\).* !cancelled\(\)/);
  assert.match(workflow.slice(strict), /if: inputs\.dependency-quality && needs\.dependency-scan\.result != 'success'\n        shell: bash\n        run: exit 1/);
  assert(workflow.indexOf('Require independent dependency scan') < workflow.indexOf('rust-skills2 strict gate\n'));
  assert(!dependency.includes('continue-on-error'));
  assert(!workflow.includes('/.github/actions/rust-dependency-quality@'));
  assert(!workflow.includes('cargo install cargo-deny') && !workflow.includes('cargo install cargo-machete') && !workflow.includes('cargo install cargo-anoint'));
});

test('own CI scans every production and example-harness locked Rust workspace and gates the existing required job', () => {
  const workflow = readFileSync('.github/workflows/ci.yml','utf8');
  const scan = workflow.indexOf('  dependency-scan:\n');
  const checks = workflow.indexOf('  checks:\n');
  const dependency = workflow.slice(scan,checks);
  assert(scan >= 0 && checks > scan);
  assert.match(dependency,provider);
  assert.match(dependency,/working-directories: '\["checks","checks\/ci-tool","checks\/nightly","policy-wasm","skill-pack"\]'/);
  assert.match(workflow.slice(checks),/needs: dependency-scan/);
  assert.match(workflow.slice(checks),/if: needs\.dependency-scan\.result != 'success'\n        shell: bash\n        run: exit 1/);
  assert.match(workflow.slice(checks),/name: Validate & compile-check/);
});
