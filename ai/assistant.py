#!/usr/bin/env python3
"""
assistant.py — a lab assistant grounded on THIS repository's docs.

Integration #3 from ../docs/ai/README.md. It is retrieval-augmented generation (RAG) over
the lab's own `docs/`: it embeds the documentation once, and at question time retrieves the
most relevant excerpts and asks the local model to answer FROM THEM, citing the source files.
The point is that a learner asking "how is the isolated segment supposed to route?" gets an
answer out of this lab's documentation — with the source — instead of a generic web answer.

Dependency-free: the embeddings come from the local `nomic-embed-text` model via Ollama, and
the nearest-neighbour search is a few lines of plain-Python cosine similarity. A small doc
corpus does not need a vector database.

USAGE
    python3 assistant.py --reindex            # build/refresh the embedding index (needs the embedder)
    python3 assistant.py --ask "what runs on the isolated segment?"
    python3 assistant.py                      # interactive; /exit to quit

The corpus is READ-ONLY on purpose: only a maintainer adds documents. A corpus a learner can
edit is an indirect-injection channel — the Day 2 / Day 3 lesson, applied to the lab itself.
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

import ollama_client as oc

HERE = Path(__file__).resolve().parent
DOCS = HERE.parent / "docs"
INDEX = HERE / ".index" / "docs.json"
SYSTEM_PROMPT = (HERE / "prompts" / "assistant_system.txt").read_text(encoding="utf-8").strip()

# Chunking: docs are prose, so split on blank lines and pack paragraphs up to a size budget.
# Big enough to keep a thought together, small enough that a hit is specific.
CHUNK_CHARS = 1100
TOP_K = 4


# ---------------------------------------------------------------------------------------------
# Indexing
# ---------------------------------------------------------------------------------------------
def _chunk_markdown(text):
    """Pack paragraphs into ~CHUNK_CHARS chunks, so each embedded piece is one coherent idea."""
    paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks, buf = [], ""
    for para in paras:
        if buf and len(buf) + len(para) + 2 > CHUNK_CHARS:
            chunks.append(buf)
            buf = para
        else:
            buf = f"{buf}\n\n{para}" if buf else para
    if buf:
        chunks.append(buf)
    return chunks


def build_index():
    """Embed every Markdown file under docs/ and cache the vectors. Needs the embedder up."""
    if not oc.is_up():
        sys.exit(f"[!] The embedder at {oc.OLLAMA_HOST} is not answering. See ai/README.md.")

    md_files = sorted(DOCS.rglob("*.md"))
    if not md_files:
        sys.exit(f"[!] No Markdown found under {DOCS}.")

    records = []
    for path in md_files:
        rel = path.relative_to(HERE.parent)
        chunks = _chunk_markdown(path.read_text(encoding="utf-8"))
        for j, chunk in enumerate(chunks):
            print(f"  embedding {rel} [{j + 1}/{len(chunks)}]", flush=True)
            records.append({
                "source": str(rel),
                "text": chunk,
                "vector": oc.embed(chunk),
            })

    INDEX.parent.mkdir(exist_ok=True)
    INDEX.write_text(json.dumps({"embed_model": oc.EMBED_MODEL, "records": records}),
                     encoding="utf-8")
    print(f"\nIndexed {len(records)} chunks from {len(md_files)} files -> {INDEX.relative_to(HERE.parent)}")


# ---------------------------------------------------------------------------------------------
# Retrieval
# ---------------------------------------------------------------------------------------------
def _cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


def _load_index():
    if not INDEX.exists():
        sys.exit("[!] No index yet. Build it first:  python3 assistant.py --reindex")
    return json.loads(INDEX.read_text(encoding="utf-8"))["records"]


def retrieve(question, records, k=TOP_K):
    """Return the k chunks whose embeddings are closest to the question's."""
    qv = oc.embed(question)
    scored = sorted(records, key=lambda r: _cosine(qv, r["vector"]), reverse=True)
    return scored[:k]


# ---------------------------------------------------------------------------------------------
# Answering
# ---------------------------------------------------------------------------------------------
def answer(question, records, model=None):
    """Retrieve, then ask the model to answer strictly from the retrieved excerpts."""
    hits = retrieve(question, records)
    context = "\n\n".join(
        f"--- source: {h['source']} ---\n{h['text']}" for h in hits
    )
    reply = oc.chat(
        [{"role": "system", "content": SYSTEM_PROMPT},
         {"role": "user", "content":
             f"Documentation excerpts:\n\n{context}\n\n---\nQuestion: {question}"}],
        model=model,
    )
    sources = sorted({h["source"] for h in hits})
    return reply, sources


def main():
    ap = argparse.ArgumentParser(description="Ask questions about the lab, answered from its docs.")
    ap.add_argument("--reindex", action="store_true", help="build/refresh the embedding index")
    ap.add_argument("--ask", help="ask one question and exit")
    ap.add_argument("--model", default=None, help=f"override the chat model (default {oc.CHAT_MODEL})")
    args = ap.parse_args()

    if args.reindex:
        build_index()
        if not args.ask:
            return

    records = _load_index()

    def _answer(q):
        reply, sources = answer(q, records, model=args.model)
        print(f"\n{reply}\n")
        print(f"[sources: {', '.join(sources)}]\n")

    if args.ask:
        _answer(args.ask)
        return

    print("Lab assistant — answers from the lab's own docs. /exit to quit.\n")
    while True:
        try:
            q = input("ask > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nbye!")
            break
        if q in ("/exit", "/quit"):
            break
        if q:
            _answer(q)


if __name__ == "__main__":
    main()
