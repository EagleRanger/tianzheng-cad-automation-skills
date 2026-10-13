# 天正 CAD 自动化与图纸校审

天正 / AutoCAD 自动化 Skill：图纸检查校审、原生批量标注、全套图纸框架及验收边界；保留原图，不含私有驱动。

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

EagleRanger 提出需求和验收；OpenAI Codex 协助整理、包装与校审。控制逻辑沿用已审查版本，本次只拆分发布结构。
