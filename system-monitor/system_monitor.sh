#!/bin/bash
################################################################################
# 고급 시스템 모니터링 스크립트
# 버전: 2.1
# 작성자: System Administrator
# 설명: 포괄적인 시스템 모니터링 및 알림 시스템
################################################################################

# 전역 변수 설정
SCRIPT_DIR="/usr/local/bin"
CONFIG_DIR="/etc/system_monitor"
LOG_DIR="/var/log"
DATA_DIR="/opt/system_monitor/data"
REPORT_DIR="/storage/system_monitor/reports"

CONFIG_FILE="$CONFIG_DIR/system_monitor.conf"
THRESHOLD_FILE="$CONFIG_DIR/thresholds.conf"
LOG_FILE="$LOG_DIR/system_monitor.log"
ALERT_LOG="$LOG_DIR/system_monitor_alerts.log"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 기본 설정값
DEFAULT_CPU_THRESHOLD=80
DEFAULT_MEMORY_THRESHOLD=85
DEFAULT_SWAP_THRESHOLD=75
DEFAULT_DISK_THRESHOLD=90
DEFAULT_LOAD_THRESHOLD=5.0
DEFAULT_EMAIL="admin@localhost"

# 설정 파일 생성 함수
create_config_files() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << EOF
# 시스템 모니터링 설정
EMAIL_TO="admin@localhost"
EMAIL_FROM="system-monitor@localhost"
SMTP_SERVER="localhost"
SMTP_PORT="25"

TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

SLACK_WEBHOOK_URL=""

JANDI_WEBHOOK_URL=""
JANDI_ROOM_NAME="monitoring-alerts"

DISCORD_WEBHOOK_URL=""
TEAMS_WEBHOOK_URL=""

CHECK_INTERVAL=300

LOG_LEVEL="INFO"
MAX_LOG_SIZE="100M"
LOG_RETENTION_DAYS=30

MONITOR_VMS=true
MONITOR_CONTAINERS=true
MONITOR_NETWORK_SECURITY=true
ENABLE_ANOMALY_DETECTION=true
ENABLE_PERFORMANCE_PREDICTION=true

EOF
    fi

    if [[ ! -f "$THRESHOLD_FILE" ]]; then
        cat > "$THRESHOLD_FILE" << EOF
# 임계값 설정
CPU_WARNING=70
CPU_CRITICAL=85
MEMORY_WARNING=75
MEMORY_CRITICAL=90
SWAP_WARNING=50
SWAP_CRITICAL=80
DISK_WARNING=85
DISK_CRITICAL=95
LOAD_WARNING=3.0
LOAD_CRITICAL=8.0
NETWORK_DROP_WARNING=1.0
NETWORK_DROP_CRITICAL=5.0
VM_MEMORY_WARNING=80
VM_MEMORY_CRITICAL=90
EOF
    fi
}

# 로그 함수
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# 색상 출력 함수
print_colored() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# 설정 파일 로드 함수
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

    if [[ -f "$THRESHOLD_FILE" ]]; then
        source "$THRESHOLD_FILE"
    fi
}

# 시스템 정보 수집 함수
get_system_info() {
    echo "=== 시스템 정보 ==="
    echo "호스트명: $(hostname -f)"
    echo "OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
    echo "커널: $(uname -r)"
    echo "업타임: $(uptime -p)"
    echo "현재 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "IP 주소: $(hostname -I | awk '{print $1}')"
    echo
}

