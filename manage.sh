#!/usr/bin/env bash
# =============================================================================
# Clobot Monitoring Stack 관리 스크립트
# 사용법: ./manage.sh [command]
# =============================================================================

set -euo pipefail

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"
PROMETHEUS_URL="http://localhost:9099"
ALERTMANAGER_URL="http://localhost:9093"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Clobot Monitoring Stack 관리 스크립트

사용법: $0 <command>

Commands:
  up          스택 전체 시작
  down        스택 전체 중지
  restart     스택 재시작
  status      각 컨테이너 상태 확인
  logs [svc]  로그 확인 (서비스명 생략 시 전체)
  reload      Prometheus & Alertmanager 설정 무중단 리로드
  validate    설정 파일 문법 검사
  alerts      현재 발화 중인 알람 목록
  targets     Prometheus scrape target 상태
  backup          Prometheus TSDB 스냅샷 생성
  build-fortigate fortigate-exporter 소스 클론 & 빌드 & 시작
  update          이미지 업데이트 후 재시작

EOF
}

# ---------------------------------------------------------------------------
cmd_up() {
  info "모니터링 스택 시작..."
  # app-tier 네트워크가 없는 경우 생성
  if ! docker network ls --format '{{.Name}}' | grep -q '^app-tier$'; then
    warn "app-tier 네트워크가 없어 새로 생성합니다."
    docker network create app-tier
  fi

  # fortigate-exporter는 빌드 소스가 있을 때만 포함
  if [ -f "$(dirname "$COMPOSE_FILE")/fortigate-exporter/src/Dockerfile" ]; then
    info "fortigate-exporter 소스 감지 → 빌드 포함 시작"
    docker compose -f "$COMPOSE_FILE" up -d
  else
    warn "fortigate-exporter 소스 없음 → 제외하고 시작 (나중에 'git clone' 후 './manage.sh build-fortigate' 실행)"
    docker compose -f "$COMPOSE_FILE" up -d \
      prometheus alertmanager grafana \
      snmp-exporter blackbox-exporter \
      haproxy-exporter jandi-adapter haproxy
  fi

  info "완료. 상태 확인 중..."
  sleep 3
  cmd_status
}

# ---------------------------------------------------------------------------
cmd_down() {
  warn "모니터링 스택 중지..."
  docker compose -f "$COMPOSE_FILE" down
  info "중지 완료."
}

# ---------------------------------------------------------------------------
cmd_restart() {
  warn "재시작..."
  docker compose -f "$COMPOSE_FILE" restart
  info "재시작 완료."
}

# ---------------------------------------------------------------------------
cmd_status() {
  echo ""
  echo "══════════════════════════════════════════"
  echo "  컨테이너 상태"
  echo "══════════════════════════════════════════"
  docker compose -f "$COMPOSE_FILE" ps
  echo ""

  # Prometheus health
  if curl -sf "${PROMETHEUS_URL}/-/healthy" > /dev/null 2>&1; then
    info "Prometheus: 정상 (${PROMETHEUS_URL})"
  else
    error "Prometheus: 응답 없음"
  fi

  # Alertmanager health
  if curl -sf "${ALERTMANAGER_URL}/-/healthy" > /dev/null 2>&1; then
    info "Alertmanager: 정상 (${ALERTMANAGER_URL})"
  else
    error "Alertmanager: 응답 없음"
  fi
}

# ---------------------------------------------------------------------------
cmd_logs() {
  local svc="${1:-}"
  if [[ -n "$svc" ]]; then
    docker compose -f "$COMPOSE_FILE" logs -f --tail=100 "$svc"
  else
    docker compose -f "$COMPOSE_FILE" logs -f --tail=50
  fi
}

# ---------------------------------------------------------------------------
cmd_reload() {
  info "Prometheus 설정 검사 중..."
  if ! cmd_validate_prometheus; then
    error "Prometheus 설정 오류. 리로드 중단."
    exit 1
  fi

  info "Alertmanager 설정 검사 중..."
  if ! cmd_validate_alertmanager; then
    error "Alertmanager 설정 오류. 리로드 중단."
    exit 1
  fi

  info "Prometheus 무중단 리로드..."
  if curl -sf -X POST "${PROMETHEUS_URL}/-/reload"; then
    info "Prometheus 리로드 성공"
  else
    error "Prometheus 리로드 실패"
  fi

  info "Alertmanager 무중단 리로드..."
  if curl -sf -X POST "${ALERTMANAGER_URL}/-/reload"; then
    info "Alertmanager 리로드 성공"
  else
    error "Alertmanager 리로드 실패"
  fi
}

# ---------------------------------------------------------------------------
cmd_validate_prometheus() {
  docker run --rm \
    --entrypoint promtool \
    -v "$(dirname "$COMPOSE_FILE")/prometheus:/etc/prometheus:ro" \
    prom/prometheus:v2.51.2 \
    check config /etc/prometheus/prometheus.yml
}

cmd_validate_alertmanager() {
  docker run --rm \
    --entrypoint amtool \
    -v "$(dirname "$COMPOSE_FILE")/alertmanager:/etc/alertmanager:ro" \
    prom/alertmanager:v0.28.1 \
    check-config /etc/alertmanager/alertmanager.yml
}

