"""Deterministic project steps and direct handoff templates, stored in the original checklist.

No scheduler, no duplicate task database, no model selection, no CAD writes.
Engineering judgments remain with the writer/reviewer. Evidence gates prevent a
local operation from being recorded as completion of whole-base replacement.
"""
import hashlib,json,re,os
from pathlib import Path
from .common import check
from .review_contract import contract, validate_results, bind_corrections, bind_requirements
from .scoped_waits import selection,open_questions

START='<!-- CAD_WORKFLOW_V1\n'
END='\nCAD_WORKFLOW_V1 -->'
EVENTS={'工程待核':'校审','图面送审':'校审','返修复核':'校审',
        '返修差异':'执行','程序故障':'管理','模块反馈':None,'整项结论':'管理','用户取舍':'管理',
        '接口交付执行':'执行','接口交付校审':'校审'}
SENDERS={'工程待核':{'执行'},'图面送审':{'执行'},'返修复核':{'执行'},
         '返修差异':{'校审'},'程序故障':{'执行','校审'},'模块反馈':{'执行','校审'},
         '整项结论':{'校审'},'用户取舍':{'执行','校审'},
         '接口交付执行':{'管理'},'接口交付校审':{'管理'}}

MANAGER_SELF_CHECK='管理自测只核接口调用、字段写入读回、保存及保护项，完成即交入口；不打开测试图或生产图判断效果。图纸定位、来源、范围及表达由执行/校审在原任务核验，已有截图只作证据交回，不新增管理放行。'

def role_boundary():
    return '执行负责修改、保存和自检；校审独立核工程与图面，差异直接交执行。普通模块通过和经验留原证据；仅需管理实际处理的接口困难、能力缺口或程序故障才通过packet生成发送目标；普通保存/对象/位置进展不发管理，另接整项结果和用户设计取舍。'+MANAGER_SELF_CHECK

def read_flow(checklist):
    data=Path(checklist).read_bytes();text=re.sub(r'\r+\n?', '\n', data.decode('utf-8-sig'))
    check(text.count(START)==1 and text.count(END)==1,'WORKFLOW_ENTRY_MISSING_OR_DUPLICATED')
    start=text.index(START)+len(START);end=text.index(END,start)
    value=json.loads(text[start:end]);nodes=value['nodes']
    check(value['schema']==1 and len({n['id'] for n in nodes})==len(nodes),'WORKFLOW_SCHEMA')
    bind_corrections(checklist,value)
    bind_requirements(checklist,value)
    return data,text,start,end,value

def current(checklist):
    flow=read_flow(checklist)[-1]
    pending=pending_nodes(checklist,flow)
    selected=selection(checklist,flow,pending);available=selected['next']
    result={'scope':flow['scope'],**selected,'nodes':flow['nodes'],'pending_count':len(pending)}
    result['continuation']={'action':'CONTINUE_CURRENT_OWNER' if available else ('REVISIT_DEFERRED' if pending else 'RETURN_FOR_USER_REVIEW'),
        'may_stop_for_partial_result':False,
        'before_finish':'python -X utf8 任务流程.py finish-check --role <执行或校审>',
        'rule':'补充、纠正、接口交付不暂停原任务；记录后继续当前未完节点。仅真实用户暂停、权限/外部依赖或已完成本次责任交接才结束；局部阻碍不阻断独立项。'}
    if flow.get('active_batch'):
        result['requirements']=contract(checklist,flow,available[0] if available else None)
    return result

def pending_nodes(checklist,flow):
    """One freshness/coverage decision for next, completion and finish-check."""
    pending=[]
    for node in flow['nodes']:
        revision=(contract(checklist,flow,node) or {}).get('revision')
        reason=None
        if node.get('state')!='done':reason='未完成'
        elif node.get('requirement_ids'):
            evidence=node.get('evidence',{})
            if evidence.get('requirements_revision')!=revision:reason='完成证据未覆盖最新意见'
            else:
                try:validate_results(node,node['owner'],evidence,flow)
                except (ValueError,KeyError):reason='逐条结果不完整或未通过'
        if reason:pending.append({**node,'reason':reason})
    # Reopening an upstream item also invalidates dependent completion, but does
    # not discard earlier evidence or restart unrelated work.
    while True:
        ids={n['id'] for n in pending}
        extra=[{**n,'reason':'前置节点需返修或复核'} for n in flow['nodes']
               if n['id'] not in ids and set(n['after']) & ids]
        if not extra:break
        pending.extend(extra)
    return pending

