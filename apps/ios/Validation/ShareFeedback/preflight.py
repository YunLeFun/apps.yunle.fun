"""Exercise the local Support composition before driving the system share UI."""
import base64
import http.cookiejar
import json
from pathlib import Path
import ssl
import sys
import urllib.error
import urllib.request
import uuid


def main():
    task, support = map(Path, sys.argv[1:3])
    control = json.loads((task / 'server-control.json').read_text())
    origin = control['origin']
    assert origin == 'https://127.0.0.1:18473'
    context = ssl.create_default_context(cafile=str(task / 'local-cert.pem'))
    cookies = http.cookiejar.CookieJar()
    client = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context), urllib.request.HTTPCookieProcessor(cookies))

    def request(path, body=None, headers=None, expected=200):
        values = {'Origin': origin, 'Content-Type': 'application/json', **(headers or {})}
        req = urllib.request.Request(origin + path, data=json.dumps(body).encode() if body is not None else None, headers=values)
        try:
            response = client.open(req, timeout=15)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            data = response.read()
            assert response.status == expected, (path, response.status, data[:300])
            return json.loads(data) if 'application/json' in response.headers.get('Content-Type', '') else data

    def command(action):
        return request('/_validation/' + action, {}, {'x-validation-key': control['controlKey']})

    command('reset')
    guest = request('/api/v1/feedback/guest', {})
    image = (support / 'apps/web/test/fixtures/feedback-screenshot.jpg').read_bytes()
    payload = {'productId': 'www', 'category': 'problem', 'description': 'Synthetic preflight screenshot feedback', 'context': {'source': 'apps-ios-share', 'version': 'acceptance'}, 'screenshots': [{'mimeType': 'image/jpeg', 'data': base64.b64encode(image).decode()}]}
    key = str(uuid.uuid4())
    headers = {'x-csrf-token': guest['csrfToken'], 'idempotency-key': key}
    request('/api/v1/private-feedback', payload, {**headers, 'Origin': 'https://invalid.example'}, expected=403)
    command('fail-after-commit')
    request('/api/v1/private-feedback', payload, headers, expected=503)
    receipt = request('/api/v1/private-feedback', payload, headers)['receipt']
    path = '/api/v1/tickets/' + receipt['ticketId']
    request(path, expected=401)
    token = receipt['ticketUrl'].split('#access=', 1)[1]
    request(path + '/access', {'token': token})
    ticket = request(path)
    assert any(payload['description'] in message['content'] for message in ticket['messages'])
    listing = request(path + '/screenshots')
    assert len(listing['items']) == 1
    restored = request(path + '/screenshots/' + listing['items'][0]['id'])
    # Support removes JPEG metadata again at its own trust boundary.
    assert restored.startswith(b'\xff\xd8') and restored.endswith(b'\xff\xd9')
    assert len(restored) == listing['items'][0]['sizeBytes']
    assert listing['items'][0]['width'] == 80 and listing['items'][0]['height'] == 120
    status = command('status')
    submissions = [event for event in status['events'] if event['kind'] == 'submit']
    assert status['records'] == 1 and len(submissions) == 2
    assert submissions[0]['id'] == submissions[1]['id'] and submissions[0]['key'] == submissions[1]['key']
    (task / 'preflight-result.json').write_text(json.dumps({'passed': True, 'oneTicketAfterRetry': True, 'privateImageReadBack': True, 'originAndGuestAccessChecked': True}, indent=2) + '\n')
    command('reset')
    print('Local Support protocol preflight passed: origin, guest/CSRF, ambiguous retry, ticket capability and private JPEG read-back')


if __name__ == '__main__':
    main()
