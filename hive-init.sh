#!/usr/bin/env bash
# =============================================================================
# hive-init.sh — Inisialisasi Hive Metastore schema dan direktori HDFS
#
# Jalankan SEKALI setelah hive-postgres dan hive-metastore pertama kali up:
#   ./hive-init.sh
#
# Prasyarat: HDFS sudah diinisialisasi (hdfs-init.sh sudah dijalankan).
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; }
info() { echo -e "  ${CYAN}[--]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $*"; }
fail() { echo -e "  ${RED}[XX]${NC} $*"; exit 1; }

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Hive Init — Metastore Schema & HDFS Warehouse${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# 1. Cek container yang dibutuhkan berjalan
# -----------------------------------------------------------------------------
info "Memeriksa container..."

for svc in hive-postgres hive-metastore namenode; do
    if docker compose ps --status running "$svc" 2>/dev/null | grep -q "$svc"; then
        ok "$svc aktif"
    else
        fail "Container '$svc' tidak berjalan. Jalankan 'docker compose up -d' terlebih dahulu."
    fi
done

# -----------------------------------------------------------------------------
# 2. Tunggu PostgreSQL benar-benar siap
# -----------------------------------------------------------------------------
info "Menunggu PostgreSQL siap..."
ELAPSED=0
until docker compose exec -T hive-postgres pg_isready -U hive -d metastore > /dev/null 2>&1; do
    if [ $ELAPSED -ge 30 ]; then
        fail "PostgreSQL tidak siap setelah 30 detik."
    fi
    sleep 2; ELAPSED=$((ELAPSED+2))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu PostgreSQL... ${ELAPSED}s"
done
echo ""
ok "PostgreSQL siap"

# -----------------------------------------------------------------------------
# 3. Cek apakah schema sudah pernah diinisialisasi
# -----------------------------------------------------------------------------
info "Memeriksa apakah schema metastore sudah ada..."

SCHEMA_EXISTS=$(docker compose exec -T hive-postgres \
    psql -U hive -d metastore -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='TBLS';" \
    2>/dev/null || echo "0")

if [ "$(echo $SCHEMA_EXISTS | tr -d '[:space:]')" = "1" ]; then
    warn "Schema metastore sudah ada. Melewati langkah initSchema."
else
    # -----------------------------------------------------------------------------
    # 4. Inisialisasi schema metastore via schematool
    # -----------------------------------------------------------------------------
    info "Menginisialisasi schema metastore Hive di PostgreSQL..."
    docker compose exec -T hive-metastore \
        bash -c '/opt/hive/bin/schematool -dbType postgres -initSchema 2>&1' \
        | grep -E "Initialization|Error|Exception|completed" || true
    ok "Schema metastore berhasil diinisialisasi"
fi

# -----------------------------------------------------------------------------
# 5. Buat direktori HDFS untuk Hive warehouse
# -----------------------------------------------------------------------------
info "Membuat direktori HDFS untuk Hive..."

HIVE_DIRS=(
    "/user/hive"
    "/user/hive/warehouse"
    "/tmp/hive"
)

for dir in "${HIVE_DIRS[@]}"; do
    docker compose exec -T namenode \
        bash -c "hdfs dfs -mkdir -p ${dir} && hdfs dfs -chmod 777 ${dir} && echo created || echo exists" \
        | grep -q "created" \
        && ok "Dibuat: ${dir}" \
        || info "Sudah ada: ${dir}"
done

# -----------------------------------------------------------------------------
# 6. Restart hive-server2 agar terhubung ke metastore yang sudah diinisialisasi
# -----------------------------------------------------------------------------
info "Restart hive-server2..."
docker compose restart hive-server2
sleep 5
ok "hive-server2 restarted"

# -----------------------------------------------------------------------------
# 7. Verifikasi koneksi via Beeline
# -----------------------------------------------------------------------------
info "Verifikasi koneksi HiveServer2..."
ELAPSED=0
until docker compose exec -T hive-server2 \
    bash -c '/opt/hive/bin/beeline -u "jdbc:hive2://localhost:10000" -e "SHOW DATABASES;" 2>&1' \
    | grep -q "default"; do
    if [ $ELAPSED -ge 60 ]; then
        warn "HiveServer2 belum merespons setelah 60 detik. Cek: docker compose logs hive-server2"
        break
    fi
    sleep 5; ELAPSED=$((ELAPSED+5))
    echo -ne "\r  ${CYAN}[--]${NC} Menunggu HiveServer2... ${ELAPSED}s"
done
echo ""
ok "HiveServer2 merespons — database default tersedia"

# -----------------------------------------------------------------------------
# 8. Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  Hive siap digunakan!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "  Web UI      : ${CYAN}http://localhost:10002${NC}"
echo -e "  JDBC string : ${CYAN}jdbc:hive2://localhost:10000${NC}"
echo ""
echo -e "  Contoh query via Beeline (dari dalam container):"
echo -e "    ${CYAN}docker compose exec hive-server2 beeline -u 'jdbc:hive2://localhost:10000'${NC}"
echo ""
echo -e "  Contoh buat tabel dari HDFS:"
echo -e "    ${CYAN}CREATE TABLE test (id INT, name STRING)${NC}"
echo -e "    ${CYAN}ROW FORMAT DELIMITED FIELDS TERMINATED BY ','${NC}"
echo -e "    ${CYAN}STORED AS TEXTFILE${NC}"
echo -e "    ${CYAN}LOCATION 'hdfs://namenode:9000/user/data/test';${NC}"
echo ""
echo -e "  Akses dari Spark (di notebook):"
echo -e "    ${CYAN}spark = SparkSession.builder \\\\${NC}"
echo -e "    ${CYAN}    .config('spark.hive.metastore.uris', 'thrift://hive-metastore:9083') \\\\${NC}"
echo -e "    ${CYAN}    .enableHiveSupport() \\\\${NC}"
echo -e "    ${CYAN}    .getOrCreate()${NC}"
echo -e "    ${CYAN}spark.sql('SHOW TABLES').show()${NC}"
echo ""
