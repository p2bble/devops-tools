#!/bin/bash

# ===================================================================
# --- 설정 ---
# ===================================================================
# 최신 와일드카드 인증서와 키 파일 (이 파일들의 내용으로 덮어쓸 예정)
SOURCE_CERT_FILE="domain.co.kr.crt"
SOURCE_KEY_FILE="domain.co.kr.key"

# 교체할 대상 파일 목록 (이 아래 목록에 있는 파일들이 교체됩니다)
TARGET_FILES=(
    "pd-registry.domain.co.kr.crt"
    "pd-registry.domain.co.kr.key"
    "pd-source.domain.co.kr.crt"
    "pd-source.domain.co.kr.key"
    "registry.domain.co.kr.crt"
    "registry.domain.co.kr.key"
    "source.domain.co.kr.crt"
    "source.domain.co.kr.key"
)

# 적용할 소유자와 그룹
OWNER="admin"
GROUP="admin"

# 오늘 날짜 (백업 파일명에 사용)
TODAY=$(date +%Y%m%d)
# ===================================================================

echo "🚀 오래된 SSL 인증서 파일 정리를 시작합니다..."
echo "----------------------------------------"

# (이전 파일 정리 로직은 동일)
# ...
for file in "${TARGET_FILES[@]}"; do
    echo "-> 작업 대상: $file"
    if [ -f "$file" ]; then
        mv -f "$file" "${file}.old.${TODAY}"
        echo "   - 백업 완료: ${file}.old.${TODAY}"
    else
        echo "   - 파일이 존재하지 않아 백업을 건너뜁니다."
    fi

    if [[ "$file" == *.crt ]]; then
        cp "$SOURCE_CERT_FILE" "$file"
        echo "   - '$SOURCE_CERT_FILE' -> '$file' 복사 완료"
        chmod 664 "$file"
        echo "   - 권한을 664로 설정했습니다."
    elif [[ "$file" == *.key ]]; then
        cp "$SOURCE_KEY_FILE" "$file"
        echo "   - '$SOURCE_KEY_FILE' -> '$file' 복사 완료"
        chmod 644 "$file"
        echo "   - 권한을 644로 설정했습니다."
    fi

    chown "${OWNER}:${GROUP}" "$file"
    echo "   - 소유자를 ${OWNER}:${GROUP}으로 변경했습니다."
    echo ""
done
echo "✅ 모든 대상 파일 정리가 완료되었습니다!"
echo ""

# ===================================================================
# --- GitLab 재설정 및 재시작 (추가된 부분) ---
# ===================================================================
echo "⚙️ GitLab 서비스에 변경사항을 적용합니다..."
echo "----------------------------------------"
echo "1/2 단계: GitLab 설정을 재구성합니다 (reconfigure)..."
docker exec -it gitlab gitlab-ctl reconfigure

echo ""
echo "2/2 단계: GitLab 컨테이너를 재시작합니다..."
docker restart gitlab

echo ""
echo "🎉 모든 작업이 완료되었습니다. GitLab에 새 인증서가 적용되었습니다."
