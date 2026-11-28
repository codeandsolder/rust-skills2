import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('strict Rust runs dependency audit once after successful lint and before cache finalization', () => {
  const workflow = readFileSync('.github/workflows/strict-rust.yml', 'utf8');
  const action = /codeandsolder\/ci-workflows\/\.github\/actions\/rust-dependency-quality@[a-f0-9]{40} # main/;
  const strict = workflow.indexOf('      - name: rust-skills2 strict gate\n');
  const audit = workflow.indexOf('      - name: Enforce dependency consolidation and report advisories\n');
  const finalize = workflow.indexOf('      - name: Finalize mandatory sccache\n');
  assert(strict >= 0 && audit > strict && finalize > audit);
  assert.match(workflow.slice(audit, finalize), action);
  assert.match(workflow.slice(audit, finalize), /if: inputs\.dependency-quality/);
  assert.match(workflow, /      dependency-quality:\n[\s\S]*?        default: true/);
  assert(!workflow.slice(audit, finalize).includes('continue-on-error'));
  assert.match(workflow.slice(audit, finalize), /working-directory: \$\{\{ inputs\.working-directory \}\}/);
  assert(!workflow.includes('cargo install cargo-deny') && !workflow.includes('cargo install cargo-machete') && !workflow.includes('cargo install cargo-anoint'));
});
