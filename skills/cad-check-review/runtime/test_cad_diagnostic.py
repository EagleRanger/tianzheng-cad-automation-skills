"""Regression coverage for retired-host and source/binary command mismatches."""
import json,tempfile,unittest,subprocess
from pathlib import Path
from unittest.mock import patch
import cad_module_diagnostic as diag
from cad_runtime.storage import encode,digest
from cad_runtime.common import ClientError
from cad_runtime.bound_edits import require_entry
from cad_runtime import lifecycle

class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.source=self.root/'copy.dwg';self.source.write_bytes(b'protected-copy')
        self.dll=self.root/'module.dll';self.dll.write_bytes(b'PE\x00HLCADNATIVEDETAILSTESTV1\x00')
        self.state=self.put('state.json',{'session_purpose':'isolated_module_test','session_client':{'session_dir':str(self.root),'loaded_dll':str(self.root/'loaded.dll')}})
        self.build=self.put('build.json',{'dll':str(self.dll),'sha256':digest(self.dll)})
        self.config=self.put('config.json',{'source':str(self.source),'source_sha256':digest(self.source),'receipt':str(self.root/'native.json')})
        self.ready={'can_submit':True,'issues':[],'saved_checkpoint':{'live_document':str(self.source),'last_saved':str(self.source),'last_sha256':digest(self.source)}}
    def put(self,name,value):
        p=self.root/name;p.write_bytes(encode(value));return p
    def prepare(self,entry='HLCADNATIVEDETAILSTESTV1'):
        return diag.prepare(self.state,self.build,entry,self.config,'read7')
    def test_retired_host_fails_before_manifest_or_private_helper(self):
        with patch.object(diag,'snapshot',return_value={'can_submit':False,'issues':['HOST_EXITED']}):
            with self.assertRaisesRegex(ClientError,'HOST_EXITED'):self.prepare()
        self.assertFalse(list(self.root.glob('*.module-dispatch.json')))
    def test_source_command_not_in_binary_fails_before_dispatch(self):
        with patch.object(diag,'snapshot',return_value=self.ready):
            with self.assertRaisesRegex(ClientError,'MODULE_ENTRY_NOT_FOUND'):self.prepare('HLCADNATIVEDETAILSTESTV2')
        self.assertFalse(list(self.root.glob('*.module-dispatch.json')))
    def test_production_state_cannot_enter_raw_diagnostic(self):
        self.put('state.json',{'session_client':{}})
        with self.assertRaisesRegex(ClientError,'ISOLATED_TEST_STATE_REQUIRED'):self.prepare()
    def test_same_id_does_not_replay_and_changed_config_is_rejected(self):
        with patch.object(diag,'snapshot',return_value=self.ready):
            path,fresh=self.prepare();self.assertTrue(fresh)
            self.assertFalse(self.prepare()[1])
            self.put('config.json',{'source':str(self.source),'source_sha256':digest(self.source),'receipt':str(self.root/'another.json')})
            with self.assertRaisesRegex(ClientError,'DIAGNOSTIC_ID_REUSED'):self.prepare()
        self.assertEqual(self.source.read_bytes(),b'protected-copy')
    def test_command_name_matches_whole_metadata_token(self):
        self.assertEqual(require_entry(self.dll,'HLCADNATIVEDETAILSTESTV1'),['HLCADNATIVEDETAILSTESTV1'])
        with self.assertRaisesRegex(ClientError,'MODULE_ENTRY_NOT_FOUND'):require_entry(self.dll,'HLCADNATIVEDETAILSTESTV')
    def close_fixture(self):
        receipt=self.put('close.receipt.json',{'status':'DOCUMENTS_CLOSED_AWAITING_ORDINARY_WINDOW_CLOSE','pid':123,'documents':[{'closed':True,'snapshot':str(self.source),'sha256':digest(self.source)}]})
        binding={'session_dir':str(self.root),'host':{'pid':123,'created':456,'image':'acad.exe'}}
        return binding,receipt,[{'id':'close1','kind':'close','receipt':str(receipt)}]
    def test_close_checks_protected_bytes_before_touching_process(self):
        binding,receipt,records=self.close_fixture();self.source.write_bytes(b'changed')
        with patch.object(lifecycle,'request_records',return_value=records),patch.object(lifecycle,'process_identity') as probe:
            with self.assertRaisesRegex(ClientError,'PROTECTED_DOCUMENT_MISMATCH'):lifecycle.finish_close(binding,'close1')
        probe.assert_not_called()
    def test_close_does_not_touch_reused_pid(self):
        binding,receipt,records=self.close_fixture()
        with patch.object(lifecycle,'request_records',return_value=records),patch.object(lifecycle,'process_identity',return_value={'pid':123,'created':999,'image':'acad.exe'}):
            with self.assertRaisesRegex(ClientError,'HOST_IDENTITY_CHANGED'):lifecycle.finish_close(binding,'close1')
        self.assertFalse(list(self.root.glob('*.finish-close.ps1')))
    def test_close_existing_request_waits_without_reposting(self):
        binding,receipt,records=self.close_fixture();self.put('close1.window-close.json',{'status':'PREPARED_NO_RETRY'})
        with patch.object(lifecycle,'request_records',return_value=records),patch.object(lifecycle,'process_identity',return_value=binding['host']),patch.object(lifecycle.subprocess,'run') as run:
            self.assertEqual(lifecycle.finish_close(binding,'close1')['status'],'CLOSE_REQUESTED_WAIT_EXIT')
        run.assert_not_called()
    def test_zero_helper_exit_without_close_receipt_is_not_success(self):
        binding,receipt,records=self.close_fixture();binding['base_job_sha256']='a'*64
        with patch.object(lifecycle,'request_records',return_value=records),patch.object(lifecycle,'process_identity',return_value=binding['host']),patch.object(lifecycle.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            with self.assertRaisesRegex(ClientError,'CLOSE_REQUEST_NOT_CONFIRMED'):lifecycle.finish_close(binding,'close1')

if __name__=='__main__':unittest.main()
