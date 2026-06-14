#!/usr/bin/env python3
"""Parse `cargo check --examples --message-format=json` and classify failures.

Buckets per example:
  FRAGMENT  - every error is name resolution (undefined symbol/crate/import).
              Expected for illustrative snippets; ignored.
  ARTIFACT  - errors caused by extracting a fragment (a `&self` method body
              wrapped as a free fn, or pseudocode `...` tokens). Not real bugs.
  LOW       - only "type annotations needed" (E0282/E0283): compiles in the
              rule's real context; at most a slightly weak standalone example.
  SUSPECT   - anything else (type mismatch, no-method, bad syntax, wrong
              arity, trait-impl mismatch, ...). These are reviewed and fixed.
"""
import json, sys, pathlib, collections

HERE = pathlib.Path(__file__).resolve().parent
manifest = json.loads((HERE / "manifest.json").read_text())

RES_CODES = {"E0432","E0433","E0412","E0425","E0405","E0531","E0422",
             "E0423","E0573","E0463","E0583","E0561","E0658","E0599a"}
RES_PREFIXES = ("cannot find","unresolved import","failed to resolve",
                "use of undeclared","cannot determine","can't find crate",
                "maybe a missing crate","unresolved module")
LOW_CODES = {"E0282","E0283"}

def code_of(d):
    return (d.get("code") or {}).get("code")

def is_resolution(d):
    if code_of(d) in RES_CODES:
        return True
    m = d.get("message","")
    return any(m.startswith(p) for p in RES_PREFIXES)

def is_artifact(d):
    m = d.get("message","")
    if "parameter is only allowed in associated functions" in m:  # method body wrapped as fn
        return True
    if code_of(d) in {"E0586", "E0585"}:              # `..=...` range / dangling doc comment
        return True
    if "`...`" in m:                                  # pseudocode ellipsis token
        return True
    if "await is only allowed inside" in m:           # wrapper edge (rare)
        return True
    if "missing documentation" in m:
        return True
    return False

src = sys.stdin if len(sys.argv) < 2 else open(sys.argv[1])
errors = collections.defaultdict(list)
for raw in src:
    raw = raw.strip()
    if not raw.startswith("{"):
        continue
    try:
        rec = json.loads(raw)
    except json.JSONDecodeError:
        continue
    if rec.get("reason") != "compiler-message":
        continue
    msg = rec.get("message", {})
    if msg.get("level") != "error":
        continue
    tgt = (rec.get("target") or {}).get("name")
    if tgt:
        errors[tgt].append(msg)

frag = artifact = low = 0
suspects = {}
for ex, diags in errors.items():
    nonres = [d for d in diags if not is_resolution(d)]
    if not nonres:
        frag += 1; continue
    if all(is_artifact(d) for d in nonres):
        artifact += 1; continue
    real = [d for d in nonres if not is_artifact(d)]
    if all(code_of(d) in LOW_CODES for d in real):
        low += 1; continue
    suspects[ex] = [d for d in real if code_of(d) not in LOW_CODES]

checked = len(manifest); failed = len(errors)
print("== compile-check summary ==")
print(f"examples checked          : {checked}")
print(f"compiled clean            : {checked - failed}")
print(f"fragments (undefined syms): {frag}")
print(f"wrapper/pseudocode artifacts: {artifact}")
print(f"low-signal (needs type ann): {low}")
print(f"SUSPECT (review these)    : {len(suspects)}")
print()
rows = []
for ex, diags in suspects.items():
    info = manifest.get(ex, {})
    rows.append((info.get("file","?"), info.get("line",0), info.get("section","?"), diags))
for file, line, section, diags in sorted(rows):
    print(f"\n--- {file}:{line}  [{section}]")
    seen = set()
    for d in diags:
        c = code_of(d) or "----"
        m = d.get("message","").splitlines()[0]
        if (c, m) in seen:
            continue
        seen.add((c, m))
        print(f"    {c}: {m}")
