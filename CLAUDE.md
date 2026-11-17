# CLAUDE.md — Terminal Agent Companion

Project instructions for Claude Code working in `C:\Users\alins\terminal-agent-companion`.
For current progress, completed milestones, and pending tasks, read [HANDOFF_NEXT_AGENT.md](HANDOFF_NEXT_AGENT.md).

## Environment & Build Rules

- **OS / Runtime:** Native Windows 11 x64 (no WSL).
- **Compiler:** .NET Framework 4.8 C# compiler (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, `/platform:x64`).
- **STRICT C# 5 ONLY:** Do **NOT** use C# 6+ syntax (`$"..."` string interpolation, `?.`, `=>` expression-bodied members, `nameof(...)`, `is Type x` pattern matching, `using static`, target-typed `new()`). Use `string.Format(...)`, explicit null checks, and `delegate { ... }`.
- **Python:** Python 3.11+ (stdlib only — no third-party packages like Pillow).
- **Build command:**
  ```powershell
  powershell -ExecutionPolicy Bypass -File C:\Users\alins\terminal-agent-companion\build.ps1
  ```
  - Always add any new `.cs` file under `src\` to `$CoreFiles` in `build.ps1`.
  - Stop any running `AgentCompanion.exe` before building so the binary is not file-locked.

## Verification Commands

- **Run automated test suite:**
  ```powershell
  C:\Users\alins\terminal-agent-companion\AgentCompanionTests.exe
  ```
- **Render offline UI preview screenshots (WPF offscreen render):**
  ```powershell
  C:\Users\alins\terminal-agent-companion\AgentCompanion.exe --render-preview C:\Users\alins\terminal-agent-companion\previews
  ```
- **Inspect live detected terminal agents:**
  ```powershell
  C:\Users\alins\terminal-agent-companion\AgentCompanion.exe --dump-detected | Out-String
  ```

## Architecture & Key Conventions

- **No Admin Rights Required:** Process & environment inspection uses Win32 `CreateToolhelp32Snapshot` + x64 PEB `ReadProcessMemory` (`src\ProcessScanner.cs`, `src\Win32Native.cs`) for same-user processes.
- **Secret Redaction:** Always pass command lines / summaries through `SecretRedactor.Redact(...)` (`src\SecretRedactor.cs`) before displaying or logging.
- **Single Canonical Agent Per Family:** `CompanionEngine.FilterSubAgentsAndDeduplicate` (`src\CompanionEngine.cs`) filters out sub-agents (`--subagent`, `--worker`, `--parent-pid`, `--internal-worker`, `agentapi`, and ancestor-PID descendants) and enforces at most 1 instance per `AgentFamily`.
- **WPF / WinForms / System.Drawing Aliases:** `src\CompanionWindow.cs` mixes WPF and WinForms. Keep existing namespace aliases (`WinForms`, `WpfBrush`, `WpfBrushes`, `WpfColor`, `WpfImage`, `WpfRectangle`, `System.Drawing.Icon`, `System.Windows.Documents.TextElement`).

## UI Design Rules (`src\Theme.cs`)

- **Brutalist Aesthetic:** Pure black/panel surfaces (`#0A0A0A`, `#141414`), off-white paper borders/text (`#F5F5EE`), muted gray (`#AAAAA2`), and yellow accent (`#FFE600`).
- **No AI Slop:** No gradients, no blur (`BlurRadius = 0` hard offset shadows via `Theme.HardShadow`), no rounded corners (`CornerRadius(0)`), no circular/pill badges, no bouncing/glowing overlays.
- **Extra-Visible Avatars:** Keep custom sprites large (`1.3x` in dock tiles, `56px` in drawer rows) inside high-contrast `#F5F5EE` square frames with crisp black borders.
- **Custom User Assets:** Do not overwrite user-slotted sprites in `data\custom_pngs\` or their paths in `data\settings.json`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. When the answer is under a Markdown heading, `graphify section "<heading>"` prints that section's text, so the .md need not be opened. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
