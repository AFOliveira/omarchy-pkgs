#!/usr/bin/env python3
"""Track Debian 13 ARM64 QEMU revisions, verifying an immutable snapshot first."""
import functools
import hashlib
import json
import lzma
from pathlib import Path
import re
import subprocess
import sys
import urllib.parse
import urllib.request

FEEDS = [
    'https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz',
    'https://deb.debian.org/debian/dists/trixie-updates/main/binary-arm64/Packages.xz',
    'https://security.debian.org/debian-security/dists/trixie-security/main/binary-arm64/Packages.xz',
]

def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        if not response.url.startswith('https://'):
            raise ValueError('Insecure redirect')
        return response.read()

def parts(version):
    match = re.fullmatch(r'(?:(\d+):)?([0-9][A-Za-z0-9.+~]*?)-([A-Za-z0-9.+~]+)', version)
    if not match:
        raise ValueError('Unsupported Debian version: ' + version)
    return int(match[1] or '0'), match[2], match[3]

def segment_cmp(a, b):
    # Debian policy: tilde precedes everything, then end/digits, letters,
    # then other characters; digit runs are compared numerically.
    def order(c):
        if c == '~': return -1
        if not c or c.isdigit(): return 0
        return ord(c) if c.isalpha() else ord(c) + 256
    while a or b:
        while (a and not a[0].isdigit()) or (b and not b[0].isdigit()):
            x, y = order(a[:1]), order(b[:1])
            if x != y: return (x > y) - (x < y)
            a, b = a[1:], b[1:]
        x = re.match(r'\d*', a)[0]
        y = re.match(r'\d*', b)[0]
        nx, ny = int(x or '0'), int(y or '0')
        if nx != ny: return (nx > ny) - (nx < ny)
        a, b = a[len(x):], b[len(y):]
    return 0

def compare(a, b):
    ea, ua, ra = parts(a)
    eb, ub, rb = parts(b)
    return (ea > eb) - (ea < eb) or segment_cmp(ua, ub) or segment_cmp(ra, rb)

def package_version(version):
    epoch, upstream, revision = parts(version)
    # Stable releases only. Fail visibly on prerelease/repack conventions that
    # need a reviewed Arch ordering rather than silently misordering them.
    if '~' in version:
        raise ValueError('Debian prerelease needs a reviewed Arch version mapping')
    return f'{epoch}.{upstream}.{revision}'

def records(data):
    found = []
    for stanza in re.split(r'\n\s*\n', lzma.decompress(data).decode()):
        fields = dict(re.findall(r'^([A-Za-z0-9-]+): (.*)$', stanza, re.M))
        if fields.get('Package') != 'qemu-user': continue
        if fields.get('Architecture') != 'arm64': raise ValueError('Wrong architecture')
        parts(fields['Version'])
        if not re.fullmatch(r'[0-9a-f]{64}', fields.get('SHA256', '')):
            raise ValueError('Missing/malformed SHA256')
        if not re.fullmatch(r'[1-9][0-9]*', fields.get('Size', '')):
            raise ValueError('Missing/malformed package size')
        found.append(fields)
    return found

def discover(current, current_pkgver, current_hash, get=fetch):
    candidates = [row for url in FEEDS for row in records(get(url))]
    if not candidates: raise ValueError('No ARM64 qemu-user package in Debian feeds')
    selected = max(candidates, key=functools.cmp_to_key(lambda a,b: compare(a['Version'], b['Version'])))
    version, checksum = selected['Version'], selected['SHA256']
    if any(row['SHA256'] != checksum for row in candidates if row['Version'] == version):
        raise ValueError('Debian feeds disagree on the selected checksum')
    ordering = compare(version, current)
    if ordering < 0: raise ValueError('Debian feeds are older than the pinned recipe')
    if ordering == 0:
        if checksum != current_hash: raise ValueError('Checksum changed for the pinned Debian revision')
        return {}
    pkgver = package_version(version)
    if int(subprocess.check_output(['vercmp', pkgver, current_pkgver], text=True)) <= 0:
        raise ValueError('New Debian revision does not advance Arch version; review mapping')
    api = 'https://snapshot.debian.org/mr/binary/qemu-user/' + urllib.parse.quote(version, safe='') + '/binfiles'
    document = json.loads(get(api))
    if document.get('binary') != 'qemu-user' or document.get('binary_version') != version:
        raise ValueError('Snapshot revision differs')
    hashes = {row['hash'] for row in document['result'] if row['architecture'] == 'arm64'}
    if len(hashes) != 1 or not re.fullmatch(r'[0-9a-f]{40}', next(iter(hashes), '')):
        raise ValueError('Missing/ambiguous ARM64 snapshot')
    snapshot = hashes.pop()
    archive = get('https://snapshot.debian.org/file/' + snapshot)
    if len(archive) != int(selected['Size']) or hashlib.sha256(archive).hexdigest() != checksum or hashlib.sha1(archive).hexdigest() != snapshot:
        raise ValueError('Snapshot bytes differ from Debian package metadata')
    return {'pkgver': pkgver, 'variables': {'_debver': version, '_snapshot': snapshot},
            'sha256sums': {'aarch64': [checksum]}}

def main():
    recipe = Path('PKGBUILD').read_text()
    def scalar(name):
        match = re.search(r'^' + name + r'=[\"\']?([^\"\'\n]+)', recipe, re.M)
        if not match: raise ValueError('Missing recipe scalar: ' + name)
        return match[1]
    checksum = re.search(r"^sha256sums_aarch64=\('([a-f0-9]{64})'\)", recipe, re.M)
    if not checksum: raise ValueError('Missing current ARM checksum')
    print(json.dumps(discover(scalar('_debver'), scalar('pkgver'), checksum[1])))

if __name__ == '__main__':
    try: main()
    except Exception as error:
        sys.exit('QEMU Debian update failed: ' + str(error))
