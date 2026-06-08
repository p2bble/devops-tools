#!/usr/bin/env bash
# 사용법: bash merge_results.sh [CSV폴더경로]
# 예시:  bash merge_results.sh /mnt/nas/asset_results

INPUT_DIR="${1:-$(dirname "$0")/../results}"
INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT="$INPUT_DIR/MASTER_${TIMESTAMP}.csv"

echo "======================================"
echo " 자산 CSV 병합 + 무결성 검증 도구"
echo " 입력 폴더: $INPUT_DIR"
echo "======================================"

mapfile -t CSV_FILES < <(find "$INPUT_DIR" -maxdepth 1 -name "*.csv" ! -name "MASTER_*" | sort)

if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
    echo "CSV 파일이 없습니다: $INPUT_DIR"
    exit 1
fi

HEADER_WRITTEN=0
TOTAL_ROWS=0
OK_COUNT=0
TAMP_COUNT=0
NO_HASH_COUNT=0

for f in "${CSV_FILES[@]}"; do
    fname=$(basename "$f")
    hash_file="${f%.csv}.sha256"

    # ── SHA256 무결성 검증 ──────────────────────────────────────────────────
    if [[ -f "$hash_file" ]]; then
        expected_hash=$(awk '{print $1}' "$hash_file")
        actual_hash=$(sha256sum "$f" | awk '{print $1}')
        if [[ "$expected_hash" == "$actual_hash" ]]; then
            integrity="OK"
            OK_COUNT=$((OK_COUNT+1))
            printf "  \e[32m[OK]     \e[0m %s\n" "$fname"
        else
            integrity="TAMPERED"
            TAMP_COUNT=$((TAMP_COUNT+1))
            printf "  \e[31m[!!변조!!]\e[0m %s\n" "$fname"
        fi
    else
        integrity="UNVERIFIED"
        NO_HASH_COUNT=$((NO_HASH_COUNT+1))
        printf "  \e[33m[미검증] \e[0m %s\n" "$fname"
    fi

    row_count=$(( $(wc -l < "$f") - 1 ))

    if [[ $HEADER_WRITTEN -eq 0 ]]; then
        head -1 "$f" | sed 's/$/,Source_File,Integrity/' > "$OUTPUT"
        HEADER_WRITTEN=1
    fi

    tail -n +2 "$f" | awk -v src="$fname" -v intg="$integrity" \
        '{print $0 ",\"" src "\",\"" intg "\""}' >> "$OUTPUT"

    TOTAL_ROWS=$((TOTAL_ROWS + row_count))
done

echo ""
echo "======================================"
echo " 검증 결과 요약"
echo "======================================"
echo "  총 PC 수    : ${#CSV_FILES[@]}대"
echo "  총 데이터   : ${TOTAL_ROWS}행"
printf "  \e[32m[OK]  정상  : %d개\e[0m\n" "$OK_COUNT"
if [[ $TAMP_COUNT -gt 0 ]]; then
    printf "  \e[31m[!!] 변조의심: %d개  ← Integrity=TAMPERED 확인\e[0m\n" "$TAMP_COUNT"
fi
if [[ $NO_HASH_COUNT -gt 0 ]]; then
    printf "  \e[33m[??] 미검증 : %d개  ← .sha256 파일 없이 제출됨\e[0m\n" "$NO_HASH_COUNT"
fi
echo ""
echo "출력 파일: $OUTPUT"
