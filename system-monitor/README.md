# System Monitor — 인프라 자동 보고서 시스템

서버별 시스템 리소스(CPU·메모리·디스크·VM·Docker)를 수집해 HTML 보고서를 생성하고,
주간/월간 보고서를 NAS에 저장한 뒤 이메일로 통합 발송하는 자동화 시스템.

## 적용 서버

| 서버 | IP | 역할 |
|---|---|---|
| monitor-01 | 172.18.100.48 | 모니터링 서버 / KVM 호스트 / **이메일 발송 담당** |
| vm-server-01 | 172.18.100.20 | KVM 호스트 / GitLab Runner |
| vm-server-02 | 172.19.100.20 | cAdvisor |
| gitlab | 172.18.100.21 | GitLab CE |

## 파일 구조

```
system-monitor/
├── system_monitor.sh          # 메인 모니터링·보고서 생성 스크립트
├── send_report_email.py       # 통합 이메일 발송 스크립트 (monitor-01 전용)
├── config/
│   ├── system_monitor.conf    # 메인 설정 (Jandi 웹훅, 이메일, 알림 간격 등)
│   └── thresholds.conf        # 임계값 설정 (CPU/메모리/디스크 경고·위험 기준)
└── systemd/
    ├── system_monitor-daily.service
    ├── system-monitor-daily.timer          # 매일 06:00
    ├── system_monitor-weekly.service
    ├── system-monitor-weekly.timer         # 매주 월요일 06:00
    ├── system_monitor-monthly.service
    ├── system-monitor-monthly.timer        # 매월 1일 06:00
    ├── system-monitor-weekly-email.service
    ├── system-monitor-weekly-email.timer   # 매주 월요일 06:15
    ├── system-monitor-monthly-email.service
    └── system-monitor-monthly-email.timer  # 매월 1일 06:15
```

## 보고서 저장 위치

NAS(`172.18.100.10`) NFS 마운트: `/storage/system_monitor/`

| 종류 | 경로 | URL |
|---|---|---|
| 일간 | `/storage/system_monitor/reports/daily/` | `http://172.18.100.10/system_monitor/reports/daily/` |
| 주간 | `/storage/system_monitor/reports/weekly/` | `http://172.18.100.10/system_monitor/reports/weekly/` |
| 월간 | `/storage/system_monitor/reports/monthly/` | `http://172.18.100.10/system_monitor/reports/monthly/` |
| 성능 CSV | `/storage/system_monitor/data/{hostname}/` | 이메일 스크립트 참조용 |

파일명 형식: `{hostname}_{type}_report_{date}.html`

## 보고서 내용

### 공통 섹션
| 섹션 | 내용 |
|---|---|
| 요약 카드 | CPU·메모리·디스크 사용률 + 업타임 (색상 코딩: 🟢 정상 / 🟡 경고 / 🔴 위험) |
| 1. CPU 상태 | 현재 사용률 · 로드 애버리지 + **주간/월간 평균·최대** |
| 2. 메모리 & SWAP | 사용량 · 비율 + **주간/월간 평균·최대** |
| 3. 디스크 | 마운트별 사용량 |
| 4. 네트워크 | 활성 TCP 연결 수 |
| 5. 가상머신 | 메모리·디스크 현황 (KVM 호스트 전용) |
| 7. Docker | 컨테이너 상태 목록 (Up=녹색 / 중지=빨강) |

### 주간·월간 트렌드 (평균·최대)
CPU와 메모리 섹션에 5분 간격 수집 데이터 기반 집계가 추가됩니다.

- **주간 보고서**: 직전 7일 평균·최대
- **월간 보고서**: 해당 월 전체 평균·최대
- CSV 데이터가 없으면 해당 행은 표시되지 않음

### 월간 전용
- 성능 트렌드 섹션: 월 전체 CPU·메모리·디스크 평균/최대/최소 집계

## 이메일 보고서

`send_report_email.py`가 NAS에서 4개 서버 보고서를 읽어 1통으로 합산 발송.

### 발송 설정
| 항목 | 값 |
|---|---|
| 발신 | stephen@clobot.co.kr |
| 수신(To) | stephen@clobot.co.kr |
| 참조(Cc) | paul2@clobot.co.kr, kyu@clobot.co.kr |
| 주간 발송 | 매주 월요일 06:15 (보고서 생성 15분 후) |
| 월간 발송 | 매월 1일 06:15 |

### 이메일 내용
- 헤더: 보고서 기간 · 전체 상태 · **📡 실시간 모니터링 → (Grafana 링크)**
- 서버별 수치: **CSV 기반 주간/월간 평균·최대** (CSV 없을 경우 스냅샷 fallback)
- 색상 코딩: ✅ 정상 / ⚠️ 경고 / 🔴 위험

