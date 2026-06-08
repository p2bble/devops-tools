#!/usr/bin/env bash
# USB 자산 수집 스크립트 (Ubuntu/Linux)
# 실행: sudo bash collect.sh
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "sudo가 필요합니다. 'sudo bash collect.sh' 로 실행해주세요."
    exit 1
fi

HOSTNAME=$(hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/../results"
mkdir -p "$RESULTS_DIR"

# config.txt 에서 RESULTS_PATH 읽기 (없으면 로컬 results/ 사용)
CONFIG_FILE="$SCRIPT_DIR/../config.txt"
if [[ -f "$CONFIG_FILE" ]]; then
    cfg_path=$(grep "^RESULTS_PATH=" "$CONFIG_FILE" | cut -d= -f2- | xargs)
    [[ -n "$cfg_path" ]] && RESULTS_DIR="$cfg_path"
fi
mkdir -p "$RESULTS_DIR"

RAW="$RESULTS_DIR/${HOSTNAME}_${TIMESTAMP}_raw.txt"
CSV="$RESULTS_DIR/${HOSTNAME}_${TIMESTAMP}.csv"

log() { echo "$1" | tee -a "$RAW"; }

log "=========================================="
log " 자산 수집 시작: $HOSTNAME  [$TIMESTAMP]"
log "=========================================="

# ── OS ──────────────────────────────────────────────────────────────────────
log ""
log "[OS]"
OS_PRETTY=$(grep ^PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VERSION=$(grep ^VERSION_ID  /etc/os-release | cut -d= -f2 | tr -d '"')
log "  $OS_PRETTY (Version: $OS_VERSION)"

# ── 메인보드 ─────────────────────────────────────────────────────────────────
log ""
log "[메인보드]"
BOARD_MFR=$(dmidecode -t baseboard | awk -F': ' '/Manufacturer/{print $2}' | head -1 | xargs)
BOARD_PROD=$(dmidecode -t baseboard | awk -F': ' '/Product Name/{print $2}' | head -1 | xargs)
BOARD_SN=$(dmidecode -t baseboard  | awk -F': ' '/Serial Number/{print $2}' | head -1 | xargs)
log "  제조사: $BOARD_MFR"
log "  모델:   $BOARD_PROD"
log "  S/N:    $BOARD_SN"

# ── CPU ──────────────────────────────────────────────────────────────────────
log ""
log "[CPU]"
CPU_MODEL=$(lscpu | awk -F': +' '/Model name/{print $2}' | head -1 | xargs)
log "  $CPU_MODEL"

# ── GPU ──────────────────────────────────────────────────────────────────────
log ""
log "[GPU]"
GPU_NAMES=()
GPU_SERIALS=()
GPU_UUIDS=()

# 1단계: nvidia-smi로 NVIDIA GPU 상세 수집 (S/N, UUID)
NVIDIA_COUNT=0
if command -v nvidia-smi &>/dev/null; then
    while IFS=',' read -r name serial uuid; do
        name=$(echo "$name" | xargs); serial=$(echo "$serial" | xargs); uuid=$(echo "$uuid" | xargs)
        GPU_NAMES+=("$name"); GPU_SERIALS+=("$serial"); GPU_UUIDS+=("$uuid")
        NVIDIA_COUNT=$((NVIDIA_COUNT+1))
        log "  [nvidia-smi] $name | S/N: $serial | UUID: $uuid"
    done < <(nvidia-smi --query-gpu=name,serial,uuid --format=csv,noheader 2>/dev/null)
fi

# 2단계: lspci로 전체 GPU 감지 → NVIDIA는 nvidia-smi가 이미 잡았으면 스킵
# (NVIDIA Optimus 노트북은 "3D controller"로 분류되어 "VGA"로는 안 잡힘)
while IFS= read -r line; do
    gpu_name=$(echo "$line" | cut -d: -f3- | xargs | sed 's/ (rev [0-9a-f][0-9a-f]*)$//')
    if echo "$line" | grep -qi "3d controller"; then
        pci_class="3D controller"
    else
        pci_class="VGA"
    fi
    if echo "$gpu_name" | grep -qi "nvidia" && [[ $NVIDIA_COUNT -gt 0 ]]; then
        continue  # nvidia-smi로 이미 수집됨
    fi
    GPU_NAMES+=("$gpu_name"); GPU_SERIALS+=("N/A"); GPU_UUIDS+=("N/A")
    log "  [lspci/$pci_class] $gpu_name | S/N: N/A | UUID: N/A"
done < <(lspci 2>/dev/null | grep -Ei "vga|3d controller|display controller")

[[ ${#GPU_NAMES[@]} -eq 0 ]] && log "  GPU 정보 없음"

# ── 스토리지 ──────────────────────────────────────────────────────────────────
log ""
log "[SSD/HDD]"
DISK_MODELS=()
DISK_SERIALS=()
DISK_SIZES=()
DISK_TYPES=()

# -P 옵션으로 KEY="VALUE" 형식 출력 → 모델명에 공백이 있어도 안전하게 파싱
while IFS= read -r line; do
    eval "$line"   # NAME MODEL SERIAL SIZE ROTA TYPE 변수로 바인딩
    [[ "${TYPE:-}" != "disk" ]] && continue
    disk_type="SSD"
    [[ "${ROTA:-0}" == "1" ]] && disk_type="HDD"
    DISK_MODELS+=("${MODEL:-}")
    DISK_SERIALS+=("${SERIAL:-}")
    DISK_SIZES+=("${SIZE:-}")
    DISK_TYPES+=("$disk_type")
    log "  [$disk_type] ${MODEL:-}  S/N: ${SERIAL:-}  Size: ${SIZE:-}"
done < <(lsblk -d -P -o NAME,MODEL,SERIAL,SIZE,ROTA,TYPE 2>/dev/null)

# ── RAM ───────────────────────────────────────────────────────────────────────
log ""
log "[RAM]"
RAM_TOTAL=$(free -h | awk '/^Mem/{print $2}')
log "  총량: $RAM_TOTAL"

RAM_MFRS=()
RAM_SIZES_M=()
RAM_PARTS=()
RAM_SERIALS=()

# dmidecode 출력은 탭 들여쓰기 → 라인별로 공백 제거 후 파싱
_save_ram_slot() {
    [[ -z "${_cur_size:-}" ]] && return
    [[ "$_cur_size" == "No Module Installed" || "$_cur_size" == "Unknown" ]] && return
    RAM_SIZES_M+=("$_cur_size")
    RAM_MFRS+=("${_cur_mfr:-}")
    RAM_PARTS+=("${_cur_part:-}")
    RAM_SERIALS+=("${_cur_sn:-}")
    log "  슬롯: ${_cur_mfr:-} ${_cur_part:-}  ${_cur_size}  S/N: ${_cur_sn:-}"
}

_cur_size="" _cur_mfr="" _cur_part="" _cur_sn=""
while IFS= read -r rawline; do
    line=$(sed 's/^[[:space:]]*//' <<< "$rawline")  # 선행 탭·공백 제거
    case "$line" in
        "Memory Device")
            _save_ram_slot
            _cur_size="" _cur_mfr="" _cur_part="" _cur_sn=""
            ;;
        "Size: "*)
            val="${line#Size: }"
            [[ "$val" =~ ^[0-9] ]] && _cur_size="$val"  # "No Module Installed" 등 제외
            ;;
        "Manufacturer: "*)  _cur_mfr="${line#Manufacturer: }"  ;;
        "Part Number: "*)   _cur_part="${line#Part Number: }"  ;;
        "Serial Number: "*) _cur_sn="${line#Serial Number: }"  ;;
    esac
