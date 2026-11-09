import unittest,json,tempfile
from pathlib import Path
from unittest.mock import patch
from cad_runtime.project_flow import START,END,finish_check
class FinishCheckTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.md=Path(self.tmp.name)/'todo.md'
  self.nodes=[dict(id='draw',owner='执行',title='draw',after=[],state='pending'),dict(id='review',owner='校审',title='review',after=['draw'],state='pending')]
 def write(self):self.md.write_text(START+json.dumps(dict(schema=1,nodes=self.nodes))+END,encoding='utf-8')
 def test_unfinished_continues_without_manager(self):
  self.write();r=finish_check(self.md,'执行');self.assertFalse(r['allow_finish']);self.assertEqual(r['action'],'CONTINUE');self.assertEqual(r['next'][0]['owner'],'执行')
 def test_review_is_direct_handoff_not_batch_finish(self):
  self.nodes[0]['state']='done';self.write();r=finish_check(self.md,'执行');self.assertFalse(r['allow_finish']);self.assertEqual(r['action'],'DIRECT_HANDOFF');self.assertEqual(r['next'][0]['owner'],'校审');self.assertEqual(finish_check(self.md,'校审')['action'],'CONTINUE')
 def test_all_done_requires_user_review_not_automatic_acceptance(self):
  for n in self.nodes:n['state']='done'
  self.write();self.assertTrue(finish_check(self.md,'校审')['allow_finish']);self.assertEqual(finish_check(self.md,'校审')['action'],'READY_FOR_USER_REVIEW')
 def test_old_revision_cannot_finish(self):
  for n in self.nodes:n.update(state='done',requirement_ids=['A'],evidence={'requirements_revision':'old'})
  self.write()
  with patch('cad_runtime.project_flow.contract',return_value={'revision':'new'}):
   r=finish_check(self.md,'执行');self.assertFalse(r['allow_finish']);self.assertEqual(len(r['remaining']),2)
 def test_missing_evidence_cannot_finish(self):
  for n in self.nodes:n.update(state='done',requirement_ids=['A'],evidence={'requirements_revision':'new','requirement_results':[]})
  self.write()
  with patch('cad_runtime.project_flow.contract',return_value={'revision':'new'}):self.assertFalse(finish_check(self.md,'执行')['allow_finish'])
if __name__=='__main__':unittest.main()
