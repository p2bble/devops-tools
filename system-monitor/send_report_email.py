#!/usr/bin/env python3
"""
인프라 통합 보고서 이메일 발송 스크립트
사용법: python3 send_report_email.py [weekly|monthly]
"""

import sys, os, re, csv, smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from glob import glob
from datetime import datetime, timedelta

# ============================================================
# ★ 이메일 설정 (수정 가능)
# ============================================================
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT   = 587
SMTP_USER   = os.environ.get("SMTP_USER", "your-smtp@example.com")
SMTP_PASS   = os.environ.get("SMTP_PASS", "YOUR_GMAIL_APP_PASSWORD")

EMAIL_FROM  = os.environ.get("EMAIL_FROM", "your-smtp@example.com")
EMAIL_TO    = os.environ.get("EMAIL_TO", "admin@example.com").split(",")
EMAIL_CC    = os.environ.get("EMAIL_CC", "").split(",") if os.environ.get("EMAIL_CC") else []

# ★ 제목 템플릿
SUBJECT_WEEKLY  = "[인프라 주간보고] {date} | 서버 {count}대 현황"
SUBJECT_MONTHLY = "[인프라 월간보고] {date} | 서버 {count}대 현황"

# ★ 실시간 모니터링 링크
GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://your-grafana:3000/d/overview")

# NAS/보고서 저장 경로
NAS_REPORT_BASE = os.environ.get("REPORT_BASE", "/storage/system_monitor/reports")
NAS_DATA_BASE   = os.environ.get("DATA_BASE",   "/storage/system_monitor/data")
NAS_WEB_BASE    = os.environ.get("WEB_BASE",    "http://your-nas/system_monitor/reports")

# 임계값 (색상 판단)
WARN  = {"cpu": 70, "mem": 75, "disk": 80}
CRIT  = {"cpu": 80, "mem": 85, "disk": 90}
# ============================================================


