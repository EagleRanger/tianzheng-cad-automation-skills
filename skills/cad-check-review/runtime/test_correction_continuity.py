"""No CAD: reproduce omissions and stale next/finish disagreement."""
import json
from unittest.mock import patch
from test_review_contract_20261108 import ReviewContractTest
from cad_runtime import project_flow as pf


class CorrectionContinuityTest(ReviewContractTest):
    def add_correction(self):
        marker='<!-- CAD_CORRECTION '+json.dumps({
            'id':'correction','nodes':['edit','review'],
            'checks':['retain_mesh','spacing_2_to_3']})+' -->\n'
        self.md.write_text(self.md.read_text(encoding='utf-8').replace(
            'Original quotes',marker+'Original quotes'),encoding='utf-8')

    def test_new_correction_automatically_requires_result(self):
        self.add_correction()
        f=pf.read_flow(self.md)[-1]
        self.assertIn('correction',pf.current(self.md)['requirements']['required_ids'])
        with self.assertRaisesRegex(ValueError,'COVERAGE_MISMATCH'):
            pf.validate_results(f['nodes'][0],'执行',self.evidence(),f)

    def test_blank_pass_does_not_cover_protected_effect(self):
        self.add_correction();f=pf.read_flow(self.md)[-1];e=self.evidence()
        row={'id':'correction','result':'PASS','evidence':[str(self.proof)]}
        e['requirement_results'].append(row)
        with self.assertRaisesRegex(ValueError,'OBSERVATION_REQUIRED'):
            pf.validate_results(f['nodes'][0],'执行',e,f)
        row['observed']={'retain_mesh':'Mesh remains visible',
                         'spacing_2_to_3':'Original spacing 1, final 2.5'}
        pf.validate_results(f['nodes'][0],'执行',e,f)

    def test_old_done_reopens_next_and_finish_consistently(self):
        p=self.root/'e.json';p.write_text(json.dumps(self.evidence()))
        pf.complete(self.md,self.state,'edit','执行',p)
        self.add_correction()
        self.assertEqual(pf.current(self.md)['next'][0]['id'],'edit')
        self.assertEqual(pf.finish_check(self.md,'执行')['next'][0]['id'],'edit')
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'reviewer'}):
            with self.assertRaisesRegex(ValueError,'PREDECESSOR_NOT_DONE_OR_STALE'):
                pf.complete(self.md,self.state,'review','校审',p)

    def test_stale_completed_review_can_be_replaced_preserving_history(self):
        p=self.root/'e.json';p.write_text(json.dumps(self.evidence()))
        pf.complete(self.md,self.state,'edit','执行',p)
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'reviewer'}):
            pf.complete(self.md,self.state,'review','校审',p)
        self.add_correction();e=self.evidence()
        e['requirement_results'].append({'id':'correction','result':'PASS',
            'evidence':[str(self.proof)],'observed':{
                'retain_mesh':'Retained','spacing_2_to_3':'2.5 times'}})
        p.write_text(json.dumps(e));pf.complete(self.md,self.state,'edit','执行',p)
        self.assertEqual(pf.current(self.md)['next'][0]['id'],'review')
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'reviewer'}):
            pf.complete(self.md,self.state,'review','校审',p)
        self.assertTrue(pf.finish_check(self.md,'校审')['allow_finish'])
        self.assertEqual(len(pf.read_flow(self.md)[-1]['nodes'][1]['previous_submissions']),1)
