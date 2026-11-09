# CAD组件接入

统一入口 `cad_session_client.py`；构建/迁移入口 `cad_components.py`。当前实测后端：Windows x64、AutoCAD 2021、天正 T20 V10。工程清单、机器配置和运行会话分别保存，换模型只换调用者。

| 层 | 输入 → 输出 | 唯一实现 |

|---|---|---|

| 项目 | 最新要求、来源、实际对象 → 当前任务与参数 | 原执行清单/接续读取/任务流程 |

| 参数与会话 | 参数＋保存点 → 一次提交、明确回执 | cad_runtime，原CLI |

| 原生操作 | 确定对象 → 原生修改、保存、对象读回 | 已发布的分项C#模块 |

| 宿主与机器 | 环境配置 → 私有桌面、文档绑定、截图、关闭 | machine/lifecycle/capture |

管理负责流程、模块研发修复和交付前自测；执行和校审负责在实际改图、核图中验证模块并反馈问题，复用已有证据。执行选工程对象、修改保存，校审独立核原意见与图面、直接返修。普通模块通过结论与经验留原清单/证据，不抄送管理；接口困难、能力缺口或真实程序故障才回管理，工程差异在执行与校审间直传；管理另接整项交付和确需用户取舍。交接不增加审批、重复测试或第二套状态库。

## 坐标改点优先顺序（2026-11-08 用户纠正）

换实际测点时，优先复用天正原生坐标标注：已有动态标注可用且坐标制式正确则移动主控点，让原生数值自动更新；直接重新坐标标注更短则重标，并清除失效旧注。不要默认手算世界/纸面坐标并逐夹点搬动。只排版仍固定真实测点与数值。已有正确保存结果不为换方法重做。

历史样本的 g0 移动未更新数值，没有记录当时动态标注开关，不能据此认定天正不支持动态坐标。`coord_update` 保留为原生路径不适用时的限定备用接口；坐标系/单位/纸空间关联只核本次真实必要条件，不另加例行全图检查。动态开关的本机后台入口及本项目纸空间自动换算尚未实测，不声称已启用；入口缺口由管理解决，执行继续其它已授权项。

## 现有会话

实际文档、保存点、宿主和未决请求均动态读取，不复用旧PID。

2. 已知操作直接 `submit`；不熟悉时只看 `describe <kind>`。`prepare`仅为可选预演。

3. 读原ID回执，按本批影响范围自检和看图；稳定可审项直接交校审，未变证据复用。

```powershell

python -X utf8 cad_session_client.py --state <原技术状态.json> status

python -X utf8 cad_session_client.py describe <kind>

python -X utf8 cad_session_client.py --state <原技术状态.json> submit <kind> --id <本批ID> --params <参数.json>

python -X utf8 cad_session_client.py --state <原技术状态.json> status --id <同一ID>

```

程序填写input/hash/output/job/receipt，模型只给工程参数。同一ID返回已有结果；未决动作查原回执，不重发。写前拒绝可直接结算为失败；已改动或结果不明才进入保护恢复。`SAVED_STILL_OPEN`表示保存成功，工程完成取原清单的实际验收。

## 操作目录

| 操作 | 内容 |

|---|---|

| inspect / page_map / layers | 模型对象、纸空间、全局图层只读；inspect可附明确视图 |

| native_details / viewport_details / table_read | 天正夹点/数值/显示组件及UpText等属性；逐视口冻结/覆盖；AcDbTable原始单元格 |

| base_replace | 删除已确定旧底板→原生PU→隔离同名定义复制→保护对象验证→保存接续 |

| entity_display / layer_patch / plant_layers | 实体显示（可精确指定普通块内子件）、全局层属性、选中植物实例的独立定义及归层 |

| paper_copy / paper_note | 按图框克隆完整原生备注；可显式改备注文本 |

| text_patch | DBText/MText/TDbText及TDbDrawingName.NameText原位改字，保留原生格式与主锚点 |

| viewport_camera / viewport_layers | 已确定配对视口的相机或分层显示；保留纸窗 |

| viewport_freeze | 只改指定视口与图层的冻结状态，保留其他显示与相机 |

| groundcover_create | 当前4夹点单上行原生地被模板克隆；先设UpText再依次移折点/承托端/锚点，第4文字点原生联动，当前支持90° |

| coord_create | 克隆完整原生坐标、设置3夹点、同步实际X/Y；当前实测YX轴序 |

| erase / hatch / transfer / copy_transform / polyline_sync | 原生局部操作；适用范围看单项describe |

| polyline_edit / polyline_offset | 显式顶点与bulge原位更新／原生偏移全部结果；保留基准身份，参数及边界看describe |

| switch / close / finish_close | 保护后切稿；或先保护关文档，再正常关专属窗口并核进程退出 |

实际CAD截图：inspect带view完成后 `capture --id <同一ID>`，使用返回的`.cad.png`。无须为数值核对截图；原生预览不作为图面证据。新能力先查本目录已发布模块及专项方法，缺哪个补哪个，不让执行重写COM、宿主或队列。

`entity_display`默认仍改模型根对象。改普通块内子件时，在该entities项增加`definition`句柄，并提供`definitions:[{handle,name,instances:[全部受影响模型实例句柄]}]`；目标身份仍为子件真实局部bounds/type/layer和before_color。模块核完整引用范围并保护其他子件、实例变换、线型/线宽及几何，保存重开后由执行和校审核实际显示。外参或动态块另需对应原生适配，不能默改同名定义。

## 移机与构建

环境配置只放安装路径、后端与工具路径；项目输入仍由原项目提供隔离副本及来源。包不含DWG、凭据、实时队列、机器配置或商业软件。接收机已有合法安装后运行：

