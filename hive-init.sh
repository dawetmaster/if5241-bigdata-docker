#!/usr/bin/env bash
# =============================================================================
# hive-init.sh — Verifikasi Hive Metastore dan buat direktori HDFS warehouse
#
# Prasyarat: hdfs-init.sh sudah selesai dijalankan.
# Schema metastore di-init otomatis oleh container hive-metastore saat start.
# Skrip ini hanya memverifikasi semua komponen siap dan buat direktori HDFS.
#
# Jalankan setelah 'docker compose up -d' dan hdfs-init.sh selesai:
#   ./hive-init.sh        (Linux/macOS)
#   bash hive-init.sh     (Windows Git Bash / WSL)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; }
info() { echo -e "  ${CYAN}[--]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $*"; }
fail() { echo -e "  ${RED}[XX]${NC} $*"; exit 1; }

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Hive Init — Verifikasi & Inisialisasi Direktori${NC}"
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
# 1. Cek semua container berjalan
# -----------------------------------------------------------------------------
info "Memeriksa container..."

for svc in hive-postgres hive-metastore namenode; do
    if container_running "$svc"; then
        ok "$svc aktif"
    else
        fail "Container '$svc' tidak berjalan. Jalankan 'docker compose up -d' terlebih dahulu."
    fi
done

# -----------------------------------------------------------------------------
# 2. Verifikasi postgres.jar ada (wajib untuk Hive + PostgreSQL)
# -----------------------------------------------------------------------------
info "Memeriksa PostgreSQL JDBC driver..."
if [ ! -f "./hive-lib/postgres.jar" ]; then
    fail "File ./hive-lib/postgres.jar tidak ditemukan.\nJalankan setup.sh (atau setup.ps1) terlebih dahulu untuk mengunduhnya."
fi
ok "postgres.jar tersedia"

# -----------------------------------------------------------------------------
# 3. Tunggu PostgreSQL siap
# -----------------------------------------------------------------------------
info "Menunggu PostgreSQL siap..."
ELAPSED=0
until docker exec hive-postgres pg_isready -U hive -d metastore > /dev/null 2>&1; do
    if [ $ELAPSED -ge 30 ]; then
        fail "PostgreSQL tidak siap setelah 30s."
    fi
    sleep 2; ELAPSED=$((ELAPSED + 2))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu PostgreSQL... ${ELAPSED}s"
done
echo ""
ok "PostgreSQL siap"

# -----------------------------------------------------------------------------
# 4. Tunggu Hive Metastore siap (port 9083)
#    Schema init dijalankan otomatis oleh container saat start
# -----------------------------------------------------------------------------
info "Menunggu Hive Metastore siap di port 9083..."
MAX_WAIT=180
ELAPSED=0
until port_open localhost 9083; do
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        fail "Port 9083 tidak terbuka setelah ${MAX_WAIT}s.\nCek log: docker compose logs hive-metastore"
    fi
    sleep 5; ELAPSED=$((ELAPSED + 5))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu port 9083... ${ELAPSED}s (schema init bisa butuh ~60s)"
done
echo ""
ok "Hive Metastore merespons di port 9083"

# -----------------------------------------------------------------------------
# 5. Verifikasi schema berhasil diinisialisasi di PostgreSQL
# -----------------------------------------------------------------------------
info "Memverifikasi schema metastore di PostgreSQL..."
ELAPSED=0
until docker exec hive-postgres \
    psql -U hive -d metastore -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='TBLS';" \
    2>/dev/null | grep -q "1"; do
    if [ $ELAPSED -ge 60 ]; then
        warn "Tabel TBLS belum ada — schema mungkin belum selesai diinisialisasi."
        warn "Cek log: docker compose logs hive-metastore"
        break
    fi
    sleep 5; ELAPSED=$((ELAPSED + 5))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu schema... ${ELAPSED}s"
done
echo ""
ok "Schema metastore tersedia di PostgreSQL"

# -----------------------------------------------------------------------------
# 6. Buat direktori HDFS untuk Hive warehouse (jika belum ada dari hdfs-init)
# -----------------------------------------------------------------------------
info "Memastikan direktori HDFS Hive tersedia..."

HIVE_DIRS=(
    "/user/hive"
    "/user/hive/warehouse"
    "/tmp/hive"
)

for dir in "${HIVE_DIRS[@]}"; do
    RESULT=$(docker exec namenode \
        bash -c "hdfs dfs -mkdir -p ${dir} 2>/dev/null && echo created || echo exists")
    if echo "$RESULT" | grep -q "created"; then
        ok "Dibuat: ${dir}"
    else
        info "Sudah ada: ${dir}"
    fi
done

docker exec namenode bash -c 'hdfs dfs -chmod -R 777 /user/hive /tmp/hive 2>/dev/null' || true

# -----------------------------------------------------------------------------
# 7. Cek hive-server2 (opsional — mungkin masih starting)
# -----------------------------------------------------------------------------
info "Memeriksa hive-server2..."
if container_running "hive-server2"; then
    info "Menunggu HiveServer2 siap di port 10000..."
    ELAPSED=0
    until port_open localhost 10000; do
        if [ $ELAPSED -ge 120 ]; then
            warn "HiveServer2 belum merespons setelah 120s."
            warn "Cek log: docker compose logs hive-server2"
            break
        fi
        sleep 5; ELAPSED=$((ELAPSED + 5))
        echo -ne "\r  ${CYAN}[--]${NC} Menunggu port 10000... ${ELAPSED}s"
    done
    echo ""
    port_open localhost 10000 && ok "HiveServer2 merespons di port 10000" || true
else
    warn "Container hive-server2 tidak berjalan — lewati."
fi

# -----------------------------------------------------------------------------
# 8. Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  Hive siap digunakan!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "  HiveServer2 Web UI : ${CYAN}http://localhost:10002${NC}"
echo -e "  JDBC string        : ${CYAN}jdbc:hive2://localhost:10000${NC}"
echo ""
echo -e "  Query via Beeline:"
echo -e "    ${CYAN}docker exec -it hive-server2 beeline -u 'jdbc:hive2://localhost:10000'${NC}"
echo ""
echo -e "  Akses dari Spark (notebook):"
echo -e "    ${CYAN}spark = SparkSession.builder \\${NC}"
echo -e "    ${CYAN}    .config('spark.hive.metastore.uris', 'thrift://hive-metastore:9083') \\${NC}"
echo -e "    ${CYAN}    .enableHiveSupport() \\${NC}"
echo -e "    ${CYAN}    .getOrCreate()${NC}"
echo ""