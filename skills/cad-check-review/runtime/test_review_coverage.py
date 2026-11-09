import json, os, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
from cad_runtime.project_flow import START, END, read_flow, current, reopen, finish_check
from cad_runtime.review_contract import contract, validate_results


class ReviewCoverageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.md = self.root/'tasks.md'
        self.proof = self.root/'proof.json'
        self.proof.write_text('{}')
        self.state = self.root/'state.json'
        self.state.write_text(json.dumps({'CAD_review_20261027':{'supervision':{
            'destination_thread':'manager','execution_thread':'writer','review_thread':'reviewer'}}}))
        self.source = '## batch\n### R01｜name\n原话保留\n- [ ] 文字末端对齐\n- 执行结果：待核\n### R02｜layout\n- [ ] 纸空间清理\n- 执行结果：待核\n## end\n'
        self.flow = {'schema':1,'scope':'test','active_batch':{'id':'test',
            'start_marker':'## batch','end_marker':'## end','heading_pattern':r'^### (R\d+)｜[^\n]*',
            'review_policy':{'scope_and_layout_required':True}},'nodes':[
            {'id':'work','owner':'执行','title':'work','after':[],'state':'pending','requirement_ids':['R01']},
            {'id':'review','owner':'校审','title':'review','after':['work'],'state':'pending','requirement_ids':['R01']},
            {'id':'layout','owner':'执行','title':'layout','after':[],'state':'pending','requirement_ids':['R02']}]}
        self.write()

    def write(self):
        self.md.write_text('当前返修：执行\n'+self.source+START+json.dumps(self.flow)+END,encoding='utf-8')

    def evidence(self):
        return {'candidate':'saved.dwg','sha256':'same','review_context':{'spaces':['Model','Paper'],'views':['layout/viewport-A']},
                'requirement_results':[{'id':'R01','result':'PASS','scope':'all tree labels on layout-A',
                'evidence':[str(self.proof)],'observed':{'R01.1':'name ends aligned with the native terminal'}}]}

    def test_new_unbound_original_cannot_report_done(self):
        self.source=self.source.replace('## end','### R03｜new\n- [ ] missing\n## end');self.write()
        with self.assertRaisesRegex(ValueError,'UNBOUND_HUMAN_REQUIREMENTS'):current(self.md)

    def test_results_do_not_invalidate_requirements(self):
        flow=read_flow(self.md)[-1];before=contract(self.md,flow,flow['nodes'][0])['revision']
        self.source=self.source.replace('执行结果：待核','执行结果：已保存 proof');self.write()
        self.assertEqual(before,contract(self.md,flow,flow['nodes'][0])['revision'])

    def test_unrelated_change_does_not_invalidate_other_scope(self):
        flow=read_flow(self.md)[-1];before=contract(self.md,flow,flow['nodes'][0])['revision']
        self.source=self.source.replace('纸空间清理','纸空间清理并整理图框');self.write()
        self.assertEqual(before,contract(self.md,flow,flow['nodes'][0])['revision'])

    def test_model_only_cannot_pass(self):
        f=read_flow(self.md)[-1];e=self.evidence();e['review_context']['spaces']=['Model']
        with self.assertRaisesRegex(ValueError,'MODEL_PAPER_VIEW'):validate_results(f['nodes'][0],'执行',e,f)

    def test_no_actual_scope_or_observation_cannot_pass(self):
        f=read_flow(self.md)[-1];e=self.evidence();e['requirement_results'][0].pop('scope')
        with self.assertRaisesRegex(ValueError,'ACTUAL_REQUIREMENT_SCOPE'):validate_results(f['nodes'][0],'执行',e,f)
        e=self.evidence();e['requirement_results'][0]['observed']={}
        with self.assertRaisesRegex(ValueError,'OBSERVATION_REQUIRED'):validate_results(f['nodes'][0],'执行',e,f)

    def test_current_evidence_is_accepted(self):
        f=read_flow(self.md)[-1];validate_results(f['nodes'][0],'执行',self.evidence(),f)

    def test_review_must_match_exact_submission(self):
        f=read_flow(self.md)[-1];f['nodes'][0]['evidence']={'candidate':'another.dwg','sha256':'old'}
        with self.assertRaisesRegex(ValueError,'REVIEW_MUST_MATCH'):validate_results(f['nodes'][1],'校审',self.evidence(),f)

    def test_reopen_preserves_evidence_and_reopens_dependents(self):
        for n in self.flow['nodes'][:2]:n.update(state='done',evidence={'candidate':'saved.dwg','sha256':'same'})
        self.write()
        with patch.dict(os.environ,{'CODEX_THREAD_ID':'reviewer'}):
            r=reopen(self.md,self.state,'work','校审','layout label failed')
        self.assertEqual(r['nodes'],['review','work'])
        f=read_flow(self.md)[-1]
        self.assertEqual(f['nodes'][0]['previous_submissions'][0]['sha256'],'same')
        self.assertFalse(finish_check(self.md,'执行')['allow_finish'])


if __name__=='__main__':unittest.main()