cmd_validate() {
  echo ""
  echo "══════════════════════════════════════════"
  echo "  Prometheus 설정 검사"
  echo "══════════════════════════════════════════"
  cmd_validate_prometheus && info "Prometheus 설정 OK" || error "Prometheus 설정 오류!"

  echo ""
  echo "══════════════════════════════════════════"
  echo "  Alert Rules 검사"
  echo "══════════════════════════════════════════"
  docker run --rm \
    --entrypoint promtool \
    -v "$(dirname "$COMPOSE_FILE")/prometheus:/etc/prometheus:ro" \
    prom/prometheus:v2.51.2 \
    check rules /etc/prometheus/rules/alert.rules.yml \
    && info "Alert Rules OK" || error "Alert Rules 오류!"

  echo ""
  echo "══════════════════════════════════════════"
  echo "  Alertmanager 설정 검사"
  echo "══════════════════════════════════════════"
  cmd_validate_alertmanager && info "Alertmanager 설정 OK" || error "Alertmanager 설정 오류!"
}

# ---------------------------------------------------------------------------
cmd_alerts() {
  echo ""
  echo "══════════════════════════════════════════"
  echo "  현재 발화 중인 알람"
  echo "══════════════════════════════════════════"
  curl -sf "${ALERTMANAGER_URL}/api/v2/alerts?active=true&silenced=false" \
    | python3 -c "
import json, sys
alerts = json.load(sys.stdin)
if not alerts:
    print('✅  발화 중인 알람 없음')
else:
    for a in alerts:
        lbl = a.get('labels', {})
        ann = a.get('annotations', {})
        print(f\"🚨 [{lbl.get('severity','?').upper()}] {lbl.get('alertname','?')}\")
        print(f\"   인스턴스: {lbl.get('instance','N/A')}\")
        print(f\"   내용: {ann.get('description','')[:100]}\")
        print()
" 2>/dev/null || warn "Alertmanager에 접근할 수 없습니다."
}

# ---------------------------------------------------------------------------
cmd_targets() {
  echo ""
  echo "══════════════════════════════════════════"
  echo "  Prometheus Scrape Target 상태"
  echo "══════════════════════════════════════════"
  curl -sf "${PROMETHEUS_URL}/api/v1/targets" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
active = data.get('data', {}).get('activeTargets', [])
up_count   = sum(1 for t in active if t.get('health') == 'up')
down_count = sum(1 for t in active if t.get('health') != 'up')
print(f'총 타겟: {len(active)}개  /  UP: {up_count}  /  DOWN: {down_count}')
print()
downs = [t for t in active if t.get('health') != 'up']
if downs:
    print('🔴 다운된 타겟:')
    for t in downs:
        lbl = t.get('labels', {})
        print(f\"  - {lbl.get('job','?')} / {lbl.get('instance','?')} — {t.get('lastError','')[:80]}\")
else:
    print('✅  모든 타겟 정상')
" 2>/dev/null || warn "Prometheus에 접근할 수 없습니다."
}

# ---------------------------------------------------------------------------
cmd_backup() {
  info "Prometheus TSDB 스냅샷 생성 중..."
  RESULT=$(curl -sf -X POST "${PROMETHEUS_URL}/api/v1/admin/tsdb/snapshot")
  SNAP_NAME=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['name'])" 2>/dev/null || echo "")
  if [[ -n "$SNAP_NAME" ]]; then
    info "스냅샷 생성 완료: /prometheus/snapshots/${SNAP_NAME}"
  else
    error "스냅샷 생성 실패: $RESULT"
  fi
}

# ---------------------------------------------------------------------------
cmd_update() {
  info "최신 이미지 Pull 중..."
  docker compose -f "$COMPOSE_FILE" pull
  info "컨테이너 재시작..."
  docker compose -f "$COMPOSE_FILE" up -d
  info "업데이트 완료."
  cmd_status
}

cmd_build_fortigate() {
  local SRC_DIR="$(dirname "$COMPOSE_FILE")/fortigate-exporter/src"
  if [ ! -d "$SRC_DIR" ]; then
    info "소스 클론 중..."
    git clone https://github.com/prometheus-community/fortigate_exporter "$SRC_DIR"
  else
    info "소스 업데이트 중..."
    git -C "$SRC_DIR" pull
  fi
  info "fortigate-exporter 빌드 & 시작..."
  docker compose -f "$COMPOSE_FILE" up -d --build fortigate-exporter
  info "완료."
}

# ---------------------------------------------------------------------------
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  up)       cmd_up ;;
  down)     cmd_down ;;
  restart)  cmd_restart ;;
  status)   cmd_status ;;
  logs)     cmd_logs "${1:-}" ;;
  reload)   cmd_reload ;;
  validate) cmd_validate ;;
  alerts)   cmd_alerts ;;
  targets)  cmd_targets ;;
  build-fortigate) cmd_build_fortigate ;;
  update)   cmd_update ;;
  help|--help|-h) usage ;;
  *) error "알 수 없는 명령: $COMMAND"; usage; exit 1 ;;
esac
