# =============================================================================
# setup.ps1 — Inisialisasi direktori untuk stack Big Data
# Kompatibel: Windows 10/11 dengan PowerShell 5.1+ atau PowerShell 7+
#
# Cara pakai (jalankan di PowerShell sebagai user biasa, bukan Administrator):
#   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#   .\setup.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# Warna helper
function Write-Ok   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Skip { param($msg) Write-Host "  [--] $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  [!!] $msg" -ForegroundColor Red }
function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Big Data Stack -- Setup Direktori" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Cek Docker tersedia
# -----------------------------------------------------------------------------
Write-Step "Memeriksa dependensi..."

try {
    $dockerVer = docker --version 2>&1
    Write-Ok "Docker: $dockerVer"
} catch {
    Write-Fail "Docker tidak ditemukan. Install Docker Desktop terlebih dahulu."
    Write-Host "         https://docs.docker.com/desktop/install/windows/" -ForegroundColor Gray
    exit 1
}

try {
    $composeVer = docker compose version --short 2>&1
    Write-Ok "Docker Compose: $composeVer"
} catch {
    Write-Fail "Docker Compose plugin tidak ditemukan."
    Write-Host "         Pastikan menggunakan Docker Desktop versi terbaru." -ForegroundColor Gray
    exit 1
}

# -----------------------------------------------------------------------------
# 2. Buat direktori
# -----------------------------------------------------------------------------
Write-Step "Membuat direktori..."

$dirs = @(
    @{ Path = "hadoop";        Desc = "Staging area HDFS (bind mount namenode & datanode)" },
    @{ Path = "hadoop-config"; Desc = "Config XML Hadoop & Hive yang di-mount ke container" },
    @{ Path = "notebooks";     Desc = "Direktori notebook Jupyter" }
)

foreach ($d in $dirs) {
    if (Test-Path $d.Path) {
        Write-Skip "'$($d.Path)' sudah ada, dilewati"
    } else {
        New-Item -ItemType Directory -Path $d.Path | Out-Null
        Write-Ok "Dibuat: .\$($d.Path)  — $($d.Desc)"
    }
}

# -----------------------------------------------------------------------------
# 3. Buat .gitignore di hadoop/
# -----------------------------------------------------------------------------
$gitignorePath = "hadoop\.gitignore"
if (-not (Test-Path $gitignorePath)) {
    @"
# Abaikan semua file di direktori staging HDFS ini
# kecuali file .gitignore itu sendiri
*
!.gitignore
"@ | Set-Content -Path $gitignorePath -Encoding UTF8
    Write-Ok "Dibuat: .\hadoop\.gitignore"
}

# -----------------------------------------------------------------------------
# 4. Verifikasi file konfigurasi
# -----------------------------------------------------------------------------
Write-Step "Memeriksa file konfigurasi..."

$requiredFiles = @(
    "docker-compose.yml",
    "Dockerfile.jupyter",
    "requirements.jupyter.txt",
    "hadoop-config\core-site.xml",
    "hadoop-config\hdfs-site.xml",
    "hadoop-config\hive-site.xml",
    "hdfs-init.sh",
    "hive-init.sh"
)

$allOk = $true
foreach ($f in $requiredFiles) {
    if (Test-Path $f) {
        Write-Ok $f
    } else {
        Write-Fail "$f tidak ditemukan"
        $allOk = $false
    }
}

if (-not $allOk) {
    Write-Host ""
    Write-Host "  [!!] Beberapa file konfigurasi tidak ditemukan." -ForegroundColor Yellow
    Write-Host "       Pastikan file berikut ada di direktori yang sama dengan setup.ps1:" -ForegroundColor Yellow
    Write-Host "       - docker-compose.yml" -ForegroundColor Gray
    Write-Host "       - Dockerfile.jupyter" -ForegroundColor Gray
    Write-Host "       - requirements.jupyter.txt" -ForegroundColor Gray
}

# -----------------------------------------------------------------------------
# 5. Cek WSL2 backend (opsional, hanya informasi)
# -----------------------------------------------------------------------------
Write-Step "Memeriksa konfigurasi Windows..."

$wslCheck = wsl --status 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Ok "WSL2 tersedia — Docker Desktop dapat menggunakan WSL2 backend (disarankan)"
} else {
    Write-Skip "WSL2 tidak terdeteksi — Docker akan menggunakan Hyper-V backend"
    Write-Host "         Untuk performa lebih baik, aktifkan WSL2:" -ForegroundColor Gray
    Write-Host "         https://docs.microsoft.com/en-us/windows/wsl/install" -ForegroundColor Gray
}

# Cek apakah path mengandung spasi (Docker bind mount kadang bermasalah)
$currentPath = (Get-Location).Path
if ($currentPath -match " ") {
    Write-Host ""
    Write-Host "  [!!] Path direktori mengandung spasi: $currentPath" -ForegroundColor Yellow
    Write-Host "       Bind mount Docker bisa bermasalah di Windows jika ada spasi di path." -ForegroundColor Yellow
    Write-Host "       Disarankan pindah ke path tanpa spasi, misal: C:\projects\bigdata" -ForegroundColor Gray
}

# -----------------------------------------------------------------------------
# 6. Instruksi langkah selanjutnya
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Setup selesai. Langkah selanjutnya:" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Build Jupyter image (hanya perlu sekali):" -ForegroundColor White
Write-Host "     docker compose build jupyter" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Jalankan stack:" -ForegroundColor White
Write-Host "     docker compose up -d" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. Inisialisasi HDFS (hanya sekali, setelah namenode up):" -ForegroundColor White
Write-Host "     bash hdfs-init.sh" -ForegroundColor Cyan
Write-Host "     (atau via WSL / Git Bash)" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Inisialisasi Hive (hanya sekali, setelah hdfs-init selesai):" -ForegroundColor White
Write-Host "     bash hive-init.sh" -ForegroundColor Cyan
Write-Host ""
Write-Host "  5. Akses UI:" -ForegroundColor White
Write-Host "     JupyterLab   -> http://localhost:8888" -ForegroundColor Cyan
Write-Host "     Spark UI     -> http://localhost:8081" -ForegroundColor Cyan
Write-Host "     Kafka UI     -> http://localhost:8080" -ForegroundColor Cyan
Write-Host "     HDFS UI      -> http://localhost:9870" -ForegroundColor Cyan
Write-Host "     Neo4j        -> http://localhost:7474" -ForegroundColor Cyan
Write-Host "     HiveServer2  -> http://localhost:10002" -ForegroundColor Cyan
Write-Host ""
Write-Host "  6. Upload file ke HDFS:" -ForegroundColor White
Write-Host "     Salin file ke .\hadoop\, lalu dari PowerShell:" -ForegroundColor Gray
Write-Host "     docker compose exec namenode hdfs dfs -put /home/hadoop/<file> /user/data/" -ForegroundColor Cyan
Write-Host ""
