sudo tee /opt/ssl-monitor/ssl_cert_monitor.sh > /dev/null << 'EOF'
#!/bin/bash
# ssl_cert_monitor.sh - SSL 인증서 만료 모니터링 스크립트

# 설정 변수들
JANDI_WEBHOOK_URL="Jandi 웹훅 URL을 여기에 입력하세요"

# 모니터링 대상 도메인들
DOMAINS=(
    "domain.co.kr:443"
    "domain.co.kr:443"
    "source.domain.co.kr:9000"
)

# 로컬 인증서 파일들
CERT_FILES=(
    "/storage/common/ssl/domain.co.kr/domain_2025.pem"
    "/storage/common/ssl/domain.co.kr/domain.co.kr.crt"
)

# 설정값들
LOG_FILE="/var/log/ssl_monitor.log"
WARNING_DAYS=30
CRITICAL_DAYS=7
CURRENT_DATE=$(date +%s)

# 잔디 메시지 전송 함수
send_jandi_message() {
    local title="$1"
    local message="$2"
    local color="$3"

    curl -X POST \
        -H "Accept: application/vnd.tosslab.jandi-v2+json" \
        -H "Content-Type: application/json" \
        -d "{
            \"body\": \"$title\",
            \"connectColor\": \"$color\",
            \"connectInfo\": [{
                \"title\": \"SSL 인증서 모니터링\",
                \"description\": \"$message\"
            }]
        }" \
        "$JANDI_WEBHOOK_URL"
}

# 도메인 SSL 인증서 확인 함수
check_domain_cert() {
    local domain="$1"
    local host=$(echo $domain | cut -d: -f1)
    local port=$(echo $domain | cut -d: -f2)

    echo "$(date): Checking domain $domain..." >> $LOG_FILE

    # OpenSSL로 인증서 정보 추출
    local cert_info=$(echo | timeout 10 openssl s_client -servername $host -connect $domain 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$cert_info" ]; then
        local end_date=$(echo "$cert_info" | grep 'notAfter' | cut -d= -f2)
        local end_timestamp=$(date -d "$end_date" +%s 2>/dev/null)

        if [ $? -eq 0 ]; then
            local days_until_expiry=$(( (end_timestamp - CURRENT_DATE) / 86400 ))

            if [ $days_until_expiry -le $CRITICAL_DAYS ]; then
                send_jandi_message "🚨 SSL 인증서 긴급 경고" \
                    "도메인: $domain\\n만료일: $end_date\\n남은 일수: ${days_until_expiry}일\\n\\n즉시 갱신이 필요합니다!" \
                    "#FF0000"
            elif [ $days_until_expiry -le $WARNING_DAYS ]; then
                send_jandi_message "⚠️ SSL 인증서 만료 경고" \
                    "도메인: $domain\\n만료일: $end_date\\n남은 일수: ${days_until_expiry}일\\n\\n갱신 준비가 필요합니다." \
                    "#FFA500"
            else
                echo "$(date): $domain certificate is valid for $days_until_expiry days." >> $LOG_FILE
            fi
        else
            echo "$(date): Could not parse end date for $domain." >> $LOG_FILE
            send_jandi_message "❌ SSL 인증서 오류" "도메인: $domain\\n오류: 만료일($end_date)을 파싱할 수 없습니다." "#FF0000"
        fi
    else
        echo "$(date): Failed to get certificate for $domain." >> $LOG_FILE
        send_jandi_message "❌ SSL 인증서 오류" "도메인: $domain\\n오류: 인증서 정보를 가져오지 못했습니다. 서버 또는 포트를 확인해주세요." "#FF0000"
    fi
}

# 파일 SSL 인증서 확인 함수
check_file_cert() {
    local cert_file="$1"

    echo "$(date): Checking file $cert_file..." >> $LOG_FILE

    if [ -f "$cert_file" ]; then
        local cert_info=$(openssl x509 -in "$cert_file" -noout -dates 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$cert_info" ]; then
            local end_date=$(echo "$cert_info" | grep 'notAfter' | cut -d= -f2)
            local end_timestamp=$(date -d "$end_date" +%s 2>/dev/null)

            if [ $? -eq 0 ]; then
                local days_until_expiry=$(( (end_timestamp - CURRENT_DATE) / 86400 ))

                if [ $days_until_expiry -le $CRITICAL_DAYS ]; then
                    send_jandi_message "🚨 SSL 인증서 긴급 경고" \
                        "인증서 파일: $cert_file\\n만료일: $end_date\\n남은 일수: ${days_until_expiry}일\\n\\n즉시 갱신이 필요합니다!" \
                        "#FF0000"
                elif [ $days_until_expiry -le $WARNING_DAYS ]; then
                    send_jandi_message "⚠️ SSL 인증서 만료 경고" \
                        "인증서 파일: $cert_file\\n만료일: $end_date\\n남은 일수: ${days_until_expiry}일\\n\\n갱신 준비가 필요합니다." \
                        "#FFA500"
                else
                    echo "$(date): $cert_file certificate is valid for $days_until_expiry days." >> $LOG_FILE
                fi
            else
                echo "$(date): Could not parse end date for $cert_file." >> $LOG_FILE
                send_jandi_message "❌ SSL 인증서 오류" "인증서 파일: $cert_file\\n오류: 만료일($end_date)을 파싱할 수 없습니다." "#FF0000"
            fi
        else
            echo "$(date): Failed to read certificate file $cert_file." >> $LOG_FILE
            send_jandi_message "❌ SSL 인증서 오류" "인증서 파일: $cert_file\\n오류: 인증서 파일을 읽을 수 없습니다." "#FF0000"
        fi
    else
        echo "$(date): Certificate file not found: $cert_file" >> $LOG_FILE
        send_jandi_message "❌ SSL 인증서 오류" "인증서 파일: $cert_file\\n오류: 파일을 찾을 수 없습니다." "#FF0000"
    fi
}

# 메인 실행 로직
echo "=========================================" >> $LOG_FILE
echo "$(date): SSL certificate monitoring started." >> $LOG_FILE

for domain in "${DOMAINS[@]}"; do
    check_domain_cert "$domain"
done

for cert_file in "${CERT_FILES[@]}"; do
    check_file_cert "$cert_file"
done

echo "$(date): SSL certificate monitoring finished." >> $LOG_FILE
echo "=========================================" >> $LOG_FILE
EOF
