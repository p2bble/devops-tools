# 🔍 Infrastructure Monitoring Stack

Prometheus 기반 온프레미스 + AWS 하이브리드 인프라 통합 모니터링 시스템입니다.

물리 서버, KVM 가상화, Docker 컨테이너, 네트워크 장비(FortiGate UTM, Cisco, Netgear), Dell iDRAC 하드웨어, HAProxy 로드밸런서, GitLab CI/CD 파이프라인, AWS EC2/CloudWatch를 단일 스택으로 모니터링합니다.

---

## 📐 아키텍처

```
                    ┌─────────────────────────────────────────────┐
                    │           Monitoring Server (pdkcld1)        │
                    │           172.19.100.10 (DMZ)                │
  ┌──────────┐      │  ┌───────────┐    ┌──────────────────┐     │
  │  Servers │─────▶│  │Prometheus │───▶│    Grafana       │     │
  │ (Node    │      │  │ :9099     │    │    :38889        │     │
  │Exporter) │      │  └─────┬─────┘    └──────────────────┘     │
  └──────────┘      │        │                                    │
                    │        ▼                                    │
  ┌──────────┐      │  ┌───────────┐    ┌──────────────────┐     │
  │ Network  │─────▶│  │Alert      │───▶│  Jandi Adapter   │────▶ 잔디
  │  Devices │SNMP  │  │Manager    │    │  (DingTalk)      │     │
  │(FortiGate│      │  │ :9093     │    └──────────────────┘     │
  │ Cisco...)│      │  └───────────┘                              │
  └──────────┘      │                                             │
  ┌──────────┐ REST │  ┌───────────┐  ┌──────┐  ┌─────────┐     │
  │FortiGate │─────▶│  │ FortiGate │  │Black │  │HAProxy  │     │
  │  UTM     │  API │  │ Exporter  │  │ box  │  │Exporter │     │
  └──────────┘      │  │  :9710    │  │:9115 │  │  :9101  │     │
                    │  └───────────┘  └──────┘  └─────────┘     │
  ┌──────────┐      │  ┌───────────┐                              │
  │  Dell    │─────▶│  │  SNMP     │                              │
  │  iDRAC   │      │  │ Exporter  │                              │
  └──────────┘      │  │  :9116    │                              │
                    └──────────────────────┬──────────────────────┘
  ┌──────────┐                             │
  │ AWS EC2  │◀── ec2_sd_configs ──────────┘ (Public IP 경유)
  │(Node Exp)│    + YACE CloudWatch
  └──────────┘
```

### 네트워크 토폴로지

```
[인터넷] ── FortiGate FW ── HAProxy(172.19.100.10 / 172.18.100.48)
                │
                ├── DMZ (172.19.100.x)
                │   ├── pdkcld1 (.10) — Monitoring Stack, KVM Host
                │   ├── dev-server (.20) — 개발 서버
                │   └── lions-agent (.21)
                │
                └── Internal (172.18.100.x)
                    ├── vm-server-01 (.20) — KVM Host, CoreDNS, GitLab Runner
                    └── gitlab-srv (.21) — GitLab CE
```

---

## 🧩 구성 컴포넌트

| 컴포넌트 | 버전 | 역할 |
|---|---|---|
| Prometheus | v2.52.0 | 메트릭 수집 엔진 (180일 보존, 50GB) |
| Alertmanager | v0.28.1 | 알람 라우팅 / 중복 제거 / Inhibit |
| Grafana | v11.1.4 | 시각화 대시보드 |
| SNMP Exporter | v0.26.0 | 네트워크 장비 수집 |
| Blackbox Exporter | v0.25.0 | HTTP/TCP/ICMP 가용성 |
| HAProxy Exporter | v0.15.0 | HAProxy 메트릭 |
| Jandi Adapter | v2.1.0 | 잔디 Incoming Webhook 어댑터 |
| YACE | v0.55.0 | AWS CloudWatch Exporter |
| FortiGate Exporter | latest | FortiGate REST API (인터페이스 실명칭/FortiAP/WiFi) |

---

## 📁 디렉토리 구조

```
infrastructure-monitoring/
├── docker-compose.yml
├── manage.sh
├── .env.example
│
├── prometheus/
│   ├── prometheus.yml                     # 수집 대상 설정 (17개 job)
│   └── rules/alert_rules.yml             # 알람 규칙 (8개 그룹, 35개 룰)
│
├── alertmanager/
│   ├── alertmanager.yml
│   └── templates/notification.tmpl
│
├── grafana/
│   ├── provisioning/
│   └── dashboards/
│       ├── clobot-overview.json          # 인프라 전체 현황
│       ├── clobot-network.json           # 네트워크 + FortiGate + FortiAP
│       ├── clobot-backup.json            # 백업 성공/실패 현황
│       ├── clobot-graylog.json           # Graylog 로그 분석
│       └── clobot-idrac.json             # Dell iDRAC 하드웨어
│
├── snmp-exporter/snmp.yml
├── blackbox/blackbox.yml
├── aws-exporter/config.yml
├── jandi-adapter/config.yml
├── fortigate-exporter/
│   └── fortigate-key.yaml.example
└── ansible/
    ├── inventory.ini.example
    └── install_monitoring_agents.yml
```

