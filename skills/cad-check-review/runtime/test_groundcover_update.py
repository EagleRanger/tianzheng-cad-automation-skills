import copy,unittest,tempfile
from pathlib import Path
from cad_runtime.planning import build_job
from unittest.mock import patch
from cad_runtime.protocol import validate,MUTATING_KINDS,BRIDGE_KINDS
from cad_runtime.common import ClientError
from cad_runtime import bound_edits

class GroundcoverUpdateTests(unittest.TestCase):
    def params(self):
        return {'items':[{'handle':'A','layer':'plants','expected':{'up':'鸢尾 8m^U2^U','down':'','height':'5.0','scale':.35,'rotation':0,'grips':[[0,0,0],[4,0,0],[0,2,0],[1,1,0]]},'grips':[[0,0,0],[5,0,0],[0,2,0]]}]}
    def test_update_is_mutating_fixed_route(self):
        validate('groundcover_update',self.params());self.assertIn('groundcover_update',MUTATING_KINDS);self.assertIn('groundcover_update',BRIDGE_KINDS)
    def test_no_new_text_field_or_lost_fourth_grip(self):
        p=self.params();p['items'][0]['unknown_text']='changed'
        with self.assertRaisesRegex(ClientError,'GROUNDCOVER_UPDATE_FIELDS'):validate('groundcover_update',p)
        p=self.params();p['items'][0]['expected']['grips'].pop()
        with self.assertRaisesRegex(ClientError,'GROUNDCOVER_GRIPS'):validate('groundcover_update',p)
    def test_crossed_duplicate_or_acute_targets_not_accepted(self):
        p=self.params();p['items']*=2
        with self.assertRaisesRegex(ClientError,'DUPLICATE_UPDATE_TARGET'):validate('groundcover_update',p)
        p=self.params();p['items'][0]['grips'][2]=[1,2,0]
        with self.assertRaisesRegex(ClientError,'ORTHOGONAL_LEADER_REQUIRED'):validate('groundcover_update',p)
    def test_text_only_edits_need_no_new_geometry(self):
        p=self.params();t=p['items'][0];t.pop('grips');t['up_text']='new upper';t['down_text']='new lower';validate('groundcover_update',p)
        t.pop('up_text');validate('groundcover_update',p)
        t.pop('down_text')
        with self.assertRaisesRegex(ClientError,'UPDATE_ACTION_REQUIRED'):validate('groundcover_update',p)
    def test_text_only_uses_original_words_not_manual_geometry(self):
        p=self.params();t=p['items'][0];t.pop('grips');t['expected']={'up':'old','down':''};t['up_text']='new';validate('groundcover_update',p)
        t['grips']=[[0,0,0],[1,0,0],[0,1,0]]
        with self.assertRaisesRegex(ClientError,'GROUNDCOVER_EXPECTED_FIELDS'):validate('groundcover_update',p)
    def test_move_only_keeps_old_dll_job_contract(self):
        with tempfile.TemporaryDirectory() as d:
            snap={'can_submit':True,'issues':[],'saved_checkpoint':{'last_saved':str(Path(d)/'input.dwg'),'last_sha256':'x'}}
            job=build_job({'session_dir':d},'groundcover_update',self.params(),'compat',snap)
            self.assertNotIn('up_text',job['items'][0])
            self.assertNotIn('down_text',job['items'][0])
    def test_text_grip_is_rejected_not_mistaken_for_translation(self):
        p=self.params();r=p['items'][0];r.pop('grips');r['text_grip']=[2,1,0]
        with self.assertRaisesRegex(ClientError,'TEXT_GRIP_SUSPENDED_NATIVE_DISPLAY_LINKAGE'):validate('groundcover_update',p)
    def test_update_has_separate_validated_release(self):
        release={'status':'ISOLATED_NATIVE_VERIFIED','adapter_contract':'V736_NATIVE_EXTENSION_V1','kinds':['groundcover_update'],'dll':'a','sha256':'x','entry':'HLCADGROUNDCOVERUPDATEV2'}
        with patch.object(bound_edits,'read',return_value=release) as reader,patch.object(bound_edits,'digest',return_value='x'),patch.object(bound_edits,'require_entry'):
            bound_edits.verified_release({},'groundcover_update')
        self.assertEqual(reader.call_args.args[0].name,'NativeGroundcoverUpdateV1.release.json')
    def test_rotation_is_explicit_single_geometry_action(self):
        p=self.params();p['items'][0]['rotation']=-27
        validate('groundcover_update',p)
        with tempfile.TemporaryDirectory() as d:
            snap={'can_submit':True,'issues':[],'saved_checkpoint':{'last_saved':str(Path(d)/'input.dwg'),'last_sha256':'x'}}
            job=build_job({'session_dir':d},'groundcover_update',p,'rotation',snap)
            self.assertEqual(job['items'][0]['rotation'],-27)
        for key,value in [('rotation',361),('rotation',float('nan')),('scale',2),('up_text','changed')]:
            q=copy.deepcopy(p);q['items'][0][key]=value
            with self.assertRaisesRegex(ClientError,'ROTATION_SINGLE_GEOMETRY_ONLY'):validate('groundcover_update',q)
        p['items'][0].pop('grips')
        with self.assertRaisesRegex(ClientError,'ROTATION_SINGLE_GEOMETRY_ONLY'):validate('groundcover_update',p)
    def test_scale_only_requires_original_scale_and_reaches_native_job(self):
        p={'items':[{'handle':'A','layer':'plants','expected':{'up':'兰引三号','down':'','scale':.2},'scale':3.0}]}
        validate('groundcover_update',p)
        with tempfile.TemporaryDirectory() as d:
            snap={'can_submit':True,'issues':[],'saved_checkpoint':{'last_saved':str(Path(d)/'input.dwg'),'last_sha256':'x'}}
            job=build_job({'session_dir':d},'groundcover_update',p,'scale',snap)
            self.assertEqual(job['items'][0]['scale'],3.0)
        for value in (0,-1,True,float('inf'),float('nan'),None):
            q=copy.deepcopy(p);q['items'][0]['scale']=value
            with self.assertRaisesRegex(ClientError,'POSITIVE_SCALE_AND_EXPECTED_SCALE_REQUIRED'):validate('groundcover_update',q)
        del p['items'][0]['expected']['scale']
        with self.assertRaisesRegex(ClientError,'POSITIVE_SCALE_AND_EXPECTED_SCALE_REQUIRED'):validate('groundcover_update',p)

if __name__=='__main__':unittest.main()
