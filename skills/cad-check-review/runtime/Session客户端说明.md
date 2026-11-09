# CAD执行短入口

换模型不重新找图、不重启宿主、不重读历史。

## 一次操作

```powershell
python -X utf8 cad_session_client.py describe <kind>
python -X utf8 cad_session_client.py --state <原技术状态.json> submit <kind> --id <本批稳定ID> --params <参数.json>
python -X utf8 cad_session_client.py --state <原技术状态.json> status --id <同一ID>
```

已知参数直接submit；describe按需，prepare仅预演。程序填写输入/哈希/保存路径/回执，不手写request.json。同一ID不重复执行，未决或异常只查这次回执。写前明确拒绝不是保存成功，也不要求重启；发生部分改动或状态未知才保护恢复。

## 只查所需内容

- 模型：`inspect {space:"Model",handles:[...]}`或bounds；纸空间：page_map。
- 全局层：`layers --id <观察ID> --names <准确层名>`；单视口：`viewport_details`。
- 天正原生值/夹点/显示子件：`native_details`；不是截图识别。 分解出的文字附`text_style`（实际样式名、字体及大字体；不可读明确UNKNOWN）和分解层级，沿原入口读取，不炸生产原件。
- 图例仅调疏密：原`table_patch.legend_hatches`传`block`、`handle`、`pattern_scale`即可；无需`rectangle`，不重写边界，按原图案名刷新显示。需要改范围时才另传`rectangle`。
- 实际图面：inspect附view后`capture --id <同一ID>`，查看返回的`.cad.png`。ViewCenter/DCS不能当工程WCS，文件预览不能当CAD图面。

操作范围、嵌套参数和原生回执看各自describe。状态从实际保存点接续；不因旧阶段字段、旧图名或旧截图覆盖当前稿。

## 本轮顺序与责任

整体换底是前置：保护绿化内容→删确定旧底板→PU→复制本轮园建底板并隔离冲突定义→视口/网格备注同步→自检和独立校审。局部对象复制不能核销整体换底；真实未定范围单列，其他成熟项继续。

管理负责流程优化、程序接口/宿主/队列研发修复及交付前自测；执行和校审在实际改图、核图中验证模块效果并反馈问题。执行完成修改、保存和批内自检，校审独立核图、直接返修。`模块反馈`与`程序故障`回管理，复用本批已有回执和图面证据，不为凑模板查源码或另写测试程序；工程差异仍在执行与校审间直传。管理另接整项交付及真实用户取舍，不新增逐笔放行。模板由原`任务流程.py packet`生成，原生消息工具发送。

分批换底的累计稿沿原`任务流程.py complete`提交：evidence保留原主体`receipt`，附`coverage_review`和`final_receipt`；模块核128类暂留对象等实际集合的无漏无重、原稿身份与最终原生保存重开。角色核对后发生显示补正时由`final_job`连接前后SHA并核几何/实例范围未改；发生工程几何变化则更新受影响的角色证据。旧会话证据用`proof_paths`明确映射，原回执不重写。技术证据成立后仍须执行自检、独立校审，不代替图纸验收。

`submit`包含身份、参数、保存点和未决动作校验；不用额外逐项审批。同类动作合批，未变证据复用，返修只看失败及实际影响范围；新原生方法做必要隔离验证，日常不每次关闭重开。

## 故障与扩展

按确切请求报告程序错误，管理在原组件修复并验证后交付；执行继续独立工程项。禁止同错无新条件重试。原件、现有修改、正确宿主/文档、真实几何和必要验收保持。

模块结构、移机与导出见[CAD组件接入](CAD组件接入.md)。

收口：获授权关闭时，`submit close`保护并关文档；收到对应原生回执后 `finish_close --id <原ID>`正常关专属窗口并核退出。`PROTECTED_HOST_EXITED`才是进程已退出，不把仅关图当释放宿主。

- 地被原生比例：`groundcover_update`在原item增加`scale`，`expected`可只给`up/down/scale`；程序保护原比例，保持前三个几何夹点、字高和内容。无需为单纯放大重新抄全部夹点；新比例由执行按图面比例确定。
