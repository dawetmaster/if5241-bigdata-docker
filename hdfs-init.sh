#!/usr/bin/env bash
# =============================================================================
# hdfs-init.sh — Buat struktur direktori awal di HDFS
#
# Format NameNode sudah ditangani otomatis oleh docker-compose.yml saat
# container pertama kali start. Skrip ini hanya membuat direktori HDFS
# dan memverifikasi cluster siap digunakan.
#
# Jalankan setelah 'docker compose up -d':
#   ./hdfs-init.sh        (Linux/macOS)
#   bash hdfs-init.sh     (Windows Git Bash / WSL)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; }
info() { echo -e "  ${CYAN}[--]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $*"; }
fail() { echo -e "  ${RED}[XX]${NC} $*"; exit 1; }

NAMENODE="namenode"
DATANODE="datanode"

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  HDFS Init — Inisialisasi Direktori${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Helper: cek container running via docker inspect
# -----------------------------------------------------------------------------
container_running() {
    local state
    state=$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null || echo "false")
    [ "$state" = "true" ]
}

# -----------------------------------------------------------------------------
# Helper: cek port dari HOST via bash built-in /dev/tcp
# -----------------------------------------------------------------------------
port_open() {
    (echo > /dev/tcp/"$1"/"$2") 2>/dev/null
}

# -----------------------------------------------------------------------------
# 1. Cek namenode container berjalan
# -----------------------------------------------------------------------------
info "Memeriksa container namenode..."
if ! container_running "$NAMENODE"; then
    fail "Container '$NAMENODE' tidak berjalan. Jalankan 'docker compose up -d' terlebih dahulu."
fi
ok "Container namenode aktif"

# -----------------------------------------------------------------------------
# 2. Tunggu NameNode siap — cek port 9870 dari host
# -----------------------------------------------------------------------------
info "Menunggu NameNode siap di port 9870..."
MAX_WAIT=120
ELAPSED=0
until port_open localhost 9870; do
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        fail "Port 9870 tidak terbuka setelah ${MAX_WAIT}s. Cek: docker compose logs namenode"
    fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu port 9870... ${ELAPSED}s"
done
echo ""
ok "NameNode merespons di port 9870"

# -----------------------------------------------------------------------------
# 3. Tunggu NameNode keluar dari safemode
#    (NameNode masuk safemode saat startup — tidak bisa mkdir sebelum keluar)
# -----------------------------------------------------------------------------
info "Menunggu NameNode keluar dari safemode..."
ELAPSED=0
until docker exec "$NAMENODE" \
    bash -c 'hdfs dfsadmin -safemode get 2>/dev/null | grep -q "OFF"'; do
    if [ $ELAPSED -ge 120 ]; then
        warn "NameNode masih dalam safemode setelah 120s, coba paksa keluar..."
        docker exec "$NAMENODE" bash -c 'hdfs dfsadmin -safemode leave 2>/dev/null' || true
        break
    fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu safemode OFF... ${ELAPSED}s"
done
echo ""
ok "NameNode siap (safemode OFF)"

# -----------------------------------------------------------------------------
# 4. Tunggu DataNode terhubung
# -----------------------------------------------------------------------------
info "Memeriksa container datanode..."
if ! container_running "$DATANODE"; then
    warn "Container '$DATANODE' tidak berjalan — lewati pengecekan DataNode."
else
    info "Menunggu DataNode register ke NameNode..."
    ELAPSED=0
    until docker exec "$NAMENODE" \
        bash -c 'hdfs dfsadmin -report 2>/dev/null | grep -q "Live datanodes (1)"'; do
        if [ $ELAPSED -ge 90 ]; then
            warn "DataNode belum terhubung setelah 90s. Cek: docker compose logs datanode"
            break
        fi
        sleep 3; ELAPSED=$((ELAPSED + 3))
        echo -ne "\r  ${CYAN}[--]${NC} Menunggu DataNode... ${ELAPSED}s"
    done
    echo ""

    LIVE=$(docker exec "$NAMENODE" \
        bash -c 'hdfs dfsadmin -report 2>/dev/null | grep -oP "Live datanodes \(\K[0-9]+"' \
        2>/dev/null || echo "0")
    ok "DataNode terhubung: ${LIVE:-0} node"
fi

# -----------------------------------------------------------------------------
# 5. Buat struktur direktori awal di HDFS
# -----------------------------------------------------------------------------
info "Membuat struktur direktori HDFS..."

HDFS_DIRS=(
    "/user"
    "/user/root"
    "/user/data"
    "/user/hive"
    "/user/hive/warehouse"
    "/tmp"
    "/data/raw"
    "/data/processed"
)

for dir in "${HDFS_DIRS[@]}"; do
    RESULT=$(docker exec "$NAMENODE" \
        bash -c "hdfs dfs -mkdir -p ${dir} 2>/dev/null && echo created || echo exists")
    if echo "$RESULT" | grep -q "created"; then
        ok "Dibuat: ${dir}"
    else
        info "Sudah ada: ${dir}"
    fi
done

docker exec "$NAMENODE" bash -c 'hdfs dfs -chmod -R 777 / 2>/dev/null' || true
ok "Permission 777 diterapkan"

# -----------------------------------------------------------------------------
# 6. Verifikasi akhir
# -----------------------------------------------------------------------------
echo ""
info "Struktur HDFS:"
docker exec "$NAMENODE" bash -c 'hdfs dfs -ls /' 2>/dev/null | sed 's/^/     /' || true

echo ""
info "Laporan cluster:"
docker exec "$NAMENODE" bash -c 'hdfs dfsadmin -report 2>/dev/null | head -15' | sed 's/^/     /' || true

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  HDFS siap digunakan!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "  Web UI    : ${CYAN}http://localhost:9870${NC}"
echo ""
echo -e "  Upload file ke HDFS:"
echo -e "    ${CYAN}cp myfile.csv ./hadoop/${NC}                                 # salin ke staging"
echo -e "    ${CYAN}docker exec namenode hdfs dfs -put /home/hadoop/myfile.csv /user/data/${NC}"
echo ""
echo -e "  List file:"
echo -e "    ${CYAN}docker exec namenode hdfs dfs -ls /user/data/${NC}"
echo ""
echo -e "  Dari notebook Spark:"
echo -e "    ${CYAN}df = spark.read.csv('hdfs://namenode:9000/user/data/myfile.csv')${NC}"
echo ""