```powershell

python -X utf8 cad_components.py discover --output machine.local.json

python -X utf8 cad_components.py doctor --environment machine.local.json

python -X utf8 cad_components.py build --environment machine.local.json --module session --output Session.dll

python -X utf8 cad_components.py build --environment machine.local.json --module <分项模块> --output <独立DLL>

```

构建与导出共用`cad_components.py#MODULE_SOURCES`；构建回执列出二进制实际包含的命令名，调用前再核对，不能用后来源码的名字猜旧DLL。包不携带本机绝对路径的release登记；接收机编译、原生验证后登记自己的模块路径、SHA、入口及证据。源代码包可移植不等于目标机器已验：首次接入验证真实开图/外参、定位截图、一项小修改保存及读回。相同已验宿主不因换模型重启；不同CAD ABI需适配。

仅需要启动新专属宿主时，使用 `start_cad_module.ps1 -EnvironmentFile <机器配置> -ProjectState <原技术状态> -Job <base_job.json> -ExpectedJobSha256 <SHA> -Dll <本次DLL>`。base job区分实际garden/planting/terrain；font_map可省略。启动和截图走私有桌面，不接管前台。用户验收结束或授权恢复时，submit close完成原生保护/关文档后，运行同一CLI的 `finish_close --id <原close ID>`。返回`PROTECTED_HOST_EXITED`才代表进程已退出；等待中重复此查询不会重发关闭。

```powershell

python -X utf8 cad_components.py export --environment machine.local.json --output cad-session-components.zip

```

导出按组件清单逐文件固化SHA，排除项目和会话数据。构建/离线测试、当前机原生测试、目标机验收分别记录；证据留原技术状态和模块release，日常入口不重复历史版本。

管理的隔离测试统一用 `cad_module_diagnostic.py --state <当前隔离technical_state.json> --build <build.json> --entry <DLL实际命令> --config <本次配置> --name <稳定ID>`。隔离状态声明`session_purpose: isolated_module_test`；调用先核宿主存活和命令匹配，同ID不重放。helper退出、命令送达和原生回执分别报告，不从旧测试目录复制宿主模板。工程送审仍由执行直接交校审，不经过此测试入口。

已保存DWG的曲线、填充与DBText可直接用 `cad_geometry_read.py --environment <机器配置> --request <sources配置> --workdir <新的ASCII临时目录>` 独立只读，不占生产宿主。DBText返回原文、对齐点/方式、插入点、字高宽高比、角度与样式；右/中对齐改字后插入点可能随字宽变化，须核真实对齐锚点。

HATCH同时返回`origin`和`pattern_lines[{angle,base_point,offset,dashes}]`，线族角度是弧度，DXF组码53为度。完整原生线族已与本项目v635修前/修后DXF逐字段核对；读取不归一化基点、不重置原点，也不据定义相同推定实际草纹正常。

`hatch`沿原参数接口自动调用已验分项模块：工作平面只逆变换闭区数据，完整保留样本图案线族和原点，不再对HATCH调用Origin/TransformBy而重载本机PAT。逐项比较完整图案、局部与回位面积、孔环并保存重开；适用模板为Z0、+Z法向、Normal样式的非实心填充，其他模板明确退回，不默改定义。边界闭合点由模块内部补齐；不能仅凭面积和图案参数一致认定草纹正常，原生渲染回归用例与实际图面证据见分项 release。工程有效范围仍由执行和校审决定。

`inspect`无论是否取图均走安全只读扩展；未知/已删句柄只拒绝当前请求，不冻结整个宿主。历史旧处理器的已证只读HOLD，管理可用`recover_cad_read_hold.py`精确核失败、当前保存稿和应急副本后结算；不重放。只接受原inspect缺失句柄或page_map的LAYOUT_NOT_FOUND；后者在写事务之前失败，并复核布局确实不存在。恢复回执按原请求隔离，dispatch文件不使用request前缀，避免被请求扫描器误认；恢复后须实读READY及未决0。

`text_patch`校验纸空间总视口以Layout.GetViewports的首项身份识别，不用会随布局激活改变的Number；普通浮动视口仍核原相机/显示。真实保存已成功而仅此旧校验失败时，`recover_cad_saved_text.py`核原差异只涉及总视口、内存/文件/目标文字一致后恢复既有输出；原失败回执和应急稿保留，不重做改字。根因、隔离测试、实际消费者证据分开记录。

`groundcover_create`参数通过`describe groundcover_create`取得；期望模板包括原生UpText/DownText/Height/Scale/角度及全部4夹点，模块还核两段显示线与前三点的对应，不能仅凭夹点数套多分支模板。新文字可使用天正上标`m^U2^U`；当前只支持单上行、原模板样式和90°引出，不擅自替代工程面积/锚点判断。`table_read`返回0起始row/column和原始TextString，不写表、不推算工程量。

发布前自测必须同时验证真实CAD命令及**当前客户端到release/DLL的分流**；只编译或直接命令测试不算完整可用。Python入口先在临时文件语法检查，再原子替换，避免在线消费者读到半成品。保留实际失败反例，修失效步骤，不将额外程序调试交执行。

`table_patch`已支持逐格旧TextString保护、原生改字、缓存刷新和保存重开。参数与0起始行列见`describe table_patch`；整批前态检查后才写入。可选`delete_tail:{start,count,before:[逐行全部旧文字],block_ids:[同大小的图块句柄或null矩阵]}`只删除明确尾行，含图例格必须声明准确block；`table_read`已返回block及content_count。保留其余格、格式和图例；不插入/合并行，不写字段、公式或数据链接。可选 `legend_hatches:[{block,handle,rectangle:[xmin,ymin,xmax,ymax]}]` 在表格引用的指定块内调整原 HATCH 矩形边界（块内 XY、Z=0、非关联）；单改图例可省略 cells。图案完整定义、原点、颜色和其余块内对象内部保留，原自动适配格随新边界刷新，不要求模型重抄这些属性。若实际图例仍因原图案定义/原点异常而缺线，可显式加 `reload_pattern:true`：在块内原点重载同名原生图案，保留图案名称、比例、角度、颜色，但会替换旧图案定义；默认不重载，图面效果由执行/校审确认。工程取舍、数值和改后图面仍由执行/校审决定。

