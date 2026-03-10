#!/usr/bin/env bash
# =============================================================================
# hdfs-init.sh — Format HDFS dan buat struktur direktori awal
#
# Jalankan SEKALI setelah namenode dan datanode pertama kali up:
#   ./hdfs-init.sh          (Linux/macOS)
#   bash hdfs-init.sh       (Windows Git Bash / WSL)
#
# Aman dijalankan ulang — cek apakah HDFS sudah pernah di-format sebelumnya.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; }
info() { echo -e "  ${CYAN}[--]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $*"; }
fail() { echo -e "  ${RED}[XX]${NC} $*"; exit 1; }

NAMENODE_CONTAINER="bigdata-namenode-1"   # nama container docker compose (compose v2 pakai project-service-N)

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  HDFS Init — Format & Buat Direktori${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# 1. Cek namenode container berjalan
# -----------------------------------------------------------------------------
info "Memeriksa namenode container..."

if ! docker compose ps --status running namenode 2>/dev/null | grep -q "namenode"; then
    fail "Container namenode tidak berjalan. Jalankan 'docker compose up -d' terlebih dahulu."
fi
ok "Namenode container aktif"

# -----------------------------------------------------------------------------
# 2. Tunggu NameNode siap (port 9870 Web UI)
# -----------------------------------------------------------------------------
info "Menunggu NameNode Web UI siap di port 9870..."
MAX_WAIT=60
ELAPSED=0
until docker compose exec -T namenode curl -sf http://localhost:9870 > /dev/null 2>&1; do
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        fail "NameNode tidak merespons setelah ${MAX_WAIT} detik. Cek log: docker compose logs namenode"
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu... ${ELAPSED}s"
done
echo ""
ok "NameNode Web UI merespons"

# -----------------------------------------------------------------------------
# 3. Cek apakah HDFS sudah pernah di-format (ada fsimage)
# -----------------------------------------------------------------------------
info "Memeriksa apakah HDFS sudah pernah di-format..."

ALREADY_FORMATTED=$(docker compose exec -T namenode \
    bash -c 'ls /tmp/hadoop-data/namenode/current/fsimage_0000000000000000000 2>/dev/null && echo yes || echo no')

if echo "$ALREADY_FORMATTED" | grep -q "yes"; then
    warn "HDFS sudah pernah di-format. Melewati langkah format."
    warn "Jika ingin format ulang (DATA HILANG): docker compose down -v lalu jalankan ulang skrip ini."
else
    # -----------------------------------------------------------------------------
    # 4. Format NameNode
    # -----------------------------------------------------------------------------
    info "Memformat HDFS NameNode..."
    docker compose exec -T namenode \
        bash -c 'hdfs namenode -format -nonInteractive -force 2>&1' | tail -5
    ok "Format selesai"
fi

# Restart namenode agar membaca fsimage baru (jika baru saja di-format)
info "Restart namenode untuk membaca state terbaru..."
docker compose restart namenode
sleep 8

# -----------------------------------------------------------------------------
# 5. Tunggu DataNode terhubung ke NameNode
# -----------------------------------------------------------------------------
info "Menunggu DataNode terhubung ke NameNode..."
ELAPSED=0
until docker compose exec -T namenode \
    bash -c 'hdfs dfsadmin -report 2>/dev/null | grep -q "Live datanodes"'; do
    if [ $ELAPSED -ge 60 ]; then
        warn "DataNode belum terhubung setelah 60 detik."
        warn "Cek: docker compose logs datanode"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu DataNode... ${ELAPSED}s"
done
echo ""

LIVE=$(docker compose exec -T namenode \
    bash -c 'hdfs dfsadmin -report 2>/dev/null | grep "Live datanodes" | grep -o "[0-9]*"' || echo "0")
ok "DataNode terhubung: ${LIVE} node"

# -----------------------------------------------------------------------------
# 6. Buat struktur direktori awal di HDFS
# -----------------------------------------------------------------------------
info "Membuat struktur direktori HDFS..."

HDFS_DIRS=(
    "/user"
    "/user/root"
    "/user/data"
    "/tmp"
    "/data/raw"
    "/data/processed"
)

for dir in "${HDFS_DIRS[@]}"; do
    docker compose exec -T namenode \
        bash -c "hdfs dfs -mkdir -p ${dir} 2>/dev/null && echo created || echo exists" | grep -q "created" \
        && ok "Dibuat: ${dir}" \
        || info "Sudah ada: ${dir}"
done

# Beri permission terbuka untuk eksperimen
docker compose exec -T namenode bash -c 'hdfs dfs -chmod -R 777 / 2>/dev/null' || true

# -----------------------------------------------------------------------------
# 7. Verifikasi akhir
# -----------------------------------------------------------------------------
echo ""
info "Verifikasi struktur HDFS:"
docker compose exec -T namenode bash -c 'hdfs dfs -ls /' 2>/dev/null | sed 's/^/     /'

echo ""
info "Laporan cluster:"
docker compose exec -T namenode bash -c 'hdfs dfsadmin -report 2>/dev/null | head -20' | sed 's/^/     /'

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  HDFS siap digunakan!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "  Web UI   : ${CYAN}http://localhost:9870${NC}"
echo ""
echo -e "  Contoh perintah:"
echo -e "  Upload file ke HDFS:"
echo -e "    ${CYAN}cp myfile.csv ./hadoop/${NC}                               # salin ke staging"
echo -e "    ${CYAN}docker compose exec namenode hdfs dfs -put /home/hadoop/myfile.csv /user/data/${NC}"
echo ""
echo -e "  List file di HDFS:"
echo -e "    ${CYAN}docker compose exec namenode hdfs dfs -ls /user/data/${NC}"
echo ""
echo -e "  Dari notebook Spark:"
echo -e "    ${CYAN}df = spark.read.csv('hdfs://namenode:9000/user/data/myfile.csv')${NC}"
echo ""
