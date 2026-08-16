# Rime 配置修改规则

- 所有个性化配置修改只能写入根目录下的 custom 配置文件（`*.custom.yaml`），例如 `wanxiang.custom.yaml`、`default.custom.yaml` 或 `squirrel.custom.yaml`；需要自定义 Lua 逻辑时，可修改 `lua/` 根目录直接包含的脚本。
- 禁止直接修改上游维护的方案文件及实现文件，包括 `*.schema.yaml`、`default.yaml`、`wanxiang_algebra.yaml`、词典文件和 `lua/` 任何子目录中的文件；这些文件可能在更新时被覆盖。`lua/` 根目录下的直接子文件不在此禁止范围内。
- 需要改变上游配置时，必须优先使用 Rime 的 `patch`、配置路径覆盖、列表追加或列表元素覆盖语法，在对应的 `*.custom.yaml` 中实现。
- 如果某项需求无法仅通过 custom 配置或 `lua/` 根目录直接包含的脚本实现，应停止修改并向用户说明限制、影响及可选方案；未经用户明确授权，不得改动其他文件。
- `build/` 是 Rime 的部署产物目录。可以通过正确的部署命令重新生成其中内容，但不得手工编辑，也不得把 `.bin` 等部署产物写入 Rime 根目录。
- 完成修改后必须检查 Git 状态，确保预期的持久化修改只涉及 `AGENTS.md`、相应的 `*.custom.yaml` 和 `lua/` 根目录直接包含的脚本；如发现其他文件发生变化，应先恢复或向用户报告，不得直接交付。
