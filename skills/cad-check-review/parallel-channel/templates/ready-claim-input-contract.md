# 接收方发布/唯一 claim 外部接口

这里只描述现成 V11 消费字段，不生成、授权或签发以下文件。接收方必须复用自己的可信发布/执行入口；不存在该入口即停止接入，不能让 AI 手写以下状态冒充已准入。

发布前必须核：真实用户授权、本方真实来源、被选 V3 profile 和 capability bounds、精确 source hash、全依赖源码/本机构建产物/输入 manifest、独立隔离副本、新 run 未终结、canonical 与 route gate。模板中的 `RECEIVER_REVIEW_REQUIRED` 或 `may_publish_ready=false` 不能通过发布前准入。DRAFT 本身不是 READY。

现成代码在运行时只接受下列同 run 关联：

| 运行时文件 | 必须由可信入口提供的消费字段与约束 |
| --- | --- |
| `runs/<run>/execution_handoff.json` | 完整准入后不可变 handoff；`status` 必须精确 `READY`，`run_id` 为本新 run，`handoff_id` 唯一；包含生成器绑定的 `program.scope`/`scope_sha256`、`program.manifest`/`manifest_sha256`、issuer/target/governance/action/canonical/launch 等完整字段。实际字节 SHA256 必须由 current 指针绑定。 |
| `config/current_execution_handoff.json` | 当前唯一活动的**完整 READY handoff 文档**，不是只含三字段的轻指针：必须保留 `program.scope/scope_sha256/manifest/manifest_sha256`、`issuer`、`target`、`governance`、`action` 和其他完整准入字段，controller 会直接消费它们。另有 `status=READY`、与 immutable handoff 相同的 `run_id`、绑定该 immutable 文件实际大写 SHA256 的 `immutable_handoff_sha256`。不得覆盖别的活动 run。 |
| `runs/<run>/execution_controller_claim.json` | 执行信封在 controller 前唯一预留；`run_id`、`handoff_id` 均与 immutable handoff 相同，`controller_attempt_reserved` 是布尔 `true`；竞争者不得同时预留，不能重放既有 claim。 |
| `runs/<run>/execution_return.json` | 一旦存在即是终态屏障；V11 拒绝再启动/提交。文件不存在不能被解释为可重发未知任务。 |

接收方发布/执行信封还应保留其原本更严格的权威、原子创建、指纹与回执要求。此接口列的是 V11 实际最低消费，不允许降低接收方原有约束。本包不提供可以伪签这三个文件的脚本。

运行后 `channel_ready.json`、`first_release.json`、每owner task/claim/accepted/result/origin_received 是原控制链生成并逐项验证的事实，不是接收方预置模板，也不能由 AI 直接填写成功状态。