def finish_check(checklist,role):
    """End-of-work check from the existing MD only; no manager approval or timer."""
    check(role in ('执行','校审','管理'),'EXECUTION_OR_REVIEW_ROLE_REQUIRED')
    flow=read_flow(checklist)[-1];revision=(contract(checklist,flow) or {}).get('revision')
    pending=pending_nodes(checklist,flow)
    selected=selection(checklist,flow,pending);ready=selected['next']
    mine=[n for n in ready if n['owner']==role]
    action='READY_FOR_USER_REVIEW' if not pending else ('CONTINUE' if mine else ('DIRECT_HANDOFF' if ready else 'REVISIT_DEFERRED'))
    return {'source':str(Path(checklist).resolve()),'role':role,'requirements_revision':revision,
            'allow_finish':not pending,'action':action,
            'remaining':[{'id':n['id'],'owner':n['owner'],'title':n['title'],'reason':n['reason'],'required_ids':n.get('requirement_ids',[])} for n in pending],
            'next':[{'id':n['id'],'owner':n['owner'],'title':n['title'],'runnable_ids':n['runnable_ids'],
                     'deferred_ids':n['deferred_ids'],'completed_ids':n['completed_ids']} for n in (mine or ready)],
            'unresolved_questions':selected['unresolved_questions'],
            'may_wait_for_user':bool(pending and not ready and selected['unresolved_questions']),
            'before_wait':'独立项做完后集中复查原依据和最新答复；已有授权内可判定的先解决。真正仍需人工的合并一次说明，原问题已问过则不重复催问；未回复不作同意。',
            'rule':'结束前读本MD最新原意见并核实际证据；未完继续。执行完成直接送校审，校审差异直接返执行，不交管理逐项检查。真实暂停或外部阻碍只停相应依赖；全项完成仍保留原意见等待用户确认。'}


def destinations(state):
    s=json.loads(Path(state).read_text(encoding='utf-8-sig'))['CAD_review_20261027']['supervision']
    result={'管理':s['destination_thread'],'执行':s['execution_thread'],'校审':s['review_thread']}
    check(len(set(result.values()))==3,'ROLE_IDENTITIES_CONFLICT')
    return result

