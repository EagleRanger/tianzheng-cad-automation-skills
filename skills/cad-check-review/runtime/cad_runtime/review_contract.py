"""Read current human requirements from the original MD; no second task store."""
import hashlib
import json
import re
from pathlib import Path


def requirement_blocks(checklist, flow):
    """Current numbered human feedback only; result notes do not change intent."""
    batch = flow.get('active_batch', {})
    pattern = batch.get('heading_pattern')
    if not pattern:
        return None
    text = source_text(checklist, flow)
    matches = list(re.finditer(pattern, text, re.M))
    blocks = {}
    for i, match in enumerate(matches):
        key = match.group(1)
        if key in blocks:
            raise ValueError('REQUIREMENT_ID_DUPLICATED:' + key)
        block = text[match.start():matches[i+1].start() if i+1 < len(matches) else len(text)]
        block = re.split(r'^- 执行结果：', block, maxsplit=1, flags=re.M)[0]
        blocks[key] = re.sub(r'\[[ xX]\]', '[ ]', block).strip()
    return blocks


def bind_requirements(checklist, flow):
    blocks = requirement_blocks(checklist, flow)
    if blocks is None:
        return
    bound = set()
    for node in flow['nodes']:
        ids = node.get('requirement_ids', [])
        bound.update(ids)
        node['acceptance_checks'] = {}
        node['acceptance_text'] = {}
        for key in ids:
            if key not in blocks:
                raise ValueError('REQUIREMENT_SOURCE_MISSING:' + key)
            checks = re.findall(r'^- \[ \] (.+)$', blocks[key], re.M)
            if not checks:  # merged feedback still requires an explicit disposition
                checks = ['补充原条的指认已并入并落实，见本条原话及配图']
            indexes = node.get('check_indexes', {}).get(key, list(range(len(checks))))
            node['acceptance_checks'][key] = [key + '.' + str(i+1) for i in indexes]
            node['acceptance_text'][key] = {key + '.' + str(i+1): checks[i] for i in indexes}
    if bound != set(blocks):
        raise ValueError('UNBOUND_HUMAN_REQUIREMENTS:' + ','.join(sorted(set(blocks)-bound)))


def bind_corrections(checklist, flow):
    """Inline corrections belong to the original MD, never a second checklist."""
    text = source_text(checklist, flow) or ''
    nodes = {n['id']: n for n in flow['nodes']}
    seen = set()
    for raw in re.findall(r'<!-- CAD_CORRECTION (.*?) -->', text):
        item = json.loads(raw)
        key = item['id']
        if key in seen or not item.get('nodes') or not item.get('checks'):
            raise ValueError('CORRECTION_INVALID_OR_DUPLICATED:' + key)
        seen.add(key)
        for target in item['nodes']:
            if target not in nodes:
                raise ValueError('CORRECTION_NODE_UNKNOWN:' + target)
            node = nodes[target]
            ids = node.setdefault('requirement_ids', [])
            if key not in ids:
                ids.append(key)
            node.setdefault('acceptance_checks', {})[key] = item['checks']


def source_text(checklist, flow):
    batch = flow.get('active_batch')
    if not batch:
        return None
    text = Path(checklist).read_text(encoding='utf-8-sig').replace('\r\n', '\n')
    start, end = batch['start_marker'], batch['end_marker']
    starts=list(re.finditer(r'^'+re.escape(start)+r'[^\n]*$',text,re.M))
    ends=list(re.finditer(r'^'+re.escape(end)+r'[^\n]*$',text,re.M))
    if len(starts) != 1 or len(ends) != 1:
        raise ValueError('REQUIREMENTS_SOURCE_MISSING_OR_DUPLICATED')
    a, b = starts[0].start(), ends[0].start()
    if a >= b:
        raise ValueError('REQUIREMENTS_SOURCE_ORDER')
    return text[a:b].rstrip()


def contract(checklist, flow, node=None):
    text = source_text(checklist, flow)
    if text is None:
        return None
    batch = flow['active_batch']
    blocks = requirement_blocks(checklist, flow)
    if blocks is not None:
        ids = (node or {}).get('requirement_ids', list(blocks))
        text = json.dumps({k: blocks[k] for k in ids}, ensure_ascii=False, sort_keys=True)
    return {'batch': batch['id'], 'source': str(Path(checklist).resolve()),
            'revision': hashlib.sha256(text.encode('utf-8')).hexdigest(),
            'read_command': f'python -X utf8 "{Path(checklist).parent / "接续读取.py"}" --batch current',
            'required_ids': (node or {}).get('requirement_ids', []),
            'acceptance_checks': (node or {}).get('acceptance_checks', {}),
            'acceptance_text': (node or {}).get('acceptance_text', {}),
            'review_policy': batch.get('review_policy', {}),
            'user_confirmation': batch.get('user_confirmation', 'pending'),
            'retention': '用户确认前原意见/截图/执行和校审结果均保留；内部PASS不代表用户确认。'}


def validate_results(node, role, evidence, flow):
    ids = node.get('requirement_ids')
    if not ids:
        return
    rows = evidence.get('requirement_results', [])
    if not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
        raise ValueError('REQUIREMENT_RESULTS_INVALID')
    actual = [r.get('id') for r in rows]
    if len(actual) != len(set(actual)) or set(actual) != set(ids):
        raise ValueError('REQUIREMENT_COVERAGE_MISMATCH: 必须逐原ID覆盖当前节点，不能只报整批PASS。')
    strict = flow.get('active_batch', {}).get('review_policy', {}).get('scope_and_layout_required')
    if strict:
        context = evidence.get('review_context', {})
        if not {'Model', 'Paper'} <= set(context.get('spaces', [])) or not context.get('views'):
            raise ValueError('ACTUAL_MODEL_PAPER_VIEW_COVERAGE_REQUIRED')
    for row in rows:
        if strict and not str(row.get('scope', '')).strip():
            raise ValueError('ACTUAL_REQUIREMENT_SCOPE_REQUIRED:' + str(row.get('id')))
        if row.get('result') != 'PASS' or not row.get('evidence'):
            raise ValueError('REQUIREMENT_UNRESOLVED:' + str(row.get('id')))
        proofs = row['evidence'] if isinstance(row['evidence'], list) else [row['evidence']]
        if not all(isinstance(p, str) and Path(p).is_file() for p in proofs):
            raise ValueError('REQUIREMENT_PROOF_MISSING:' + str(row.get('id')))
        required = node.get('acceptance_checks', {}).get(row['id'], [])
        observations = row.get('observed', {})
        if any(not isinstance(observations.get(k), str) or not observations[k].strip()
               for k in required):
            raise ValueError('CORRECTION_OBSERVATION_REQUIRED:' + row['id'])
    if role == '校审' or node.get('review_source_node'):
        sources = [node['review_source_node']] if node.get('review_source_node') else node['after']
        predecessors = [n for n in flow['nodes'] if n['id'] in sources]
        if not predecessors or any(n.get('evidence', {}).get('sha256') != evidence.get('sha256')
                                   or n.get('evidence', {}).get('candidate') != evidence.get('candidate')
                                   for n in predecessors):
            raise ValueError('REVIEW_MUST_MATCH_SUBMITTED_CANDIDATE')
