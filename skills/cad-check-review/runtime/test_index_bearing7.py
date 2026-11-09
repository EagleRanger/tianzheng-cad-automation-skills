import unittest
from cad_runtime.protocol import validate
from cad_runtime.common import ClientError

class SevenGripBearingTests(unittest.TestCase):
    def row(self):
        return dict(handle='C655',type='TDbSymbIndexPointer',layout='布局2',layer='DIM_IDEN',
            expected=dict(UpText='3m机耕路大样 详',DownText='余同',Height='5.0',Scale=1,LayoutRotation=0),
            expected_grips=[[0,0,0]]*7,bearing=[25,40,0])
    def test_seven_grip_bearing_preserves_contract(self):
        validate('native_annotation_update',{'annotations':[self.row()]})
    def test_seven_does_not_allow_text_or_scale(self):
        for changes in [dict(up_text='改名'),dict(scale=2),dict(rotation=0)]:
            row=self.row();row.update(changes)
            with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})
    def test_unknown_topologies_and_caller_follower_rejected(self):
        row=self.row();row['expected_grips']*=2
        with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})
        row=self.row();row['follower']=[5,6,0]
        with self.assertRaises(ClientError):validate('native_annotation_update',{'annotations':[row]})
if __name__=='__main__':unittest.main()
