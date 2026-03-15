# 🔍 Infrastructure Monitoring Stack

Prometheus 기반 온프레미스 인프라 통합 모니터링 시스템입니다.

물리 서버, KVM 가상화, Docker 컨테이너, 네트워크 장비(FortiGate UTM, Cisco, Netgear), Dell iDRAC 하드웨어, HAProxy 로드밸런서, GitLab CI/CD 파이프라인을 단일 스택으로 모니터링합니다.

---

## 📐 아키텍처

```
                    ┌─────────────────────────────────────────┐
                    │           Monitoring Server              │
                    │                                         │
  ┌──────────┐      │  ┌───────────┐    ┌──────────────────┐ │
  │  Servers │─────▶│  │Prometheus │───▶│    Grafana       │ │
  │ (Node    │      │  │ :9099     │    │    :38889        │ │
  │Exporter) │      │  └─────┬─────┘    └──────────────────┘ │
  └──────────┘      │        │                                │
                    │        ▼                                │
  ┌──────────┐      │  ┌───────────┐    ┌──────────────────┐ │
  │ Network  │─────▶│  │Alert      │───▶│  Jandi Adapter   │──▶ 잔디
  │  Devices │SNMP  │  │Manager    │    │  (DingTalk)      │ │
  │(FortiGate│      │  │ :9093     │    └──────────────────┘ │
  │ Cisco...)│      │  └───────────┘                         │
  └──────────┘      │                                         │
                    │  ┌───────────┐  ┌──────┐  ┌─────────┐ │
  ┌──────────┐      │  │  SNMP     │  │Black │  │HAProxy  │ │
  │  Dell    │─────▶│  │ Exporter  │  │ box  │  │Exporter │ │
  │  iDRAC   │      │  │  :9116    │  │:9115 │  │  :9101  │ │
  └──────────┘      │  └───────────┘  └──────┘  └─────────┘ │
                    └─────────────────────────────────────────┘
```

---

## 🧩 구성 컴포넌트

| 컴포넌트 | 버전 | 역할 |
|---|---|---|
| Prometheus | v2.51.2 | 메트릭 수집 엔진 (180일 보존) |
| Alertmanager | v0.28.1 | 알람 라우팅 / 중복 제거 / Inhibit |
| Grafana | v11.1.4 | 시각화 대시보드 |
| SNMP Exporter | v0.26.0 | 네트워크 장비 수집 |
| Blackbox Exporter | v0.25.0 | HTTP/TCP/ICMP 가용성 |
| HAProxy Exporter | v0.15.0 | HAProxy 메트릭 |
| Jandi Adapter | v2.1.0 | 잔디 Incoming Webhook 어댑터 |
| FortiGate Exporter | latest | FortiGate REST API (선택사항) |

---

## 📁 디렉토리 구조

```
monitoring/
├── docker-compose.yml
├── manage.sh                              # 운영 관리 스크립트
├── .env.example                           # 환경 변수 템플릿
├── .gitignore
│
├── prometheus/
│   ├── prometheus.yml                     # 수집 대상 설정
│   └── rules/
│       └── alert_rules.yml               # 알람 규칙 (8개 그룹)
│
├── alertmanager/
│   ├── alertmanager.yml                   # 라우팅 / Inhibit / Receiver
│   └── templates/
│       └── notification.tmpl             # 잔디 + Gmail 메시지 템플릿
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/prometheus.yml    # Prometheus 데이터소스 자동 연결
│   │   └── dashboards/clobot.yml        # 대시보드 자동 로드 설정
│   └── dashboards/
│       ├── clobot-overview.json         # 인프라 전체 현황 (커스텀)
│       ├── clobot-network.json          # 네트워크 장비 + FortiGate (커스텀)
│       └── clobot-idrac.json            # Dell iDRAC 하드웨어 (커스텀)
│
├── snmp-exporter/
│   └── snmp.yml                          # if_mib / fortigate_mib / dell_idrac
│
├── blackbox/
│   └── blackbox.yml                      # HTTP/TCP/ICMP 프로브 설정
│
├── jandi-adapter/
│   └── config.yml                        # 잔디 Webhook URL 설정
│
├── fortigate-exporter/
│   └── fortigate-key.yaml.example        # FortiGate API Token 예시
│
└── ansible/
    ├── inventory.ini.example             # 인벤토리 예시
    └── install_monitoring_agents.yml     # Node Exporter 일괄 설치 플레이북
```