中间行删除沿原 `table_patch`，使用 `delete_rows:{rows:[{row:原0起始行号,before:[本行全部旧文字],block_ids:[本行全部原生图块句柄或null]}],renumber:true/false}`。只删第2行及以后的指定数据行，先核整批原值，再按原行号倒序调用原生 DeleteRows；`renumber:true` 仅将剩余数据行第0列从1连续编号。该批次不混用 cells/delete_tail/legend_hatches；拒绝数据区合并、字段、公式、多内容及链接。其余单元格内容/原生图例、格式、行高、列宽、表位置和表样式前后比对，非目标实体修改监测、缓存刷新、保存重开一起验证。不是清空单元格，也不借跨表搬行删除。

### 常用文字操作（沿原 Session 入口）

`text_read {"handles":["块定义句柄"]}` 可读取 BlockTableRecord 的直接子对象：返回实际 handle、type、layer 与原生几何；HATCH 含图案、边界、原点、法向和标高。不是内存炸开后的临时对象，不写图、不递归导出全库。

- 块内删字：原 `erase` 直接接受 `{"targets":[{"handle":"文字句柄","block":"所属块名","text":"原文字"}]}`；不传 bounds，也不要求先读取文字范围。程序直接核块名/对象/原文并删除，其他块成员与引用自动保护。

- 地被原位改字：`groundcover_update.items` 给 handle、layer、expected（原 up/down 两行文字即可），增加 `up_text` 和/或 `down_text`，省略 `grips` 就不移动引线、落点。仅移夹点的旧参数继续可用，原文字由程序补入。

- 图框 MText：`text_format.texts` 给当前文字、所属块和前后格式；可选 `contents` 清理内嵌格式，但原生解析的 plain_text 必须逐字相同；可选 `location` 调整锚点位置。共享引用由程序自动收集保护，不要求人工抄齐引用清单。

- 接口不会用或找不到：说明当前卡住动作即可发管理。先解释已有入口，实际故障修失效处，当前缺能力才补模块；不自动把反馈扩成研发，不重复核验未变部分。工程与图面判断仍直接交校审。

开发交付前简要自检本次变化的必要性、已有能力能否复用、实际影响范围及真实验证结果；只修必要差异，不要求执行/校审额外填表。

### 原生索引落点联动（2026-11-08 实测）

原入口 `cad_session_client.py submit index_anchor --id <本批唯一ID> --params <参数文件>`。

参数：`{"indexes":[{"handle":"当前句柄","layout":"准确布局名","layer":"准确层名","expected_grips":[七个当前原生点],"anchor":[新X,新Y,新Z]}]}`。

适用已验证的七夹点、单落点圆 `TDbSymbIndexPointer`：g2 是圆心主控制点，g3 是引线与圆的接点；模块只移动 g2 一次，g3 自动跟随，不接受手工搬随动点。其余五点、正文、详图号、图号和样式由模块保护。七点不自动等于双分支，先按真实线圆拓扑识别；别的拓扑不得仅按夹点数量套用。

当前工程指向和图面效果仍由执行/校审负责。

纸空间 `paper_entities_copy` 已支持整体 `TDbSymbMultiLeader`，参数不变，仍用准确源/目标布局、同尺寸图框和源对象 type/layer/bounds。`paper_copy` 仍只复制文字；无需炸开引线或逐点重画。

`entity_display` 可选成对字段 `before_linetype_scale` / `linetype_scale`，只设置所选实体的线型比例，均须有限正数，旧值不符在写入前拒绝；省略时维持原比例。仅改比例时保持原 target_layer/color。复用原参数与原会话，不设置全局 LTSCALE，不改变几何或线型名称。

### 纸空间原生坐标更新

原入口 `cad_session_client.py submit coord_update --id <唯一ID> --params <参数文件>`，原位修改既有 `TDbSymbCoord`，不克隆、不拆文字。

参数：`{"axis_order":"YX","items":[{"template_handle":"当前句柄","layout":"准确纸空间布局","layer":"准确层名","expected":{"x_value":原X值,"y_value":原Y值,"rotation":原旋转,"grips":[原三点]},"world_xy":[世界E,世界N],"grips":[纸面测点,纸面折点,纸面横线端]}]}`。

世界值用完整双精度传入，天正 XValue=N、YValue=E；不从纸面夹点计算世界值，也不直接改显示字符串。移动主控后重读，已随动到位的不重复移动。源点及视口投影由执行/校审确定，模块不代做工程判断。原字体、字高、旋转、十字及其它实体/视口保持。当前支持已验三夹点、十字、两行坐标样式；旧模型 `coord_create` 入口不变。

## 填充等圆曲线读取（2026-11-08）

`cad_hatch_split.py` 原调用不变。原生 `EllipticalArc2d` 仅在长短半径严格相等且为正时按真圆弧读取；不近似非圆椭圆，不把弧线加密成折线。切割范围由执行/校审核定。

## 原生标注保存后读回（2026-11-08）

`groundcover_update` 原调用不变；独立数据库读原生标注时按被读数据库设置 `WorkingDatabase`，结束恢复，避免纸空间文字位置读错。已提交后校验失败不得重发；先保护源/输出/应急稿，按现成 `recover_cad_saved_groundcover.py` 绑定原请求和独立原生期望证据，比较当前宿主与保存稿后只结算原请求，不重写DWG。失败回执保留，补 `.resolution.json`。

