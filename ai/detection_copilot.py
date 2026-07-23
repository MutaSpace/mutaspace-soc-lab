#!/usr/bin/env python3
"""
detection_copilot.py — draft detection rules with the local model, then GATE them.

Integration #2 from ../docs/ai/README.md. This is the Day 4 "generate → validate → repair"
loop, wired to real static validators:

    1. GENERATE  the model drafts a rule from a plain-language incident description
    2. VALIDATE  `sigma check` (log rules) or `suricata -T` (network rules) checks it, offline
    3. REPAIR    if validation fails, the error is fed back for up to N repair attempts
    4. HUMAN     the surviving rule is written to ai/out/ for a person to review before deploy

The model never deploys anything. It produces a validated *draft*; a human installs it into
the lab's ruleset (Wazuh local_rules.xml / the Suricata rules dir) through the normal Ansible
flow. That "AI drafts, human decides" seam is the whole point.

USAGE
    python3 detection_copilot.py --samples                 # run every sample incident
    python3 detection_copilot.py --type sigma --incident "20 failed ssh logins then a success"
    python3 detection_copilot.py --type suricata --incident "beacon with UA EvilBot/1.0; sid 9000001"

Needs the local model up (see ai/README.md). The validators are optional: without them the
draft is shown ungated, with a clear note — enough to build and demo against sample data.
"""

import argparse
import re
import sys
from pathlib import Path

import ollama_client as oc
import validators

HERE = Path(__file__).resolve().parent
PROMPTS = HERE / "prompts"
SAMPLES = HERE / "samples" / "incidents.md"
OUT = HERE / "out"

MAX_REPAIR_ATTEMPTS = 2


def _load_prompt(name):
    return (PROMPTS / name).read_text(encoding="utf-8").strip()


def _strip_fences(text):
    """Models sometimes wrap output in ```...``` despite being told not to. Remove it."""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text)
    return text.strip()


def _validate(rule_type, rule_text):
    return validators.sigma_check(rule_text) if rule_type == "sigma" \
        else validators.suricata_test(rule_text)


def generate_and_gate(rule_type, incident, model=None):
    """
    Run the full generate → validate → repair loop for one incident.

    Returns a dict describing what happened: the final rule text, whether it passed, whether
    it was actually gated (vs the validator being absent), and how many repairs it took.
    """
    gen_prompt = _load_prompt(f"{rule_type}_gen.txt")
    repair_prompt = _load_prompt(f"{rule_type}_repair.txt")

    print(f"\n=== [{rule_type}] {incident.splitlines()[0][:70]} ===")
    print("  generating…", flush=True)
    rule = _strip_fences(oc.chat(
        [{"role": "system", "content": gen_prompt},
         {"role": "user", "content": incident}],
        model=model,
    ))

    result = _validate(rule_type, rule)
    attempts = 0
    while result.status == "fail" and attempts < MAX_REPAIR_ATTEMPTS:
        attempts += 1
        print(f"  validation failed — repairing ({attempts}/{MAX_REPAIR_ATTEMPTS})…", flush=True)
        rule = _strip_fences(oc.chat(
            [{"role": "system", "content": repair_prompt},
             {"role": "user", "content":
                 f"Broken rule:\n{rule}\n\nValidator output:\n{result.output}"}],
            model=model,
        ))
        result = _validate(rule_type, rule)

    # Report
    if result.status == "skipped":
        print(f"  [skipped] {result.output}")
        print(f"  draft (UNGATED — install the validator to check it):\n{_indent(rule)}")
    elif result.passed:
        print(f"  [VALIDATED]{' after ' + str(attempts) + ' repair(s)' if attempts else ''}")
        print(_indent(rule))
    else:
        print(f"  [FAILED] still invalid after {MAX_REPAIR_ATTEMPTS} repair(s):\n{result.output}")
        print(_indent(rule))

    return {
        "type": rule_type,
        "incident": incident,
        "rule": rule,
        "passed": result.passed,
        "gated": result.gated,
        "repairs": attempts,
    }


def _indent(text):
    return "\n".join("    " + ln for ln in text.splitlines())


def _parse_samples():
    """Read samples/incidents.md into (type, description) pairs from its `## [type] title` headings."""
    text = SAMPLES.read_text(encoding="utf-8")
    items = []
    # Split on headings like "## [sigma] SSH brute force…"
    for match in re.finditer(r"^## \[(sigma|suricata)\] (.+?)$(.*?)(?=^## |\Z)",
                             text, re.MULTILINE | re.DOTALL):
        rule_type, title, body = match.group(1), match.group(2).strip(), match.group(3).strip()
        items.append((rule_type, f"{title}\n{body}"))
    return items


def _write_accepted(results):
    """Write validated (or ungated) drafts to ai/out/ for human review. Never auto-deployed."""
    OUT.mkdir(exist_ok=True)
    written = []
    for i, r in enumerate(results, 1):
        if r["passed"] or not r["gated"]:
            ext = "yml" if r["type"] == "sigma" else "rules"
            slug = re.sub(r"[^a-z0-9]+", "-", r["incident"].splitlines()[0].lower())[:40].strip("-")
            path = OUT / f"{i:02d}-{r['type']}-{slug}.{ext}"
            path.write_text(r["rule"] + "\n", encoding="utf-8")
            written.append(path)
    return written


def main():
    ap = argparse.ArgumentParser(description="Draft and statically validate detection rules.")
    ap.add_argument("--samples", action="store_true", help="run every incident in samples/incidents.md")
    ap.add_argument("--type", choices=["sigma", "suricata"], help="rule type for a one-off --incident")
    ap.add_argument("--incident", help="a single incident description to generate from")
    ap.add_argument("--model", default=None, help=f"override the chat model (default {oc.CHAT_MODEL})")
    args = ap.parse_args()

    if not oc.is_up():
        print(f"[!] The model endpoint at {oc.OLLAMA_HOST} is not answering.\n"
              "    Start it (ai/README.md) or set OLLAMA_HOST, then re-run.", file=sys.stderr)
        sys.exit(1)

    if args.samples:
        work = _parse_samples()
    elif args.incident and args.type:
        work = [(args.type, args.incident)]
    else:
        ap.error("give --samples, or both --type and --incident")

    results = [generate_and_gate(t, desc, model=args.model) for t, desc in work]

    written = _write_accepted(results)
    passed = sum(1 for r in results if r["passed"])
    ungated = sum(1 for r in results if not r["gated"])
    print(f"\n=== summary: {passed}/{len(results)} validated"
          f"{f', {ungated} ungated (validator missing)' if ungated else ''} ===")
    for p in written:
        print(f"  wrote {p.relative_to(HERE.parent)}")
    print("\nReview each rule before deploying it into the lab ruleset. AI drafts, human decides.")


if __name__ == "__main__":
    main()
