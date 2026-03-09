# Panduan Stack Big Data: Hadoop + Kafka + Spark + Jupyter + Neo4j

Panduan ini mencakup setup, operasional sehari-hari, troubleshooting, dan upgrade stack berbasis Docker Compose.

---

## Daftar Isi

1. [Prasyarat](#1-prasyarat)
2. [Struktur Direktori](#2-struktur-direktori)
3. [Komponen Stack](#3-komponen-stack)
4. [Setup Pertama Kali](#4-setup-pertama-kali)
5. [Operasional Sehari-hari](#5-operasional-sehari-hari)
6. [Mengakses UI](#6-mengakses-ui)
7. [Menjalankan Notebook Spark Streaming](#7-menjalankan-notebook-spark-streaming)
8. [Menjalankan Kafka Producer](#8-menjalankan-kafka-producer)
9. [Aturan Penting: Version Alignment](#9-aturan-penting-version-alignment)
10. [Menambah atau Mengubah Python Dependencies](#10-menambah-atau-mengubah-python-dependencies)
11. [Troubleshooting](#11-troubleshooting)
12. [Upgrade Versi Komponen](#12-upgrade-versi-komponen)
13. [Reset Bersih](#13-reset-bersih)

---

## 1. Prasyarat

| Kebutuhan | Versi Minimum | Catatan |
|---|---|---|
| Docker Desktop / Docker Engine | 24.x | Pastikan Docker daemon berjalan |
| Docker Compose | v2 (plugin) | Gunakan `docker compose` bukan `docker-compose` |
| RAM tersedia | 8 GB | Semua service aktif sekaligus |
| Disk tersedia | 20 GB | Untuk image dan volume |
| Arsitektur | amd64 atau arm64 | Apple Silicon didukung |

Verifikasi instalasi:

```bash
docker --version
docker compose version
```

---

## 2. Struktur Direktori

```
project/
├── docker-compose.yml          # Definisi semua service
├── Dockerfile.jupyter          # Custom image Jupyter berbasis Spark
├── requirements.jupyter.txt    # Python dependencies untuk Jupyter
└── notebooks/                  # Di-mount ke container Jupyter
```

Buat folder `notebooks` sebelum menjalankan stack:

```bash
mkdir -p notebooks
```

---

## 3. Komponen Stack

| Service | Image | Port Host | Keterangan |
|---|---|---|---|
| `namenode` | `openeuler/hadoop:latest` | `9870` | HDFS NameNode + Web UI |
| `datanode` | `openeuler/hadoop:latest` | — | HDFS DataNode |
| `kafka` | `apache/kafka:4.1.1` | `9092` (ext), `29092` (int) | Broker KRaft, tanpa ZooKeeper |
| `kafka-ui` | `provectuslabs/kafka-ui:latest` | `8080` | Web UI monitoring Kafka |
| `spark-master` | `apache/spark:3.5.1-...` | `8081`, `7077` | Spark Master + UI |
| `spark-worker` | `apache/spark:3.5.1-...` | — | Spark Worker |
| `jupyter` | `local/jupyter-spark:3.5.1` | `8888` | JupyterLab (custom build) |
| `neo4j` | `neo4j:5` | `7474`, `7687` | Graph database + Browser |

### Kafka Listener

Kafka dikonfigurasi dengan dua listener terpisah untuk menghindari `NoBrokersAvailable`:

```
INTERNAL://kafka:29092  → untuk sesama container (Jupyter, Spark)
EXTERNAL://localhost:9092 → untuk aplikasi yang jalan di host
```

---

## 4. Setup Pertama Kali

### Langkah 1 — Clone atau siapkan file

Unduh dan ekstrak terlebih dahulu arsip yang disediakan sesuai dengan arsitektur device Anda:
| Arsitektur | OS |
|------------|----|
| `amd64` | Windows, macOS (sebelum Apple Silicon), Linux |
| `arm64` | Windows (untuk Snapdragon), macOS (Apple Silicon), Linux ARM |

Setelah ekstrak, pastikan ketiga file ini ada di direktori yang sama:
- `docker-compose.yml`
- `Dockerfile.jupyter`
- `requirements.jupyter.txt`

### Langkah 2 — Build Jupyter image

Jupyter menggunakan custom image yang perlu di-build terlebih dahulu. Langkah ini hanya perlu dilakukan sekali (atau setelah `requirements.jupyter.txt` diubah):

```bash
docker compose build jupyter
```

Proses ini membutuhkan waktu 3–5 menit tergantung kecepatan internet — pip mengunduh semua dependencies dan menyimpannya di dalam image.

### Langkah 3 — Jalankan semua service

```bash
docker compose up -d
```

### Langkah 4 — Verifikasi semua container berjalan

```bash
docker compose ps
```

Semua service harus berstatus `running`. Tunggu 30–60 detik untuk Kafka dan Spark selesai inisialisasi sebelum menjalankan notebook.

---

## 5. Operasional Sehari-hari

### Menjalankan stack

```bash
docker compose up -d
```

### Menghentikan stack (data tetap tersimpan)

```bash
docker compose down
```

### Melihat log semua service

```bash
docker compose logs -f
```

### Melihat log service tertentu

```bash
docker compose logs -f jupyter
docker compose logs -f kafka
docker compose logs -f spark-master
```

### Restart service tertentu

```bash
docker compose restart jupyter
```

### Cek resource usage

```bash
docker stats
```

---

## 6. Mengakses UI

Setelah stack berjalan, semua UI bisa diakses via browser:

| UI | URL | Kredensial |
|---|---|---|
| **JupyterLab** | http://localhost:8888 | Tanpa token/password |
| **Spark Master** | http://localhost:8081 | — |
| **Kafka UI** | http://localhost:8080 | — |
| **HDFS NameNode** | http://localhost:9870 | — |
| **Neo4j Browser** | http://localhost:7474 | `neo4j` / `IF5241-bigdata` |

---

## 7. Menjalankan Notebook Spark Streaming

### Langkah 1 — Buka JupyterLab

Buka http://localhost:8888 di browser. Notebook tersedia di file browser sebelah kiri.

### Langkah 2 — Pastikan producer berjalan

Sebelum menjalankan sel streaming di notebook, pastikan `producer_variance.py` sudah aktif mengirim pesan ke Kafka (lihat [Bagian 8](#8-menjalankan-kafka-producer)).

### Langkah 3 — Jalankan sel secara berurutan

Jalankan setiap sel dari atas ke bawah secara berurutan. Jangan melewati sel setup atau SparkSession.

### Langkah 4 — Sel streaming

Sel yang menjalankan `query_a.awaitTermination(40)` akan memblokir selama 40 detik sambil menampilkan output batch secara real-time. Setelah selesai, `query_a.stop()` otomatis menghentikan stream.

### Catatan penting

Jika kernel pernah di-restart atau notebook dibuka ulang setelah container restart, **hapus checkpoint lama** terlebih dahulu agar tidak terjadi konflik offset Kafka:

```bash
rm -rf ./notebooks/.spark_checkpoint/variance
```

Lalu restart kernel di JupyterLab: **Kernel → Restart Kernel**.

---

## 8. Menjalankan Kafka Producer

`producer_variance.py` mengirim pesan `"1 2 3 4 5 6"` ke topic `variance` setiap 2 detik.

### Dari host (terminal biasa)

> Jika ada kendala dengan pip, disarankan membuat virtual environment terlebih dahulu dengan command berikut
> ```bash
> python -m venv .venv
> source .venv/bin/activate
> ```

```bash
pip install kafka-python
python producer_variance.py
```

Pastikan `BOOTSTRAP_SERVER` di dalam file menggunakan `localhost:9092` (EXTERNAL listener).

### Dari dalam container Jupyter (via terminal JupyterLab)

Buka terminal di JupyterLab (**File → New → Terminal**), lalu:

```bash
python /home/notebooks/producer_variance.py
```

Pastikan `BOOTSTRAP_SERVER` menggunakan `kafka:29092` (INTERNAL listener).

### Menghentikan producer

Tekan `Ctrl+C` di terminal tempat producer berjalan.

---

## 9. Aturan Penting: Version Alignment

> **Ini adalah aturan paling kritis di stack ini.**

Spark driver (Jupyter) dan Spark executor (worker) **harus menggunakan versi Spark yang identik**. Jika berbeda, akan muncul error:

```
java.io.InvalidClassException: org.apache.spark.rdd.RDD;
local class incompatible: stream classdesc serialVersionUID = ...
```

Versi Spark dikontrol di **satu tempat**: argumen `SPARK_IMAGE` di `docker-compose.yml`:

```yaml
jupyter:
  build:
    args:
      SPARK_IMAGE: apache/spark:3.5.1-scala2.12-java17-python3-r-ubuntu  # ← satu tempat ini

spark-master:
  image: apache/spark:3.5.1-scala2.12-java17-python3-r-ubuntu  # ← harus sama

spark-worker:
  image: apache/spark:3.5.1-scala2.12-java17-python3-r-ubuntu  # ← harus sama
```

Versi JAR Kafka connector di notebook juga harus mengikuti:

```python
.config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1")
#                                                                                ↑ sama
```

---

## 10. Menambah atau Mengubah Python Dependencies

Semua Python dependencies Jupyter dikelola di `requirements.jupyter.txt`. Proses installasi terjadi saat build image, bukan saat container start — sehingga startup menjadi instan.

### Cara menambah package

1. Edit `requirements.jupyter.txt`, tambahkan package yang diinginkan:

```
# contoh menambahkan scipy
scipy==1.15.2
```

2. Rebuild image Jupyter:

```bash
docker compose build jupyter
```

3. Restart container Jupyter:

```bash
docker compose up -d --force-recreate jupyter
```

Service lain (Kafka, Spark, Neo4j) tidak perlu disentuh.

---

## 11. Troubleshooting

### `NoBrokersAvailable` di producer

Periksa bootstrap server yang digunakan:

| Lokasi producer dijalankan | Bootstrap server yang benar |
|---|---|
| Terminal host | `localhost:9092` |
| Dalam container | `kafka:29092` |

### `InvalidClassException` / `serialVersionUID` mismatch

Versi Spark di Jupyter tidak sama dengan worker. Pastikan `SPARK_IMAGE` di `docker-compose.yml` identik untuk semua service Spark, lalu rebuild:

```bash
docker compose build jupyter
docker compose up -d --force-recreate jupyter spark-master spark-worker
```

### `Partition offset was changed` / `failOnDataLoss`

Terjadi ketika checkpoint menyimpan offset lama tapi Kafka topic di-reset (biasanya setelah `docker compose down -v`). Solusi:

```bash
rm -rf ./notebooks/.spark_checkpoint/variance
```

Lalu restart kernel di JupyterLab.

### Kernel Jupyter `404 Kernel does not exist`

Ini terjadi ketika browser masih memegang referensi kernel lama dari session sebelumnya. Tutup tab dan buka ulang http://localhost:8888, atau klik **Kernel → Restart Kernel** di dalam notebook.

### Spark jobs tidak jalan, worker tidak terdaftar

Cek apakah worker sudah terhubung ke master:

```bash
docker compose logs spark-worker | grep "Successfully registered"
```

Jika belum, restart worker:

```bash
docker compose restart spark-worker
```

### Stream berjalan tapi tidak ada output di notebook

Periksa apakah `clear_output()` dan `print()` ada di dalam `calculate_variance`. Output `print()` dari dalam `foreachBatch` hanya terlihat jika dipanggil di driver thread — pastikan fungsi tidak memindahkan operasi output ke executor.

---

## 12. Upgrade Versi Komponen

### Upgrade Spark

1. Pilih versi baru dari [Docker Hub apache/spark](https://hub.docker.com/r/apache/spark/tags)
2. Update `docker-compose.yml` di **tiga tempat sekaligus**:

```yaml
# spark-master
image: apache/spark:3.5.X-scala2.12-java17-python3-r-ubuntu

# spark-worker
image: apache/spark:3.5.X-scala2.12-java17-python3-r-ubuntu

# jupyter build args
SPARK_IMAGE: apache/spark:3.5.X-scala2.12-java17-python3-r-ubuntu
```

3. Update versi JAR di notebook:

```python
"org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.X"
```

4. Rebuild dan restart:

```bash
docker compose build jupyter
docker compose up -d --force-recreate spark-master spark-worker jupyter
```

### Upgrade Kafka

Ganti versi di `docker-compose.yml`:

```yaml
image: apache/kafka:X.X.X
```

Lalu:

```bash
docker compose up -d --force-recreate kafka kafka-ui
```

---

## 13. Reset Bersih

Gunakan ini jika ingin memulai dari awal (semua data hilang):

```bash
# Hentikan semua container dan hapus semua volume
docker compose down -v

# Hapus checkpoint Spark
rm -rf ./notebooks/.spark_checkpoint

# Hapus image Jupyter yang sudah di-build (opsional)
docker rmi local/jupyter-spark:3.5.1

# Mulai dari awal
docker compose build jupyter
docker compose up -d
```

> **Peringatan:** `down -v` akan menghapus semua data HDFS, Kafka topics, dan Neo4j database secara permanen.