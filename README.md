# 天正 CAD 自动化与图纸校审

**v1.2.0 · 2026-11-04 · 15 个专项 Skill，附执行源码与公开方法库**

面向 Windows 天正 / AutoCAD 的图纸修改、原生标注、施工图校审与交付。接收方 AI 可以复用已开发的公式、规划器、原生模块和后台控制链，按自己的软件环境、图纸和授权对接，不必从文字说明重新开发已有执行部分。

## 本次更新

- 从原有 3 个 Skill 扩展为 15 个：加入填充、文字、分幅、工程量、图面检查，以及乔木、灌草、坐标、标高、索引和尺寸专项入口。
- 更新连续审图与修改流程：保留原意见、同类合批、逐项验收；保护已完成且未受影响的内容，不为每次小修重复全图检查、打印或冷启动 CAD。
- **后台优先，不抢用户页面。** 复用已绑定文档和宿主，截图默认 `PrintWindow`，不静默回退前台操作。后台任务经用户验收后，保护保存稿并关闭本任务独立宿主。
- 附带公开方法库和按对象召回脚本，移除作者本机路径与历史任务依赖；补入数组式原生对象执行模块与标注布局策略源码。

## 可以做什么

按当前图纸的真实对象和要求，辅助处理原生标注、填充闭区、尺寸与角度、乔木组串线、灌草面积引出、坐标和标高、索引、文字样式、布局分幅、工程量对账、图面检查及图册交付。保留原生可编辑语义，不用散件或图片假冒天正对象。

新增专项主要是可迁移的方法、判断与核验规则，**不是 15 个开箱即用的全自动命令**。批量 ARC/LINE 命令继续保留原有验证候选边界；具体拓扑、软件版本、捕获和显示能力需在接收方环境核实。

## 下载与安装

[下载 v1.2.0 完整 ZIP](https://github.com/EagleRanger/tianzheng-cad-automation-skills/releases/download/v1.2.0/tianzheng-cad-automation-skills-v1.2.0-20261104.zip)

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
3. 阅读 [执行源码与迁移说明](skills/tianzheng-batch-polyline-dimension/references/migration.md)及 [新增原生对象模块](skills/tianzheng-batch-polyline-dimension/runtime/docs/native-annotation-job.md)。实际公式、AutoLISP、Python、PowerShell 和 C# 源码放在批量标注目录的 `runtime/`。
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
