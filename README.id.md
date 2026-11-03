# RAG Document Q&A API

[English](README.md) · **Bahasa Indonesia**

Unggah PDF, ajukan pertanyaan, lalu periksa kutipan yang mendasari jawabannya. Layanan FastAPI ini mencari teks dan menyusun jawaban secara lokal. Setiap sitasi memuat nama file asli, nomor halaman fisik PDF (mulai dari 1), dan teks sumber.

## Cara kerja

1. **Mengindeks PDF.** pypdf membaca teks per halaman. API membaginya menjadi potongan maksimal 150 kata dengan 30 kata yang tumpang tindih. BGE-M3 melalui Ollama mengubah potongan menjadi vektor berdimensi 1.024. PostgreSQL menyimpan vektor dan informasi halaman menggunakan pgvector.
2. **Mencari sumber.** LangChain menggunakan model yang sama untuk mengubah pertanyaan menjadi vektor. Pencarian berdasarkan jarak kosinus mengambil hingga empat potongan dari dokumen yang dipilih.
3. **Menjawab dengan sitasi.** Llama 3 8B menerima pertanyaan dan potongan bernomor. API memvalidasi ID sumber dari model, lalu mengambil kutipan dan nomor halaman dari database. Jika model tidak menyertakan sumber, daftar sitasi dikembalikan kosong. Tetap cocokkan isi kutipan dengan klaim dalam jawaban.

## Menjalankan project

Siapkan Git dan Docker dengan Compose v2. Di Windows, aktifkan Docker Desktop dalam mode Linux containers. Pada penggunaan pertama, Docker mengunduh image dan sekitar 6 GB bobot model. Pemrosesan di CPU dengan RAM terbatas bisa memerlukan beberapa menit per pertanyaan.

```sh
git clone https://github.com/aeez/rag-document-qa-api.git
cd rag-document-qa-api
docker compose up -d --build
docker compose exec ollama ollama pull bge-m3
docker compose exec ollama ollama pull llama3:8b
```

Buka [Swagger UI](http://localhost:8000/docs) untuk mencoba endpoint secara interaktif. Port API hanya dibuka pada alamat loopback host. Model dan isi database tersimpan di volume Docker setelah `docker compose down`.

## Mencoba satu pertanyaan

Buat PDF teks satu halaman bernama `kebijakan.pdf` yang memuat kalimat **“Klaim biaya harus diajukan dalam 14 hari.”** Jalankan contoh PowerShell ini dari folder yang berisi PDF tersebut. Perintah kedua menggunakan ID dokumen dari hasil unggahan.

```powershell
$doc = curl.exe -fsS -F "file=@kebijakan.pdf" http://localhost:8000/documents | ConvertFrom-Json
$body = @{ document_id = $doc.document_id; question = "Berapa lama batas pengajuan klaim biaya?" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:8000/ask -ContentType "application/json" -Body $body | ConvertTo-Json -Depth 5
```

Contoh bentuk respons untuk PDF tersebut. Redaksi jawaban model dapat berbeda.

```json
{
  "answer": "Dalam 14 hari.",
  "citations": [
    {
      "filename": "kebijakan.pdf",
      "page": 1,
      "excerpt": "Klaim biaya harus diajukan dalam 14 hari."
    }
  ]
}
```

## Referensi API

| Endpoint | Masukan | Respons berhasil |
| --- | --- | --- |
| `POST /documents` | PDF teks melalui kolom multipart `file`, maksimal 10 MiB dan 100 halaman. | `201` dengan `document_id` dan `chunks` |
| `POST /ask` | JSON berisi UUID dokumen dan `question` yang tidak kosong, maksimal 1.000 karakter. | `200` dengan `answer` dan `citations` |

API menolak PDF terenkripsi dan melewati halaman tanpa teks yang dapat diekstrak. Untuk hasil pindai, jalankan OCR sebelum mengunggah. Jika sumber tidak cukup dan model mengembalikan daftar sumber kosong, jawaban bawaannya adalah `Jawaban tidak ditemukan di dokumen.` Pesan galat tersedia di kolom `detail`.

| Gejala | Langkah pemeriksaan |
| --- | --- |
| `404` saat bertanya | Gunakan ID yang dikembalikan saat unggahan berhasil. |
| `413` atau `422` saat mengunggah | Periksa ukuran, jumlah halaman, proteksi kata sandi, dan apakah teks PDF bisa diseleksi. |
| `502` saat bertanya | Format JSON atau ID sumber dari model tidak valid. Coba pertanyaan yang lebih spesifik. |
| `503` atau respons lambat | Periksa kedua model dengan `docker compose exec ollama ollama list`. Baca `docker compose logs --tail 50 ollama` untuk melihat kendala RAM atau pemuatan model. |

## Evaluasi dan batas penggunaan

Prototipe ini ditujukan untuk satu pengguna lokal. Autentikasi dan pemisahan data antar pengguna belum tersedia. Setiap permintaan mencari dalam satu dokumen. Volume database berisi teks hasil ekstraksi dan embedding, sehingga perlu diperlakukan sebagai data dokumen.

**Status evaluasi:** belum ada skor relevansi terukur yang dipublikasikan. Rencana evaluasi menggunakan 150 pertanyaan uji terpisah. Untuk setiap pertanyaan, catat jawaban acuan atau tandai bahwa informasi tidak tersedia, lalu catat halaman pendukung. Nilai ketepatan jawaban dan dukungan sitasi secara terpisah. Saat melaporkan persentase, sertakan jumlah kasus yang lulus dan jumlah yang dinilai.

## Isi repositori

| File | Fungsi |
| --- | --- |
| [main.py](main.py) | Unggahan, pemotongan teks, pencarian, pemanggilan model, dan validasi sitasi |
| [schema.sql](schema.sql) | Ekstensi pgvector dan struktur penyimpanan potongan teks |
| [compose.yaml](compose.yaml) | Layanan API, PostgreSQL, dan Ollama |
| [Dockerfile](Dockerfile) · [requirements.txt](requirements.txt) | Lingkungan Python 3.12 dan dependensi aplikasi |
