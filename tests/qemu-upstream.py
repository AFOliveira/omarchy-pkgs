#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import lzma
import re
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'pkgbuilds/qemu-user-static'
spec = importlib.util.spec_from_file_location('qemu', PACKAGE / '.omarchy/upstream.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
CURRENT = '1:10.0.11+ds-0+deb13u1+b1'

class Updates(unittest.TestCase):
    def fixtures(self, version):
        blob = b'fixture package bytes'
        sha = hashlib.sha256(blob).hexdigest()
        snap = hashlib.sha1(blob).hexdigest()
        row = f'Package: qemu-user\nArchitecture: arm64\nVersion: {version}\nSHA256: {sha}\nSize: {len(blob)}\n'
        feeds = {url: lzma.compress(row.encode()) for url in q.FEEDS}
        def get(url):
            if url in feeds: return feeds[url]
            if '/mr/' in url:
                return json.dumps({'binary':'qemu-user', 'binary_version':version,
                  'result':[{'architecture':'arm64','hash':snap}]}).encode()
            return blob
        return get, feeds, sha

    def test_versions(self):
        for old, new in [(CURRENT,'1:10.0.11+ds-0+deb13u1+b2'),
                         (CURRENT,'1:10.0.11+ds-0+deb13u2'),
                         (CURRENT,'1:10.0.12+ds-1'),
                         (CURRENT,'2:9.0.0+ds-1')]:
            with self.subTest(new=new):
                get,_,_=self.fixtures(new)
                result=q.discover(old,q.package_version(old),'0'*64,get)
                self.assertEqual(result['variables']['_debver'],new)
                self.assertGreater(q.compare(new,old),0)
        self.assertLess(q.compare('1:10.0~rc1-1','1:10.0-1'),0)
        self.assertLess(q.compare('1:10.0-2','1:10.0-10'),0)

    def test_security_wins(self):
        newer='1:10.0.11+ds-0+deb13u2'
        get,feeds,_=self.fixtures(newer)
        _,oldfeeds,_=self.fixtures(CURRENT)
        feeds[q.FEEDS[0]]=oldfeeds[q.FEEDS[0]]
        self.assertEqual(q.discover(CURRENT,q.package_version(CURRENT),'0'*64,get)['variables']['_debver'],newer)

    def test_unchanged(self):
        get,_,sha=self.fixtures(CURRENT)
        self.assertEqual(q.discover(CURRENT,q.package_version(CURRENT),sha,get),{})
        with self.assertRaisesRegex(ValueError,'Checksum changed'):
            q.discover(CURRENT,q.package_version(CURRENT),'0'*64,get)

    def test_bad_metadata(self):
        get,feeds,_=self.fixtures('1:10.0.12+ds-1')
        feeds[q.FEEDS[0]]=lzma.compress(b'Package: qemu-user\nArchitecture: arm64\nVersion: invalid\n')
        with self.assertRaises(ValueError): q.discover(CURRENT,q.package_version(CURRENT),'0'*64,get)

    def test_snapshot_failures(self):
        for failure in ['missing','bytes','metadata']:
            get,_,_=self.fixtures('1:10.0.12+ds-1')
            def bad(url):
                if '/file/' in url:
                    if failure=='missing': raise OSError('unavailable snapshot')
                    if failure=='bytes': return b'corrupt'
                if '/mr/' in url and failure=='metadata': return b'{}'
                return get(url)
            with self.subTest(failure=failure), self.assertRaises((ValueError,OSError)):
                q.discover(CURRENT,q.package_version(CURRENT),'0'*64,bad)

    def sync(self, recipe, release):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'fixture'; (p/'.omarchy').mkdir(parents=True)
            (p/'PKGBUILD').write_text(recipe)
            (p/'.omarchy/package.json').write_text('{"source":"local"}')
            (p/'.omarchy/upstream.sh').write_text("#!/bin/bash\ncat <<'JSON'\n"+json.dumps(release)+"\nJSON\n")
            # Load production functions, excluding only the command dispatch.
            prefix=(ROOT/'bin/sync-upstream').read_text().split('if [[ ${#SPECIFIC_PACKAGES[@]} -gt 0 &&')[0]
            prefix=prefix.replace('BUILD_ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")', 'BUILD_ROOT='+str(ROOT))
            command=prefix+'\nPKGBUILDS_DIR='+tmp+'\nSPECIFIC_MODE=true\nsync_package fixture\n((FAILED == 0))\n'
            result=subprocess.run(['bash','-c',command],capture_output=True,text=True)
            return result,(p/'PKGBUILD').read_text()

    def test_atomic_sync_and_idempotence(self):
        get,_,_=self.fixtures('1:10.0.11+ds-0+deb13u2')
        release=q.discover(CURRENT,q.package_version(CURRENT),'0'*64,get)
        before=(PACKAGE/'PKGBUILD').read_text()
        before=re.sub(r'^pkgver=.*$', 'pkgver='+q.package_version(CURRENT), before, flags=re.M)
        before=re.sub(r'^_debver=.*$', '_debver='+CURRENT, before, flags=re.M)
        result,after=self.sync(before,release)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('_debver='+release['variables']['_debver'],after)
        self.assertIn('_snapshot='+release['variables']['_snapshot'],after)
        self.assertIn(release['sha256sums']['aarch64'][0],after)
        result,again=self.sync(after,release)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(again,after)

    def test_invalid_variables_leave_recipe_unchanged(self):
        before=(PACKAGE/'PKGBUILD').read_text()
        for variables in [{'_debver':'$(touch /tmp/qemu-injection)'}, {'pkgver':'2'},
                          {'_absent':'1'}, {'_snapshot':'abc\ncommand'}, {'_snapshot':'https://bad'}]:
            with self.subTest(variables=variables):
                result,after=self.sync(before,{'pkgver':'99','variables':variables,'sha256sums':{'aarch64':['a'*64]}})
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(before,after)

if __name__=='__main__': unittest.main()
