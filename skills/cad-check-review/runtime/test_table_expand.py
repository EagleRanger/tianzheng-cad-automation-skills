import copy
import unittest
from cad_runtime.protocol import validate, BRIDGE_KINDS, MUTATING_KINDS


class TableExpandTests(unittest.TestCase):
    def params(self):
        return {'tables':[{'handle':'A1','layout':'Model','layer':'0','row_count':4,
            'column_count':4,'column_map':[0,1,2,None,None,None,3,None,None],
            'column_widths':[50]*9,'row_heights':[25]*4,'text_height':5,
            'cells':[{'row':1,'column':3,'before':'','after':'Specification'}]}]}

    def test_preserves_original_columns(self):
        validate('table_expand',self.params())
        self.assertIn('table_expand', BRIDGE_KINDS & MUTATING_KINDS)

    def test_no_missing_duplicate_or_reordered_old_columns(self):
        for mapping in ([0,1,None,3],[0,1,1,2,3],[0,2,1,3],[None,0,1,2,3]):
            p=self.params();p['tables'][0]['column_map']=mapping
            with self.assertRaises(ValueError):validate('table_expand',p)

    def test_new_column_must_be_empty_before(self):
        p=self.params();p['tables'][0]['cells'][0]['before']='old'
        with self.assertRaises(ValueError):validate('table_expand',p)

    def test_exact_dimensions_and_finite_values(self):
        for key,value in [('column_widths',[50]*8),('row_heights',[20,20,-1,20]),('text_height',float('nan'))]:
            p=self.params();p['tables'][0][key]=value
            with self.assertRaises(ValueError):validate('table_expand',p)

    def test_no_duplicate_cell_patch(self):
        p=self.params();p['tables'][0]['cells']*=2
        with self.assertRaises(ValueError):validate('table_expand',p)

    def test_center_and_inset_legend_without_inventing_cells(self):
        p=self.params();t=p['tables'][0]
        t.update(cell_alignment='MiddleCenter',row_height_mode='at_least',
                 legend_fits=[{'row':2,'column':1,'block':'BE1','fit_ratio':0.8}])
        validate('table_expand',p)
        for change in ({'row':0},{'column':3},{'fit_ratio':1},{'fit_ratio':0},
                       {'fit_ratio':True},{'fit_ratio':float('nan')},{'block':'wrong'}):
            q=copy.deepcopy(p);q['tables'][0]['legend_fits'][0].update(change)
            with self.subTest(change=change),self.assertRaises(ValueError):validate('table_expand',q)
        q=copy.deepcopy(p);q['tables'][0]['legend_fits']*=2
        with self.assertRaises(ValueError):validate('table_expand',q)

    def test_explicit_height_policy_and_supported_alignment(self):
        for mode in ('exact','at_least'):
            p=self.params();p['tables'][0]['row_height_mode']=mode
            validate('table_expand',p)
        for key,value in [('row_height_mode','shrink_font'),('cell_alignment','TopLeft')]:
            p=self.params();p['tables'][0][key]=value
            with self.assertRaises(ValueError):validate('table_expand',p)


if __name__=='__main__':unittest.main()
