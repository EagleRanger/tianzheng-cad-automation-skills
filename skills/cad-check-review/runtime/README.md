# CAD session runtime source

这是 `cad-session-components` 0.6.6 的可迁移源码快照，仅安装到
`skills/cad-check-review/runtime/`。它与旧 batch runtime 共存，不互换或覆盖。
本包带现成 Python / PowerShell 控制链、C# 原生实现与离线测试，不要求接收 AI 重写。

## 功能与真实边界

- 会话精确绑定、主机身份、原子队列与单次提交、请求回执、保存点、失败恢复、专属后台生命周期。
- 原生几何/显示读取；文字、表格、图例、填充、地被、坐标、标高/索引更新；底板替换、纸空间/布局/视口控制。
- 构建模块完整目录见 `cad_components.py` 的 `MODULE_SOURCES`；调用参数用 `cad_session_client.py describe [kind]` 查询。
- 源方法有原机器分项成熟证据，但本次源码组合仅做离线验证/编译；不声称新机实测或工程成图验收。
- `paper_roots_copy` / `paper_roots_activate`：保留实现；实际显示仍 HOLD，不作为正式推荐入口。
- `paper_leaders_copy`：五个代表对象的原生复制、保存重开和 CLI 曾通过；保色显示仍待核，不以属性一致冒充图面通过。
- 当前共享 `CadAdapterContractV1` 对 groundcover 仅有对应离线验证，不等于新编译组合已在 CAD 加载实测。
- 所有工程对象、源图、授权、参数、图面及全套验收由接收方的原项目负责；本包不携带它们。

## 依赖及最小接入

Windows x64、Python 3.11+（标准库）、合法安装/授权的 AutoCAD 2021 / 天正 T20 V10。
离线编译使用机器 .NET Framework C# compiler 及本机 AutoCAD 的
`acdbmgd.dll` / `acmgd.dll` / `accoremgd.dll`，不分发 Autodesk/Tianzheng 二进制。
其他 CAD ABI 未验证，不可更名冒充兼容。截图默认 PrintWindow；不自动前台回退。

1. 将此目录完整放进上述 Skill runtime；不要把已运行宿主的 DLL 热替换。
2. `python -X utf8 cad_components.py discover --output <私有机器配置.json>`，在包外核配置。
3. `python -X utf8 cad_components.py doctor --environment <私有机器配置.json>` 仅检查依赖，绝不代表加载/保存/图面验收。
4. `python -X utf8 cad_components.py build --environment <私有机器配置.json> --module <模块名> --output <包外新DLL>`。
5. 扩展模块沿 `cad_runtime/bound_edits.py::verified_release` 读取各自 `*.release.json`。
   这些登记包含机器私有路径与验证证据，故不随包；接收机验证后登记自身 DLL、SHA256、适配器绑定、命令及证据。
   缺登记会明确拒绝，不应绕过哈希/适配器/保存保护。参见现成模块函数及接入说明，不重写执行控制链。
6. 使用项目自己的 base job、独立工作副本及原技术状态，通过 `start_cad_module.ps1`
   的 `-Job -ExpectedJobSha256 -Dll -EnvironmentFile -ProjectState` 接入新专属宿主；已有宿主沿原状态恢复。
   业务 CLI 必须显式 `--state <项目原技术状态.json>`，不能把安装目录当作项目。
7. 首次目标机在用户授权的隔离图上验加载、来源/依赖、定位、代表修改、保存读回和实际图面；完成后再决定扩展。

离线测试：`python -X utf8 -B -m unittest discover -s . -p "test_*.py"`。
Windows 中文环境需显式启用 UTF-8，避免测试按系统 GBK 编码读取中文回执。
测试使用临时合成数据与 mocks；实际 CAD、付费模型和通知不属于离线验证。
`CAD_review_20261027` 是现有项目流程适配器兼容字段名，不携带真实项目状态；不同项目接入须保留原项目权威状态，不复制旧工程。

`source-manifest.json` 描述本包内容身份；私有来源原路径、完整源SHA和编译/测试日志不在包内。
源快照的 __init__ 为0.6.6，而 components.json仍为0.6.4；公开副本仅机械对齐元数据，未改变生产源或业务逻辑。

## 扩展模块登记合同（准确模板，不是已验证登记）

现有工具没有 `register` 子命令；登记文件是配置数据，不是新执行器。
`build` 生成的 `<模块>.build.json` 已含 dll、sha256、commands、sources，状态仅为 COMPILED_NOT_LOADED。
在接收机完成对应原生隔离验收后，把这些真实字段填入下面合同，并以既有路由要求的文件名放在 runtime 根。
不要只把编译回执的状态改成“已验”；原生保护、保存/重开和实际显示必须另有真实证据。

```json
{
  "status": "NOT_VALIDATED",
  "dll": "<目标机已编译且已验证DLL的完整路径>",
  "sha256": "<build回执与当前DLL一致的SHA256>",
  "entry": "<build.commands中对应生产入口，不是测试入口>",
  "kinds": ["<仅已验证的操作kind>"],
  "compatible_adapters": ["<实际绑定会话loaded_dll_sha256>"],
  "sources": {"<源码文件名>": "<build.sources中的精确SHA256>"},
  "target_machine_validation": {
    "native_receipt": "<本机原生验收回执>",
    "save_reopen": "<本机保存及读回证据>",
    "actual_display": "<本机实际图面证据或明确待验证>"
  }
}
```

此模板初态必被 `verified_release` 拒绝。真实验收后才能设
`status: ISOLATED_NATIVE_VERIFIED`；只有 source_register 可用 NATIVE_METADATA_VERIFIED。
显式 kinds 保持发布操作范围；默认使用 compatible_adapters 精确SHA分支，不为移机删除适配器绑定。
既有 `adapter_contract: V736_NATIVE_EXTENSION_V1` 是另一个已有的运行合同分支，只有原生模块确实采用且接收机已验证该合同才登记，不能为绕开SHA临时添加。
sources 是构建来源证据，运行时仍逐次核 DLL SHA、命令存在、适配器/宿主/文档/保存点身份。

例如 `--module textformat` 的生产入口为 `HLCADTEXTFORMATV11`（不是 `...TEST...`），
对应登记名 `NativeTextFormatV1.release.json`，kinds仅填实际验过的 text_read/text_format/text_style_import/erase 子集。
其他准确登记文件名见 `cad_runtime/bound_edits.py::verified_release` 的完整路由；
每个入口必须存在于本机 build.commands 及本包 C# CommandMethod，不猜旧DLL版本。
`viewport_freeze` 还必须用 `HLCADVIEWPORTFREEZEV<数字>` 专用入口，不能登记通用 BoundApply。
恢复模块 `RecoverPaperCheckpointV1.release.json` 的必需字段为 status/dll/sha256/entry，
状态同样仅允许真实 ISOLATED_NATIVE_VERIFIED；恢复链仍绑定原请求，不重放写入。
部分历史失败恢复器保留已知故障实现的固定SHA白名单，只处理精确匹配的历史失败；
这是原有fail-closed保护，不是通用恢复许可。新机新编译模块或未知失败不得删除这些检查强行套用。