## 原生标高与六夹点索引更新（2026-11-08）

原入口 `cad_session_client.py submit native_annotation_update --id <唯一ID> --params <JSON>`；`describe native_annotation_update` 返回字段。annotations 每行复用当前 native_details 的实际 layout/layer、expected 属性和 expected_grips。三夹点 TDbSymbElevation 支持 text/scale，真实 g0 保持；六夹点 TDbSymbIndexPointer 支持 up_text/bearing；七夹点单落点圆索引增加 bearing（此拓扑不支持混改 up_text）。bearing 是当前空间中 g1 的目标绝对三维坐标，仅移动 g1 一次：g0/g4/g5/g6 随动，g2 真实落点保持，g3 接点由原生径向跟随；不用另算或逐点移动。七点须通过实际单落点圆拓扑检查，不通用到双分支。完整文字、索引圈/图号、字形字号和相对位置按原生显示子件保护。未改字段省略；不支持的拓扑交管理，不让执行改控制程序。独立副本保存重开和原 CLI 已验证，工程数值、指向及排布仍归执行/校审。

`cad_geometry_read.py` Core 启动改为 `/i` 一次性源副本，再只读原请求；规避无输入启动在 NETLOAD 前退出 53。

同入口补充：`target_layer` 仅把单个指定原生标注迁到已存在层，原隐藏层及其他对象不动；可作为唯一改动。五夹点 `TDbSymbArrow` 用 `text`/`text2` 一并修改主、副文，expected 采用 Text/Text2/Height/Scale/LayoutRotation；原箭头和五点保持，不炸成散件。原生实测 `Text2` 是可写 COM 属性，非临时推断。证据见 native_annotation_update_20261108.layer_arrow_extension。

## 最新园建同步种植：入口适用范围（2026-11-08只读核对）

- `base_replace` 做**模型空间**整体替换：source_targets为当前确认的最新园建底板集合，old_targets与protected_targets不重叠且完整覆盖当前目标模型对象，deferred_targets必须属于protected。工程角色由执行/校审按既有分类和变更维护；同一次必要盘点复用，不反复扫图。删除旧底→原生PU未引用定义→MangleName隔离复制→生成新entity_map→保存重开；植物、种植专用标注/填充及布局保护。范围或样式不合种植用途的园建内容不能因“整个底板”无差别复制。

- 全量替换自然覆盖所选底板内的新增/修改/删除，但旧映射目标若已删/改/改作种植用途，必须依据当前身份重分类，不能直接重放旧params。source_targets完整性由执行/校审负责，模块的classification_complete只证明目标模型分类完整。

- 原生模型对象按完整对象克隆；现有验收函数对专有标注主要比较类型/包络/通用显示，不能冒充全部天正文字/夹点语义已验。仅受影响原生标注复用native_details读回及已有图面给校审，不重复全图识别。

保留准确适配器哈希、宿主/稿件/请求绑定和完整分类门禁，运行前核保存与切稿接口签名。侧库保存前恢复宿主WorkingDatabase，避免活动编辑器视图污染侧库纸空间；未放宽纸空间保护。CLI已实际保存并激活新稿、READY且无未决请求。版本和二进制哈希只取release，不在业务参数固定；未改生产宿主/业务DWG。测试样本的缺地形及搬移后相对外参错误已仅在隔离样本修正，生产地形校验保持。

- 准备顺序：园建本轮独立校审确认源 → 沿原入口 source_register 新源（仅未登记时）→ switch 当前种植工作稿并等原切稿结算 → 从旧映射+现有变更/当前对象身份形成上述集合 → submit base_replace 一次 → status取原回执及新映射 → 按symbol_map处理新图层的相关视口显示，保护plant layers和既有种植布局 → 当前受影响纸空间标注另同步 → 执行自检与校审直交。前置未就绪只准备参数/做独立项，不在生产试错。

- `polyline_sync`仅现存对应模型LWPOLYLINE的几何更新，不覆盖增删、HATCH、块、原生标注或纸空间，不能代表整体换底。

- `base_replace`保留目标纸空间，不复制源纸空间。`paper_entities_copy`当前仅支持文字、LINE/LWPOLYLINE、TDbSymbCoord和TDbSymbMultiLeader，等尺寸图框间平移；不支持TDbSymbElevation/IndexPointer/Arrow的跨图复制，不隐式删旧，不整体复制园建布局。已有目标原生标高/索引/箭头可用native_annotation_update精确修改；新增此类纸空间对象若确为种植所需，属于管理需补的能力缺口，不能改type伪装或拆成散件。X04/X05等园建详图并非自动全部搬进种植。

- 图层同步用新symbol_map和精确视口/图层对，viewport_layers只处理指定视口冻结/覆盖、不替代全局开关；不得照搬园建隐藏策略掩盖种植标注。工程图种可见性由执行/校审决定。

## 视口冻结入口修复（2026-11-08）

`viewport_freeze` 已改为专用 `HLCADVIEWPORTFREEZEV1`，沿原 CLI 和 `PresentationPatchV1.release.json` 调用，参数不变。旧通用 `HLCADBOUNDAPPLYV7` 在多模块同宿主时实际落入不支持该操作的 BoundCadEditsV1；隔离已复现，专用入口在旧模块仍加载时完成冻结/解冻和保存重开，原 CLI 回到 READY。客户端拒绝此操作再发布到通用命令，构建/导出包含专用入口。旧业务失败是写入前拒绝，保留回执；当前状态仍匹配时，使用新批次ID调用一次，不重发旧请求。

## 纸空间显示与指定删除（2026-11-08）

原 CLI 新增 `paper_patch`，`describe paper_patch` 查看合同。统一传 `items`，每项必填 `layout/handle/type/layer/action`。不要求重复获取 bounds；用当前保存点既有句柄和布局。可同批混合显示修改与删除，多布局也可一次提交。

