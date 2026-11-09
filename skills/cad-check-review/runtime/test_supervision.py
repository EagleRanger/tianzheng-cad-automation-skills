import json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from cad_runtime.project_flow import supervise

class SupervisionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.state=Path(self.tmp.name)/'state.json';self.md=Path(self.tmp.name)/'list.md'
        self.state.write_text(json.dumps({'CAD_review_20261027':{'supervision':{'destination_thread':'manager','execution_thread':'writer','review_thread':'reviewer'}}}))
        self.flow={'next':[{'id':'garden','owner':'执行','title':'修园建'}],'requirements':{'revision':'v1'}}
        self.native={'polls':[{'cursor':'c1','thread':{'id':'writer','status':{'type':'idle'}},'latestTurn':{'status':'completed'}}]}
        self.mock=patch('cad_runtime.project_flow.current',return_value=self.flow);self.mock.start();self.addCleanup(self.mock.stop)
    def test_idle_resumes_once_and_readonly_probe_does_not_consume_send(self):
        self.assertEqual(supervise(self.md,self.state,self.native)['action'],'RESUME_ONCE')
        self.assertEqual(supervise(self.md,self.state,self.native)['action'],'RESUME_ONCE')
        self.assertEqual(supervise(self.md,self.state,self.native,record_sent=True)['action'],'RESUME_SENT_RECORDED')
        self.assertEqual(supervise(self.md,self.state,self.native)['action'],'VERIFY_PICKUP')
    def test_active_does_not_wake(self):
        self.native['polls'][0]['thread']['status']['type']='active'
        self.assertEqual(supervise(self.md,self.state,self.native)['action'],'WAIT_NATIVE')
    def test_pause_and_external_need_evidence(self):
        for kind in ('user_pause','approval','external_dependency'):
            result=supervise(self.md,self.state,self.native,{'kind':kind,'reason':'真实条件','evidence':'native user turn'})
            self.assertEqual(result['action'],'HOLD' if kind=='user_pause' else 'CHECK_HOLD_SCOPE');self.assertFalse(result['send'])
        with self.assertRaises(ValueError):supervise(self.md,self.state,self.native,{'kind':'next_step','reason':'未完'})
    def test_reviewer_is_not_woken_before_its_node(self):
        self.native['polls'][0]['thread']['id']='reviewer'
        self.assertEqual(supervise(self.md,self.state,self.native)['action'],'READ_NATIVE_OWNER')
    def test_completed_nodes_do_not_resume(self):
        self.flow['next']=[]
        self.assertEqual(supervise(self.md,self.state,self.native)['action'],'RETURN_FOR_USER_REVIEW')
    def test_attention_and_unknown_state_do_not_resume(self):
        self.native['polls'][0]['thread']['status']={'type':'idle','activeFlags':['waitingOnApproval']}
        self.assertEqual(supervise(self.md,self.state,self.native)['action'],'CHECK_NATIVE_ATTENTION')

if __name__=='__main__':unittest.main()
