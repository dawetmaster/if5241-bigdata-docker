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
14. [Menggunakan Apache Hive](#14-menggunakan-apache-hive)

---

## 1. Prasyarat

| Kebutuhan | Versi Minimum | Catatan |
|---|---|---|
| Docker Desktop / Docker Engine | 24.x | Pastikan Docker daemon berjalan |
| Docker Compose | v2 (plugin) | Gunakan `docker compose` bukan `docker-compose` |
| RAM tersedia | 12 GB | Semua service aktif sekaligus (dengan Hive) |
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
├── hdfs-init.sh                # Inisialisasi HDFS (jalankan sekali)
├── hive-init.sh                # Inisialisasi Hive metastore (jalankan sekali)
├── hadoop-config/              # Config XML yang di-mount ke Hadoop & Hive
│   ├── core-site.xml
│   ├── hdfs-site.xml
│   └── hive-site.xml
├── hadoop/                     # Staging area host ↔ HDFS
└── notebooks/                  # Di-mount ke container Jupyter
```

Gunakan skrip setup untuk membuat direktori secara otomatis:

```bash
# Linux / macOS
chmod +x setup.sh && ./setup.sh

# Windows (PowerShell)
.\setup.ps1
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
| `hive-postgres` | `postgres:16-alpine` | `5432` | Metastore database untuk Hive |
| `hive-metastore` | `apache/hive:4.0.1` | `9083` | Thrift Metastore server |
| `hive-server2` | `apache/hive:4.0.1` | `10000`, `10002` | HiveServer2 JDBC + Web UI |
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

Semua service harus berstatus `running`. Tunggu 30–60 detik untuk Kafka dan Spark selesai inisialisasi.

### Langkah 5 — Inisialisasi HDFS (hanya sekali)

```bash
chmod +x hdfs-init.sh
./hdfs-init.sh
```

Skrip ini memformat NameNode (jika belum pernah), menunggu DataNode terhubung, dan membuat struktur direktori awal di HDFS. Aman dijalankan ulang — tidak akan format ulang jika sudah ada data.

### Langkah 6 — Inisialisasi Hive (hanya sekali, setelah HDFS siap)

```bash
chmod +x hive-init.sh
./hive-init.sh
```

Skrip ini menginisialisasi schema metastore di PostgreSQL via `schematool`, membuat direktori HDFS `/user/hive/warehouse`, dan memverifikasi koneksi HiveServer2.

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
| **HiveServer2 UI** | http://localhost:10002 | — |
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

> **Peringatan:** `down -v` akan menghapus semua data HDFS, Kafka topics, Neo4j database, dan Hive metastore secara permanen. Setelah `up` kembali, jalankan ulang `hdfs-init.sh` dan `hive-init.sh`.
---

## 14. Menggunakan Apache Hive

### Arsitektur Hive di Stack Ini

```
HiveServer2 (port 10000/10002)
      │  HiveQL query
      ▼
Hive Metastore (port 9083)  ←── metadata tabel, schema, partisi
      │                              │
      │                              ▼
      │                     PostgreSQL (port 5432)
      │
      ▼  baca/tulis data
HDFS (namenode:9000)
      │
      └── /user/hive/warehouse/   ← default lokasi data tabel Hive
```

### Akses via Beeline (CLI)

Masuk ke HiveServer2 dari dalam container:

```bash
docker compose exec hive-server2 beeline -u 'jdbc:hive2://localhost:10000'
```

Contoh query dasar:

```sql
-- Lihat semua database
SHOW DATABASES;

-- Buat database baru
CREATE DATABASE IF NOT EXISTS bigdata;
USE bigdata;

-- Buat tabel dari file CSV yang sudah ada di HDFS
CREATE TABLE IF NOT EXISTS sensor_data (
    id     INT,
    ts     STRING,
    value  DOUBLE
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/user/data/sensor/';

-- Query data
SELECT COUNT(*) FROM sensor_data;
```

### Akses dari Spark (di Notebook Jupyter)

Tambahkan konfigurasi Hive Metastore saat membuat SparkSession:

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder     .appName("HiveIntegration")     .master("spark://spark-master:7077")     .config("spark.jars.packages",
            "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1")     .config("spark.sql.catalogImplementation", "hive")     .config("spark.hive.metastore.uris", "thrift://hive-metastore:9083")     .enableHiveSupport()     .getOrCreate()

# Sekarang bisa query tabel Hive langsung dari Spark
spark.sql("SHOW DATABASES").show()
spark.sql("SELECT * FROM bigdata.sensor_data LIMIT 10").show()

# Atau buat tabel Hive dari DataFrame Spark
df = spark.read.csv("hdfs://namenode:9000/user/data/myfile.csv", header=True)
df.write.mode("overwrite").saveAsTable("bigdata.my_table")
```

### Upload Data ke HDFS lalu Baca via Hive

```bash
# 1. Salin file ke staging area
cp data.csv ./hadoop/

# 2. Upload ke HDFS
docker compose exec namenode hdfs dfs -mkdir -p /user/data/sensor
docker compose exec namenode hdfs dfs -put /home/hadoop/data.csv /user/data/sensor/

# 3. Registrasikan ke Hive (bisa via Beeline atau Spark)
```

### Troubleshooting Hive

**Metastore gagal start — koneksi ke PostgreSQL ditolak**

Pastikan `hive-postgres` sudah healthy sebelum `hive-metastore` start:

```bash
docker compose logs hive-postgres | tail -5
docker compose ps hive-postgres   # harus "healthy"
```

**`schematool` error saat `hive-init.sh`**

Jika schema sudah ada tapi corrupt, reset PostgreSQL:

```bash
docker compose stop hive-metastore hive-server2
docker compose rm -f hive-postgres
docker volume rm $(basename $(pwd))_hive_postgres_data
docker compose up -d hive-postgres
# Tunggu healthy, lalu jalankan ulang hive-init.sh
./hive-init.sh
```

**HiveServer2 tidak bisa akses HDFS**

Pastikan `core-site.xml` dan `hdfs-site.xml` di `./hadoop-config/` sudah ada dan `fs.defaultFS` menunjuk ke `hdfs://namenode:9000`.
