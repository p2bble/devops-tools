#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Multi-Vendor Network Configuration Backup Script

지원 벤더:
- Cisco IOS: SSH (Netmiko)
- Cisco SB-Series (S300): HTTP REST export ➔ SSH fallback
- FortiGate: SSH ➔ HTTPS API fallback
- HP/Aruba ProCurve: SSH (Netmiko)
"""

import os
import sys
import json
import logging
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

from netmiko import ConnectHandler, NetmikoTimeoutException, NetmikoAuthenticationException
import requests
from requests.auth import HTTPBasicAuth
import warnings

# SSL 경고 비활성화
warnings.filterwarnings('ignore', message='Unverified HTTPS request')

# 로그 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[
        logging.FileHandler('network_backup.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class NetworkDeviceBackup:
    def __init__(self, config_file='devices-config.json'):
        self.config_file = config_file
        self.backup_dir = self._create_backup_directory()
        self.devices = self._load_device_config().get('devices', [])

    def _create_backup_directory(self):
        """백업을 저장할 날짜별 디렉터리를 생성합니다."""
        path = os.path.join('backups', datetime.now().strftime('%Y%m%d'))
        os.makedirs(path, exist_ok=True)
        return path

    def _load_device_config(self):
        """장비 설정 파일을 로드합니다."""
        try:
            with open(self.config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"설정 파일 로드 실패: {e}")
            sys.exit(1)

    def _save_file(self, device, content, ext, binary=False):
        """백업된 설정을 파일로 저장합니다."""
        ip_safe = device['ip'].replace('.', '-')
        filename = f"{device['hostname']}_{ip_safe}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.{ext}"
        filepath = os.path.join(self.backup_dir, filename)
        mode = 'wb' if binary else 'w'
        try:
            with open(filepath, mode, encoding=None if binary else 'utf-8') as fd:
                fd.write(content)
            logger.info(f"백업 완료: {filename}")
        except Exception as e:
            logger.error(f"파일 저장 실패 ({filename}): {e}")


    def backup_cisco_ios(self, device):
        """Cisco IOS 장비의 설정을 백업합니다 (CBS 시리즈 포함)."""
        info = {
            'device_type': 'cisco_ios',
            'host': device['ip'],
            'username': device['username'],
            'password': device['password'],
            'secret': device.get('secret', ''),
            'timeout': 60,  # 타임아웃 시간 증가
            'fast_cli': False,
            'global_delay_factor': 2, # 프롬프트 감지 안정성 향상
        }
        try:
            with ConnectHandler(**info) as conn:
                conn.enable() # secret이 있을 경우를 대비해 명시적으로 호출
                conn.send_command('terminal length 0', expect_string=r'#')
                cfg = conn.send_command('show running-config', expect_string=r'#')
                self._save_file(device, cfg, 'txt')
            return True
        except (NetmikoTimeoutException, NetmikoAuthenticationException) as e:
            logger.error(f"Cisco IOS ({device['hostname']}) 실패: {e}")
            return False
        except Exception as e:
            logger.error(f"Cisco IOS ({device['hostname']}) 예상치 못한 오류: {e}")
            return False

    def backup_cisco_sb(self, device):
        """Cisco SB-Series의 설정을 HTTP를 통해 백업합니다."""
        url = f"http://{device['ip']}/rest/configuration?format=text"
        try:
            resp = requests.get(url,
                auth=HTTPBasicAuth(device['username'], device['password']),
                verify=False, timeout=30)
            resp.raise_for_status()
            self._save_file(device, resp.text, 'txt')
            return True
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                logger.warning(f"SB-Series HTTP 실패 ({device['hostname']}): URL Not Found. 이 모델은 HTTP 백업을 지원하지 않을 수 있습니다.")
            else:
                logger.error(f"SB-Series HTTP 실패 ({device['hostname']}): {e}")
            return False
        except Exception as e:
            logger.error(f"SB-Series HTTP 실패 ({device['hostname']}): {e}")
            return False

    def backup_cisco_s300_ssh(self, device):
        """Cisco SB-Series (S300)의 설정을 SSH를 통해 백업합니다."""
        info = {
            'device_type': 'cisco_s300',
            'host': device['ip'],
            'username': device['username'],
            'password': device['password'],
            'timeout': 60, # 타임아웃 시간 증가
            'fast_cli': False,
            'global_delay_factor': 2,
        }
        try:
            with ConnectHandler(**info) as conn:
                cfg = conn.send_command('show running-config')
                self._save_file(device, cfg, 'txt')
            return True
        except Exception as e:
            logger.error(f"SB-Series SSH ({device['hostname']}) 실패: {e}")
            return False

    def backup_cisco_sb_wrapper(self, device):
        """Cisco SB-Series 백업을 위한 래퍼 함수. HTTP 실패 시 SSH로 대체합니다."""
        logger.info(f"SB-Series ({device['hostname']}) HTTP 백업 시도...")
        if not self.backup_cisco_sb(device):
            logger.warning(f"SB-Series ({device['hostname']}) HTTP 백업이 실패하여 SSH 방식으로 대체합니다.")
            return self.backup_cisco_s300_ssh(device)
        return True

    def backup_fortigate(self, device):
        """FortiGate 장비의 설정을 백업합니다. SSH 실패 시 HTTPS API로 대체합니다."""
        info = {
            'device_type': 'fortinet',
            'host': device['ip'],
            'username': device['username'],
            'password': device['password'],
            'timeout': 90, # 긴 설정 파일에 대비해 타임아웃 증가
            'fast_cli': False,
            'global_delay_factor': 2, # 프롬프트 감지 안정성 향상
        }
        try:
            logger.info(f"FortiGate ({device['hostname']}) SSH 백업 시도...")
            with ConnectHandler(**info) as conn:
                cfg = conn.send_command('show full-configuration')
                self._save_file(device, cfg, 'conf')
            return True
        except Exception as ssh_err:
            logger.warning(f"FortiGate SSH 실패 ({device['hostname']}): {ssh_err}, HTTPS API로 대체합니다.")
            return self._backup_fortigate_http(device)

    def _backup_fortigate_http(self, device):
        """FortiGate 장비의 설정을 HTTPS API를 통해 백업합니다."""
        api_token = device.get('api_token')
        if not api_token or api_token == 'API_토큰_선택사항':
            logger.error(f"FortiGate HTTPS API 실패 ({device['hostname']}): 설정 파일에 유효한 API 토큰이 없습니다.")
            return False

        url = f"https://{device['ip']}/api/v2/monitor/system/config/backup"
        params = {'scope': 'global', 'access_token': api_token}
        try:
            logger.info(f"FortiGate ({device['hostname']}) HTTPS API 백업 시도...")
            resp = requests.get(
                url,
                params=params,
                verify=False,
                timeout=60 # 타임아웃 시간 증가
            )
            resp.raise_for_status()
            self._save_file(device, resp.content, 'conf', binary=True)
            return True
        except Exception as e:
            logger.error(f"FortiGate HTTPS API 실패 ({device['hostname']}): {e}")
            return False

    def backup_hp(self, device):
        """HP/Aruba 장비의 설정을 백업합니다."""
        info = {
            'device_type': device.get('device_type', 'hp_procurve'),
            'host': device['ip'],
            'username': device['username'],
            'password': device['password'],
            'timeout': 60 # 타임아웃 시간 증가
        }
        try:
            with ConnectHandler(**info) as conn:
                conn.send_command('terminal length 0', expect_string=r'#')
                cfg = conn.send_command('show running-config', expect_string=r'#')
                self._save_file(device, cfg, 'txt')
            return True
        except Exception as e:
            logger.error(f"HP/Aruba ({device['hostname']}) 실패: {e}")
            return False

    def run_backup(self):
        """모든 장비에 대한 백업을 병렬로 실행합니다."""
        total = len(self.devices)
        success = 0
        logger.info(f"총 {total}대 백업 시작...")
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = []
            for d in self.devices:
                vendor = d.get('vendor', '').lower()
                if vendor == 'cisco':
                    if d.get('device_type') == 'cisco_s300':
                        futures.append(executor.submit(self.backup_cisco_sb_wrapper, d))
                    else: # cisco_ios
                        futures.append(executor.submit(self.backup_cisco_ios, d))
                elif vendor in ('fortinet', 'fortigate'):
                    futures.append(executor.submit(self.backup_fortigate, d))
                elif vendor in ('hp', 'aruba'):
                    futures.append(executor.submit(self.backup_hp, d))
                else:
                    logger.warning(f"지원되지 않는 벤더 ({d.get('vendor', 'N/A')}) - 스킵: {d.get('hostname', 'N/A')}")

            for f in as_completed(futures):
                if f.result():
                    success += 1

        logger.info(f"백업 완료: 성공 {success}, 실패 {total - success}")

if __name__ == '__main__':
    NetworkDeviceBackup().run_backup()