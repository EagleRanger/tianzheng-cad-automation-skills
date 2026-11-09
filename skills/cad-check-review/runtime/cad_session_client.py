"""Stable CAD CLI facade. Each effect belongs to its named module; no CAD startup here."""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
_RUNTIME=Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path: sys.path.insert(0,str(_RUNTIME))
from cad_runtime.common import ClientError,check
from cad_runtime.storage import read,digest,encode,same,atomic_new,lock
from cad_runtime.protocol import KINDS,SUCCESS,number,bounds,target,targets,validate
from cad_runtime.host import process_identity
from cad_runtime.machine import load_profile
from cad_runtime.binding import STATE,update_pointer,load_binding,bind
from cad_runtime.receipts import request_records,status_view,settled,resolve_failed_base
from cad_runtime.session import snapshot
from cad_runtime.planning import approved_sources,build_job
from cad_runtime.submission import submit
from cad_runtime.evidence import capture
from cad_runtime.workflow import describe
from cad_runtime.layers import read_layers
from cad_runtime.lifecycle import finish_close
ROOT=Path(__file__).resolve().parent.parent

def brief(state_path=STATE):
    try:
        binding = load_binding(state_path); snap = snapshot(binding)
        rows = ["执行会话（自动读原队列；不启动CAD）：" + snap["state"], "会话目录：" + snap["session_dir"]]
        if snap.get("saved_checkpoint"): rows.append("实际技术保存点：" + str(snap["saved_checkpoint"]["last_saved"]))
        unresolved = [r for r in snap["requests"] if not settled(r)]
        rows.extend("未决：" + r["state"] + "；" + r["request"] for r in unresolved[-3:])
        done = [r for r in snap["requests"] if r["state"] == "RECEIPTED"][-3:]
        rows.extend("最近已回执（不重发）：" + str(r.get("id")) + "；" + r["receipt"] for r in done)
        rows.extend("失败已收口（未执行，不重发）：" + str(r.get('id')) + '；' + r['receipt'] for r in snap['requests'] if r['state']=='RESOLVED_REJECTED')
        rows.append("核对指定历史动作：status --id <原请求ID>；最近列表仅用于定位回执，不替代业务完成判断。")
        rows.extend(snap["issues"]); rows.extend(snap["warnings"]); rows.append("下一步：" + snap["next_action"])
        rows.append('执行接口：python -X utf8 "' + str(Path(__file__).resolve()) + '" describe；prepare/submit只传kind、id、params文件，不手写request.json。')
        return "\n".join(rows)
    except (OSError, ValueError, KeyError) as exc:
        return "执行会话未接妥（不影响原要求读取）：" + str(exc)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, default=STATE, help="测试或当前项目原技术状态路径")
    subs = parser.add_subparsers(dest="command", required=True)
    status = subs.add_parser("status"); status.add_argument("--id", help="只读精确原请求；不重发、不切稿")
    finish = subs.add_parser('finish_close',help='原生保护并关文档后，正常关闭同一专属窗口并核进程退出')
    finish.add_argument('--id',required=True)
    resolve = subs.add_parser('resolve_failed_base',help='管理仅凭原生失败与当前空闲证据收口；保留失败回执，不重发不写DWG')
    resolve.add_argument('--id',required=True);resolve.add_argument('--probe',type=Path,required=True)
    cap = subs.add_parser("capture"); cap.add_argument("--id", required=True)
    layers = subs.add_parser("layers", help="只读当前文档指定图层；不解冻、不保存、不打开其他DWG")
    layers.add_argument("--id", required=True); layers.add_argument("--names", nargs="+", required=True)
    desc = subs.add_parser("describe"); desc.add_argument("kind", nargs="?")
    reg = subs.add_parser("bind"); reg.add_argument("--job", required=True); reg.add_argument("--launch"); reg.add_argument("--loaded-dll")
    for name in ("prepare", "submit"):
        sub = subs.add_parser(name); sub.add_argument("kind", choices=KINDS); sub.add_argument("--id", required=True); sub.add_argument("--params", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "status":
            result = status_view(snapshot(load_binding(args.state)), args.id)
        elif args.command == 'finish_close':result=finish_close(load_binding(args.state),args.id)
        elif args.command == "describe": result = describe(args.kind)
        elif args.command == 'resolve_failed_base': result=resolve_failed_base(Path(load_binding(args.state)['session_dir']),args.id,args.probe)
        elif args.command == "bind": result = bind(args.job, args.launch, args.loaded_dll, args.state)
        elif args.command == "capture": result = capture(load_binding(args.state), args.id)
        elif args.command == "layers": result = read_layers(load_binding(args.state), args.id, args.names)
        else: result = submit(load_binding(args.state), args.kind, read(args.params), args.id, args.command == "prepare")
        print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"state": "REJECTED_BEFORE_QUEUE", "error": str(exc)}, ensure_ascii=False))
        return 2
    return 0

if __name__ == "__main__": sys.exit(main())
