# GitOps CI/CD Pipeline Template

서버 설정 파일을 Git으로 관리하고 MR 머지 시 자동 배포하는 GitLab CI/CD 파이프라인 템플릿.

## 구조

```
infra-repo/
├── server-a/
│   ├── docker-compose.yml
│   ├── haproxy/haproxy.cfg
│   ├── prometheus/prometheus.yml
│   ├── prometheus/rules/alert.rules.yml
│   └── alertmanager/alertmanager.yml
├── server-b/
│   ├── docker-compose.yml
│   └── coredns/Corefile
└── .gitlab-ci.yml   ← gitlab-ci.yml.template 복사 후 수정
```

## 설정

### 1. CI/CD 변수 등록

GitLab → Settings → CI/CD → Variables

| 변수명 | 설명 | 타입 |
|--------|------|------|
| `INFRA_SSH_KEY` | 배포 서버 SSH 개인키 전체 내용 | Variable |

### 2. Runner 등록

```bash
docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url 'https://your-gitlab.com' \
  --token 'glrt-xxxxxxxxxxxx' \
  --executor 'docker' \
  --docker-image 'alpine:3.18' \
  --docker-volumes '/var/run/docker.sock:/var/run/docker.sock' \
  --description 'infra-runner'
```

## 파이프라인 동작

| 변경 파일 | 배포 방식 |
|----------|---------|
| `*/haproxy/**` | **수동 승인** → scp + restart |
| `*/prometheus/**` | 자동 → hot-reload (재시작 없음) |
| `*/alertmanager/**` | 자동 → hot-reload |
| `*/coredns/**` | 자동 → scp + docker restart |
| `*/docker-compose.yml` | **수동 승인** → docker compose up -d |
