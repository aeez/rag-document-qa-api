# RAG Document Q&A API

**English** · [Bahasa Indonesia](README.id.md)

Upload a PDF, ask a question, and inspect the passage behind the answer. This FastAPI service runs retrieval and generation locally. Each citation includes the original filename, the physical PDF page number (starting at 1), and the retrieved text.

## How it works

1. **Index a PDF.** pypdf extracts text page by page. The API splits each page into passages of up to 150 words with a 30-word overlap. BGE-M3 embeds each passage through Ollama. PostgreSQL stores the 1,024-dimensional vectors and their page metadata with pgvector.
2. **Retrieve evidence.** LangChain embeds the question with the same model. A cosine-distance search returns up to four passages from the requested document.
3. **Answer and cite.** Llama 3 8B receives the question and numbered passages. The API validates the returned source IDs and resolves them to stored excerpts. If the model returns no sources, the API responds with an empty citation list. Valid source IDs alone do not guarantee that a passage supports the answer.

## Run locally

Install Git and Docker with Compose v2. On Windows, start Docker Desktop in Linux container mode. The first run downloads container images and roughly 6 GB of model weights. CPU inference on a memory-constrained machine can take minutes per question.

```sh
git clone https://github.com/aeez/rag-document-qa-api.git
cd rag-document-qa-api
docker compose up -d --build
docker compose exec ollama ollama pull bge-m3
docker compose exec ollama ollama pull llama3:8b
```

Open [Swagger UI](http://localhost:8000/docs) for an interactive walkthrough. The API listens on the host's loopback address. Model weights and database records persist in Docker volumes after `docker compose down`.

## Try a question

Create a one-page text PDF named `policy.pdf` containing the sentence **“Expense claims must be submitted within 14 days.”** The following PowerShell example uploads that file and uses the actual ID returned by the API.

```powershell
$doc = curl.exe -fsS -F "file=@policy.pdf" http://localhost:8000/documents | ConvertFrom-Json
$body = @{ document_id = $doc.document_id; question = "When are expense claims due?" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:8000/ask -ContentType "application/json" -Body $body | ConvertTo-Json -Depth 5
```

Illustrative response for this example. Model wording may vary.

```json
{
  "answer": "Within 14 days.",
  "citations": [
    {
      "filename": "policy.pdf",
      "page": 1,
      "excerpt": "Expense claims must be submitted within 14 days."
    }
  ]
}
```

## API reference

| Endpoint | Input | Success |
| --- | --- | --- |
| `POST /documents` | Multipart form field `file`. Text PDF, up to 10 MiB and 100 pages. | `201` with `document_id` and `chunks` |
| `POST /ask` | JSON with a document UUID and a nonblank `question` of up to 1,000 characters. | `200` with `answer` and `citations` |

Encrypted PDFs are rejected. For scans, run OCR before upload. Pages without extractable text are skipped. If the retrieved passages offer insufficient evidence and the model returns no sources, the fallback text is `Jawaban tidak ditemukan di dokumen.` Error responses use FastAPI's `detail` field.

| Symptom | What to check |
| --- | --- |
| `404` on a question | Copy the ID returned by a successful upload. |
| `413` or `422` on upload | Check the byte and page limits, password protection, and whether the PDF contains selectable text. |
| `502` on a question | The model returned invalid JSON or a source ID outside the retrieved set. Retry with a specific question. |
| `503` or slow answers | Use `docker compose exec ollama ollama list` to confirm both models are installed. Check `docker compose logs --tail 50 ollama` for memory or model-loading errors. |

## Evaluation and scope

This is a local, single-user prototype. It has no authentication or tenant isolation. One request searches one document. The API stores extracted passages and embeddings, so treat the database volume as document data.

**Evaluation status:** no measured relevance score has been published. The planned evaluation uses 150 held-out questions. Record a reference answer (or an expected abstention) and source page for each. Grade answer relevance against the reference and citation support against the PDF separately. Report the number of passing cases and denominator alongside each percentage.

## Repository guide

| File | Purpose |
| --- | --- |
| [main.py](main.py) | Upload, chunking, retrieval, model invocation, and citation validation |
| [schema.sql](schema.sql) | pgvector extension and passage storage |
| [compose.yaml](compose.yaml) | Local API, PostgreSQL, and Ollama services |
| [Dockerfile](Dockerfile) · [requirements.txt](requirements.txt) | Python 3.12 runtime and application dependencies |
