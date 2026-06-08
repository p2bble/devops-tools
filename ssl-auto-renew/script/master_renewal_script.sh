#!/bin/bash

# --- 설정 변수 ---
YEAR="2026"
DOMAIN="domain"
SOURCE_DIR="/storage/common/ssl/temp_certs/"

# 서버 접속 정보
GITLAB_USER="admin"
GITLAB_HOST="192.168.xxx.xxx"
HAPROXY_USER="admin"
HAPROXY_HOST="192.168.xxx.xxx"
K8S_USER="admin"
K8S_HOST="192.168.xxx.xxx"


echo "======= [1/4] 로컬 인증서 파일 가공 시작 ======="
bash /storage/common/ssl/script/server_process_ssl.sh $DOMAIN $YEAR $SOURCE_DIR
if [ $? -ne 0 ]; then
    echo "!!! 파일 가공 실패. 스크립트를 중단합니다."
    exit 1
fi
echo "======= 로컬 작업 완료 ======="
echo ""


echo "======= [2/4] GitLab 서버 인증서 갱신 시작 ======="
ssh ${GITLAB_USER}@${GITLAB_HOST} << 'EOF'
    echo "GitLab 컨테이너를 재시작합니다..."
    cd /data/docker/gitlab-server-docker
    docker compose up -d --force-recreate gitlab
    echo "GitLab 작업 완료!"
EOF
echo "======= GitLab 작업 완료 ======="
echo ""


# 참고: croms 갱신 시 아래와 같은 로직을 추가할 수 있습니다.
# echo "======= [3/4] HAProxy 서버 인증서 갱신 시작 ======="
# ssh ${HAPROXY_USER}@${HAPROXY_HOST} "
#     echo 'HAProxy docker-compose.yml 파일을 수정합니다...'
#     sed -i 's/croms_$[YEAR-1].pem/domain_${YEAR}.pem/' /data/docker/docker-compose.yml
#
#     echo 'HAProxy 컨테이너를 재시작합니다...'
#     cd /data/docker/
#     docker-compose up -d --force-recreate haproxy
#     echo 'HAProxy 작업 완료!'
# "
# echo "======= HAProxy 작업 완료 ======="
# echo ""


echo "======= [4/4] 수동 작업 안내 ======="
echo "✅ 대부분의 자동화 작업이 완료되었습니다."
echo "⚠️ 아래 작업은 수동으로 진행해야 합니다:"
echo "  - Kubernetes(KIRO) Secret 갱신"
echo "  - FortiGate 방화벽 인증서 업데이트"
echo "  - 더존 ERP 갱신 요청"