```
실시간 모니터링 URL:
https://monitor.clobot.co.kr/d/clobot-overview/clobot-infra-overview?orgId=1&refresh=30s
```

## 성능 데이터 수집 (CSV)

root crontab: `*/5 * * * * /usr/local/bin/system_monitor.sh saveperf`

- 저장 경로(로컬): `/opt/system_monitor/data/performance_YYYYMM.csv`
- 저장 경로(NAS): `/storage/system_monitor/data/{hostname}/performance_YYYYMM.csv`
  - 보고서 생성 시 자동 동기화
- 형식: `timestamp,cpu_usage,memory_usage,disk_usage,load_avg`

## 설치 방법

### 1. 스크립트 배포 (전체 서버)

```bash
sudo cp system_monitor.sh /usr/local/bin/system_monitor.sh
sudo chmod +x /usr/local/bin/system_monitor.sh
sudo mkdir -p /etc/system_monitor
sudo cp config/system_monitor.conf /etc/system_monitor/
sudo cp config/thresholds.conf /etc/system_monitor/
```

### 2. 로그 파일 권한

```bash
sudo touch /var/log/system_monitor.log /var/log/system_monitor_alerts.log
sudo chown clobot:clobot /var/log/system_monitor.log /var/log/system_monitor_alerts.log
```

### 3. 성능 데이터 수집 cron (전체 서버)

```bash
(sudo crontab -l 2>/dev/null; \
 echo "*/5 * * * * /usr/local/bin/system_monitor.sh saveperf > /dev/null 2>&1") \
 | sudo crontab -
```

### 4. 보고서 타이머 등록 (전체 서버)

```bash
sudo cp systemd/system_monitor-weekly.service  /etc/systemd/system/
sudo cp systemd/system-monitor-weekly.timer    /etc/systemd/system/
sudo cp systemd/system_monitor-monthly.service /etc/systemd/system/
sudo cp systemd/system-monitor-monthly.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now system-monitor-weekly.timer
sudo systemctl enable --now system-monitor-monthly.timer
```

### 5. 이메일 스크립트 (monitor-01 전용)

```bash
# send_report_email.py 상단의 SMTP_PASS, EMAIL_TO, EMAIL_CC 입력
vi send_report_email.py

sudo cp send_report_email.py /usr/local/bin/
sudo chmod +x /usr/local/bin/send_report_email.py

sudo cp systemd/system-monitor-weekly-email.service  /etc/systemd/system/
sudo cp systemd/system-monitor-weekly-email.timer    /etc/systemd/system/
sudo cp systemd/system-monitor-monthly-email.service /etc/systemd/system/
sudo cp systemd/system-monitor-monthly-email.timer   /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now system-monitor-weekly-email.timer
sudo systemctl enable --now system-monitor-monthly-email.timer
```

## 스크립트 실행 모드

```bash
system_monitor.sh report weekly    # 주간 HTML 보고서 생성
system_monitor.sh report monthly   # 월간 HTML 보고서 생성
system_monitor.sh report daily     # 일간 HTML 보고서 생성
system_monitor.sh saveperf         # 성능 데이터 CSV 저장 (cron 전용)
system_monitor.sh full             # 전체 모니터링 + 임계값 초과 시 잔디 알림
system_monitor.sh cpu              # CPU만 모니터링
system_monitor.sh memory           # 메모리만 모니터링
system_monitor.sh disk             # 디스크만 모니터링
system_monitor.sh vms              # 가상머신 상태만
```

## 임계값 기준

| 항목 | 경고(⚠️) | 위험(🔴) |
|---|---|---|
| CPU | ≥ 70% | ≥ 80% |
| 메모리 | ≥ 75% | ≥ 85% |
| SWAP | ≥ 50% | ≥ 75% |
| 디스크 | ≥ 80% | ≥ 90% |
| 로드 애버리지 | ≥ 3.0 | ≥ 5.0 |

`config/thresholds.conf`에서 변경 가능.

## 보고서 자동 정리 정책

보고서 생성 시 `cleanup_old_reports()` 자동 실행:

| 종류 | 보존 기간 |
|---|---|
| 일간 | 30일 |
| 주간 | 12주 (84일) |
| 월간 | 1년 (365일) |

## 알림 채널

| 채널 | 조건 | 내용 |
|---|---|---|
| 잔디 `monitoring-alerts` | 보고서 생성 시 | 링크 포함 알림 |
| 이메일 | 주간 월요일 06:15 / 월간 1일 06:15 | 4서버 통합 1통 |
