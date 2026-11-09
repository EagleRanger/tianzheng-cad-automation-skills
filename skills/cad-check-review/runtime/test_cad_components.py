"""Deployment tests use temporary files; no CAD startup or drawing mutation."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
import hashlib
from unittest.mock import patch
import cad_components as bundle
from cad_runtime.machine import load_profile, doctor, discover, PATH_KEYS
from cad_runtime.storage import encode
from cad_runtime.common import ClientError

class ComponentTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix="CAD 模块测试 ")
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)

    def profile(self):
        p=discover(bundle.ROOT)
        for k in PATH_KEYS: p[k]="deps/"+k
        path=self.root/"machine.json";path.write_bytes(encode(p))
        return path

    def test_machine_relative_paths_do_not_depend_on_cwd(self):
        p=load_profile(self.profile())
        for key in PATH_KEYS:self.assertEqual(Path(p[key]),self.root/"deps"/key)

    def test_missing_installation_is_not_reported_ready(self):
        p=load_profile(self.profile())
        self.assertEqual(doctor(p)["status"],"DEPENDENCIES_INCOMPLETE")

    def test_other_abi_cannot_be_silently_selected(self):
        path=self.profile();p=json.loads(path.read_text());p["backend"]="some-other-cad";path.write_bytes(encode(p))
        with self.assertRaisesRegex(ClientError,"ENV_BACKEND_UNVALIDATED"):load_profile(path)

    def test_existing_wrong_binary_is_not_accepted_as_autocad(self):
        profile=discover(bundle.ROOT);profile['acad_exe']=sys.executable
        self.assertIn("AutoCAD binary ABI is not verified as 24.0",doctor(profile)["issues"])

    def test_project_paths_cannot_enter_machine_profile(self):
        path=self.profile();p=json.loads(path.read_text());p["current_drawing"]="client.dwg";path.write_bytes(encode(p))
        with self.assertRaisesRegex(ClientError,"ENV_PROFILE_FIELDS"):load_profile(path)

    def test_export_uses_explicit_file_allowlist_and_real_hashes(self):
        profile=discover(bundle.ROOT)
        out=self.root/"bundle.zip";bundle.export_bundle(profile,out)
        with zipfile.ZipFile(out) as z:
            names=z.namelist();manifest=json.loads(z.read("package-manifest.json"))
            for files in bundle.MODULE_SOURCES.values():
                for source in files:self.assertIn(source,names)
            self.assertFalse(any(n.endswith('.dwg') or 'session_status' in n or 'machine.local' in n for n in names))
            for name,expected in manifest["files"].items():self.assertEqual(hashlib.sha256(z.read(name)).hexdigest(),expected)
            z.extractall(self.root/"另一电脑目录")
        # An extracted copy has no project state; read-only capability discovery still works.
        result=subprocess.run([sys.executable,"-X","utf8",str(self.root/"另一电脑目录/cad_session_client.py"),"describe","inspect"],cwd=self.root,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
        self.assertEqual(json.loads(result.stdout)["protocol"],"V736")

    def test_export_never_overwrites_package(self):
        p=self.root/"keep.zip";p.write_bytes(b"existing")
        with self.assertRaisesRegex(ClientError,"EXPORT_EXISTS"):bundle.export_bundle(discover(bundle.ROOT),p)
        self.assertEqual(p.read_bytes(),b"existing")

if __name__=="__main__":unittest.main()
