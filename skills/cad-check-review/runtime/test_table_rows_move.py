import unittest
from cad_runtime.protocol import validate,OPERATION_CONTRACTS,BRIDGE_KINDS,MUTATING_KINDS
from cad_runtime.workflow import describe

class RowMoveTests(unittest.TestCase):
    def params(self):
        return dict(source_table=dict(handle='A',layout='Model',layer='0',row_count=17,column_count=4),target_table=dict(handle='B',layout='Model',layer='0',row_count=15,column_count=4),rows=[11,13,16],insert_before=2,renumber=True)
    def test_sparse_original_rows_and_contract(self):
        validate('table_rows_move',self.params())
        self.assertIn('table_rows_move',BRIDGE_KINDS & MUTATING_KINDS)
        self.assertIn('table_rows_move',OPERATION_CONTRACTS)
        self.assertTrue(describe('table_rows_move'))
    def test_headers_duplicate_rows_and_schema_rejected(self):
        for rows in [[1],[17],[11,11],[True],[]]:
            p=self.params();p['rows']=rows
            with self.assertRaises(ValueError):validate('table_rows_move',p)
        for change in [dict(handle='A'),dict(column_count=8)]:
            p=self.params();p['target_table'].update(change)
            with self.assertRaises(ValueError):validate('table_rows_move',p)

if __name__=='__main__':unittest.main()
