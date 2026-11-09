"""V736 operation contracts; no file or CAD access."""
import math, re
from .common import check


KINDS = {
    "viewport_restore": ({"source","source_layout","source_handle","target_layout","offset"},set()),
    "layout_import": ({"source","source_layout","target_layout"},set()),
    "layout_delete": ({"layout","replacement_layout"},set()),
    "purge_unused": (set(),set()),
    "paper_roots_activate": ({"layout","targets"},set()),
    "paper_leaders_copy": ({"source","source_layout","target_layout","source_targets","offset"},set()),
    "paper_roots_copy": ({"source","source_layout","target_layout","source_targets"},{"frozen_layer_pairs"}),
    "paper_index_create": ({"layout","boundary_template","index_template","expected_index_label","items"},set()),
    "table_rows_move": ({"source_table","target_table","rows","insert_before","renumber"},set()),
    "table_expand": ({"tables"},set()),
    "paper_patch": ({"items"},set()),
    "native_annotation_update": ({"annotations"},set()),
    "coord_update": ({"axis_order","items"},{"display_only"}),
    "index_anchor": ({"indexes"},set()),
    "hatch_pattern": ({"hatches"},set()),
    "source_register": ({"path", "expected_sha256", "role"}, set()),
    "text_read": (set(), {"handles","styles","source"}),
    "text_style_import": ({"source","styles"}, set()),
    "text_format": ({"texts"}, set()),
    "groundcover_update": ({"items"}, set()),
    "table_patch": ({"tables"}, set()),
    "groundcover_create": ({"items"}, set()),
    "table_read": ({"handles"}, set()),
    "viewport_freeze": ({"layout","freezes"}, set()),
    "text_patch": ({"layout","texts"}, set()),
    "paper_transform": ({"layout","transforms"}, set()),
    "coord_create": ({"axis_order","items"}, {"new_layers"}),
    "plant_layers": ({"roles"}, set()),
    "native_details": ({"handles"}, set()),
    "viewport_details": ({"handles","layers"}, set()),
    "inspect": ({"space"}, {"handles", "bounds", "view"}),
    "page_map": ({"layout", "title_contains", "frame_block_prefix", "grid_block_name"}, set()),
    "erase": ({"targets"}, set()),
    "hatch": ({"template", "template_layer", "expected_pattern", "parts"}, {"expected_color", "replace_target"}),
    "transfer": ({"source", "old_targets", "source_targets"}, set()),
    "copy_transform": ({"layout", "frame_block_prefix", "grid_block_name", "pairs"}, set()),
    "switch": ({"next_path"}, set()),
    "close": (set(), set()),
    "layer_patch": ({"layers"}, set()),
    "paper_read": ({"source", "source_layout", "handles"}, set()),
    "paper_copy": ({"source", "source_layout", "target_layout", "source_frame", "source_targets", "target_frames"}, {"target_layer"}),
    "paper_entities_copy": ({"source", "source_layout", "target_layout", "source_frame", "source_targets", "target_frames"}, {"target_layer"}),
    "paper_note": ({"source", "source_layout", "target_layout", "source_frame", "source_targets", "target_frames", "note_text"}, {"target_layer"}),
    "entity_display": ({"entities"}, {"new_layers","definitions"}),
    "polyline_sync": ({"source", "pairs"}, set()),
    "polyline_create": ({"creations"},set()),
    "polyline_edit": ({"edits"},set()),
    "polyline_offset": ({"offsets"},set()),
    "base_replace": ({"source", "source_targets", "old_targets", "protected_targets", "deferred_targets"}, {"source_groups"}),
    "viewport_camera": ({"source","source_layout","target_layout","pairs"},set()),
    "viewport_layers": ({"source","source_layout","target_layout","pairs","layer_pairs","protected_layers"},set()),
}

BRIDGE_KINDS = {"coord_create","viewport_details","plant_layers","native_details","layer_patch", "paper_read", "paper_copy", "paper_note", "entity_display", "polyline_sync", "base_replace","viewport_camera","viewport_layers"}
MUTATING_KINDS = {"coord_create","plant_layers","erase", "hatch", "transfer", "copy_transform", "layer_patch", "paper_copy", "paper_note", "entity_display", "polyline_sync", "base_replace","viewport_camera","viewport_layers"}
BRIDGE_KINDS.update({'paper_transform','text_style_import','text_read','text_format','groundcover_update','table_patch','viewport_freeze','text_patch','hatch','inspect','groundcover_create','table_read'})
BRIDGE_KINDS.add('source_register')
BRIDGE_KINDS.update({"coord_update","index_anchor","hatch_pattern","paper_entities_copy"})
MUTATING_KINDS.update({"coord_update","index_anchor","hatch_pattern","paper_entities_copy"})
BRIDGE_KINDS.add('native_annotation_update')
MUTATING_KINDS.add('native_annotation_update')
BRIDGE_KINDS.update({"polyline_edit","polyline_offset","polyline_create"})
MUTATING_KINDS.update({"polyline_edit","polyline_offset","polyline_create"})
MUTATING_KINDS.update({'paper_transform','text_style_import','text_format','groundcover_update','table_patch','viewport_freeze','text_patch','groundcover_create'})


BRIDGE_KINDS.add("paper_patch")
MUTATING_KINDS.add("paper_patch")

BRIDGE_KINDS.add("table_expand")
MUTATING_KINDS.add("table_expand")
BRIDGE_KINDS.add("table_rows_move")
MUTATING_KINDS.add("table_rows_move")
BRIDGE_KINDS.add("paper_index_create")
MUTATING_KINDS.add("paper_index_create")

BRIDGE_KINDS.add("paper_roots_activate")
MUTATING_KINDS.add("paper_roots_activate")
BRIDGE_KINDS.add("paper_leaders_copy")
MUTATING_KINDS.add("paper_leaders_copy")
BRIDGE_KINDS.add("paper_roots_copy")
MUTATING_KINDS.add("paper_roots_copy")

BRIDGE_KINDS.update({"layout_import","purge_unused","viewport_restore","layout_delete"})
MUTATING_KINDS.update({"layout_import","purge_unused","viewport_restore","layout_delete"})

SUCCESS = {
    "viewport_restore": "SAVED_STILL_OPEN",
    "layout_import": "SAVED_STILL_OPEN",
    "layout_delete": "SAVED_STILL_OPEN",
    "purge_unused": "SAVED_STILL_OPEN",
    "paper_roots_activate": "SAVED_STILL_OPEN",
    "paper_leaders_copy": "SAVED_STILL_OPEN",
    "paper_roots_copy": "SAVED_STILL_OPEN",
    "paper_index_create": "SAVED_STILL_OPEN",
    "table_rows_move": "SAVED_STILL_OPEN",
    "table_expand": "SAVED_STILL_OPEN",
    "paper_patch": "SAVED_STILL_OPEN",
    "coord_update":"SAVED_STILL_OPEN",
    "index_anchor":"SAVED_STILL_OPEN",
    "native_annotation_update":"SAVED_STILL_OPEN",
    "hatch_pattern":"SAVED_STILL_OPEN", "paper_entities_copy":"SAVED_STILL_OPEN",
    "polyline_create":"SAVED_STILL_OPEN", "polyline_edit":"SAVED_STILL_OPEN", "polyline_offset":"SAVED_STILL_OPEN",
    "source_register": "SOURCE_REGISTERED_NO_DRAWING_CHANGE",
    "paper_transform":"SAVED_STILL_OPEN",
    "text_style_import":"SAVED_STILL_OPEN", "text_read":"BOUND_TEXT_READ", "text_format":"SAVED_STILL_OPEN",
    "groundcover_update":"SAVED_STILL_OPEN",
    "table_patch":"SAVED_STILL_OPEN",
    "groundcover_create":"SAVED_STILL_OPEN", "table_read":"BOUND_NATIVE_DETAILS_READ",
    "viewport_freeze":"SAVED_STILL_OPEN","text_patch":"SAVED_STILL_OPEN",
    "coord_create": "SAVED_STILL_OPEN",
    "plant_layers": "SAVED_STILL_OPEN",
    "native_details": "BOUND_NATIVE_DETAILS_READ",
    "viewport_details": "BOUND_NATIVE_DETAILS_READ",
    "inspect": "SCOPED_READ_ONLY_INSPECTION", "page_map": "PAGE_MAP_READ_ONLY",
    "erase": "SAVED_STILL_OPEN", "hatch": "SAVED_STILL_OPEN",
    "transfer": "SAVED_STILL_OPEN", "copy_transform": "SAVED_STILL_OPEN",
    "switch": "CURRENT_SAVED_BEFORE_SWITCH",
    "layer_patch": "SAVED_STILL_OPEN", "paper_copy": "SAVED_STILL_OPEN", "polyline_sync": "SAVED_STILL_OPEN",
    "paper_read": "BOUND_PAPER_READ_ONLY",
    "base_replace": "SAVED_STILL_OPEN",
    "paper_note": "SAVED_STILL_OPEN", "entity_display": "SAVED_STILL_OPEN",
    "viewport_camera":"SAVED_STILL_OPEN","viewport_layers":"SAVED_STILL_OPEN",
}


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def bounds(value, strict=False):
    check(isinstance(value, list) and len(value) == 4 and all(number(x) for x in value), "BOUNDS: 必须是[minX,minY,maxX,maxY]有限数字")
    check(value[0] <= value[2] and value[1] <= value[3], "BOUNDS_ORDER")
    if strict: check(value[0] < value[2] and value[1] < value[3], "BOUNDS_EMPTY")


def target(value):
    check(isinstance(value, dict) and set(value) == {"handle", "type", "layer", "bounds"}, "TARGET: 需真实handle/type/layer/bounds四项")
    check(isinstance(value["handle"], str) and re.fullmatch(r"[0-9A-Fa-f]+", value["handle"]), "TARGET_HANDLE")
    check(all(isinstance(value[k], str) and value[k] for k in ("type", "layer")), "TARGET_TYPE_LAYER")
    bounds(value["bounds"])


def targets(values, empty=False):
    check(isinstance(values, list) and (values or empty), "TARGET_LIST_EMPTY")
    for value in values: target(value)
    check(len({v["handle"].upper() for v in values}) == len(values), "TARGET_DUPLICATE")


