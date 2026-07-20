# Claude Code 設定

讓新機器能重建一致的 Claude Code 環境。`install.sh` 會處理這個目錄下的內容。

## 納入版控的東西

| 檔案 | 內容 | 還原方式 |
|---|---|---|
| `settings.json` | Claude Code 的偏好設定（主題、通知等） | symlink 到 `~/.claude/settings.json` |
| `mcp-servers.json` | MCP 伺服器清單 | `install.sh` 依此執行 `claude mcp add-json`（user scope） |

## 刻意**不**納入版控的東西

這些要嘛含機密、要嘛是機器/工作階段的狀態，放進 repo 只會外洩或製造衝突：

| 路徑 | 為什麼不放 |
|---|---|
| `~/.claude/.credentials.json` | **OAuth token**，等同帳號密碼 |
| `~/.claude.json` | 混合檔：含 `oauthAccount`、`userID`、`machineID` 等身分資訊，其餘是各專案的用量統計與快取，沒有版控價值 |
| `~/.claude/history.jsonl`、`projects/`、`sessions/`、`file-history/` | 對話與檔案編輯歷史，含專案內容 |
| `~/.claude/telemetry/`、`cache/`、`shell-snapshots/` | 純本機執行期狀態 |

## MCP 的密鑰怎麼處理

`mcp-servers.json` 裡**只寫變數名稱的參照**，不寫值：

```json
"env": { "SOME_API_KEY": "${SOME_API_KEY}" }
```

實際的值放在不納入版控的 `~/.config/claude-secrets.env`：

```bash
# ~/.config/claude-secrets.env（自己建立，chmod 600，不要進 repo）
export SOME_API_KEY=實際的值
```

再由 `~/.bashrc` 載入（`install.sh` 不會自動建立這個檔案，因為內容因人而異）。

## 已知注意事項

- **`settings.json` 用 symlink 管理**：在 Claude Code 裡用 `/config` 改設定會直接寫進 repo 的檔案，`git status` 就看得到異動，這是刻意的。但若哪天發現 `~/.claude/settings.json` 變回一般檔案（某些程式會用「寫暫存檔再 rename」的方式存檔，那會取代掉 symlink），重跑 `install.sh` 就會重新連回來——記得先確認那個檔案裡有沒有你要保留的新設定。
- **MCP 會增加每次對話的 context 開銷**：每台伺服器的工具定義都會載入 context。加新的 MCP 前先確認它帶來的價值大於這個固定成本。
