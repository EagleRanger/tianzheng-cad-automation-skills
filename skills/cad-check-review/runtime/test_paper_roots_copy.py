import copy
import unittest
import tempfile, os
from pathlib import Path
from unittest.mock import patch
from cad_runtime import bound_edits
from cad_runtime import planning
from cad_runtime.protocol import validate, MUTATING_KINDS, BRIDGE_KINDS, SUCCESS

class PaperRootsCopyTests(unittest.TestCase):
    def leaders(self):
        return {'source':'source.dwg','source_layout':'布局1','target_layout':'布局2',
                'source_targets':[{'handle':'4119D','type':'TDbSymbMultiLeader','layer':'DIM_LEAD'}],
                'offset':[719.6879446795047,2921.702547190511]}
    def test_native_leader_copy_is_separate_mutation(self):
        validate('paper_leaders_copy',self.leaders())
        self.assertIn('paper_leaders_copy',MUTATING_KINDS)
        self.assertIn('paper_leaders_copy',BRIDGE_KINDS)
    def test_leaders_do_not_admit_viewports_or_extra_transform(self):
        for t in ('AcDbViewport','AcDbBlockReference','TDbText','TDbSymbDrawingIndex'):
            p=self.leaders();p['source_targets'][0]['type']=t
            with self.assertRaises(ValueError):validate('paper_leaders_copy',p)
        for key in ('frozen_layer_pairs','rotation','scale','erase_targets'):
            p=self.leaders();p[key]=[]
            with self.assertRaises(ValueError):validate('paper_leaders_copy',p)
    def test_leader_offset_finite_xy_and_source_identity(self):
        for v in ([0],[0,0,0],[True,0],[float('inf'),0],None):
            p=self.leaders();p['offset']=v
            with self.assertRaises(ValueError):validate('paper_leaders_copy',p)
        p=self.leaders();p['source_targets']*=2
        with self.assertRaises(ValueError):validate('paper_leaders_copy',p)
    def test_leader_release_does_not_reopen_broad_hold(self):
        release={'status':'ISOLATED_NATIVE_VERIFIED','kinds':['paper_leaders_copy'],'adapter_contract':'V736_NATIVE_EXTENSION_V1','dll':'test.dll','sha256':'x','entry':'HLCADPAPERLEADERSCOPYV1'}
        with patch.object(bound_edits,'read',return_value=release) as rd,patch.object(bound_edits,'digest',return_value='x'),patch.object(bound_edits,'require_entry'):
            bound_edits.verified_release({},'paper_leaders_copy')
            self.assertEqual(rd.call_args.args[0].name,'NativePaperLeadersCopyV1.release.json')
        with patch.object(bound_edits,'read',return_value={'status':'HOLD_PRODUCTION_DISPLAY_FEEDBACK'}):
            with self.assertRaises(ValueError):bound_edits.verified_release({},'paper_roots_copy')
    def test_leader_job_binds_registered_source_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            p=self.leaders();p['source']=str(Path(folder)/'reference.dwg')
            snap={'can_submit':True,'issues':[],'saved_checkpoint':{'last_saved':str(Path(folder)/'input.dwg'),'last_sha256':'a'*64}}
            binding={'session_dir':folder}
            with patch.object(planning,'approved_sources',return_value={os.path.normcase(p['source']):'b'*64}):
                job=planning.build_job(binding,'paper_leaders_copy',p,'leader_job',snap)
                self.assertEqual(job['source_sha256'],'b'*64)
                self.assertEqual(job['input_sha256'],'a'*64)
            with patch.object(planning,'approved_sources',return_value={}):
                with self.assertRaises(ValueError):planning.build_job(binding,'paper_leaders_copy',p,'leader_job',snap)
    def setUp(self):
        self.p={'source':'source.dwg','source_layout':'布局1','target_layout':'布局1','source_targets':[{'handle':'AB','type':'AcDbViewport','layer':'0'},{'handle':'AC','type':'AcDbPolyline','layer':'0'}]}
    def test_explicit_roots_original_coordinates(self):
        validate('paper_roots_copy',self.p)
        self.assertIn('paper_roots_copy',MUTATING_KINDS)
        self.assertIn('paper_roots_copy',BRIDGE_KINDS)
        self.assertEqual(SUCCESS['paper_roots_copy'],'SAVED_STILL_OPEN')
    def test_no_implicit_transform_or_selection(self):
        for k in ('offset','scale','bounds','target_frames','erase_targets'):
            p=copy.deepcopy(self.p);p[k]=[0,0]
            with self.assertRaises(ValueError):validate('paper_roots_copy',p)
    def test_no_model_space(self):
        for k in ('source_layout','target_layout'):
            p=copy.deepcopy(self.p);p[k]='Model'
            with self.assertRaises(ValueError):validate('paper_roots_copy',p)
    def test_no_empty_or_duplicate_roots(self):
        for roots in ([],[self.p['source_targets'][0]]*2):
            p=copy.deepcopy(self.p);p['source_targets']=roots
            with self.assertRaises(ValueError):validate('paper_roots_copy',p)
    def test_reject_unsupported_proxy(self):
        self.p['source_targets'][0]['type']='AcDbProxyEntity'
        with self.assertRaises(ValueError):validate('paper_roots_copy',self.p)

    def test_explicit_frozen_aliases(self):
        self.p['frozen_layer_pairs']=[{'source':'DIM_ELEV','target':'$0$DIM_ELEV'},{'source':'PUB_TEXT','target':'$1$PUB_TEXT'}]
        validate('paper_roots_copy',self.p)
    def test_reject_ambiguous_frozen_source(self):
        self.p['frozen_layer_pairs']=[{'source':'DIM_ELEV','target':'$0$DIM_ELEV'},{'source':'dim_elev','target':'0'}]
        with self.assertRaises(ValueError):validate('paper_roots_copy',self.p)
    def test_native_sheet_types(self):
        for kind in ['AcDbHatch','TDbDrawingName','TDbSymbDrawingIndex','TDbSymbNorthThumb','TDbSymbArrow']:
            self.p['source_targets'][0]['type']=kind
            validate('paper_roots_copy',self.p)

if __name__=='__main__':unittest.main()
