#!/usr/bin/env python3
"""Alertmanager -> Jandi Incoming Webhook proxy"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, urllib.request, urllib.error, os

JANDI_URL = os.environ.get(
    'JANDI_WEBHOOK_URL',
    'https://wh.jandi.com/connect-api/webhook/18381544/015336224f0bb780cb9fed693501d493'
)

SEV_COLOR = {'critical': '#F20001', 'warning': '#FAC11B', 'info': '#00BCD4'}
SEV_EMOJI = {'critical': '🔴', 'warning': '⚠️', 'info': 'ℹ️'}

def build_payload(data):
    status = data.get('status', 'firing')
    labels = data.get('commonLabels', {})
    anns   = data.get('commonAnnotations', {})
    alerts = data.get('alerts', [])
    sev    = labels.get('severity', 'warning')
    name   = labels.get('alertname', 'Alert')
    if status == 'resolved':
        body  = '✅ [RESOLVED] ' + name
        color = '#4CAF50'
    else:
        body  = SEV_EMOJI.get(sev, '⚠️') + ' [' + sev.upper() + '] ' + name
        color = SEV_COLOR.get(sev, '#FAC11B')
    info = []
    summary = anns.get('summary', '')
    if summary:
        info.append({'title': '요약', 'description': summary})
    for alert in alerts[:5]:
        al   = alert.get('labels', {})
        aa   = alert.get('annotations', {})
        ins  = al.get('nodename') or al.get('instance') or ''
        desc = aa.get('description') or aa.get('summary') or ''
        if ins or desc:
            info.append({'title': ins, 'description': desc})
    if len(alerts) > 5:
        info.append({'title': '', 'description': '... 외 ' + str(len(alerts)-5) + '건'})
    if not info:
        info.append({'title': '알람', 'description': str(labels)})
    return {'body': body, 'connectColor': color, 'connectInfo': info}

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw)
        except Exception as e:
            print('JSON parse error: ' + str(e), flush=True)
            self.send_response(400); self.end_headers(); return
        payload = build_payload(data)
        req = urllib.request.Request(
            JANDI_URL,
            data=json.dumps(payload).encode(),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        try:
            resp = urllib.request.urlopen(req, timeout=10)
            print('OK ' + str(resp.status) + ': ' + payload['body'][:80], flush=True)
            self.send_response(200); self.end_headers()
        except urllib.error.HTTPError as e:
            body = e.read()
            print('Jandi HTTP ' + str(e.code) + ': ' + str(body), flush=True)
            self.send_response(502); self.end_headers()
        except Exception as e:
            print('Jandi error: ' + str(e), flush=True)
            self.send_response(500); self.end_headers()
    def log_message(self, fmt, *args):
        pass

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8060))
    print('Jandi proxy listening on :' + str(port), flush=True)
    HTTPServer(('0.0.0.0', port), Handler).serve_forever()
