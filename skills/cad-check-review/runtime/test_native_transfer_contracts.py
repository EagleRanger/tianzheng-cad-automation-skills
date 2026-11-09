import unittest
from cad_runtime.protocol import validate

class TransferContracts(unittest.TestCase):
    def test_cross_layout_zero_offset_preserves_original_position(self):
        row=dict(handle='A',layout='A',target_layout='B',layer='0',type='AcDbHatch',action='move',offset=[0,0])
        validate('paper_patch',{'items':[row]})
        for dest in ('Model','A',''):
            with self.assertRaises(ValueError):validate('paper_patch',{'items':[dict(row,target_layout=dest)]})

    def test_native_block_copy_has_explicit_translation(self):
        row=dict(handle='B',layout='A',layer='0',type='AcDbBlockReference',action='copy',offset=[500,0])
        validate('paper_patch',{'items':[row]})
        with self.assertRaises(ValueError):validate('paper_patch',{'items':[dict(row,type='AcDbViewport')]})

    def test_model_coordinate_display_only_does_not_accept_value_or_anchor_change(self):
        row=dict(template_handle='AB',layout='Model',layer='0',expected=dict(x_value=10,y_value=20,rotation=0,grips=[[20,10,0],[20,30,0],[50,30,0]]),grips=[[20,10,0],[20,40,0],[50,40,0]])
        p=dict(axis_order='YX',display_only=True,items=[row]);validate('coord_update',p)
        with self.assertRaises(ValueError):validate('coord_update',dict(p,items=[dict(row,world_xy=[20,10])]))
        with self.assertRaises(ValueError):validate('coord_update',dict(p,items=[dict(row,grips=[[21,10,0],[21,40,0],[50,40,0]])]))

    def test_restore_requires_exact_viewport_and_finite_offset(self):
        p=dict(source='source.dwg',source_layout='S',target_layout='T',source_handle='AB',offset=[0,0])
        validate('viewport_restore',p)
        for kw in (dict(source_handle='*'),dict(offset=[float('nan'),0]),dict(target_layout='Model')):
            with self.assertRaises(ValueError):validate('viewport_restore',dict(p,**kw))

if __name__=='__main__':unittest.main()
