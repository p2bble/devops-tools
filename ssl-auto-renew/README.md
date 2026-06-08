# 🔐 SSL 인증서 갱신 및 배포 최종 가이드 (2025 개정판)

이 문서는 `domain.co.kr` 도메인의 SSL 인증서 갱신부터 파일 가공, 각 서버 배포, 그리고 자동 모니터링 시스템 구축까지의 모든 과정을 상세히 기술한 최종 가이드입니다.

프로세스 대부분이 스크립트로 자동화되어 있어, 휴먼 에러를 최소화하고 일관된 작업을 보장하는 것을 목표로 합니다.

-----

## 📚 목차

1.  [**1부: 사전 준비 및 인증서 가공**](https://www.google.com/search?q=%231%EB%B6%80-%EC%82%AC%EC%A0%84-%EC%A4%80%EB%B9%84-%EB%B0%8F-%EC%9D%B8%EC%A6%9D%EC%84%9C-%EA%B0%80%EA%B3%B5)
      * [1.1. 인증서 구매 및 업로드](https://www.google.com/search?q=%2311-%EC%9D%B8%EC%A6%9D%EC%84%9C-%EA%B5%AC%EB%A7%A4-%EB%B0%8F-%EC%97%85%EB%A1%9C%EB%93%9C)
      * [1.2. 스크립트를 이용한 파일 자동 가공](https://www.google.com/search?q=%2312-%EC%8A%A4%ED%81%AC%EB%A6%BD%ED%8A%B8%EB%A5%BC-%EC%9D%B4%EC%9A%A9%ED%95%9C-%ED%8C%8C%EC%9D%BC-%EC%9E%90%EB%8F%99-%EA%B0%80%EA%B3%B5)
2.  [**2부: 🚀 서비스별 인증서 배포**](https://www.google.com/search?q=%232%EB%B6%80-%F0%9F%9A%80-%EC%84%9C%EB%B9%84%EC%8A%A4%EB%B3%84-%EC%9D%B8%EC%A6%9D%EC%84%9C-%EB%B0%B0%ED%8F%AC)
      * [2.1. GitLab 서버 - [권장] 통합 스크립트 배포](https://www.google.com/search?q=%2321-gitlab-%EC%84%9C%EB%B2%84---%EA%B6%8C%EC%9E%A5-%ED%86%B5%ED%95%A9-%EC%8A%A4%ED%81%AC%EB%A6%BD%ED%8A%B8-%EB%B0%B0%ED%8F%AC)
      * [2.2. GitLab 서버 - 수동 배포 및 트러블슈팅](https://www.google.com/search?q=%2322-gitlab-%EC%84%9C%EB%B2%84---%EC%88%98%EB%8F%99-%EB%B0%B0%ED%8F%AC-%EB%B0%8F-%ED%8A%B8%EB%9F%AC%EB%B8%94%EC%8A%88%ED%8C%85)
      * [2.3. 기타 서비스 (HAProxy, Kubernetes, FortiGate)](https://www.google.com/search?q=%2323-%EA%B8%B0%ED%83%80-%EC%84%9C%EB%B9%84%EC%8A%A4-haproxy-kubernetes-fortigate)
3.  [**3부: 🛠️ 인증서 만료 자동 모니터링**](https://www.google.com/search?q=%233%EB%B6%80-%F0%9F%9B%A0%EF%B8%8F-%EC%9D%B8%EC%A6%9D%EC%84%9C-%EB%A7%8C%EB%A3%8C-%EC%9E%90%EB%8F%99-%EB%AA%A8%EB%8B%88%ED%84%B0%EB%A7%81)
      * [3.1. 시스템 개요](https://www.google.com/search?q=%2331-%EC%8B%9C%EC%8A%A4%ED%85%9C-%EA%B0%9C%EC%9A%94)
      * [3.2. 설치 방법](https://www.google.com/search?q=%2332-%EC%84%A4%EC%B9%98-%EB%B0%A9%EB%B2%95)
      * [3.3. 핵심 스크립트 상세 (`ssl_cert_monitor.sh`)](https://www.google.com/search?q=%2333-%ED%95%B5%EC%8B%AC-%EC%8A%A4%ED%81%AC%EB%A6%BD%ED%8A%B8-%EC%83%81%EC%84%B8-ssl_cert_monitorsh)
      * [3.4. 정상 작동 확인](https://www.google.com/search?q=%2334-%EC%A0%95%EC%83%81-%EC%9E%91%EB%8F%99-%ED%99%95%EC%9D%B8)

-----

## 1부: 사전 준비 및 인증서 가공

### 1.1. 인증서 구매 및 업로드

1.  **인증서 구매**: 각 도메인(`domain.co.kr`) 담당자를 통해 SSL 인증서 갱신을 진행합니다.
2.  **파일 업로드**: 인증 기관에서 전달받은 아래 4종의 원본 파일을 NAS 서버의 임시 경로(`  /storage/common/ssl/temp_certs/ `)에 업로드합니다.
      * `KeyFile_...key`: 개인키
      * `File_...crt` 또는 `.pem`: 도메인 인증서
      * `ChainFile_...`: 체인 인증서
      * `CA_...`: 루트 인증서

### 1.2. 스크립트를 이용한 파일 자동 가공

업로드된 원본 파일들을 각 서버 환경에 맞는 최종 포맷(`.pem`, `.crt`, `.key`)으로 가공하고 연도별로 아카이빙하는 스크립트입니다.

  * **스크립트 위치**: `/storage/common/ssl/script/server_process_ssl.sh`

  * **주요 기능**: 원본 인증서 파일들을 조합하여 서버 배포용 최종 파일을 생성하고, Wildcard(`*`)를 사용하여 다양한 원본 파일명을 자동으로 인식합니다.

  * **실행 방법**: NAS 서버에서 아래 형식으로 실행합니다.

    ```bash
    # 사용법: bash [스크립트 경로] [도메인 이름] [만료 연도] [원본 파일 경로]

    # domain.co.kr 예시
    bash /storage/common/ssl/script/server_process_ssl.sh domain 2026 /storage/common/ssl/temp_certs/

    # domain2.co.kr 예시
    bash /storage/common/ssl/script/server_process_ssl.sh domain2 2026 /storage/common/ssl/temp_certs/
    ```

  * **결과 확인**: 실행 후 `...작업 완료!` 메시지를 확인하고, 각 도메인 폴더(예: `/storage/common/ssl/domain.co.kr/`)에 최종 인증서 파일들이 생성되었는지 확인합니다.

-----

## 2부: 🚀 서비스별 인증서 배포

가공된 인증서를 각 서비스에 배포하고 적용합니다.

### 2.1. GitLab 서버 - [권장] 통합 스크립트 배포

GitLab은 구조가 복잡하여 수동 작업 시 오류 발생 가능성이 높습니다. 따라서 아래의 **통합 스크립트 사용을 강력히 권장**합니다.

  * **스크립트 위치**: `/storage/common/ssl/script/cleanup_and_deploy_certs.sh`

  * **자동 처리 작업 목록**:

    1.  기존의 오래된 인증서 파일들을 `.old` 확장자로 **백업**
    2.  최신 와일드카드 인증서로 **교체 및 정리**
    3.  파일 소유자 및 권한 **자동 설정**
    4.  GitLab 설정 **재구성** (`gitlab-ctl reconfigure`) 자동 실행
    5.  GitLab 컨테이너 **재시작** (`docker restart`) 자동 실행

  * **실행 방법**: GitLab 서버에 접속하여 인증서 폴더로 이동 후, 스크립트를 실행합니다.

    ```bash
    # 1. domain 인증서가 저장된 폴더로 이동
    cd /storage/common/ssl/domain.co.kr

    # 2. 통합 스크립트 실행
    sudo bash ../script/cleanup_and_deploy_certs.sh
    ```

    위 명령어 하나로 GitLab 인증서 배포의 모든 과정이 자동으로 완료됩니다.

### 2.2. GitLab 서버 - 수동 배포 및 트러블슈팅

부득이하게 수동으로 배포하거나 문제가 발생했을 경우 아래 절차를 따릅니다.

1.  **[Step 1] 파일 교체**: NAS에서 가공된 최신 `domain.co.kr.crt`와 `domain.co.kr.key` 파일을 GitLab 서버의 Docker 볼륨 경로에 덮어씁니다.

2.  **[Step 2] 설정 재구성 (Reconfigure)**: **가장 중요한 단계입니다.** 이 명령어는 GitLab의 모든 내부 서비스(웹, 레지스트리 등)에 새로운 인증서 설정을 전파하는 역할을 합니다.

    > 💡 **"설계도(`gitlab.rb`)를 보고 시스템을 리모델링하는 과정"** 과 같습니다.

    ```bash
    docker exec -it gitlab gitlab-ctl reconfigure
    ```

3.  **[Step 3] 서비스 재시작 (Restart)**: 변경된 설정을 100% 확실하게 적용하기 위해 컨테이너 전체를 재시작합니다.

    > 💡 **"리모델링 후 건물의 메인 전원을 껐다 켜서 모든 시스템을 초기화하는 과정"** 과 같습니다.

    ```bash
    docker restart gitlab
    ```

> ⚠️ **[중요] CI/CD 인증서 오류 해결**
>
>   * **현상**: GitLab 웹 UI는 정상이나, CI/CD 파이프라인의 `docker login` 등에서 `tls: ... certificate has expired` 오류 발생.
>   * **원인**: **`reconfigure`** 또는 **`restart`** 과정이 누락되어, GitLab 컨테이너 레지스트리 서비스가 갱신 전의 만료된 인증서를 계속 사용하고 있기 때문입니다.
>   * **해결**: 위 **Step 2, 3번 명령어(`reconfigure`, `restart`)를 반드시 순서대로 실행**해야 합니다.

### 2.3. 기타 서비스 (HAProxy, Kubernetes, FortiGate)

  * **HAProxy (xxx)**

    1.  `/data/docker/docker-compose.yml` 파일에서 인증서 파일명을 새 버전(예: `domain_2026.pem`)으로 수정합니다.
    2.  `docker-compose up -d --force-recreate haproxy` 명령으로 재시작합니다.

  * **Kubernetes (xxx)**

    1.  `kubectl delete secret xxx-gateway-certs -n istio-system` 명령으로 기존 Secret을 삭제합니다.
    2.  `kubectl create secret tls ...` 명령으로 새 인증서 파일을 사용하여 Secret을 다시 생성합니다.
    3.  `kubectl delete pod -l app=xxx-mg -n xxx` 명령으로 관련 Pod를 재시작합니다.

  * **FortiGate 방화벽**

    1.  관리 페이지 `System > Certificates`에서 새 인증서(`File_...`)와 키(`KeyFile_...`)를 Import 합니다.
    2.  `System > Settings` 및 `VPN > SSL-VPN Settings`에서 서버 인증서를 새로 업로드한 것으로 교체합니다.
    3.  CLI에서 `fnsysctl killall sslvpnd` 명령으로 SSL VPN 서비스를 재시작합니다.

-----

## 3부: 🛠️ 인증서 만료 자동 모니터링

인증서 만료일을 주기적으로 감시하고 잔디(Jandi)로 경고를 보내는 시스템입니다.

### 3.1. 시스템 개요

  * 매일 오전 6시, 지정된 도메인과 로컬 인증서 파일의 만료일을 점검합니다.
  * 만료일이 30일/7일 이내로 남았을 경우 잔디로 경고 메시지를 전송합니다.

### 3.2. 설치 방법

모니터링이 필요한 서버에서 `setup_ssl_monitor.sh` 스크립트를 실행하여 시스템을 설치합니다.

  * **스크립트 위치**: `/storage/common/ssl/script/setup_ssl_monitor.sh`

  * **주요 기능**: 모니터링 스크립트 복사, 로그 설정, Cron 작업 등록 자동화.

  * **실행 방법**:

    ```bash
    # 스크립트가 있는 위치로 이동 후 실행
    cd /storage/common/ssl/script/
    bash ./setup_ssl_monitor.sh
    ```

### 3.3. 핵심 스크립트 상세 (`ssl_cert_monitor.sh`)

실제 모니터링 작업을 수행하는 스크립트입니다. 새로운 도메인이나 인증서 파일을 추가하려면 이 파일을 수정해야 합니다.

  * **파일 위치**: `/opt/ssl-monitor/ssl_cert_monitor.sh`

  * **주요 설정 (수정 대상)**:

      * `DOMAINS`: 외부에서 접근 가능한 도메인과 포트 목록
      * `CERT_FILES`: 서버 내부에 저장된 인증서 파일 경로 목록

    \<details\>
    \<summary\>\<b\>📜 ssl\_cert\_monitor.sh 전체 코드 보기\</b\>\</summary\>

    ```bash
    #!/bin/bash
    # ssl_cert_monitor.sh - SSL 인증서 만료 모니터링 스크립트

    # 설정 변수들
    JANDI_WEBHOOK_URL="https://wh.jandi.com/connect-api/webhook/..." # 실제 웹훅 URL로 교체

    # 모니터링 대상 도메인들
    DOMAINS=(
        "domain.co.kr:443"
        "source.domain.co.kr:9000"
        "registry.domain.co.kr:443"
    )

    # 로컬 인증서 파일들
    CERT_FILES=(
        "/storage/common/ssl/domain.co.kr/domain_2026.pem"
        "/storage/common/ssl/domain.co.kr/domain.co.kr.crt"
        "/storage/common/ssl/domain.co.kr/source.domain.co.kr.crt"
        "/storage/common/ssl/domain.co.kr/registry.domain.co.kr.crt"
    )

    # (이하 스크립트 로직은 생략)
    # ...
    ```

    \</details\>

### 3.4. 정상 작동 확인

스크립트가 올바르게 실행되면 로그 파일에 아래와 같이 기록이 남습니다.

  * **로그 확인 명령어**: `tail -f /var/log/ssl_monitor.log`

  * **정상 실행 로그 예시**:

    ```log
    =========================================
    Tue Sep 23 19:19:02 KST 2025: SSL certificate monitoring started.
    Tue Sep 23 19:19:02 KST 2025: Checking domain domain.co.kr:443...
    Tue Sep 23 19:19:02 KST 2025: domain.co.kr:443 certificate is valid for 102 days.
    Tue Sep 23 19:19:02 KST 2025: Checking domain source.domain.co.kr:9000...
    Tue Sep 23 19:19:02 KST 2025: source.domain.co.kr:9000 certificate is valid for 388 days.
    Tue Sep 23 19:19:02 KST 2025: Checking domain registry.domain.co.kr:443...
    Tue Sep 23 19:19:02 KST 2025: registry.domain.co.kr:443 certificate is valid for 388 days.
    Tue Sep 23 19:19:02 KST 2025: Checking file /storage/common/ssl/domain.co.kr/domain.co.kr.crt...
    Tue Sep 23 19:19:02 KST 2025: /storage/common/ssl/domain.co.kr/domain.co.kr.crt certificate is valid for 388 days.
    Tue Sep 23 19:19:02 KST 2025: SSL certificate monitoring finished.
    ```
