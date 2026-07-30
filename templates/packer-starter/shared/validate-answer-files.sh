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
#   Two distinct traps have caused this, and both are checked here.
#
#   1. A DOUBLE HYPHEN is illegal inside an XML comment. Writing a command line
#      like `tool.sh - -flag` (unspaced) in a comment breaks the whole document.
#      It happened once with a real command, cost a day, and then happened AGAIN
#      in the very comment written to warn about it.
#
#   2. A COMPONENT MAY APPEAR ONLY ONCE PER SETTINGS PASS. The document is still
#      well-formed XML, so check 1 passes it happily - but Windows rejects it.
#      Adding a second Microsoft-Windows-Deployment block to `specialize` (one for
#      BitLocker, one for BypassNRO) produced "The computer restarted unexpectedly
#      or encountered an unexpected error" and a 24-hour build that never reached
#      WinRM. Windows says exactly what is wrong, but only in
#      Windows\Panther\setuperr.log on a disk Packer deletes on failure:
#      "The same namespace should not appear twice in a single settings section",
#      hrResult = 0x8022001b. Merge the commands into one component instead.
#
#   So this is a machine check rather than a note asking people to be careful.
#
# WHAT IT DOES
#   Substitutes Packer's ${...} placeholders with a dummy value, then for each file
#   parses it as XML, reports any illegal `--` inside a comment, and reports any
#   component named twice within one settings pass. Each check reports the line
#   number and says what to fix, because the XML parser's own message does not.
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

# A component may be named only once per settings pass. Scan the raw text rather
# than the parsed tree so the report can carry a line number. Comments are blanked
# out first (newlines kept, so line numbers stay true) because they discuss these
# very tag names.
stripped = re.sub(r'<!--.*?-->', lambda m: '\n' * m.group(0).count('\n'), raw, flags=re.S)
IDENTITY = ('name', 'processorArchitecture', 'publicKeyToken', 'language', 'versionScope')
current_pass, seen = None, {}
for m in re.finditer(r'<settings\s+pass="([^"]+)"|</settings>|<component\s([^>]*?)/?>',
                     stripped, re.S):
    if m.group(0).startswith('</settings'):
        current_pass = None
    elif m.group(1) is not None:
        current_pass, seen = m.group(1), {}
    else:
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(2)))
        key = tuple(attrs.get(a, '') for a in IDENTITY)
        # count in `stripped`, not `raw`: blanking comments shifts character
        # offsets but preserves newlines, so only this string's lines are true.
        line = stripped[:m.start()].count('\n') + 1
        if key in seen:
            problems.append(
                f"line {line}: component '{attrs.get('name', '?')}' appears twice in the "
                f"'{current_pass}' pass (first at line {seen[key]}). Windows rejects the "
                f"whole answer file - merge the two into one component.")
        else:
            seen[key] = line

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
  echo "An invalid answer file makes Windows Setup fail without saying why - it either"
  echo "resets in a silent loop, or stops at 'The computer restarted unexpectedly'."
  echo "Fix the above before building."
  exit 1
fi
