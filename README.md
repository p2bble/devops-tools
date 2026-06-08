# DevOps Tools

온프레미스 인프라 운영에 필요한 범용 DevOps 도구 모음.  
Prometheus 모니터링 스택, 알람 어댑터, 서버 보고서, 네트워크 백업, GitOps CI/CD 템플릿을 포함합니다.

---

## 도구 목록

| 디렉토리 | 역할 |
|---------|------|
| [infrastructure-monitoring](#infrastructure-monitoring) | Prometheus + Grafana 모니터링 스택 |
| [system-monitor](#system-monitor) | 서버 HTML 보고서 자동 생성·이메일 발송 |
| [jandi-adapter](#jandi-adapter) | Alertmanager → Jandi/Slack webhook 어댑터 |
| [blackbox](#blackbox) | HTTP/ICMP/TCP 엔드포인트 프로브 설정 |
| [network-backup](#network-backup) | 네트워크 장비 설정 자동 백업 |
| [gitlab-cicd](#gitlab-cicd) | GitOps 인프라 배포 파이프라인 템플릿 |
| [scripts/backup](#scriptsbackup) | KVM·서비스·파일 백업 자동화 스크립트 |
| [ansible](#ansible) | Node Exporter·서버 초기 설정 플레이북 |
| [ssl-auto-renew](#ssl-auto-renew) | SSL 인증서 만료 모니터링·갱신 스크립트 |
| [asset-collector](#asset-collector) | Linux/Windows 서버 자산 정보 수집 도구 |

---

## infrastructure-monitoring

Prometheus 기반 온프레미스 + 클라우드 하이브리드 모니터링 스택.

| 컴포넌트 | 버전 | 역할 |
|---------|------|------|
| Prometheus | v2.52.0 | 메트릭 수집 |
| Alertmanager | v0.28.1 | 알람 라우팅·중복 제거 |
| Grafana | v11.1.4 | 대시보드 시각화 |
| SNMP Exporter | v0.26.0 | 네트워크 장비 (스위치/방화벽/AP) |
| Blackbox Exporter | v0.25.0 | HTTP/ICMP/SSL 가용성 |

**빠른 시작:**

```bash
cp .env.example .env
vi .env                      # GRAFANA_ADMIN_PASSWORD 등 설정
vi prometheus/prometheus.yml # [CUSTOMIZE] 구간 서버 IP 교체
docker compose up -d
./manage.sh status
```

대시보드: `overview` / `network` / `backup` / `log` / `idrac`  
알람 규칙: InstanceDown, HighCPU/Memory/Disk, BackupFailed, SSLExpiry, InterfaceDown 등 35개

---

## system-monitor

서버별 CPU·메모리·디스크 수치를 HTML 보고서로 생성하고 주간·월간 이메일 발송.

```bash
# 환경변수 설정
export SMTP_USER="report@example.com"
export SMTP_PASS="gmail-app-password"
export EMAIL_TO="admin@example.com"
export EMAIL_CC="manager@example.com"
export GRAFANA_URL="http://your-grafana:3000/d/overview"
export REPORT_BASE="/storage/system_monitor/reports"
export DATA_BASE="/storage/system_monitor/data"
export WEB_BASE="http://your-nas/system_monitor/reports"

# 발송
python3 send_report_email.py weekly    # 주간 보고서
python3 send_report_email.py monthly   # 월간 보고서
```

**기능:**
- 서버별 평균·최대 수치 (CSV 기반, 5분 간격 수집)
- 임계값 색상 표시 (✅ 정상 / ⚠️ 경고 / 🔴 위험)
- 동일 호스트 중복 보고서 자동 제거
- Grafana 실시간 링크 포함

---

## jandi-adapter

Alertmanager webhook을 Jandi 메시지 포맷으로 변환하는 Python 프록시.  
`JANDI_WEBHOOK_URL` 환경변수만 변경하면 Slack 등 다른 webhook으로도 전환 가능.

```bash
export JANDI_WEBHOOK_URL="https://wh.jandi.com/connect-api/webhook/..."
python3 jandi_proxy.py

# 또는 Docker
docker run -e JANDI_WEBHOOK_URL=... -p 5001:5001 python:3.11-slim python jandi_proxy.py
```

**Alertmanager 연동:**

```yaml
receivers:
  - name: jandi
    webhook_configs:
      - url: 'http://localhost:5001/alert'
        send_resolved: true
```

알람 반복 주기: critical 4h / warning 6h / info 24h

---

## blackbox

Blackbox Exporter 설정 템플릿. HTTP·ICMP·TCP 프로브 모듈 포함.

```yaml
# prometheus.yml 에 추가
- job_name: 'blackbox-http'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
        - https://your-service.example.com
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: localhost:9115
```

---

## network-backup

Netmiko 기반 네트워크 장비 설정 자동 백업.  
Cisco IOS, HP/Aruba, FortiGate(REST API) 지원. ThreadPoolExecutor 병렬 실행.

```bash
pip install netmiko requests
cp devices-config.example.json devices-config.json
vi devices-config.json   # 장비 IP·계정 입력
python3 network-config-backup.py
```

---

## gitlab-cicd

서버 설정 파일을 Git으로 관리하고 MR 머지 시 자동 배포하는 GitLab CI/CD 파이프라인 템플릿.

**파이프라인 동작:**

| 변경 경로 | 배포 방식 |
|----------|---------|
| `*/haproxy/**` | 수동 승인 → scp + restart |
| `*/prometheus/**` | 자동 hot-reload |
| `*/alertmanager/**` | 자동 hot-reload |
| `*/coredns/**` | 자동 scp + docker restart |
| `*/docker-compose.yml` | 수동 승인 |

사용법: `gitlab-cicd/gitlab-ci.yml.template` → `.gitlab-ci.yml`로 복사 후 IP/경로 수정

---

## scripts/backup

백업 자동화 스크립트 템플릿 (Prometheus textfile 연동으로 `BackupFailed` 알람 자동 연동).

| 스크립트 | 용도 |
|---------|------|
| `backup-vm.sh.example` | KVM VM 병렬 백업 |
| `backup-service.sh.example` | 서비스 파일 → NAS rsync |
| `backup-files.sh.example` | 서버 설정파일 → NAS rsync |

---

## ansible

Node Exporter 일괄 설치 및 서버 초기 설정 플레이북.

```bash
cp ansible/inventory.ini.example ansible/inventory.ini
vi ansible/inventory.ini   # 서버 목록 입력
ansible-playbook -i ansible/inventory.ini ansible/install_monitoring_agents.yml
```

---

## ssl-auto-renew

SSL 인증서 만료 모니터링 및 갱신 자동화 스크립트 모음.

```bash
# 만료 30일 전 Jandi 알림
bash script/check_ssl_expiry.sh your-domain.com

# Let's Encrypt 인증서 갱신 + 서버 배포
bash script/master_renewal_script.sh your-domain.com 2026 /etc/ssl/certs

# 모니터링 cron 설정
bash script/setup_ssl_monitor.sh
```

**기능:**
- 만료 30일·7일 전 경고 알림 (Jandi webhook)
- HAProxy·GitLab·Kubernetes·FortiGate 동시 배포
- cron 기반 자동 실행

---

## asset-collector

Linux/Windows 서버의 하드웨어·OS·소프트웨어 자산 정보를 CSV로 수집하는 도구.

```bash
# Linux
bash Linux/collect.sh

# Windows (PowerShell, 관리자 권한)
.\Windows\run_as_admin.bat

# 수집 결과 병합
bash merge/merge_results.sh   # Linux
.\merge\merge_results.bat     # Windows
```

**수집 항목:** CPU·메모리·디스크·OS·설치 소프트웨어·네트워크 인터페이스  
설정 파일: `config.txt` (저장 경로, 제외 항목 등)
