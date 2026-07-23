"""
ollama_client.py — a tiny, dependency-free client for the lab's local model.

Every AI tool in this directory talks to Ollama through this one module. It uses only the
Python standard library (urllib + json), so the tools run on a lab node with nothing to
`pip install` — which matters on nlp-01, an isolated-segment box that should not be reaching
out to a package index.

The endpoint is read from the OLLAMA_HOST environment variable and defaults to the local
Ollama on the same machine. Point it at the model node from elsewhere with, e.g.:

    export OLLAMA_HOST=http://10.10.20.30:11434     # nlp-01, once the fw-01 rule is open

See ../docs/ai/README.md for where the model runs and how reachability is decided.
"""

import json
import os
import urllib.error
import urllib.request

# Default matches the Ollama default. group_vars/all.yml sets ai_ollama_bind /
# ai_ollama_port for the deployed node; this client just needs a URL to POST to.
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")

# Model names mirror the group_vars/all.yml defaults so the tools and the playbook agree.
CHAT_MODEL = os.environ.get("AI_CHAT_MODEL", "qwen2.5:3b")
EMBED_MODEL = os.environ.get("AI_EMBED_MODEL", "nomic-embed-text")


class OllamaUnavailable(RuntimeError):
    """Raised when the model endpoint cannot be reached — with a fix, not a stack trace."""


def _post(path, payload, timeout=300):
    """POST a JSON body to the Ollama API and return the decoded JSON response."""
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{OLLAMA_HOST}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.URLError as err:
        raise OllamaUnavailable(
            f"Could not reach the model at {OLLAMA_HOST} ({err}).\n"
            "  - Is Ollama running there? On the lab node: `ansible-playbook "
            "ansible/playbooks/80-ai-assist.yml`.\n"
            "  - Testing off-box? Set OLLAMA_HOST to the node's address and make sure the "
            "fw-01 rule is open.\n"
            "  - No lab yet? Run `ollama serve` locally and `ollama pull qwen2.5:3b`."
        ) from err


def is_up():
    """True if the endpoint answers /api/tags. Used by tools to fail early and kindly."""
    try:
        with urllib.request.urlopen(f"{OLLAMA_HOST}/api/tags", timeout=5) as resp:
            return resp.status == 200
    except (urllib.error.URLError, TimeoutError):
        return False


def chat(messages, model=None, temperature=0.1, num_predict=1024):
    """
    One non-streaming chat completion. Returns the assistant's text.

    Low temperature by default: rule generation and grounded Q&A want the model to be
    faithful and repeatable, not creative.
    """
    resp = _post("/api/chat", {
        "model": model or CHAT_MODEL,
        "messages": messages,
        "stream": False,
        "options": {"temperature": temperature, "num_predict": num_predict},
    })
    return resp.get("message", {}).get("content", "")


def embed(text, model=None):
    """Return the embedding vector (list of floats) for a piece of text."""
    resp = _post("/api/embeddings", {"model": model or EMBED_MODEL, "prompt": text})
    vector = resp.get("embedding")
    if not vector:
        raise OllamaUnavailable(
            f"The embedder returned no vector. Is '{model or EMBED_MODEL}' pulled? "
            "Check `ollama list` on the model node."
        )
    return vector
