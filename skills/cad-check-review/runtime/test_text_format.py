import copy,unittest,tempfile,json
from pathlib import Path
from cad_runtime.receipts import request_records
from cad_runtime.storage import digest
from unittest.mock import patch
from cad_runtime.protocol import validate,MUTATING_KINDS,BRIDGE_KINDS
from cad_runtime.common import ClientError
from cad_runtime import bound_edits

class TextFormatTests(unittest.TestCase):
    def test_paper_dbtext_style_height_are_explicit_and_type_scoped(self):
        p={'layout':'布局1','texts':[{'handle':'A','type':'AcDbText','layer':'0','position':[1,2,3],'before':'title','after':'title','text_style':'00ALYSA','text_height':10}]}
        validate('text_patch',p)
        p['texts'][0]['type']='AcDbMText'
        with self.assertRaisesRegex(ClientError,'DBTEXT_STYLE_REQUIRED'):validate('text_patch',p)
        p['texts'][0]['type']='AcDbText';p['texts'][0]['text_height']=0
        with self.assertRaisesRegex(ClientError,'POSITIVE_DBTEXT_HEIGHT_REQUIRED'):validate('text_patch',p)
        p['texts'][0]['text_height']=10;p['texts'][0]['text_width_factor']=.8;validate('text_patch',p)
        for value in (0,-.1,float('nan')):
            p['texts'][0]['text_width_factor']=value
            with self.assertRaisesRegex(ClientError,'POSITIVE_DBTEXT_WIDTH_FACTOR_REQUIRED'):validate('text_patch',p)
    def test_style_read_without_handles_and_import_contract(self):
        validate('text_read',{'styles':[]})
        validate('text_read',{'styles':['Standard'],'source':'approved.dwg'})
        validate('text_style_import',{'styles':['Standard'],'source':'approved.dwg'})
        for params in ({},{'handles':['A'],'styles':[]},{'styles':['A','a']}):
            with self.assertRaises(ClientError):validate('text_read',params)
        with self.assertRaises(ClientError):validate('text_style_import',{'styles':[],'source':'x'})
    def test_title_style_roles_only_on_native_title(self):
        p={'layout':'布局1','texts':[{'handle':'A','type':'TDbDrawingName','layer':'DIM_SYMB','position':[1,2,0],'before':'name','after':'name','name_style':'Standard1','scale_style':'_TCH_DIM'}]}
        validate('text_patch',p)
        p['texts'][0]['type']='AcDbMText'
        with self.assertRaisesRegex(ClientError,'NATIVE_TITLE_STYLE_REQUIRED'):validate('text_patch',p)
    def params(self):
        f={'style':'Standard','height':5,'width':70,'attachment':1,'line_spacing_style':1,'line_spacing_factor':1}
        return {'texts':[{'handle':'A','layer':'text','text':'unchanged','owner':{'handle':'B','name':'frame','instances':['C','D']},'before':f,'after':copy.deepcopy(f)}]}
    def test_format_and_optional_source_read(self):
        validate('text_format',self.params());validate('text_read',{'handles':['A']});validate('text_read',{'handles':['A'],'source':'approved.dwg'})
        self.assertIn('text_format',MUTATING_KINDS);self.assertNotIn('text_read',MUTATING_KINDS)
    def test_required_reference_scope_and_before_format(self):
        p=self.params();del p['texts'][0]['owner']['instances']
        validate('text_format',p)
        p=self.params();p['texts'][0]['owner']['instances']=['C','c']
        with self.assertRaisesRegex(ClientError,'EXACT_TEXT_REFERENCE_SCOPE'):validate('text_format',p)
        p=self.params();del p['texts'][0]['before']['width']
        with self.assertRaisesRegex(ClientError,'EXACT_TEXT_FORMAT_FIELDS'):validate('text_format',p)
    def test_optional_contents_location_and_automatic_reference_scope(self):
        p=self.params();t=p['texts'][0];t['contents']='same plain text';t['location']=[1,2,0];t['owner'].pop('instances');validate('text_format',p)
        t['location']=[float('nan'),2,0]
        with self.assertRaisesRegex(ClientError,'FINITE_LOCATION_REQUIRED'):validate('text_format',p)
    def test_content_rewrite_and_invalid_formats_not_supported(self):
        p=self.params();p['texts'][0]['new_text']='replace'
        with self.assertRaisesRegex(ClientError,'TEXT_FORMAT_FIELDS'):validate('text_format',p)
        for k,v in [('height',0),('width',-1),('attachment',0),('line_spacing_factor',5)]:
            p=self.params();p['texts'][0]['after'][k]=v
            with self.assertRaisesRegex(ClientError,'INVALID_TEXT_FORMAT'):validate('text_format',p)
    def test_reference_reader_receipt_is_bound_to_reference_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp);j=d/'job.json';receipt=d/'r.json';req=d/'request_r.json'
            job={'input_sha256':'current','source':'reference.dwg','source_sha256':'reference','receipt':str(receipt)}
            j.write_text(json.dumps(job));req.write_text(json.dumps({'kind':'text_read','job_path':str(j),'job_sha256':digest(j)}))
            for value,state in [('reference','RECEIPTED'),('current','UNREADABLE_REQUEST')]:
                receipt.write_text(json.dumps({'status':'BOUND_TEXT_READ','source_sha256':value}))
                self.assertEqual(request_records(d)[0]['state'],state)
    def test_block_text_erase_does_not_need_geometry_bounds(self):
        validate('erase',{'targets':[{'handle':'A','block':'tree','text':'name'}]})
        validate('erase',{'targets':[{'handle':'A','type':'AcDbLine','layer':'0','bounds':[0,0,1,1]}]})
        with self.assertRaisesRegex(ClientError,'BLOCK_TEXT_TARGET_FIELDS'):
            validate('erase',{'targets':[{'handle':'A','block':'tree','text':'name','bounds':[0,0,1,1]}]})
    def test_actual_release_routes_read_and_write(self):
        release={'status':'ISOLATED_NATIVE_VERIFIED','adapter_contract':'V736_NATIVE_EXTENSION_V1','kinds':['text_read','text_format'],'dll':'a','sha256':'x','entry':'HLCADTEXTFORMATV2'}
        for kind in release['kinds']:
            with patch.object(bound_edits,'read',return_value=release) as reader,patch.object(bound_edits,'digest',return_value='x'),patch.object(bound_edits,'require_entry'):
                bound_edits.verified_release({},kind)
            self.assertEqual(reader.call_args.args[0].name,'NativeTextFormatV1.release.json')

if __name__=='__main__':unittest.main()
