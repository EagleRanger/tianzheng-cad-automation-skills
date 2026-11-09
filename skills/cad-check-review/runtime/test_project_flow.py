import unittest,tempfile,json,os
from unittest.mock import patch
from pathlib import Path
from cad_runtime.project_flow import START,END,current,route,packet,guard,validate_evidence,sha,complete

class FlowTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
  self.nodes=[{'id':k,'owner':r,'title':k,'after':a,'state':'pending'} for k,r,a in
   [('base_replace','执行',[]),('base_check','执行',['base_replace']),('base_review','校审',['base_check']),('planting','执行',['base_review'])]]
  self.flow={'schema':1,'scope':'whole base first','nodes':self.nodes};self.md=self.root/'md';self.write()
  self.state=self.root/'state';self.state.write_text(json.dumps({'CAD_review_20261027':{'supervision':{'destination_thread':'manager','execution_thread':'writer','review_thread':'reviewer'}}}),encoding='utf-8')
 def write(self):self.md.write_text(START+json.dumps(self.flow)+END,encoding='utf-8')
 def test_base_is_first(self):self.assertEqual([x['id'] for x in current(self.md)['next']],['base_replace'])
 def test_drafting_hatch_blocked_but_base_reads_allowed(self):
  with self.assertRaises(ValueError):guard(self.md,'hatch')
  guard(self.md,'inspect');guard(self.md,'base_replace')
 def test_readback_survives_missing_flow_marker(self):
  self.md.write_text('no flow marker')
  guard(self.md,'inspect');guard(self.md,'page_map');guard(self.md,'switch')
  with self.assertRaises(ValueError):guard(self.md,'hatch')
 def test_windows_bom_crlf_is_readable(self):
  self.md.write_bytes(('\ufeff'+START+json.dumps(self.flow)+END).replace('\n','\r\n').encode('utf-8'))
  self.assertEqual(current(self.md)['next'][0]['id'],'base_replace')
 def test_repeated_cr_is_readable_without_mutating_user_text(self):
  raw=('原话与数值 5.0\n'+START+json.dumps(self.flow)+END).replace('\n','\r\r\r\n').encode('utf-8')
  self.md.write_bytes(raw)
  self.assertEqual(current(self.md)['next'][0]['id'],'base_replace')
  self.assertEqual(self.md.read_bytes(),raw)
 def test_partial_repair_not_complete_whole_base(self):
  dwg=self.root/'fake.dwg';dwg.write_bytes(b'fixture');r=self.root/'receipt';r.write_text(json.dumps({'status':'SAVED_STILL_OPEN','sha256':sha(dwg),'changes':{'erased':1032}}))
  with self.assertRaisesRegex(ValueError,'WHOLE_BASE_RECEIPT'):
   validate_evidence(self.nodes[0],'执行',{'candidate':str(dwg),'sha256':sha(dwg),'receipt':str(r)},self.flow)
 def cumulative_fixture(self):
  base=self.root/'base.dwg';base.write_bytes(b'primary base');final=self.root/'final.dwg';final.write_bytes(b'final display fix')
  proof=self.root/'role-proof.json';proof.write_text('{}')
  primary=self.root/'primary.receipt.json';primary.write_text(json.dumps({'status':'SAVED_STILL_OPEN','output':str(base),'sha256':sha(base),'changes':{'operation':'base_replace','protected_verified':True,'classification_complete':True,'coverage_complete':False,'reopen_verified':True,'entity_map':[{'source':'1','target':'2'}],'deferred_targets':[{'handle':'A'},{'handle':'B'}]}}))
  role=self.root/'coverage.json';role.write_text(json.dumps({'primary_sha256':sha(base),'current_saved_scope_sha256':sha(base),'objects':[{'handle':h,'decision':'reviewed retained planting','evidence':proof.name} for h in ['A','B']],'missing_objects':[],'duplicate_membership':[]}))
  receipt=self.root/'final.receipt.json';receipt.write_text(json.dumps({'status':'SAVED_STILL_OPEN','output':str(final),'sha256':sha(final),'changes':{'native_save_reopen_verified':True,'operation_changes':{'geometry_unchanged':True,'definition_instances_and_other_children_unchanged':True}}}))
  job=self.root/'final.job.json';job.write_text(json.dumps({'input_sha256':sha(base),'output':str(final)}))
  return {'candidate':str(final),'sha256':sha(final),'receipt':str(primary),'coverage_review':str(role),'final_receipt':str(receipt),'final_job':str(job)}
 def test_cumulative_base_uses_real_dispositions_without_rewriting_partial_receipt(self):
  e=self.cumulative_fixture();old=Path(e['receipt']).read_bytes()
  validate_evidence(self.nodes[0],'执行',e,self.flow)
  self.assertEqual(old,Path(e['receipt']).read_bytes());self.assertEqual(current(self.md)['next'][0]['id'],'base_replace')
 def test_cumulative_base_rejects_missing_or_duplicate_deferred_roles(self):
  for handles in [['A'],['A','A','B']]:
   e=self.cumulative_fixture();p=Path(e['coverage_review']);v=json.loads(p.read_text());v['objects']=[{'handle':h,'decision':'x','evidence':'role-proof.json'} for h in handles];p.write_text(json.dumps(v))
   with self.assertRaisesRegex(ValueError,'DEFERRED_ROLE_COVERAGE'):validate_evidence(self.nodes[0],'执行',e,self.flow)
 def test_cumulative_base_rejects_unrelated_final_version(self):
  e=self.cumulative_fixture();p=Path(e['final_job']);v=json.loads(p.read_text());v['input_sha256']='unrelated';p.write_text(json.dumps(v))
  with self.assertRaisesRegex(ValueError,'COVERAGE_FINAL_VERSION_NOT_LINKED'):validate_evidence(self.nodes[0],'执行',e,self.flow)
 def test_cumulative_base_requires_new_role_review_after_geometry_change(self):
  e=self.cumulative_fixture();p=Path(e['final_receipt']);v=json.loads(p.read_text());v['changes']['operation_changes']['geometry_unchanged']=False;p.write_text(json.dumps(v))
  with self.assertRaisesRegex(ValueError,'COVERAGE_FINAL_VERSION_NOT_LINKED'):validate_evidence(self.nodes[0],'执行',e,self.flow)
 def test_cumulative_base_rejects_final_without_native_reopen(self):
  e=self.cumulative_fixture();p=Path(e['final_receipt']);v=json.loads(p.read_text());v['changes']['native_save_reopen_verified']=False;p.write_text(json.dumps(v))
  with self.assertRaisesRegex(ValueError,'FINAL_NATIVE_REOPEN_REQUIRED'):validate_evidence(self.nodes[0],'执行',e,self.flow)
 def test_cumulative_role_proofs_can_reference_explicit_prior_session_paths(self):
  e=self.cumulative_fixture();old=self.root/'role-proof.json';archive=self.root/'prior';archive.mkdir();dest=archive/old.name;old.rename(dest)
  with self.assertRaisesRegex(ValueError,'DEFERRED_ROLE_PROOF_MISSING'):validate_evidence(self.nodes[0],'执行',e,self.flow)
  e['proof_paths']={dest.name:str(dest)};validate_evidence(self.nodes[0],'执行',e,self.flow)
 def test_saved_subject_base_with_deferred_area_cannot_close_whole_node(self):
  dwg=self.root/'partial.dwg';dwg.write_bytes(b'partial');r=self.root/'receipt'
  r.write_text(json.dumps({'status':'SAVED_STILL_OPEN','sha256':sha(dwg),'changes':{'operation':'base_replace','protected_verified':True,'classification_complete':True,'coverage_complete':False,'entity_map':[{'source':'A','target':'B'}],'reopen_verified':True}}))
  with self.assertRaisesRegex(ValueError,'WHOLE_BASE_RECEIPT'):
   validate_evidence(self.nodes[0],'执行',{'candidate':str(dwg),'sha256':sha(dwg),'receipt':str(r)},self.flow)
 def test_reviewer_can_receive_early_engineering_query(self):
  p=packet(self.md,self.state,'工程待核','执行',{'issue':'preserve planting?','evidence':['receipt']})
  self.assertEqual(p['threadId'],'reviewer');self.assertFalse(p['copy_to_management'])
 def test_review_return_goes_writer(self):self.assertEqual(route('返修差异','校审',self.state)['threadId'],'writer')
 def test_module_fault_goes_manager(self):self.assertEqual(route('程序故障','执行',self.state)['threadId'],'manager')
 def test_missing_interface_does_not_require_invented_error_and_repro(self):
  p=packet(self.md,self.state,'程序故障','执行',{'issue':'No exact viewport reader','manager_request':'Provide the missing native viewport reader'})
  self.assertEqual(p['threadId'],'manager')
 def test_both_drafting_roles_report_fault_and_validate_repair(self):
  for sender in ['执行','校审']:
   p=packet(self.md,self.state,'程序故障',sender,{'issue':'Missing native fields','manager_request':'Add the missing native field read'})
   self.assertEqual(p['threadId'],'manager');self.assertIn('同一接口问题仍存在才续报',json.loads(p['prompt'])['分工'])
 def test_ordinary_module_feedback_has_no_send_target(self):
  for sender in ['执行','校审']:
   p=packet(self.md,self.state,'模块反馈',sender,{'issue':'Actual use checked','module':'text_patch','result':'PASS','evidence':['existing_receipt.json']})
   self.assertEqual(p['effect'],'record_in_existing_evidence_only');self.assertFalse(p['send'])
   self.assertIsNone(p['tool']);self.assertNotIn('threadId',p);self.assertNotIn('prompt',p)
   self.assertFalse(p['copy_to_management'])
 def test_delivered_modules_are_validated_by_both_consumers(self):
  for event,recipient in [('接口交付执行','writer'),('接口交付校审','reviewer')]:
   p=packet(self.md,self.state,event,'管理',{'issue':'Ready module entry'})
   self.assertEqual(p['threadId'],recipient);self.assertIn('验证模块效果并反馈问题',json.loads(p['prompt'])['分工'])
   self.assertIn('manager_self_check',p);self.assertNotIn('manager_self_check',json.loads(p['prompt']))
 def test_progress_disguised_as_fault_has_no_management_recipient(self):
  for issue in ('Saved a new hash', 'Source handles and target offsets prepared', 'Native operation passed'):
   p=packet(self.md,self.state,'程序故障','执行',{'issue':issue})
   self.assertFalse(p['send']);self.assertNotIn('threadId',p);self.assertNotIn('prompt',p)
 def test_module_feedback_cannot_reroute_engineering_review(self):
  with self.assertRaisesRegex(ValueError,'ENGINEERING_REVIEW_IS_NOT'):
   packet(self.md,self.state,'模块反馈','校审',{'issue':'Needs drawing review','scope':'judge engineering sources'})
 def test_real_user_question_does_not_require_invented_alternatives(self):
  p=packet(self.md,self.state,'用户取舍','校审',{'issue':'Missing design selection','question':'Which retained design is authoritative?','why_user_required':'The source supplies no author decision'})
  self.assertEqual(p['threadId'],'manager')
 def test_ordinary_engineering_query_needs_no_fabricated_evidence(self):
  self.assertEqual(packet(self.md,self.state,'工程待核','执行',{'issue':'Interpret the retained exception in the original list'})['threadId'],'reviewer')
 def test_program_ticket_contains_no_review_context(self):
  p=packet(self.md,self.state,'程序故障','校审',{'issue':'missing exact loop reader','manager_request':'Repair read_curves output','evidence':['error.json'],'operation':'read_curves','expected':'native curve fields','error_code':'CAPABILITY_NOT_AVAILABLE','repro_file':'inputs.json'})
  b=json.loads(p['prompt']);self.assertNotIn('当前节点',b);self.assertNotIn('原清单',b)
 def test_review_body_cannot_be_attached_to_program_ticket(self):
  with self.assertRaisesRegex(ValueError,'ENGINEERING_REVIEW_IS_NOT'):
   packet(self.md,self.state,'程序故障','校审',{'issue':'x','evidence':['x'],'operation':'x','expected':'x','error_code':'missing','repro_file':'x','scope':'judge the complete planting boundary'})
 def test_user_decision_requires_real_question_and_choices(self):
  with self.assertRaisesRegex(ValueError,'REAL_USER_DESIGN_DECISION_REQUIRED'):packet(self.md,self.state,'用户取舍','执行',{'issue':'review incomplete','evidence':['x']})
  p=packet(self.md,self.state,'用户取舍','校审',{'issue':'conflicting design sources','evidence':['image.png'],'question':'Which design applies?','why_user_required':'Both alternatives authorized; latest choice unknown','options':['A','B']})
  self.assertEqual(p['threadId'],'manager')
 def test_technical_delivery_returns_to_correct_consumer(self):
  self.assertEqual(route('接口交付校审','管理',self.state)['threadId'],'reviewer')
  self.assertEqual(route('接口交付执行','管理',self.state)['threadId'],'writer')
 def test_cannot_inject_recipient(self):
  with self.assertRaises(ValueError):packet(self.md,self.state,'工程待核','执行',{'issue':'x','evidence':['x'],'threadId':'manager'})
 def test_cannot_pass_base_review_before_check(self):
  with self.assertRaisesRegex(ValueError,'BASE_SELF_CHECK_REQUIRED'):packet(self.md,self.state,'图面送审','执行',{'issue':'x','evidence':['x'],'candidate':'x','sha256':'x','scope':'whole','node':'base_review'})
 def test_other_sender_cannot_be_reviewer(self):
  with self.assertRaises(ValueError):route('返修差异','执行',self.state)
 def native_review_fixture(self):
  dwg=self.root/'review.dwg';dwg.write_bytes(b'reviewed current drawing')
  for n in self.nodes[:2]:n.update(state='done',evidence={'sha256':sha(dwg)})
  self.md.write_text('<!-- 接续摘要：开始 -->\n当前返修：校审\n已完成：底板未完成\n<!-- 接续摘要：结束 -->\n'+START+json.dumps(self.flow)+END,encoding='utf-8')
  report=self.root/'review.json';report.write_text(json.dumps({'candidate':str(dwg),'sha256':sha(dwg),'result':'PASS','proofs':[str(dwg)]}),encoding='utf-8')
  return report
 def test_native_reviewer_identity_needs_no_duplicate_fields_in_engineering_report(self):
  report=self.native_review_fixture();before=report.read_bytes()
  with patch.dict(os.environ,{'CODEX_THREAD_ID':'reviewer','CODEX_TURN_ID':''}):
   result=complete(self.md,self.state,'base_review','校审',report)
  self.assertEqual(result['next'][0]['id'],'planting');self.assertEqual(report.read_bytes(),before)
  self.assertIn('整体替换、逐幅自检与独立校审已通过',self.md.read_text(encoding='utf-8'))
  node=next(n for n in current(self.md)['nodes'] if n['id']=='base_review')
  self.assertEqual(node['evidence']['review_thread'],'reviewer');self.assertNotIn('review_turn',node['evidence'])
 def test_manager_cannot_complete_engineering_review_even_with_declared_reviewer(self):
  report=self.native_review_fixture();v=json.loads(report.read_text());v['review_thread']='reviewer';report.write_text(json.dumps(v));before=self.md.read_bytes()
  with patch.dict(os.environ,{'CODEX_THREAD_ID':'manager'}):
   with self.assertRaisesRegex(ValueError,'REVIEW_CALLER_MISMATCH'):complete(self.md,self.state,'base_review','校审',report)
  self.assertEqual(self.md.read_bytes(),before)
 def test_explicit_stale_reviewer_is_not_silently_replaced(self):
  report=self.native_review_fixture();v=json.loads(report.read_text());v['review_thread']='retired-reviewer';report.write_text(json.dumps(v))
  with patch.dict(os.environ,{'CODEX_THREAD_ID':'reviewer'}):
   with self.assertRaisesRegex(ValueError,'REVIEW_THREAD_MISMATCH'):complete(self.md,self.state,'base_review','校审',report)
 def test_missing_runtime_and_declared_identity_is_reported_as_missing(self):
  report=self.native_review_fixture()
  with patch.dict(os.environ,{'CODEX_THREAD_ID':''}):
   with self.assertRaisesRegex(ValueError,'REVIEW_IDENTITY_MISSING'):complete(self.md,self.state,'base_review','校审',report)
 def test_dependency_unblocks_only_after_review(self):
  for node in self.nodes[:2]:node['state']='done'
  self.write();self.assertEqual(current(self.md)['next'][0]['id'],'base_review')
  with self.assertRaises(ValueError):guard(self.md,'hatch')
  self.nodes[2]['state']='done';self.write();guard(self.md,'hatch');self.assertEqual(current(self.md)['next'][0]['id'],'planting')

if __name__=='__main__':unittest.main()
