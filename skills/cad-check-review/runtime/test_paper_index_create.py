import copy
import unittest
from cad_runtime.protocol import validate, OPERATION_CONTRACTS, BRIDGE_KINDS, MUTATING_KINDS
from cad_runtime.workflow import describe


class PaperIndexTests(unittest.TestCase):
    def params(self):
        return dict(layout='布局1', boundary_template=dict(handle='A', layer='0'),
                    index_template=dict(handle='B', layer='DIM_IDEN'), expected_index_label='1/7',
                    items=[dict(key='15', vertices=[[0, 0], [30, 4], [22, 40], [-4, 31]],
                                position=[10, 14], index_label='15/15', drawing_label='PM-15')])

    def test_rotated_polygon_and_native_labels(self):
        p = self.params()
        original = copy.deepcopy(p)
        validate('paper_index_create', p)
        self.assertEqual(original, p)
        self.assertIn('paper_index_create', BRIDGE_KINDS & MUTATING_KINDS)
        self.assertIn('paper_index_create', OPERATION_CONTRACTS)
        self.assertTrue(describe('paper_index_create'))

    def test_invalid_geometry_before_dispatch(self):
        for vertices in [[], [[0, 0], [1, 1]], [[0, 0], [1, 0], [0, 0]],
                         [[0, 0], [True, 1], [2, 2]], [[0, 0], [1, float('nan')], [2, 2]]]:
            p = self.params(); p['items'][0]['vertices'] = vertices
            with self.assertRaises(ValueError): validate('paper_index_create', p)

    def test_target_scope_and_duplicate_key(self):
        p = self.params(); p['layout'] = 'Model'
        with self.assertRaises(ValueError): validate('paper_index_create', p)
        p = self.params(); p['items'] *= 2
        with self.assertRaises(ValueError): validate('paper_index_create', p)
        p = self.params(); p['delete_old'] = True
        with self.assertRaises(ValueError): validate('paper_index_create', p)
        p = self.params(); p['items'][0]['position'] = [0, 0, 0]
        with self.assertRaises(ValueError): validate('paper_index_create', p)


if __name__ == '__main__': unittest.main()
