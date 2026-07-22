# Roles

This folder holds the three roles this lab actually needs, and explains why there are only three.

---

## Why so few roles

A role is worth writing when the same block of tasks has to run on more than one host and carry
its own defaults, handlers and files. A role is not worth writing when it wraps a single task that
runs on a single machine, because then the role is just a second file to open before you can read
what the playbook does.

The domain promotion runs on one host, once. The Wazuh server installation runs on one host, once.
Neither is a role. Agent installation runs on eight hosts across two operating systems, with a
restart handler and a version pin — that is a role.

| Role | Applies to | Why it exists |
|---|---|---|
| `common_linux` | six Linux hosts | Baseline packages and time synchronisation that every Linux host needs before anything else works |
| `wazuh_agent_linux` | five Linux hosts | Repository setup, pinned agent install, enrollment, and the switch from IP to FQDN |
| `wazuh_agent_windows` | two Windows hosts | The same job through the MSI, with the same parameters |

---

## Time synchronisation is not housekeeping

`common_linux` installs and enables `chrony`. In most projects that would be a tidiness task. In
this one it is load-bearing twice over.

Kerberos rejects authentication when the clock skew between client and domain controller exceeds
five minutes, so a drifting Linux host stops being able to talk to the domain. And a SIEM
correlates by timestamp — an endpoint whose clock is wrong does not produce wrong-looking events,
it produces events that quietly sort into the wrong place in a timeline, which is worse.

---

## wazuh-ansible is cloned, not installed

Wazuh publishes its official Ansible roles as a Git repository rather than as a Galaxy collection,
and the branch you want is the one matching your Wazuh version. If the lab ever outgrows the
all-in-one deployment and moves to a distributed install, clone them here:

```bash
git clone --depth 1 --branch v4.14.6 \
  https://github.com/wazuh/wazuh-ansible.git roles/wazuh-ansible
```

They are not used today. `40-wazuh-server.yml` installs the server with Wazuh's own installation
assistant, which is the supported path for an all-in-one deployment and is what the existing
[wazuh-01 build documentation](../../docs/vms/wazuh-01-build.md) describes.

The clone target is listed in `ansible/.gitignore` so that a vendored copy of someone else's
repository never lands in this one's history.

---

## Learning Reflection

Three roles is fewer than this lab probably "should" have, and deciding what did *not* become a role
turned out to be the interesting part.

The rule that emerged is that a role earns its existence by being **used more than once against
machines that differ**. `common_linux` is applied to Ubuntu servers, an Ubuntu desktop and two Kali
boxes; `wazuh_agent_linux` and `wazuh_agent_windows` each enroll several hosts. Everything else —
promoting the forest, creating DNS records, seeding the lab accounts — happens exactly once against
exactly one machine. Wrapping a one-shot sequence in a role does not make it reusable, it just moves
it somewhere a reader has to go looking for it, and adds a layer of variable indirection between the
task and the value it uses.

The second thing worth naming is that the Linux and Windows agent roles are separate on purpose,
even though they do "the same thing". They share a goal and almost no mechanism: one is an apt
repository, a systemd unit and a text config file; the other is an MSI, a Windows service and a
different text config file, reached over a different transport with different authentication. A
single role with `when: ansible_os_family == ...` on every task is not one role, it is two roles
sharing a filename — and it hides the fact that the Windows path has a whole extra failure mode in
WinRM before any of it starts.

The last lesson is about handlers. Both agent roles notify a restart handler rather than restarting
inline, and the reason is not tidiness: an agent restarted in the middle of its own configuration
re-registers with the manager against a half-written `ossec.conf`. Handlers run at the end of the
play, which is the only point at which "the agent's configuration is finished" is actually true.
Deferring the side effect until the state is complete is the whole idea behind handlers, and it is
easy to treat them as a style preference until something re-registers with the wrong name.
