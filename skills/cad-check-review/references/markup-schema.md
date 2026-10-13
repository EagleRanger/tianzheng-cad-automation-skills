# 红框标注配置

在生成标注脚本前，创建 UTF-8 JSON。示例：

```json
{
  "expected_dwg_name": "review.dwg",
  "runtime_dir": "C:/tmp/cad-review-20260804",
  "layer": "00-自动检查",
  "layer_color_aci": 1,
  "layer_lineweight": 70,
  "text_lineweight": 18,
  "polyline_width": 0.3,
  "issues": [
    {
      "id": "01",
      "status": "错误",
      "bbox": [40431210.0, 2875548.0, 40431258.0, 2875569.0],
      "note": [40431260.0, 2875614.0],
      "note_width": 94.0,
      "text_height": 3.0,
      "text": "黄花美人蕉475㎡使用错误图例；应统一为专用图例。"
    }
  ]
}
```

## 字段

- `expected_dwg_name`：运行时隔离副本的文件名。应用脚本会拒绝其他图名。
- `runtime_dir`：只使用正斜杠的绝对路径，优先选择纯 ASCII 临时路径。
- `layer`：默认 `00-自动检查`。
- `layer_color_aci`：默认1，即红色。
- `layer_lineweight`：AutoCAD线宽枚举值，70代表0.70 mm。
- `text_lineweight`：文字线宽枚举值，18代表0.18 mm。
- `polyline_width`：模型单位中的多段线固定宽度，按图纸尺度调整。
- `issues`：至少一项；ID必须唯一。
- `bbox`：`[xmin, ymin, xmax, ymax]`，必须满足最小值小于最大值。
- `note`：MText左上插入点 `[x, y]`。
- `note_width`、`text_height`：必须为正数。
- `status`：建议使用 `错误`、`待核问题` 或 `检查提示`。
- `text`：只写事实、差异和明确建议；生成器会自动添加 `[ID] status：` 前缀。

## 生成与执行

```powershell
python scripts/generate_markup_bundle.py issues.json --output-dir C:\tmp\cad-review-20260804
```

生成：

- `apply_markup.lsp`
- `audit_markup.lsp`
- `run_apply.scr`
- `run_audit.scr`
- `normalized_config.json`

先把隔离副本复制为 `expected_dwg_name`，再用完整天正/AutoCAD启动批处理。应用脚本只有在全部问题成功生成后才保存；中途出错会退出且不保存部分成果。

保存后重开并执行 `run_audit.scr`。只有 `audit_summary.txt` 中 `PASS=YES` 才能进入图面验收。