def supervise(checklist,state,native,hold=None,record_sent=False):
    """Consume a native wait snapshot. No timer, CAD operation or message send.

    The manager verifies pause/approval/external dependencies before requesting
    resume. A sent cursor is remembered only after the native send succeeded.
    """
    flow=current(checklist);nodes=flow['next'];roles=destinations(state)
    if hold:
        check(isinstance(hold,dict) and hold.get('kind') in ('user_pause','approval','external_dependency','user_decision') and hold.get('reason') and hold.get('evidence'),'REAL_HOLD_WITH_EVIDENCE_REQUIRED')
        if hold.get('kind')=='user_pause' and not hold.get('node'):
            return {'action':'HOLD','send':False,'hold':hold,'reason':'用户未限定范围的明确暂停仍暂停整体。'}
        if not hold.get('node'):
            return {'action':'CHECK_HOLD_SCOPE','send':False,'hold':hold,'reason':'不能把未定位的小问题当整批HOLD；先在原ID登记影响范围，其余已授权独立项继续。'}
        check(any(n['id']==hold['node'] for n in flow.get('nodes',nodes)),'HOLD_NODE_UNKNOWN')
        filtered=[]
        for n in nodes:
            if n['id']!=hold['node']:filtered.append(n);continue
            affected=hold.get('requirement_ids')
            if affected:
                available=n.get('runnable_ids',n.get('requirement_ids',[]))
                check(set(affected)<=set(n.get('requirement_ids',available)),'HOLD_IDS_INVALID')
                remain=[k for k in available if k not in affected]
                if remain:filtered.append({**n,'runnable_ids':remain})
        nodes=filtered
        if not nodes:return {'action':'HOLD_SCOPED_REMAINDER','send':False,'hold':hold,'unresolved_questions':flow.get('unresolved_questions',[])}
    if not nodes:
        return {'action':'REVISIT_DEFERRED' if flow.get('pending_count') else 'RETURN_FOR_USER_REVIEW',
                'send':False,'unresolved_questions':flow.get('unresolved_questions',[]),
                'reason':'独立可做项已处理，保留待答原ID；未决不计完成。' if flow.get('pending_count') else '本轮节点已完成，用户确认仍按原清单保留。'}
    node=nodes[0];thread=roles[node['owner']]
    polls=native.get('polls',[])
    poll=next((p for p in polls if p.get('thread',{}).get('id')==thread),None)
    if poll is None:return {'action':'READ_NATIVE_OWNER','send':False,'threadId':thread,'node':node['id']}
    cursor=poll.get('cursor');check(cursor,'NATIVE_CURSOR_REQUIRED')
    status=poll.get('thread',{}).get('status',{});turn=poll.get('latestTurn') or {}
    if status.get('type')=='active' or turn.get('status')=='inProgress':
        return {'action':'WAIT_NATIVE','send':False,'threadId':thread,'cursor':cursor,'node':node['id']}
    if status.get('type')!='idle' or status.get('activeFlags'):
        return {'action':'CHECK_NATIVE_ATTENTION','send':False,'threadId':thread,'cursor':cursor,'node':node['id']}
    data=json.loads(Path(state).read_text(encoding='utf-8-sig'));s=data['CAD_review_20261027']['supervision']
    key='|'.join([thread,cursor,node['id'],flow.get('requirements',{}).get('revision',''),','.join(node.get('runnable_ids',[]))])
    guard=s.get('continuation_guard',{})
    if guard.get('last_resume_key')==key:
        return {'action':'VERIFY_PICKUP','send':False,'threadId':thread,'cursor':cursor,'node':node['id'],'reason':'同停点已发送接续，不重复唤醒；核原生实际接手。'}
    result={'action':'RESUME_ONCE','send':True,'threadId':thread,'hostId':'local','cursor':cursor,'node':node['id'],
        'stop_check':'发送前核最新用户暂停、审批和外部依赖；未知时只核停点，不把局部未完当阻碍。',
        'prompt':'本轮已授权且当前节点未完，请接当前已保存稿继续：'+node['title']+'。原要求只读 '+str(Path(checklist).resolve())+'；补充或纠正记录后继续实做，不以答复或局部保存结束整批。工程问题直接给校审，程序故障给管理，独立未完项继续。'}
    if node.get('runnable_ids'):
        result['runnable_ids']=node['runnable_ids']
        result['prompt']+=' 当前仅推进这些独立原ID：'+','.join(node['runnable_ids'])+'；待答项及其直接依赖不动、不猜答复、不重复催问。'
    if flow.get('unresolved_questions') or hold:result['deferred_questions_remain_open']=True
    if record_sent:
        guard.update(last_resume_key=key,last_resume_cursor=cursor,last_resume_thread=thread,last_resume_node=node['id'])
        s['continuation_guard']=guard
        # Preserve concurrent changes instead of overwriting a newer project state.
        original=Path(state).read_bytes();latest=json.loads(original.decode('utf-8-sig'))
        latest['CAD_review_20261027']['supervision']['continuation_guard']=guard
        check(Path(state).read_bytes()==original,'PROJECT_STATE_CHANGED_RETRY_READ')
        temporary=Path(str(state)+'.continuation.tmp');temporary.write_text(json.dumps(latest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');os.replace(temporary,state)
        result.update(action='RESUME_SENT_RECORDED',send=False)
    return result

def route(event,sender,state):
    check(event in EVENTS and sender in SENDERS[event],'EVENT_SENDER_MISMATCH')
    role=EVENTS[event]
    if role is None:return {'event':event,'sender':sender,'recipient_role':None}
    return {'event':event,'sender':sender,'recipient_role':role,'threadId':destinations(state)[role],'hostId':'local'}

def packet(checklist,state,event,sender,payload):
    dest=route(event,sender,state)
    check(isinstance(payload,dict) and payload.get('issue'),'HANDOFF_ISSUE_REQUIRED')
    check(not ({'threadId','recipient','model','thinking'} & set(payload)),'DESTINATION_AND_MODEL_ARE_NOT_PAYLOAD')
    if event in ('图面送审','返修复核'):
        check(payload.get('candidate') and payload.get('sha256') and payload.get('scope') and payload.get('evidence'),'STABLE_REVIEW_INPUT_REQUIRED')
    if event in ('程序故障','模块反馈'):
        allowed={'issue','evidence','operation','expected','error_code','repro_file','input_files','module','result','observed','manager_request'}
        check(set(payload)<=allowed,'ENGINEERING_REVIEW_IS_NOT_A_PROGRAM_TICKET: 审查范围、判断和返修正文直接交校审；管理仅收接口与复现文件。')
        if 'manager_request' in payload:check(isinstance(payload['manager_request'],str),'MANAGER_REQUEST_MUST_BE_TEXT')
        # A missing interface need not have an error code or reproduction yet.
        # Management repairs/self-tests; drafting roles validate actual use and report.
    if event=='模块反馈' or (event=='程序故障' and not str(payload.get('manager_request') or '').strip()):
        # Validation belongs to existing drawing evidence. Do not generate a send
        # target/prompt for ordinary PASS reports, lessons or partial review results.
        return {'event':event,'sender':sender,'recipient_role':None,'tool':None,'effect':'record_in_existing_evidence_only','send':False,
                'copy_to_management':False,
                'next':'普通进度、保存哈希、对象清单、位置安排和成功反馈留原MD/已有证据，不发送管理。工程差异直接交执行/校审。只有确需管理修复或讲清接口调用时，在manager_request中用一句话写明所需处理；不要求新增错误、截图或复现表单。'}
    if event=='用户取舍':
        check(set(payload)<={'issue','question','why_user_required','options','evidence','node','requirement_ids'},'USER_DECISION_ONLY: 图面明细留原清单，只发需要用户决定的问题。')
        check(payload.get('question') and payload.get('why_user_required'),'REAL_USER_DESIGN_DECISION_REQUIRED')
        if 'options' in payload:check(isinstance(payload['options'],list),'OPTIONS_MUST_BE_LIST')
    if event=='整项结论':
        check(set(payload)<={'issue','candidate','sha256','evidence','result','scope','node'},'WHOLE_RESULT_ONLY')
        flow=read_flow(checklist)[-1]
        check(not any(n['owner'] in ('执行','校审') for n in pending_nodes(checklist,flow)),
              'WHOLE_REVIEW_NOT_COMPLETE: 执行或独立校审仍未完成，局部结果直接交对方，不能回传管理。')
        check(payload.get('result')=='PASS' and payload.get('evidence'),'WHOLE_REVIEW_EVIDENCE_REQUIRED')
        check(any(n['owner']=='校审' and n.get('evidence',{}).get('candidate')==payload.get('candidate')
                  and n.get('evidence',{}).get('sha256')==payload.get('sha256') and payload.get('sha256')
                  for n in flow['nodes']),'WHOLE_REVIEW_VERSION_MISMATCH')
    if event=='图面送审' and payload.get('node')=='base_review':
        check(any(n['id']=='base_review' for n in current(checklist)['next']),'BASE_SELF_CHECK_REQUIRED')
    # The exact native send tool consumes this ready template; no forwarding via management.
    technical=event in ('程序故障','模块反馈') or event.startswith('接口交付')
    body={'事项':event,'内容':payload}
    if event=='用户取舍':body['待答接续']='问题只挂受影响原ID及真实依赖；先完成其余已授权独立项，最后合并回看未决。未回复不算同意，不反复催问，不把整批停住。'
    body['结束检查']='结束前运行 任务流程.py finish-check --role '+(dest['recipient_role'] if dest.get('recipient_role') in ('执行','校审') else sender)+'；allow_finish=false时按next继续或直接交另一责任方，不能以局部回复宣告整批完成。'
    body['接续']='补充、返修或接口交付不撤销原批授权；接收方记录后继续当前未完节点。普通答复和局部保存不是停止条件；真实暂停/阻碍沿原入口记录，仅停实际依赖。'
    if not technical and dest['recipient_role']!='管理':
        flow=read_flow(checklist)[-1]
        node=next((n for n in flow['nodes'] if n['id']==payload.get('node')),None)
        if flow.get('active_batch'):body['共享MD需求与验收']=contract(checklist,flow,node)
    if technical:body['范围']='仅处理程序/接口；不接管工程或图面校审。'
    if event in ('程序故障','模块反馈'):
        body['管理处理顺序']='先核当前卡住的具体动作和已有入口：用法不清就讲清调用，实际故障只修失效处，确有当前能力缺口才补模块，不按反馈自动立研发项。复用已有效的回执与测试；只有新增验证会改变操作或验收决定时才做，不重复验证未变部分。反馈说明实际问题即可，不要求发送方先研究接口或补齐表单。'
    if event=='程序故障':
        body['分工']='管理只处理manager_request所指接口问题，交现成入口；不追索工程对象清单、页位置或连续保存进度。执行/校审在原任务验证，成功留原证据；同一接口问题仍存在才续报。发送方继续未受影响的改图/校核。'
        body['管理自测边界']=MANAGER_SELF_CHECK
    elif event.startswith('接口交付'):body['分工']='接收方在原改图/核图任务中验证模块效果并反馈问题：通过结论留原证据，不另发成功回报；工程差异直交执行/校审，接口困难或程序故障才交管理。复用本批已有证据，不另起重复测试或逐笔管理放行。'
    elif dest['recipient_role']!='管理':body.update({'原清单':str(Path(checklist).resolve()),'当前节点':[
        {k:n[k] for k in ('id','owner','title')} for n in current(checklist)['next']]})
    if dest['recipient_role']=='管理':
        # The manager consumes a bounded exception/result, never the whole batch.
        check(len(json.dumps(payload,ensure_ascii=False))<=2400,
              'MANAGER_RECEIPT_TOO_LONG: 只发具体请求或整项结论，明细用原证据路径。')
    result={**dest,'tool':'send_message_to_thread','prompt':json.dumps(body,ensure_ascii=False,indent=2),
            'effect':'template_only_not_sent','copy_to_management':False}
    if event.startswith('接口交付'):
        result['manager_self_check']={'entry':str(Path(checklist).resolve().parent.parent/'.project-reasoning/PROJECT_LOOP.md')+'#development-simplification',
            'action':'管理交付前核必要性、可删除项、已有替代和验证复用；只处理本次变化，不发送额外填表或审批要求给执行/校审。',
            'boundary':MANAGER_SELF_CHECK}
    return result

def sha(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()

def cumulative_base(evidence,primary):
    """Bind a partial base replacement, reviewed dispositions and final save.

    The original partial receipt stays false. This is a technical evidence
    check; base_check and independent base_review remain separate task nodes.
    """
    changes=primary.get('changes',{})
    check(primary.get('status')=='SAVED_STILL_OPEN' and changes.get('operation')=='base_replace' and
          changes.get('protected_verified') is True and changes.get('classification_complete') is True and
          changes.get('reopen_verified') is True and changes.get('entity_map'),'PRIMARY_BASE_RECEIPT_REQUIRED')
    check(Path(primary['output']).is_file() and sha(primary['output'])==primary['sha256'],'PRIMARY_BASE_IDENTITY')
    report_path=Path(evidence['coverage_review'])
    report=json.loads(report_path.read_text(encoding='utf-8-sig'))
    check(report.get('primary_sha256')==primary['sha256'],'COVERAGE_PRIMARY_MISMATCH')
    expected=[r['handle'].upper() for r in changes.get('deferred_targets',[])]
    rows=report.get('objects',[]);actual=[str(r.get('handle','')).upper() for r in rows]
    check(len(expected)==len(set(expected)) and len(actual)==len(set(actual)) and set(actual)==set(expected)
          and report.get('missing_objects')==[] and report.get('duplicate_membership')==[],
          'DEFERRED_ROLE_COVERAGE_INCOMPLETE_OR_DUPLICATED')
    for row in rows:
        check(bool(row.get('decision')) and bool(row.get('evidence')),'DEFERRED_ROLE_EVIDENCE_REQUIRED')
        proofs=row['evidence'] if isinstance(row['evidence'],list) else [row['evidence']]
        for p in proofs:
            proof=Path(p) if Path(p).is_absolute() else report_path.parent/p
            if not proof.is_file() and p in evidence.get('proof_paths',{}):
                proof=Path(evidence['proof_paths'][p]);check(proof.name==Path(p).name,'ROLE_PROOF_MAPPING_NAME_CHANGED')
            check(proof.is_file(),'DEFERRED_ROLE_PROOF_MISSING:'+p)
    final=json.loads(Path(evidence['final_receipt']).read_text(encoding='utf-8-sig'))
    check(final.get('status')=='SAVED_STILL_OPEN' and final.get('sha256')==evidence['sha256'] and
          Path(final['output']).resolve()==Path(evidence['candidate']).resolve(),'FINAL_SAVE_IDENTITY')
    final_changes=final.get('changes',{})
    check(final_changes.get('native_save_reopen_verified') is True or final_changes.get('reopen_verified') is True,
          'FINAL_NATIVE_REOPEN_REQUIRED')
    reviewed_sha=report.get('current_saved_scope_sha256')
    if reviewed_sha!=evidence['sha256']:
        # Reuse reviewed object roles after a precisely bound display-only fix.
        # Geometry or membership changes require a new role review for that scope.
        job=json.loads(Path(evidence['final_job']).read_text(encoding='utf-8-sig'))
        op=final_changes.get('operation_changes',{})
        check(job.get('input_sha256')==reviewed_sha and Path(job['output']).resolve()==Path(evidence['candidate']).resolve()
              and op.get('geometry_unchanged') is True and op.get('definition_instances_and_other_children_unchanged') is True,
              'COVERAGE_FINAL_VERSION_NOT_LINKED')
    return {'mode':'cumulative','primary_sha256':primary['sha256'],'reviewed_scope_sha256':reviewed_sha,
            'final_sha256':evidence['sha256'],'deferred_roles':len(actual),'primary_receipt_rewritten':False}

def validate_evidence(node,role,evidence,flow):
    check(role==node['owner'],'NODE_OWNER_MISMATCH')
    check(set(node['after']) <= {n['id'] for n in flow['nodes'] if n.get('state')=='done'},'PREDECESSOR_NOT_DONE')
    validate_results(node,role,evidence,flow)
    candidate=evidence.get('candidate');digest=evidence.get('sha256')
    check(candidate and Path(candidate).is_file() and digest==sha(candidate),'CANDIDATE_IDENTITY')
    if node['id']=='base_replace':
        r=json.loads(Path(evidence['receipt']).read_text(encoding='utf-8-sig'))
        if evidence.get('coverage_review'):
            cumulative_base(evidence,r)
            return
        changes=r.get('changes',{})
        check(r.get('status')=='SAVED_STILL_OPEN' and r.get('sha256')==digest and
              changes.get('operation')=='base_replace' and changes.get('protected_verified') is True and
              changes.get('coverage_complete') is True and changes.get('entity_map') and
              changes.get('reopen_verified') is True,'WHOLE_BASE_RECEIPT_REQUIRED_NOT_LOCAL_COUNT')
    elif node['id']=='base_check':
        for k in ('old_base_removed','new_base_coverage','planting_preserved','viewports_and_grid_notes','native_readback','actual_views'):
            check(evidence.get(k) is True,'BASE_CHECK_MISSING:'+k)
        check(evidence.get('proofs') and all(Path(p).is_file() for p in evidence['proofs']),'CHECK_PROOFS_REQUIRED')
    elif node['id']=='base_review':
        check(evidence.get('result')=='PASS' and evidence.get('review_thread') and evidence.get('proofs'), 'INDEPENDENT_REVIEW_REQUIRED')
        previous=next(n for n in flow['nodes'] if n['id']=='base_check')['evidence']
        check(previous['sha256']==digest,'REVIEW_MUST_USE_SELF_CHECKED_VERSION')
    else:
        check(evidence.get('result')=='PASS' and evidence.get('proofs'),'DELIVERY_EVIDENCE_REQUIRED')

def complete(checklist,state,node_id,role,evidence_path):
    original,text,start,end,flow=read_flow(checklist)
    node=next((n for n in flow['nodes'] if n['id']==node_id),None)
    check(node is not None,'NODE_ALREADY_DONE_OR_UNKNOWN')
    check(not any(q['node']==node_id for q in open_questions(flow)),
          'UNRESOLVED_QUESTION_NOT_COMPLETE: 先处理其余独立项；待答不能标成完成。')
    pending={n['id'] for n in pending_nodes(checklist,flow)}
    check(not (set(node['after']) & pending),'PREDECESSOR_NOT_DONE_OR_STALE')
    revise=False
    if node.get('state')=='done':
        dependents=[n for n in flow['nodes'] if node_id in n.get('after',[])]
        revise=(node_id in pending or bool(node.get('requirement_ids') and role==node['owner']=='执行' and dependents
                    and all(n.get('state')!='done' for n in dependents)))
        check(revise,'NODE_ALREADY_DONE_OR_UNKNOWN')
    evidence=json.loads(Path(evidence_path).read_text(encoding='utf-8-sig'))
    if node.get('review_source_node') and role=='管理':
        check(os.environ.get('CODEX_THREAD_ID')==destinations(state)['管理'],'FINAL_REVIEW_MANAGER_IDENTITY_REQUIRED')
    reviewer_source=None
    if node_id=='base_review' or (role=='校审' and node.get('requirement_ids')):
        expected=destinations(state)['校审'];native=os.environ.get('CODEX_THREAD_ID');declared=evidence.get('review_thread')
        if native:check(native==expected,'REVIEW_CALLER_MISMATCH: 工程节点须由当前校审对话提交，管理不代放行。')
        if declared:check(declared==expected,'REVIEW_THREAD_MISMATCH: 报告中的显式校审身份与当前入口不一致。')
        reviewer=native or declared
        check(reviewer,'REVIEW_IDENTITY_MISSING: 当前运行未提供CODEX_THREAD_ID；请在原证据中记录实际review_thread。')
        # Runtime identity belongs to the handoff entry, not to engineering prose.
        # Do not rewrite the signed-off report or invent a missing native turn ID.
        evidence={**evidence,'review_thread':reviewer};reviewer_source='native_environment' if native else 'declared_evidence'
        if os.environ.get('CODEX_TURN_ID') and not evidence.get('review_turn'):evidence['review_turn']=os.environ['CODEX_TURN_ID']
    if node.get('requirement_ids'):
        check(evidence.get('requirements_revision')==contract(checklist,flow,node)['revision'],
              'REQUIREMENTS_CHANGED_OR_UNREAD: 用接续读取 --batch current 取得当前原意见及修订，按最新要求核验。')
    validate_evidence(node,role,evidence,flow)
    if revise and node.get('evidence'):
        node.setdefault('previous_submissions',[]).append(node['evidence'])
    node.update(state='done',evidence={'path':str(Path(evidence_path).resolve()),'candidate':evidence['candidate'],'sha256':evidence['sha256']})
    if node.get('requirement_ids'):
        node['evidence'].update(requirements_revision=evidence['requirements_revision'],
                                requirement_results=evidence['requirement_results'])
        if 'review_context' in evidence:node['evidence']['review_context']=evidence['review_context']
    if node_id=='base_review' or (role=='校审' and node.get('requirement_ids')):
        node['evidence'].update(review_thread=evidence['review_thread'],review_identity_source=reviewer_source)
        if evidence.get('review_turn'):node['evidence']['review_turn']=evidence['review_turn']
    updated=text[:start]+json.dumps(flow,ensure_ascii=False,indent=2)+text[end:]
    remaining=pending_nodes(checklist,flow)
    remaining_ids={n['id'] for n in remaining}
    done={n['id'] for n in flow['nodes']}-remaining_ids
    ready=[n for n in remaining if not (set(n['after']) & remaining_ids)]
    if ready:
        first=ready[0]
        # Update the existing compact return point in the same write; do not
        # leave a second, contradictory owner/phase in the human-readable head.
        a=updated.index('<!-- 接续摘要：开始 -->');b=updated.index('<!-- 接续摘要：结束 -->',a)
        head=updated[a:b]
        head,count=re.subn(r'^当前返修：[^\n]*',f"当前返修：{first['owner']}｜{first['title']}；当前节点{first['id']}。范围及例外仍按原条。",head,flags=re.M)
        check(count==1,'CURRENT_OWNER_FIELD_REQUIRED')
        if flow.get('active_batch'):
            completion='已完成：前轮证据保留；本轮逐原ID执行/独立校审结果见本MD节点，仍待用户确认，不据内部PASS删除原意见。'
            head=re.sub(r'^已完成：[^\n]*',completion,head,flags=re.M)
        elif 'base_review' in done:
            completion='已完成：本轮种植非绿化底板整体替换、逐幅自检与独立校审已通过（证据见CAD_WORKFLOW_V1）；当前继续种植未完项，整套图纸尚未交付完成。'
            if 'planting' in done:completion='已完成：本轮底板及种植节点已有完成证据；整套交付状态以原条和实际交付回执为准。'
            if re.search(r'^已完成：',head,re.M):head=re.sub(r'^已完成：[^\n]*',completion,head,flags=re.M)
        updated=updated[:a]+head+updated[b:]
    if not ready and flow.get('active_batch'):
        updated=re.sub(r'^当前返修：[^\n]*','当前返修：管理｜本轮内部执行与独立校审完成，待交用户确认；原意见及两方结果保留，不自动核销或删除。',updated,count=1,flags=re.M)
    result=updated.encode('utf-8')
    path=Path(checklist);tmp=path.with_name(path.name+'.workflow.tmp')
    check(path.read_bytes()==original,'CHECKLIST_CHANGED_RELOAD')
    with tmp.open('xb') as f:f.write(result)
    try:
        check(path.read_bytes()==original,'CHECKLIST_CHANGED_RELOAD');os.replace(tmp,path)
    finally:
        if tmp.exists():tmp.unlink()
    response={'state':'NODE_COMPLETED','node':node_id,'next':current(checklist)['next']}
    if ready and ready[0]['id']=='base_review':
        response['handoff']=packet(checklist,state,'图面送审','执行',{'node':'base_review','candidate':evidence['candidate'],'sha256':evidence['sha256'],'scope':flow['scope'],'issue':'底板逐幅自检完成，请独立校审并将差异直接交执行。','evidence':[str(Path(evidence_path).resolve())]})
    return response


def reopen(checklist,state,node_id,role,reason):
    """A failed review reopens the affected work and its dependents in the same MD."""
    check(role in ('校审','管理') and str(reason).strip(),'REVIEW_REOPEN_REASON_REQUIRED')
    check(os.environ.get('CODEX_THREAD_ID')==destinations(state)[role],'REOPEN_ROLE_IDENTITY_REQUIRED')
    original,text,start,end,flow=read_flow(checklist)
    node=next((n for n in flow['nodes'] if n['id']==node_id),None)
    check(node is not None and node.get('requirement_ids'),'CURRENT_BATCH_NODE_REQUIRED')
    affected={node_id}
    while True:
        more={n['id'] for n in flow['nodes'] if set(n['after']) & affected}-affected
        if not more:break
        affected.update(more)
    for n in flow['nodes']:
        if n['id'] in affected:
            if n.get('evidence'):n.setdefault('previous_submissions',[]).append(n.pop('evidence'))
            n.update(state='pending',reopen_reason=reason)
    updated=text[:start]+json.dumps(flow,ensure_ascii=False,indent=2)+text[end:]
    updated=re.sub(r'^当前返修：[^\n]*','当前返修：'+node['owner']+'｜'+reason+'；沿原节点返修并重新校审。',updated,count=1,flags=re.M)
    path=Path(checklist);tmp=path.with_name(path.name+'.reopen.tmp')
    check(path.read_bytes()==original,'CHECKLIST_CHANGED_RELOAD')
    with tmp.open('xb') as f:f.write(updated.encode('utf-8'))
    try:
        check(path.read_bytes()==original,'CHECKLIST_CHANGED_RELOAD');os.replace(tmp,path)
    finally:
        if tmp.exists():tmp.unlink()
    return {'state':'REOPENED','nodes':sorted(affected),'next':current(checklist)['next']}

def guard(checklist,kind):
    """Called automatically by the project facade, before queue publication."""
    if kind not in ('hatch','groundcover_create','groundcover_update'):return None
    flow=current(checklist)
    accepted=any(n['id']=='base_review' and n.get('state')=='done' for n in flow['nodes'])
    check(accepted,'BASE_FIRST: 先整体换底、逐幅自检并独立校审；当前禁止进入种植填充或新增地被标注。读取接续入口的当前节点。')
    return flow
