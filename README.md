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
                    │  ┌───────────┐  ┌──────┐  ┌─────────┐     │
  ┌──────────┐      │  │  SNMP     │  │Black │  │HAProxy  │     │
  │  Dell    │─────▶│  │ Exporter  │  │ box  │  │Exporter │     │
  │  iDRAC   │      │  │  :9116    │  │:9115 │  │  :9101  │     │
  └──────────┘      │  └───────────┘  └──────┘  └─────────┘     │
                    └──────────────────────┬──────────────────────┘
  ┌──────────┐                             │
  │ AWS EC2  │◀── ec2_sd_configs ──────────┘ (Public IP 경유)
  │(Node Exp)│    + YACE CloudWatch
  └──────────┘
```

### 네트워크 토폴로지

```
[인터넷] ── FortiGate FW ── HAProxy(172.19.100.10 / 172.18.100.48)
                │                    │
                ├── DMZ (172.19.100.x)
                │   ├── pdkcld1 (.10) — Monitoring Stack, KVM Host
                │   ├── dev-server (.20) — 개발 서버
                │   ├── clobot-erp (.11)
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
│   ├── prometheus.yml                     # 수집 대상 설정 (14개 job)
│   └── rules/
│       └── alert_rules.yml               # 알람 규칙 v2.3 (8개 그룹, 35개 룰)
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
├── aws-exporter/
│   └── config.yml                        # YACE CloudWatch 수집 설정
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

`.env` 파일에 필요한 변수:

```bash
GRAFANA_ADMIN_PASSWORD=your_password
HAPROXY_STATS_PASSWORD=your_password
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_REGION=ap-northeast-2
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
- 물리 서버 / KVM 하이퍼바이저 (pdkcld1, vm-server-01)
- 개발 서버, GitLab, ERP, Lions-Agent

### KVM 가상화 (Libvirt Exporter)
- KVM VM CPU / 메모리 / 상태 (vstate 기반)
- 운영 VM 가동 현황 모니터링 (9개 지정 VM)

### Docker 컨테이너 (cAdvisor)
- 컨테이너 CPU / 메모리 / OOM Kill 감지

### GitLab CI/CD
- 파이프라인 상태 / 성공률 (gitlab-ci-pipelines-exporter)
- GitLab Runner 상태 (Puma, Sidekiq, Workhorse, Redis, PostgreSQL)

### 네트워크 장비 (SNMP)
- **FortiGate UTM** — if_mib + fortigate_mib (CPU/메모리/세션)
- **Cisco 스위치** — if_mib_standard

### 하드웨어 (Dell iDRAC SNMP)
- PowerEdge 서버 시스템 상태 (5대)
- 온도 / 팬 속도 / 전력 소비

### 서비스 가용성 (Blackbox)
- HTTP/HTTPS 엔드포인트 (monitor, scope, ERP)
- SSL 인증서 만료일 감지
- ICMP Ping

### AWS (EC2 + CloudWatch)
- **EC2 Auto-Discovery**: `ec2_sd_configs`로 running 인스턴스 자동 발견 (Public IP 경유)
- **CloudWatch**: YACE 경유 RDS, ALB 등 메트릭 (5분 간격)

---

## 🌐 AWS EC2 모니터링 연동

### 사전 요구사항
- AWS IAM 키 (EC2 DescribeInstances + CloudWatch GetMetricData 권한)
- EC2 Security Group에서 9100/TCP 포트를 사무실 공인IP에 허용
- EC2 인스턴스에 Node Exporter 설치

### Node Exporter 설치 (EC2)

```bash
cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
tar xzf node_exporter-1.8.1.linux-amd64.tar.gz
sudo cp node_exporter-1.8.1.linux-amd64/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

### 새 EC2 인스턴스 추가 시

Prometheus가 `ec2_sd_configs`로 자동 발견하므로 설정 변경 불필요. 해야 할 것:

1. EC2에 Node Exporter 설치 (위 스크립트)
2. Security Group에 9100/TCP 허용 (소스: 사무실 공인IP)
3. 1~2분 후 Grafana 대시보드에 자동 표시

### 다른 리전 EC2 추가 시

`prometheus.yml`에 해당 리전의 job 추가 필요:

```yaml
  - job_name: 'aws-ec2-node-exporter-us'
    ec2_sd_configs:
      - region: 'us-east-1'
        port: 9100
    relabel_configs:
      - source_labels: [__meta_ec2_instance_state]
        regex: running
        action: keep
      - source_labels: [__meta_ec2_tag_Name]
        target_label: nodename
      - source_labels: [__meta_ec2_public_ip]
        target_label: __address__
        replacement: '${1}:9100'
```

---

## 🚨 알람 규칙 v2.3 (8개 그룹)

| 그룹 | 주요 알람 | 비고 |
|---|---|---|
| **Availability** | InstanceDown (2분), AwsInstanceUnreachable (info/10분) | AWS는 별도 severity로 분리 |
| **NodeResources** | CPU 85/95%, 메모리 85/95%, 디스크 15/5%, IOWait, 재부팅 | |
| **LibvirtVMs** | VM CPU vCPU당 85/95%, VM Crashed, VM Paused | vCPU 수 대비 정규화 |
| **Endpoints** | HTTP 다운, 응답지연 5초/10분, SSL 만료 21일 전/만료됨 | 임계치 완화 (v2.2: 3초/5분) |
| **HAProxy** | 백엔드 다운, 서버 다운, 큐/응답 지연 | |
| **FortiGate** | CPU 80%, 메모리 85%, 세션 50만 초과 | |
| **iDRAC** | 시스템 WARNING/CRITICAL, 온도 70°C 초과 | |
| **Containers** | CPU 90%, 메모리 90%(limit 설정 시), OOM Kill | |

