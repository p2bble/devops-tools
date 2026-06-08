#!/bin/bash
# SSL 인증서 만료일 확인 스크립트

DOMAINS=("domain.co.kr")
WARN_DAYS=30

for domain in "${DOMAINS[@]}"; do
    expiry_date=$(echo | openssl s_client -connect ${domain}:443 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
    expiry_timestamp=$(date -d "$expiry_date" +%s)
    current_timestamp=$(date +%s)
    days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    if [ $days_until_expiry -lt $WARN_DAYS ]; then
        echo "WARNING: $domain SSL certificate expires in $days_until_expiry days ($expiry_date)"
    else
        echo "OK: $domain SSL certificate expires in $days_until_expiry days ($expiry_date)"
    fi
done