done < <(dmidecode -t memory 2>/dev/null)
_save_ram_slot  # 마지막 블록

# ── Jetson 보드 S/N (해당하는 경우) ──────────────────────────────────────────
JETSON_SN=""
if [[ -f /sys/firmware/devicetree/base/serial-number ]]; then
    JETSON_SN=$(cat /sys/firmware/devicetree/base/serial-number | tr -d '\0')
    log ""
    log "[Jetson S/N] $JETSON_SN"
fi

# ── CSV 생성 ──────────────────────────────────────────────────────────────────
GPU_COUNT=${#GPU_NAMES[@]}
DISK_COUNT=${#DISK_MODELS[@]}
RAM_COUNT=${#RAM_SIZES_M[@]}
MAX_ROWS=$GPU_COUNT
[[ $DISK_COUNT -gt $MAX_ROWS ]] && MAX_ROWS=$DISK_COUNT
[[ $RAM_COUNT  -gt $MAX_ROWS ]] && MAX_ROWS=$RAM_COUNT
[[ $MAX_ROWS   -lt 1         ]] && MAX_ROWS=1

HEADER="Hostname,OS,Board_Mfr,Board_Product,Board_SN,CPU,"
HEADER+="GPU_Name,GPU_Serial,GPU_UUID,"
HEADER+="Disk_Model,Disk_Serial,Disk_Size,Disk_Type,"
HEADER+="RAM_Total,RAM_Mfr,RAM_Size,RAM_Part,RAM_Serial"
[[ -n "$JETSON_SN" ]] && HEADER+=",Jetson_SN"
echo "$HEADER" > "$CSV"

for ((i=0; i<MAX_ROWS; i++)); do
    if [[ $i -eq 0 ]]; then
        ROW="\"$HOSTNAME\",\"$OS_PRETTY\",\"$BOARD_MFR\",\"$BOARD_PROD\",\"$BOARD_SN\",\"$CPU_MODEL\","
        RAM_TOTAL_CELL="\"$RAM_TOTAL\""
    else
        ROW="\"\",\"\",\"\",\"\",\"\",\"\","
        RAM_TOTAL_CELL="\"\""
    fi

    GPU_NAME_C="\"${GPU_NAMES[$i]:-}\""
    GPU_SN_C="\"${GPU_SERIALS[$i]:-}\""
    GPU_UUID_C="\"${GPU_UUIDS[$i]:-}\""
    ROW+="${GPU_NAME_C},${GPU_SN_C},${GPU_UUID_C},"

    DISK_MODEL_C="\"${DISK_MODELS[$i]:-}\""
    DISK_SN_C="\"${DISK_SERIALS[$i]:-}\""
    DISK_SIZE_C="\"${DISK_SIZES[$i]:-}\""
    DISK_TYPE_C="\"${DISK_TYPES[$i]:-}\""
    ROW+="${DISK_MODEL_C},${DISK_SN_C},${DISK_SIZE_C},${DISK_TYPE_C},"

    RAM_MFR_C="\"${RAM_MFRS[$i]:-}\""
    RAM_SIZE_C="\"${RAM_SIZES_M[$i]:-}\""
    RAM_PART_C="\"${RAM_PARTS[$i]:-}\""
    RAM_SN_C="\"${RAM_SERIALS[$i]:-}\""
    ROW+="${RAM_TOTAL_CELL},${RAM_MFR_C},${RAM_SIZE_C},${RAM_PART_C},${RAM_SN_C}"

    if [[ -n "$JETSON_SN" ]]; then
        [[ $i -eq 0 ]] && ROW+=",\"$JETSON_SN\"" || ROW+=",\"\""
    fi

    echo "$ROW" >> "$CSV"
done

# ── 무결성 해시 생성 (SHA256) ─────────────────────────────────────────────────
HASH_FILE="${CSV%.csv}.sha256"
sha256sum "$CSV" | awk -v base="$(basename "$CSV")" '{print $1 "  " base}' > "$HASH_FILE"

log ""
log "CSV 저장 완료: $CSV"
log "SHA256  완료: $HASH_FILE"
log "RAW 저장 완료: $RAW"
echo ""
echo "완료!"
