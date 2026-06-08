#!/bin/bash
# test_jandi_webhook.sh - 잔디 웹훅 테스트 스크립트

# 잔디 웹훅 URL (실제 값으로 채워져 있어야 합니다)
JANDI_WEBHOOK_URL="Jandi 웹훅 URL을 여기에 입력하세요"

echo "잔디 웹훅 테스트를 시작합니다..."

# 테스트 메시지 전송 함수
send_test_message() {
    local test_type="$1"
    local color="$2"
    
    case $test_type in
        "success")
            title="✅ SSL 모니터링 시스템 테스트 성공"
            message="SSL 인증서 모니터링 시스템이 정상적으로 설정되었습니다.\\n\\n• 모니터링 스크립트: 정상 작동\\n• 잔디 웹훅: 연결 성공\\n• 로그 시스템: 정상 작동"
            ;;
        "warning")
            title="⚠️ SSL 인증서 경고 테스트"
            message="테스트 도메인: test.example.com\\n만료일: 2025-10-15\\n남은 일수: 25일\\n\\n갱신 준비가 필요합니다."
            ;;
        "critical")
            title="🚨 SSL 인증서 긴급 경고 테스트"
            message="테스트 도메인: critical.example.com\\n만료일: 2025-09-15\\n남은 일수: 3일\\n\\n즉시 갱신이 필요합니다!"
            ;;
        "error")
            title="❌ SSL 인증서 연결 오류 테스트"
            message="테스트 도메인: error.example.com\\n오류: 연결 실패 또는 인증서 정보 추출 실패"
            ;;
    esac
    
    # Jandi Webhook으로 curl POST 요청
    curl -X POST \
        -H "Accept: application/vnd.tosslab.jandi-v2+json" \
        -H "Content-Type: application/json" \
        -d "{
            \"body\": \"$title\",
            \"connectColor\": \"$color\",
            \"connectInfo\": [{
                \"title\": \"SSL 인증서 모니터링 테스트\",
                \"description\": \"$message\"
            }]
        }" \
        "$JANDI_WEBHOOK_URL"
    
    echo "" # curl 출력과 구분을 위한 줄바꿈
    if [ $? -eq 0 ]; then
        echo "✅ $test_type 테스트 메시지 전송 성공"
    else
        echo "❌ $test_type 테스트 메시지 전송 실패"
    fi
}

# 웹훅 URL이 기본값인지 확인
if [[ "$JANDI_WEBHOOK_URL" == *"YOUR_WEBHOOK_TOKEN"* ]]; then
    echo "❌ 에러: 웹훅 URL이 설정되지 않았습니다."
    echo "스크립트에서 YOUR_WEBHOOK_TOKEN을 실제 토큰으로 변경해주세요."
    exit 1
fi

echo "다양한 알림 유형을 테스트합니다..."
echo ""

# 1. 성공 메시지 테스트
echo "1. 성공 메시지 테스트 중..."
send_test_message "success" "#00FF00"
sleep 2

# 2. 경고 메시지 테스트
echo "2. 경고 메시지 테스트 중..."
send_test_message "warning" "#FFA500"
sleep 2

# 3. 긴급 경고 메시지 테스트
echo "3. 긴급 경고 메시지 테스트 중..."
send_test_message "critical" "#FF0000"
sleep 2

# 4. 오류 메시지 테스트
echo "4. 오류 메시지 테스트 중..."
send_test_message "error" "#808080"
sleep 2

echo ""
echo "모든 테스트가 완료되었습니다."