# 이상 탐지 함수
analyze_performance_anomaly() {
    local metric_type="$1"
    local current_value="$2"
    local data_file="$DATA_DIR/performance_$(date +%Y%m).csv"

    if [[ "$ENABLE_ANOMALY_DETECTION" != true ]]; then
        return 0
    fi

    if command -v python3 >/dev/null 2>&1 && [[ -f "$data_file" ]]; then
        local anomaly_result
        anomaly_result=$(python3 -c "
import pandas as pd
import sys
try:
    df = pd.read_csv('$data_file')
    if len(df) < 20:
        sys.exit(0)
    recent_data = df.tail(2016)
    baseline_mean = recent_data['$metric_type'].mean()
    baseline_std = recent_data['$metric_type'].std()
    z_score = abs(($current_value - baseline_mean) / baseline_std) if baseline_std > 0 else 0
    if z_score > 2.5:
        print(f'ANOMALY|{z_score:.2f}')
    else:
        print(f'NORMAL|{z_score:.2f}')
except Exception:
    sys.exit(0)
        " 2>/dev/null || echo "NORMAL|0.00")

        if [[ "$anomaly_result" == ANOMALY* ]]; then
            send_alert "성능 이상 탐지" "${metric_type}에서 이상치 감지: 현재값 ${current_value}"
            return 1
        fi
    fi
    return 0
}

# 이메일 알림 함수
send_email() {
    local subject="$1"
    local message="$2"
    if [[ -n "$EMAIL_TO" ]]; then
        echo -e "$message" | mail -s "[$(hostname -f)] $subject" "$EMAIL_TO"
    fi
}

# 텔레그램 알림 함수
send_telegram() {
    local message="$1"
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        local telegram_message
        telegram_message="🖥️ <b>$(hostname -f)</b>%0A%0A$message%0A%0A⏰ $(date '+%Y-%m-%d %H:%M:%S')"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d "chat_id=${TELEGRAM_CHAT_ID}" \
             -d "text=${telegram_message}" \
             -d "parse_mode=HTML" >/dev/null
    fi
}

# JANDI 알림 함수
send_jandi() {
    local message="$1"
    local payload=$(cat <<EOF
{
  "body": "$message",
  "connectColor": "#FFA500",
  "connectInfo": [
    {"title": "호스트", "description": "$(hostname -f)"},
    {"title": "시간", "description": "$(date '+%Y-%m-%d %H:%M:%S')"}
  ]
}
EOF
)
    curl -s -X POST "$JANDI_WEBHOOK_URL" -H "Content-Type: application/json" -d "$payload"
}

# 통합 알림 함수
send_alert() {
    local subject="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] ALERT: $subject - $message" >> "$ALERT_LOG"
    send_email "$subject" "$message"
    send_telegram "$message"
    send_jandi "$subject" "$message" "danger"

    log_message "ALERT" "$subject: $message"
}

# CPU 모니터링 함수
monitor_cpu() {
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | head -1)
    local cpu_int=${cpu_usage%.*}

    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

    echo "=== CPU 상태 ==="
    echo "CPU 사용률: ${cpu_usage}%"
    echo "로드 애버리지 (1분): ${load_avg}"
    echo "CPU 코어별 사용률:"
    mpstat -P ALL 1 1 | grep -E '^Average:.*[0-9]' | awk '{printf "  CPU%s: %.1f%%\n", $2, 100-$12}'

    if (( cpu_int > CPU_CRITICAL )); then
        send_alert "CPU 위험" "CPU 사용률이 ${cpu_usage}%로 위험 수준입니다."
        print_colored "$RED" "⚠️ CPU 사용률 위험: ${cpu_usage}%"
        analyze_performance_anomaly "cpu_usage" "$cpu_usage"
        return 2
    elif (( cpu_int > CPU_WARNING )); then
        send_alert "CPU 경고" "CPU 사용률이 ${cpu_usage}%로 경고 수준입니다."
        print_colored "$YELLOW" "⚠️ CPU 사용률 경고: ${cpu_usage}%"
        analyze_performance_anomaly "cpu_usage" "$cpu_usage"
        return 1
    else
        print_colored "$GREEN" "✅ CPU 상태 정상: ${cpu_usage}%"
        return 0
    fi
}

