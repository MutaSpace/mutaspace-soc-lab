# AI tools for the SOC lab

Two working tools that use the lab's local model (see [../docs/ai/README.md](../docs/ai/README.md)
for the design and the model deployment). Both are the Day 4 "AI drafts, human decides" pattern
made concrete, both run on CPU, and both are dependency-free Python — nothing to `pip install` to
try them, which keeps them runnable on the isolated `nlp-01` node.

| Tool | Integration | What it does |
|------|-------------|--------------|
| `detection_copilot.py` | #2 | Drafts a Sigma or Suricata rule from a plain-language incident, then **validates it** (`sigma check` / `suricata -T`) and **repairs** failures, up to twice. Validated drafts land in `out/` for a human to review before deploy. |
| `assistant.py` | #3 | Answers questions about this lab **from the lab's own `docs/`** (RAG with `nomic-embed-text`), citing the source files. |

Shared plumbing: `ollama_client.py` (the model client) and `validators.py` (the static gates).

## Prerequisites

1. **The model.** Point `OLLAMA_HOST` at the lab's model node, or run Ollama locally:
   ```bash
   export OLLAMA_HOST=http://10.10.20.30:11434   # nlp-01, once the fw-01 rule is open
   # ...or, off-lab, just: ollama serve && ollama pull qwen2.5:3b && ollama pull nomic-embed-text
   ```
   Stand it up on the lab node with `ansible-playbook ansible/playbooks/80-ai-assist.yml`.

2. **Validators (optional, for the copilot).** Install to gate rules for real; skip to demo
   against sample data (drafts are shown clearly marked as ungated):
   ```bash
   pip install -r ai/requirements.txt      # sigma-cli, for `sigma check`
   sudo apt-get install -y suricata        # for `suricata -T`
   ```

## Detection copilot (#2)

```bash
python3 ai/detection_copilot.py --samples
python3 ai/detection_copilot.py --type sigma    --incident "20 failed ssh logins for root then one success on ubuntu-app-01"
python3 ai/detection_copilot.py --type suricata --incident "outbound HTTP beacon, User-Agent EvilBot/1.0; sid 9000001"
```

The loop: **generate → validate → repair → human**. It never deploys — validated drafts are
written to `ai/out/` (gitignored) for you to review and then install into the lab ruleset
(Wazuh `local_rules.xml` / the Suricata rules dir) through the normal Ansible flow. Sample
incidents live in `samples/incidents.md` and are grounded in this lab's own hosts and segments.

## Lab assistant (#3)

```bash
python3 ai/assistant.py --reindex                         # embed docs/ once (needs the embedder)
python3 ai/assistant.py --ask "what runs on the isolated segment?"
python3 ai/assistant.py                                   # interactive
```

It embeds `docs/` into `ai/.index/` (gitignored), retrieves the most relevant excerpts for a
question, and asks the model to answer **from them**, citing sources. It is told to say "that
isn't in the docs" rather than guess — a confident wrong answer about this lab is worse than an
honest gap.

## Security notes

- **No secrets to the model.** Never put credentials, real PII, or a scenario's answer key in a
  prompt or a doc the assistant can retrieve. You cannot leak what is not there.
- **Read-only corpus.** Only a maintainer adds docs the assistant indexes; a learner-editable
  corpus is an indirect-injection channel.
- **Human at the end.** Nothing here deploys a rule, closes an alert, or touches a host. Every
  output is a draft a person confirms.

## Status

Written and statically checked (Python compiles; the pure-logic paths — sample parsing, chunking,
cosine, fence-stripping — are unit-exercised). **Not yet run end-to-end against the live model on
`nlp-01`** (the node is not built at the time of writing). Run them once the model is up and
update this line — this lab's rule is "verify on the host; never assume."