---

## 🚀 빠른 시작

```bash
git clone https://github.com/p2bble/infrastructure-monitoring.git
cd infrastructure-monitoring

# 환경 변수 설정
cp .env.example .env
vi .env

# FortiGate API 토큰 설정
cp fortigate-exporter/fortigate-key.yaml.example fortigate-exporter/fortigate-key.yaml
vi fortigate-exporter/fortigate-key.yaml

# 실행
./manage.sh validate && ./manage.sh up
```

Grafana: `http://YOUR_SERVER:38889` (admin / .env 설정값)

---

## 📊 Prometheus Job 목록 (17개)

| # | Job | 대상 | 비고 |
|---|---|---|---|
| 1 | prometheus | localhost:9099 | Self-monitoring |
| 2 | node-exporter | pdkcld1, vm-server-01, dev-server 등 | OS 메트릭 |
| 3 | libvirt-exporter | pdkcld1, vm-server-01 | KVM VM 상태 |
| 4 | cadvisor | dev-server | Docker 컨테이너 |
| 5 | gitlab | gitlab-srv 컴포넌트 7개 | GitLab 전체 |
| 6 | gitlab-ci-pipelines | gitlab-srv:8080 | CI 파이프라인 |
| 7 | haproxy | haproxy-exporter:9101 | 로드밸런서 |
| 8 | blackbox-http | monitor, scope, ERP 등 | HTTP/HTTPS 가용성 |
| 9 | blackbox-http-insecure | source.clobot.co.kr | GitLab HTTPS |
| 10 | blackbox-icmp | 내부 서버 4대 | ICMP Ping |
| 11 | snmp | FortiGate, Cisco 등 | 인터페이스 트래픽 |
| 12 | snmp-fortigate | FortiGate 2대 | FortiGate MIB |
| 13 | idrac | iDRAC 5대 (172.18.100.240~245) | Dell 하드웨어 |
| 14 | aws-cloudwatch | aws-exporter:5000 | CloudWatch (YACE) |
| 15 | aws-ec2-node-exporter | ap-northeast-2 EC2 자동발견 | AWS 서울 |
| 16 | aws-ec2-node-exporter-us | us-east-1 EC2 자동발견 | AWS 버지니아 |
| **17** | **fortigate** | **fortigate-exporter:9710 → 172.19.100.1** | **REST API (DMZ)** |
| **18** | **fortigate-dev** | **fortigate-exporter:9710 → 172.18.100.1** | **REST API (Internal)** |

---

## 🚨 알람 규칙 (8개 그룹, 35개 룰)

| 그룹 | 주요 알람 |
|---|---|
| Availability | InstanceDown (2분), AwsInstanceUnreachable (info) |
| NodeResources | CPU 85/95%, 메모리 85/95%, 디스크 15/5%, IOWait |
| LibvirtVMs | VM CPU (vCPU 정규화) 85/95%, Crashed, Paused |
| Endpoints | HTTP 다운, 응답지연 5초/10분, SSL 만료 21일 전 |
| HAProxy | 백엔드/서버 다운, 큐/응답 지연 |
| FortiGate | CPU 80%, 메모리 85%, 세션 50만 초과 |
| iDRAC | 시스템 WARNING/CRITICAL, 온도 70°C 초과 |
| Containers | CPU 90%, 메모리 90%, OOM Kill |

**Inhibit 규칙:** InstanceDown 시 해당 인스턴스 Warning 자동 억제

---

## 📈 Grafana 대시보드

| 대시보드 | 주요 내용 |
|---|---|
| Clobot Infra Overview | Up/Down, 알람, VM 가동, CI 성공률, SSL, CPU/메모리 |
| Clobot Network Devices | SNMP 트래픽, FortiGate CPU/세션, FortiAP/WiFi 모니터링 |
| Clobot Backup Status | 항목별 백업 성공/실패, 파일 크기 트렌드 |
| Clobot Graylog Log Analysis | 로그 볼륨, 에러 추세, SSH 인증 실패 |
| Clobot iDRAC Hardware | 시스템 상태, 온도/팬/전력 |

### Network 대시보드 주요 PromQL

```promql
# 물리 포트 다운 수 (가상 인터페이스 제외)
count(fortigate_interface_link_up{name=~"port[0-9]+|x[0-9]+"} == 0) or vector(0)

# 연결 AP 수
sum(fortigate_wifi_access_points{status="active"})

# WiFi 클라이언트 수
sum(fortigate_wifi_fabric_clients)

# AP별 클라이언트 수 (timeseries)
sum by(ap_name)(fortigate_wifi_managed_ap_radio_client_count)
```

