import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classifyLicense, inspectTree, treeSelectors } from '../scripts/release-licenses.mjs';

test('SPDX alternatives and obligations are evaluated rather than substring matched', () => {
    for (const [expression, result] of [
        ['GPL-3.0+', 'strong'], ['AGPL-3.0-only', 'strong'],
        ['LGPL-3.0-only', 'weak'], ['MIT OR GPL-3.0-only', 'other'],
        ['GPL-2.0-only OR BSD-3-Clause', 'other'],
        ['MIT/Apache-2.0/GPL-2.0', 'other'],
        ['(MIT OR GPL-2.0-only) AND LGPL-3.0-only', 'weak'],
        ['MIT AND (GPL-2.0-only OR AGPL-3.0-only)', 'strong'],
        ['MIT OR GPL-2.0-only AND AGPL-3.0-only', 'other'],
        ['GPL-2.0-only WITH Classpath-exception-2.0', 'strong'],
        ['GPL-2.0-only AND LicenseRef-unknown', 'strong'],
        ['GPL-2.0-only OR LicenseRef-unknown', 'strong'],
        ['LGPL-3.0-only OR MIT', 'other'],
        ['MIT AND LicenseRef-unknown', 'unknown'],
        ['GPL-2.0-only OR (MIT', 'invalid-copyleft'],
        ['', 'unknown'], ['NOASSERTION', 'unknown'],
    ]) assert.equal(classifyLicense(expression), result, expression);
});

test('tree parsing skips roots but includes workspace packages when linked', () => {
    const graph = '0root v1.0.0\tGPL-2.0-only\n1helper v1.0.0\tMIT\n2linked v1.0.0\tGPL-3.0-only\n1helper v1.0.0\tMIT (*)\n0linked v1.0.0\tGPL-3.0-only\n1unknown v1.0.0\t (*)\n';
    assert.deepEqual(inspectTree(graph).map(({packageName, classification}) => [packageName, classification]), [
        ['helper v1.0.0', 'other'], ['linked v1.0.0', 'strong'], ['unknown v1.0.0', 'unknown'],
    ]);
    assert.throws(() => inspectTree('unrecognized'));
});

test('Cargo selectors keep feature and target selection, not test modes', () => {
    assert.deepEqual(treeSelectors('--locked --workspace --all-targets --exclude foo -F gpu --target wasm32-wasip1 --test example'),
        ['--locked', '--workspace', '--exclude', 'foo', '-F', 'gpu', '--target', 'wasm32-wasip1']);
    assert.deepEqual(treeSelectors('--offline --package=foo --no-default-features --features=bar --bin tool'), ['--offline', '--package=foo', '--no-default-features', '--features=bar']);
    assert.throws(() => treeSelectors('--config hack'));
    assert.throws(() => treeSelectors('--features --locked'));
});

test('canonical strict entrypoint invokes blocking license policy exactly once per selection', () => {
    const workflow = readFileSync('.github/workflows/strict-rust.yml', 'utf8');
    const action = readFileSync('.github/actions/rust-strict/action.yml', 'utf8');
    const script = readFileSync('scripts/strict_clippy.sh', 'utf8');
    assert.match(workflow, /uses: \.\/\.rust-skills2-gate\/\.github\/actions\/rust-strict/);
    assert.match(action, /scripts\/strict_clippy\.sh/);
    const invocation = 'node "$LICENSE_POLICY" "$TOOLCHAIN" "$PWD" "${CARGO_ARGS[*]}"';
    assert.equal(script.split(invocation).length, 2);
    assert(script.indexOf(invocation) < script.indexOf('cargo "+$TOOLCHAIN" fmt'));
    assert.match(script, /set -euo pipefail/);
    assert.doesNotMatch(workflow, /release-licenses\.mjs/);
});