### v2.2 → v2.3 변경사항 (2026-03-18)
- **InstanceDown**: `aws-ec2-node-exporter` job 제외, 별도 `AwsInstanceUnreachable` (severity: info) 신설
- **VMHighCpuUsage**: vCPU 수로 정규화 (`/ libvirt_domain_info_virtual_cpus`), 임계치 85%/15분 + critical 95%/5분
- **HttpSlowResponse**: 임계치 3초/5분 → 5초/10분 완화

### Inhibit 규칙
- InstanceDown 발생 시 해당 인스턴스의 CPU/Memory/Disk Warning 자동 억제
- Critical 발생 시 같은 인스턴스의 Warning 억제

---

## 📈 Grafana 대시보드

### Clobot Infra Overview (상단 패널)

| 위치 | 패널 | PromQL |
|---|---|---|
| 1 | 🟢 온라인 인스턴스 | `count(up{job=~"node-exporter\|aws-ec2-node-exporter"} == 1)` |
| 2 | 🔴 오프라인 인스턴스 | `count(up{...} == 0)` |
| 3 | ⚠️ 활성 알람 | `count(ALERTS{alertstate="firing"})` |
| 4 | 🖥️ 운영 VM 가동 | `count(libvirt_domain_info_vstate{domain=~"..."} == 1)` |
| 5 | 🚀 CI 파이프라인 성공률 | `count(gitlab_ci_pipeline_status == 1) / count(gitlab_ci_pipeline_status) * 100` |
| 6 | 💾 가용 디스크 최소값 | `min(node_filesystem_avail_bytes / node_filesystem_size_bytes * 100)` |

### 운영 VM 목록 (패널 4 대상)

| 호스트 | VM |
|---|---|
| pdkcld1 | croms-p2-staging, croms-rx-UXUI, croms-rx-core-dev, croms-rx-core-stage, croms-rx-dev, high-tech-dev, k8s-rx-dev-master |
| vm-server-01 | finance-vm-01, sonarQube |

### 자동 프로비저닝 대시보드

| 대시보드 | 내용 |
|---|---|
| **Clobot Infra Overview** | Up/Down, 알람, VM 가동, CI 성공률, SSL, CPU/메모리, HAProxy |
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

## 🔧 네트워크 설정 주의사항

### DNS (CoreDNS)

Blackbox Exporter는 내부 도메인을 CoreDNS(vm-server-01, 172.18.100.20:53)를 통해 해석합니다.
CoreDNS는 `source.clobot.co.kr`, `monitor.clobot.co.kr` 등을 HAProxy 내부IP(172.18.100.48)로 매핑하여 Hairpin NAT 문제를 방지합니다.

```yaml
# docker-compose.yml — blackbox-exporter
dns:
  - 172.18.100.20    # CoreDNS (vm-server-01)
  - 8.8.8.8          # Fallback
```

> **주의**: DNS IP 오타(예: `172.10.x` vs `172.18.x`) 시 CoreDNS를 못 찾고 외부 DNS로 fallback → 공인IP로 해석 → Hairpin NAT 실패 → probe 장애로 이어집니다.

### Blackbox Exporter 네트워크

Blackbox Exporter는 `monitoring-tier` + `app-tier` 두 Docker 네트워크에 연결되어야 합니다.
`app-tier`가 없으면 내부 대역(172.18.x/172.19.x) 접근이 불가합니다.

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
- AWS EC2 Node Exporter(9100)는 사무실 공인IP만 SG에서 허용

---

## 📋 요구사항

- Docker 20.10+
- Docker Compose v2.0+
- 모니터링 대상 서버에 Node Exporter 설치
- SNMP 지원 네트워크 장비 (community string 설정 필요)
- (AWS) IAM 키 — EC2 DescribeInstances + CloudWatch GetMetricData
- (선택) Ansible — Node Exporter 일괄 설치 시

---

## 📝 변경 이력

### v2.3 (2026-03-18)
- **AWS 연동**: EC2 Auto-Discovery (`ec2_sd_configs`, Public IP 경유) + YACE CloudWatch Exporter 추가
- **DNS 수정**: Blackbox Exporter DNS `172.10.100.20`(오타) → `172.18.100.20`(CoreDNS) 수정, Hairpin NAT 문제 해결
- **Blackbox 네트워크**: `app-tier` 네트워크 추가로 내부 대역 접근 가능
- **Alert Rules v2.3**: AWS InstanceDown 분리(info), VM CPU vCPU 정규화, HTTP 응답 임계치 완화(5초/10분)
- **대시보드 개선**: 상단 패널 교체 — HTTP 엔드포인트→운영 VM 가동 현황, SSL 만료→CI 파이프라인 성공률
- **prometheus.yml**: TCP 블록 orphaned `relabel_configs` YAML 에러 수정

### v2.2 (2026-03-15)
- Alert Rules 초기 구성 (8개 그룹)
- Libvirt VM 모니터링 추가
- Dell iDRAC SNMP 모니터링 추가

### v2.0 (2026-03)
- Monitoring Stack 초기 구축
- Prometheus + Alertmanager + Grafana + Exporters

---

## 📄 라이선스

MIT License
