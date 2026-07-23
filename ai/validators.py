"""
validators.py — the static validators that gate generated detection rules.

This is the load-bearing half of the detection copilot. An LLM produces plausible-looking
rules that are often subtly invalid; a static validator catches that mechanically, offline,
before a human ever spends attention on the rule. The generate → validate → repair loop
only works for artifact types that have a validator like these.

Both validators DEGRADE GRACEFULLY. If the underlying tool is not installed, they return a
`skipped` status rather than crashing, so the copilot still runs against sample data on a
machine that does not yet have sigma-cli or suricata — you just see the draft ungated, with
a clear note that it was not checked. Install the tools (see ai/README.md) to gate for real.
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

# A validator result. `status` is one of: "pass", "fail", "skipped".
#   pass    — the tool ran and accepted the rule
#   fail    — the tool ran and rejected it; `output` is the error to feed the repair prompt
#   skipped — the tool is not installed; the rule was not checked at all
class Result:
    def __init__(self, status, output):
        self.status = status
        self.output = output

    @property
    def passed(self):
        return self.status == "pass"

    @property
    def gated(self):
        """Was the rule actually checked? False when the validator was missing."""
        return self.status in ("pass", "fail")


def sigma_check(rule_yaml):
    """
    Validate a Sigma rule with `sigma check` (from the pip package `sigma-cli`).

    sigma-cli exits non-zero and prints the problem when a rule is malformed, which is
    exactly the signal the repair loop needs.
    """
    if shutil.which("sigma") is None:
        return Result("skipped", "sigma-cli not installed (`pip install sigma-cli`).")

    with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False) as fh:
        fh.write(rule_yaml)
        path = fh.name
    try:
        proc = subprocess.run(
            ["sigma", "check", path],
            capture_output=True, text=True, timeout=30,
        )
        output = (proc.stdout + proc.stderr).strip()
        return Result("pass" if proc.returncode == 0 else "fail", output)
    except subprocess.TimeoutExpired:
        return Result("fail", "ERROR: `sigma check` timed out after 30s.")
    finally:
        Path(path).unlink(missing_ok=True)


def suricata_test(rule_text):
    """
    Validate a Suricata rule with `suricata -T` — the config/rule self-test mode.

    -T loads and checks the rule and exits; it never captures traffic (no -i, no pcap), so
    it is safe and fast to run anywhere and needs no network. We point it at only the one
    rule file so the check is about the generated rule, not the system ruleset.
    """
    if shutil.which("suricata") is None:
        return Result("skipped", "suricata not installed (`apt-get install suricata`).")

    with tempfile.NamedTemporaryFile("w", suffix=".rules", delete=False) as fh:
        fh.write(rule_text + "\n")
        path = fh.name
    try:
        proc = subprocess.run(
            ["suricata", "-T", "-S", path, "-l", tempfile.gettempdir()],
            capture_output=True, text=True, timeout=45,
        )
        output = _filter(proc.stdout + proc.stderr)
        # suricata -T returns 0 when the rule loads cleanly.
        return Result("pass" if proc.returncode == 0 else "fail", output)
    except subprocess.TimeoutExpired:
        return Result("fail", "ERROR: `suricata -T` timed out after 45s.")
    finally:
        Path(path).unlink(missing_ok=True)


def _filter(output):
    """Keep only the lines from suricata -T that say something about the rule."""
    keep = ("Error", "error", "warning", "Warning", "rules successfully", "rule files")
    lines = [ln for ln in output.splitlines() if any(k in ln for k in keep)]
    return "\n".join(lines).strip() or output.strip()
