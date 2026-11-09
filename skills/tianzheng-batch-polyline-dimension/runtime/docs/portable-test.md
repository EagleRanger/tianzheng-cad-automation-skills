# 先测试：一张隔离 DWG，少量 ARC/LINE

本包保留 15 个 Skill 和已有业务实现，附真实启动/监督模块与接收机测试入口。不含商业 CAD/天正、SDK、作者私有图纸、旧 READY 或凭据；本测试入口不自动安装、不自动保存图纸、不上传。建议解压到短且只含 ASCII 字符的路径，尤其是 AutoCAD 2018。

在本目录的上一级 `runtime` 用 PowerShell 7.5 或更新版运行：

```powershell
./scripts/Invoke-PortableCadTest.ps1
```

`PASS / offline_package_and_import` 只表示包完整性与模块可导入；不会启动或接管 CAD。

1. 选择一张自有测试 DWG（建议简单、无缺失外部参照），用 CAD 的 LIST 获取 1–5 个模型空间轻量多段线句柄，至少有一段弧和一段直线。关闭查看原图的 CAD 后再启动隔离测试。偏移量按图纸单位和真实外侧选择，不照搬示例值。

   ```powershell
   $test = ./scripts/Invoke-PortableCadTest.ps1 -Stage Prepare -SourceDrawing 'C:\your-test.dwg' -SourceHandles '2A,2B' -Group ROAD -Offset 2
   ```

   Prepare 拷贝图纸、核对原件和副本 SHA-256、生成一次性测试输入和自有原生执行脚本，不会动 CAD。

2. 自己结束其他 CAD/天正任务，使用本机真实的天正启动快捷方式。Open 会启动可见窗口；如有平台选择，手动选已安装的版本。启动失败保留现场，不自动强杀或重跑。

   ```powershell
   ./scripts/Invoke-PortableCadTest.ps1 -Stage Open -RunDirectory $test.run -TianzhengShortcutPath 'C:\path\your-tianzheng.lnk' -ConfirmIsolatedDesktop
   ```

3. 确认窗口打开的是新生成的 `cadtest-*.dwg`，图纸未编辑。执行下式，在控制台指定时间内，将它输出的 **一条** `(load ...)` 粘贴到该测试窗口的 CAD 命令行。只在测试目录和脚本来源可信时允许 CAD 加载；不关闭全局安全检查。

   ```powershell
   ./scripts/Invoke-PortableCadTest.ps1 -Stage Run -RunDirectory $test.run -ConfirmWriteToTestCopy -WaitSeconds 300
   ./scripts/Invoke-PortableCadTest.ps1 -Stage Review -RunDirectory $test.run
   ```

   控制器核对本机 PID、进程启动时间、程序路径、窗口、图纸和脚本摘要；持真实互斥锁发放本次 READY，并写不可重复的 claim。CAD 内再核实际打开的完整路径、`DBMOD=0` 和范围句柄后领取，调用原有 V12 原生 ARC/LINE 自动标注，不全图选取、不自动存盘。该测试路径由人触发 CAD 内的一次加载，不冒充双窗口 Exact-B 自动派发。失败或等待超时先看 `lifecycle.json`、`dialogs.jsonl`、`test-receipt.json`，不要重复加载或伪造状态；若 CAD 已领取但未返回，先查正在运行的操作。

4. 查看 `summary.tsv` 和 `details.tsv`，对照源段及新增对象句柄；用 LIST/属性核直线为原生线性标注，弧段为原生角度而非弧长，并保存截图做图面复核。若要验证持久性，由测试人**另存为新的测试文件**再重开核对，不覆盖原件。离线校验和报告可读都不等于视觉验收。

## 2018 的额外验证

单图原生 LISP 测试不调用外部 AutoCAD COM ROT，也不要求先 NETLOAD。若还要验证 .NET 原生读取、布局和其他辅助命令，用本机匹配版本的 SDK 编译后，在隔离 CAD 中对照 `config/public_module_builds.json` 验证 NETLOAD、CommandMethod 和 LispFunction 实际注册；不能借用 2021 的构建结论。构建命令和本机信任摘要见 [运行时说明](../README.md#构建与信任)。

原项目的双窗口 Exact-B、项目 V8 派单和专项脚本保留源码及真实检查，须对接接收方工作流；本次单图测试不迁入作者的任务权限，也不证明任意图纸、2018 各模块或正式生产运行均已通过。
