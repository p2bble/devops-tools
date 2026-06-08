# network_backup

네트워크 장비 설정을 자동으로 백업하는 Python 스크립트.  
Cisco, FortiGate 등 멀티벤더 장비를 SSH/HTTPS API로 접속해 running-config를 날짜별 디렉터리에 저장.

## 지원 벤더

| 벤더 | 접속 방식 | device_type |
|------|----------|-------------|
| Cisco IOS (CBS350 등) | SSH (Netmiko) | `cisco_ios` |
| Cisco SB-Series (SG220) | HTTP REST → SSH fallback | `cisco_s300` |
| FortiGate | SSH → HTTPS API fallback | `fortinet` |
| HP/Aruba ProCurve | SSH (Netmiko) | `hp_procurve` |

## 실행

```bash
# 의존성 설치 (최초 1회)
pip install -r requirements.txt   # 또는 pip install netmiko requests

# 전체 장비 백업
python3 network-config-backup.py
```

백업 파일 저장 위치: `backups/YYYYMMDD/{hostname}_{ip}_{timestamp}.txt`

## 장비 설정 (devices-config.json)

장비 인벤토리 파일. 실제 IP/계정 정보가 포함되어 있으므로 **인수인계 후 패스워드 변경 필요**.

```json
{
  "devices": [
    {
      "hostname": "cisco-CBS350-24T-4X",
      "ip": "192.168.100.1",
      "vendor": "cisco",
      "device_type": "cisco_ios",
      "username": "clobot",
      "password": "...",
      "secret": ""
    },
    {
      "hostname": "fortinet-FG-80E",
      "ip": "172.16.1.1",
      "vendor": "fortinet",
      "device_type": "fortinet",
      "username": "clobot",
      "password": "...",
      "api_token": "선택사항"
    }
  ]
}
```

## 현재 등록 장비 (6대)

| 장비명 | IP | 벤더 |
|--------|-----|------|
| cisco-CBS350-24T-4X | 192.168.100.1 | Cisco IOS |
| fortinet-FG-80E | 172.16.1.1 | FortiGate |
| cisco-SG220-26-1 | 192.168.100.3 | Cisco SB |
| cisco-SG220-26-2 | 192.168.100.4 | Cisco SB |
| cisco-CBS220-24T-4G-1 | 192.168.100.9 | Cisco IOS |
| cisco-CBS220-24T-4G-2 | 192.168.100.10 | Cisco IOS |

## 장비 추가 방법

`devices-config.json`에 항목 추가 후 스크립트 재실행:

```json
{
  "hostname": "new-switch",
  "ip": "192.168.100.x",
  "vendor": "cisco",
  "device_type": "cisco_ios",
  "username": "admin",
  "password": "password",
  "secret": "enable_secret"
}
```

## 스케줄 자동화

현재 수동 실행. cron으로 주 1회 자동화 권장:

```bash
# crontab -e
0 2 * * 1 cd /opt/network-backup && python3 network-config-backup.py >> /var/log/network_backup.log 2>&1
```

## 로그

실행 로그는 `network_backup.log`에 기록 (stdout 동시 출력).  
백업 성공/실패 장비 수, 오류 원인 포함.

## 인수인계 주의사항

- `devices-config.json`의 모든 패스워드를 인수 후 즉시 변경할 것
- FortiGate API 토큰은 FortiGate 관리 UI → 시스템 → 관리자 → API 키에서 재발급
- Cisco enable secret(`secret` 필드)이 비어 있으면 SSH 접속만 시도
