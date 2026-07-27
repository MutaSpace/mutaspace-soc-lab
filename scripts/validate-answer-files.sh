#!/usr/bin/env bash
# =============================================================================
# scripts/validate-answer-files.sh
#
# Validates every Windows Autounattend template in this repository as XML.
#
# WHY THIS EXISTS
#   A malformed Autounattend.xml is the single most expensive failure in this
#   repo's history. Windows Setup does not report it: it parses the file, fails,
#   and silently resets. The VM boots WinPE, shows the Setup background with no
#   UI, writes nothing to the disk, reboots, and loops forever - which looks
#   exactly like a driver or firmware fault and is neither.
#
#   The specific trap is that a DOUBLE HYPHEN is illegal inside an XML comment.
#   Writing a command line like `tool.sh - -flag` (unspaced) in a comment breaks
#   the whole document. It happened once with a real command, cost a day, and then
#   happened AGAIN in the very comment written to warn about it.
#
#   So this is a machine check rather than a note asking people to be careful.
#
# WHAT IT DOES
#   Substitutes Packer's ${...} placeholders with a dummy value, then parses each
#   file as XML and separately reports any illegal `--` inside a comment (which is
#   the same failure, but with a message that says what to fix).
#
# USAGE
#   ./scripts/validate-answer-files.sh
#   Exits non-zero if any file is invalid. Wired into pre-commit.
# =============================================================================
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t FILES < <(find packer -name 'Autounattend.xml*' -type f | sort)
if (( ${#FILES[@]} == 0 )); then
  echo "no Autounattend templates found - nothing to validate"; exit 0
fi

fail=0
for f in "${FILES[@]}"; do
  out="$(python3 - "$f" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path = sys.argv[1]
raw = open(path, encoding='utf-8').read()

# Report illegal '--' inside comments first: it is the most likely cause and the
# XML parser's own message ("invalid token") does not say why.
problems = []
for m in re.finditer(r'<!--(.*?)-->', raw, re.S):
    for hm in re.finditer(r'--', m.group(1)):
        line = raw[:m.start(1) + hm.start()].count('\n') + 1
        ctx = m.group(1)[max(0, hm.start()-40):hm.start()+40].replace('\n', ' ').strip()
        problems.append(f"line {line}: illegal '--' inside an XML comment: ...{ctx}...")

try:
    ET.fromstring(re.sub(r'\$\{[^}]+\}', 'PLACEHOLDER', raw))
except ET.ParseError as e:
    problems.append(f"XML parse error: {e}")

if problems:
    print('\n'.join(problems)); sys.exit(1)
PY
)"
  if [[ -n "$out" ]]; then
    printf 'FAIL  %s\n' "$f"
    printf '        %s\n' "$out"
    fail=1
  else
    printf 'ok    %s\n' "$f"
  fi
done

if (( fail )); then
  echo
  echo "A malformed answer file makes Windows Setup reset silently in a loop."
  echo "Fix the above before building. Double hyphens inside XML comments are the usual cause."
  exit 1
fi
