# 天正 CAD 自动化与图纸校审

**v1.1.0 · 2026-10-26**

## 本版更新

- **原生标注更完整：** 补充整体引出、多落点拓扑、坐标/尺寸语义保护与折角复核，不把单一模板夹点规则套给所有对象。
- **图面校审更贴近真实内容：** 保护用户当前手改；将嵌套块文字、桩号、无文字引线及原生显示部件纳入检查范围，避免只看新增对象和粗略包围盒。
- **打印、保存与收尾：** 补充准确文档打印防串图、当前图签目录、固化候选的独立副本重开及过程稿窗口管理。
- **批量标注复用：** 先用成熟共同成带公式，只修已证异常子集；区分用户样本接受、落盘、重开几何和文字语义，不把局部成功提升为整包通用。
- **迁移边界清楚：** 保留3个Skill与已有脚本接口；不附私有执行器、项目图纸和运行记录，不把尚未验收的多窗口并发写入当可用功能。

详见 [更新记录](CHANGELOG.md) 与 [近期可迁移实践](skills/tianzheng-cad-automation-framework/docs/recent-practices.md)。本轮是公开方法和接入包更新，没有借发布启动CAD、改图或补跑业务；接收方仍须在自己的环境验证。

天正 / AutoCAD 自动化 Skill：图纸检查校审、原生批量标注、全套图纸框架及验收边界；保留原图，不含私有驱动。

<!-- project-support:start -->
> 如果本项目对你或你的 AI 开发有帮助，下载使用或借鉴后，欢迎点个 [Star](https://github.com/EagleRanger/tianzheng-cad-automation-skills) 支持，也让更多有同类需求的人找到它。
<!-- project-support:end -->

这是独立的软件自动化项目，源文件、安装包和版本在本仓库分别维护。总合集只提供[项目分类索引](https://github.com/EagleRanger/windows-app-automation-skills)，不替代本仓库。

## 包含内容

- [cad-check-review](skills/cad-check-review/SKILL.md)
- [tianzheng-batch-polyline-dimension](skills/tianzheng-batch-polyline-dimension/SKILL.md)
- [tianzheng-cad-automation-framework](skills/tianzheng-cad-automation-framework/SKILL.md)

## 下载与安装

从[本项目 Release](https://github.com/EagleRanger/tianzheng-cad-automation-skills/releases/latest) 下载独立 ZIP，解压后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -All
```

安装器只复制本仓库的 3 个 Skill，可通过 `-Skill` 选装或 `-Destination` 指定目录。
相同内容重复安装不变，已有不同版本拒绝覆盖；`-WhatIf` 仅预览。不启动应用、不登录、不修改其他 Skill，不自动安装软件、后端或大模型。

## 使用条件与边界

框架与可复用脚本不等于完整私有执行器。批量标注需要接收方自行配置兼容的项目执行环境；本仓库不附公司图纸或私有 CAD 驱动。

保留原 Skill 里的实测版本和失败边界；迁移包安装通过不等于接收方电脑已完成真实应用连接或业务验收。仅在当前用户授权范围内操作，保护已有文件与窗口。

## 来源、许可与贡献

见 [分项许可与来源](LICENSES.md)，以及各 Skill 保留的第三方说明。本包不含账号、密码、API 密钥、Cookie、生产图纸、私人日志和本机缓存。

EagleRanger 提出需求和验收；OpenAI Codex 协助方法整理、包装、离线验证与校审。现有控制脚本接口保留，本版更新可公开的校审经验、接入说明和边界；不宣称提供完整私有驱动。
