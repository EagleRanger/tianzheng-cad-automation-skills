# 天正 CAD 自动化与图纸校审

**v1.3.0 · 2026-11-09 · 15 个专项 Skill，附完整后台组件与执行源码**

先读 [后台运行组件](skills/cad-check-review/runtime/README.md)；批量标注另有 [接收机测试说明](skills/tianzheng-batch-polyline-dimension/runtime/docs/portable-test.md)。安装只复制文件，不覆盖现有不同内容。

面向 Windows 天正 / AutoCAD 的图纸修改、原生标注、施工图校审与交付。接收方 AI 可以复用已开发的公式、规划器、原生模块和后台控制链，按自己的软件环境、图纸和授权对接，不必从文字说明重新开发已有执行部分。

## 本次更新

- 加入完整单宿主后台会话组件：环境发现、源码构建、文档绑定、一次提交、原生执行、保存回执、后台截图和安全收口；复用已绑定宿主，不抢用户前台。
- 扩充已有原生模块与接口：表格修改和行处理、文字格式与图名、填充与地被、坐标及标高、视口和布局、纸空间限定操作，附源码、协议和测试。
- 同步15个专项Skill中的合批修改、执行与校审直接闭环、只修失败部分、过程稿保护和资源管理方法；减少重复打开CAD及重复验收。
- 提供完整生命周期与批量标注迁移代码、包内方法索引和接收机自测入口，不依赖作者的对话记忆、工程目录或已编译DLL。

适用边界：成熟控制链为单个专属后台宿主；双宿主并发仍未验收。纸空间整根复制保留显示HOLD，窄引出复制的技术成功不等于保色/图面通过。新机及其他CAD版本须独立实测；公开包不含图纸、机器配置、账号或商业软件。

## 可以做什么

按当前图纸的真实对象和要求，辅助处理原生标注、填充闭区、尺寸与角度、乔木组串线、灌草面积引出、坐标和标高、索引、文字样式、布局分幅、工程量对账、图面检查及图册交付。保留原生可编辑语义，不用散件或图片假冒天正对象。

专项Skill包含方法、判断与核验规则，并配套已有运行模块，但**不是 15 个开箱即用的全自动命令**。批量 ARC/LINE 命令继续保留原有验证候选边界；具体拓扑、软件版本、捕获和显示能力需在接收方环境核实。

## 下载与安装

解压至较短路径，安装完整家族以保留专项之间的方法依赖：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -All
```

安装器只复制文件，不启动 CAD、不登录、不改图，也不覆盖已有不同内容；`-Destination` 可选位置，`-WhatIf` 仅预览。已有同名旧版时，由接收方 AI 比较后合并或先备份，不覆盖本地改动。

如用 Git 下载，在 Windows 上启用该次克隆的长路径支持：

```text
git -c core.longpaths=true -c core.autocrlf=false clone https://github.com/EagleRanger/tianzheng-cad-automation-skills.git
```

## 接收方 AI 从哪里开始

1. 阅读 [CAD 主入口](skills/cad-check-review/SKILL.md)，用 `scripts/resolve_cad_method.py --workflow` 看全流程，或 `--query "对象与动作"` 定位本类方法。索引、必要规则与已附实现均使用包内路径，不需要作者的对话记忆或私有知识库。
2. 保留完整 `skills/`。专项间会复用主入口的规则和相邻 Skill；只取一个 `SKILL.md` 不等于完整安装。
3. 阅读 [执行源码与迁移说明](skills/tianzheng-batch-polyline-dimension/references/migration.md)及 [新增原生对象模块](skills/tianzheng-batch-polyline-dimension/runtime/docs/native-annotation-job.md)。会话与原生操作源码位于 `cad-check-review/runtime/`；批量标注公式、AutoLISP、Python、PowerShell 和 C# 位于批量标注目录的 `runtime/`。两套入口按用途调用，不互相替换。
4. 按接收方实际安装合法取得软件、SDK 和公开依赖，绑定自己的工作副本、真实文档和运行范围。构建不等于加载，静态检查不等于真实图纸验收；不要伪造 READY、源句柄或成功回执。

## 包含的专项

| 范围 | Skill |
| --- | --- |
| 修改、校审、方法召回 | `cad-check-review` |
| 填充、文字、布局、数量、图面 | `cad-area-hatch`、`cad-text-style`、`cad-layout-sheet`、`cad-quantity-table-review`、`cad-drawing-visual-review` |
| 乔木与种植 | `cad-tree-group-annotation`、`tianzheng-planting-annotation`、`tianzheng-groundcover-annotation` |
| 坐标、标高、索引、尺寸 | `tianzheng-coordinate-annotation`、`tianzheng-elevation-annotation`、`tianzheng-index-annotation`、`cad-dimension-annotation` |
| 批量原生尺寸执行源码 | `tianzheng-batch-polyline-dimension` |
| 全套图纸自动化架构 | `tianzheng-cad-automation-framework` |

## 验证与来源

本版发布核对源码完整性、包内导航、离线算法、安装复制及远端下载一致性；发布过程不启动 CAD、不修改图纸、不接管前台。不附私有图纸、截图、历史运行数据、任务身份、账号或商业软件/SDK。

[分项许可与来源](LICENSES.md)保持有效。EagleRanger 提出需求和验收，OpenAI Codex 协助开发整理、迁移打包与验证。已有第三方代码按原来源和许可使用，不重新授予商业软件权利。

如果实际下载、使用或借鉴后觉得有帮助，欢迎自愿点个 [Star](https://github.com/EagleRanger/tianzheng-cad-automation-skills)。[办公软件控制合集](https://github.com/EagleRanger/windows-app-automation-skills)为独立分类索引，本仓库独立维护。