- `action:"display"`：按需成对提供 `before_color/color`（ACI 0～256）、`before_linetype/linetype`（图内已有线型名）、`before_linetype_scale/linetype_scale`（正数）。不改图层、坐标、文字、块定义和插入变换。支持普通线/多段线/圆弧/圆、块插入、文字及浮动视口。块内显式颜色不会因修改块插入颜色自动改变；不以根对象读回代替图面核验。

- `action:"erase"`：只删除指定纸空间根对象；块插入的所属属性文字一并删除，共享定义保留。浮动视口有非矩形裁剪边界时，两者须同批列入；程序不自动猜测重复图套或扩大删除范围。系统纸空间视口及模型对象不能作为目标。不删除整个布局。

- 按既有 `submit paper_patch --id <新批次> --params <参数文件>` 调用，同一保存点一次提交。全批前态在写前核对；未选对象原生写入事件保护，受影响布局保存重开比对。无需新宿主/临时 COM/分解图签。

示例：`{"items":[{"layout":"布局2","handle":"真实句柄","type":"AcDbBlockReference","layer":"实际层","action":"display","before_color":2,"color":7},{"layout":"布局2","handle":"另一真实句柄","type":"AcDbViewport","layer":"实际层","action":"erase"}]}`。颜色7只是接口例子；工程目标颜色线型从已确认园建样式取得。

管理只验证接口/属性/保护/保存，工程对象选择和成图由执行、校审负责。

### 共享纸空间图框子件显示

`entity_display` 原合同的 `definitions` 每项可加 `space:"paper"`，仍传定义 `handle/name/instances` 全部引用句柄；未声明维持旧模型引用限制。所有实际引用必须是静态纸空间插入，漏报引用在写前拒绝。entities 中 `definition` 指定该定义；可选精确的 LINE/LWPOLYLINE/ARC/HATCH 或嵌套 BlockReference 子件。支持已定义的 ACI/层/线型比例字段，不新加线型名称修改。只改选中子件，保护未选文字、嵌套定义、实例变换和几何；不会把所有块成员统一染色。

根插入色仍用 paper_patch；两层不要混为一次根属性读回。

### 原生苗木表扩列与排版

`table_expand` 沿原 CLI，一批 `tables` 可处理上下两张表。必填 `handle/layout/layer/row_count/column_count/column_map/column_widths/row_heights`。`column_map` 是结果列到原0起列的映射，原列必须完整按序出现，`null` 为新增空列；例如原4列扩9列 `[0,1,2,null,null,null,3,null,null]`。程序保留原文字/数量/面积与图例块引用，绝不按物种猜规格。

可选 `text_height/title_height/text_style/position:[x,y,z]` 及 `cells:[{row,column,before,after}]`；cell坐标是扩列后的0起位置，新列before必须空字符串。旧图例格不能用文字覆盖。行数不变，支持未合并表或第一行整行标题合并；不支持字段/公式/数据链接、多内容格或其他复杂合并。原文字、行数、布局及旧列顺序不变；宽高应留足文字空间，图面由执行/校审核。

已验两张原生4列表分别扩9/8列，图例保留、标题合并、指定规格文字/字号/宽高/位置、原CLI再次扩列及保存重开。无需炸表或重建图例。

普通块子件元数据读取：直接 `text_read` 的 `handles` 传实体句柄，返回 native bounds、color_index、linetype、linetype_scale、owner.instances。BlockReference直接返回定义名/句柄和矩阵，不为查属性递归拆解。读定义句柄仍是children简表。见 NativeTextFormatV1.release.json 的 entity_metadata_evidence/cli_evidence。

### 已验补充入口（2026-11-08）

- `viewport_camera` 每个 pair 可加 `world_offset:[dx,dy,0]` 和正数 `custom_scale`。偏移作用于 WCS ViewTarget，不改 DCS ViewCenter；仅平面正交视口支持偏移。目标纸空间窗口不变，按比例调整 ViewHeight，保留锁定及冻结；旧参数仍有效。

- `paper_patch` 的 `action:"move"` 配 `offset:[dx,dy]`，整张图的根对象同批同偏移；原生图名、文字、含属性图框和浮动视口均支持。裁剪视口及其边界必须一起移，未列对象不动。系统纸空间浏览相机不作为工程几何保护项，浮动视口相机仍完整保护。

- `paper_patch action:"copy"` 支持同一当前DWG的原生图块及 `TDbSymbNorthThumb` 指北针；给出 `handle/layout/type/layer/offset:[dx,dy]`，跨布局另给 `target_layout`。原生 DeepClone 保持源对象，返回新句柄；指北针夹点、完整展开图元、显示样式、平移和保存重开均核对。无需 `source`，不要为单个既有指北针复用停用的 `paper_roots_copy`。同批同一源句柄只列一次；再次复制用新批ID。V13同布局平移、跨布局原位、真实文档重开及原CLI通过；20项离线检查通过。原视口复制器的 HOLD 不解除，整布局仍用 `layout_import`；工程位置、数量、朝向由执行/校审核验。

- `table_rows_move`：`source_table/target_table` 各带 `handle/layout/layer/row_count/column_count`；`rows` 指原表0起行号，`insert_before` 指目标原表0起行，`renumber:true` 可重排序号。两表列结构须相同，前两行表头不可移动。原生复制整行及块图例、行高、文字样式，删除源行；不猜规格，不炸表。扩列另用 `table_expand`。

- 图名 `text_patch` 已修复中文/数字/标点导致相同样式片段数变化的误报。仅无内容的样式比较去除相同片段；实际结果保存重开仍完整比对。写入提交标记按实际事务提交时点记录。

