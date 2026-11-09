"""Read-only layer queries: binding, one launch, no silent retry or invented success."""
import subprocess, unittest
from unittest.mock import patch
from pathlib import Path
import cad_session_client as client
from cad_runtime import layers
import test_cad_session_client as fixtures


class LayerQueryTests(unittest.TestCase):
    setUp=fixtures.SessionTests.setUp
    put=fixtures.SessionTests.put
    probe=fixtures.SessionTests.probe
    submit=fixtures.SessionTests.submit

    def run_query(self, names=None):
        return client.read_layers(self.binding, "layer_trial", names or ["00-网格2"])

    def ready(self):
        return {"can_submit":True,"saved_checkpoint":self.native}

    def test_busy_host_never_starts_layer_helper(self):
        with patch.object(layers,"snapshot",return_value={"can_submit":False}), patch.object(layers.subprocess,"run") as runner:
            with self.assertRaisesRegex(client.ClientError,"NOT_READY"):self.run_query()
        runner.assert_not_called()
        self.assertFalse((self.folder/"layer_trial.layers.json").exists())

    def test_pending_query_is_not_launched_twice(self):
        with patch.object(layers,"snapshot",return_value=self.ready()), patch.object(layers.subprocess,"run",return_value=subprocess.CompletedProcess([],0,b"",b"")) as runner:
            a=self.run_query();b=self.run_query()
            with self.assertRaisesRegex(client.ClientError,"DIFFERENT_INPUT"):self.run_query(["other layer"])
        self.assertEqual(a,b);self.assertFalse(b["replayed"]);runner.assert_called_once()
        self.assertFalse((self.folder/"request.json").exists())
        self.assertFalse(list(self.folder.glob("*.dwg")) != [self.drawing])

    def test_saved_point_change_invalidates_same_query_id(self):
        with patch.object(layers,"snapshot",side_effect=[self.ready(),{"can_submit":True,"saved_checkpoint":{**self.native,"last_sha256":"b"*64}}]), patch.object(layers.subprocess,"run",return_value=subprocess.CompletedProcess([],0,b"",b"")) as runner:
            self.run_query()
            with self.assertRaisesRegex(client.ClientError,"DIFFERENT_INPUT"):self.run_query()
        runner.assert_called_once()

    def test_failed_helper_receipt_is_not_reported_as_layer_result(self):
        def fail(*args,**kwargs):
            self.put(self.folder/"layer_trial.layers.receipt.json",{"status":"LAYER_QUERY_FAILED","error":"LAYER_COM_HOST_MISMATCH"})
            return subprocess.CompletedProcess([],0,b"",b"")
        with patch.object(layers,"snapshot",return_value=self.ready()), patch.object(layers.subprocess,"run",side_effect=fail):
            with self.assertRaisesRegex(client.ClientError,"LAYER_COM_HOST_MISMATCH"):self.run_query()

    def test_completed_snapshot_returns_without_new_com_call(self):
        def complete(*args,**kwargs):
            self.put(self.folder/"layer_trial.layers.receipt.json",{"status":"READ_ONLY_LAYER_STATE","layers":[{"name":"00-网格2","frozen":False}],"cad_modified":False})
            return subprocess.CompletedProcess([],0,b"",b"")
        with patch.object(layers,"snapshot",return_value=self.ready()), patch.object(layers.subprocess,"run",side_effect=complete) as runner:
            self.assertFalse(self.run_query()["reused_snapshot"])
            self.assertTrue(self.run_query()["reused_snapshot"])
        runner.assert_called_once()

if __name__=="__main__":unittest.main()
