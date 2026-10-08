"""Post every markdown file under DOCS_DIR to the RAG service's /ingest (stdlib only)."""
import json
import os
import pathlib
import urllib.request

root = pathlib.Path(os.environ.get("DOCS_DIR", "/repo"))
url = os.environ.get("RAG_URL", "http://rag-app.apps.svc.cluster.local") + "/ingest"
files = sorted(p for p in root.rglob("*.md") if ".git" not in p.parts)
for i in range(0, len(files), 10):
    docs = [{"source": str(p.relative_to(root)), "text": p.read_text(errors="ignore")} for p in files[i:i + 10]]
    req = urllib.request.Request(url, data=json.dumps({"documents": docs}).encode(),
                                 headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        print([d["source"] for d in docs], "->", resp.read().decode())
print(f"ingested {len(files)} files")
