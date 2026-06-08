#!/bin/bash
# setup_ssl_monitor.sh - SSL 모니터링 시스템 설치 스크립트

echo "SSL 인증서 모니터링 시스템 설치를 시작합니다..."

# 1. 디렉토리 생성
echo "디렉토리 생성 중..."
sudo mkdir -p /opt/ssl-monitor
sudo mkdir -p /var/log

# 2. 스크립트 복사 및 권한 설정
echo "스크립트 설치 중..."
sudo cp ssl_cert_monitor.sh /opt/ssl-monitor/
sudo chmod +x /opt/ssl-monitor/ssl_cert_monitor.sh

# 3. 로그 파일 생성
echo "로그 파일 설정 중..."
sudo touch /var/log/ssl_monitor.log
sudo chmod 644 /var/log/ssl_monitor.log

# 4. 로그 로테이션 설정
echo "로그 로테이션 설정 중..."
sudo tee /etc/logrotate.d/ssl-monitor > /dev/null << 'EOF'
/var/log/ssl_monitor.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

# 5. cron 작업 설정 (사용자 확인 후)
echo "Cron 작업을 설정하시겠습니까? (y/n)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Cron 작업 설정 중..."
    # 기존 SSL 모니터링 cron 제거
    (crontab -l 2>/dev/null | grep -v "ssl_cert_monitor.sh") | crontab -
    
    # 새로운 cron 추가 (매일 오전 9시)
    (crontab -l 2>/dev/null; echo "0 6 * * * /opt/ssl-monitor/ssl_cert_monitor.sh") | crontab -
    
    echo "매일 오전 6시에 SSL 인증서 모니터링이 실행됩니다."
fi

# 6. 잔디 웹훅 설정 안내
echo ""
echo "=== 잔디 웹훅 설정 안내 ==="
echo "1. 잔디 관리자 페이지에 접속하세요"
echo "2. '통합' > '인커밍 웹훅'을 선택하세요"
echo "3. 새 웹훅을 생성하고 URL을 복사하세요"
echo "4. 다음 명령으로 웹훅 URL을 설정하세요:"
echo "   sudo sed -i 'YOUR_JANDI_WEBHOOK_URL' /opt/ssl-monitor/ssl_cert_monitor.sh"
echo ""

# 7. 테스트 실행 제안
echo "=== 테스트 실행 ==="
echo "설치가 완료되었습니다. 테스트를 실행하시겠습니까? (y/n)"
read -r test_response
if [[ "$test_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "테스트 실행 중..."
    sudo /opt/ssl-monitor/ssl_cert_monitor.sh
    echo ""
    echo "테스트 완료. 로그를 확인해보세요:"
    echo "tail -20 /var/log/ssl_monitor.log"
fi

echo ""
echo "SSL 인증서 모니터링 시스템 설치가 완료되었습니다!"
echo "주요 파일 위치:"
echo "- 모니터링 스크립트: /opt/ssl-monitor/ssl_cert_monitor.sh"
echo "- 로그 파일: /var/log/ssl_monitor.log"
echo "- 로그 로테이션 설정: /etc/logrotate.d/ssl-monitor"