# 메모리 모니터링 함수
monitor_memory() {
    local memory_info
    memory_info=$(free -m)
    local total_mem used_mem available_mem
    total_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $2}')
    used_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $3}')
    available_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $7}')
    local memory_usage
    memory_usage=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc)
    local memory_usage_int=${memory_usage%.*}

    local swap_total swap_used swap_usage
    swap_total=$(echo "$memory_info" | awk '/^Swap:/ {print $2}')
    swap_used=$(echo "$memory_info" | awk '/^Swap:/ {print $3}')
    swap_usage=0
    if [[ $swap_total -gt 0 ]]; then
        swap_usage=$(echo "scale=1; $swap_used * 100 / $swap_total" | bc)
    fi
    local swap_usage_int=${swap_usage%.*}

    echo "=== 메모리 상태 ==="
    echo "총 메모리: ${total_mem}MB"
    echo "사용 메모리: ${used_mem}MB (${memory_usage}%)"
    echo "사용 가능: ${available_mem}MB"
    echo "SWAP 사용: ${swap_used}MB / ${swap_total}MB (${swap_usage}%)"

    echo "상위 메모리 사용 프로세스:"
    ps aux --sort=-%mem | head -6 | awk 'NR==1 || NR<=6 {printf "  %-12s %-8s %-6s %s\n", $1, $2, $4, $11}'

    local alert_count=0
    if (( memory_usage_int > MEMORY_CRITICAL )); then
        send_alert "메모리 위험" "메모리 사용률이 ${memory_usage}%로 위험 수준입니다."
        print_colored "$RED" "⚠️ 메모리 사용률 위험: ${memory_usage}%"
        analyze_performance_anomaly "memory_usage" "$memory_usage"
        ((alert_count++))
    elif (( memory_usage_int > MEMORY_WARNING )); then
        send_alert "메모리 경고" "메모리 사용률이 ${memory_usage}%로 경고 수준입니다."
        print_colored "$YELLOW" "⚠️ 메모리 사용률 경고: ${memory_usage}%"
        analyze_performance_anomaly "memory_usage" "$memory_usage"
        ((alert_count++))
    else
        print_colored "$GREEN" "✅ 메모리 상태 정상: ${memory_usage}%"
    fi

    if (( swap_usage_int > SWAP_CRITICAL )); then
        send_alert "SWAP 위험" "SWAP 사용률이 ${swap_usage}%로 위험 수준입니다."
        print_colored "$RED" "⚠️ SWAP 사용률 위험: ${swap_usage}%"
        ((alert_count++))
    elif (( swap_usage_int > SWAP_WARNING )); then
        send_alert "SWAP 경고" "SWAP 사용률이 ${swap_usage}%로 경고 수준입니다."
        print_colored "$YELLOW" "⚠️ SWAP 사용률 경고: ${swap_usage}%"
        ((alert_count++))
    else
        print_colored "$GREEN" "✅ SWAP 상태 정상: ${swap_usage}%"
    fi

    return $alert_count
}

# 디스크 모니터링 함수
monitor_disk() {
    echo "=== 디스크 상태 ==="
    local alert_count=0

    # df 명령어에 -T 옵션을 추가하여 파일시스템 타입을 함께 조회
    while read -r filesystem fstype size used avail use_percent mountpoint; do
        # ✨ 아래 squashfs 제외 로직 추가
        if [[ "$fstype" == "squashfs" ]]; then
            continue
        fi
        
        if [[ "$filesystem" =~ ^/dev/ ]]; then
            local usage=${use_percent%?}
            echo "마운트포인트: $mountpoint"
            echo "  파일시스템: $filesystem"
            echo "  크기: $size, 사용: $used ($use_percent), 사용 가능: $avail"

            if (( usage > DISK_CRITICAL )); then
                send_alert "디스크 위험" "디스크 $mountpoint 사용률이 $use_percent로 위험 수준입니다."
                print_colored "$RED" "⚠️ 디스크 $mountpoint 위험: $use_percent"
                ((alert_count++))
            elif (( usage > DISK_WARNING )); then
                send_alert "디스크 경고" "디스크 $mountpoint 사용률이 $use_percent로 경고 수준입니다."
                print_colored "$YELLOW" "⚠️ 디스크 $mountpoint 경고: $use_percent"
                ((alert_count++))
            else
                print_colored "$GREEN" "✅ 디스크 $mountpoint 정상: $use_percent"
            fi
        fi
    done < <(df -hT | tail -n +2) # df -h -> df -hT 로 변경

    echo
    echo "디스크 I/O 통계:"
    iostat -d 1 1 | grep -E '^Device|^[a-zA-Z]' | tail -n +2

    return $alert_count
}

# 네트워크 모니터링 함수
monitor_network() {
    echo "=== 네트워크 상태 ==="

    for interface in $(ls /sys/class/net/ | grep -v lo); do
        if [[ -f "/sys/class/net/$interface/operstate" ]]; then
            local state ip
            state=$(cat "/sys/class/net/$interface/operstate")
            ip=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            echo "인터페이스: $interface"
            echo "  상태: $state"
            [[ -n "$ip" ]] && echo "  IP: $ip"
        fi
    done

    local tcp_connections
    tcp_connections=$(netstat -tn | grep ESTABLISHED | wc -l)
    echo "활성 TCP 연결 수: $tcp_connections"

    echo "네트워크 통계:"
    cat /proc/net/dev | grep -E '(eth|ens|enp|wlan)' | while read -r line; do
        local interface rx_packets tx_packets
        interface=$(echo "$line" | awk '{print $1}' | tr -d ':')
        rx_packets=$(echo "$line" | awk '{print $2}')
        tx_packets=$(echo "$line" | awk '{print $10}')
        echo "  $interface: RX $rx_packets packets, TX $tx_packets packets"
    done
}

