import unittest
from unittest.mock import patch
from cad_runtime.protocol import validate
from cad_runtime.binding import STATE
import recover_cad_paper_checkpoint as recovery

class CameraAndPaperMoveTests(unittest.TestCase):
    def camera(self):
        def t(h):return dict(handle=h,type='AcDbViewport',layer='0',bounds=[0,0,10,10])
        return dict(source='source.dwg',source_layout='L',target_layout='L',pairs=[dict(source=t('A'),target=t('B'),world_offset=[11,-13,0],custom_scale=2)])
    def test_plan_camera_parameters(self):
        p=self.camera();validate('viewport_camera',p)
        for change in [dict(world_offset=[1,2,3]),dict(world_offset=[1,float('nan'),0]),dict(custom_scale=0),dict(custom_scale=True)]:
            p=self.camera();p['pairs'][0].update(change)
            with self.assertRaises(ValueError):validate('viewport_camera',p)
    def test_layer_copy_cannot_inherit_camera_offset(self):
        p=self.camera();p.update(layer_pairs=[dict(source='A',target='B')],protected_layers=[])
        with self.assertRaises(ValueError):validate('viewport_layers',p)
    def test_paper_move_excludes_other_edits_and_model(self):
        row=dict(handle='A',layout='L',layer='0',type='AcDbViewport',action='move',offset=[594,-420])
        validate('paper_patch',dict(items=[row]))
        for change in [dict(layout='Model'),dict(color=2),dict(offset=[0,0]),dict(offset=[1,2,3]),dict(offset=[float('inf'),2])]:
            with self.assertRaises(ValueError):validate('paper_patch',dict(items=[dict(row,**change)]))
    def test_recovery_default_state_is_original_pointer(self):
        with patch.object(recovery,'load_binding',side_effect=RuntimeError('stop')) as load:
            with self.assertRaises(RuntimeError):recovery.recover(None,'failed')
            load.assert_called_once_with(STATE)

if __name__=='__main__':unittest.main()
