# 天正 CAD 自动化与图纸校审

**v1.1.1 · 2026-10-29 · 含原生标注执行源码**

面向 Windows 天正 / AutoCAD 的图纸校审、原生标注与受控自动化 Skill。保留可编辑原生对象、保护原图，供接收方 AI 使用现有代码对接自己的 CAD 环境。

## 可以做什么

- 读取目标多段线的直线、圆弧及关联信息，调用已有原生尺寸生成代码；圆弧标注角度，直线标注长度。
- 复用尺寸带排布、异常角度与文字锚点修复算法，并检查原生对象、端点关联和文字碰撞。
- 生成图纸校审红框和问题说明，核对保存前后与独立重开结果。
- 使用受控会话、精确文档绑定及已有后台接口。**后台优先，不默认抢占用户页面**；需要界面的步骤必须另有相应授权，后台失败不自动改为鼠标盲点。

这些能力按各自验证范围复用：特殊文字修复有原样本稳定性记录；完整批量命令仍保留 `VALIDATION_CANDIDATE` 状态，跨结构图纸与接收方新机器需验证。**源码迁移版不等于任意 DWG 一键全自动，也不承诺全部命令或多窗口并发写入均已验收。**

## 本版内容

3 个 Skill 保持独立：

- [图纸校审](skills/cad-check-review/SKILL.md)
- [天正原生批量标注](skills/tianzheng-batch-polyline-dimension/SKILL.md)：包含实际公式、规划器、AutoLISP、PowerShell 控制、C# 原生模块源码及相应构建/对接材料。
- [全套图纸自动化框架](skills/tianzheng-cad-automation-framework/SKILL.md)

执行源码放在批量标注 Skill 的 `runtime/` 中，随 Skill 一起安装。接收方需要配置自己的软件、解释器、图纸副本和真实会话输入，不需要重新编写已有的标注算法。第三方软件、商业 SDK/许可和作者的图纸、账号、运行状态不随包分发。

## 下载与安装

**[下载 v1.1.1 完整 ZIP](https://github.com/EagleRanger/tianzheng-cad-automation-skills/releases/download/v1.1.1/tianzheng-cad-automation-skills-v1.1.1-20261029.zip)** · [迁移说明](skills/tianzheng-batch-polyline-dimension/references/migration.md)

解压后安装全部或指定 Skill：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -All
```

安装器只复制目录，不启动 CAD、不登录、不自动改动已有不同版本；`-Destination` 可选安装位置，`-WhatIf` 只预览。保留整个批量标注目录，不能只取 SKILL.md 或遗漏 runtime。

接收方 AI 先读迁移说明、检查源码清单，再按本机实际环境安装公开依赖、构建自有模块及绑定新任务。首次在用户允许的隔离副本上验证；保留精确对象、哈希、范围和保存约束，不用作者历史运行数据充当新机授权。

## 验证与边界

本次发布检查源码、配置、离线算法、安装复制与包体/远端一致性；没有借发布启动 CAD、修改真实图纸或接管前台。编译通过、文件齐全和离线测试通过均不能替代新机加载、原生对象、保存重开及图面验收。

后台与完整命令成熟度分开。已知未通过的连接候选不作为默认可用路线；不以专有格式拆散、文字覆盖或图片替代原生标注来制造成功。

## 来源与支持

[分项许可与来源](LICENSES.md)保持有效；商业 CAD 程序及 SDK 由接收方合法取得，不随包重新授权。EagleRanger 提出需求和验收，OpenAI Codex 协助代码整理、迁移打包与核验。

如果实际下载、使用或借鉴后觉得有帮助，欢迎自愿点个 [Star](https://github.com/EagleRanger/tianzheng-cad-automation-skills)。[办公软件合集](https://github.com/EagleRanger/windows-app-automation-skills)提供分类索引与整包，本仓库继续独立维护。
