"""Step-module regressions use fake receipts; never open CAD."""
from pathlib import Path
import json,subprocess,unittest
from unittest.mock import patch
import cad_session_client as client
from cad_runtime import evidence
import test_cad_session_client as fixtures

class StepModuleTests(unittest.TestCase):
    setUp=fixtures.SessionTests.setUp
    put=fixtures.SessionTests.put
    probe=fixtures.SessionTests.probe
    submit=fixtures.SessionTests.submit
    accepted=fixtures.SessionTests.accepted
    receipt=fixtures.SessionTests.receipt

    def test_capture_helper_path_survives_module_move_and_pending_call_is_not_replayed(self):
        self.submit(params={**self.params,"view":{"layout":"布局1","x":5,"y":5,"width":10,"height":10}})
        self.accepted();self.receipt()
        self.binding["base_job_sha256"]=client.digest(self.base)
        with patch.object(evidence,"snapshot",return_value={"can_submit":True,"saved_checkpoint":self.native}), patch.object(evidence.subprocess,"run",return_value=subprocess.CompletedProcess([],0,b"",b"")) as runner:
            first=client.capture(self.binding,"op1")
            second=client.capture(self.binding,"op1")
        self.assertEqual(first["status"],"CAPTURE_IN_PROGRESS")
        self.assertEqual(second,first)
        runner.assert_called_once()
        argv=runner.call_args.args[0]
        self.assertEqual(Path(argv[argv.index("-File")+1]),Path(client.__file__).with_name("run_private_cad_script.ps1"))
        text=(self.folder/"op1.capture.ps1").read_text(encoding="utf-8-sig")
        self.assertIn(str(Path(client.__file__).with_name("capture_private_session.ps1")),text)
        self.assertFalse((self.folder/"request.json").exists())

    def test_public_description_covers_native_handlers_without_needing_a_project(self):
        result=client.describe()
        self.assertEqual(set(result["operation"]),set(result["parameters"]))
        for op,contract in result["operation"].items():
            native="\n".join(Path(client.__file__).with_name(source.strip()).read_text(encoding="utf-8-sig") for source in contract.get("native_source","V736BaseSession.cs").split(" + "))
            expected={"viewport_restore":"NativeViewportRestoreV1.Apply(","layout_delete":"DeleteLayout(db,job,","paper_leaders_copy":"public void LeadersRun(){Execute(true);}","layout_import":'doc.Editor.Command("_.-LAYOUT","_Template",job.source,job.source_layout)',"purge_unused":"Purge(db);"}.get(op)
            if expected is None:
                self.assertTrue(contract.get("native_handler"),op)
                expected=contract["native_handler"]+"("
            self.assertIn(expected,native)
            self.assertTrue(contract["scope"])
            self.assertTrue(contract["completion"])
        self.assertIn("allowlisting does not establish",result["operation"]["transfer"]["completion"])
        self.assertEqual(len(result["execution_steps"]),9)

    def test_unknown_description_gives_exact_supported_command_without_accepting_alias(self):
        with self.assertRaisesRegex(client.ClientError,"describe switch"):
            client.describe("switch_document")
        self.assertNotIn("switch_document",client.KINDS)
        self.assertEqual(set(client.describe("switch")["examples"]["switch"]["params"]),{"next_path"})

if __name__=="__main__":unittest.main()
