# 双后台通道源码接入包（非默认执行）

本包提供已实测通道的成熟源码，不是一键部署器，也不是默认 CAD 执行入口。发布仅覆盖源码移植与离线验证，接收机尚未实机验收。

已有实机证据限定为 **2 个真实来源、2 个独立私有桌面 CAD 宿主**，各自在独立同源副本执行固定 `KNOWN_WRITE_BATCH`：1024 条原生 LINE、唯一检查点保存、独立原生数据库重读、原来源提交和读回，以及实际写事务区间的正交叠。不是任意工程命令并行、不是 3 个以上实例，也不建立尺寸/图面验收结论。

## 入口与控制链

保留 `public-source` 下的项目相对结构；可以整体作为接收项目的独立源码根。不得逐个文件扁平化。`reports/cad_multi_window_interface_research/independent_project_jobs_v3/` 是下文简称 `V11`。

`build_channel_draft_v11.ps1` → 新 run 的隔离副本、scope、manifest、boot、**DRAFT**；接收方既有受控发布/执行信封负责真正 READY 与唯一 claim（本包不签发、不伪造、不跳过）。

实际准入沿 `assert_cad_canonical_open_consistency.ps1` → canonical 组件哈希/源码语义和 `test_tianzheng_startup_fastpath.ps1` → `assert_cad_command_research_routing_v1.ps1` → 选定 V3 validator → `channel_contract_v11.ps1` 的 scope/manifest 校验。实际 V3 分支依赖的普通启动源码、平台选择器、生命周期、预算、静稳检查与白名单全部随包；未选择的其它业务路由不展开、不授权。

`invoke_channel_v11.ps1` 保留生命周期协调的**全局 CadOperationGuard**；`launch_channel_v11.ps1` 建立私有桌面及固定 boot；每个 owner 的原生模块在自己的 CAD 和 DWG 内单队列执行。`publish_channel_request_v11.ps1` 由真实来源各自调用，`receive_channel_result_v11.ps1` 由同一真实来源独立读回。来源、PID/created/HWND/document、nonce、sequence、expiry、hash、READY/claim 和禁止重放均保留。并未宣称旧 runtime 所有锁都已改成实例锁。

成熟工程模块仍沿主包各自的原生源段、算法和验收合同。本通道当前业务处理器只支持固定 LINE。接入尺寸、植物、分幅等需单独显式适配、登记、限定与实机验证；不能把 `KNOWN_WRITE_BATCH` 换成任意字符串，不能让接收 AI 重写启动/传输/回执链。

## 离线构建

需要 Windows、PowerShell 7.5+、.NET Framework 4.x C# 编译器、合法安装的 AutoCAD 2021 托管程序集（可显式指定兼容 SDK 路径）。工具和 Autodesk 程序集不随包。

旧 .NET Framework 编译器需要短源码根（例如 `C:/cad-channel`）；深目录遇到 CS2021 文件名过长时，可将整个源码目录原样复制到短路径再编译，只缩短 `OutputDirectory` 不够。

```powershell
pwsh -NoProfile -File ./build_offline.ps1 -OutputDirectory C:/receiver-build/parallel-v11
```

输出目录必须是新目录且在源码根之外。该脚本只编译三个 DLL、协议测试 EXE，运行协议测试、解析所有 PowerShell 与静态 fastpath 回归；不运行 controller/launcher/worker/restore/close，不调用 CAD/COM/窗口或写注册表。原 `build_channel_v11.ps1` 是原局部模块构建入口；推荐以上完整离线构建，不在分发源码树产生 binary。

## 接收方一次性配置（仅填写和准入，不能代替真实授权）