# 서비스 모니터링 함수
monitor_services() {
    echo "=== 서비스 상태 ==="
    local services=("ssh" "systemd-resolved" "cron" "rsyslog")
    local failed_services=()

    if command -v virsh &>/dev/null; then
        services+=("libvirtd")
    fi

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            print_colored "$GREEN" "✅ $service: 활성"
        else
            print_colored "$RED" "❌ $service: 비활성"
            failed_services+=("$service")
        fi
    done

    if [[ ${#failed_services[@]} -gt 0 ]]; then
        local failed_list
        failed_list=$(IFS=', '; echo "${failed_services[*]}")
        send_alert "서비스 실패" "다음 서비스들이 비활성 상태입니다: $failed_list"
        return 1
    fi

    return 0
}

# VM 모니터링 함수
monitor_vms() {
    if ! command -v virsh &>/dev/null; then
        echo "libvirt가 설치되지 않았습니다. VM 모니터링을 건너뜁니다."
        return 0
    fi

    echo "=== 가상머신 상태 ==="

    local running_vms stopped_vms
    running_vms=$(virsh list --state-running --name)
    stopped_vms=$(virsh list --state-shutoff --name)

    echo "실행 중인 VM:"
    if [[ -n "$running_vms" ]]; then
        while read -r vm; do
            [[ -n "$vm" ]] && echo "  ✅ $vm"
        done <<< "$running_vms"
    else
        echo "  없음"
    fi

    echo "중지된 VM:"
    if [[ -n "$stopped_vms" ]]; then
        while read -r vm; do
            [[ -n "$vm" ]] && echo "  ❌ $vm"
        done <<< "$stopped_vms"
    else
        echo "  없음"
    fi

    echo
    echo "VM 메모리 사용 현황:"
    while read -r vm; do
        if [[ -n "$vm" ]]; then
            local vm_stats current_mem max_mem rss_mem current_gb max_gb rss_gb
            vm_stats=$(virsh domstats --balloon "$vm" 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                current_mem=$(echo "$vm_stats" | grep "balloon.current" | cut -d= -f2)
                max_mem=$(echo "$vm_stats" | grep "balloon.maximum" | cut -d= -f2)
                rss_mem=$(echo "$vm_stats" | grep "balloon.rss" | cut -d= -f2)
                if [[ -n "$current_mem" && -n "$max_mem" && -n "$rss_mem" ]]; then
                    (( current_gb = current_mem / 1024 / 1024 ))
                    (( max_gb = max_mem / 1024 / 1024 ))
                    (( rss_gb = rss_mem / 1024 / 1024 ))
                    echo "  $vm: ${current_gb}GB / ${max_gb}GB (실제사용: ${rss_gb}GB)"
                fi
            fi
        fi
    done <<< "$running_vms"
}

# 프로세스 모니터링 함수
monitor_processes() {
    echo "=== 프로세스 상태 ==="

    local total_processes zombie_processes
    total_processes=$(ps aux | wc -l)
    zombie_processes=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')

    echo "총 프로세스 수: $((total_processes - 1))"
    echo "좀비 프로세스 수: $zombie_processes"

    if (( zombie_processes > 0 )); then
        print_colored "$YELLOW" "⚠️ 좀비 프로세스 발견: $zombie_processes개"
        send_alert "좀비 프로세스" "$zombie_processes개의 좀비 프로세스가 발견되었습니다."
    fi

    echo
    echo "상위 CPU 사용 프로세스:"
    ps aux --sort=-%cpu | head -6 | awk 'NR==1 || NR<=6 {printf "  %-12s %-8s %-6s %s\n", $1, $2, $3, $11}'
}

# 성능 데이터 저장 함수
save_performance_data() {
    local timestamp cpu_usage memory_usage disk_usage load_avg perf_file

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    memory_usage=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100.0}')
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//g')
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

    perf_file="$DATA_DIR/performance_$(date +%Y%m).csv"

    if [[ ! -f "$perf_file" ]]; then
        echo "timestamp,cpu_usage,memory_usage,disk_usage,load_avg" > "$perf_file"
    fi

    echo "$timestamp,$cpu_usage,$memory_usage,$disk_usage,$load_avg" >> "$perf_file"
}

################################################################################
# 보고서 HTML 생성 함수 (VM 메모리 현황 포함)
################################################################################
################################################################################
# 보고서 트렌드 보조 함수 (주간/월간 평균·최대 계산)
################################################################################
_pcls() {
    local v="${1%.*}" w="$2" cr="$3"
    if   (( v >= cr )); then echo "crit"
    elif (( v >= w  )); then echo "warn"
    else echo "ok"; fi
}

trend_rows() {
    local rt="$1" col="$2" lbl="$3" warn_t="$4" crit_t="$5"
    local perf="$DATA_DIR/performance_$(date +%Y%m).csv"
    [[ ! -f "$perf" ]] && return
    local stats period
    if [[ "$rt" == "weekly" ]]; then
        local cut; cut=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null)
        period="주간 7일"
        stats=$(awk -F',' -v c="$((col+1))" -v cut="$cut" \
            'NR>1 && $1>=cut { s+=$c; if($c>m)m=$c; n++ }
             END { if(n) printf "%.1f\t%.1f\t%d", s/n, m, n }' "$perf")
    else
        local mo; mo=$(date '+%Y-%m')
        period="월간 $(date '+%m')월"
        stats=$(awk -F',' -v c="$((col+1))" -v m="$mo" \
            'NR>1 && substr($1,1,7)==m { s+=$c; if($c>mx)mx=$c; n++ }
             END { if(n) printf "%.1f\t%.1f\t%d", s/n, mx, n }' "$perf")
    fi
    [[ -z "$stats" ]] && return
    local avg max cnt ca cm
    avg=$(cut -f1 <<<"$stats")
    max=$(cut -f2 <<<"$stats")
    cnt=$(cut -f3 <<<"$stats")
    ca=$(_pcls "$avg" "$warn_t" "$crit_t")
    cm=$(_pcls "$max" "$warn_t" "$crit_t")
    echo "<tr style='background:#f8fbff'><td><b>${lbl} 평균</b> <span style='font-size:.75em;color:#aaa'>(${period} · ${cnt}건)</span></td><td class=\"${ca}\">${avg}%</td></tr>"
    echo "<tr style='background:#f8fbff'><td>${lbl} 최대</td><td class=\"${cm}\">${max}%</td></tr>"
}

generate_report() {
    local report_type="$1"
    local date_fmt subdir

    if [[ "$report_type" == "weekly" ]]; then
        date_fmt='W%V'; subdir='weekly'
    elif [[ "$report_type" == "monthly" ]]; then
        date_fmt='%Y-%m'; subdir='monthly'
    else
        # weekly나 monthly가 아니면, 지원하지 않는 타입으로 간주하고 오류 메시지 출력
        echo "오류: 지원하지 않는 보고서 타입입니다: '$report_type'" >&2
        return 1 # 함수를 실패로 종료
    fi

    local report_date=$(date +"$date_fmt")
    local report_dir="$REPORT_DIR/$subdir"
    mkdir -p "$report_dir"
    local hostname=$(hostname -s)
    local report_file="$report_dir/${hostname}_${report_type}_report_${report_date}.html"

    # HTML 시작부
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head><meta charset="utf-8">
  <title>${report_type^} 시스템 모니터링 보고서 - $HOSTNAME</title>
  <style>
    *{box-sizing:border-box}
    body{font-family:Arial,sans-serif;margin:0;padding:16px;background:#f5f5f5}
    h1{margin:0;font-size:1.4em;color:#fff}
    h3{color:#444;border-left:4px solid #2c3e50;padding-left:8px;margin-top:24px}
    .header{background:#2c3e50;padding:16px;border-radius:6px;margin-bottom:20px}
    .header p{margin:4px 0;color:rgba(255,255,255,.9);font-size:.9em}
    .summary{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:20px}
    .card{background:#fff;border-radius:6px;padding:14px;flex:1;min-width:140px;box-shadow:0 1px 3px rgba(0,0,0,.1);text-align:center}
    .card .val{font-size:1.8em;font-weight:bold;margin:4px 0}
    .card .lbl{font-size:.8em;color:#777}
    .ok{color:#27ae60}.warn{color:#e67e22}.crit{color:#e74c3c}
    .bar-wrap{background:#e0e0e0;border-radius:4px;height:8px;margin-top:4px}
    .bar{height:8px;border-radius:4px}
    table{border-collapse:collapse;width:100%;margin-bottom:16px;background:#fff;border-radius:6px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)}
    th,td{border:1px solid #e0e0e0;padding:8px 10px;text-align:left;font-size:.9em}
    th{background:#f9f9f9;font-weight:600}
    tr:hover{background:#fafafa}
    .up{color:#27ae60;font-weight:bold}.dn{color:#e74c3c}
  </style>
</head>
<body>
  <div class="header">
    <h1>📊 ${report_type^} 시스템 모니터링 보고서</h1>
    <p>🖥️ 호스트: $HOSTNAME</p>
    <p>생성시간: $(date '+%Y-%m-%d %H:%M:%S')</p>
  </div>
EOF

    # 요약 카드 (상단 상태 한눈에 보기)
    {
      local cv=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f",100-$8}')
      local mp=$(free -m | awk '/^Mem:/{printf "%.1f",$3/$2*100}')
      local dp=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
      local ut=$(uptime -p)
      local cc="ok"; ((${cv%.*}>=80))&&cc="crit"||((${cv%.*}>=70))&&cc="warn"
      local mc="ok"; ((${mp%.*}>=85))&&mc="crit"||((${mp%.*}>=75))&&mc="warn"
      local dc="ok"; ((dp>=90))&&dc="crit"||((dp>=80))&&dc="warn"
      local cb="#27ae60";[[ $cc == warn ]]&&cb="#e67e22";[[ $cc == crit ]]&&cb="#e74c3c"
      local mb="#27ae60";[[ $mc == warn ]]&&mb="#e67e22";[[ $mc == crit ]]&&mb="#e74c3c"
      local db="#27ae60";[[ $dc == warn ]]&&db="#e67e22";[[ $dc == crit ]]&&db="#e74c3c"
      echo "<div class='summary'>"
      echo "<div class='card'><div class='lbl'>CPU 사용률</div><div class='val ${cc}'>${cv}%</div><div class='bar-wrap'><div class='bar' style='width:${cv}%;background:${cb}'></div></div></div>"
      echo "<div class='card'><div class='lbl'>메모리</div><div class='val ${mc}'>${mp}%</div><div class='bar-wrap'><div class='bar' style='width:${mp}%;background:${mb}'></div></div></div>"
      echo "<div class='card'><div class='lbl'>디스크(/)</div><div class='val ${dc}'>${dp}%</div><div class='bar-wrap'><div class='bar' style='width:${dp}%;background:${db}'></div></div></div>"
      echo "<div class='card'><div class='lbl'>업타임</div><div class='val ok' style='font-size:.85em'>${ut}</div></div>"
      echo "</div>"
    } >> "$report_file"

    # 1. CPU
    {
      echo '<h3>1. CPU 상태</h3>'
      echo '<table><tr><th>항목</th><th>값</th></tr>'
      top -bn1 | grep "Cpu(s)" | awk '{v=100-$8;cl=(v>=80)?"crit":(v>=70)?"warn":"ok";printf "<tr><td>사용률</td><td class=\"%s\">%.1f%%</td></tr>\n",cl,v}'
      uptime | awk -F'load average:' '{printf "<tr><td>로드(1, 5, 15분)</td><td>%s</td></tr>\n",$2}'
      trend_rows "$report_type" 1 "CPU 사용률" 70 80
      echo '</table>'
    } >> "$report_file"

    # 2. 메모리 및 SWAP
    {
      echo '<h3>2. 메모리 및 SWAP</h3>'
      echo '<table><tr><th>구분</th><th>총</th><th>사용</th><th>잔여</th><th>사용%</th></tr>'
      free -m | awk 'NR==2{p=$3/$2*100;cl=(p>=85)?"crit":(p>=75)?"warn":"ok";printf "<tr><td>메모리</td><td>%sMB</td><td>%sMB</td><td>%sMB</td><td class=\"%s\">%.1f%%</td></tr>\n",$2,$3,$7,cl,p}'
      free -m | awk 'NR==3 && $2>0 {printf "<tr><td>SWAP</td><td>%sMB</td><td>%sMB</td><td>%sMB</td><td>%.1f%%</td></tr>\n",$2,$3,$4,$3/$2*100}'
      trend_rows "$report_type" 2 "메모리 사용률" 75 85
      echo '</table>'
    } >> "$report_file"

    # 3. 디스크 사용량
    {
      echo '<h3>3. 디스크 사용량</h3>'
      echo '<table><tr><th>마운트</th><th>총</th><th>사용</th><th>잔여</th><th>사용%</th></tr>'
      df -hT | awk '$2!="squashfs" && /^\/dev\//{p=$6+0;cl=(p>=90)?"crit":(p>=80)?"warn":"ok";printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class=\"%s\">%s</td></tr>\n",$7,$3,$4,$5,cl,$6}'
      echo '</table>'
    } >> "$report_file"

    # 4. 네트워크 TCP 연결 수
    {
      echo '<h3>4. 네트워크 TCP 연결 수</h3>'
      local tcp=$(netstat -tn | grep ESTABLISHED | wc -l)
      echo "<p>활성 TCP 연결: ${tcp}</p>"
    } >> "$report_file"

    # 5. 가상머신 사용 현황
    if command -v virsh &> /dev/null; then
        {
          echo '<h3>5. 가상머신 메모리 사용 현황</h3>'
          echo '<table><tr><th>가상머신</th><th>상태</th><th>할당 메모리</th><th>실제 사용 메모리</th></tr>'
          for vm in $(virsh -c qemu:///system list --all --name); do
            [[ -z "$vm" ]] && continue
            state=$(virsh -c qemu:///system domstate "$vm" 2>/dev/null)
            if [[ "$state" == "running" ]]; then
              stats=$(virsh -c qemu:///system domstats --balloon "$vm" 2>/dev/null)
              max_kb=$(awk -F= '/balloon.maximum/ {print $2}' <<<"$stats")
              rss_kb=$(awk -F= '/balloon.rss/ {print $2}' <<<"$stats")
              max_gb=$((max_kb/1024/1024))
              rss_gb=$((rss_kb/1024/1024))
              echo "<tr><td>$vm</td><td>$state</td><td>${max_gb}GB</td><td>${rss_gb}GB</td></tr>"
            else
              echo "<tr><td>$vm</td><td>$state</td><td>N/A</td><td>N/A</td></tr>"
            fi
          done
          echo '</table>'

          echo '<h3>6. 가상머신 디스크 사용 현황</h3>'
          echo '<table><tr><th>가상머신</th><th>디스크</th><th>할당 용량</th><th>실제 사용량</th></tr>'
          for vm in $(virsh -c qemu:///system list --state-running --name); do
            virsh -c qemu:///system domblklist "$vm" --details 2>/dev/null | awk '$2 == "disk"' | while read type device target source; do
              if [[ -n "$source" && "$source" != "-" ]]; then
                disk_info=$(sudo qemu-img info --force-share "$source" 2>/dev/null)
                if [[ $? -eq 0 && -n "$disk_info" ]]; then
                  virtual_size=$(echo "$disk_info" | grep "virtual size" | sed 's/.*virtual size: \([^(]*\).*/\1/' | tr -d ' ')
                  disk_size=$(echo "$disk_info" | grep "disk size" | sed 's/.*disk size: \([^(]*\).*/\1/' | tr -d ' ')
                  echo "<tr><td>$vm</td><td>$target</td><td>${virtual_size}</td><td>${disk_size}</td></tr>"
                else
                  echo "<tr><td>$vm</td><td>$target</td><td>N/A</td><td>qemu-img 실패</td></tr>"
                fi
              fi
            done
          done
          echo '</table>'
        } >> "$report_file"
    fi

    # 7. Docker 서비스 현황
    if command -v docker &> /dev/null; then
        {
          echo '<h3>7. Docker 서비스 상태</h3>'
          echo '<table><tr><th>컨테이너</th><th>이미지</th><th>상태</th></tr>'
          docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}' | while IFS="|" read name image status; do
            cl="dn"; echo "$status" | grep -qi "^up" && cl="up"
            echo "<tr><td>$name</td><td>$image</td><td class=\"$cl\">$status</td></tr>"
          done
          echo '</table>'
        } >> "$report_file"
    fi

    # HTML 종료
    echo '</body></html>' >> "$report_file"

    log_message "INFO" "Report generated: $report_file"
    # NAS 경로에 맞는 웹 접근 URL (환경에 맞게 수정)
    local base_url="http://172.18.100.10/system_monitor/reports"
    local link="${base_url}/${subdir}/$(basename "$report_file")"
    
    # Jandi 알림을 위한 JSON 페이로드 생성
    local jandi_payload
    jandi_payload=$(cat <<EOF
    {
      "body": "${hostname} - 📄 ${report_type^} 보고서 생성 완료",
      "connectColor": "#4081F5",
      "connectInfo": [
        {
          "title": "시간",
          "description": "$(date '+%Y-%m-%d %H:%M:%S')"
        },
        {
          "title": "상세",
          "description": "[링크 확인](${link})"
        }
      ]
    }
EOF
    )

    # 생성된 페이로드를 Jandi Webhook으로 직접 전송
    curl -s -X POST "$JANDI_WEBHOOK_URL" -H "Content-Type: application/json" -d "$jandi_payload"

    echo "Report generated: $report_file"
    cleanup_old_reports

    # 성능 CSV를 NAS에 동기화 (이메일 스크립트 참조용)
    local csv_src="$DATA_DIR/performance_$(date +%Y%m).csv"
    local csv_nas_dir="/storage/system_monitor/data/${hostname}"
    if [[ -f "$csv_src" ]] && mountpoint -q /storage 2>/dev/null; then
        mkdir -p "$csv_nas_dir"
        cp "$csv_src" "$csv_nas_dir/" 2>/dev/null || true
        log_message "INFO" "CSV 동기화 완료: $csv_nas_dir"
    fi
}

################################################################################
# 오래된 보고서 자동 정리 (daily>30일, weekly>12주, monthly>1년)
################################################################################
cleanup_old_reports() {
    find "$REPORT_DIR/daily"   -name "*.html" -mtime +30  -delete 2>/dev/null
    find "$REPORT_DIR/weekly"  -name "*.html" -mtime +84  -delete 2>/dev/null
    find "$REPORT_DIR/monthly" -name "*.html" -mtime +365 -delete 2>/dev/null
    log_message "INFO" "오래된 보고서 정리 완료 (daily>30일 weekly>12주 monthly>1년)"
}

################################################################################
# 메인 함수 및 실행 엔트리포인트
################################################################################
# 메인 모니터링 함수
main_monitor() {
    local mode="${1:-full}"
    local arg2="$2"

    create_config_files
    load_config

    log_message "INFO" "시스템 모니터링 시작 (모드: $mode)"

    case "$mode" in
        cpu)
            get_system_info
            monitor_cpu
            ;;
        memory)
            get_system_info
            monitor_memory
            ;;
        disk)
            get_system_info
            monitor_disk
            ;;
        network)
            get_system_info
            monitor_network
            ;;
        services)
            get_system_info
            monitor_services
            ;;
        vms)
            get_system_info
            monitor_vms
            ;;
        processes)
            get_system_info
            monitor_processes
            ;;
        saveperf)
            load_config
            save_performance_data
            ;;
        report)
            generate_report "$arg2"
            ;;
        full|*)
            print_colored "$CYAN" "========================================"
            print_colored "$CYAN" "    시스템 모니터링 시작"
            print_colored "$CYAN" "========================================"
            echo
            get_system_info

            local total_alerts=0

            monitor_cpu
            ((total_alerts += $?))
            echo

            monitor_memory
            ((total_alerts += $?))
            echo

            monitor_disk
            ((total_alerts += $?))
            echo

            monitor_network
            echo

            monitor_services
            ((total_alerts += $?))
            echo

            if [[ "$MONITOR_VMS" == true ]]; then
                monitor_vms
                echo
            fi

            monitor_processes
            echo

            save_performance_data

            print_colored "$CYAN" "========================================"
            if (( total_alerts == 0 )); then
                print_colored "$GREEN" "    모든 시스템 상태 정상"
            else
                print_colored "$YELLOW" "    총 $total_alerts 개의 경고/알림 발생"
            fi
            print_colored "$CYAN" "========================================"
            ;;
    esac

    log_message "INFO" "시스템 모니터링 완료"
}

# 도움말 함수
show_help() {
    cat << EOF
사용법: $0 [옵션]
옵션:
  full      전체 시스템 모니터링 (기본값)
  cpu       CPU 모니터링만
  memory    메모리 모니터링만
  disk      디스크 모니터링만
  network   네트워크 모니터링만
  services  서비스 모니터링만
  vms       가상머신 모니터링만
  processes 프로세스 모니터링만
  report    수동 보고서 생성
  help      이 도움말 표시
예시:
  $0              # 전체 모니터링
  $0 cpu          # CPU만 모니터링
  $0 memory       # 메모리만 모니터링
  $0 report       # 보고서 생성
설정 파일: $CONFIG_FILE
로그 파일: $LOG_FILE
EOF
}

# 스크립트 시작점
case "${1:-full}" in
    help|--help|-h)
        show_help
        ;;
    *)
        main_monitor "$1" "$2"
        ;;
esac
