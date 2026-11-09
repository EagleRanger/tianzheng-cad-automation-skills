"""回归真实交接故障；临时目录/假宿主，不调用CAD、不写真实DWG。"""
import copy
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import cad_session_client as c
from cad_runtime import receipts as receipts_module, session as session_module, planning as planning_module, submission as submission_module, evidence as evidence_module

class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.drawing = self.folder / "isolated.dwg"
        self.drawing.write_bytes(b"test fixture only, not a real DWG")
        self.dll = self.folder / "loaded.dll"; self.dll.write_bytes(b"fixture")
        self.base = self.folder / "base.json"
        config = {k: str(self.drawing) for k in ("garden", "planting", "terrain")}
        config.update({k + "_sha256": c.digest(self.drawing) for k in ("garden", "planting", "terrain")})
        self.put(self.base, config)
        self.host = {"pid": 123, "created": 456, "image": "acad.exe"}
        self.binding = {"session_dir": str(self.folder), "base_job": str(self.base), "base_job_sha256": c.digest(self.base),
                        "loaded_dll": str(self.dll), "loaded_dll_sha256": c.digest(self.dll), "host": self.host}
        self.native = {"status": "READY_SAME_DOCUMENT", "last_saved": str(self.drawing), "last_sha256": c.digest(self.drawing),
                       "live_document": str(self.drawing), "pid": 123}
        self.put(self.folder / "session_status.json", self.native)
        self.params = {"space": "Model", "bounds": [0, 0, 10, 10]}
    def put(self, path, obj):
        Path(path).write_bytes(c.encode(obj))
    def probe(self, pid): return self.host
    def submit(self, request_id="op1", params=None, dry=False):
        from cad_runtime import bound_edits
        def fake_publish(binding,envelope,job_path,checkpoint):
            self.put(self.folder/'request_native_archive.json',envelope)
            return {'transport':'bound_native_extension'}
        with patch.object(submission_module,'BRIDGE_KINDS',submission_module.BRIDGE_KINDS-{'inspect'}),patch.object(bound_edits,'verified_release',return_value={}),patch.object(bound_edits,'publish',side_effect=fake_publish):
            return c.submit(self.binding, "inspect", self.params if params is None else params, request_id, dry, self.probe)
    def accepted(self):
        if (self.folder / "request.json").exists():(self.folder / "request.json").rename(self.folder / "request_native_archive.json")
    def receipt(self):
        self.put(self.folder / "op1.receipt.json", {"status": "SCOPED_READ_ONLY_INSPECTION", "source_sha256": c.digest(self.drawing), "pid": 123})

    def test_missing_scope_and_wrong_xy_schema_never_enters_cad(self):
        for params in ({"space": "Model"}, {"space": "Model", "x": 0, "y": 0, "width": 10, "height": 10}):
            with self.assertRaises(c.ClientError): self.submit(params=params)
        self.assertFalse((self.folder / "request.json").exists())
        self.assertEqual(list(self.folder.glob("*.job.json")), [])

    def test_recent_receipts_use_time_not_random_archive_name(self):
        self.submit("op1"); self.accepted(); self.receipt()
        old = self.folder / "request_native_archive.json"
        old.rename(self.folder / "request_zzzz.json")
        os.utime(self.folder / "op1.receipt.json", ns=(1000000000, 1000000000))
        self.submit("op2")
        (self.folder / "request.json").rename(self.folder / "request_aaaa.json")
        self.put(self.folder / "op2.receipt.json", {"status": "SCOPED_READ_ONLY_INSPECTION", "source_sha256": c.digest(self.drawing), "pid": 123})
        os.utime(self.folder / "op2.receipt.json", ns=(2000000000, 2000000000))
        self.assertEqual([r["id"] for r in c.request_records(self.folder)], ["op1", "op2"])

    def test_exact_receipt_lookup_preserves_other_pending_and_does_not_replay(self):
        self.submit(); self.accepted(); self.receipt(); self.submit("op2")
        before = {p.name: p.read_bytes() for p in self.folder.glob("*.json")}
        view = c.status_view(c.snapshot(self.binding, self.probe), "op1")
        self.assertEqual(view["request_counts"], {"total": 2, "unsettled": 1})
        self.assertEqual([r["id"] for r in view["requests"]], ["op2", "op1"])
        self.assertFalse(view["can_submit"]); self.assertFalse(view["replayed"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.folder.glob("*.json")})

    def test_missing_or_ambiguous_exact_receipt_never_infers_resubmit(self):
        self.submit(); self.accepted(); self.receipt()
        snap = c.snapshot(self.binding, self.probe)
        with self.assertRaisesRegex(c.ClientError, "REQUEST_ID_NOT_FOUND"):
            c.status_view(snap, "missing")
        snap["requests"].append(copy.deepcopy(snap["requests"][0]))
        with self.assertRaisesRegex(c.ClientError, "REQUEST_ID_AMBIGUOUS"):
            c.status_view(snap, "op1")
        self.assertFalse((self.folder / "request.json").exists())

    def test_dcs_or_paper_not_silently_used_as_model_wcs(self):
        with self.assertRaisesRegex(c.ClientError, "INSPECT_SPACE"):
            self.submit(params={"space": "DCS", "bounds": [0, 0, 1, 1]})

    def test_view_layout_is_explicit_name_not_hardcoded_layout_one(self):
        p={**self.params,"view":{"layout":"布局2","x":5,"y":5,"width":10,"height":10}}
        with patch('cad_runtime.bound_edits.verified_release',return_value={}):
            self.assertEqual(self.submit(params=p,dry=True)["job"]["layout"],"布局2")
        p["view"]["layout"]="布局2\ncommand"
        with self.assertRaisesRegex(c.ClientError,"VIEW_INVALID"):self.submit(params=p,dry=True)
        self.assertFalse((self.folder/"request.json").exists())

    def test_reconciled_rejected_view_is_terminal_but_not_success(self):
        self.submit();self.accepted()
        failed=self.folder/'preserved_failure.json';self.put(failed,{'error':'LAYOUT_INVALID'})
        emergency=self.folder/'emergency.dwg';emergency.write_bytes(b'protected fixture')
        self.put(self.folder/'op1.receipt.json',{'status':'RECONCILED_READ_ONLY_REJECTION','source_sha256':c.digest(self.drawing),'reason':'LAYOUT_INVALID_BEFORE_VIEW_CHANGE','inspection_completed':False,'replayed':False,'preserved_failure':str(failed),'emergency':str(emergency)})
        snap=c.snapshot(self.binding,self.probe)
        self.assertTrue(snap['can_submit']);self.assertEqual(snap['requests'][0]['state'],'RESOLVED_REJECTED')
        self.assertEqual(self.submit()['state'],'ALREADY_SUBMITTED')
        with self.assertRaisesRegex(c.ClientError,'CAPTURE_NEEDS_COMPLETED_VIEW_REQUEST'):
            with patch.object(evidence_module,'snapshot',return_value=snap):c.capture(self.binding,'op1')

    def test_prepare_no_queue_and_complete_final_hash(self):
        prepared = self.submit(dry=True)
        self.assertFalse((self.folder / "request.json").exists())
        self.assertFalse((self.folder / "op1.job.json").exists())
        result = self.submit()
        envelope = c.read(self.folder / "request.json")
        self.assertEqual(envelope["job_sha256"], c.digest(envelope["job_path"]))
        self.assertEqual(prepared["request"], envelope)
        self.assertEqual(result["state"], "SUBMITTED")
        self.assertNotIn(b"__HASH__", (self.folder / "request.json").read_bytes())

    def test_accepted_no_receipt_overrides_stale_ready(self):
        self.submit(); self.accepted()
        snap = c.snapshot(self.binding, self.probe)
        self.assertFalse(snap["can_submit"])
        self.assertEqual(snap["requests"][0]["state"], "ACCEPTED_UNSETTLED")
        with self.assertRaisesRegex(c.ClientError, "SESSION_NOT_READY"): self.submit("op2")
        self.assertFalse((self.folder / "op2.job.json").exists())

    def test_cold_new_client_same_id_never_replays(self):
        self.submit(); self.accepted()
        restored = json.loads(json.dumps(self.binding))
        result = c.submit(restored, "inspect", self.params, "op1", probe=self.probe)
        self.assertEqual(result["state"], "ALREADY_SUBMITTED")
        self.assertFalse(result["replayed"])
        self.assertFalse((self.folder / "request.json").exists())

    def test_completed_id_dedup_and_next_operation_allowed(self):
        self.submit(); self.accepted(); self.receipt()
        self.assertEqual(self.submit()["state"], "ALREADY_SUBMITTED")
        self.assertEqual(self.submit("op2")["state"], "SUBMITTED")

    def test_id_reused_with_changed_targets_rejected(self):
        self.submit(); self.accepted()
        with self.assertRaisesRegex(c.ClientError, "REQUEST_ID_REUSED"):
            self.submit(params={"space": "Model", "bounds": [1, 1, 10, 10]})

    def test_new_model_reorders_keys_does_not_change_request_identity(self):
        self.submit(); self.accepted()
        self.assertEqual(self.submit(params={"bounds": [0, 0, 10, 10], "space": "Model"})["state"], "ALREADY_SUBMITTED")

    def test_native_accept_during_scan_is_not_false_ready(self):
        self.submit()
        real_read = c.read
        moved = []
        def moving_read(path):
            obj = real_read(path)
            if Path(path).name == "request.json" and not moved:
                self.accepted(); moved.append(True)
            return obj
        with patch.object(receipts_module, "read", side_effect=moving_read):
            snap = c.snapshot(self.binding, self.probe)
        self.assertFalse(snap["can_submit"])
        self.assertIn("QUEUE_CHANGED", snap["issues"][0])

    def test_legacy_failed_close_with_old_ready_stays_held(self):
        self.submit(); self.accepted()
        self.put(self.folder / "op1.receipt.json", {"status": "HOLD_DEFERRED_CLOSE_FAILED"})
        snap = c.snapshot(self.binding, self.probe)
        self.assertFalse(snap["can_submit"])
        self.assertEqual(snap["requests"][0]["state"], "RECEIPT_REQUIRES_RECONCILIATION")

    def test_failure_receipt_precedes_ready_even_with_complete_job(self):
        self.submit(); self.accepted(); self.receipt()
        self.put(self.folder / "session_failure.json", {"status": "HOLD"})
        self.assertIn("NATIVE_FAILURE", c.snapshot(self.binding, self.probe)["issues"][0])

    def test_pid_reuse_and_loaded_dll_change_rejected(self):
        snap = c.snapshot(self.binding, lambda pid: {**self.host, "created": 789})
        self.assertFalse(snap["can_submit"])
        self.assertIn("HOST_IDENTITY_CHANGED", snap["issues"][0])
        self.dll.write_bytes(b"changed")
        self.assertIn("LOADED_DLL_CHANGED", c.snapshot(self.binding, self.probe)["issues"][0])

    def test_corrupt_or_wrong_hash_archive_never_disappears(self):
        self.submit(); self.accepted()
        (self.folder / "op1.job.json").write_text("{}")
        snap = c.snapshot(self.binding, self.probe)
        self.assertFalse(snap["can_submit"])
        self.assertEqual(snap["requests"][0]["state"], "UNREADABLE_REQUEST")

    def test_no_rehash_of_open_dwg_in_prepare(self):
        real = c.digest
        def no_dwg(path):
            self.assertNotEqual(Path(path).suffix.lower(), ".dwg")
            return real(path)
        with patch.object(session_module, "digest", side_effect=no_dwg), patch.object(receipts_module, "digest", side_effect=no_dwg), patch.object(submission_module, "digest", side_effect=no_dwg):
            self.assertEqual(self.submit(dry=True)["state"], "VALIDATED_NOT_SUBMITTED")

    def test_atomic_publish_does_not_overwrite_existing_queue(self):
        queued = self.folder / "request.json"
        self.put(queued, {"existing": True}); before = queued.read_bytes()
        with self.assertRaises(FileExistsError): c.atomic_new(queued, {"replacement": True})
        self.assertEqual(before, queued.read_bytes())

    def test_race_between_two_clients_only_one_can_publish(self):
        barrier = threading.Barrier(2); results = []
        def worker(identity):
            barrier.wait()
            try: results.append(c.submit(self.binding,"inspect",self.params,identity,False,self.probe)["state"])
            except (c.ClientError, OSError): results.append("rejected")
        threads = [threading.Thread(target=worker, args=(f"op{i}",)) for i in range(2)]
        # Patch once outside concurrent workers. Overlapping context managers
        # can restore another worker's mock and leak a deleted fixture later.
        from cad_runtime import bound_edits
        with patch.object(submission_module,'BRIDGE_KINDS',submission_module.BRIDGE_KINDS-{'inspect'}),patch.object(bound_edits,'verified_release',return_value={}),patch.object(bound_edits,'publish',side_effect=AssertionError('legacy queue fixture must not use extension')):
            for thread in threads: thread.start()
            for thread in threads: thread.join()
        self.assertEqual(results.count("SUBMITTED"), 1)
        self.assertEqual(c.read(self.folder / "request.json")["job_sha256"], c.digest(c.read(self.folder / "request.json")["job_path"]))

    def test_host_starting_cannot_be_treated_as_ready(self):
        (self.folder / "session_status.json").unlink()
        snap = c.snapshot(self.binding, self.probe)
        self.assertEqual(snap["state"], "STARTING_OR_BOOT_FAILED")
        self.assertFalse(snap["can_submit"])

    def test_legacy_aliased_terrain_is_not_reported_as_validated_xref(self):
        snap = c.snapshot(self.binding, self.probe)
        self.assertIn("TERRAIN_ALIASES_PRIMARY_DRAWING", snap["warnings"][0])
        # Existing read-only diagnosis remains possible; do not invent a new permission state.
        self.assertTrue(snap["can_submit"])

    def test_machine_profile_change_blocks_next_request(self):
        profile = self.folder / "machine.local.json"
        self.put(profile, {"backend":"fixture"})
        self.binding.update(environment=str(profile), environment_sha256=c.digest(profile))
        self.assertTrue(c.snapshot(self.binding, self.probe)["can_submit"])
        self.put(profile, {"backend":"changed"})
        snap=c.snapshot(self.binding,self.probe)
        self.assertFalse(snap["can_submit"])
        self.assertIn("MACHINE_ENVIRONMENT_CHANGED",snap["issues"])

    def test_capture_refuses_a_different_saved_drawing(self):
        self.submit(params={**self.params, "view": {"layout":"布局1", "x":5, "y":5, "width":10, "height":10}})
        self.accepted(); self.receipt()
        self.native["last_sha256"] = "b" * 64
        self.put(self.folder / "session_status.json", self.native)
        with patch.object(evidence_module, "snapshot", return_value={"can_submit":True, "saved_checkpoint":self.native}):
            with self.assertRaisesRegex(c.ClientError, "CAPTURE_SAVED_POINT_CHANGED"):
                c.capture(self.binding, "op1")
        self.assertFalse((self.folder / "op1.capture.json").exists())

    def test_capture_completed_id_reuses_evidence_without_new_process(self):
        self.submit(params={**self.params, "view": {"layout":"布局1", "x":5, "y":5, "width":10, "height":10}})
        self.accepted(); self.receipt()
        proof={"status":"ACTUAL_CAD_VIEW_CAPTURED", "image":"fixture.cad.png"}
        self.put(self.folder / "op1.capture.receipt.json", proof)
        with patch.object(evidence_module, "snapshot", return_value={"can_submit":True,"saved_checkpoint":self.native}), patch.object(evidence_module.subprocess,"run") as run:
            self.assertEqual(c.capture(self.binding, "op1"), proof)
            run.assert_not_called()

    def test_unallowlisted_transfer_rejected_before_queue(self):
        obj = {"handle": "AA", "type": "AcDbPolyline", "layer": "0", "bounds": [0, 0, 1, 1]}
        with self.assertRaisesRegex(c.ClientError, "SOURCE_NOT_ALLOWLISTED"):
            c.submit(self.binding, "transfer", {"source": str(self.folder / "old.dwg"), "old_targets": [], "source_targets": [obj]}, "op1", probe=self.probe)
        self.assertFalse((self.folder / "request.json").exists())

    def test_bad_target_and_nan_rejected(self):
        with self.assertRaises(c.ClientError): c.validate("erase", {"targets": [{"handle": "AA"}]})
        with self.assertRaises(c.ClientError): self.submit(params={"space": "Model", "bounds": [0, 0, float("nan"), 10]})

    def test_input_hash_and_receipt_cannot_be_supplied_by_model(self):
        with self.assertRaisesRegex(c.ClientError, "UNKNOWN_FIELDS"):
            self.submit(params={**self.params, "input_sha256": "__HASH__"})

    def test_wrong_source_receipt_is_not_success(self):
        self.submit(); self.accepted()
        self.put(self.folder / "op1.receipt.json", {"status": "SCOPED_READ_ONLY_INSPECTION", "source_sha256": "0" * 64})
        self.assertFalse(c.snapshot(self.binding, self.probe)["can_submit"])

    def test_early_switch_receipt_is_not_ready_until_native_state_updated(self):
        c.submit(self.binding, "switch", {"next_path": str(self.drawing)}, "op1", probe=self.probe)
        self.accepted()
        saved = self.folder / "op1.dwg"; saved.write_bytes(b"protected fixture")
        receipt = self.folder / "op1.receipt.json"
        self.put(receipt, {"status": "CURRENT_SAVED_BEFORE_SWITCH", "saved": str(saved), "sha256": c.digest(saved), "next": str(self.drawing)})
        state = self.folder / "session_status.json"
        stamp = receipt.stat().st_mtime_ns
        os.utime(state, ns=(stamp-10000000, stamp-10000000))
        self.assertFalse(c.snapshot(self.binding, self.probe)["can_submit"])
        os.utime(state, ns=(stamp+10000000, stamp+10000000))
        self.assertTrue(c.snapshot(self.binding, self.probe)["can_submit"])

    @unittest.skipUnless(os.name == 'nt', 'Windows path identity')
    def test_windows_allowlisted_source_is_case_insensitive(self):
        out = c.submit(self.binding, "switch", {"next_path": str(self.drawing).upper()}, "op1", dry_run=True, probe=self.probe)
        self.assertEqual(out["state"], "VALIDATED_NOT_SUBMITTED")

if __name__ == "__main__": unittest.main(verbosity=2)