def validate(kind, params):
    check(kind in KINDS, "UNSUPPORTED_KIND: 先describe；不让CAD试错")
    check(isinstance(params, dict), "PARAMS_OBJECT_REQUIRED")
    required, optional = KINDS[kind]
    check(not (set(params) - required - optional), "UNKNOWN_FIELDS:" + ",".join(sorted(set(params) - required - optional)))
    check(required <= set(params), "MISSING_FIELDS:" + ",".join(sorted(required - set(params))))
    if kind == 'paper_roots_activate':
        from .paper_roots_copy import validate_paper_roots_copy
        validate_paper_roots_copy({'source':'placeholder.dwg','source_layout':params['layout'],'target_layout':params['layout'],'source_targets':params['targets']})
    elif kind == 'paper_roots_copy':
        from .paper_roots_copy import validate_paper_roots_copy
        validate_paper_roots_copy(params)
    elif kind == 'paper_index_create':
        from .paper_index_create import validate_paper_index_create
        validate_paper_index_create(params)
    elif kind == 'table_rows_move':
        from .table_rows_move import validate_table_rows_move
        validate_table_rows_move(params)
    elif kind == 'table_expand':
        from .table_expand import validate_table_expand
        validate_table_expand(params)
    elif kind == 'paper_patch':
        from .paper_patch import validate_paper_patch
        validate_paper_patch(params)
    elif kind == 'source_register':
        check(isinstance(params['path'],str) and params['path'].lower().endswith('.dwg'), 'SOURCE_DWG_REQUIRED')
        check(isinstance(params['expected_sha256'],str) and re.fullmatch('[a-f0-9]{64}',params['expected_sha256']), 'SOURCE_HASH_REQUIRED')
        check(params['role'] in ('garden','planting','reference'), 'SOURCE_ROLE_REQUIRED')
    if kind=='paper_leaders_copy':
        from .paper_roots_copy import validate_paper_roots_copy
        validate_paper_roots_copy(params)
        check(all(t['type']=='TDbSymbMultiLeader' for t in params['source_targets']),'EXACT_NATIVE_MULTILEADERS_ONLY')
        v=params['offset'];check(isinstance(v,list) and len(v)==2 and all(number(x) for x in v),'FINITE_PAPER_OFFSET_REQUIRED')
    if kind in ("layout_import","viewport_restore"):
        check(isinstance(params["source"],str) and params["source"].lower().endswith(".dwg"),"SOURCE_DWG_REQUIRED")
        for key in ("source_layout","target_layout"):
            value=params[key]
            check(isinstance(value,str) and value.strip() and value.lower()!="model" and not any(c in value for c in "\r\n*?\"<>/\\|:;="),"EXACT_PAPER_LAYOUT_NAME_REQUIRED")
    if kind=="layout_delete":
        for key in ("layout","replacement_layout"):
            value=params[key]
            check(isinstance(value,str) and value.strip() and value.lower()!="model" and not any(ord(c)<32 or c in '*?"<>/\\|:;=' for c in value),"EXACT_PAPER_LAYOUT_NAME_REQUIRED")
        check(params["layout"].casefold()!=params["replacement_layout"].casefold(),"DISTINCT_REPLACEMENT_LAYOUT_REQUIRED")
    if kind=="viewport_restore":
        check(isinstance(params["source_handle"],str) and re.fullmatch("[0-9a-fA-F]+",params["source_handle"]),"EXACT_VIEWPORT_HANDLE_REQUIRED")
        v=params["offset"];check(isinstance(v,list) and len(v)==2 and all(number(x) for x in v),"FINITE_PAPER_OFFSET_REQUIRED")
    for key in ("layout", "title_contains", "frame_block_prefix", "grid_block_name", "template", "template_layer", "expected_pattern", "source", "next_path", "source_layout", "target_layout", "target_layer"):
        if key in params: check(isinstance(params[key], str) and params[key].strip(), "EMPTY_FIELD:" + key)
    if kind in ('text_read','text_style_import'):
        if kind=='text_read':check(('handles' in params)!=('styles' in params),'TEXT_READ_HANDLES_OR_STYLES_REQUIRED')
        if 'styles' in params:
            names=params['styles'];check(isinstance(names,list) and (kind=='text_read' or names) and all(isinstance(n,str) and n.strip() and not any(ord(c)<32 for c in n) for n in names) and len({n.casefold() for n in names})==len(names),'UNIQUE_STYLE_NAMES_REQUIRED')
    if kind=='text_format':
        check(isinstance(params['texts'],list) and params['texts'],'TEXT_FORMAT_ITEMS_REQUIRED');seen=set()
        for t in params['texts']:
            check(isinstance(t,dict) and {'handle','layer','text','owner','before','after'}<=set(t)<={'handle','layer','text','owner','before','after','contents','location'},'TEXT_FORMAT_FIELDS')
            check(isinstance(t['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',t['handle']) and t['handle'].upper() not in seen and isinstance(t['layer'],str) and t['layer'] and isinstance(t['text'],str),'TEXT_FORMAT_IDENTITY');seen.add(t['handle'].upper())
            o=t['owner'];check(isinstance(o,dict) and {'handle','name'}<=set(o)<={'handle','name','instances'} and isinstance(o['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',o['handle']) and isinstance(o['name'],str) and o['name'],'TEXT_OWNER_IDENTITY')
            refs=o.get('instances',[]);check(isinstance(refs,list) and all(isinstance(h,str) and re.fullmatch(r'[0-9A-Fa-f]+',h) for h in refs) and len({h.upper() for h in refs})==len(refs),'EXACT_TEXT_REFERENCE_SCOPE')
            if 'contents' in t:check(isinstance(t['contents'],str),'TEXT_CONTENTS_STRING_REQUIRED')
            if 'location' in t:check(isinstance(t['location'],list) and len(t['location'])==3 and all(number(v) for v in t['location']),'FINITE_LOCATION_REQUIRED')
            for key in ('before','after'):
                f=t[key];check(isinstance(f,dict) and set(f)=={'style','height','width','attachment','line_spacing_style','line_spacing_factor'},'EXACT_TEXT_FORMAT_FIELDS')
                check(isinstance(f['style'],str) and f['style'] and all(number(f[n]) for n in ('height','width','line_spacing_factor')) and f['height']>0 and f['width']>=0 and .25<=f['line_spacing_factor']<=4 and type(f['attachment']) is int and 1<=f['attachment']<=9 and type(f['line_spacing_style']) is int and f['line_spacing_style'] in (1,2),'INVALID_TEXT_FORMAT')
    elif kind == 'native_annotation_update':
        rows=params['annotations'];check(isinstance(rows,list) and rows,'ANNOTATION_TARGETS_REQUIRED');seen=set()
        for row in rows:
            required={'handle','type','layout','layer','expected','expected_grips'}
            check(isinstance(row,dict) and required<=set(row)<=required|{'text','text2','scale','up_text','bearing','target_layer','rotation'},'NATIVE_ANNOTATION_FIELDS')
            h=row['handle'];check(isinstance(h,str) and re.fullmatch(r'[0-9A-Fa-f]+',h) and h.upper() not in seen,'UNIQUE_ANNOTATION_HANDLE_REQUIRED');seen.add(h.upper())
            check(all(isinstance(row[k],str) and row[k].strip() for k in ('layout','layer')),'EXACT_ANNOTATION_OWNER_REQUIRED')
            elevation=row['type']=='TDbSymbElevation';arrow=row['type']=='TDbSymbArrow'
            check(elevation or arrow or row['type']=='TDbSymbIndexPointer','SUPPORTED_NATIVE_ANNOTATION_REQUIRED')
            allowed=({'text','scale','rotation'} if elevation else {'text','text2'} if arrow else {'up_text','bearing'})|{'target_layer'}
            check(bool(set(row)&allowed) and (set(row)-required)<=allowed,'NATIVE_ANNOTATION_CHANGE_SCOPE')
            keys={'Text','TextHeight','Scale','LayoutRotation'} if elevation else {'Text','Text2','Height','Scale','LayoutRotation'} if arrow else {'UpText','DownText','Height','Scale','LayoutRotation'}
            e=row['expected'];check(isinstance(e,dict) and set(e)==keys,'EXACT_NATIVE_PROPERTIES_REQUIRED')
            check(number(e['Scale']) and e['Scale']>0 and number(e['LayoutRotation']),'EXPECTED_NATIVE_NUMBERS')
            check(all(isinstance(e[k],str) for k in keys-{'Scale','LayoutRotation'}),'EXPECTED_NATIVE_TEXT_PROPERTIES')
            g=row['expected_grips'];check(isinstance(g,list) and len(g) in ((3,) if elevation else (5,) if arrow else (6,7)),'VERIFIED_ANNOTATION_GRIP_COUNT')
            if not elevation and not arrow and len(g)==7:check('up_text' not in row,'SEVEN_GRIP_BEARING_ONLY')
            points=g+([row['bearing']] if 'bearing' in row else [])
            for p in points:check(isinstance(p,list) and len(p)==3 and all(number(v) for v in p),'FINITE_ANNOTATION_POINT_REQUIRED')
            for key in ('text','text2','up_text','target_layer'):
                if key in row:check(isinstance(row[key],str) and row[key].strip(),'NONEMPTY_NATIVE_TEXT')
            if 'scale' in row:check(number(row['scale']) and row['scale']>0,'POSITIVE_NATIVE_SCALE')
            if 'rotation' in row:
                check(number(row['rotation']) and -360<=row['rotation']<=360,'ROTATION_DEGREES_REQUIRED')
                check(not set(row)&{'text','scale','text2','up_text','bearing'},'ELEVATION_ROTATION_ONLY')
    elif kind == 'index_anchor':
        rows=params['indexes'];check(isinstance(rows,list) and rows,'INDEX_TARGETS_REQUIRED');seen=set()
        for row in rows:
            check(isinstance(row,dict) and set(row)=={'handle','layout','layer','expected_grips','anchor'},'INDEX_ANCHOR_FIELDS')
            h=row['handle'];check(isinstance(h,str) and re.fullmatch(r'[0-9A-Fa-f]+',h) and h.upper() not in seen,'UNIQUE_INDEX_HANDLE_REQUIRED');seen.add(h.upper())
            check(all(isinstance(row[k],str) and row[k].strip() for k in ('layout','layer')),'EXACT_INDEX_OWNER_LAYER_REQUIRED')
            grips=row['expected_grips'];check(isinstance(grips,list) and len(grips)==7,'EXPECTED_SEVEN_GRIPS_REQUIRED')
            for point in grips+[row['anchor']]:check(isinstance(point,list) and len(point)==3 and all(number(v) for v in point),'FINITE_INDEX_POINT_REQUIRED')
    elif kind == 'hatch_pattern':
        rows=params['hatches'];check(isinstance(rows,list) and rows,'HATCH_EDITS_REQUIRED')
        for row in rows:
            check(isinstance(row,dict) and {'target','before','after'}<=set(row)<={'target','before','after','layout'},'HATCH_PATTERN_FIELDS')
            if 'layout' in row:check(isinstance(row['layout'],str) and row['layout'].strip(),'EXACT_LAYOUT_NAME_REQUIRED')
            target(row['target']);check(row['target']['type']=='AcDbHatch','NATIVE_HATCH_REQUIRED')
            for key in ('before','after'):
                p=row[key];check(isinstance(p,dict) and set(p)=={'pattern','scale'} and isinstance(p['pattern'],str) and re.fullmatch(r'[A-Za-z0-9_-]+',p['pattern']) and p['pattern'].upper()!='SOLID' and number(p['scale']) and p['scale']>0,'HATCH_PATTERN_SCALE')
        targets([r['target'] for r in rows])
    elif kind == 'groundcover_update':
        check(isinstance(params['items'],list) and params['items'],'UPDATE_ITEMS_REQUIRED');seen=set()
        for row in params['items']:
            check(isinstance(row,dict) and {'handle','layer','expected'}<=set(row)<={'handle','layer','expected','grips','up_text','down_text','scale','layout','text_grip','rotation'},'GROUNDCOVER_UPDATE_FIELDS')
            check(bool({'grips','up_text','down_text','scale','text_grip','rotation'}&set(row)),'UPDATE_ACTION_REQUIRED')
            check(isinstance(row['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',row['handle']) and row['handle'].upper() not in seen,'DUPLICATE_UPDATE_TARGET');seen.add(row['handle'].upper())
            check(isinstance(row['layer'],str) and row['layer'].strip(),'GROUNDCOVER_LAYER_REQUIRED')
            if 'layout' in row:check(isinstance(row['layout'],str) and row['layout'].strip(),'EXACT_LAYOUT_NAME_REQUIRED')
            e=row['expected'];short=isinstance(e,dict) and set(e) in ({'up','down'},{'up','down','scale'}) and 'grips' not in row and 'text_grip' not in row and 'rotation' not in row
            check(short or (isinstance(e,dict) and set(e)=={'up','down','height','scale','rotation','grips'}),'GROUNDCOVER_EXPECTED_FIELDS')
            if short:
                check(all(isinstance(e[k],str) for k in ('up','down')),'UPDATE_EXPECTED_TEXT_REQUIRED')
            else:
                check(all(isinstance(e[k],str) for k in ('up','down','height')) and e['height'] and number(e['scale']) and e['scale']>0 and number(e['rotation']),'UPDATE_EXPECTED_TEXT_REQUIRED')
                g=e['grips'];check(isinstance(g,list) and len(g)>=3 and all(isinstance(p,list) and len(p)==3 and all(number(v) for v in p) for p in g),'GROUNDCOVER_GRIPS')
            if 'rotation' in row:
                check(len(params['items'])==1 and number(row['rotation']) and abs(row['rotation'])<=360 and 'grips' in row and not ({'scale','up_text','down_text','text_grip'}&set(row)),'ROTATION_SINGLE_GEOMETRY_ONLY')
            if 'scale' in row:check(number(row['scale']) and row['scale']>0 and number(e.get('scale')) and e['scale']>0,'POSITIVE_SCALE_AND_EXPECTED_SCALE_REQUIRED')
            for k in ('up_text','down_text'):
                if k in row:check(isinstance(row[k],str) and not any(ord(c)<32 for c in row[k]),'NATIVE_TEXT_STRING_REQUIRED')
            if 'text_grip' in row:
                check(False,'TEXT_GRIP_SUSPENDED_NATIVE_DISPLAY_LINKAGE: use principal grips; independent text control has an unverified display effect')
            if 'grips' in row:
                check(row.get('down_text','')=='','SINGLE_UPTEXT_MOVE_REQUIRED')
                validate('groundcover_create',{'items':[{'template_handle':row['handle'],'layer':row['layer'],'up_text':row.get('up_text',e['up']),'expected':e,'grips':row['grips']}]})
    elif kind == 'table_patch':
        tables=params.get('tables',[])
        if isinstance(tables,list) and any(isinstance(t,dict) and isinstance(t.get('legend_hatches'),list) and any(isinstance(h,dict) and h.get('outline') for h in t['legend_hatches']) for t in tables):
            check(all(isinstance(t,dict) and isinstance(t.get('legend_hatches'),list) and t['legend_hatches'] and all(isinstance(h,dict) and h.get('outline') is True for h in t['legend_hatches']) and not any(t.get(k) for k in ('cells','delete_tail','delete_rows')) for t in tables),'OUTLINE_BATCH_SEPARATE_REQUIRED')
        check(isinstance(params['tables'],list) and params['tables'],'TABLE_PATCH_ITEMS_REQUIRED')
        if any(isinstance(t,dict) and t.get('delete_rows') is not None for t in params['tables']):
            check(all(isinstance(t,dict) and t.get('delete_rows') is not None for t in params['tables']),'ROW_DELETE_BATCH_SEPARATE_REQUIRED')
        seen=set()
        for t in params['tables']:
            required={'handle','layer','row_count','column_count'}
            check(isinstance(t,dict) and required<=set(t)<=required|{'cells','delete_tail','delete_rows','legend_hatches'},'TABLE_PATCH_FIELDS')
            check(isinstance(t['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',t['handle']) and t['handle'].upper() not in seen and isinstance(t['layer'],str) and t['layer'].strip(),'TABLE_PATCH_IDENTITY');seen.add(t['handle'].upper())
            check(all(type(t[n]) is int and t[n]>0 for n in ('row_count','column_count')),'TABLE_PATCH_SIZE')
            d=t.get('delete_tail');limit=t['row_count']
            deleted=t.get('delete_rows')
            if deleted is not None:
                check(not any(t.get(k) for k in ('cells','delete_tail','legend_hatches')),'ROW_DELETE_SEPARATE_OPERATION_REQUIRED')
                check(isinstance(deleted,dict) and set(deleted)=={'rows','renumber'} and type(deleted['renumber']) is bool,'EXACT_ROW_DELETE_FIELDS')
                check(isinstance(deleted['rows'],list) and deleted['rows'],'DELETE_ROWS_REQUIRED');removed=set()
                for row in deleted['rows']:
                    check(isinstance(row,dict) and set(row)=={'row','before','block_ids'},'EXACT_DELETED_ROW_FIELDS')
                    n=row['row'];check(type(n) is int and 2<=n<t['row_count'] and n not in removed,'UNIQUE_ORIGINAL_DATA_ROWS_REQUIRED');removed.add(n)
                    check(isinstance(row['before'],list) and len(row['before'])==t['column_count'] and all(isinstance(v,str) for v in row['before']),'ROW_EXPECTED_ALL_CELLS')
                    check(isinstance(row['block_ids'],list) and len(row['block_ids'])==t['column_count'] and all(v is None or isinstance(v,str) and re.fullmatch(r'[0-9A-Fa-f]+',v) for v in row['block_ids']),'ROW_EXPECTED_ALL_BLOCKS')
            if d is not None:
                check(isinstance(d,dict) and {'start','count','before'}<=set(d)<={'start','count','before','block_ids'},'EXACT_TAIL_FIELDS')
                check(type(d['start']) is int and type(d['count']) is int and d['start']>=2 and d['count']>0 and d['start']+d['count']==t['row_count'],'EXACT_TAIL_ROWS_REQUIRED')
                check(isinstance(d['before'],list) and len(d['before'])==d['count'] and all(isinstance(row,list) and len(row)==t['column_count'] and all(isinstance(v,str) for v in row) for row in d['before']),'TAIL_EXPECTED_ALL_CELLS');limit=d['start']
            if d is not None and 'block_ids' in d:
                b=d['block_ids'];check(isinstance(b,list) and len(b)==d['count'] and all(isinstance(row,list) and len(row)==t['column_count'] and all(v is None or isinstance(v,str) and re.fullmatch(r'[0-9A-Fa-f]+',v) for v in row) for row in b),'TAIL_BLOCK_MATRIX_REQUIRED')
            legends=t.get('legend_hatches',[]);check(isinstance(legends,list),'LEGEND_HATCH_LIST');hatches=set()
            for h in legends:
                check(isinstance(h,dict) and {'block','handle'}<=set(h)<={'block','handle','rectangle','reload_pattern','pattern_scale','outline','before_color','color'},'LEGEND_HATCH_FIELDS')
                check('rectangle' in h or 'pattern_scale' in h or h.get('reload_pattern') is True or h.get('outline') is True or 'color' in h,'LEGEND_CHANGE_REQUIRED')
                check(all(isinstance(h[k],str) and re.fullmatch(r'[0-9A-Fa-f]+',h[k]) for k in ('block','handle')),'LEGEND_HATCH_IDENTITY')
                check(h['handle'].upper() not in hatches,'DUPLICATE_LEGEND_HATCH');hatches.add(h['handle'].upper())
                if 'color' in h or 'before_color' in h:
                    check(set(h)=={'block','handle','before_color','color'},'COLOR_ONLY_LEGEND_REQUIRED')
                    check(type(h['color']) is int and 1<=h['color']<=255 and type(h['before_color']) is int and 0<=h['before_color']<=256,'EXACT_ACI_COLOR_PAIR_REQUIRED')
                if 'outline' in h:check(h['outline'] is True and set(h)=={'block','handle','outline'},'OUTLINE_ONLY_LEGEND_REQUIRED')
                if 'reload_pattern' in h:check(type(h['reload_pattern']) is bool,'PATTERN_RELOAD_BOOLEAN_REQUIRED')
                if 'pattern_scale' in h:check(number(h['pattern_scale']) and h['pattern_scale']>0,'POSITIVE_PATTERN_SCALE_REQUIRED')
                if 'rectangle' in h:
                    q=h['rectangle'];check(isinstance(q,list) and len(q)==4 and all(number(v) for v in q) and q[2]>q[0] and q[3]>q[1],'LOCAL_RECTANGLE_REQUIRED')
            if any(h.get('outline') for h in legends):check(all(h.get('outline') for h in legends) and not any(t.get(k) for k in ('cells','delete_tail','delete_rows')),'OUTLINE_BATCH_SEPARATE_REQUIRED')
            if any('color' in h or 'before_color' in h for h in legends):
                check(all(isinstance(x,dict) and isinstance(x.get('legend_hatches'),list) and x['legend_hatches'] and all(isinstance(h,dict) and 'color' in h and 'before_color' in h for h in x['legend_hatches']) and not any(x.get(k) for k in ('cells','delete_tail','delete_rows')) for x in tables),'COLOR_BATCH_SEPARATE_REQUIRED')
            cells=t.get('cells',[]);check(isinstance(cells,list) and (cells or d is not None or deleted is not None or legends),'CELL_LIST_REQUIRED');selected=set()
            for c in cells:
                check(isinstance(c,dict) and set(c)=={'row','column','before','after'},'EXACT_CELL_FIELDS')
                check(type(c['row']) is int and type(c['column']) is int and 0<=c['row']<limit and 0<=c['column']<t['column_count'],'CELL_OUT_OF_RETAINED_RANGE')
                key=(c['row'],c['column']);check(key not in selected,'DUPLICATE_CELL');selected.add(key)
                check(isinstance(c['before'],str) and isinstance(c['after'],str) and len(c['after'])<=10000 and '\x00' not in c['after'],'CELL_BEFORE_AFTER_TEXT')
    elif kind == 'paper_transform':
        check(isinstance(params['layout'],str) and params['layout'].strip() and params['layout']!='Model','PAPER_LAYOUT_REQUIRED')
        rows=params['transforms'];check(isinstance(rows,list) and rows,'PAPER_TRANSFORMS_REQUIRED');seen=set()
        for row in rows:
            check(isinstance(row,dict) and set(row)=={'handle','type','layer','before','scale_x','offset_x','offset_y'},'PAPER_TRANSFORM_FIELDS')
            check(isinstance(row['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',row['handle']) and isinstance(row['layer'],str) and row['layer'].strip(),'PAPER_TRANSFORM_IDENTITY')
            check(row['handle'].upper() not in seen,'DUPLICATE_PAPER_TRANSFORM');seen.add(row['handle'].upper())
            check(row['type'] in ('AcDbPolyline','AcDbHatch'),'PAPER_POLYLINE_SOLID_ONLY')
            check(all(number(row[k]) for k in ('scale_x','offset_x','offset_y')) and row['scale_x']>0,'FINITE_POSITIVE_X_TRANSFORM_REQUIRED')
            g=row['before'];check(isinstance(g,dict) and g.get('kind')==('POLYLINE' if row['type']=='AcDbPolyline' else 'HATCH'),'EXACT_PAPER_GEOMETRY_REQUIRED')
            check(g.get('normal')==[0,0,1] and number(g.get('elevation')),'PAPER_POSITIVE_Z_PLANE_REQUIRED')
            if row['type']=='AcDbPolyline':
                v=g.get('vertices');check(isinstance(v,list) and len(v)>=2 and all(isinstance(p,dict) and number(p.get('bulge')) and abs(p['bulge'])<1e-12 for p in v),'PAPER_STRAIGHT_POLYLINE_REQUIRED')
            else:
                check(g.get('pattern','').upper()=='SOLID' and g.get('associative') is False and isinstance(g.get('loops'),list) and g['loops'],'PAPER_NONASSOCIATIVE_SOLID_REQUIRED')
    elif kind in ('viewport_freeze','text_patch'):
        check(params['layout']!='Model','PAPER_LAYOUT_REQUIRED')
        rows=params['freezes' if kind=='viewport_freeze' else 'texts'];check(isinstance(rows,list) and rows,'PATCH_ROWS_REQUIRED');seen=set()
        for row in rows:
            fields={'handle','layer','before','after'} if kind=='viewport_freeze' else {'handle','layer','type','position','before','after'}
            extra={'name_style','scale_style','name_height','scale_height','text_style','text_height','text_width_factor'} if kind=='text_patch' else set()
            check(isinstance(row,dict) and fields<=set(row)<=fields|extra,'PATCH_FIELDS')
            check(isinstance(row['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',row['handle']) and isinstance(row['layer'],str) and row['layer'].strip(),'PATCH_IDENTITY')
            key=(row['handle'].upper(),row['layer']) if kind=='viewport_freeze' else row['handle'].upper();check(key not in seen,'DUPLICATE_PATCH');seen.add(key)
            if kind=='viewport_freeze':check(type(row['before']) is bool and type(row['after']) is bool,'FREEZE_BOOLEAN_REQUIRED')
            else:
                check(row['type'] in ('AcDbText','AcDbMText','TDbDrawingName','TDbText') and isinstance(row['before'],str) and isinstance(row['after'],str) and row['after'] and not any(ord(c)<32 for c in row['after']),'TEXT_PATCH_CONTENT')
                p=row['position'];check(isinstance(p,list) and len(p)==3 and all(number(v) for v in p),'TEXT_POSITION_REQUIRED')
                for k in ('name_height','scale_height'):
                    if k in row:check(row['type']=='TDbDrawingName' and isinstance(row[k],str) and bool(re.fullmatch(r'(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)',row[k])) and number(float(row[k])) and float(row[k])>0,'POSITIVE_NATIVE_TITLE_HEIGHT_REQUIRED')
                for k in ('name_style','scale_style'):
                    if k in row:check(row['type']=='TDbDrawingName' and isinstance(row[k],str) and row[k].strip() and not any(ord(c)<32 for c in row[k]),'NATIVE_TITLE_STYLE_REQUIRED')
                if 'text_style' in row:check(row['type']=='AcDbText' and isinstance(row['text_style'],str) and row['text_style'].strip() and not any(ord(c)<32 for c in row['text_style']),'DBTEXT_STYLE_REQUIRED')
                if 'text_height' in row:check(row['type']=='AcDbText' and number(row['text_height']) and row['text_height']>0,'POSITIVE_DBTEXT_HEIGHT_REQUIRED')
                if 'text_width_factor' in row:check(row['type']=='AcDbText' and number(row['text_width_factor']) and row['text_width_factor']>0,'POSITIVE_DBTEXT_WIDTH_FACTOR_REQUIRED')
    elif kind == "groundcover_create":
        check(isinstance(params['items'],list) and params['items'],'GROUNDCOVER_ITEMS_REQUIRED')
        for row in params['items']:
            check(isinstance(row,dict) and set(row)=={'template_handle','layer','up_text','expected','grips'},'GROUNDCOVER_FIELDS')
            check(isinstance(row['template_handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',row['template_handle']) and isinstance(row['layer'],str) and row['layer'].strip() and isinstance(row['up_text'],str) and row['up_text'].strip() and not any(ord(c)<32 for c in row['up_text']),'GROUNDCOVER_IDENTITY_TEXT')
            e=row['expected'];check(isinstance(e,dict) and set(e)=={'up','down','height','scale','rotation','grips'},'GROUNDCOVER_EXPECTED_FIELDS')
            check(isinstance(e['up'],str) and e['up'] and e['down']=='' and isinstance(e['height'],str) and e['height'] and number(e['scale']) and e['scale']>0 and number(e['rotation']),'SINGLE_UPTEXT_TEMPLATE_REQUIRED')
            for pts,n in [(e['grips'],4),(row['grips'],3)]:check(isinstance(pts,list) and len(pts)==n and all(isinstance(p,list) and len(p)==3 and all(number(v) for v in p) for p in pts),'GROUNDCOVER_GRIPS')
            g=row['grips'];u=[a-b for a,b in zip(g[1],g[0])];v=[a-b for a,b in zip(g[2],g[0])];nu=math.hypot(*u);nv=math.hypot(*v);check(nu>1e-6 and nv>1e-6 and abs(sum(a*b for a,b in zip(u,v))/(nu*nv))<1e-7,'ORTHOGONAL_LEADER_REQUIRED')
    elif kind == 'coord_update':
        check(type(params.get('display_only',False)) is bool,'BOOLEAN_DISPLAY_ONLY_REQUIRED')
        display_only=params.get('display_only',False)
        check(params['axis_order']=='YX' and isinstance(params['items'],list) and params['items'],'YX_COORD_ITEMS_REQUIRED');seen=set()
        for row in params['items']:
            check(isinstance(row,dict) and set(row)==({'template_handle','layout','layer','expected','grips'} if display_only else {'template_handle','layout','layer','expected','world_xy','grips'}),'PAPER_COORD_UPDATE_FIELDS')
            h=row['template_handle'];check(isinstance(h,str) and re.fullmatch(r'[0-9A-Fa-f]+',h) and h.upper() not in seen,'UNIQUE_COORD_UPDATE_HANDLES');seen.add(h.upper())
            check(all(isinstance(row[k],str) and row[k].strip() for k in ('layout','layer')) and (display_only or row['layout']!='Model'),'EXACT_PAPER_LAYOUT_REQUIRED')
            e=row['expected'];check(isinstance(e,dict) and set(e)=={'x_value','y_value','rotation','grips'} and all(number(e[k]) for k in ('x_value','y_value','rotation')),'EXPECTED_COORD_VALUES_REQUIRED')
            if not display_only:
                w=row['world_xy'];check(isinstance(w,list) and len(w)==2 and all(number(v) for v in w),'EXPLICIT_WORLD_XY_REQUIRED')
            for g in (e['grips'],row['grips']):check(isinstance(g,list) and len(g)==3 and all(isinstance(p,list) and len(p)==3 and all(number(v) for v in p) for p in g),'THREE_FINITE_GRIPS')
            if display_only:check(row['grips'][0]==e['grips'][0],'DISPLAY_ONLY_MEASURE_POINT_FIXED')
            g=row['grips'];u=[a-b for a,b in zip(g[0],g[1])];v=[a-b for a,b in zip(g[2],g[1])];nu=math.hypot(*u);nv=math.hypot(*v);check(nu>1e-6 and nv>1e-6,'ZERO_LENGTH_LEADER');dot=sum(a*b for a,b in zip(u,v))/(nu*nv);check(-1+1e-8<dot<=1e-8,'LEADER_MUST_BE_RIGHT_OR_OBTUSE')
    elif kind == "coord_create":
        check(params['axis_order']=='YX' and isinstance(params['items'],list) and params['items'],'YX_COORD_ITEMS_REQUIRED')
        for row in params['items']:
            check(isinstance(row,dict) and set(row)=={'template_handle','expected_template_rotation','grips','layer'},'COORD_ITEM_FIELDS')
            check(isinstance(row['template_handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',row['template_handle']) and number(row['expected_template_rotation']) and isinstance(row['layer'],str) and row['layer'].strip(),'COORD_TEMPLATE_AND_LAYER')
            g=row['grips'];check(isinstance(g,list) and len(g)==3 and all(isinstance(p,list) and len(p)==3 and all(number(v) for v in p) for p in g),'THREE_FINITE_GRIPS')
            u=[a-b for a,b in zip(g[0],g[1])];v=[a-b for a,b in zip(g[2],g[1])];nu=math.hypot(*u);nv=math.hypot(*v);check(nu>1e-6 and nv>1e-6,'ZERO_LENGTH_LEADER')
            dot=sum(a*b for a,b in zip(u,v))/(nu*nv);check(-1+1e-8<dot<=1e-8,'LEADER_MUST_BE_RIGHT_OR_OBTUSE')
        if 'new_layers' in params:
            layers=params['new_layers'];check(isinstance(layers,list) and layers,'COORD_LAYERS_REQUIRED')
            names=set()
            for layer in layers:
                check(isinstance(layer,dict) and {'name','color'}<=set(layer)<= {'name','color','freeze_viewports'},'COORD_LAYER_FIELDS')
                name=layer['name'];check(isinstance(name,str) and name.strip() and name not in ('0','Defpoints') and name not in names and any(i['layer']==name for i in params['items']),'ONLY_USED_COORD_LAYER_ALLOWED');names.add(name)
                check(type(layer['color']) is int and 1<=layer['color']<=255,'COORD_LAYER_ACI')
                vp=layer.get('freeze_viewports',[]);check(isinstance(vp,list) and all(isinstance(h,str) and re.fullmatch(r'[0-9A-Fa-f]+',h) for h in vp) and len(set(h.upper() for h in vp))==len(vp),'COORD_FREEZE_VIEWPORTS')
    elif kind == "plant_layers":
        check(isinstance(params["roles"],list) and params["roles"],"ROLES_REQUIRED")
        seen=set()
        for row in params["roles"]:
            check(isinstance(row,dict) and set(row)=={"layer","color","targets"} and isinstance(row["layer"],str) and row["layer"].strip() and row["layer"] not in ("0","Defpoints"),"ROLE_LAYER_FIELDS")
            check(isinstance(row["color"],int) and not isinstance(row["color"],bool) and 1<=row["color"]<=255,"ROLE_LAYER_COLOR")
            targets(row["targets"])
            for t in row["targets"]:
                check(t["type"] in ("AcDbBlockReference","AcDbCircle") and t["handle"].upper() not in seen,"ROLE_TYPE_OR_DUPLICATE")
                seen.add(t["handle"].upper())
    elif kind in ("native_details","viewport_details","table_read") or (kind=="text_read" and "handles" in params):
        if kind=="viewport_details":check(isinstance(params["layers"],list) and params["layers"] and all(isinstance(n,str) and n.strip() for n in params["layers"]),"EXACT_LAYER_NAMES_REQUIRED")
        check(isinstance(params["handles"],list) and params["handles"] and all(isinstance(h,str) and re.fullmatch(r"[0-9A-Fa-f]+",h) for h in params["handles"]),"HANDLES_REQUIRED")
        check(len({h.upper() for h in params["handles"]})==len(params["handles"]),"DUPLICATE_HANDLES")
    elif kind == "inspect":
        check(params["space"] == "Model", "INSPECT_SPACE: 本适配器只按模型WCS查询；纸空间用page_map；不能把DCS/ViewCenter当WCS")
        check(bool(params.get("handles")) or params.get("bounds") is not None, "SCOPED_INSPECTION_REQUIRED: x/y/width/height不是查询边界")
        if "handles" in params:
            check(isinstance(params["handles"], list) and all(isinstance(h, str) and re.fullmatch(r"[0-9A-Fa-f]+", h) for h in params["handles"]), "HANDLES_INVALID")
        if "bounds" in params: bounds(params["bounds"], strict=True)
        if "view" in params:
            view = params["view"]
            check(isinstance(view, dict) and set(view) == {"x", "y", "width", "height", "layout"}, "VIEW_FIELDS")
            check(isinstance(view["layout"], str) and 0 < len(view["layout"].strip()) <= 255 and not any(ord(c) < 32 for c in view["layout"]) and all(number(view[k]) for k in ("x", "y", "width", "height")) and view["width"] > 0 and view["height"] > 0, "VIEW_INVALID")
    elif kind == "erase":
        rows=params['targets'];check(isinstance(rows,list) and rows,'TARGET_LIST_EMPTY')
        if any(isinstance(t,dict) and 'block' in t for t in rows):
            check(all(isinstance(t,dict) and set(t)=={'handle','block','text'} for t in rows),'BLOCK_TEXT_TARGET_FIELDS')
            for t in rows:check(isinstance(t['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',t['handle']) and isinstance(t['block'],str) and t['block'] and isinstance(t['text'],str),'BLOCK_TEXT_IDENTITY')
            check(len({t['handle'].upper() for t in rows})==len(rows),'TARGET_DUPLICATE')
        else:targets(rows)
    elif kind == "layer_patch":
        rows=params["layers"]
        check(isinstance(rows,list) and 0<len(rows)<=64,"LAYER_PATCH_LIST")
        for row in rows:
            check(isinstance(row,dict) and set(row)=={"name","before","after"} and isinstance(row["name"],str) and row["name"].strip(),"EXACT_LAYER_PATCH_FIELDS")
            for key in ("before","after"):
                flags=row[key]
                check(isinstance(flags,dict) and {"on","frozen"}<=set(flags) and set(flags)<={"on","frozen","color"} and all(type(flags[k]) is bool for k in ("on","frozen")),"EXACT_LAYER_FLAGS")
                if 'color' in flags:check(type(flags['color']) is int and 1<=flags['color']<=255,'LAYER_COLOR_INVALID')
            check(('color' in row['before'])==('color' in row['after']),'COLOR_BEFORE_AFTER_REQUIRED')
        check(len({r["name"].casefold() for r in rows})==len(rows),"DUPLICATE_LAYER")
    elif kind == "paper_read":
        check(params["source_layout"]!="Model","PAPER_LAYOUT_REQUIRED")
        check(isinstance(params["handles"],list) and 0<len(params["handles"])<=128 and all(isinstance(h,str) and re.fullmatch(r"[0-9A-Fa-f]+",h) for h in params["handles"]),"PAPER_HANDLES_REQUIRED")
    elif kind in ("paper_copy", "paper_note", "paper_entities_copy"):
        check(params["source_layout"]!="Model" and params["target_layout"]!="Model","PAPER_LAYOUT_REQUIRED")
        target(params["source_frame"]);targets(params["source_targets"]);targets(params["target_frames"])
        check(params["source_frame"]["type"]=="AcDbBlockReference" and all(t["type"]=="AcDbBlockReference" for t in params["target_frames"]),"EXACT_FRAME_BLOCKS_REQUIRED")
        check(all(t["type"] in ({"AcDbText","AcDbMText","TDbText","AcDbLine","AcDbPolyline","TDbSymbCoord","TDbSymbMultiLeader"} if kind=="paper_entities_copy" else {"AcDbText","AcDbMText","TDbText"}) for t in params["source_targets"]),"ONLY_NATIVE_TEXT_NOTES_SUPPORTED")
        if kind=='paper_note':
            check(len(params['source_targets'])==1 and isinstance(params['note_text'],str) and 0<len(params['note_text'])<=1000 and not any(ord(c)<32 for c in params['note_text']),'SINGLE_PLAIN_NOTE_REQUIRED')
    elif kind=='entity_display':
        rows=params['entities'];check(isinstance(rows,list) and rows,'ENTITY_DISPLAY_REQUIRED')
        for row in rows:
            check(isinstance(row,dict) and {'target','before_color','target_layer','color'}<=set(row)<={'target','before_color','target_layer','color','definition','before_linetype_scale','linetype_scale'},'ENTITY_DISPLAY_FIELDS')
            target(row['target']);check(row['target']['type'] in ('AcDbPolyline','AcDbArc','AcDbLine','AcDbHatch') or row['target']['type']=='AcDbBlockReference' and 'definition' in row,'DISPLAY_NATIVE_TYPE_UNSUPPORTED')
            check(('before_linetype_scale' in row)==('linetype_scale' in row),'LINETYPE_SCALE_BEFORE_AFTER_REQUIRED')
            if 'linetype_scale' in row:check(all(number(row[k]) and row[k]>0 for k in ('before_linetype_scale','linetype_scale')),'POSITIVE_FINITE_LINETYPE_SCALE_REQUIRED')
            check(isinstance(row['target_layer'],str) and row['target_layer'].strip(),'DISPLAY_TARGET_LAYER_REQUIRED')
            check(all(type(row[k]) is int and 0<=row[k]<=256 for k in ('before_color','color')),'DISPLAY_COLOR_INVALID')
        targets([row['target'] for row in rows])
        definitions=params.get('definitions',[]);check(isinstance(definitions,list),'DISPLAY_DEFINITIONS_LIST')
        for d in definitions:
            check(isinstance(d,dict) and {'handle','name','instances'}<=set(d)<={'handle','name','instances','space'},'DISPLAY_DEFINITION_FIELDS')
            check(d.get('space','model') in ('model','paper'),'DISPLAY_REFERENCE_SPACE')
            check(isinstance(d['handle'],str) and re.fullmatch(r'[0-9A-Fa-f]+',d['handle']) and isinstance(d['name'],str) and d['name'],'DISPLAY_DEFINITION_IDENTITY')
            refs=d['instances'];check(isinstance(refs,list) and refs and all(isinstance(h,str) and re.fullmatch(r'[0-9A-Fa-f]+',h) for h in refs) and len(set(h.upper() for h in refs))==len(refs),'EXACT_DEFINITION_INSTANCES_REQUIRED')
        owners={d['handle'].upper() for d in definitions};check(len(owners)==len(definitions),'DUPLICATE_DISPLAY_DEFINITION')
        used=set()
        for row in rows:
            if 'definition' in row:
                check(isinstance(row['definition'],str) and row['definition'].upper() in owners,'DISPLAY_DEFINITION_NOT_DECLARED');used.add(row['definition'].upper())
        check(used==owners,'UNUSED_DISPLAY_DEFINITION')
        new=params.get('new_layers',[]);check(isinstance(new,list),'NEW_LAYERS_LIST')
        for row in new:check(isinstance(row,dict) and set(row)=={'name','color'} and isinstance(row['name'],str) and row['name']!='0' and row['name'].strip() and type(row['color']) is int and 1<=row['color']<=255,'NEW_LAYER_FIELDS')
        check(len({row['name'].casefold() for row in new})==len(new),'DUPLICATE_NEW_LAYER')
        check({row['name'].casefold() for row in new}<={row['target_layer'].casefold() for row in rows},'NEW_LAYER_NOT_USED_BY_TARGETS')
    elif kind in ('viewport_camera','viewport_layers'):
        check(params['source_layout']!='Model' and params['target_layout']!='Model','PAPER_VIEWPORT_LAYOUT_REQUIRED')
        check(isinstance(params['pairs'],list) and params['pairs'],'VIEWPORT_PAIRS_REQUIRED')
        for pair in params['pairs']:
            optional={'world_offset','custom_scale'} if kind=='viewport_camera' else set()
            check(isinstance(pair,dict) and {'source','target'}<=set(pair) and set(pair)<={'source','target'}|optional,'VIEWPORT_PAIR_FIELDS')
            for key in ('source','target'):target(pair[key]);check(pair[key]['type']=='AcDbViewport','NATIVE_VIEWPORT_REQUIRED')
            if 'world_offset' in pair:
                value=pair['world_offset']
                check(isinstance(value,list) and len(value)==3 and all(type(v) in (int,float) and math.isfinite(v) for v in value) and value[2]==0,'PLAN_WORLD_OFFSET_REQUIRED')
            if 'custom_scale' in pair:check(type(pair['custom_scale']) in (int,float) and math.isfinite(pair['custom_scale']) and pair['custom_scale']>0,'POSITIVE_CAMERA_SCALE_REQUIRED')
        targets([p['target'] for p in params['pairs']])
        if kind=='viewport_layers':
            rows=params['layer_pairs'];protected=params['protected_layers']
            check(isinstance(rows,list) and rows and isinstance(protected,list) and all(isinstance(x,str) and x for x in protected),'LAYER_MAPPING_AND_PROTECTION_REQUIRED')
            for row in rows:
                check(isinstance(row,dict) and {'source','target'}<=set(row) and set(row)<={'source','target','color','frozen'} and all(isinstance(row[k],str) and row[k] for k in ('source','target')),'LAYER_MAPPING_FIELDS')
                if 'color' in row:check(type(row['color']) is int and 0<=row['color']<=256,'VIEWPORT_COLOR_INVALID')
                if 'frozen' in row:check(type(row['frozen']) is bool,'VIEWPORT_FREEZE_INVALID')
            check(len({row['target'].casefold() for row in rows})==len(rows),'DUPLICATE_TARGET_LAYER')
            check(not ({row['target'].casefold() for row in rows}&{x.casefold() for x in protected}),'PROTECTED_PLANT_LAYER_SELECTED')
    elif kind == "polyline_create":
        rows=params['creations']
        if not isinstance(rows,list) or not rows: raise ValueError('creations required')
        for row in rows:
            if set(row)!={'template','closed','vertices'} or type(row['closed']) is not bool: raise ValueError('exact template, closed, vertices required')
            targets([row['template']])
            vertices=row['vertices']
            if not isinstance(vertices,list) or len(vertices)<(3 if row['closed'] else 2): raise ValueError('too few vertices')
            for v in vertices:
                if not isinstance(v,list) or len(v)!=5 or any(type(n) not in (int,float) or not math.isfinite(n) for n in v) or min(v[3:])<0: raise ValueError('explicit finite OCS x,y,bulge,widths required')
            for a,b in zip(vertices,vertices[1:]+(vertices[:1] if row['closed'] else [])):
                if a[:2]==b[:2]: raise ValueError('zero length segment')
    elif kind in ("polyline_edit","polyline_offset"):
        rows=params['edits' if kind=='polyline_edit' else 'offsets']
        check(isinstance(rows,list) and rows,'POLYLINE_OPERATIONS_REQUIRED')
        for row in rows:
            fields={'target','expected_closed','vertices'} if kind=='polyline_edit' else {'target','distance'}
            check(isinstance(row,dict) and set(row)==fields,'POLYLINE_OPERATION_FIELDS')
            target(row['target']);check(row['target']['type']=='AcDbPolyline','NATIVE_POLYLINE_REQUIRED')
            if kind=='polyline_offset':
                check(number(row['distance']) and row['distance']!=0,'FINITE_NONZERO_OFFSET_REQUIRED')
            else:
                check(type(row['expected_closed']) is bool,'EXPECTED_CLOSED_REQUIRED')
                v=row['vertices']
                check(isinstance(v,list) and len(v)>=(3 if row['expected_closed'] else 2),'VERTEX_COUNT')
                check(all(isinstance(x,list) and len(x)==5 and all(number(y) for y in x) and x[3]>=0 and x[4]>=0 for x in v),'VERTEX_DATA')
                check(all(v[i][:2]!=v[(i+1)%len(v)][:2] for i in range(len(v) if row['expected_closed'] else len(v)-1)),'ZERO_LENGTH_SEGMENT')
        if kind=='polyline_edit':targets([r['target'] for r in rows])
    elif kind == "polyline_sync":
        check(isinstance(params["pairs"],list) and params["pairs"],"POLYLINE_PAIRS_REQUIRED")
        for pair in params["pairs"]:
            check(isinstance(pair,dict) and {"source","target"}<=set(pair)<={"source","target","preserve_target_endpoints"},"POLYLINE_PAIR_FIELDS")
            ends=pair.get('preserve_target_endpoints',[])
            check(isinstance(ends,list) and all(isinstance(x,str) and x in ('start','end') for x in ends) and len(set(ends))==len(ends),'ENDPOINT_NAMES')
            for t in (pair['source'],pair['target']):
                target(t);check(t["type"]=="AcDbPolyline","ONLY_NATIVE_MODEL_LWPOLYLINE_SUPPORTED")
        targets([p["target"] for p in params["pairs"]])
    elif kind == "base_replace":
        targets(params['source_targets']);targets(params['old_targets'],empty=True);targets(params['protected_targets'],empty=True)
        targets(params['deferred_targets'],empty=True)
        protected={t['handle'].upper():t for t in params['protected_targets']}
        check(all(t['handle'].upper() in protected and t==protected[t['handle'].upper()] for t in params['deferred_targets']),'DEFERRED_MUST_MATCH_PROTECTED')
        check(not ({t['handle'].upper() for t in params['old_targets']} & {t['handle'].upper() for t in params['protected_targets']}),'OLD_PROTECTED_COLLISION')
        selected={t['handle'].upper() for t in params['source_targets']}
        check(isinstance(params.get('source_groups',[]),list),'SOURCE_GROUPS_LIST')
        for group in params.get('source_groups',[]):
            check(isinstance(group,dict) and set(group)=={'name','handles'} and isinstance(group['name'],str) and group['name'] and isinstance(group['handles'],list) and group['handles'],'SOURCE_GROUP_FIELDS')
            check(all(isinstance(h,str) and h.upper() in selected for h in group['handles']) and len(set(h.upper() for h in group['handles']))==len(group['handles']),'GROUP_MEMBER_NOT_COPIED')
    elif kind == "transfer":
        targets(params["old_targets"], empty=True); targets(params["source_targets"])
    elif kind == "copy_transform":
        check(isinstance(params["pairs"], list) and params["pairs"], "PAIRS_EMPTY")
        all_targets = []
        for pair in params["pairs"]:
            check(isinstance(pair, dict) and set(pair) == {"source_grid", "source_frame", "target_frame"}, "PAIR_FIELDS")
            all_targets.extend(pair.values())
            for value in pair.values(): target(value)
            g, f, t = (pair[k]["bounds"] for k in ("source_grid", "source_frame", "target_frame"))
            check(abs(t[0] - f[0]) <= .001, "COPY_DISPLACEMENT_NOT_VERTICAL")
            def contains(a, b): return b[0]>=a[0]-.001 and b[1]>=a[1]-.001 and b[2]<=a[2]+.001 and b[3]<=a[3]+.001
            check(contains(f, g), "COPY_SOURCE_OUTSIDE_FRAME")
            moved = [g[i] + t[i % 2] - f[i % 2] for i in range(4)]
            check(contains(t, moved), "COPY_TARGET_OUTSIDE_FRAME")
        targets(all_targets)
    elif kind == "hatch":
        check(re.fullmatch(r"[0-9A-Fa-f]+", params["template"]), "TEMPLATE_HANDLE")
        if "expected_color" in params: check(type(params["expected_color"]) is int and 0 <= params["expected_color"] <= 256, "COLOR_INVALID")
        if "replace_target" in params: target(params["replace_target"])
        check(isinstance(params["parts"], list) and params["parts"], "HATCH_PARTS_EMPTY")
        for part in params["parts"]:
            check(isinstance(part, dict) and set(part) == {"loops"} and isinstance(part["loops"], list) and part["loops"], "HATCH_LOOPS_EMPTY")
            for loop in part["loops"]:
                check(isinstance(loop, list) and len(loop) >= 3, "CLOSED_LOOP_TOO_SHORT")
                for point in loop:
                    check(isinstance(point, list) and len(point) in (2, 3) and all(number(v) for v in point), "LOOP_POINT_INVALID")


# Operation-specific effects and boundaries consumed by the existing describe command.
OPERATION_CONTRACTS = {'inspect': {'native_handler': 'InspectRegion', 'effect': 'read objects; optionally set view', 'scope': 'Model WCS; view uses its layout coordinates', 'completion': 'native inspection receipt; actual image requires capture'}, 'page_map': {'native_handler': 'PageMap', 'effect': 'read layout frames, viewport and grid identities', 'scope': 'named layout, declared block/title selectors', 'completion': 'mapping receipt; semantic sheet pairing remains project work'}, 'erase': {'native_handler': 'EraseExact', 'effect': 'erase exact checked entities and save', 'scope': 'handle/type/layer/bounds identity in bound isolated drawing', 'completion': 'SaveModified receipt plus affected-object and visual review'}, 'hatch': {'native_handler': 'HatchWorkplane', 'effect': 'create hatches from explicit loops/template and save', 'scope': 'provided loops and optional exact replacement target', 'completion': 'SaveModified receipt; source area and overlap still require project checks'}, 'transfer': {'native_handler': 'TransferExact', 'effect': 'clone exact source entities to current model; remove specified old targets; save', 'scope': 'allowlisted source in same session, model space only', 'completion': 'SaveModified receipt; allowlisting does not establish correct engineering source'}, 'copy_transform': {'native_handler': 'CopyTransform', 'effect': 'copy grids vertically between matched frames and save', 'scope': 'same layout, vertical displacement only; not general copying', 'completion': 'SaveModified receipt; drawing source remains a separate project judgment'}, 'switch': {'native_handler': 'SwitchDocument', 'effect': 'protect current document, open allowlisted next document', 'scope': 'same private host and bound session', 'completion': 'switch receipt plus newer settled native status; early receipt alone is insufficient'}, 'close': {'native_handler': 'CloseSafely', 'effect': 'protect document and request task-host exit', 'scope': 'bound task document and authorized lifecycle action', 'completion': 'lifecycle protection receipt AND process actually exited; not ordinary READY'}}

OPERATION_CONTRACTS.update({
'plant_layers': {'native_source':'PlantLayerSplitV1.cs','native_handler':'Apply','effect':'isolate selected static symbol definitions per role and assign instance layer','scope':'exact INSERT/CIRCLE list; preserve other users, original definitions, transforms and nonplot children; dynamic, attributed or nested blocks need another adapter','completion':'native save/reopen of instances, clones and preserved originals; engineering category mapping remains execution/review'},
'native_details': {'native_source':'NativeDetailsReadV1.cs','native_handler':'Read','effect':'read native Tianzheng grips, values and in-memory display parts','scope':'exact handles in current bound document; no save or mutation','completion':'native receipt with values, unavailable fields explicit and unchanged source'},
'paper_note': {'native_source':'BoundCadEditsV6.cs','native_handler':'ApplyPaperCopies','effect':'clone one native text template and set explicit single-line text at matched frame positions','scope':'DBText/MText/TDbText; original source unchanged; exact frame identities','completion':'native save/reopen text readback; engineering wording and layout require execution/review'},
'entity_display': {'native_source':'EntityDisplayOpsV1.cs','native_handler':'Apply','effect':'set exact entity layer/ACI; optional definitions identifies ordinary block children and every affected model reference','scope':'root model entities by default; block children require definition handle/name and complete model-instance handles; preserve geometry, widths, Z, other children and instance transforms','completion':'native save/reopen then execution/reviewer validation on affected sheets'},
'viewport_camera': {'native_source':'BoundViewportOpsV5.cs','native_handler':'Apply','effect':'copy only source view target/direction/center/twist/scale; retain target paper window, clip, lock and frozen layers','scope':'exact source/target AcDbViewport identities and explicit paper layouts','completion':'saved native readback and actual affected sheets; source pairing is engineering input'},
'viewport_layers': {'native_source':'BoundViewportOpsV5.cs','native_handler':'Apply','effect':'map baseline per-viewport freeze and overrides onto explicitly named new layers; optional exact frozen/color replaces baseline values','scope':'exact viewport and layer pairs; protected plant layers excluded; global layer flags unchanged; named plot-style overrides require explicit mapping and stop','completion':'saved native readback plus actual affected sheets; 5m/2m use must be chosen by execution/review'},
'base_replace': {'native_source':'BaseReplaceV3.cs','native_handler':'Build','effect':'classify all target model entities; remove exact old base, PU unused definitions, clone latest source with isolated definitions, rebuild groups, save/reopen and activate candidate','scope':'explicit source/old/protected identities including true zero bounds; preserves paper objects; source/target hashes bound automatically','completion':'native complete mapping, protected checks, save/reopen and active candidate; per-viewport new-layer visibility sync and engineering coverage require self-check/review'},
'layer_patch': {'native_source': 'BoundCadEditsV6.cs', 'native_handler': 'ApplyLayers', 'effect': 'set exact global layer on/frozen/optional ACI with before-state assertions; save/reopen', 'scope': 'current bound drawing; global flags and ACI only; no per-viewport change', 'completion': 'Exact receipt; affected native readback and actual sheet review still required'},
'paper_read': {'native_source': 'BoundCadEditsV1.cs', 'native_handler': 'ReadPaper', 'effect': 'read native note text parts from exact source-layout handles', 'scope': 'approved source; no drawing mutation or switching', 'completion': 'Exact receipt; affected native readback and actual sheet review still required'},
'paper_copy': {'native_source': 'BoundCadEditsV6.cs', 'native_handler': 'ApplyPaperCopies', 'effect': 'clone whole native notes to corresponding paper-space frame positions; save', 'scope': 'approved source; DBText/MText/TDbText only; equal-size frames; translation only', 'completion': 'Exact receipt; affected native readback and actual sheet review still required'},
'polyline_sync': {'native_source': 'BoundCadEditsV1.cs', 'native_handler': 'ApplyPolylineGeometry', 'effect': 'copy complete source LWPOLYLINE geometry onto existing target; save', 'scope': 'model space only; preserve target handle, layer and display properties', 'completion': 'Exact receipt; affected native readback and actual sheet review still required'},
})

OPERATION_CONTRACTS["viewport_details"]={"native_source":"NativeDetailsReadV1.cs","native_handler":"ReadViewports","effect":"read exact viewport freeze and display overrides","scope":"named viewports and layers in current drawing; no save or mutation","completion":"native source-bound receipt; absent layers explicit"}

OPERATION_CONTRACTS["coord_create"]={"native_source":"NativeCoordCreateV1.cs","native_handler":"Apply","effect":"clone whole native coordinate templates, move 3 grips, explicitly update X/Y and save","scope":"current model TDbSymbCoord with verified YX axis; existing or explicitly declared destination layer with selected viewport freezes; original templates unchanged","completion":"saved native root plus measured values/grips/display; sheet positioning remains execution/review"}

OPERATION_CONTRACTS["viewport_freeze"]={"native_source":"PresentationPatchV1.cs","native_handler":"Apply","effect":"set exact per-viewport layer freeze in current document without switching drawings","scope":"explicit paper layout, viewport/layer and before/after state; preserve global layers and cameras","completion":"native save/reopen and scoped readback"}
OPERATION_CONTRACTS["text_patch"]={"native_source":"PresentationPatchV1.cs","native_handler":"Apply","effect":"replace native paper DBText/MText in place","scope":"exact handle/type/layer/position/old text; preserve formatting and other objects","completion":"native save/reopen and actual sheet review"}

OPERATION_CONTRACTS["groundcover_create"]={"native_source":"NativeGroundcoverCreateV1.cs","native_handler":"Apply","effect":"clone intact native single-branch upper-text groundcover leader; set UpText then sequentially move elbow/bearing/anchor","scope":"current model template, 4 verified grips including native text control; no lower text; native two-segment topology verified; explicit 90-degree targets","completion":"saved native root and actual properties/grips; placement, area/source and sheet expression belong to execution/review"}
OPERATION_CONTRACTS["table_read"]={"native_source":"NativeDetailsReadV1.cs","native_handler":"ReadTables","effect":"read AcDbTable row/column indexed TextString cells","scope":"exact current handles; 0-based rows and columns; no writing or total calculations","completion":"bound read-only receipt; engineering quantities not inferred"}
OPERATION_CONTRACTS["inspect"].update(native_source="NativeViewV1.cs",native_handler="Run")
OPERATION_CONTRACTS["hatch"].update(native_source="HatchWorkplaneV2.cs",native_handler="Run")
OPERATION_CONTRACTS["text_patch"]["effect"]="replace paper DBText/MText or native TDbDrawingName.NameText in place"
OPERATION_CONTRACTS["paper_transform"]={"native_source":"PaperTransformOpsV1.cs","native_handler":"Apply","effect":"per-object native paper coordinate edits: x'=scale_x*x+offset_x, y'=y+offset_y, Z unchanged","scope":"params {layout,transforms:[{handle,type,layer,before,scale_x,offset_x,offset_y}]}; before is the complete geometry object from the current native geometry read. Positive X scale, +Z plane; straight AcDbPolyline or non-associative SOLID AcDbHatch with LINE loops only. All original geometries checked before any write; preserve native handles, display, widths, Z and unselected objects. No universal affine transform or arc conversion.","completion":"native save/reopen exact geometry and properties verified; engineering targets and sheet review remain with execution/review"}

OPERATION_CONTRACTS["table_patch"]={"native_source":"NativeTablePatchV1.cs","native_handler":"Apply","effect":"patch exact AcDbTable TextString cells after whole-batch before-state checks; rebuild native table cache; save and reopen-verify","scope":"0-based row/column; exact handle/layer/dimensions; reject fields, formulas, linked or block-content targets; optional exact tail removal with all old cell texts and block IDs; delete_rows:{rows:[{row:original zero-based data row,before:all old cell texts,block_ids:all original block handles or null}],renumber:boolean} deletes selected middle rows in descending original order; optional renumber changes only column 0 data-row serials; separate batch without cells/delete_tail/legend_hatches; rejects data-row merges; optional legend_hatches:[{block,handle,rectangle:[xmin,ymin,xmax,ymax]}] changes only named block-local Z0 nonassociative hatch loops, preserves patterns and siblings, refreshes automatic cell fitting; optional reload_pattern:true explicitly reloads same named native pattern at local origin, preserving scale/angle/color but replacing old pattern definitions; optional pattern_scale:positive changes only native PatternScale; rectangle is optional for scale-only edits and existing loops stay unchanged; cells may be omitted for legend-only edits; no row insertion or merging","completion":"saved cells, retained formats/legends/geometry and native cache verified; engineering contents and actual sheet review remain execution/review"}

OPERATION_CONTRACTS["groundcover_update"]={"native_source":"NativeGroundcoverCreateV1.cs","native_handler":"Update","effect":"update native leader in place: optional UpText/DownText, native Scale with expected original scale, or single-upper-text 90-degree grips; unchanged fields retained","scope":"current TDbSymbMultiLeader and read-back expected values/grips; text-only keeps first 3 geometry grips; no clone/delete; native text-control grips may update with text","completion":"native text, geometry and style save/reopen verified; engineering wording and placement belong to execution/review"}
OPERATION_CONTRACTS['table_patch']['scope']+='; color-only legend_hatches:[{block,handle,before_color:0..256,color:1..255}] requires explicit original ACI/ByLayer/ByBlock and target ACI. Separate color-only batch, no cell/row/geometry/pattern edits; reject RGB originals or references outside the selected table and its native cache. Preserve full patterns, loops, siblings, cell content/format/scale and table geometry; refresh table cache and verify save/reopen.'
OPERATION_CONTRACTS["text_read"]={"native_source":"NativeTextFormatV1.cs","native_handler":"Read","effect":"read text/format, exact entity bounds and block-reference scope","scope":"current handles or approved source; no switching/save; bounds null if native extents unavailable","completion":"source-bound native read-only receipt; block-local bounds can be passed directly to erase for that exact child"}
OPERATION_CONTRACTS["text_format"]={"native_source":"NativeTextFormatV1.cs","native_handler":"Apply","effect":"set MText format; optional Contents removes inline formatting only if native plain_text remains identical; optional explicit location","scope":"exact text/owner/before format; shared references collected and protected internally, optional supplied instances checked; static non-xref definitions","completion":"plain text, unselected objects and reference transforms preserved; native save/reopen verified; actual sheet expression belongs to execution/review"}

OPERATION_CONTRACTS['erase']['scope']='generic exact handle/type/layer/bounds; block text alternatively uses only handle/block/text, automatically preserves sibling entities and references'
OPERATION_CONTRACTS['groundcover_update']['scope']='text-only: handle/layer/expected up+down and new strings; geometry/style captured and retained internally. Grip moves keep their existing explicit geometry contract.'
OPERATION_CONTRACTS['text_read']['completion']='native read-only receipt; reference identities retained, large transformation snapshots stay inside native protection checks'

OPERATION_CONTRACTS['text_read']['scope']='choose exactly one: handles for object content, or styles for native style properties (empty list lists all); optional approved source, no mutation or save'

OPERATION_CONTRACTS["text_style_import"]={"native_source":"NativeTextStylesV1.cs","native_handler":"Import","effect":"reuse equivalent native render properties or clone source style; never replace an existing definition","scope":"approved source and exact style names; import mapping returns actual target names; no entity edits","completion":"existing styles protected, native save/reopen checked"}

OPERATION_CONTRACTS["text_patch"]["scope"]="exact paper text identity; TDbDrawingName optionally sets name_style, scale_style, name_height, scale_height independently; omitted fields, native content, anchor, spacing, Scale and shared style definitions preserved. Glyph width and derived scale-text x can change naturally with font."

OPERATION_CONTRACTS["text_patch"]["scope"] += " AcDbText also accepts optional text_style:string text_height:positive number and text_width_factor:positive number; omitted fields, content, native justification/anchor, layer and shared styles preserved. For center/right justification the computed start point follows glyph metrics; actual alignment anchor stays fixed. Use before=after for format-only edits."

OPERATION_CONTRACTS["table_read"]["effect"]="read native table cells and content/cell/table-style inheritance with provenance; preserve raw null style and height; text_styles maps native font records. Unresolved fonts add representative rendered_samples from an isolated database of the exact saved input, without replacing raw fields or inferring all cells; legend_sample identifies a native Block cell. No production table decomposition or writes."
OPERATION_CONTRACTS['source_register']={'native_source':'NativeSourceRegisterV1.cs','native_handler':'Run','effect':'register an explicitly selected same-session DWG and digest in the existing host; no open/save/switch','scope':'path, expected_sha256, role(garden/planting/reference); no replacing an existing differing registration','completion':'native unchanged-document receipt; then use existing switch/transfer. Registration is not engineering approval.'}
OPERATION_CONTRACTS['polyline_sync']['scope'] += '; optional pair.preserve_target_endpoints:["start","end"] retains specified original target endpoint point/bulge/start_width/end_width at new first/last index. Requires both open and same normal/elevation; other vertices from source. This does not fit curves or prove tangent continuity. Omit for unchanged whole-source behavior.'

OPERATION_CONTRACTS['polyline_edit']={'native_source':'PolylineGeometryV1.cs','native_handler':'Replace','effect':'update exact model LWPOLYLINE vertices in target OCS; preserve handle, display, normal/elevation, thickness and closed state','scope':'edits[].target, expected_closed, vertices=[[x,y,bulge,start_width,end_width],...]; widths explicit, no fitting/tangent inference','completion':'saved receipt includes before/after; execution/review checks shape and connections'}
OPERATION_CONTRACTS['polyline_offset']={'native_source':'PolylineGeometryV1.cs','native_handler':'OffsetCurves','effect':'native GetOffsetCurves on exact model LWPOLYLINE, append ALL returned curves; source unchanged','scope':'offsets[].target,distance (finite nonzero signed native drawing units); source properties inherited; no trimming or choosing one result','completion':'saved receipt with signed distance and all output handles/types/geometry; signed distance does not imply engineering inside/outside'}

OPERATION_CONTRACTS['hatch_pattern']={'native_source':'HatchPatternPatchV1.cs','native_handler':'Apply','effect':'set native predefined pattern name/scale on exact existing model HATCH','scope':'hatches:[{target:{handle,type,layer,bounds},before:{pattern,scale},after:{pattern,scale}}]; preserves boundary loops, islands, area, association, origin, angle, layer and display; no replacement hatch or engineering scale inference','completion':'native receipt and protected geometry; isolated save/reopen tested, real sheet appearance belongs to execution/review'}

OPERATION_CONTRACTS['groundcover_update']['scope'] += '; optional items[].layout selects an exact existing paper Layout owner; omitted means Model. Grips remain that owner native coordinates, no viewport conversion; topology/identity/non-target guards unchanged.'

OPERATION_CONTRACTS['polyline_create']={'native_source':'PolylineGeometryV1.cs','native_handler':'CreateCurves','effect':'create separate native model LWPOLYLINE objects; exact template supplies display and OCS plane; source unchanged','scope':'creations:[{template:{handle,type,layer,bounds},closed:false,vertices:[[x,y,bulge,start_width,end_width],...]}]; no fitting, implicit joining or inferred side','completion':'saved receipt returns each new identity and full geometry; execution/review validates engineering connections'}

OPERATION_CONTRACTS['paper_entities_copy']={'native_source':'BoundCadEditsV1.cs','native_handler':'ApplyPaperCopies','effect':'clone exact paper-space line/polyline/text/native coordinate entities between equal-size named frames, translation only','scope':'same parameters as paper_copy; no grid generation or implicit scaling; exact layout/type/layer/bounds required; preserves whole native coordinate','completion':'saved copied identities, source unchanged; natural layout correctness by execution/review'}

OPERATION_CONTRACTS['groundcover_update']['scope'] += '; geometry moves reread native followers and skip satisfied grips. Four-grip single-upper leaders: 0 baseline, 1 ledge, 2 anchor; text follows baseline/ledge. Fourth grip is not a text translation control; text_grip is rejected.'

OPERATION_CONTRACTS['groundcover_update']['scope'] += '; optional rotation in degrees [-360,360], one exact item with full expected four grips and explicit three target grips; cannot combine text/scale edits. Native LayoutRotation applied before principal grips; original displayed text/font/height/width and entity style retained.'

OPERATION_CONTRACTS['hatch_pattern']['scope'] += '; optional hatches[].layout selects the exact existing paper owner, omitted means Model. Scale remains in that space; caller supplies paper/model equivalence. Three-loop paper hatch and wrong-owner rollback saved/reopened.'

OPERATION_CONTRACTS['index_anchor']={'native_source':'IndexAnchorV1.cs','native_handler':'Apply','effect':'move native landing-circle center once; line contact follows automatically','scope':'indexes:[{handle,layout,layer,expected_grips:[[x,y,z],...7],anchor:[x,y,z]}]; TDbSymbIndexPointer with verified single landing circle and seven grips; control 2, follower 3. Preserve text, index number, symbol, style and other five grips. No caller-supplied follower move, no decomposition, no viewport conversion. Other index topologies are not implied.','completion':'saved receipt returns actual linked grips and control move count; real source isolated save/reopen verified; engineering placement remains execution/review'}

OPERATION_CONTRACTS['paper_entities_copy']['scope'] += '; TDbSymbMultiLeader supported as one native object. Exact source 2384A same-frame copy saved/reopened: text, native grips and geometry retained; no exploding or re-creating leader parts.'

OPERATION_CONTRACTS['entity_display']['scope'] += '; optional paired before_linetype_scale and linetype_scale set exact positive finite entity LinetypeScale; omitted retains current value. Whole batch checks old values before writes; geometry, linetype name, lineweight, visibility/transparency and untargeted objects remain protected.'

OPERATION_CONTRACTS['coord_update']={'native_source':'NativeCoordUpdateV1.cs','native_handler':'Apply','effect':'update the same paper TDbSymbCoord: three paper grips plus full-precision real world X/Y; no clone','scope':'axis_order YX; items:[{template_handle,layout,layer,expected:{x_value,y_value,rotation,grips},world_xy:[E,N],grips:[[paper_x,paper_y,z],...3]}]. Native XValue=N,YValue=E, never derived from paper grip. Preserve original native style, cross, layers, unrelated entities/viewports; single measured cross and two label topology tested. No projection or engineering point selection inside module.','completion':'exact native values, generated labels and grips verified; actual full-document isolated save/reopen tested; placement engineering stays execution/review'}

OPERATION_CONTRACTS['coord_update']['scope'] += '; Fallback only: user prefers native coordinate re-annotation or verified Tianzheng dynamic annotation for changing the measured point. Old non-updating grip samples did not establish dynamic mode state. Do not default to hand-computing paper/world positions, and do not redo already-correct saved work.'

OPERATION_CONTRACTS["native_annotation_update"]={'native_source': 'NativeAnnotationUpdateV1.cs', 'native_handler': 'Apply', 'effect': 'in-place native elevation Text/Scale, six-grip index UpText/g1 bearing, five-grip Arrow Text/Text2; optional single-object target_layer', 'scope': 'annotations rows require handle/type/layout/layer, expected original native properties and expected_grips. Elevation keys Text/TextHeight/Scale/LayoutRotation (3 grips); Index keys UpText/DownText/Height/Scale/LayoutRotation (6 or verified 7 grips); Arrow keys Text/Text2/Height/Scale/LayoutRotation (5 grips). Optional text/scale for elevation, or rotation (absolute LayoutRotation degrees [-360,360], elevation only, cannot combine text/scale). Rotation preserves true grip0 and rigidly rotates all three native grips; expected LayoutRotation is the old angle, rotation is the requested angle. Optional up_text/bearing for six-grip index; seven-grip single-landing-circle index supports bearing only (no up_text), with native topology check. bearing is absolute g1 target: g0/g4/g5/g6 follow, g2 stays fixed, g3 follows radially. Other seven-grip topologies are rejected. Optional text/text2 for arrow; optional target_layer for each. Target layer must exist; layer states and unselected entities stay unchanged. Native anchors, index references and styles protected. No decomposition or engineering inference.', 'completion': 'native properties/grips/reference/style plus isolated save-reopen and original CLI verified; engineering and visual acceptance remains execution/review'}

OPERATION_CONTRACTS["paper_patch"]={"native_source":"NativePaperPatchV1.cs","native_handler":"Apply","effect":"exact paper root display properties or erase selected roots; no automatic deduplication","scope":"items require layout/handle/type/layer/action; display uses explicit before/after color, linetype or linetype_scale pairs; erase supports floating viewports and native block roots including owned attributes; viewport clip must be selected together; model, block definitions, paper viewport 1 and layout deletion are excluded","completion":"exact native readback, unselected entity guard, retained paper snapshot and save/reopen; design selection and graphical review remain execution/review"}

OPERATION_CONTRACTS["entity_display"]["scope"] += "; definitions optional space=paper requires every static reference to be in paper layouts, complete instance handles; supports explicit nested block-reference child color without editing its definition or contents; omitted space retains model-only behavior"

OPERATION_CONTRACTS["table_expand"]={"native_source":"NativeTableExpandV1.cs","native_handler":"Apply","effect":"insert explicit empty columns into native table, format widths/heights/font and optionally position, patch explicit text cells; preserve original data/legend columns in order","scope":"tables require handle/layout/layer/row_count/column_count, column_map (original zero-based indices in order, null=new), column_widths and row_heights. Optional text_height/title_height/text_style/position/cells, cell_alignment=MiddleCenter, row_height_mode=exact(default)|at_least, legend_fits=[{row,column,block,fit_ratio}]. Legend cells use result coordinates and stable existing block IDs; 0<fit_ratio<1; native AutoFit is measured then disabled. at_least reports actual/minimum row heights without shrinking fonts. Full first-row title merge or unmerged table only; no row reorder, formula/data links or invented specifications; existing legend blocks preserved","completion":"native data/legend mapping, geometry orientation and unselected roots protected; save-reopen verified; engineering contents and graphic acceptance remain execution/review"}
OPERATION_CONTRACTS['table_rows_move']={'native_source':'NativeTableRowsMoveV1.cs','native_handler':'Apply','effect':'native whole-row copy then descending deletion using original indices; preserve values, legend blocks and cell formatting','scope':'source_table/target_table:{handle,layout,layer,row_count,column_count}; same column count/schema. rows are original zero-based data rows >=2 in desired insertion order; insert_before is original target row; renumber boolean explicitly renumbers column0 from data row2. No formulas/links or merged data rows. Quantities/area units remain caller responsibility.','completion':'save-reopen, row mapping/content/legend/style/height/column-width and unselected entity guards; engineering validation belongs to execution/review'}
OPERATION_CONTRACTS['viewport_camera']['scope'] += '; optional pair.world_offset=[dx,dy,0] translates plan camera ViewTarget in WCS; optional pair.custom_scale fixes scale with target ViewHeight=paper Height/scale; omitted values retain source. Does not move paper window.'
OPERATION_CONTRACTS['paper_patch']['scope'] += '; action=move with offset:[dx,dy] translates selected paper roots together, including native TDbText/TDbDrawingName, block owned attributes and floating viewport/clip pair; viewport camera/scale/freeze/lock unchanged. System paper viewport browsing state excluded from save comparison; floating views remain checked.'

OPERATION_CONTRACTS["paper_index_create"]={"native_source":"NativePaperIndexCreateV1.cs","native_handler":"Apply","effect":"create closed straight paper polylines plus whole TDbSymbDrawingIndex clones; preserve all old objects","scope":"layout, boundary_template/index_template:{handle,layer}, expected_index_label, items:[{key,vertices:[[x,y],...],position:[center_x,center_y],index_label,drawing_label?}]; paper XY; no camera projection or inferred geometry; native uniform boundary width and index styles inherited","completion":"new root handles, exact labels/grips/vertices, template preservation and native save/reopen; engineering placement by execution/review"}

OPERATION_CONTRACTS["paper_roots_copy"]={"native_source":"NativePaperRootsCopyV1.cs","native_handler":"Copy","effect":"WblockClone explicit paper roots at original coordinates; no model transfer or erase","scope":"source, source_layout, target_layout, source_targets:[{handle,type,layer}], frozen_layer_pairs?:[{source,target}]; exact explicit layer aliases, otherwise same names only; include each viewport clip root; existing target layout required; names mangled on collision","completion":"root/dependency map, viewport geometry and native properties preserved, target existing entities protected, save/reopen; execution/review confirm sheet contents"}

OPERATION_CONTRACTS["paper_roots_activate"]={"native_source":"NativePaperRootsCopyV1.cs","native_handler":"Activate","effect":"turn on exact floating viewports and refresh exact paper roots; no geometry change","scope":"layout, targets:[{handle,type,layer}]","completion":"native enabled viewport, unchanged geometry, save/reopen; actual GUI checked by execution/review"}

OPERATION_CONTRACTS["layout_import"]={"native_source":"NativeLayoutOpsV1.cs","native_handler":"-LAYOUT Template","effect":"import entire named source layout at original paper coordinates into a NEW named layout; preserve model and old layouts","scope":"approved source DWG, exact source_layout and unique target_layout; no resize, transform or automatic deletion","completion":"native command and saved receipt; actual viewport display checked by execution/review"}
OPERATION_CONTRACTS["purge_unused"]={"native_source":"NativeLayoutOpsV1.cs","native_handler":"Database.Purge unused symbol definitions","effect":"AutoCAD native purge of unused named definitions; no erase of referenced model or paper objects","scope":"current bound isolated working copy; no entity cleanup by inference","completion":"saved receipt; cleanup of old paper entities is a separate existing paper_patch action"}

OPERATION_CONTRACTS["layout_import"]["workflow"]="另存过程稿保护旧数据，清旧并PU后原生整套导入；不要求逐根映射或重新分幅。保存后执行整理文字/专用页/视口图层并直接送校审。"

OPERATION_CONTRACTS["viewport_restore"]={"native_source":"NativeLayoutOpsV1.cs + NativeViewportRestoreV1.cs","effect":"Restore one rectangular 2D native viewport from approved protected DWG into existing target paper layout using source center+offset, dimensions, camera/scale/twist/lock and same-name frozen layers. No source edits or model transfer.","scope":"source/source_layout/source_handle/target_layout/offset:[dx,dy]. Not clipped or perspective views; no layer-name mapping or per-viewport layer override migration. Missing frozen layer names are absent in target and are not created. Whole layouts use existing layout_import.","completion":"native fields/save-reopen; execution/review checks actual display"}
OPERATION_CONTRACTS["paper_patch"]["scope"] += "; move optional target_layout transfers non-viewport native entities between existing paper layouts with original handles. Associative hatch boundaries move together. copy clones a native block insert and owned attributes, reusing its same-DWG definition, or an exact native TDbSymbNorthThumb with full native shape retained; source unchanged, optional target_layout, offset required. Cross-layout viewport uses viewport_restore."
OPERATION_CONTRACTS["coord_update"]["scope"] += "; optional display_only:true supports Model or paper space, omits world_xy; fixes first grip and all X/Y values and original style, adjusts only display grips."

OPERATION_CONTRACTS["layout_import"]["workflow"]="用户2026-11-09确认：新建布局，再原生复制已有布局/视口/图框，复制后调整。layout_import 用 AutoCAD -LAYOUT Template 一次完成整布局原位复制到新布局；先沿此入口，不要求为常规复制逐视口转属、重建或计算映射。过程稿保护原数据，后续用现有文字和图层入口整理。"

OPERATION_CONTRACTS["paper_patch"]["scope"] += "; action=resize only rectangular orthographic floating viewport: exact before_width/before_height and new positive width/height; center, scale, view target/center/direction/twist, frozen layers, lock and clip identity preserved; ViewHeight follows new paper height/scale. Empty native layout viewport lists are initialized in the private document with prior layout/tilemode restored; system viewport still rejected. Resize cannot include move/display fields."

OPERATION_CONTRACTS["layout_delete"]={"native_source":"NativeLayoutDeleteV1.cs + NativeLayoutOpsV1.cs","effect":"Delete one exact inactive paper layout using LayoutManager.DeleteLayout; no purge or model deletion.","scope":"layout and replacement_layout must exist, be distinct and not Model. If old layout is current, first activate the verified replacement through existing view entry. Migration acceptance is execution/review responsibility.","completion":"retained entity write guard, root handles, relative tab order, plot fields and non-system viewport fields checked before/after and save/reopen; actual migration completeness remains execution/review"}
OPERATION_CONTRACTS["table_patch"]["scope"]+="; outline:true is a separate outline-only batch of exact hatch-only block definitions. Derive one closed native polyline from the existing single rectangular Z0 nonassociative hatch loop; inherit hatch display properties. Existing hatch/pattern and explicit table fit scales remain unchanged. Existing outlines or mixed edits reject before write."

OPERATION_CONTRACTS["paper_leaders_copy"]={"native_source":"NativePaperRootsCopyV1.cs + NativePaperLeadersCopyV1.cs","effect":"Append caller-selected intact TDbSymbMultiLeader paper roots by native WblockCloneObjects, then native XY displacement. Preserve all grip topology, UpText/DownText, height/scale/rotation and display properties.","scope":"approved source and exact paper layouts; source_targets require exact handle/type/layer; finite offset:[dx,dy]. Only TDbSymbMultiLeader, no viewports, frame blocks, deletion, scale/rotation or layer mapping. Existing broad paper_roots_copy HOLD remains in force.","completion":"native cross-DWG ownership, all grips, properties, existing-entity guard and save/reopen verified; execution/review verifies displayed position and actual engineering content"}
