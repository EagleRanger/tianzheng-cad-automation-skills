"""Actual handoff regressions; fixture files only, no live CAD."""
import json,subprocess,unittest
from pathlib import Path
from unittest.mock import patch
import cad_session_client as c
from cad_runtime import bound_edits as bridge
import test_cad_session_client as f

class BoundEditTests(unittest.TestCase):
    def test_viewport_freeze_rejects_legacy_shared_command_before_dispatch(self):
        release = {'status': 'ISOLATED_NATIVE_VERIFIED', 'kinds': ['viewport_freeze'],
                   'entry': 'HLCADBOUNDAPPLYV7', 'adapter_contract': 'V736_NATIVE_EXTENSION_V1'}
        with patch.object(bridge, 'read', return_value=release):
            with self.assertRaisesRegex(c.ClientError, 'VIEWPORT_FREEZE_REQUIRES_DEDICATED_ENTRY'):
                bridge.verified_release({}, 'viewport_freeze')

    def test_annotation_single_layer_and_arrow_two_texts(self):
        row={'handle':'A','type':'TDbSymbElevation','layout':'布局2','layer':'hidden','expected':{'Text':'12.92','TextHeight':'7.0','Scale':1,'LayoutRotation':0},'expected_grips':[[0,0,0]]*3,'target_layer':'DIM_ELEV'}
        c.validate('native_annotation_update',{'annotations':[row]})
        row.update(type='TDbSymbArrow',expected={'Text':'下6级','Text2':'0.15*6','Height':'3.5','Scale':2,'LayoutRotation':0},expected_grips=[[0,0,0]]*5,text='下5级',text2='0.15*5')
        c.validate('native_annotation_update',{'annotations':[row]})
        row['bearing']=[1,2,0]
        with self.assertRaisesRegex(c.ClientError,'NATIVE_ANNOTATION_CHANGE_SCOPE'):c.validate('native_annotation_update',{'annotations':[row]})
    def test_native_annotation_uses_bound_queue_and_rejects_unverified_topology(self):
        row={'handle':'A','type':'TDbSymbIndexPointer','layout':'布局2','layer':'DIM_IDEN','expected':{'UpText':'旧详图','DownText':'','Height':'5.0','Scale':1,'LayoutRotation':0},'expected_grips':[[0,0,0]]*6,'up_text':'节点B详图3','bearing':[1,2,0]}
        p={'annotations':[row]};c.validate('native_annotation_update',p)
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            out=c.submit(self.binding,'native_annotation_update',p,'annotation',probe=self.probe)
        self.assertEqual(out['transport'],'bound_native_extension')
        self.assertEqual(c.read(self.folder/'annotation.job.json')['annotations'],[row])
        self.assertFalse((self.folder/'request.json').exists())
        row['expected_grips'].extend([[0,0,0],[0,0,0]])
        with self.assertRaisesRegex(c.ClientError,'VERIFIED_ANNOTATION_GRIP_COUNT'):c.validate('native_annotation_update',p)
        row['expected_grips']=row['expected_grips'][:6];row['scale']=2
        with self.assertRaisesRegex(c.ClientError,'NATIVE_ANNOTATION_CHANGE_SCOPE'):c.validate('native_annotation_update',p)

    def test_paper_coord_update_requires_world_xy_separate_from_grips(self):
        row={'template_handle':'A','layout':'布局2','layer':'DIM_COOR','expected':{'x_value':2843179.7,'y_value':431878.8,'rotation':0,'grips':[[0,0,0],[0,25,0],[27.5,25,0]]},'world_xy':[431879.98735831503,2843175.8852694724],'grips':[[1,2,0],[1,27,0],[28.5,27,0]]}
        p={'axis_order':'YX','items':[row]};c.validate('coord_update',p)
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            out=c.submit(self.binding,'coord_update',p,'paper_coord',probe=self.probe)
        self.assertEqual(out['transport'],'bound_native_extension')
        job=c.read(self.folder/'paper_coord.job.json');self.assertEqual(job['items'][0]['world_xy'],row['world_xy']);self.assertNotEqual(row['world_xy'],row['grips'][0][:2])
        row['world_xy']=[1]
        with self.assertRaisesRegex(c.ClientError,'EXPLICIT_WORLD_XY_REQUIRED'):c.validate('coord_update',p)
        row['world_xy']=[1,2];row['layout']='Model'
        with self.assertRaisesRegex(c.ClientError,'EXACT_PAPER_LAYOUT_REQUIRED'):c.validate('coord_update',p)



    def test_entity_linetype_scale_requires_finite_before_after_pair(self):
        row={'target':{'handle':'A','type':'AcDbPolyline','layer':'0','bounds':[0,0,5,5]},'before_color':2,'target_layer':'0','color':2,'before_linetype_scale':5,'linetype_scale':2.5}
        p={'entities':[row]};c.validate('entity_display',p)
        row.pop('before_linetype_scale')
        with self.assertRaisesRegex(c.ClientError,'LINETYPE_SCALE_BEFORE_AFTER_REQUIRED'):c.validate('entity_display',p)
        row['before_linetype_scale']=5
        for value in (0,-1,float('nan'),float('inf'),True):
            row['linetype_scale']=value
            with self.assertRaisesRegex(c.ClientError,'POSITIVE_FINITE_LINETYPE_SCALE_REQUIRED'):c.validate('entity_display',p)
        row.pop('linetype_scale');row.pop('before_linetype_scale');c.validate('entity_display',p)



    def test_paper_leader_copy_does_not_expand_text_only_operation(self):
        frame={'handle':'A','type':'AcDbBlockReference','layer':'0','bounds':[0,0,100,100]}
        leader={'handle':'B','type':'TDbSymbMultiLeader','layer':'0','bounds':[1,1,10,10]}
        p={'source':'source.dwg','source_layout':'布局2','target_layout':'布局2','source_frame':frame,'target_frames':[frame],'source_targets':[leader]}
        c.validate('paper_entities_copy',p)
        with self.assertRaisesRegex(c.ClientError,'ONLY_NATIVE_TEXT_NOTES_SUPPORTED'):c.validate('paper_copy',p)



    def test_index_anchor_single_control_uses_original_bound_queue(self):
        p={'indexes':[{'handle':'A','layout':'布局2','layer':'DIM_IDEN','expected_grips':[[0,0,0]]*7,'anchor':[1,2,0]}]}
        c.validate('index_anchor',p)
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            out=c.submit(self.binding,'index_anchor',p,'index_anchor',probe=self.probe)
        self.assertEqual(out['transport'],'bound_native_extension')
        self.assertIn('output',c.read(self.folder/'index_anchor.job.json'))
        self.assertFalse((self.folder/'request.json').exists())
        p['indexes'][0]['follower']=[3,4,0]
        with self.assertRaisesRegex(c.ClientError,'INDEX_ANCHOR_FIELDS'):c.validate('index_anchor',p)
        p['indexes'][0].pop('follower');p['indexes'][0]['anchor'][0]=float('nan')
        with self.assertRaisesRegex(c.ClientError,'FINITE_INDEX_POINT'):c.validate('index_anchor',p)


    setUp=f.SessionTests.setUp
    put=f.SessionTests.put
    probe=f.SessionTests.probe
    def test_polyline_endpoint_option_is_explicit_and_rejects_unknown_or_duplicate_names(self):
        t={'handle':'A','type':'AcDbPolyline','layer':'0','bounds':[0,0,1,1]}
        p={'source':'source.dwg','pairs':[{'source':t,'target':t,'preserve_target_endpoints':['end']}]}
        c.validate('polyline_sync',p)
        for invalid in (['end','end'],['middle'],'end',[None]):
            p['pairs'][0]['preserve_target_endpoints']=invalid
            with self.assertRaisesRegex(c.ClientError,'ENDPOINT_NAMES'):c.validate('polyline_sync',p)
        p['pairs'][0].pop('preserve_target_endpoints');c.validate('polyline_sync',p)
    def test_plain_inspect_is_bound_and_cannot_reach_old_hold_handler(self):
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            out=c.submit(self.binding,'inspect',{'space':'Model','handles':['FFFFFFFFF']},'missing',probe=self.probe)
        self.assertEqual(out['transport'],'bound_native_extension')
        self.assertFalse((self.folder/'request.json').exists())
        self.assertTrue((self.folder/'missing.dispatch.json').exists())

    def test_native_title_patch_accepts_exact_type_not_generic_native_objects(self):
        p={'layout':'布局1','texts':[{'handle':'A','type':'TDbDrawingName','layer':'DIM_SYMB','position':[1,2,3],'before':'旧图名','after':'新图名'}]}
        c.validate('text_patch',p)
        p['texts'][0]['type']='TDbSymbMultiLeader'
        with self.assertRaisesRegex(c.ClientError,'TEXT_PATCH_CONTENT'):c.validate('text_patch',p)

    def test_table_read_reuses_bound_registry_without_mutating_output(self):
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            out=c.submit(self.binding,'table_read',{'handles':['A']},'cells',probe=self.probe)
        self.assertEqual(out['transport'],'bound_native_extension')
        self.assertNotIn('output',c.read(self.folder/'cells.job.json'))

    def test_groundcover_rejects_sharp_angle_before_native_dispatch(self):
        p={'items':[{'template_handle':'A','layer':'PLANT','up_text':'兰引三号 105m^U2^U','expected':{'up':'草','down':'','height':'5.0','scale':0.35,'rotation':0,'grips':[[0,0,0],[2,0,0],[0,-1,0],[1,1,0]]},'grips':[[0,0,0],[2,0,0],[0,-1,0]]}]}
        c.validate('groundcover_create',p)
        p['items'][0]['grips'][2]=[1,1,0]
        with self.assertRaisesRegex(c.ClientError,'ORTHOGONAL_LEADER_REQUIRED'):c.validate('groundcover_create',p)

    def test_new_modules_select_their_release_not_legacy_adapter_allowlist(self):
        for kind,name in [('table_read','NativeTableReadV1.release.json'),('native_details','NativePlantDetailsV1.release.json'),('groundcover_create','NativeGroundcoverV1.release.json')]:
            r={**self.release(),'status':'ISOLATED_NATIVE_VERIFIED','adapter_contract':'V736_NATIVE_EXTENSION_V1','kinds':[kind],'entry':'HLCADTEST'}
            with patch.object(bridge,'read',return_value=r) as reader,patch.object(bridge,'require_entry'):
                bridge.verified_release(self.binding,kind)
            self.assertEqual(reader.call_args.args[0].name,name)

    def layer_params(self):
        return {'layers':[{'name':'GRID','before':{'on':True,'frozen':True},'after':{'on':True,'frozen':False}}]}
    def paper_params(self):
        return {'layout':'布局1','transforms':[{'handle':'A','type':'AcDbPolyline','layer':'0','before':{'kind':'POLYLINE','normal':[0,0,1],'elevation':63.2402787578,'vertices':[{'bulge':0},{'bulge':0}]},'scale_x':1.3,'offset_x':-2,'offset_y':0}]}

    def test_paper_transform_bound_dispatch_and_native_save_contract(self):
        with patch.object(bridge,'verified_release',return_value=self.release()) as release,patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            out=c.submit(self.binding,'paper_transform',self.paper_params(),'ruler',probe=self.probe)
        self.assertEqual(out['transport'],'bound_native_extension');self.assertFalse((self.folder/'request.json').exists())
        release.assert_called_with(self.binding,'paper_transform')
        self.assertIn('output',c.read(self.folder/'ruler.job.json'))
        r={**self.release(),'status':'ISOLATED_NATIVE_VERIFIED','adapter_contract':'V736_NATIVE_EXTENSION_V1','kinds':['paper_transform'],'entry':'HLCADTEST'}
        with patch.object(bridge,'read',return_value=r) as reader,patch.object(bridge,'require_entry'):
            bridge.verified_release(self.binding,'paper_transform')
        self.assertEqual(reader.call_args.args[0].name,'NativePaperTransformV1.release.json')

    def test_paper_transform_rejects_model_arcs_duplicates_and_nonfinite(self):
        for change,reason in [(lambda p:p.update(layout='Model'),'PAPER_LAYOUT_REQUIRED'),(lambda p:p['transforms'][0]['before']['vertices'][0].update(bulge=.5),'PAPER_STRAIGHT_POLYLINE_REQUIRED'),(lambda p:p['transforms'].append(dict(p['transforms'][0])),'DUPLICATE_PAPER_TRANSFORM'),(lambda p:p['transforms'][0].update(offset_x=float('inf')),'FINITE_POSITIVE_X_TRANSFORM_REQUIRED'),(lambda p:p['transforms'][0].update(scale_x=0),'FINITE_POSITIVE_X_TRANSFORM_REQUIRED')]:
            p=self.paper_params();change(p)
            with self.assertRaisesRegex(c.ClientError,reason):c.validate('paper_transform',p)

    def test_committed_paper_resolution_keeps_failure_and_reuses_exact_output(self):
        from cad_runtime.receipts import request_records
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            c.submit(self.binding,'paper_transform',self.paper_params(),'ruler_fix',probe=self.probe)
        rec=request_records(self.folder)[0];request=Path(rec['request']);q=c.read(request);job=c.read(q['job_path'])
        emergency=self.folder/'emergency.dwg';emergency.write_bytes(b'exact committed result');Path(job['output']).write_bytes(emergency.read_bytes())
        failure=Path(job['receipt']);c.atomic_new(failure,{'status':'BOUND_MODULE_FAILED','write_started':True,'committed':False,'error':'UNSELECTED_OBJECT_MODIFIED_AT_COMMIT:2E2A','emergency':str(emergency)})
        original=failure.read_bytes();resolved=Path(str(failure)+'.resolution.json')
        c.atomic_new(resolved,{'status':'SAVED_STILL_OPEN','request':str(request),'request_sha256':c.digest(request),'job_sha256':q['job_sha256'],'failure':str(failure),'failure_sha256':c.digest(failure),'source_sha256':job['input_sha256'],'output':job['output'],'sha256':c.digest(emergency),'recovery':{'status':'COMMITTED_PAPER_TRANSFORM_RECOVERED','replayed':False,'production_entities_modified':False,'original_failure_preserved':True}})
        rows=request_records(self.folder);self.assertEqual(rows[0]['state'],'RECEIPTED');self.assertEqual(rows[0]['receipt'],str(resolved));self.assertEqual(failure.read_bytes(),original)
        Path(job['output']).write_bytes(b'other output')
        bad=request_records(self.folder)[0];self.assertEqual(bad['state'],'UNREADABLE_REQUEST');self.assertIn('PAPER_RECOVERED_OUTPUT_CHANGED',bad['error'])
    def release(self):return {'dll':str(self.dll),'sha256':c.digest(self.dll)}

    def test_hatch_never_reaches_old_pattern_transform_handler(self):
        p={'template':'A','template_layer':'GRASS','expected_pattern':'GRASS','parts':[{'loops':[[[0,0,0],[3,0,0],[3,3,0],[0,3,0]]]}]}
        with patch.object(bridge,'verified_release',return_value=self.release()) as release,patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            out=c.submit(self.binding,'hatch',p,'hatch1',probe=self.probe)
        self.assertEqual(out['transport'],'bound_native_extension');self.assertFalse((self.folder/'request.json').exists())
        release.assert_called_with(self.binding,'hatch')

    def child_display_params(self):
        return {'entities':[{'target':{'handle':'A','type':'AcDbLine','layer':'BASE','bounds':[0,0,1,1]},'definition':'B','before_color':41,'target_layer':'BASE','color':256}],
                'definitions':[{'handle':'B','name':'WALKWAY','instances':['C','D']}]}

    def test_block_child_display_requires_declared_definition(self):
        p=self.child_display_params();c.validate('entity_display',p)
        p.pop('definitions')
        with self.assertRaisesRegex(c.ClientError,'DISPLAY_DEFINITION_NOT_DECLARED'):c.validate('entity_display',p)

    def test_block_child_display_requires_exact_unique_reference_handles(self):
        p=self.child_display_params();p['definitions'][0]['instances']=['C','c']
        with self.assertRaisesRegex(c.ClientError,'EXACT_DEFINITION_INSTANCES_REQUIRED'):c.validate('entity_display',p)

    def test_model_display_still_works_without_block_scope(self):
        p=self.child_display_params();p.pop('definitions');p['entities'][0].pop('definition');c.validate('entity_display',p)

    def test_unused_definition_scope_is_rejected(self):
        p=self.child_display_params();p['definitions'].append({'handle':'E','name':'OTHER','instances':['F']})
        with self.assertRaisesRegex(c.ClientError,'UNUSED_DISPLAY_DEFINITION'):c.validate('entity_display',p)

    def test_pending_extension_uses_same_registry_and_repeated_id_never_relaunches(self):
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')) as run:
            first=c.submit(self.binding,'layer_patch',self.layer_params(),'layer1',probe=self.probe)
            again=c.submit(self.binding,'layer_patch',self.layer_params(),'layer1',probe=self.probe)
        self.assertEqual(first['state'],'SUBMITTED');self.assertEqual(again['state'],'ALREADY_SUBMITTED')
        run.assert_called_once();self.assertFalse((self.folder/'request.json').exists())
        snap=c.snapshot(self.binding,self.probe);self.assertFalse(snap['can_submit'])
        self.assertEqual(snap['requests'][0]['kind'],'layer_patch')

    def test_changed_before_state_same_id_rejected(self):
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            c.submit(self.binding,'layer_patch',self.layer_params(),'layer1',probe=self.probe)
            p=self.layer_params();p['layers'][0]['before']['frozen']=False
            with self.assertRaisesRegex(c.ClientError,'REQUEST_ID_REUSED'):c.submit(self.binding,'layer_patch',p,'layer1',probe=self.probe)

    def test_missing_validated_extension_stops_before_publish(self):
        with patch.object(bridge,'verified_release',side_effect=c.ClientError('BOUND_MODULE_NOT_VALIDATED')):
            with self.assertRaisesRegex(c.ClientError,'BOUND_MODULE_NOT_VALIDATED'):c.submit(self.binding,'layer_patch',self.layer_params(),'no1',probe=self.probe)
        self.assertFalse(list(self.folder.glob('request*.json')))

    def test_unsupported_source_or_paper_model_mix_rejected(self):
        params={'source':str(self.folder/'outside.dwg'),'source_layout':'Layout1','handles':['A']}
        with self.assertRaisesRegex(c.ClientError,'SOURCE_NOT_ALLOWLISTED'):c.submit(self.binding,'paper_read',params,'read1',probe=self.probe)
        params.update(source=str(self.drawing),source_layout='Model')
        with self.assertRaisesRegex(c.ClientError,'PAPER_LAYOUT_REQUIRED'):c.validate('paper_read',params)

    def test_new_layout_uses_extension_instead_of_old_native_guard(self):
        p={'space':'Model','handles':['A'],'view':{'layout':'布局2','x':1,'y':2,'width':10,'height':20}}
        with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            c.submit(self.binding,'inspect',p,'view2',probe=self.probe)
        self.assertFalse((self.folder/'request.json').exists())
        self.assertEqual(c.read(self.folder/'view2.job.json')['layout'],'布局2')
        self.assertTrue((self.folder/'view2.dispatch.json').exists())

    def failed_base(self,changed=False):
        job={'input':str(self.drawing),'input_sha256':c.digest(self.drawing),'output':str(self.folder/'failed.dwg'),'receipt':str(self.folder/'base.receipt.json')}
        self.put(self.folder/'base.job.json',job)
        req=self.folder/'request_bound_base.json'
        self.put(req,{'kind':'base_replace','client_request_id':'base','job_path':str(self.folder/'base.job.json'),'job_sha256':c.digest(self.folder/'base.job.json')})
        self.put(job['receipt'],{'status':'BASE_REPLACE_FAILED','source_sha256':job['input_sha256'],'active_document_changed':changed})
        self.put(self.folder/'base.dispatch.json',{'request':str(req),'host':self.host,'document':str(self.drawing)})
        probe=self.folder/'idle.json';self.put(probe,{'status':'BOUND_HOST_READ_ONLY','cmdactive':0,'request':str(req),'source_sha256':job['input_sha256'],'pid':123,'created':456,'document':str(self.drawing)})
        return job,probe

    def test_failed_base_resolution_preserves_failure_and_does_not_approve_candidate(self):
        job,probe=self.failed_base();before=Path(job['receipt']).read_bytes()
        result=c.resolve_failed_base(self.folder,'base',probe)
        self.assertEqual(result['state'],'RESOLVED_REJECTED');self.assertFalse(result['completed'])
        self.assertEqual(Path(job['receipt']).read_bytes(),before)
        self.assertEqual(c.request_records(self.folder)[0]['state'],'RESOLVED_REJECTED')
        self.assertFalse((self.folder/'failed.dwg').exists())

    def test_base_resolution_rejects_changed_live_document_or_host(self):
        job,probe=self.failed_base(changed=True)
        with self.assertRaisesRegex(c.ClientError,'NOT_SAFE_TO_RESOLVE'):c.resolve_failed_base(self.folder,'base',probe)
        self.put(job['receipt'],{'status':'BASE_REPLACE_FAILED','source_sha256':job['input_sha256'],'active_document_changed':False})
        p=c.read(probe);p['pid']=999;self.put(probe,p)
        with self.assertRaisesRegex(c.ClientError,'LIVE_IDENTITY'):c.resolve_failed_base(self.folder,'base',probe)

    def test_base_dispatch_uses_verified_release_entry(self):
        release={**self.release(),'entry':'HLCADBASEREPLACEV3'}
        with patch.object(bridge,'verified_release',return_value=release),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            bridge.publish(self.binding,{'kind':'base_replace','client_request_id':'entry3'},self.folder/'entry3.job.json',self.native)
        self.assertEqual(c.read(self.folder/'entry3.dispatch.json')['entry'],'HLCADBASEREPLACEV3')

if __name__=='__main__':unittest.main()
