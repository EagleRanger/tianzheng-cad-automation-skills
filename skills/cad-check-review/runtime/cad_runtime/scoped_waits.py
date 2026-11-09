"""Keep local questions and partial evidence in the existing workflow MD only."""
import hashlib
import json
import os
from pathlib import Path

from .common import check
from .review_contract import contract,validate_results


def open_questions(flow):
    return [q for q in flow.get('deferred_questions',[]) if q.get('state')=='pending']


def selection(checklist,flow,pending):
    ids={n['id'] for n in pending};ready=[n for n in pending if not set(n['after'])&ids]
    questions=open_questions(flow);runnable=[];deferred=[]
    for node in ready:
        waits=[q for q in questions if q['node']==node['id']]
        required=node.get('requirement_ids',[])
        held=set(k for q in waits for k in q.get('requirement_ids',[]))
        whole=any(q.get('whole_node') for q in waits)
        done=set();progress=node.get('partial_evidence',{})
        if progress and progress.get('requirements_revision')==(contract(checklist,flow,node) or {}).get('revision'):
            covered=[r.get('id') for r in progress.get('requirement_results',[])]
            if set(covered)<=set(required):
                try:
                    validate_results({**node,'requirement_ids':covered},node['owner'],progress,flow)
                    done=set(covered)
                except (ValueError,KeyError):pass  # changed/missing proof is work again
        done=done-held if not whole else set()
        remaining=[k for k in required if k not in done]
        allowed=[k for k in remaining if k not in held] if not whole else []
        row={**node,'runnable_ids':allowed,'deferred_ids':[k for k in remaining if whole or k in held],
             'completed_ids':sorted(done)}
        if whole or (required and remaining and not allowed):deferred.append(row)
        else:runnable.append(row)
    return {'next':runnable,'deferred_nodes':deferred,'unresolved_questions':questions}


def write_flow(path,original,text,start,end,flow):
    path=Path(path);tmp=path.with_name(path.name+'.scoped-wait.tmp')
    check(path.read_bytes()==original,'CHECKLIST_CHANGED_RELOAD')
    with tmp.open('x',encoding='utf-8') as f:
        f.write(text[:start]+json.dumps(flow,ensure_ascii=False,indent=2)+text[end:])
    try:
        check(path.read_bytes()==original,'CHECKLIST_CHANGED_RELOAD');os.replace(tmp,path)
    finally:
        if tmp.exists():tmp.unlink()


def defer(checklist,state,node_id,role,value):
    from .project_flow import read_flow,destinations,current
    original,text,start,end,flow=read_flow(checklist)
    check(role in ('执行','校审','管理'),'ROLE_REQUIRED')
    check(os.environ.get('CODEX_THREAD_ID')==destinations(state)[role],'WAIT_ROLE_IDENTITY_REQUIRED')
    node=next((n for n in flow['nodes'] if n['id']==node_id),None)
    check(node is not None and (node['owner']==role or role=='管理'),'WAIT_NODE_OWNER_MISMATCH')
    check(node.get('state')!='done','WAIT_ONLY_UNFINISHED_NODE')
    reason=value.get('reason') or value.get('why_user_required')
    check(value.get('question') and reason and value.get('evidence'),
          'WAIT_NEEDS_QUESTION_REASON_AND_ORIGINAL_SOURCE')
    kind=value.get('kind','user_decision')
    check(kind in ('user_decision','approval','external_dependency','user_pause'),'WAIT_KIND_INVALID')
    required=node.get('requirement_ids',[]);affected=value.get('requirement_ids',[])
    check(isinstance(affected,list) and len(affected)==len(set(affected)) and set(affected)<=set(required),'WAIT_IDS_INVALID')
    whole=value.get('whole_node') is True
    check((bool(affected) and not whole) or (whole and not affected),'WAIT_SCOPE_REQUIRED: 列受影响原ID；确实整个节点受阻才显式whole_node。')
    key=hashlib.sha256(json.dumps([node_id,kind,sorted(affected),whole,value['question']],ensure_ascii=False).encode()).hexdigest()[:16]
    records=flow.setdefault('deferred_questions',[])
    existing=next((q for q in records if q['id']==key and q.get('state')=='pending'),None)
    if existing:return {'status':'ALREADY_DEFERRED','id':key,'next':current(checklist)['next']}
    record={'id':key,'node':node_id,'kind':kind,'requirement_ids':affected,'whole_node':whole,
            'question':value['question'],'reason':reason,'evidence':value['evidence'],
            'resume_when':value.get('resume_when','取得该问题的实际答复或新依据后回到原ID'),
            'state':'pending'}
    records.append(record);write_flow(checklist,original,text,start,end,flow)
    return {'status':'DEFERRED_NOT_COMPLETED','id':key,'next':current(checklist)['next']}


