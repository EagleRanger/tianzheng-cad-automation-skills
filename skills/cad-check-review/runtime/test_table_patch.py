import copy,json,unittest
from unittest.mock import patch
from pathlib import Path
from cad_runtime.protocol import validate,MUTATING_KINDS,BRIDGE_KINDS
from cad_runtime import bound_edits
from cad_runtime.common import ClientError

class TablePatchTests(unittest.TestCase):
    def outline_params(self):
        return {'tables':[{'handle':'37E86','layer':'plants','row_count':16,'column_count':9,
            'legend_hatches':[{'block':'37EB4','handle':'37EB7','outline':True}]}]}
    def test_outline_is_separate_and_cannot_change_hatch_or_cells(self):
        validate('table_patch',self.outline_params())
        for field,value in [('rectangle',[-1,-1,1,1]),('pattern_scale',2),('reload_pattern',True),('outline',False)]:
            p=self.outline_params();p['tables'][0]['legend_hatches'][0][field]=value
            with self.assertRaises(ClientError):validate('table_patch',p)
        p=self.outline_params();p['tables'][0]['cells']=[{'row':2,'column':2,'before':'x','after':'y'}]
        with self.assertRaisesRegex(ClientError,'OUTLINE_BATCH_SEPARATE_REQUIRED'):validate('table_patch',p)
        p=self.outline_params();p['tables']+=self.params()['tables']
        with self.assertRaisesRegex(ClientError,'OUTLINE_BATCH_SEPARATE_REQUIRED'):validate('table_patch',p)
    def delete_params(self):
        return {'tables':[{'handle':'37E86','layer':'plants','row_count':18,'column_count':3,
            'delete_rows':{'rows':[{'row':2,'before':['1','','plant'],'block_ids':[None,'ABC',None]},
                                   {'row':3,'before':['2','','plant2'],'block_ids':[None,'DEF',None]}],'renumber':True}}]}
    def test_middle_rows_and_noncontiguous_indices_are_original_and_explicit(self):
        p=self.delete_params();validate('table_patch',p)
        p['tables'][0]['delete_rows']['rows'][1]['row']=7;validate('table_patch',p)
        p['tables'][0]['delete_rows']['renumber']=False;validate('table_patch',p)
    def test_header_duplicate_out_of_range_and_bool_row_rejected(self):
        for n in (0,1,2,18,True):
            p=self.delete_params();p['tables'][0]['delete_rows']['rows'][1]['row']=n
            with self.assertRaisesRegex(ClientError,'UNIQUE_ORIGINAL_DATA_ROWS_REQUIRED'):validate('table_patch',p)
    def test_delete_needs_complete_old_cells_and_legend_ids(self):
        for key in ('before','block_ids'):
            p=self.delete_params();p['tables'][0]['delete_rows']['rows'][0][key].pop()
            with self.assertRaises(ClientError):validate('table_patch',p)
            p=self.delete_params();del p['tables'][0]['delete_rows']['rows'][0][key]
            with self.assertRaises(ClientError):validate('table_patch',p)
    def test_delete_does_not_mix_other_table_changes_or_infer_renumber(self):
        p=self.delete_params();p['tables'][0]['cells']=[{'row':4,'column':2,'before':'x','after':'y'}]
        with self.assertRaisesRegex(ClientError,'ROW_DELETE_SEPARATE_OPERATION_REQUIRED'):validate('table_patch',p)
        p=self.delete_params();p['tables']+=self.params()['tables']
        with self.assertRaisesRegex(ClientError,'ROW_DELETE_BATCH_SEPARATE_REQUIRED'):validate('table_patch',p)
        p=self.delete_params();p['tables'][0]['delete_rows']['renumber']='true'
        with self.assertRaisesRegex(ClientError,'EXACT_ROW_DELETE_FIELDS'):validate('table_patch',p)
    def color_params(self):
        return {'tables':[{'handle':'37E86','layer':'plants','row_count':16,'column_count':9,
            'legend_hatches':[{'block':'37E87','handle':'37E8B','before_color':256,'color':8}]}]}
    def test_color_only_accepts_explicit_aci_pair(self):
        p=self.color_params();validate('table_patch',p)
        for before in (0,1,255,256):
            p['tables'][0]['legend_hatches'][0]['before_color']=before;validate('table_patch',p)
    def test_color_requires_before_and_no_geometry_or_cell_edit(self):
        for field,value in [('rectangle',[-1,-1,1,1]),('pattern_scale',2),('reload_pattern',True)]:
            p=self.color_params();p['tables'][0]['legend_hatches'][0][field]=value
            with self.assertRaisesRegex(ClientError,'COLOR_ONLY_LEGEND_REQUIRED'):validate('table_patch',p)
        p=self.color_params();del p['tables'][0]['legend_hatches'][0]['before_color']
        with self.assertRaisesRegex(ClientError,'COLOR_ONLY_LEGEND_REQUIRED'):validate('table_patch',p)
        p=self.color_params();p['tables'][0]['cells']=[{'row':2,'column':2,'before':'x','after':'y'}]
        with self.assertRaisesRegex(ClientError,'COLOR_BATCH_SEPARATE_REQUIRED'):validate('table_patch',p)
        p=self.color_params();p['tables']+=self.params()['tables']
        with self.assertRaisesRegex(ClientError,'COLOR_BATCH_SEPARATE_REQUIRED'):validate('table_patch',p)
    def test_color_rejects_rgb_bool_fractional_null_and_out_of_range(self):
        for field,values in [('color',[0,256,-1,True,1.5,None,'8',[8,8,8]]),('before_color',[-1,257,False,1.5,None,'256'])]:
            for value in values:
                p=self.color_params();p['tables'][0]['legend_hatches'][0][field]=value
                with self.assertRaisesRegex(ClientError,'EXACT_ACI_COLOR_PAIR_REQUIRED'):validate('table_patch',p)
    def params(self):
        return {'tables':[{'handle':'AB','layer':'plants','row_count':5,'column_count':4,
            'cells':[{'row':2,'column':2,'before':'old','after':'new'}]}]}
    def test_native_write_contract_and_tail(self):
        p=self.params();validate('table_patch',p)
        self.assertIn('table_patch',MUTATING_KINDS);self.assertIn('table_patch',BRIDGE_KINDS)
        p['tables'][0]['delete_tail']={'start':4,'count':1,'before':[['4','','old','10']]};validate('table_patch',p)
    def test_wrong_index_bool_and_duplicate_rejected(self):
        for changes in ({'row':True},{'row':5},{'column':4}):
            p=self.params();p['tables'][0]['cells'][0].update(changes)
            with self.assertRaises(ClientError):validate('table_patch',p)
        p=self.params();p['tables'][0]['cells']*=2
        with self.assertRaisesRegex(ClientError,'DUPLICATE_CELL'):validate('table_patch',p)
    def test_old_values_are_required_even_blank(self):
        p=self.params();p['tables'][0]['cells'][0]['before']='';validate('table_patch',p)
        del p['tables'][0]['cells'][0]['before']
        with self.assertRaisesRegex(ClientError,'EXACT_CELL_FIELDS'):validate('table_patch',p)
    def test_tail_cannot_hide_missing_expected_values_or_middle_deletion(self):
        for tail in ({'start':3,'count':1,'before':[['','','','']]},
                     {'start':4,'count':1,'before':[['','','']]},
                     {'start':0,'count':5,'before':[['','','','']]*5}):
            p=self.params();p['tables'][0]['delete_tail']=tail
            with self.assertRaises(ClientError):validate('table_patch',p)
    def test_cannot_patch_removed_row_or_infer_cell_content(self):
        p=self.params();p['tables'][0]['delete_tail']={'start':4,'count':1,'before':[['','','','']]};p['tables'][0]['cells'][0]['row']=4
        with self.assertRaisesRegex(ClientError,'CELL_OUT_OF_RETAINED_RANGE'):validate('table_patch',p)
        p=self.params();p['tables'][0]['cells'][0]['after']=50
        with self.assertRaisesRegex(ClientError,'CELL_BEFORE_AFTER_TEXT'):validate('table_patch',p)
    def test_actual_client_release_selection(self):
        release={'status':'ISOLATED_NATIVE_VERIFIED','kinds':['table_patch'],'adapter_contract':'V736_NATIVE_EXTENSION_V1','dll':'test.dll','sha256':'x','entry':'HLCADTABLEPATCHV2'}
        with patch.object(bound_edits,'read',return_value=release) as reader,patch.object(bound_edits,'digest',return_value='x'),patch.object(bound_edits,'require_entry'):
            bound_edits.verified_release({},'table_patch')
        self.assertEqual(reader.call_args.args[0].name,'NativeTablePatchV1.release.json')
    def test_scale_only_preserves_existing_boundary_and_rejects_invalid_values(self):
        p=self.params();t=p['tables'][0];del t['cells']
        t['legend_hatches']=[{'block':'37EC1','handle':'37EC4','pattern_scale':0.12}]
        validate('table_patch',p)
        for value in (0,-1,True,float('inf'),float('nan'),'0.12',None):
            q=copy.deepcopy(p);q['tables'][0]['legend_hatches'][0]['pattern_scale']=value
            with self.assertRaisesRegex(ClientError,'POSITIVE_PATTERN_SCALE_REQUIRED'):validate('table_patch',q)
        del t['legend_hatches'][0]['pattern_scale']
        with self.assertRaisesRegex(ClientError,'LEGEND_CHANGE_REQUIRED'):validate('table_patch',p)
    def test_legend_patch_needs_no_manual_pattern_or_empty_cells(self):
        p=self.params();t=p['tables'][0];del t['cells']
        t['legend_hatches']=[{'block':'37EB4','handle':'37EB7','rectangle':[-1.5,-0.8,1.5,0.8]}]
        validate('table_patch',p)
        t['legend_hatches'][0]['reload_pattern']=True;validate('table_patch',p)
        t['legend_hatches'][0]['reload_pattern']='yes'
        with self.assertRaisesRegex(ClientError,'PATTERN_RELOAD_BOOLEAN_REQUIRED'):validate('table_patch',p)
        del t['legend_hatches'][0]['reload_pattern']
        for rect in ([0,0,0,1],[0,0,float('inf'),1],[False,0,1,1]):
            q=copy.deepcopy(p);q['tables'][0]['legend_hatches'][0]['rectangle']=rect
            with self.assertRaisesRegex(ClientError,'LOCAL_RECTANGLE_REQUIRED'):validate('table_patch',q)
        t['legend_hatches']*=2
        with self.assertRaisesRegex(ClientError,'DUPLICATE_LEGEND_HATCH'):validate('table_patch',p)

if __name__=='__main__':unittest.main()
