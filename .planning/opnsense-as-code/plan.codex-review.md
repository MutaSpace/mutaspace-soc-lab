**CRITICAL**

1. **Root password/hash mismatch is still not build-blocked.**  
   Wave 1 only enforces non-empty values in Packer. The actual lockout risk is a hash that does not match `PKR_VAR_root_password`, and that is only checked manually in Wave 2.  
   **Fix:** make the hash/password cross-check a required scripted preflight in `task build:opnsense` or a dedicated `task fw:preflight`, and require it before `qm destroy 9004`. Do not rely on an operator remembering the Python one-liner.

2. **Second full fw-01 redeploy is treated too casually.**  
   Wave 3 says the second `-replace` is “routine” and “cheap,” but fw-01 is load-bearing, has no guest agent, and recovery is serial/noVNC only. The second redeploy may be justified to prove API-zero-touch, but it is not operationally cheap.  
   **Fix:** either prove the API bake on a disposable clone/test VM first, or keep the second live `-replace` but repeat the full Wave 2 maintenance gate explicitly: fresh backup, console verified, no-apply window called out, rollback ready, and lab-impact notice.

3. **API-key bootstrap path is underspecified.**  
   “Create ONE API key over SSH” may not be trivial or idempotent on OPNsense 26.7, especially with root shell = `csh`, unknown CLI tooling, and the need to capture both plaintext secret for clients and hashed secret for the seed.  
   **Fix:** add a discovery task before Wave 3 implementation: identify the exact supported non-GUI command/path for API-key creation, prove it captures plaintext secret once, prove the resulting `<apikeys>` hash works after reboot, then bake that observed format.

**IMPORTANT**

4. **`qm destroy 9004` happens before all local gates are complete.**  
   The plan runs `packer validate`, but the real build-blocking checks include password/hash match, gitleaks/pre-commit, and possibly template rendering sanity. Destroying 9004 before those pass widens the no-template/no-apply window.  
   **Fix:** make 2.2 depend on a named “all local gates green” checkpoint: `packer validate`, password/hash script, relevant pre-commit/gitleaks, and rendered config inspection if available.

5. **Template_exists no-apply window is documented but not guarded.**  
   The plan says “run NO tofu apply,” but there is no mechanical protection against another terminal/operator invoking `tofu apply` while 9004 is absent.  
   **Fix:** add an operational lock/runbook marker before `qm destroy 9004`, and consider a Taskfile wrapper for rebuild that owns destroy→build→verify so operators do not run partial commands manually.

6. **Rollback restores config but not necessarily template/live-state mismatch.**  
   If Wave 2 or Wave 3 fails after replacing fw-01, restoring `/conf/config.xml` may recover service, but the live VM remains a clone of the newly built template. That may be acceptable, but the plan calls it “pre-cutover state,” which is only config-level rollback.  
   **Fix:** state the rollback scope precisely: config restore only. If true VM-level rollback is required, add a Proxmox backup/snapshot strategy for VMID 100 before `-replace`.

7. **EVE→Wazuh plan is directionally correct but module-level feasibility is unproven.**  
   The plan correctly notes that `<syslog_eve>` alone is insufficient and includes syslog destination, rulesets/policies, and Wazuh decoder. The gap is proving `ansibleguy.opnsense` can manage all of those OPNsense Suricata/syslog fields cleanly.  
   **Fix:** add a Wave 4 spike/gate: map exact collection modules/API endpoints for IDS rulesets, policies, EVE syslog toggle, and remote syslog destination before claiming implementation.

8. **Suricata “enable ET Open rulesets/policies” may create operational noise without a pinned ruleset policy.**  
   The plan says enable ET Open, but not which categories, update schedule, or expected alert volume. That is risky even with IPS off.  
   **Fix:** define the minimal ruleset/policy needed for the verification alert first, then expand later under “go-live/tuning.”

9. **`ansibleguy.opnsense` floating minimum version is risky for firewall automation.**  
   Floating versions can change module behavior between deploys. This is infrastructure control over a load-bearing firewall.  
   **Fix:** pin to a tested version or bounded range, then deliberately update later.

**MINOR**

10. **Wave 2 exit overclaims “zero manual firewall steps.”**  
   Wave 2 includes manual config export and console verification. Those are valid safety steps, but they are firewall-touching pre-cutover actions.  
   **Fix:** reword to “zero manual firewall configuration during deploy”; keep manual backup/console checks as approved safety gates.

11. **“No real management IP committed” conflicts with the plan text.**  
   The plan itself contains real lab IPs like `10.10.10.1`, `10.10.10.20`, and `<LAB_MANAGEMENT_IP>`. Maybe the intent is “no secrets or external management IPs,” but as written it is inconsistent.  
   **Fix:** clarify the policy, or use variables/placeholders in committed docs if these IPs are considered sensitive.

12. **Some verification claims depend on existing task semantics.**  
   `task scenario:run -- ssh-bruteforce` and `task scenario:verify -- ssh-bruteforce` may not be valid syntax depending on the Taskfile’s argument handling.  
   **Fix:** use the repo’s exact scenario invocation in the final runbook.

**Verdict:** not sound to execute as-is; fix the password/hash hard gate, make the API bootstrap concrete, and treat the Wave 3 live redeploy with the same load-bearing controls as Wave 2 before proceeding.