def resolve(checklist,state,key,role,answer,evidence):
    from .project_flow import read_flow,destinations,current
    check(role in ('执行','校审','管理') and os.environ.get('CODEX_THREAD_ID')==destinations(state)[role],'WAIT_ROLE_IDENTITY_REQUIRED')
    check(str(answer).strip() and str(evidence).strip(),'ACTUAL_ANSWER_AND_SOURCE_REQUIRED: 超时/未回复不是答复或授权。')
    original,text,start,end,flow=read_flow(checklist)
    row=next((q for q in flow.get('deferred_questions',[]) if q['id']==key and q['state']=='pending'),None)
    check(row is not None,'OPEN_QUESTION_NOT_FOUND')
    node=next(n for n in flow['nodes'] if n['id']==row['node'])
    check(role==node['owner'] or role=='管理','WAIT_NODE_OWNER_MISMATCH')
    row.update(state='answered',answer=answer,answer_source=evidence)
    write_flow(checklist,original,text,start,end,flow)
    return {'status':'ANSWER_RECORDED_WORK_NOT_COMPLETED','next':current(checklist)['next']}


def checkpoint(checklist,state,node_id,role,evidence_path):
    """Save verified independent progress without completing a node or bypassing review."""
    from .project_flow import read_flow,pending_nodes,validate_evidence,current,destinations
    original,text,start,end,flow=read_flow(checklist)
    node=next((n for n in flow['nodes'] if n['id']==node_id),None)
    check(node and node.get('requirement_ids') and node['owner']==role,'PARTIAL_REQUIREMENT_NODE_REQUIRED')
    caller=os.environ.get('CODEX_THREAD_ID')
    if caller:check(caller==destinations(state)[role],'PARTIAL_CALLER_MISMATCH')
    check(node.get('state')!='done','PARTIAL_NODE_ALREADY_DONE')
    pending={n['id'] for n in pending_nodes(checklist,flow)}
    check(not set(node['after'])&pending,'PREDECESSOR_NOT_DONE_OR_STALE')
    evidence=json.loads(Path(evidence_path).read_text(encoding='utf-8-sig'))
    check(evidence.get('requirements_revision')==contract(checklist,flow,node)['revision'],'PARTIAL_REQUIREMENTS_CHANGED')
    ids=[r.get('id') for r in evidence.get('requirement_results',[])]
    check(ids and len(ids)==len(set(ids)) and set(ids)<=set(node['requirement_ids']),'PARTIAL_IDS_INVALID')
    waits=[q for q in open_questions(flow) if q['node']==node_id]
    check(not any(q.get('whole_node') or set(ids)&set(q['requirement_ids']) for q in waits),'DEFERRED_ITEM_CANNOT_PASS_WITHOUT_ANSWER')
    validate_evidence({**node,'requirement_ids':ids},role,evidence,flow)
    node['partial_evidence']={**evidence,'path':str(Path(evidence_path).resolve())}
    write_flow(checklist,original,text,start,end,flow)
    return {'status':'PROGRESS_RECORDED_NOT_COMPLETED','node':node_id,'next':current(checklist)['next']}
