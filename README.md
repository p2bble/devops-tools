# Infrastructure Monitoring Stack

Prometheus 기반 온프레미스 + 클라우드 하이브리드 인프라 통합 모니터링 템플릿.

물리 서버, KVM 가상화, Docker 컨테이너, 네트워크 장비(SNMP), HTTP/ICMP 엔드포인트, SSL 인증서, AWS CloudWatch를 단일 스택으로 모니터링합니다.

---

## 스택 구성

| 컴포넌트 | 버전 | 역할 |
|---------|------|------|
| Prometheus | v2.52.0 | 메트릭 수집 엔진 |
| Alertmanager | v0.28.1 | 알람 라우팅 및 중복 제거 |
| Grafana | v11.1.4 | 시각화 대시보드 |
| SNMP Exporter | v0.26.0 | 네트워크 장비 (스위치, 방화벽, AP) |
| Blackbox Exporter | v0.25.0 | HTTP/ICMP/SSL 엔드포인트 가용성 |
| Jandi Adapter | v2.1.0 | 알람 → Webhook 연동 (잔디/Slack/Teams 교체 가능) |

**선택적 서비스** (docker-compose.yml 주석 해제):
- HAProxy Exporter — HAProxy 로드밸런서 사용 시
- FortiGate Exporter — FortiGate UTM REST API
- AWS CloudWatch Exporter (YACE) — AWS EC2/RDS/ALB

---

## 빠른 시작

```bash
git clone https://github.com/p2bble/infrastructure-monitoring.git
cd infrastructure-monitoring

# 1. 환경 변수 설정
cp .env.example .env
vi .env   # GRAFANA_ADMIN_PASSWORD, GMAIL_APP_PASSWORD 등 입력

# 2. 서버 목록 설정 (필수)
vi prometheus/prometheus.yml   # [CUSTOMIZE] 구간의 IP/nodename 교체

# 3. 알람 수신 설정
vi alertmanager/alertmanager.yml   # 이메일 주소 교체

# 4. 실행
docker compose up -d

# 5. 상태 확인
./manage.sh status
```

| 서비스 | 기본 포트 | 비고 |
|--------|---------|------|
| Grafana | :3000 | `admin` / `.env` 비밀번호 |
| Prometheus | :9099 | 메트릭 쿼리 |
| Alertmanager | :9093 | 알람 현황 |

---

## 커스터마이징 가이드

### 1. 서버 추가 (`prometheus/prometheus.yml`)

`[CUSTOMIZE]` 주석이 있는 구간의 IP와 `nodename` 레이블을 실제 서버로 교체합니다.

```yaml
- job_name: 'node-exporter'
  static_configs:
    - targets: ['실제서버IP:9100']
      labels:
        nodename: '서버명'
        role: 'app'   # infra / app / db / dev 등 자유롭게 정의
```

Node Exporter 설치 (각 서버에서):
```bash
docker run -d --name node-exporter --net="host" --pid="host" \
  -v "/:/host:ro,rslave" \
  prom/node-exporter --path.rootfs=/host
```

### 2. 알람 채널 변경 (`alertmanager/alertmanager.yml`)

기본 채널은 잔디(Jandi) Webhook입니다. 다른 메신저로 교체 시:

| 메신저 | 교체 방법 |
|--------|---------|
| **Slack** | `webhook_configs.url` → Slack Incoming Webhook URL |
| **Teams** | `webhook_configs.url` → Teams Connector URL |
| **Telegram** | [alertmanager-bot](https://github.com/metalmatze/alertmanager-bot) 사용 |
| **PagerDuty** | `pagerduty_configs` 섹션 사용 |

### 3. 대시보드 목록 (`grafana/dashboards/`)

| 파일 | 내용 |
|------|------|
| `overview.json` | 전체 인프라 현황 (CPU/메모리/디스크/알람) |
| `network.json` | 네트워크 장비 트래픽 및 상태 |
| `backup.json` | 백업 성공/실패 현황 |
| `log.json` | Graylog/로그 수집 현황 |
| `idrac.json` | Dell iDRAC 하드웨어 센서 |

### 4. 네트워크 장비 SNMP (`snmp-exporter/snmp.yml`)

지원 모듈:
- `if_mib` — 범용 스위치/라우터 (Cisco, HP, 기타)
- `fortigate` — FortiGate UTM
- `aruba_cx` — Aruba 스위치

### 5. 선택 서비스 활성화 (`docker-compose.yml`)

`docker-compose.yml` 하단의 주석을 해제하면 됩니다.

```bash
# FortiGate Exporter 사용 시
cp fortigate-exporter/fortigate-key.yaml.example fortigate-exporter/fortigate-key.yaml
vi fortigate-exporter/fortigate-key.yaml   # FortiGate IP / API Token 입력
```

---

## 알람 규칙 (`prometheus/rules/alert.rules.yml`)

| 그룹 | 주요 알람 |
|------|---------|
| 서버 가용성 | InstanceDown, HighCPU, HighMemory, DiskSpaceLow |
| 백업 | BackupFailed, BackupStale |
| SSL 인증서 | SSLCertExpirySoon (30일/7일) |
| 네트워크 | InterfaceDown, HighBandwidth |
| 하드웨어 | iDRAC 온도/팬/전원 이상 |

---

## 디렉토리 구조

```
.
├── docker-compose.yml
├── .env.example
├── manage.sh                   # 스택 관리 스크립트
├── prometheus/
│   ├── prometheus.yml          # ← 서버 목록 커스터마이징 필수
│   └── rules/
│       └── alert.rules.yml     # 알람 규칙 35개
├── alertmanager/
│   ├── alertmanager.yml        # ← 수신 이메일/채널 설정
│   └── templates/
│       └── notification.tmpl
├── grafana/
│   ├── provisioning/
│   └── dashboards/
│       ├── overview.json
│       ├── network.json
│       ├── backup.json
│       ├── log.json
│       └── idrac.json
├── snmp-exporter/
│   └── snmp.yml
├── blackbox/
│   └── blackbox.yml
├── fortigate-exporter/         # FortiGate 사용 시
│   └── fortigate-key.yaml.example
└── ansible/
    ├── install_monitoring_agents.yml   # Node Exporter 일괄 설치
    └── inventory.ini.example
```

---

## 관련 자료

- [Prometheus 문서](https://prometheus.io/docs/)
- [Grafana 문서](https://grafana.com/docs/)
- [Alertmanager 문서](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [SNMP Exporter](https://github.com/prometheus/snmp_exporter)
