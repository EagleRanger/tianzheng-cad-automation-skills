# Tianzheng native dimension runtime sources — 1.1.1

本目录补齐已有原生 ARC/LINE 标注、布局公式/规划、特殊文字恢复、原生读写、精确 owner 传输和构建源。不是任意 DWG 一键全自动成品，也不继承作者电脑的运行权限。

成熟度保持不变：完整命令包是 `VALIDATION_CANDIDATE`；特殊文字子链只有原底板 3/3 证据；精确 B 通道只有限定混合 ARC/LINE 功能验证。跨结构 DWG、新机加载、整图视觉、保存重开与完整连续三次均未由本包证明。

## 文件与真实执行入口

`public-runtime-manifest.json` 是唯一公共文件清单，`files` 含相对路径和 SHA-256；`public-runtime-receipt.json` 是本次离线验证记录，不是 CAD 运行状态。`config/public_module_builds.json` 记录 7 个自有模块的真实源码与构建依赖，区分 `CommandMethod` 命令和 `LispFunction`。

| 能力 | 已附公开路径 | 接入边界 |
| --- | --- | --- |
| 运行时 ledger→原生 ARC/LINE batch | `scripts/compile_selected_typed_segment_batch.py`、`scripts/tdimarc_native_full_batch.lsp` | 使用接收方当前几何、隔离副本和 scope，不固化作者目标。 |
| 普通布局规划 | `scripts/plan_typed_dimension_quantified_common_band.py`、`scripts/annotation_layout_formula.py`、`config/annotation_vector_layout_formula_v2.json` | 文字高 H、源宽、拓扑和原生夹点来自本次实测。 |
| 特殊文字 grip4 | `scripts/plan_special_text_peer_normal_restore_v2.py`、`scripts/invoke_special_text_peer_normal_restore_observed_v4.ps1` | 原 controller 保留单 acad 门和原生回读；不是双窗口通用控制器。planner 的 WCS DX/DY 不重算。 |
| 精确 B 传输 | `scripts/cad_exact_b_focus_independent_transport_v4.ps1` 及同目录 V1/V2/V3 helpers、`reports/cad_multi_window_interface_research/` 实际依赖源 | 函数库完整；不导入就自动执行。真实 READY/claim/lease、A/B owner、scope/manifest/hash 和受限 worker 必须接收方绑定。focus 仅观察，不夺焦点。 |
| 原登记完整工作流 | `reference/project-orchestration/scripts/invoke_selected_typed_dimension_workflow.ps1` → 同区 `invoke_selected_typed_dimension_batch.ps1`、`invoke_selected_typed_dimension_layout_stage.ps1`，共享脚本按实际映射定位 | 保留完整已开发控制链，项目根与跨文件路径已映射；其原项目治理输入须对接接收方自己的合同，不能跳过 guard。不是开箱即用默认入口。 |
| 原逐源部分收敛 controller | `reference/project-orchestration/scripts/invoke_selected_typed_dimension_polyline_controller.ps1` | 已通过子集冻结、仅失败子集处理；仍保留原 scope/owner/未保存与验收门。 |
| 候选完整语义/布局组合 | `reference/project-orchestration/scripts/invoke_clean_full_generation_semantic_probe_v30.ps1`、`invoke_composed_layout_continuation_v33.ps1`、`invoke_post_ordinary_rescue_audit_visual_v35.ps1` 及各 trusted wrapper | 仅候选源码，不因文件齐全升级成熟度。 |

`reference/project-orchestration` 是原项目编排/治理源，不是删掉执行层。其脚本能定位已附源码；原 Loop/current 状态和作者任务登记不克隆。接收 AI 应复用业务与控制代码，将原治理接口接到本地等价的真实 scope/hash/owner/回执合同；不得删门或把静态模板填成假 READY/PASS。原 10/28 两目标恢复 harness 依赖旧 run 的已验候选/恢复数据，没有作为新图通用准备器收录。10/29 已失败 B-document bridge V4 也不是默认路径。

## 依赖与接收方配置

- Windows x64、PowerShell 7（脚本使用 `ConvertFrom-Json -DateKind String`，需对应版本支持）。`CAD_POWERSHELL` 指定实际完整路径；未设置时使用标准 `Program Files/PowerShell/7/pwsh.exe`。OwnHelperJob 保留实际 executable 的精确比较。
- Python 3：`CAD_PYTHON` 或当前 `python.exe` 应用路径。编译器/规划器多数只用标准库；截图/ROI/栅格审计另需 NumPy、Pillow。本包不携带这些库，不声称未验证的版本锁定。
- Windows 自带 .NET Framework 4.x 的 `csc/cvtres`、系统签名和 WPF 组件；受限编译保留原 kernel Job 资源/子进程/时间/输出及清理门。
- 已安装、合法匹配的 AutoCAD .NET SDK `acmgd/acdbmgd/accoremgd` 和本机天正运行环境（原验证为 AutoCAD 2021 / T20 V10）。商业 SDK/ARX、天正与 AutoCAD 本体均不分发；版本适配需接收方实测。

`config` 中 7 个公共策略/注册模板保留必要字段、阈值、动作和拒绝约束，作者历史证据/身份已移除。`templates/*.template` 只是输入结构：实际 receiver runtime/source admission、owner PID/start/image/HWND、当前 DWG hash、scope、manifest、READY/claim 和串行 lease 必须在接收方授权运行中重新建立。缺失时正确结果是 `NOT_CONFIGURED`/停止，不是绕过检查。

## 构建与信任

```powershell
$env:CAD_PYTHON = '<实际 python.exe 完整路径>'
./scripts/build_public_modules.ps1 -AutoCadSdkDirectory '<实际 AutoCAD SDK 目录>'
```

这是显式构建操作，不加载 DLL、不启动 CAD、不登记身份、不创建 READY。结果只证明本机编译；将返回的本机 `config/receiver_build_manifest.json` SHA-256 从可信构建过程保存到 `CAD_BUILD_MANIFEST_SHA256`。精确 B 不再写死作者旧 DLL hash，但仍核验该 pin、模块 hash 与绑定源码 hash。manifest 或源码改变即拒绝。构建残留不覆盖；仅显式 `-ReuseExistingVerifiedModules` 且成功回执/源/引用/产物 hash 与已清空 Job 均匹配时复用成功子集。

新机编译产物不得冒用原 DLL 哈希；`CommandMethod`/`LispFunction` 源码存在和编译通过都不证明 CAD 已加载/注册。源图 admission 另需 `CAD_SOURCE_ADMISSION_SHA256`，与构建信任分开。

## 离线检查

```text
python -B tests/run_offline_tests.py
```

执行原有三项合成算法测试，共 20 个断言案例：ledger 10、公共带几何 6、语义 4。最后 4 项按原 pytest 风格函数提供同等新鲜 `tmp_path` 标准库适配，无需安装 pytest；不改测试断言或算法。不会启动 CAD、消费 READY 或读取作者 runs。真实 CAD 操作仍须由接收方明确授权并完成原生回读和相应验收。
