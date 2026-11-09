import json
import unittest
from unittest.mock import patch
from test_review_contract_20261108 import ReviewContractTest
from cad_runtime import project_flow as pf
from cad_runtime.scoped_waits import defer,resolve,checkpoint


class ScopedWaitTests(unittest.TestCase):
    setUp=ReviewContractTest.setUp
    tearDown=ReviewContractTest.tearDown
    write=ReviewContractTest.write
    evidence=ReviewContractTest.evidence

    def hold_b(self):
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'writer'}):
            return defer(self.md,self.state,'edit','执行',{'question':'B选哪种方案？','reason':'来源冲突',
                'evidence':'native question source','requirement_ids':['b']})
    def checkpoint_a(self):
        e=self.evidence();e['requirement_results']=e['requirement_results'][:1]
        p=self.root/'partial.json';p.write_text(json.dumps(e))
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'writer'}):
            return checkpoint(self.md,self.state,'edit','执行',p)
    def native(self):
        return {'polls':[{'cursor':'c1','thread':{'id':'writer','status':{'type':'idle'}},'latestTurn':{'status':'completed'}}]}
    def test_one_question_keeps_other_requirement_runnable(self):
        self.hold_b();n=pf.current(self.md)['next'][0]
        self.assertEqual(n['runnable_ids'],['a']);self.assertEqual(n['deferred_ids'],['b'])
        f=pf.finish_check(self.md,'执行')
        self.assertEqual(f['action'],'CONTINUE');self.assertFalse(f['allow_finish']);self.assertFalse(f['may_wait_for_user'])
        s=pf.supervise(self.md,self.state,self.native());self.assertEqual(s['action'],'RESUME_ONCE')
        self.assertEqual(s['runnable_ids'],['a'])
    def test_independent_progress_saved_then_only_remainder_waits(self):
        self.hold_b();self.assertEqual(self.checkpoint_a()['status'],'PROGRESS_RECORDED_NOT_COMPLETED')
        f=pf.finish_check(self.md,'执行')
        self.assertEqual(f['action'],'REVISIT_DEFERRED');self.assertFalse(f['allow_finish'])
        self.assertTrue(f['may_wait_for_user']);self.assertEqual(len(f['unresolved_questions']),1)
        self.assertEqual(pf.supervise(self.md,self.state,self.native())['action'],'REVISIT_DEFERRED')
        self.assertEqual(pf.read_flow(self.md)[-1]['nodes'][0]['state'],'pending')
    def test_answer_resumes_original_id_without_redoing_other_id(self):
        key=self.hold_b()['id'];self.checkpoint_a()
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'writer'}):
            resolve(self.md,self.state,key,'执行','采用方案1','actual native user answer')
        n=pf.current(self.md)['next'][0]
        self.assertEqual(n['runnable_ids'],['b']);self.assertEqual(n['completed_ids'],['a'])
        self.assertEqual(pf.finish_check(self.md,'执行')['action'],'CONTINUE')
        self.assertFalse(pf.finish_check(self.md,'执行')['allow_finish'])
    def test_unanswered_question_cannot_be_passed_or_completed(self):
        self.hold_b();p=self.root/'full.json';p.write_text(json.dumps(self.evidence()))
        with self.assertRaisesRegex(ValueError,'UNRESOLVED_QUESTION'):
            pf.complete(self.md,self.state,'edit','执行',p)
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'writer'}):
            with self.assertRaisesRegex(ValueError,'DEFERRED_ITEM'):
                checkpoint(self.md,self.state,'edit','执行',p)
    def test_unrelated_node_runs_but_dependent_review_stays_blocked(self):
        self.flow['nodes'].append({'id':'independent','title':'independent','owner':'执行','state':'pending','after':[]})
        self.write();self.hold_b();self.checkpoint_a()
        self.assertEqual([n['id'] for n in pf.current(self.md)['next']],['independent'])
        self.assertEqual(pf.finish_check(self.md,'执行')['action'],'CONTINUE')
    def test_scoped_external_hold_does_not_stop_other_node(self):
        self.flow['nodes'].append({'id':'independent','title':'independent','owner':'执行','state':'pending','after':[]})
        self.write()
        r=pf.supervise(self.md,self.state,self.native(),{'kind':'approval','node':'edit',
            'reason':'approval only for edit','evidence':'native approval'})
        self.assertEqual(r['node'],'independent');self.assertEqual(r['action'],'RESUME_ONCE')
    def test_transient_item_hold_keeps_same_node_other_ids(self):
        r=pf.supervise(self.md,self.state,self.native(),{'kind':'user_decision','node':'edit',
            'requirement_ids':['b'],'reason':'choice','evidence':'question'})
        self.assertEqual(r['runnable_ids'],['a'])
    def test_explicit_global_user_pause_still_stops(self):
        r=pf.supervise(self.md,self.state,self.native(),{'kind':'user_pause','reason':'user said stop all','evidence':'user turn'})
        self.assertEqual(r['action'],'HOLD');self.assertFalse(r['send'])
    def test_native_approval_attention_is_not_cleared(self):
        self.hold_b();native=self.native();native['polls'][0]['thread']['status']['activeFlags']=['waitingOnApproval']
        self.assertEqual(pf.supervise(self.md,self.state,native)['action'],'CHECK_NATIVE_ATTENTION')
    def test_duplicate_question_reuses_same_original_record(self):
        first=self.hold_b();second=self.hold_b()
        self.assertEqual(first['id'],second['id']);self.assertEqual(second['status'],'ALREADY_DEFERRED')
        self.assertEqual(len(pf.read_flow(self.md)[-1]['deferred_questions']),1)
    def test_original_requirement_change_reopens_partial_progress(self):
        self.hold_b();self.checkpoint_a()
        self.md.write_text(self.md.read_text(encoding='utf-8').replace('Original quotes','New instruction'),encoding='utf-8')
        self.assertEqual(pf.current(self.md)['next'][0]['runnable_ids'],['a'])
    def test_no_blank_answer_or_unknown_scope(self):
        key=self.hold_b()['id']
        with patch.dict(pf.os.environ,{'CODEX_THREAD_ID':'writer'}):
            with self.assertRaisesRegex(ValueError,'ACTUAL_ANSWER'):
                resolve(self.md,self.state,key,'执行','','no answer')
            with self.assertRaisesRegex(ValueError,'WAIT_IDS_INVALID'):
                defer(self.md,self.state,'edit','执行',{'question':'x','reason':'x','evidence':'x','requirement_ids':['absent']})


if __name__=='__main__':unittest.main()
