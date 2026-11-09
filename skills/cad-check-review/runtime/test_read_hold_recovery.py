import unittest,copy
from recover_cad_read_hold import check_read_failure
from cad_runtime.common import ClientError

class ReadHoldTests(unittest.TestCase):
    def case(self):
        return ({'kind':'page_map'},dict(input='x',input_sha256='x',receipt='x',layout='missing',title_contains='x',frame_block_prefix='x',grid_block_name='x'),
            {'error':'System.InvalidOperationException: LAYOUT_NOT_FOUND:missing\r\n at V736BaseSession.PageMap\r\n at V736BaseSession.Pump'})
    def test_exact_missing_layout_read_is_admitted(self):
        check_read_failure(*self.case())
    def test_mutation_wrong_layout_wrong_stack_or_output_is_rejected(self):
        for part,key,value in [(0,'kind','paper_patch'),(1,'layout','other'),(1,'output','dwg'),(2,'error','eUnknownHandle')]:
            c=copy.deepcopy(self.case());c[part][key]=value
            with self.assertRaises(ClientError):check_read_failure(*c)
    def test_existing_handle_recovery_remains_bounded(self):
        q={'kind':'inspect'};j={'handles':['AB']};f={'error':'eUnknownHandle at V736BaseSession.InspectRegion'}
        check_read_failure(q,j,f)
        j['image']='image.png'
        with self.assertRaises(ClientError):check_read_failure(q,j,f)

if __name__=='__main__':unittest.main()