---

## 🚀 빠른 시작

### 1. 저장소 클론

```bash
git clone https://github.com/your-org/monitoring.git
cd monitoring
```

### 2. 환경 변수 설정

```bash
cp .env.example .env
vi .env  # 비밀번호 및 토큰 입력
```

### 3. 필수 설정 파일 수정

**잔디 Webhook URL 설정:**
```bash
vi jandi-adapter/config.yml
# url: 'https://wh.jandi.com/connect-api/webhook/YOUR_ID/YOUR_TOKEN'
```

**Prometheus 수집 대상 설정:**
```bash
vi prometheus/prometheus.yml
# 서버 IP, 도메인을 실제 환경에 맞게 수정
```

**SNMP community 설정:**
```bash
vi snmp-exporter/snmp.yml
# your_community_name, your_community를 실제 값으로 변경
```

**Alertmanager 이메일 설정:**
```bash
vi alertmanager/alertmanager.yml
# smtp 설정 및 수신 이메일 주소 변경
```

### 4. 실행

```bash
# 설정 검증
./manage.sh validate

# 스택 시작
./manage.sh up

# 상태 확인
./manage.sh status
```

### 5. Grafana 접속

```
http://YOUR_SERVER_IP:38889
ID: admin / PW: .env에서 설정한 값
```

---

## 📊 모니터링 대상

### 서버 (Node Exporter)
- 물리 서버 / KVM 하이퍼바이저
- 개발 서버, GitLab, ERP 등

### KVM 가상화 (Libvirt Exporter)
- KVM VM CPU / 메모리 / 상태
- vstate 기반 VM 상태 알람

### 네트워크 장비 (SNMP)
- **FortiGate UTM** — if_mib + fortigate_mib (CPU/메모리/세션)
- **Cisco 스위치** — if_mib_standard
- **Axgate 장비** — if_mib_iptime

### 하드웨어 (Dell iDRAC SNMP)
- PowerEdge 서버 시스템 상태
- 온도 / 팬 속도 / 전력 소비

### 서비스 가용성 (Blackbox)
- HTTP/HTTPS 엔드포인트
- SSL 인증서 만료일 감지
- ICMP Ping

---

## 🚨 알람 규칙 (8개 그룹)

| 그룹 | 주요 알람 |
|---|---|
| **Availability** | InstanceDown (2분) |
| **NodeResources** | CPU 85/95%, 메모리 85/95%, 디스크 15/5%, IOWait, 재부팅 |
| **LibvirtVMs** | VM CPU 90%, VM Crashed, VM Paused |
| **Endpoints** | HTTP 다운, 응답지연 3초, SSL 만료 21일 전/만료됨 |
| **HAProxy** | 백엔드 다운, 서버 다운, 큐/응답 지연 |
| **FortiGate** | CPU 80%, 메모리 85%, 세션 50만 초과 |
| **iDRAC** | 시스템 WARNING/CRITICAL, 온도 70°C 초과 |
| **Containers** | CPU 90%, 메모리 90%(limit 설정 시), OOM Kill |

### Inhibit 규칙
- InstanceDown 발생 시 해당 인스턴스의 CPU/Memory/Disk Warning 자동 억제
- Critical 발생 시 같은 인스턴스의 Warning 억제

---

## 📈 Grafana 대시보드

### 자동 프로비저닝 (Grafana 시작 시 자동 로드)

| 대시보드 | 내용 |
|---|---|
| **Clobot Infra Overview** | Up/Down 현황, 알람 목록, SSL 만료, CPU/메모리, HAProxy 백엔드 |
| **Clobot Network Devices** | SNMP 트래픽, FortiGate CPU/세션/WAN 트래픽 |
| **Clobot iDRAC Hardware** | 시스템 상태, 온도/팬/전력 |

### 커뮤니티 대시보드 Import 권장

Grafana → Dashboards → New → Import → ID 입력

| ID | 대상 |
|---|---|
| **1860** | Node Exporter Full |
| **193** | Docker Monitoring (cAdvisor) |
| **16675** | HAProxy 2 Full |
| **7587** | Prometheus Blackbox Exporter |
| **11169** | SNMP Stats |
| **23230** | Libvirt KVM QEMU |
| **11303** | Dell iDRAC SNMP |
| **10620** | GitLab CI Pipelines |
| **13329** | GitLab CI Environments & Deployments |