- 确有失败未决的 `paper_patch/text_patch`，用 `python recover_cad_paper_checkpoint.py --state <原状态文件> --id <失败ID>`：先另存保护当前内容，再回到哈希一致的原保存点，保留失败回执及候选，不自动重放。只处理原请求，不开第二队列；恢复后由消费者按原需求决定新批次。

- 已提交的 `paper_patch` 报 `PAPER_SAVE_REOPEN_MISMATCH` 时，先沿同一恢复入口 `--diagnose-build` 绑定原请求，只读比较源稿、当前内存、实际输出和应急稿。默认回退仍保留；只有精确删除批次、源稿扣除原目标后与输出完全一致、当前内存及保存旗标证据吻合，才以 `--adopt-saved-build ... --diagnosis ...` 结算已有输出。保留原失败/应急稿，不重放、不改DWG，不把已提交失败当成未执行。
- `paper_patch` V12 修复本次视口读取上下文误报：沿内存中已识别的系统纸空间视口句柄和owner统一其浏览相机身份；浮动视口仅在其余字段全部一致且本机原生DXF90状态位逐一相同时，允许文档/独立数据库的On读数不同。真实关闭位、相机/比例/裁剪变化继续拒绝；实际差异写入snapshot-difference，不能直接删除On检查。[Autodesk视口旗标](https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-DXF/files/GUID-2602B0FB-02E4-4B9A-B03C-B1D904753D34.htm)与[GetViewports的布局激活条件](https://help.autodesk.com/cloudhelp/2024/ENU/OARX-ManagedRefGuide/files/OARX-ManagedRefGuide-Autodesk_AutoCAD_DatabaseServices_Layout_GetViewports.html)只解释API；实际判定以原生对照为准。图面与工程对象选择仍交执行/校审。

模块自测不代替执行/校审的工程验收。

### 分幅索引成组创建

本项目最新要求已明确沿用园建分幅、图框和视口，按下文原生 `layout_import` 复制完整布局；本节生成能力不构成重新分幅、重算索引或改变比例的业务授权。

`paper_index_create` 一批生成指定纸空间闭合直线多段线及完整 `TDbSymbDrawingIndex`，旧组保留。合同用 `describe paper_index_create`：`layout`、`boundary_template:{handle,layer}`、`index_template:{handle,layer}`、`expected_index_label`，以及 `items:[{key,vertices:[[x,y],...],position:[x,y],index_label,drawing_label?}]`。顶点是目标纸空间 XY，末点不要重复首点，自动闭合；`position` 是索引第一个原生夹点（圆心）。不同旋转/尺寸直接传不同顶点，不用平移代替相机投影。投影、编号和落位由执行/校审提供。

范围线继承原模板显示、统一宽度、厚度；模板本身可为开线，结果始终闭合。索引整体复制，原生 `IndexLabel` 改编号，选填 `DrawingLabel` 改图号，其余样式和两夹点相对关系保留。仅同一指定纸空间、平面模板；不移动或删旧组，不修改模型、不计算视口。新回执按 key 返回两个新句柄，执行校审通过后，用已有 `paper_patch action:erase` 精确删旧根对象。

隔离15组不同旋转/尺寸测试、原 CLI 追加2组及保存重开通过；模板编号不符在写前拒绝。旧图面证据仍由执行/校审消费，不新增管理审图。

### 园建纸空间原样复制到种植（2026-11-08）

**最新用户纠正：本批停止扩展以下自定义复制器，改用另存种植副本、清旧视口图框、PU、原位复制园建对应布局的原生流程。以下为历史接口与隔离试验记录，不是当前推荐生产入口。复制器生产显示反馈尚未闭环，release 保持 HOLD；技术通过不等于实际可见或工程通过。**

入口仍为 `cad_session_client.py submit paper_roots_copy --id <本批ID> --params <参数JSON>`。参数只需 `source`（原会话已登记来源）、`source_layout`、`target_layout`、`source_targets:[{handle,type,layer}]`，可选 `frozen_layer_pairs:[{source,target}]`。源根由执行/校审指定，目标布局须已存在。直接按原纸坐标复制，不传位移、比例或新分幅参数；不会自动清旧图、替换模型或挑选图框。

原生 `WblockCloneObjects` 保留图框块及属性、浮动视口、上下双窗及裁剪、天正图名/索引/指北针/箭头/引出、文字和HATCH。裁剪视口须把对应裁剪根一起列入；系统纸空间浏览视口不复制。同名块定义采用原生改名复制，避免复用目标旧定义；回执返回根句柄映射及符号映射。目标模型、已有纸空间实体保留。完成复制后，执行改种植专属图名与显示，校审确认后再按既有精确删除入口清旧。

**冻结图层需按真实对应。** 已替换底板可能带 `$0$`、`$1$` 等前缀，必须传已有源→目标层映射；不推断前缀。未指定时只映射准确同名，缺失同名层会原生导入。回执逐项说明采用的名称与是否显式映射，不能据此宣称种植图种的最终可见性正确；该判断仍由执行/校审逐窗处理。

已验：12个代表根含上述原生类型与裁剪双窗、同名不同定义图框及属性，显式冻结别名；连续三批（含原CLI）保存重开、保护已有实体及正常关闭退出，59项离线回归通过。

**实现反例及已采用修复：** 将当前目标另读为旁路数据库、复制保存再切稿的候选虽通过首次保存重开，重复激活时宿主退出；准确底层崩溃根因尚未证实，不发布该路线。最终直接在当前目标文档事务内复制并另存，去掉目标旁路读写及切稿；源读取/克隆与结果读回分别绑定自己的 WorkingDatabase，原生数值属性字符串按数值比较（如 `120` 与 `120.0`）。失败版本、保护稿与证据保留，不用第一次成功覆盖重复调用或关闭失败。

本轮停用反例：生产首幅纸面对象保存存在，但浮动视口 On=false；在独立副本测试激活/刷新又发生原生致命异常，具体崩溃API未证实。隔离宿主已退出，原保存稿和测试候选均保留。V9/V10不发布；用户已改用另存清旧布局、PU、园建布局原位复制的直接作业。不能把原属性/句柄比对当成实际视口显示通过。

### 原生布局导入与清理（2026-11-08，当前入口）

开发优先级（用户最新纠正）：另存过程稿保护旧数据后直接调用原生操作；本模块只需准确来源和布局名，不要求逐根比对或重新建立分幅。清旧/导入/文字整理/视口图层按实际批量处理，保存和图面核验复用本批证据；不把对接对齐本身做成新的长期任务。
直接复用 AutoCAD 整套布局导入，不逐根重建视口或自行换算新分幅。正常顺序：有效种植稿另存保护 → 既有 `paper_patch` 精确清旧图框/视口 → `purge_unused` 清未引用定义 → `layout_import` 从园建整套导入原布局 → 执行整理种植图名图号、图层和专用页 → 保存直交校审。

- `submit purge_unused --id <稳定ID> --params <空对象JSON>`：参数 `{}`。复用 BaseReplace 已验证的 `Database.Purge` 未引用符号定义清理，保留模型实物；不是无差别擦除。旧视口/图框未删时 PU 不能替代删除。
- `submit layout_import --id <稳定ID> --params <JSON>`：`{"source":"已登记园建DWG完整路径","source_layout":"布局1","target_layout":"种植_园建原布局"}`。目标必须为尚不存在的准确布局名；调用原生 `-LAYOUT Template` 整套复制纸空间/视口及页面设置并保存，不接受位移/比例/新几何参数。保留既有其他布局，不自动选择或删除工程对象。
内容和来源保存在另存保护稿，所需窗随后恢复到确定位置；不要为保留内容留下旧框与新框重叠。旧说明/索引专用文字须由执行整理，不能原位叠压新图。
首幅真实PrintWindow显示已由校审确认，工程内容/全套显示不据此核销。57项相关离线检查通过。
- 经验：先调用现成整套布局能力；只有明确缺失的步骤才补接口。自定义纸空间克隆字段一致仍可能空黑，不能把对象属性验对当实际显示通过。PU候选的命令 All 还可能清理模型零长度等对象，本入口只清未引用定义，避免扩大用户本次纸面清理范围。

TDbText 改字（2026-11-08）：沿 `text_patch` 同一 `texts` 参数，type 为 TDbText，position 用原生首夹点，before/after 为实读与目标文字；不炸开、不重造。纯 TDbText 批次只核所选文字和数据库修改事件保护项，免全套视口重扫；保存重开实测见当前 NativeTextPatchV1.release.json，不固定旧版本。普通成功及改图进度留原证据，只有未解决的接口问题交管理。

### 2026-11-09 标高整体转正

`native_annotation_update` 的三夹点 `TDbSymbElevation` 增加可选 `rotation`：目标 LayoutRotation 绝对角度（度，-360～360），不是旋转增量；`expected.LayoutRotation`仍填写最新读回的旧角度。保留原 handle/type/layout/layer、expected 四项和 expected_grips 三点，不需自行计算移动夹点。旋转不得与 text/scale 混改；保持真实 g0，核三点刚性旋转及未改文字/字高/比例/样式、非目标实体保护。仅覆盖本次验证的三夹点标高，不扩为索引/箭头旋转。原入口无需重启生产宿主。

## 2026-11-09 表格格式与视口窗口的定点补充

- `table_expand` 同一接口新增 `cell_alignment:"MiddleCenter"`，整表原生水平/垂直居中；保留原文字、数量、图例引用及首行合并。
- `legend_fits:[{row:2,column:1,block:"实际块句柄",fit_ratio:0.8}]` 以结果行列定位；先读取原生 AutoFit 比例，再关闭 AutoFit 并乘指定比例，图例完整缩入格内。比例必须大于0小于1，拒绝新空列、合并/多内容图例格、旧块ID不符；不改共享图例块定义及图案。
- `row_height_mode:"exact"` 为默认严格行高，原行为保留；`"at_least"` 明确允许 CAD 因字体/内容把行增高，回执含 requested/actual/minimum 行高，不缩字迁就。换 `_TCH_DIM` 的隔离实例请求2.6，原生最低4.2866667；原严格请求事务未提交，已核 live/emergency 等于已存稿后沿原恢复入口恢复，不靠重放失败请求。实际页高、字形及留白由执行/校审验，不以原生通过代替图面验收。
- `paper_patch action:"resize"` 仅矩形正交浮动视口，必填 `before_width/before_height/width/height`；保持纸面中心、比例、ViewTarget/ViewCenter、方向/扭转、冻结层、锁定和裁剪身份，ViewHeight按新高度/原比例更新。拒绝混加移动/显示字段、系统视口、非矩形裁剪及旧尺寸不符。只改纸窗，非重新分幅或工程世界坐标变换。
- 未激活布局的 GetViewports 可能为空；resize 在专属后台文档初始化准确布局的原生视口列表，再恢复原布局/TileMode。禁止用空列表或临时 Number=-1 推断目标是系统视口；系统对象继续以 GetViewports 首个 ObjectId 保护。
- `table_patch` 保存时匿名块名可能由 `*U75` 改为 `*U73`；仅该匿名名称不作为持久身份，仍逐一核稳定块句柄、引用、内容、图例全部原生几何和缓存。已提交的保存误报先做来源/现场/保存/应急稿诊断，禁止重放。原恢复入口 `recover_cad_paper_checkpoint.py --diagnose-build/--adopt-saved-build` 只承接已核 exact scale-only 失败；路径转绝对路径，失败回执保留，不能泛化成放行其他未核变更。

## 2026-11-09 图例边框及迁移后旧布局删除

- 三个矩形填充图例沿原 `table_patch`，准确表句柄/图层/行列数后提交 `legend_hatches:[{"block":"实际块句柄","handle":"实际填充句柄","outline":true}]`。这是独立批次；不能混改单元格、删行或填充。块必须只有所指定的一份 HATCH，已有边框会在写入前拒绝，避免重复线。
- 从原单环矩形填充实际边界生成一条闭合四点原生多段线，继承原填充的图层、颜色等显示属性；不重载 PAT、不改原点或原填充，不重算表格显式 fit_ratio。支持零凸度矩形环和四直线矩形环，后者仅允许 1e-7 内的端点浮点误差；非矩形不推断。
- 新增 `submit layout_delete --id <稳定ID> --params <JSON>`：`{"layout":"待删旧纸空间布局","replacement_layout":"已核迁移完成的新纸空间布局"}`。调用 `LayoutManager.DeleteLayout`，只删准确指定的一个非活动旧布局；名称必须存在、相异且不是 Model。若旧布局当前激活，先沿现有视图入口激活新布局后再提交，不自动猜测替代布局。
- 迁移完整性由执行/校审先核。模块只核保留布局相对顺序、模型/纸空间根句柄、页面设置、非系统视口字段及非目标实体修改事件，保存读回再次比较；不同时 PU、不删除共享块定义、不代替整套图面验收。
- 已通过隔离原生保存、实际重开及原 CLI 连续调用；重复加边框、Model 布局删除均在写入前拒绝。
- 本次测试准备反例：复制地形依赖时改了文件名，原相对外参找不到导致启动未就绪。应保留来源依赖的原文件名，不仅核文件内容；失败宿主已保护副本后正常退出。布局字典用原生 `foreach(DBDictionaryEntry ...)`，不可假定 LINQ `Cast<DBDictionaryEntry>` 的非泛型枚举接口相同。两项修复仅适用实际失败处，不扩展生产流程。

## 2026-11-09 纸空间天正整体说明恢复

- `paper_roots_copy` 的视口显示 HOLD 保持；不能直接解锁宽入口恢复说明。已有同库 `paper_transform` 可迁移尚存在的整体说明；原布局已删除且回旧稿会丢后续改动时，可用下面已验窄入口从准确保护稿恢复。
- `submit paper_leaders_copy --id <稳定ID> --params <JSON>`：必填 `source`（同会话已登记保护DWG）、`source_layout`、`target_layout`、`source_targets:[{handle,type:"TDbSymbMultiLeader",layer}]`、`offset:[dx,dy]`。偏移为纸空间整体XY位移；不能混入视口/图框、缩放/旋转、删除或冻结层映射。
- 复用原生 `WblockCloneObjects`，只克隆明确指定的整体说明及其必要依赖，再用原生 `TransformBy` 整体平移。源文字、全部夹点、上下两行、字高/比例/角度及显示属性逐一对照；目标仍是可整体编辑的原天正类型，不炸开、不逐点重建。不覆盖同名依赖；沿原克隆方式保留映射及必要别名。
- 跨图来源必须经过原 `planning.build_job` 的 allowlist 与 source_sha256 绑定，原生再次核源文件。新增来源型操作不能只登记协议/路由而漏接该绑定。首个 CLI 验证请求因此在写入前拒绝，修正后新验证请求成功；失败回执保留，未重放写入。
- 当前五项代表对象的隔离原生复制、保存、实际重开、原 CLI 调用均通过，视口混入写前拒绝；39项相关离线测试通过。执行核实际位置和布局可读性、校审核工程语义，不把接口验证当作本轮工程验收。

### 2026-11-09 表格原生图例限定改色

表格单元格图例引用会包含表缓存 `*T` 下的块参照，不能据此放宽通用 `entity_display` 的共享块保护。沿 `table_patch` 使用 `legend_hatches:[{block,handle,before_color:原ACI,color:目标ACI}]`，例如原 ByLayer 为 256、目标灰色为 8。原颜色限 ACI/ByLayer/ByBlock；目标限 1—255。整批只改颜色，不混入文字、删行、图案、尺度、矩形或边框调整。

写前核表格身份、原颜色、原HATCH所在块及该块仅引用于本表/本表缓存；RGB原色或其他共享引用拒绝。只写原HATCH的ColorIndex，保留图案完整定义、尺度、角度、闭区、同块其他对象，以及表格内容、位置、格式和图例比例；不调用图案重载或几何重算。原生表缓存刷新、保存重开和非目标实体监测共同验证。

V15证据见 `NativeTablePatchV1.release.json` 的 color_evidence、color_negative_evidence、color_cli_evidence；5个代表HATCH原生保存重开及正式CLI调用通过，旧颜色不符/块归属错误均写前拒绝，52项相关测试通过。这里只证明接口效果，正式图面与工程验收仍由执行和校审负责。测试副本必须保留地形依赖原文件名，不能只保留文件哈希。

### 2026-11-09 保存稿显示属性只读诊断

`cad_geometry_read.py --operation display_state` 复用既有独立 Core 入口；配置 `sources:[{path,sha256,handles,layers,layouts}]` 和唯一 `receipt`，读对象/图层颜色、透明度、锁定状态、布局 ShowPlotStyles 及指定层逐视口覆盖。只读侧数据库、核源文件未变，无保存、不改系统变量。默认 operation 仍为 geometry，组件导出包含相同源。

Core 中天正对象可能是代理，空 children 不证明没有图形或显示正常。实际截图仍灰，根因尚未证实；此证据仅排除已读属性差异，不能作为保色验收。当前不改变五条原生复制的技术成功记录，另保留实际显示未通过。未知根因不晋升为经验结论。