def get_csv_stats(hostname: str, report_type: str) -> dict:
    """NAS CSV에서 주간/월간 평균·최대 계산"""
    now = datetime.now()
    csv_path = os.path.join(NAS_DATA_BASE, hostname,
                            f"performance_{now.strftime('%Y%m')}.csv")

    if not os.path.exists(csv_path):
        return {}

    days = 7 if report_type == "weekly" else now.day  # 월간: 해당 월 전체
    cutoff = now - timedelta(days=days)

    cpu_l, mem_l, disk_l = [], [], []
    try:
        with open(csv_path, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                try:
                    ts = datetime.strptime(row["timestamp"], "%Y-%m-%d %H:%M:%S")
                    if ts >= cutoff:
                        cpu_l.append(float(row["cpu_usage"]))
                        mem_l.append(float(row["memory_usage"]))
                        disk_l.append(float(row["disk_usage"]))
                except (ValueError, KeyError):
                    continue
    except Exception:
        return {}

    if not cpu_l:
        return {}

    return {
        "cpu":     {"avg": sum(cpu_l)/len(cpu_l),  "max": max(cpu_l)},
        "mem":     {"avg": sum(mem_l)/len(mem_l),  "max": max(mem_l)},
        "disk":    {"avg": sum(disk_l)/len(disk_l), "max": max(disk_l)},
        "samples": len(cpu_l),
        "days":    days,
    }


def status_cls(val: float, key: str) -> str:
    if val >= CRIT[key]: return "crit"
    if val >= WARN[key]: return "warn"
    return "ok"

def cls_color(cls: str) -> str:
    return {"ok": "#27ae60", "warn": "#e67e22", "crit": "#e74c3c"}.get(cls, "#999")

def cls_badge(cls: str) -> str:
    return {"ok": "✅", "warn": "⚠️", "crit": "🔴"}.get(cls, "")


def parse_report(fpath: str) -> dict:
    """HTML 보고서에서 호스트명·생성시간·스냅샷 수치 추출"""
    with open(fpath, "r", encoding="utf-8") as f:
        html = f.read()

    data = {"file": fpath}

    m = re.search(r"🖥️ 호스트: ([^<\n]+)", html)
    data["hostname"] = m.group(1).strip() if m else \
                       os.path.basename(fpath).split("_")[0]

    m = re.search(r"🕐 생성시간: ([^<\n]+)", html)
    data["generated"] = m.group(1).strip() if m else ""

    # 요약 카드 스냅샷 (fallback용)
    cards = re.findall(
        r"<div class='lbl'>([^<]+)</div><div class='val (\w+)'[^>]*>([^<]+)</div>",
        html
    )
    data["snapshot"] = {}
    for label, cls, val in cards[:4]:
        data["snapshot"][label.strip()] = {"cls": cls, "val": val.strip()}

    return data


def build_metric_cell(label: str, short: str,
                      avg: float, max_v: float, key: str) -> str:
    """평균+최대 표시 셀 (CSV 데이터 있을 때)"""
    cls   = status_cls(avg, key)
    color = cls_color(cls)
    badge = cls_badge(cls)
    return (
        f'<td style="padding:10px 14px;text-align:center;'
        f'border-right:1px solid #f0f0f0;min-width:80px">'
        f'<div style="font-size:1.2em;font-weight:700;color:{color}">'
        f'{avg:.1f}%</div>'
        f'<div style="font-size:.7em;color:#bbb;margin-top:1px">'
        f'최대 {max_v:.1f}% {badge}</div>'
        f'<div style="font-size:.68em;color:#ddd">{short}</div>'
        f'</td>'
    )


def build_snapshot_cell(label: str, short: str, snapshot: dict) -> str:
    """스냅샷 표시 셀 (CSV 없을 때 fallback)"""
    m     = snapshot.get(label, {})
    val   = m.get("val", "N/A")
    cls   = m.get("cls", "ok")
    color = cls_color(cls)
    badge = cls_badge(cls)
    return (
        f'<td style="padding:10px 14px;text-align:center;'
        f'border-right:1px solid #f0f0f0;min-width:80px">'
        f'<div style="font-size:1.2em;font-weight:700;color:{color}">'
        f'{val}</div>'
        f'<div style="font-size:.7em;color:#bbb;margin-top:1px">'
        f'생성시점 {badge}</div>'
        f'<div style="font-size:.68em;color:#ddd">{short}</div>'
        f'</td>'
    )


def build_email_body(report_type: str, reports: list, date_str: str) -> str:
    report_label = "주간" if report_type == "weekly" else "월간"
    now_str      = datetime.now().strftime("%Y-%m-%d %H:%M")

    # 서버 행 생성
    rows = ""
    all_status = "ok"

    for r in reports:
        hostname  = r["hostname"]
        generated = r["generated"]
        snapshot  = r["snapshot"]
        fname     = os.path.basename(r["file"])
        link      = f"{NAS_WEB_BASE}/{report_type}/{fname}"

        stats = get_csv_stats(hostname, report_type)
        has_csv = bool(stats)

        # 상태 판단
        if has_csv:
            srv_cls = max(
                status_cls(stats["cpu"]["avg"],  "cpu"),
                status_cls(stats["mem"]["avg"],  "mem"),
                status_cls(stats["disk"]["avg"], "disk"),
                key=lambda x: {"ok": 0, "warn": 1, "crit": 2}[x]
            )
        else:
            srv_cls = r.get("status", "ok")

        if srv_cls == "crit": all_status = "crit"
        elif srv_cls == "warn" and all_status == "ok": all_status = "warn"

        # 데이터 출처 표시
        if has_csv:
            src_note = f"{stats['days']}일 / {stats['samples']}건"
            cpu_td   = build_metric_cell("CPU 사용률", "CPU",
                                         stats["cpu"]["avg"],  stats["cpu"]["max"],  "cpu")
            mem_td   = build_metric_cell("메모리",     "MEM",
                                         stats["mem"]["avg"],  stats["mem"]["max"],  "mem")
            disk_td  = build_metric_cell("디스크(/)",  "DISK",
                                         stats["disk"]["avg"], stats["disk"]["max"], "disk")
        else:
            src_note = "스냅샷"
            cpu_td   = build_snapshot_cell("CPU 사용률", "CPU",  snapshot)
            mem_td   = build_snapshot_cell("메모리",     "MEM",  snapshot)
            disk_td  = build_snapshot_cell("디스크(/)",  "DISK", snapshot)

        uptime = snapshot.get("업타임", {}).get("val", "N/A")
        srv_badge = cls_badge(srv_cls)

        rows += f"""
        <tr style="border-bottom:1px solid #f5f5f5">
          <td style="padding:12px 16px;border-right:1px solid #f0f0f0;min-width:130px">
            <span style="font-weight:600;font-size:.93em">{srv_badge} {hostname}</span><br>
            <span style="font-size:.7em;color:#ccc">{generated}</span><br>
            <span style="font-size:.68em;color:#d0e0ff;background:#2c3e50;
                         padding:1px 5px;border-radius:3px">{src_note}</span>
          </td>
          {cpu_td}{mem_td}{disk_td}
          <td style="padding:10px 12px;text-align:center;font-size:.75em;
                     color:#aaa;border-right:1px solid #f0f0f0">{uptime}</td>
          <td style="padding:10px 12px;text-align:center">
            <a href="{link}"
               style="display:inline-block;background:#2c3e50;color:#fff;
                      padding:5px 12px;border-radius:16px;text-decoration:none;
                      font-size:.75em;font-weight:600">보고서</a>
          </td>
        </tr>"""

    overall_text  = {"ok":"✅ 전체 정상","warn":"⚠️ 주의 필요","crit":"🔴 위험 항목"}[all_status]
    overall_color = cls_color(all_status)

    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:Arial,sans-serif;margin:0;padding:24px;background:#f0f2f5">
<div style="max-width:700px;margin:0 auto">

  <!-- 헤더 -->
  <div style="background:#2c3e50;padding:20px 24px;border-radius:10px 10px 0 0">
    <table style="width:100%;border-collapse:collapse">
      <tr>
        <td style="vertical-align:middle">
          <h2 style="margin:0;color:#fff;font-size:1.15em;font-weight:700">
            📊 인프라 {report_label} 보고서
          </h2>
          <p style="margin:6px 0 0;color:rgba(255,255,255,.7);font-size:.85em">
            {date_str} &nbsp;·&nbsp; 서버 {len(reports)}대 &nbsp;·&nbsp;
            <span style="color:{overall_color};font-weight:700">{overall_text}</span>
          </p>
        </td>
        <td style="text-align:right;vertical-align:middle;white-space:nowrap">
          <a href="{GRAFANA_URL}"
             style="display:inline-block;background:rgba(255,255,255,.12);
                    color:#fff;padding:8px 16px;border-radius:20px;
                    text-decoration:none;font-size:.8em;font-weight:600;
                    border:1px solid rgba(255,255,255,.25)">
            📡 실시간 모니터링 →
          </a>
        </td>
      </tr>
    </table>
  </div>

  <!-- 서버 테이블 -->
  <div style="background:#fff;border-radius:0 0 10px 10px;
              box-shadow:0 2px 12px rgba(0,0,0,.08);overflow:hidden">
    <table style="width:100%;border-collapse:collapse">
      <thead>
        <tr style="background:#fafafa;border-bottom:2px solid #eee">
          <th style="padding:9px 16px;text-align:left;font-size:.78em;
                     color:#888;border-right:1px solid #f0f0f0">서버</th>
          <th style="padding:9px 14px;text-align:center;font-size:.78em;
                     color:#888;border-right:1px solid #f0f0f0">CPU<br>
              <span style="font-weight:400;color:#bbb">평균 / 최대</span></th>
          <th style="padding:9px 14px;text-align:center;font-size:.78em;
                     color:#888;border-right:1px solid #f0f0f0">메모리<br>
              <span style="font-weight:400;color:#bbb">평균 / 최대</span></th>
          <th style="padding:9px 14px;text-align:center;font-size:.78em;
                     color:#888;border-right:1px solid #f0f0f0">디스크<br>
              <span style="font-weight:400;color:#bbb">평균 / 최대</span></th>
          <th style="padding:9px 14px;text-align:center;font-size:.78em;
                     color:#888;border-right:1px solid #f0f0f0">업타임</th>
          <th style="padding:9px 14px;text-align:center;font-size:.78em;color:#888">링크</th>
        </tr>
      </thead>
      <tbody>{rows}
      </tbody>
    </table>
  </div>

  <!-- 안내 -->
  <div style="margin-top:10px;padding:10px 14px;background:#fff;border-radius:8px;
              font-size:.73em;color:#aaa;box-shadow:0 1px 4px rgba(0,0,0,.05)">
    수치: CSV 평균·최대 (5분 간격 수집) &nbsp;|&nbsp;
    ✅ 정상 &nbsp;
    ⚠️ 경고 CPU≥70%·MEM≥75%·DISK≥80% &nbsp;
    🔴 위험 CPU≥80%·MEM≥85%·DISK≥90%
  </div>

  <p style="text-align:center;margin-top:14px;font-size:.72em;color:#ccc">
    자동 생성 · 인프라 모니터링 시스템 · {now_str}
  </p>
</div>
</body>
</html>"""


def send_email(subject: str, body: str):
    msg = MIMEMultipart("alternative")
    msg["From"]    = EMAIL_FROM
    msg["To"]      = ", ".join(EMAIL_TO)
    msg["Cc"]      = ", ".join(EMAIL_CC)
    msg["Subject"] = subject
    msg.attach(MIMEText(body, "html", "utf-8"))

    with smtplib.SMTP(SMTP_SERVER, SMTP_PORT, timeout=30) as s:
        s.ehlo(); s.starttls()
        s.login(SMTP_USER, SMTP_PASS)
        s.sendmail(EMAIL_FROM, EMAIL_TO + EMAIL_CC, msg.as_string())


def main():
    report_type = sys.argv[1] if len(sys.argv) > 1 else "weekly"
    if report_type not in ("weekly", "monthly"):
        print("Usage: send_report_email.py [weekly|monthly]")
        sys.exit(1)

    pattern = os.path.join(NAS_REPORT_BASE, report_type,
                           f"*_{report_type}_report_*.html")
    files = sorted(glob(pattern))
    if not files:
        print(f"❌ 보고서 없음: {pattern}")
        sys.exit(1)

    # 호스트명 기준 중복 제거: 파일명이 최신(내림차순 정렬 후 첫 번째)인 것만 유지
    seen_hosts: dict = {}
    for f in sorted(files, reverse=True):
        hostname = os.path.basename(f).split("_")[0]
        if hostname not in seen_hosts:
            seen_hosts[hostname] = f
    reports = [parse_report(f) for f in sorted(seen_hosts.values())]

    now = datetime.now()
    if report_type == "weekly":
        date_str = now.strftime("%Y년 %m월") + f" {now.isocalendar()[1]}주차"
        subject  = SUBJECT_WEEKLY.format(date=date_str, count=len(reports))
    else:
        date_str = now.strftime("%Y년 %m월")
        subject  = SUBJECT_MONTHLY.format(date=date_str, count=len(reports))

    body = build_email_body(report_type, reports, date_str)

    try:
        send_email(subject, body)
        print(f"✅ 발송 완료 → {', '.join(EMAIL_TO)} (참조: {', '.join(EMAIL_CC)})")
        print(f"   제목: {subject}")
    except Exception as e:
        print(f"❌ 발송 실패: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
