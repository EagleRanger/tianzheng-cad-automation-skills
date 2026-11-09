"""Isolated regression for shared-MD handoff, coverage, revision and retention."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from cad_runtime.review_contract import contract, source_text, validate_results
from cad_runtime import project_flow as pf


class ReviewContractTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.proof = self.root/'proof.txt'; self.proof.write_text('fixture')
        self.cad = self.root/'fixture.dwg'; self.cad.write_bytes(b'fixture-not-real-dwg')
        self.ids = ['a','b']
        self.flow = {'schema':1,'scope':'fixture','active_batch':{
            'id':'fixture','start_marker':'## requirements','end_marker':'<!-- CAD_WORKFLOW_V1',
            'user_confirmation':'pending'},'nodes':[
            {'id':'edit','owner':'执行','title':'edit','state':'pending','after':[], 'requirement_ids':self.ids},
            {'id':'review','owner':'校审','title':'review','state':'pending','after':['edit'],'requirement_ids':self.ids}]}
        self.md = self.root/'checklist.md'
        self.write()
        self.state=self.root/'state.json'
        self.state.write_text(json.dumps({'CAD_review_20261027':{'supervision':{
            'destination_thread':'manager','execution_thread':'writer','review_thread':'reviewer'}}}))
    def tearDown(self): self.tmp.cleanup()
    def write(self):
        self.md.write_text('<!-- 接续摘要：开始 -->\n已完成：history\n当前返修：执行｜fixture\n<!-- 接续摘要：结束 -->\n## requirements\nOriginal quotes and images.\n'+pf.START+json.dumps(self.flow)+pf.END,encoding='utf-8')
    def evidence(self):
        return {'candidate':str(self.cad),'sha256':pf.sha(self.cad),'result':'PASS',
                'proofs':[str(self.proof)],'requirements_revision':contract(self.md,self.flow)['revision'],
                'requirement_results':[{'id':i,'result':'PASS','evidence':[str(self.proof)]} for i in self.ids]}
    def test_source_is_original_and_revision_changes(self):
        c=contract(self.md,self.flow); self.assertIn('Original quotes',source_text(self.md,self.flow))
        self.md.write_text(self.md.read_text().replace('Original quotes','User correction'))
        self.assertNotEqual(c['revision'],contract(self.md,self.flow)['revision'])
    def test_missing_duplicate_fail_and_missing_proof_rejected(self):
        for rows in [[],[{'id':'a'},{'id':'a'}],
                     [{'id':i,'result':'FAIL','evidence':[str(self.proof)]} for i in self.ids],
                     [{'id':i,'result':'PASS','evidence':['does-not-exist']} for i in self.ids]]:
            e=self.evidence();e['requirement_results']=rows
            with self.assertRaises(ValueError):validate_results(self.flow['nodes'][0],'执行',e,self.flow)
    def test_review_wrong_candidate_rejected(self):
        self.flow['nodes'][0]['evidence']={'candidate':'other','sha256':'other'}
        with self.assertRaises(ValueError):validate_results(self.flow['nodes'][1],'校审',self.evidence(),self.flow)
    def test_complete_records_rows_not_user_acceptance(self):
        p=self.root/'evidence.json';p.write_text(json.dumps(self.evidence()))
        pf.complete(self.md,self.state,'edit','执行',p)
        f=pf.read_flow(self.md)[-1]
        self.assertEqual(f['nodes'][0]['evidence']['requirement_results'],self.evidence()['requirement_results'])
        self.assertEqual(f['active_batch']['user_confirmation'],'pending')
        self.assertEqual(pf.current(self.md)['next'][0]['id'],'review')
    def test_stale_revision_prevents_completion(self):
        e=self.evidence();e['requirements_revision']='old';p=self.root/'bad.json';p.write_text(json.dumps(e))
        with self.assertRaises(ValueError):pf.complete(self.md,self.state,'edit','执行',p)
        self.assertEqual(pf.read_flow(self.md)[-1]['nodes'][0]['state'],'pending')
    def test_packet_includes_original_entry(self):
        x=pf.packet(self.md,self.state,'工程待核','执行',{'issue':'fixture','node':'edit'})
        self.assertIn('共享MD需求与验收',x['prompt'])
        self.assertEqual(x['threadId'],'reviewer')
    def test_revised_submission_and_final_still_waits_for_user(self):
        p=self.root/'evidence.json';p.write_text(json.dumps(self.evidence()))
        pf.complete(self.md,self.state,'edit','执行',p)
        self.cad.write_bytes(b'revised-fixture')
        p.write_text(json.dumps(self.evidence()))
        pf.complete(self.md,self.state,'edit','执行',p)
        self.assertEqual(len(pf.read_flow(self.md)[-1]['nodes'][0]['previous_submissions']),1)
        e=self.evidence();e['review_thread']='reviewer';p.write_text(json.dumps(e))
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'reviewer'}):
            pf.complete(self.md,self.state,'review','校审',p)
        f=pf.read_flow(self.md)[-1]
        self.assertEqual(f['active_batch']['user_confirmation'],'pending')
        self.assertIn('待交用户确认',self.md.read_text())
        self.assertIn('Original quotes',source_text(self.md,f))


if __name__=='__main__':unittest.main()
