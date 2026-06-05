# 백업 스크립트

인프라 백업 자동화 스크립트 템플릿 모음.  
모든 스크립트는 **Prometheus textfile 연동**으로 백업 성공/실패를 모니터링 스택에 자동 기록합니다.

---

## 스크립트 목록

| 파일 | 용도 | 설치 대상 |
|------|------|---------|
| `backup-vm.sh.example` | KVM 가상 머신 병렬 백업 | KVM 호스트 |
| `backup-service.sh.example` | Docker 서비스 백업파일 → NAS rsync | 서비스 서버 |
| `backup-files.sh.example` | 서버 설정파일(/etc, docker 구성) → NAS rsync | 모든 서버 |
| `cron.example` | cron 스케줄 설정 예시 | — |

---

## 빠른 시작

```bash
# 1. 스크립트 복사 및 [CUSTOMIZE] 구간 편집
sudo cp backup-files.sh.example /usr/local/bin/backup-files.sh
sudo vi /usr/local/bin/backup-files.sh   # NAS 경로, 백업 대상 지정

# 2. 실행 권한 부여
sudo chmod +x /usr/local/bin/backup-files.sh

# 3. 수동 테스트
sudo /usr/local/bin/backup-files.sh

# 4. Prometheus 메트릭 확인
cat /var/lib/node_exporter/textfile/*.prom

# 5. cron 등록
sudo crontab -e   # cron.example 참고
```

---

## 공통 패턴

모든 스크립트가 공유하는 설계 원칙입니다.

### Prometheus textfile 연동

각 스크립트 실행 후 `/var/lib/node_exporter/textfile/` 에 `.prom` 파일을 생성합니다.

```
# 백업 성공 여부 (1=성공, 0=실패)
service_backup_success{service="gitlab"} 1

# 마지막 백업 완료 시각 (Unix timestamp)
service_backup_last_timestamp{service="gitlab"} 1717123456
```

`prometheus/rules/alert.rules.yml`의 알람 규칙이 자동으로 감지합니다.

| 알람 | 조건 | 의미 |
|------|------|------|
| `BackupFailed` | success = 0 | 백업 실패 즉시 알람 |
| `BackupStale` | timestamp 25시간 초과 | 백업 미실행 (스크립트 누락/cron 장애) |

### NAS 마운트

백업 목적지는 NAS NFS 마운트를 전제합니다.

```bash
# NAS NFS 마운트 (fstab 등록)
# /etc/fstab
192.168.1.100:/volume1/backup  /mnt/nas/backup  nfs  defaults,_netdev  0 0

# 마운트 확인
mountpoint -q /mnt/nas/backup && echo "OK" || echo "NOT MOUNTED"
```

### 안전 실행 (`set -uo pipefail`)

모든 스크립트는 `set -uo pipefail` 로 시작합니다.
- 미정의 변수 사용 시 즉시 종료
- 파이프 중간 실패도 감지
- 예상치 못한 데이터 손상 방지

---

## 커스터마이징 체크리스트

스크립트 상단의 `[CUSTOMIZE]` 구간만 수정하면 됩니다.

- [ ] `NAS_BASE` / `DST_DIR` — NAS 마운트 경로
- [ ] `SERVICE_NAME` — 서비스 식별자 (Prometheus 레이블)
- [ ] `SRC_DIR` — 서비스 백업 파일 생성 경로
- [ ] `VM_INCLUDE` / `VM_EXCLUDE` — 백업 대상 VM 목록
- [ ] `DOCKER_EXCLUDES` — 대용량 볼륨 제외 패턴
- [ ] cron 스케줄 — `cron.example` 참고
