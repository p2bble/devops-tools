===================================================
  자산 전수조사 수집 도구  v1.1
  (Windows / Ubuntu 공용)
===================================================

[ 디렉터리 구조 ]
  asset_collector/
  ├── Windows/
  │   ├── run_as_admin.bat   ← Windows 실행 진입점 (더블클릭)
  │   ├── launcher.ps1       ← 관리자 권한 상승 처리
  │   └── collect.ps1        ← 실제 수집 스크립트
  ├── Linux/
  │   └── collect.sh         ← Ubuntu 수집 스크립트
  ├── merge/
  │   ├── merge_results.bat  ← CSV 병합 실행 (더블클릭)
  │   ├── merge_results.ps1  ← Windows 병합 스크립트
  │   └── merge_results.sh   ← Linux 병합 스크립트
  ├── results/               ← 수집 결과 자동 저장
  ├── config.txt             ← 네트워크 공유 경로 설정 (선택)
  └── README.txt

---------------------------------------------------
[ Windows PC / 노트북 실행 방법 ]
---------------------------------------------------
1. 압축 해제 후 Windows 폴더 진입
   (USB 사용 시 USB를 꽂은 후 진입)
2. run_as_admin.bat 더블클릭
3. UAC 팝업에서 "예" 클릭 (관리자 권한 필요)
4. 완료 후 results/ 폴더에 CSV 파일 생성됨

※ nvidia-smi가 설치된 PC는 GPU S/N, UUID 자동 수집
※ 미설치 PC는 GPU 이름만 수집 (모든 GPU 이름은 수집됨)
※ NVIDIA Optimus 노트북은 내장(VGA) + 외장(3D controller)
   두 GPU 모두 감지됨 - 정상 동작

---------------------------------------------------
[ Ubuntu PC / 노트북 / 워크스테이션 실행 방법 ]
---------------------------------------------------
1. 압축 해제 후 터미널에서 Linux 폴더로 이동
     cd /media/$USER/<USB_이름>/Linux
     또는
     cd ~/Downloads/asset_collector/Linux
2. 실행:
     sudo bash collect.sh
3. 완료 후 results/ 폴더에 CSV + RAW txt 파일 생성됨

※ nvidia-smi 없어도 lspci로 GPU 이름 자동 감지
※ Jetson 보드: S/N 자동 감지 시 CSV에 Jetson_SN 컬럼 추가

---------------------------------------------------
[ 수집 항목 ]
---------------------------------------------------
  - OS 버전
  - 메인보드: 제조사 / 모델명 / 시리얼
  - CPU 모델명
  - GPU: 제품명 / 시리얼 / UUID
      nvidia-smi 설치 시 → S/N, UUID 수집
      미설치 시          → lspci로 이름만 수집 (S/N=N/A)
  - SSD/HDD: 모델 / 시리얼 / 용량 / 타입(SSD·HDD) 구분
  - RAM: 총량 / 슬롯별 제조사·용량·Part No·시리얼

---------------------------------------------------
[ 결과 파일 ]
---------------------------------------------------
  results/<호스트명>_<날짜시간>.csv
    → Google Sheets / Excel에 직접 붙여넣기 가능

  results/<호스트명>_<날짜시간>_raw.txt
    → 상세 원본 로그 (확인/검증용)

---------------------------------------------------
[ CSV 취합 및 병합 방법 ]
---------------------------------------------------
각 PC에서 수집한 CSV를 한 폴더에 모은 후 병합합니다.

  [ 방법 1 - Windows에서 병합 ]
  1. 수집된 CSV 파일을 모두 results/ 폴더에 복사
  2. merge/merge_results.bat 더블클릭
  3. results/MASTER_날짜시간.csv 생성됨

  [ 방법 2 - 폴더 경로 직접 지정 ]
  powershell -ExecutionPolicy Bypass -File merge\merge_results.ps1 "D:\수집결과폴더"

  [ 방법 3 - Linux/Mac 에서 병합 ]
  bash merge/merge_results.sh /path/to/csv폴더

  병합 결과: 모든 PC의 데이터가 한 파일로 합쳐지며
             Source_File 컬럼에 원본 파일명이 기록됨

---------------------------------------------------
[ 네트워크 공유 경로 설정 (선택사항) ]
---------------------------------------------------
config.txt 에서 RESULTS_PATH를 설정하면 수집 결과가
로컬 대신 지정한 공유 경로에 직접 저장됩니다.

  Windows 예시 (SMB 공유):
    RESULTS_PATH=\\172.19.100.10\asset_results

  Linux 예시 (NFS/Samba 마운트):
    RESULTS_PATH=/mnt/nas/asset_results

  → 설정 시 담당자가 파일을 별도 전송할 필요 없이
    실행만 하면 중앙 폴더에 자동 저장됨

---------------------------------------------------
[ 주의사항 ]
---------------------------------------------------
  - Windows: 관리자 권한 없으면 일부 S/N 미수집
  - Linux: sudo 없으면 dmidecode 실패 (메인보드/RAM S/N)
  - S/N이 "Default string": BIOS 미설정 → 실물 스티커 확인
  - S/N이 "00000000": 노트북 온보드 RAM은 미등록이 정상
  - GPU S/N이 "[N/A]": 노트북 GPU는 nvidia-smi로 S/N 조회 불가
  - Jetson 보드는 Ubuntu 스크립트로 동일하게 사용 가능

---------------------------------------------------
[ 버전 이력 ]
---------------------------------------------------
  v1.0  2026-04-29  최초 작성 (Windows + Ubuntu 수집)
  v1.1  2026-04-29  병합 스크립트 추가 / 네트워크 공유 경로
                    설정 지원 / GPU lspci 폴백 추가 /
                    RAM 슬롯별 상세 수집 수정
