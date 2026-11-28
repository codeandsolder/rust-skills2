import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

// This is a GPL-family policy, not a general SPDX approval list. A license
// outside the GPL family is not thereby certified as suitable for distribution.
const strong = /^(?:AGPL|GPL)(?:-|$)/i;
const weak = /^LGPL(?:-|$)/i;
const unknown = /^(?:LicenseRef-|DocumentRef-|NONE$|NOASSERTION$)/i;

// SPDX expressions are disjunctions of possible grants (OR), conjunctions
// of obligations (AND), and optional exceptions (WITH). Cargo also accepts
// the historical slash separator as OR. No exception is automatically approved.
export function classifyLicense(expression) {
    if (!expression?.trim()) return 'unknown';
    const tokens = expression.match(/\(|\)|\/|[A-Za-z0-9][A-Za-z0-9.\-+:]*/g) ?? [];
    const joined = tokens.join('');
    if (joined !== expression.replace(/\s/g, '')) {
        return /\b(?:A|L)?GPL(?:-|\b)/i.test(expression) ? 'invalid-copyleft' : 'unknown';
    }
    let cursor = 0;
    const rank = { other: 0, weak: 1, strong: 2, unknown: 3 };
    const choose = (a, b, compare) => compare(rank[a], rank[b]) ? a : b;
    function atom() {
        if (tokens[cursor] === '(') {
            cursor++;
            const result = or();
            if (tokens[cursor++] !== ')') throw new Error('unbalanced expression');
            return result;
        }
        const id = tokens[cursor++];
        if (!id || ['AND', 'OR', 'WITH', ')', '/'].includes(id)) throw new Error('expected license');
        let result = strong.test(id) ? 'strong' : weak.test(id) ? 'weak' : unknown.test(id) ? 'unknown' : 'other';
        if (tokens[cursor] === 'WITH') {
            cursor++;
            const exception = tokens[cursor++];
            if (!exception || !/^[A-Za-z0-9][A-Za-z0-9.\-+]*$/.test(exception) || ['AND', 'OR', 'WITH'].includes(exception)) throw new Error('expected exception');
            // A GPL exception may be meaningful, but must be reviewed rather
            // than implicitly treating every exception as a permissive grant.
        }
        return result;
    }
    function and() {
        let result = atom();
        while (tokens[cursor] === 'AND') {
            cursor++;
            const right = atom();
            // Known GPL obligations cannot be hidden by an unknown conjunct.
            if (result === 'strong' || right === 'strong') result = 'strong';
            else if (result === 'weak' || right === 'weak') result = 'weak';
            else result = choose(result, right, (a, b) => a >= b);
        }
        return result;
    }
    function or() {
        let result = and();
        while (tokens[cursor] === 'OR' || tokens[cursor] === '/') {
            cursor++;
            result = choose(result, and(), (a, b) => a <= b);
        }
        return result;
    }
    try {
        const result = or();
        if (cursor !== tokens.length) throw new Error('trailing tokens');
        return result;
    } catch {
        return /\b(?:A|L)?GPL(?:-|\b)/i.test(expression) ? 'invalid-copyleft' : 'unknown';
    }
}

// Preserve package, feature, target and lock selections from the strict
// compilation job, but deliberately exclude test/build/proc-macro edges.
export function treeSelectors(cargoArgs) {
    const args = cargoArgs.trim().split(/\s+/).filter(Boolean);
    const selectors = [];
    const flags = new Set(['--locked', '--frozen', '--offline', '--workspace', '--all-features', '--no-default-features']);
    const values = new Set(['-p', '--package', '--exclude', '-F', '--features', '--target']);
    const ignored = new Set(['--all-targets', '--lib', '--bins', '--examples', '--tests', '--benches', '--keep-going', '--no-deps']);
    const ignoredValues = new Set(['--bin', '--example', '--test', '--bench']);
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (flags.has(arg)) selectors.push(arg);
        else if (values.has(arg) || ignoredValues.has(arg)) {
            const value = args[++i];
            if (!value || value.startsWith('-')) throw new Error('missing value for ' + arg);
            if (values.has(arg)) selectors.push(arg, value);
        } else if (/^--(?:package|exclude|features|target)=.+$/.test(arg)) selectors.push(arg);
        else if (!ignored.has(arg) && !/^--(?:bin|example|test|bench)=.+$/.test(arg)) throw new Error('unsupported Cargo selector ' + arg);
    }
    return selectors;
}

export function inspectTree(output) {
    const packages = new Map();
    for (const line of output.split(/\r?\n/)) {
        if (!line.trim()) continue;
        const match = /^(\d+)([^\t]+)\t(.*)$/.exec(line);
        if (!match) throw new Error('unexpected cargo tree row: ' + line);
        const [, depth, packageName, rawLicense] = match;
        // A repository's own declared license is not a dependency. A
        // workspace member encountered at depth > 0 is still a dependency.
        if (Number(depth) === 0) continue;
        const license = rawLicense.replace(/ \(\*\)$/, '').trim();
        packages.set(packageName + '\t' + license, { packageName, license, classification: classifyLicense(license) });
    }
    return [...packages.values()].sort((a, b) => a.packageName.localeCompare(b.packageName));
}

function main() {
    const [toolchain, cwd, cargoArgs = '--locked --workspace --all-targets'] = process.argv.slice(2);
    if (!toolchain || !cwd) throw new Error('usage: release-licenses.mjs TOOLCHAIN WORKSPACE CARGO_ARGS');
    const args = ['+' + toolchain, 'tree', ...treeSelectors(cargoArgs), '--edges', 'normal,no-proc-macro', '--prefix', 'depth', '--format', '{p}\t{l}', '--color', 'never'];
    const result = spawnSync('cargo', args, { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    if (result.error) throw result.error;
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.status !== 0) throw new Error('cargo tree failed: ' + result.status);
    const packages = inspectTree(result.stdout);
    let failed = false;
    for (const { packageName, license, classification } of packages) {
        if (classification === 'strong' || classification === 'invalid-copyleft') {
            console.error('GPL/AGPL release dependency: ' + packageName + ' — ' + license);
            failed = true;
        } else if (classification === 'weak' || classification === 'unknown') {
            console.warn('Release license review (' + classification + '): ' + packageName + ' — ' + (license || '(undeclared)'));
        }
    }
    console.log('Checked ' + packages.length + ' normal dependency identities (excluding build, dev and proc-macro edges).');
    if (failed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    try { main(); } catch (error) { console.error(error); process.exitCode = 1; }
}