### 커뮤니티 대시보드 추천 ID

| ID | 대상 |
|---|---|
| 1860 | Node Exporter Full |
| 193 | Docker Monitoring (cAdvisor) |
| 16675 | HAProxy 2 Full |
| 7587 | Prometheus Blackbox Exporter |
| 23230 | Libvirt KVM QEMU |
| 11303 | Dell iDRAC SNMP |
| 10620 | GitLab CI Pipelines |

---

## 🛠 manage.sh 명령어

```bash
./manage.sh validate && ./manage.sh reload   # 설정 변경 후 무중단 적용
./manage.sh targets                          # DOWN 타겟 확인
./manage.sh alerts                           # 현재 발화 알람
./manage.sh logs prometheus                  # 서비스 로그
./manage.sh backup                           # TSDB 스냅샷
```

| 명령 | 동작 |
|---|---|
| up / down / restart | 스택 시작/중지/재시작 |
| status | 컨테이너 + Health 엔드포인트 확인 |
| reload | validate 통과 시에만 무중단 리로드 |
| validate | promtool + amtool 검증 |
| alerts | firing 알람 목록 |
| targets | UP/DOWN 타겟 상세 |
| backup | TSDB 스냅샷 |

---

## 🔧 FortiGate Exporter 설정

SNMP 대비 이점: 인터페이스 실명칭(한글 VLAN명), FortiAP/WiFi 클라이언트, CPU per-core 수집.
Docker Hub 이미지 사용으로 별도 빌드 불필요.

```bash
cp fortigate-exporter/fortigate-key.yaml.example fortigate-exporter/fortigate-key.yaml
vi fortigate-exporter/fortigate-key.yaml
./manage.sh up
```

**필수 주의사항:**
- 최상위 키는 FortiGate URL 직접 사용 (`targets:` 래퍼 사용 금지 → "no API authentication" 오류)
- `Switch/ManagedSwitch` probe 반드시 exclude (FortiSwitch 중복 메트릭 1400+건 방지)
- FortiGate admin 포트 확인: CLI `get system global` → `admin-sport` 값
- API 토큰 발급: FortiGate GUI → System → Administrators → REST API Admin

---

## 🌐 AWS EC2 연동

EC2 Auto-Discovery로 running 인스턴스를 자동 발견합니다.
새 EC2 추가 시: Node Exporter 설치 + SG에서 9100/TCP 허용만 하면 자동 수집.

IAM 권한: `EC2 DescribeInstances` + `CloudWatch GetMetricData`

---

## 🔧 네트워크 주의사항

- **Blackbox DNS**: `172.18.100.20` (CoreDNS) — 내부 도메인을 HAProxy 내부IP로 해석해 Hairpin NAT 방지
- **Blackbox 네트워크**: `app-tier` + `monitoring-tier` 두 네트워크 연결 필요

---

## ⚠️ 보안 주의사항

- `.env`, `fortigate-key.yaml`, `dns_inventory.ini`는 Git 커밋 금지
- Prometheus(9099), Alertmanager(9093)는 localhost 바인딩
- AWS EC2 Node Exporter(9100)는 사무실 공인IP만 SG 허용

---

## 📝 변경 이력

### v2.4 (2026-05-07)
- **FortiGate Exporter 정식 배포**: 로컬 빌드 제거, Docker Hub `prometheuscommunity/fortigate-exporter:latest` 전환
- **Prometheus job 추가**: `fortigate` (172.19.100.1), `fortigate-dev` (172.18.100.1) — REST API (job 17, 18)
- **Network 대시보드 개선**: 인터페이스 실명칭(한글 VLAN명), FortiAP/WiFi 패널 6개 신규 (연결 AP 수, WiFi 클라이언트, 메모리, AP별 클라이언트/트래픽)
- **신규 대시보드**: Clobot Backup Status, Clobot Graylog Log Analysis
- **대시보드 한글 인코딩 수정**: Backup/Graylog 패널 제목 깨짐(U+FFFD) 전체 수정
- **fortigate-key.yaml.example 갱신**: 올바른 포맷 및 트러블슈팅 주석

### v2.3 (2026-03-18)
- AWS EC2 Auto-Discovery + YACE CloudWatch Exporter 추가
- Blackbox DNS 오타 수정 (172.10.x → 172.18.x), Hairpin NAT 해결
- Alert Rules v2.3: AWS InstanceDown 분리, VM CPU vCPU 정규화, HTTP 임계치 완화

### v2.2 (2026-03-15)
- Alert Rules 초기 구성, Libvirt VM, Dell iDRAC SNMP 모니터링 추가

### v2.0 (2026-03)
- Monitoring Stack 초기 구축 (Prometheus + Alertmanager + Grafana)

---

## 📄 라이선스

MIT License
