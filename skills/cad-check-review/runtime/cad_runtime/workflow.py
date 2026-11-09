"""Read-only operation navigation, not a second project state or authorization system."""
from pathlib import Path
import json
from .common import check
from .protocol import KINDS,SUCCESS,OPERATION_CONTRACTS

def describe(kind=None):
    if kind in ('polyline_edit','polyline_offset'):
        target={'handle':'<actual>','type':'AcDbPolyline','layer':'<actual>','bounds':['minX','minY','maxX','maxY']}
        params={'edits':[{'target':target,'expected_closed':False,'vertices':[[0,0,0.2,0,0],[10,0,0,0,0]]}]} if kind=='polyline_edit' else {'offsets':[{'target':target,'distance':0.2}]}
        return {'operation':kind,'entry':'cad_session_client.py submit '+kind+' --id <stable-id> --params <json>','params_example_only':params,**OPERATION_CONTRACTS[kind],
                'note':'Vertex x/y are target OCS, bulge=tan(signed arc angle/4); each row explicitly supplies start/end drawing widths (not curb offset distance). Closed, elevation and normal stay unchanged. Offset results are ALL appended; source is kept. Use receipt geometry to choose direction and connections; do not assume sign means engineering inside/outside.'}
    if kind == 'polyline_sync':
        return {'operation':kind,'entry':'cad_session_client.py submit polyline_sync --id <stable-id> --params <json>',
                'params':{'source':'<approved source DWG>','pairs':[{'source':{'handle':'<source>','type':'AcDbPolyline','layer':'<actual>','bounds':['minX','minY','maxX','maxY']},'target':{'handle':'<target>','type':'AcDbPolyline','layer':'<actual>','bounds':['minX','minY','maxX','maxY']},'preserve_target_endpoints':['end']}]},
                'optional':'Omit preserve_target_endpoints for whole source; [start], [end], or [start,end] keeps the corresponding old target endpoint point/bulge/start_width/end_width at the new first/last index. Other vertices come from source. Open polylines in the same normal/elevation only.',
                'boundary':'Preserves target handle/display. Does not infer which endpoint, fit curves, or certify tangent continuity. Engineering selection and affected drawing review remain execution/review.'}
    if kind == "layers":
        return {"operation":"layers", "entry":"cad_session_client.py layers --id <stable-id> --names <exact-names>",
                "module":"cad_runtime.layers.read_layers -> read_cad_layers.ps1", "inputs":["current session binding", "stable ID", "1..64 exact layer names"],
                "outputs":"global layer on/frozen/color/plot/lineweight/linetype, missing names, bound document/checkpoint and read-only receipt",
                "effects":"read-only COM query in existing private desktop; no DWG writes or native queue submission",
                "limits":"Current document only; does not include per-viewport freezes; reuse of an ID returns its original dated snapshot. Use a new ID only for a genuinely new observation after a state change.",
                "failure":"Returns failed/pending explicitly; existing pending query is never launched again. Control-chain errors go to management; layer visibility meaning remains a drafting judgment."}
    selected = [kind] if kind else list(KINDS)
    suggestion = next((k for k in KINDS if kind and kind.startswith(k + "_")), None)
    check(all(k in KINDS for k in selected), "UNSUPPORTED_KIND: 可用操作为 " + ", ".join([*KINDS, "layers"]) +
          ("；你可能需要 describe " + suggestion if suggestion else "；使用 describe <上述操作名> 查看参数，不需检索旧源码"))
    result={"protocol": "V736", "parameters": {k: {"required": sorted(KINDS[k][0]), "optional": sorted(KINDS[k][1])} for k in selected},
            "operation": {k: {**OPERATION_CONTRACTS[k], "receipt_status": SUCCESS.get(k, "lifecycle receipt plus actual process exit")} for k in selected},
            "execution_steps": [{"step": s["step"], "owner": s["owner"]} for s in json.loads(Path(__file__).with_name("components.json").read_text(encoding="utf-8"))["execution_steps"]],
            "examples": {k: {"params": {"next_path": "<本会话已批准的完整DWG路径>"}, "prepare": "prepare switch --id <本批ID> --params <参数JSON>", "submit": "submit switch --id <同一ID> --params <同一参数JSON>"} for k in selected if k == "switch"},
            "binding": "input/sha256/output/receipt/job哈希由客户端填；params禁止这些字段",
            "space": "inspect只查模型WCS；布局对象用page_map；view仅控制可选截图",
            "inspect_view": {"fields": ["layout", "x", "y", "width", "height"], "layout": "明确的实际布局名，如Model、布局1、布局2；由原生检查存在性",
                             "meaning": "x/y为截图视图中心，width/height为实际视图范围，不是像素；view与模型查询handles/bounds分开",
                             "output": "inspect完成后运行 capture --id 同一ID，返回真实CAD图面 .cad.png；旧CapturePreviewImage的.png可能只是空白图纸预览，不能用于审图。实际view_image核图，不以文件存在代替。"},
            "target": {"handle": "真实十六进制句柄", "type": "原生RX类型", "layer": "真实图层", "bounds": ["minX", "minY", "maxX", "maxY"]},
            "limits": "copy_transform仅同布局图框之间的竖向平移；不能把这项当任意复制。未知能力先查已有方法，不能试塞JOB_KIND。"}
    if kind:
        # The task-specific entry is short. Architecture and other operations
        # stay in the unqualified catalog, not every command response.
        for key in ('execution_steps','limits','space','inspect_view'):
            if key!='inspect_view' or kind!='inspect':result.pop(key,None)
        if kind in ('switch','close','layer_patch','page_map','coord_create','native_details','viewport_details','viewport_freeze','text_patch','layout_import','purge_unused','viewport_restore','paper_patch','coord_update'):result.pop('target',None)
        samples={
          'layout_import':{'source':'<approved source DWG>','source_layout':'<source layout>','target_layout':'<new layout name>'},
          'viewport_restore':{'source':'<approved saved DWG>','source_layout':'<source layout>','source_handle':'<rectangular viewport>','target_layout':'<existing target layout>','offset':[0,0]},
          'paper_patch':{'items':[{'handle':'<native root>','layout':'<source layout>','target_layout':'<optional target layout>','type':'<native type>','layer':'<exact layer>','action':'move','offset':[0,0]}]},
          'coord_update':{'axis_order':'YX','display_only':True,'items':[{'template_handle':'<TDbSymbCoord>','layout':'Model','layer':'<actual>','expected':{'x_value':'<native XValue>','y_value':'<native YValue>','rotation':'<LayoutRotation>','grips':'<all 3 current grips>'},'grips':'<3 desired grips; first unchanged>'}]},
          'native_annotation_update':{'annotations':[{'handle':'<current handle>','type':'TDbSymbElevation','layout':'<actual owner layout>','layer':'<actual layer>','expected':{'Text':'<current Text>','TextHeight':'<current TextHeight string>','Scale':1,'LayoutRotation':0},'expected_grips':'<three current native grips from native_details>','text':'<new elevation text>','scale':'<optional positive native Scale>'}]},
          'text_style_import':{'source':'<approved source DWG>','styles':['<source style name>']},
          'inspect':{'space':'Model','handles':['<model handle>'],'view':{'layout':'<actual layout>','x':'<center x>','y':'<center y>','width':'<drawing units>','height':'<drawing units>'}},
          'native_details':{'handles':['<native handle>']},
          'table_patch':{'tables':[{'handle':'<current AcDbTable>','layer':'<actual layer>','row_count':'<actual rows>','column_count':'<actual columns>','cells':[{'row':14,'column':2,'before':'<current TextString>','after':'<explicit new text>'}]}]},
          'text_read':{'handles':['<current/source text handle>']},
          'text_format':{'texts':[{'handle':'<MText handle>','layer':'<actual layer>','text':'<exact current Contents>','owner':{'handle':'<owner record>','name':'<owner name>','instances':['<optional; collected internally when omitted>']},'before':'<entire data.format object from text_read>','after':'<explicit replacement format with same six fields>','contents':'<optional: native plain_text must remain identical>','location':'<optional: explicit native point>'}]},
          'table_read':{'handles':['<current AcDbTable handle>']},
          'groundcover_update':{'items':[{'handle':'<existing TDbSymbMultiLeader>','layer':'<current layer>','expected':{'up':'<original upper text>','down':'<original lower text>'},'up_text':'<optional new upper text>','down_text':'<optional new lower text; text-only omits grips>'}]},
          'groundcover_create':{'items':[{'template_handle':'<current TDbSymbMultiLeader>','layer':'<existing layer>','up_text':'<name and area, e.g. 兰引三号 105m^U2^U>','expected':{'up':'<actual UpText>','down':'','height':'<actual Height>','scale':'<actual Scale>','rotation':'<actual LayoutRotation degrees>','grips':'<all current grips>'},'grips':[['<elbow x>','<elbow y>',0],['<bearing x>','<bearing y>',0],['<anchor x>','<anchor y>',0]]}]},
          'viewport_details':{'handles':['<viewport handle>'],'layers':['<exact layer>']},
          'viewport_freeze':{'layout':'<actual layout>','freezes':[{'handle':'<viewport handle>','layer':'<exact layer>','before':False,'after':True}]},
          'text_patch':{'layout':'<actual layout>','texts':[{'handle':'<text handle>','type':'AcDbText','layer':'<exact layer>','position':['<x>','<y>','<z>'],'before':'<actual text>','after':'<replacement>'}]},
          'coord_create':{'axis_order':'YX','items':[{'template_handle':'<native coordinate template>','expected_template_rotation':'<read back value>','grips':[['<measure x>','<measure y>',0],['<elbow x>','<elbow y>',0],['<text x>','<text y>',0]],'layer':'<destination layer>'}],'new_layers':[{'name':'<same destination layer>','color':3,'freeze_viewports':['<non-target viewport handle>']}]},
          'plant_layers':{'roles':[{'layer':'<role layer>','color':3,'targets':[{'handle':'<root handle>','type':'AcDbBlockReference','layer':'<actual layer>','bounds':['<minX>','<minY>','<maxX>','<maxY>']}]}]}}
        if kind in samples:result['examples'][kind]={'params':samples[kind]}
        if not result['examples']:result.pop('examples')
        result['run']='submit '+kind+' --id <本批ID> --params <参数.json>; status --id <同一ID>'
    if kind=='text_read':result['style_read_example']={'styles':['<exact style name>'],'source':'<optional approved source DWG>'}
    if kind=='native_annotation_update':
        result.pop('target',None)
        result['index_variant']={'type':'TDbSymbIndexPointer','expected':{'UpText':'<current>','DownText':'<current>','Height':'<current Height string>','Scale':1,'LayoutRotation':0},'expected_grips':'<six current native grips>','up_text':'<optional new name>','bearing':'<optional new g1 point; native symbol/text follow; g2 landing stays>'}
        result['note']='Use current native_details properties and grips. Omit unchanged optional fields. Elevation g0 is protected; index references and actual g2 landing are protected. Receipt and saved file verify native updates; execution/review judge engineering values and layout.'
        result['target_layer']='Optional exact existing layer on the selected native object only; leaves layer on/frozen/locked state and other entities unchanged. Can be the only change.'
        result['arrow_variant']={'type':'TDbSymbArrow','expected':{'Text':'<current main text>','Text2':'<current secondary text>','Height':'<actual string>','Scale':'<actual number>','LayoutRotation':'<actual number>'},'expected_grips':'<five current native grips>','text':'<optional new main text>','text2':'<optional new secondary text>'}
    if kind=='text_patch':result['native_plain_text']={'type':'TDbText','position':'native first grip from existing native_details','edit':'same texts row with before/after; content only; existing native Text/TextString setter; batch related rows'}
    if kind=='text_patch':result['native_title_styles']={'fields':['name_style','scale_style','name_height','scale_height'],'use':'TDbDrawingName only: style fields are existing style names; height fields are positive decimal strings. Omitted fields unchanged. Keep before=after for format-only edits. Native anchor/spacing/Scale retained; native nominal height getter checked at its one-decimal precision; each rendered text-piece metric retained through save/reopen, without assuming mixed fonts have equal glyph heights. COM height strings round to one decimal, so use text_read display geometry for precise output.'}
    return result
