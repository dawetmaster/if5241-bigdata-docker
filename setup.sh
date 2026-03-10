#!/usr/bin/env bash
# =============================================================================
# setup.sh — Inisialisasi direktori untuk stack Big Data
# Kompatibel: Linux, macOS (bash/zsh)
#
# Cara pakai:
#   chmod +x setup.sh
#   ./setup.sh
# =============================================================================

set -euo pipefail

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CHECKMARK="${GREEN}✓${NC}"
ARROW="${CYAN}→${NC}"

echo ""
echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}  Big Data Stack — Setup Direktori${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# 1. Cek Docker tersedia
# -----------------------------------------------------------------------------
echo -e "${ARROW} Memeriksa dependensi..."

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker tidak ditemukan. Install Docker terlebih dahulu.${NC}"
    echo "  https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "  ${CHECKMARK} Docker: $(docker --version)"

if ! docker compose version &> /dev/null; then
    echo -e "${RED}✗ Docker Compose plugin tidak ditemukan.${NC}"
    echo "  Pastikan menggunakan Docker Desktop atau install plugin Compose."
    exit 1
fi
echo -e "  ${CHECKMARK} Docker Compose: $(docker compose version --short)"
echo ""

# -----------------------------------------------------------------------------
# 2. Buat direktori
# -----------------------------------------------------------------------------
echo -e "${ARROW} Membuat direktori..."

DIRS=(
    "hadoop"           # bind mount namenode & datanode — staging area HDFS
    "hadoop-config"    # config XML Hadoop & Hive yang di-mount ke container
    "notebooks"        # bind mount Jupyter — tempat menyimpan .ipynb
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "  ${YELLOW}⚠ '$dir' sudah ada, dilewati${NC}"
    else
        mkdir -p "$dir"
        echo -e "  ${CHECKMARK} Dibuat: ./$dir"
    fi
done
echo ""

# -----------------------------------------------------------------------------
# 3. Buat .gitignore di hadoop/ agar data tidak ikut ter-commit
# -----------------------------------------------------------------------------
if [ ! -f "hadoop/.gitignore" ]; then
    cat > hadoop/.gitignore << 'EOF'
# Abaikan semua file di direktori staging HDFS ini
# kecuali file .gitignore itu sendiri
*
!.gitignore
EOF
    echo -e "  ${CHECKMARK} Dibuat: ./hadoop/.gitignore"
fi

# -----------------------------------------------------------------------------
# 4. Verifikasi file yang dibutuhkan ada
# -----------------------------------------------------------------------------
echo -e "${ARROW} Memeriksa file konfigurasi..."

REQUIRED_FILES=(
    "docker-compose.yml"
    "Dockerfile.jupyter"
    "requirements.jupyter.txt"
    "hadoop-config/core-site.xml"
    "hadoop-config/hdfs-site.xml"
    "hadoop-config/hive-site.xml"
    "hdfs-init.sh"
    "hive-init.sh"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
    if [ -f "$f" ]; then
        echo -e "  ${CHECKMARK} $f"
    else
        echo -e "  ${RED}✗ $f tidak ditemukan${NC}"
        ALL_OK=false
    fi
done
echo ""

if [ "$ALL_OK" = false ]; then
    echo -e "${YELLOW}⚠ Beberapa file konfigurasi tidak ditemukan.${NC}"
    echo "  Pastikan semua file berikut ada di direktori yang sama dengan setup.sh:"
    echo "  - docker-compose.yml"
    echo "  - Dockerfile.jupyter"
    echo "  - requirements.jupyter.txt"
    echo ""
fi

# -----------------------------------------------------------------------------
# 5. Instruksi langkah selanjutnya
# -----------------------------------------------------------------------------
echo -e "${CYAN}=================================================================${NC}"
echo -e "${GREEN}  Setup selesai. Langkah selanjutnya:${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo ""
echo -e "  1. Build Jupyter image (hanya perlu sekali):"
echo -e "     ${CYAN}docker compose build jupyter${NC}"
echo ""
echo -e "  2. Jalankan stack:"
echo -e "     ${CYAN}docker compose up -d${NC}"
echo ""
echo -e "  3. Inisialisasi HDFS (hanya sekali, setelah namenode up):"
echo -e "     ${CYAN}chmod +x hdfs-init.sh && ./hdfs-init.sh${NC}"
echo ""
echo -e "  4. Inisialisasi Hive (hanya sekali, setelah hdfs-init selesai):"
echo -e "     ${CYAN}chmod +x hive-init.sh && ./hive-init.sh${NC}"
echo ""
echo -e "  5. Akses UI:"
echo -e "     JupyterLab   → ${CYAN}http://localhost:8888${NC}"
echo -e "     Spark UI     → ${CYAN}http://localhost:8081${NC}"
echo -e "     Kafka UI     → ${CYAN}http://localhost:8080${NC}"
echo -e "     HDFS UI      → ${CYAN}http://localhost:9870${NC}"
echo -e "     Neo4j        → ${CYAN}http://localhost:7474${NC}"
echo -e "     HiveServer2  → ${CYAN}http://localhost:10002${NC}"
echo ""
echo -e "  6. Upload file ke HDFS:"
echo -e "     Salin file ke ${CYAN}./hadoop/${NC}, lalu dari dalam container:"
echo -e "     ${CYAN}docker compose exec namenode hdfs dfs -put /home/hadoop/<file> /user/data/${NC}"
echo ""
