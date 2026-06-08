#!/bin/bash
BASE_PATH="/storage/common/ssl"

usage() {
    echo "사용법: $0 <domain> <year> <source_dir>"
    echo "  <domain>: 'xxx' 또는 'xxx'"
    echo "  <year>: 인증서 연도 (예: 2025)"
    echo "  <source_dir>: 원본 인증서 파일이 업로드된 경로"
    exit 1
}

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    usage
fi

DOMAIN=$1
YEAR=$2
SOURCE_DIR=$3

# clobot.co.kr 처리
if [ "$DOMAIN" == "xxx" ]; then
    echo ">>> *.domain.co.kr 인증서 처리를 시작합니다."
    ARCHIVE_DIR="${BASE_PATH}/domain.co.kr/${YEAR}"
    DEST_DIR="${BASE_PATH}/domain.co.kr"

    echo "1. 아카이브 디렉토리(${ARCHIVE_DIR}) 생성 및 원본 파일 이동..."
    mkdir -p "$ARCHIVE_DIR"
    mv "${SOURCE_DIR}"/* "${ARCHIVE_DIR}/"

    PEM_FILE=$(find "$ARCHIVE_DIR" -name "File_Wildcard.domain.co.kr*.pem" -o -name "File_Wildcard.domain.co.kr*.crt")
    KEY_FILE=$(find "$ARCHIVE_DIR" -name "KeyFile_Wildcard.domain.co.kr*.key")
    # --- 💡 [수정됨] 체인 인증서 파일도 찾도록 추가 ---
    CHAIN_FILE=$(find "$ARCHIVE_DIR" -name "*ChainBundle*")

    if [ -z "$PEM_FILE" ] || [ -z "$KEY_FILE" ] || [ -z "$CHAIN_FILE" ]; then
        echo "!!! 아카이빙된 domain 원본 파일(pem/key/chain)을 찾을 수 없습니다."
        mv "${ARCHIVE_DIR}"/* "${SOURCE_DIR}"/
        exit 1
    fi

    echo "2. 최종 인증서 파일(.crt, .key) 생성 및 권한 설정..."
    # --- 💡 [수정됨] .crt 파일 생성 시 체인 인증서를 함께 묶어줌 (Fullchain) ---
    (cat "$PEM_FILE"; echo; cat "$CHAIN_FILE") > "${DEST_DIR}/domain.co.kr.crt"
    cp "$KEY_FILE" "${DEST_DIR}/domain.co.kr.key"
    chown clobot:clobot "${DEST_DIR}/domain.co.kr.crt" "${DEST_DIR}/domain.co.kr.key"
    chmod 644 "${DEST_DIR}/domain.co.kr.crt" "${DEST_DIR}/domain.co.kr.key"
    
    echo "3. HAProxy용 통합 인증서(domain.pem) 생성..."
    cat "${DEST_DIR}/domain.co.kr.crt" "${DEST_DIR}/domain.co.kr.key" > "${DEST_DIR}/domain.pem"
    chown clobot:clobot "${DEST_DIR}/domain.pem"
    chmod 644 "${DEST_DIR}/domain.pem"

    echo ">>> domain.co.kr 작업 완료!"

# domain.co.kr 처리 (기존과 동일하게 이미 Fullchain을 만들고 있었음)
elif [ "$DOMAIN" == "xxx" ]; then
    OUTPUT_FILE="domain_${YEAR}.pem"
    ARCHIVE_DIR="${BASE_PATH}/domain.co.kr/${YEAR}"
    DEST_DIR="${BASE_PATH}/domain.co.kr"

    echo ">>> *.domain.co.kr 인증서 처리를 시작합니다."
    echo "1. 아카이브 디렉토리(${ARCHIVE_DIR}) 생성 및 원본 파일 이동..."
    mkdir -p "$ARCHIVE_DIR"
    mv "${SOURCE_DIR}"/*domain.co.kr* "${SOURCE_DIR}"/*ChainBundle* "${SOURCE_DIR}"/*GLOBALSIGN* "${ARCHIVE_DIR}/"

    KEY_FILE=$(find "$ARCHIVE_DIR" -name "KeyFile_Wildcard.domain.co.kr*.key")
    PEM_FILE=$(find "$ARCHIVE_DIR" -name "File_Wildcard.domain.co.kr*.pem" -o -name "File_Wildcard.domain.co.kr*.crt")
    CHAIN_FILE=$(find "$ARCHIVE_DIR" -name "*ChainBundle*")
    ROOT_CA_FILE=$(find "$ARCHIVE_DIR" -name "*GLOBALSIGN*")

    if ! { [ -f "$KEY_FILE" ] && [ -f "$PEM_FILE" ] && [ -f "$CHAIN_FILE" ] && [ -f "$ROOT_CA_FILE" ]; }; then
        echo "!!! 아카이빙된 croms 필수 파일 4개를 찾을 수 없습니다."
        mv "${ARCHIVE_DIR}"/* "${SOURCE_DIR}"/
        exit 1
    fi

    echo "2. 인증서 병합 및 권한 설정..."
    cat "$KEY_FILE" "$PEM_FILE" "$CHAIN_FILE" "$ROOT_CA_FILE" > "${DEST_DIR}/${OUTPUT_FILE}"
    chown clobot:clobot "${DEST_DIR}/${OUTPUT_FILE}"
    chmod 644 "${DEST_DIR}/${OUTPUT_FILE}"
    echo ">>> doamin.co.kr 작업 완료! 이제 docker-compose.yml을 수정하세요."

else
    usage
fi