1. 把所有 `RECEIVER_SOURCE_A`、`RECEIVER_SOURCE_B`、`RECEIVER_COORDINATOR` 在 C#/PS/JSON 中一致绑定为本方真实身份，保留所有身份比较，随后重新编译。来源 B 在当前合同同时是生命周期执行者；不能据占位符伪造两个真实来源。
2. 配置 `config/project_execution_index.json` 的 `loop_id`、publisher，和 registry/routing 中对应真实身份、发布范围。`may_publish_ready=false`、profile/component 的 `RECEIVER_REVIEW_REQUIRED` 均是故意未准入。只有接收方当前授权和既有可信发布链能改变准入状态。现成 publisher/执行信封是接收方原生项目输入；不得为了运行包临时伪签 READY、claim、不可变回执或自制成功 JSON。
3. 本地审核 canonical 启动源码和静态回归后，将组件模板的 entry/inner SHA 填为本机实际源码 SHA，版本与 loop 保持一致。配置未激活时 canonical gate 必须拒绝，不删检查。V3 route 的 allowed operations、2-owner capability bounds、ABI 与路径字段已完整提供，不需逆向私有文件。
4. 编译输出需在接收方明确准入后按 manifest ABI 放到 V11 的 `bin/CadChannelV11.dll`、`bin/OwnStartupJobV4.dll` 与 `reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll`。`config/parallel_receiver.json.helper_sha256` 填 **本机实际 helper DLL SHA**，不能使用作者二进制 hash。此配置本身也进入新run的 manifest/boot依赖hash；须在生成新DRAFT前填完，运行中不可修改（修改需新run重新绑定/准入）。本包不自动安装或复制到信任目录。
5. 为 helper 明确绑定安装的 PowerShell：`$env:CAD_PARALLEL_PWSH_EXE=(Get-Command pwsh -ErrorAction Stop).Source`。C# 仍要求文件存在、leaf=`pwsh.exe` 且传入路径精确等于该固定路径；不允许任意 executable。生命周期模板使用相同安装入口。
6. DRAFT 生成器的必填输入是 `-RunId`（新且不可重用）、`-SourceRelativePath`（源码根内受保护 DWG）、`-SourceSha256`（其实际大写 SHA256）、`-TianzhengSys`（本机 SYS24x64）。七个 ARX 的完整路径和实际 hash 会绑定进 boot，合同仍逐项比较。AutoCAD2021 安装路径与 T20 V10 的当前用户 trusted 目录保留标准默认；若接收机不同，须显式统一修改 launcher、publisher 和 helper 的 exact-image 对照并重新建 hash，不可放宽比较。
7. `templates/channel_handoff.draft.json` 是完整非 READY 基础模板，替代历史 handoff 继承；用户授权栏必须记录接收方本轮实际授权，不继承作者授权。实际执行前以同 run 的不可变 READY/claim/manifest/scope 进入原受控入口。

本包只有接收方发布/唯一 claim 的接口合同，**不包含一个可对新项目自动授权的 READY 发布器**。这属于接收方既有授权系统的外部依赖，而非缺失启动/传输/业务/关闭算法。配置没填完时停止在明确 gate，不让 AI 绕门补造。

## 保护关闭是独立步骤

controller 的 finally 对活宿主仅写 `PENDING_EXECUTOR_PROTECTED_CLOSE`，**不会关闭 CAD**。不能把业务完成或 helper 退出说成 CAD 已退出。

`lifecycle-templates/A/` 保留成熟的六文件链：`invoke_identity_read.ps1`+根 worker → `invoke_save.ps1`+`save/startup_tip_worker_v4.ps1` → `invoke_close.ps1`+`close/startup_tip_worker_v4.ps1`。仅将实例化值换成非运行绑定模板，未造新的通用关闭器。复制到本轮 `runs/<fresh-run>/resource_closeout/<owner>/` 后，由执行者一次性绑定实际 root/run/owner/私有desktop、PID/created/HWND、源 work 全路径、唯一保护副本、实测 DBMOD 与关闭前独立 shared-read SHA；模板的 `PID/created/HWND=0`、`DBMOD=-1`、占位 hash 不能直接运行。B 使用同一成熟链但须独立绑定 B，绝不把 A 绑定改标签冒充 B。

保持 worker leaf `startup_tip_worker_v4.ps1`（OwnStartupJobV4 的白名单）。COM 候选只在该私有桌面内获取，先核 PID/created/HWND，再访问精确完整文档。先 identity 结果 `READ_COMPLETE_NO_CLOSE` 且唯一未保存文档状态一致，再 SaveAs 新副本及读取 `SAVE_RETURNED_VERIFY_INDEPENDENTLY`；独立调用 `scripts/get_shared_file_sha256_v1.ps1 -Path <protected>`，确认非空/实际 SHA 后才允许 close；`QUIT_RETURNED_VERIFY_PROCESS` 仍需随后核进程实际消失，禁止自动 kill。最后只在该 PID 已不存在时执行 `restore_cad_manual_dialogs_after_exit.ps1 -ClosedProcessId <pid> -ExecutablePath <exact-acad>` 并用 `-CheckOnly` 读回；它会修改该精确版本 profile 的两个对话设置，须在接收方授权范围内。本轮发布验证没有执行这些步骤。

## 架构来源与范围

参考 [cad-mcp 多实例](https://github.com/shtirlitsDva/cad-mcp/blob/master/docs/acd-mcp.md) 与 [dwg-mcp 架构](https://github.com/bimwright/dwg-mcp/blob/master/ARCHITECTURE.md) 的“工具端适配、会话隔离、请求/结果边界”思路；这里保留本项目成熟的 private desktop、固定原生模块和 own-job 控制链，没有复制其管道实现。参考来源不表示依赖、AutoCAD 2021 即插即用兼容或第三方代码已打包。

不含真实 DWG、DLL/EXE、凭据、私有来源 ID、旧 run 回放器、机器运行配置和作者历史 PLAN。源码清单与 hash 在 `public-source-manifest.json`；离线通过不等于接收机部署成功或 CAD 实机验收。