---

## 🛠 관리 스크립트 (`manage.sh`)

모니터링 스택의 모든 운영 작업을 단일 스크립트로 처리합니다. `set -euo pipefail` 기반으로 오류 발생 시 즉시 중단하며, 컬러 로그(INFO/WARN/ERROR)로 상태를 명확히 출력합니다.

| 명령어 | 설명 | 상세 동작 |
|---|---|---|
| `up` | 스택 시작 | app-tier 네트워크 자동 생성, fortigate-exporter 소스 유무 감지 후 조건부 포함 |
| `down` | 스택 중지 | docker compose down |
| `restart` | 스택 재시작 | docker compose restart |
| `status` | 상태 확인 | 컨테이너 목록 + Prometheus/Alertmanager health 엔드포인트 자동 점검 |
| `logs [svc]` | 로그 확인 | 서비스명 생략 시 전체, 지정 시 해당 서비스만 tail -f |
| `reload` | **무중단 리로드** | validate 통과 시에만 `POST /-/reload` 실행 — 서비스 중단 없이 설정 반영 |
| `validate` | 설정 검사 | promtool(prometheus.yml + alert.rules.yml) + amtool(alertmanager.yml) 문법 검증 |
| `alerts` | 알람 목록 | Alertmanager API에서 현재 firing 알람을 심각도/인스턴스/내용과 함께 출력 |
| `targets` | 타겟 상태 | Prometheus API에서 전체 타겟 수, UP/DOWN 수, DOWN 타겟 상세(에러 메시지 포함) 출력 |
| `backup` | TSDB 스냅샷 | `POST /api/v1/admin/tsdb/snapshot` — 스냅샷명 및 경로 출력 |
| `build-fortigate` | FortiGate 빌드 | 소스 없으면 자동 git clone, 있으면 pull 후 docker compose build & up |
| `update` | 이미지 업데이트 | docker compose pull 후 up -d, 완료 후 status 자동 출력 |

```bash
# 가장 많이 쓰는 패턴
./manage.sh validate && ./manage.sh reload   # 설정 변경 후 안전 적용
./manage.sh targets                          # DOWN 타겟 즉시 확인
./manage.sh alerts                           # 현재 발화 알람 확인
./manage.sh logs prometheus                  # 특정 서비스 로그
./manage.sh backup                           # 데이터 백업 전 스냅샷
```

---

## 🤖 Ansible — Node Exporter 일괄 설치

```bash
# 인벤토리 파일 준비
cp ansible/inventory.ini.example dns_inventory.ini
vi dns_inventory.ini  # 실제 서버 정보 입력

# 전체 서버에 Node Exporter 설치
ansible-playbook -i dns_inventory.ini ansible/install_monitoring_agents.yml

# 특정 그룹만
ansible-playbook -i dns_inventory.ini ansible/install_monitoring_agents.yml \
  --limit dmz_servers
```

---

## 🔧 FortiGate Exporter 설정 (선택사항)

SNMP 대신 REST API로 더 풍부한 FortiGate 지표 수집 시:

```bash
# 소스 클론 및 빌드
./manage.sh build-fortigate

# API 토큰 설정
cp fortigate-exporter/fortigate-key.yaml.example \
   fortigate-exporter/fortigate-key.yaml
vi fortigate-exporter/fortigate-key.yaml  # 실제 토큰 입력

# docker-compose.yml에서 fortigate-exporter 주석 해제 후
./manage.sh up
```

**FortiGate에서 API 토큰 발급:**
FortiGate UI → System → Administrators → Create New → REST API Admin

---

## ⚠️ 보안 주의사항

- `.env` 파일은 절대 Git에 커밋하지 마세요
- `fortigate-exporter/fortigate-key.yaml`은 `.gitignore`에 포함됨
- 실제 서버 IP가 포함된 `dns_inventory.ini`는 Git에 올리지 마세요
- Prometheus UI(9099), Alertmanager(9093)는 내부 네트워크에서만 접근하도록 바인딩 권장

---

## 📋 요구사항

- Docker 20.10+
- Docker Compose v2.0+
- 모니터링 대상 서버에 Node Exporter 설치
- SNMP 지원 네트워크 장비 (community string 설정 필요)
- (선택) Ansible — Node Exporter 일괄 설치 시

---

## 📄 라이선스

MIT License
