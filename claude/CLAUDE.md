# 全域工作慣例

## 溝通
- 一律用**繁體中文**回覆。

## Git
- **Commit 前先草擬訊息，等我明確同意才執行。** 每次都要當下的同意，上一次同意不算。
- **絕不主動 `git push`**，除非我在那個當下說了「push」。commit 完成不等於可以推送。
- Commit 訊息用 gitmoji 風格，標題用繁體中文。

## 驗證
- 動到 git 底層（stash、commit-tree、ref）或其他破壞性操作前，先在隔離環境驗證機制（`/tmp` 的臨時 repo 或 Docker），不要拿正在工作的 repo 試。
  - 特別注意：`git stash push` 沒加 `-- <path>` 會捲走所有已追蹤變更。
- 視覺／互動相關的改動，commit 前要先同步到我的即時環境讓我實際測過，不是只給文字 diff。純文件／後端邏輯不受此限。

## MCP
- 新增 MCP 一律預設 **`--scope project`**（寫進該 repo 的 `.mcp.json`，跟著版控走、換機器不會消失）。
  要用 `user` scope（全域載入、每個專案都揹成本）必須先問過我。
- 密鑰用 `${VAR}` 展開，值放 `~/.config/claude-secrets.env`，不要寫進 `.mcp.json`。

## 建立專案 CLAUDE.md
執行 `/init` 或要寫任何專案的 CLAUDE.md 時，先讀 `~/.claude/templates/project-CLAUDE.md`，依它的結構與取捨原則撰寫。
