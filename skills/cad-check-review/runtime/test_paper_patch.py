import unittest
from cad_runtime.protocol import validate, MUTATING_KINDS, BRIDGE_KINDS, SUCCESS


class PaperPatchTests(unittest.TestCase):
    def row(self, **kw):
        return dict(handle='A12', layout='Layout1', type='AcDbPolyline',
                    layer='0', action='display', before_color=2, color=7, **kw)

    def test_display_pairs_and_routing(self):
        validate('paper_patch', {'items': [self.row(before_linetype='ByLayer', linetype='Continuous')]})
        self.assertIn('paper_patch', MUTATING_KINDS)
        self.assertIn('paper_patch', BRIDGE_KINDS)
        self.assertEqual(SUCCESS['paper_patch'], 'SAVED_STILL_OPEN')

    def test_erase_needs_no_geometry_scan(self):
        validate('paper_patch', {'items': [dict(handle='A13', layout='Layout1',
                  type='AcDbViewport', layer='0', action='erase')]})

    def test_invalid_batches_fail_before_dispatch(self):
        cases = []
        r = self.row(); r['layout'] = 'Model'; cases.append([r])
        r = self.row(); del r['before_color']; cases.append([r])
        r = self.row(); r['color'] = True; cases.append([r])
        r = self.row(); r['action'] = 'erase'; cases.append([r])
        cases.append([self.row(), self.row()])
        cases.append([self.row(before_linetype_scale=1, linetype_scale=float('nan'))])
        for rows in cases:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                validate('paper_patch', {'items': rows})


class NorthCopyContractTests(unittest.TestCase):
    def test_native_north_copy_same_and_cross_layout(self):
        row=dict(handle='A3',layout='L1',type='TDbSymbNorthThumb',layer='DIM_SYMB',action='copy',offset=[100,0])
        validate('paper_patch', {'items':[row]})
        validate('paper_patch', {'items':[dict(row,offset=[0,0],target_layout='L2')]})
        for change in ({'type':'AcDbViewport'},{'type':'TDbSymbMultiLeader'},{'target_layout':'Model'},{'offset':[0,0]}):
            with self.subTest(change=change),self.assertRaises(ValueError):validate('paper_patch',{'items':[dict(row,**change)]})


class ViewportResizeContractTests(unittest.TestCase):
    def row(self):
        return dict(handle='A1',layout='L1',type='AcDbViewport',layer='0',
                    action='resize',before_width=120,before_height=80,width=180,height=120)

    def test_explicit_paper_dimensions_only(self):
        row=self.row();validate('paper_patch',{'items':[row]})
        for change in ({'type':'AcDbPolyline'},{'layout':'Model'},{'width':0},
                       {'height':True},{'before_width':float('inf')},
                       {'offset':[1,2]},{'color':7},{'target_layout':'L2'}):
            with self.subTest(change=change),self.assertRaises(ValueError):
                validate('paper_patch',{'items':[dict(row,**change)]})
        for field in ('before_width','before_height','width','height'):
            q=dict(row);del q[field]
            with self.subTest(field=field),self.assertRaises(ValueError):validate('paper_patch',{'items':[q]})

    def test_dimensions_rejected_for_other_actions(self):
        for action in ('erase','display','move','copy'):
            row=self.row();row['action']=action
            with self.subTest(action=action),self.assertRaises(ValueError):validate('paper_patch',{'items':[row]})


class PaperDefinitionContractTests(unittest.TestCase):
    def params(self):
        return {'entities':[{'target':{'handle':'A1','type':'AcDbBlockReference','layer':'0','bounds':[0,0,10,10]},'definition':'B1','before_color':2,'color':256,'target_layer':'0'}], 'definitions':[{'handle':'B1','name':'FRAME','instances':['C1','C2'],'space':'paper'}]}

    def test_paper_shared_definition(self):
        validate('entity_display', self.params())

    def test_nested_reference_requires_definition(self):
        d=self.params(); del d['entities'][0]['definition'];d.pop('definitions')
        with self.assertRaises(ValueError):validate('entity_display',d)

    def test_unknown_reference_scope(self):
        d=self.params();d['definitions'][0]['space']='any'
        with self.assertRaises(ValueError):validate('entity_display',d)


if __name__ == '__main__':
    unittest.main()
