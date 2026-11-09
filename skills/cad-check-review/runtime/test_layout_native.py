import unittest
from cad_runtime.protocol import validate, MUTATING_KINDS, BRIDGE_KINDS

class LayoutNativeContracts(unittest.TestCase):
    def test_delete_exact_distinct_paper_layout_only(self):
        p={'layout':'种植_园建原布局','replacement_layout':'种植原图布局1'}
        validate('layout_delete',p)
        self.assertIn('layout_delete',MUTATING_KINDS)
        self.assertIn('layout_delete',BRIDGE_KINDS)
        for name in ('Model','model','*','?','A/B','A\nB',''):
            for key in p:
                with self.assertRaises(ValueError):validate('layout_delete',dict(p,**{key:name}))
        with self.assertRaises(ValueError):validate('layout_delete',dict(p,replacement_layout=p['layout']))
        for extra in ('purge','targets','force','all_layouts'):
            with self.assertRaises(ValueError):validate('layout_delete',dict(p,**{extra:True}))
    def test_named_source_no_new_geometry(self):
        p={'source':'garden.dwg','source_layout':'布局1','target_layout':'种植平面'}
        validate('layout_import',p)
        self.assertIn('layout_import',BRIDGE_KINDS)
        for extra in ('scale','offset','erase_targets','commands'):
            with self.assertRaises(ValueError):validate('layout_import',dict(p,**{extra:1}))
    def test_exact_paper_names_only(self):
        for name in ('Model','*','?','布局1\n_PURGE','A/B',''):
            with self.assertRaises(ValueError):validate('layout_import',{'source':'garden.dwg','source_layout':name,'target_layout':'种植'})
    def test_purge_cannot_be_used_to_delete_entities(self):
        validate('purge_unused',{})
        self.assertIn('purge_unused',MUTATING_KINDS)
        with self.assertRaises(ValueError):validate('purge_unused',{'targets':['AB']})

if __name__=='__main__':unittest.main()
