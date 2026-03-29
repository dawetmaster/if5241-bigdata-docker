# Stack Big Data (IF4044/IF5241) Edisi 2026 dengan Docker

## Shoutout

Apresiasi ke @julianchandras untuk pengajuan fix-nya <3

## Permulaan

> AI Disclosure: Ini dibuat bersama dengan Claude Sonnet 4.6

Stack lengkap untuk praktikum Big Data berbasis Docker Compose, mencakup HDFS, Kafka, Spark, Jupyter, Hive, dan Neo4j — siap pakai di amd64 maupun arm64 (Apple Silicon, Snapdragon).

---

## Komponen

| Service | Versi | Port | Keterangan |
|---|---|---|---|
| HDFS NameNode | Hadoop 3.4.1 | `9870`, `9000` | Distributed filesystem + Web UI |
| HDFS DataNode | Hadoop 3.4.1 | — | Penyimpanan blok data |
| Kafka | 4.1.1 (KRaft) | `9092`, `29092` | Message broker, tanpa ZooKeeper |
| Kafka UI | latest | `8080` | Web UI monitoring topic & offset |
| Spark Master | 3.5.1 | `8081`, `7077` | Cluster manager + Web UI |
| Spark Worker | 3.5.1 | — | Eksekutor job Spark |
| JupyterLab | custom build | `8888` | Notebook berbasis Spark 3.5.1 |
| Hive Metastore | 4.0.1 | `9083` | Thrift server metadata tabel |
| HiveServer2 | 4.0.1 | `10000`, `10002` | JDBC endpoint + Web UI |
| PostgreSQL | 16 | `5432` | Backend metastore Hive |
| Neo4j | 5 | `7474`, `7687` | Graph database + Browser |

---

## Struktur File

```
project/
├── Readme.md
├── docker-compose.yml
├── Dockerfile.jupyter
├── requirements.jupyter.txt
├── setup.sh                    # Setup direktori (Linux/macOS)
├── setup.ps1                   # Setup direktori (Windows)
├── hdfs-init.sh                # Inisialisasi HDFS (jalankan sekali)
├── hive-init.sh                # Inisialisasi Hive metastore (jalankan sekali)
├── hadoop-config/
│   ├── core-site.xml           # fs.defaultFS → hdfs://namenode:9000
│   ├── hdfs-site.xml           # replication, data dir, permission
│   └── hive-site.xml           # metastore URI, warehouse dir, PostgreSQL conn
├── hadoop/                     # Staging area host ↔ HDFS (dibuat oleh setup)
└── notebooks/                  # Notebook Jupyter (dibuat oleh setup)
```

---

## Quick Start

### 1. Jalankan setup

```bash
# Linux / macOS
chmod +x setup.sh && ./setup.sh

# Windows (PowerShell)
.\setup.ps1
```

Skrip ini membuat direktori yang diperlukan dan memverifikasi semua file wajib ada.

### 2. Build Jupyter image

Hanya perlu sekali, atau setelah `requirements.jupyter.txt` diubah:

```bash
docker compose build jupyter
```

### 3. Jalankan stack

```bash
docker compose up -d
```

### 4. Inisialisasi HDFS

Jalankan sekali setelah pertama kali `up`:

```bash
chmod +x hdfs-init.sh && ./hdfs-init.sh
```

### 5. Inisialisasi Hive

Jalankan sekali setelah `hdfs-init.sh` selesai:

```bash
chmod +x hive-init.sh && ./hive-init.sh
```

### 6. Akses UI

| UI | URL | Kredensial |
|---|---|---|
| JupyterLab | http://localhost:8888 | — |
| Spark Master | http://localhost:8081 | — |
| Kafka UI | http://localhost:8080 | — |
| HDFS NameNode | http://localhost:9870 | — |
| HiveServer2 | http://localhost:10002 | — |
| Neo4j Browser | http://localhost:7474 | `neo4j` / `IF5241-bigdata` |

---

## Panduan Lengkap

Lihat **[Guides.md](Guides.md)** untuk dokumentasi lengkap mencakup:
- Operasional sehari-hari (start, stop, logs, restart)
- Menjalankan notebook Spark Streaming
- Menggunakan Kafka producer
- Integrasi Hive dengan Spark
- Aturan version alignment Spark
- Troubleshooting lengkap
- Cara upgrade komponen
- Reset bersih

---

## Reset Bersih

> ⚠️ Semua data HDFS, Kafka, Hive, dan Neo4j akan terhapus permanen.

```bash
docker compose down -v
rm -rf notebooks/.spark_checkpoint
docker compose build jupyter
docker compose up -d
./hdfs-init.sh
./hive-init.sh
```
