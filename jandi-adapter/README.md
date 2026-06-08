# Jandi Alertmanager Adapter

Prometheus Alertmanager의 webhook 알람을 Jandi(잔디) 메시지 포맷으로 변환하는 Python 프록시.

## 배경

Alertmanager의 기본 webhook은 Jandi 포맷과 맞지 않아 별도 어댑터가 필요.  
DingTalk 어댑터 대비 Jandi 포맷에 최적화되어 있음.

## 설정

```bash
# 환경변수
JANDI_WEBHOOK_URL=https://wh.jandi.com/connect-api/webhook/xxxxx/yyy
LISTEN_PORT=5001        # 기본값
```

## 배포 (Docker)

```yaml
# docker-compose.yml
services:
  jandi-adapter:
    image: python:3.11-slim
    container_name: jandi-adapter
    working_dir: /app
    volumes:
      - ./jandi-adapter:/app
    command: python jandi_proxy.py
    environment:
      - JANDI_WEBHOOK_URL=${JANDI_WEBHOOK_URL}
    ports:
      - "5001:5001"
    restart: unless-stopped
```

## Alertmanager 연동

```yaml
# alertmanager.yml
receivers:
  - name: jandi
    webhook_configs:
      - url: 'http://localhost:5001/alert'
        send_resolved: true
```

## 알람 포맷

| 심각도 | 색상 | 반복 주기 |
|--------|------|---------|
| critical | 🔴 빨강 | 4시간 |
| warning | 🟡 노랑 | 6시간 |
| info | 🔵 파랑 | 24시간 |
