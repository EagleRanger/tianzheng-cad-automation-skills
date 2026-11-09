"""Rotation admission: preserve engineering fields and reject other native types."""
import copy
import unittest
from cad_runtime.protocol import validate
from cad_runtime.common import ClientError

class ElevationRotationTests(unittest.TestCase):
    def row(self):
        return dict(handle='35B8',type='TDbSymbElevation',layout='Model',layer='DIM_ELEV',
            expected=dict(Text='12.50',TextHeight='7.0',Scale=.5,LayoutRotation=330),
            expected_grips=[[0,0,0],[1,1,0],[2,1,0]],rotation=15)
    def test_absolute_degrees_and_layer(self):
        for angle in [-360,-30,0,15,330,360]:
            row=self.row();row.update(rotation=angle,target_layer='DIM_ELEV')
            validate('native_annotation_update',{'annotations':[row]})
    def test_nonfinite_boolean_out_of_range(self):
        for angle in [float('nan'),float('inf'),True,'15',361,-361,None]:
            row=self.row();row['rotation']=angle
            with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})
    def test_cannot_mix_engineering_value_or_scale(self):
        for changes in [dict(text='12.60'),dict(scale=1),dict(bearing=[1,2,0])]:
            row=self.row();row.update(changes)
            with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})
    def test_exact_topology_and_before_required(self):
        for key in ['expected_grips','expected']:
            row=self.row();row.pop(key)
            with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})
        row=self.row();row['expected_grips'].append([0,0,0])
        with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})
    def test_other_native_types_rejected(self):
        for typ in ['TDbSymbArrow','TDbSymbIndexPointer','AcDbText']:
            row=self.row();row['type']=typ
            with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})

if __name__=='__main__':unittest.main()
