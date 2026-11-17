# Terminal Agent Companion (Windows 11)

A lightweight, native Windows 11 desktop companion that auto-detects AI coding agents running inside Windows Terminal (`pwsh` / `powershell` / `cmd`), normalizes their live progress, notifies you only when approval/completion/failure matters, lets you click an agent to focus its Windows Terminal window, and includes a **Custom PNG Studio UI** for assigning custom `.png` sprites to both companion states and agent families.

---

## 1. Architecture Proposal

### Stack Justification
- **Chosen Stack:** **C# / .NET Framework 4.8 WPF + WinForms (`NotifyIcon`) + Win32 P/Invoke**, compiled with the built-in Windows 11 compiler (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` `/platform:x64`).
- **Why (over Tauri):** Rust/Cargo and Node.js are not installed on this machine, whereas .NET Framework 4.8 `csc.exe` and WPF assemblies are built into Windows 11 23H2. Compiling directly produces a zero-install native `.exe` (`AgentCompanion.exe`) with direct access to Win32 ToolHelp32, x64 PEB memory reading, `ReadDirectoryChangesW` (`FileSystemWatcher`), `RegisterWaitForSingleObject`, `WS_EX_TRANSPARENT` click-through, and Windows system tray notifications with no admin rights required.

### Components & Data Flow
1. **`Win32Native` & `ProcessScanner`**:
   - Calls `CreateToolhelp32Snapshot` (`ToolHelp32`) to enumerate processes without needing WMI/CIM privileges.
   - Reads each relevant process's x64 PEB (`NtQueryInformationProcess` + `ReadProcessMemory`) to extract `ExecutablePath`, `CommandLine`, `CurrentDirectory`, and `WT_SESSION` from its environment block.
   - Walks `ParentProcessId` (`agent -> shell -> OpenConsole/conhost -> WindowsTerminal.exe`) to bind every detected agent to its shell working directory (`ProjectName`) and owning terminal window.
2. **`IAgentAdapter` Plugin Contract** (`src/adapters/IAgentAdapter.cs`):
   - `Detect(processSnapshot)` — identifies running instances of that agent family from full executable path and command line.
   - `GetState(instance, processSnapshot)` — enriches terminal context and infers command execution from descendant processes when no fresh transcript event exists.
   - `Subscribe(onEvent)` — sets up `FileSystemWatcher` (`ReadDirectoryChangesW`) on agent session directories and `data/hooks/<family>*.jsonl`.
   - `FocusWindow(instance)` — raises the owning `WindowsTerminal.exe` window.
   - Adding a new agent requires adding one adapter implementing `IAgentAdapter` and registering it in `CompanionEngine`.
3. **`CompanionEngine` + `SecretRedactor`**:
   - Combines `IAgentAdapter` subscriptions, lightweight reconciliation (2.5s), and zero-polling Win32 `RegisterWaitForSingleObject` exit handles (`exitCode == 0` -> `Finished`, `exitCode != 0` -> `Errored`).
   - Scrubs API keys (`sk-ant-...`, `sk-...`, `AIza...`, `ghp_...`, `Bearer ...`, `API_KEY=...`, `--token ...`) via `SecretRedactor` before storing or rendering.
4. **UI & Notifications (`CompanionWindow`, `CustomPngStudioWindow`, `NotificationService`)**:
   - Borderless, transparent, always-on-top floating sprite with edge snapping, tray-only hide/restore, and `WS_EX_TRANSPARENT` click-through when idle.
   - Expandable compact panel showing the single canonical agent per family, state, `[confirmed]` / `[inferred]` badge, summary, files touched, and elapsed time.
   - **Custom PNG Studio** (`Model > Icon` or the tray menu): browse or drag-and-drop validated custom `.png` files for all 7 companion states and all 4 agent families.
   - `NotificationService` respects Windows Focus Assist (`SHQueryUserNotificationState`) and in-app Mute, firing notifications only on transitions to `WaitingApproval`, `Finished`, or `Errored`.

### Windows Terminal Tab & Pane Investigation
- `WindowsTerminal.exe` hosts multiple top-level `CASCADIA_HOSTING_WINDOW_CLASS` windows inside one process and injects a `WT_SESSION` UUID into every shell/agent environment block (verified readable from x64 PEB memory).
- Windows Terminal exposes **no public Win32 HWND or COM API** to select an individual tab or split pane by `WT_SESSION` from outside the terminal without elevated UI Automation or synthetic keystrokes.
- **What works reliably (no admin rights):** `WindowFocuser` matches the owning `WindowsTerminal.exe` PID, scores all visible `CASCADIA_HOSTING_WINDOW_CLASS` windows against the project folder and agent name in window titles, un-minimizes if needed, and focuses the matching terminal window (`SetForegroundWindow`).

### Permissions / Elevation Note
- **No administrator rights required.** All features — `ToolHelp32`, PEB `ReadProcessMemory` for same-user processes, `ReadDirectoryChangesW`, tray balloon notifications, and `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` startup registration — run strictly under standard user permissions. Only processes running elevated (Administrator) cannot be opened for PEB inspection from a non-elevated companion.

---


### Using Custom PNGs
1. Click the floating orb (or right-click it, or use the tray icon -> **Custom PNG Studio...**) and click **PNGs**.
2. Drag and drop any `.png` file onto any state slot (`Idle`, `Thinking`, `Running Command`, `Editing Files`, `Waiting for Input`, `Finished`, `Errored`) or any agent family card (`Claude Code`, `Codex`, `Cursor`, `Antigravity`).
3. Custom PNGs are copied into `data\custom_pngs\` and saved in `data\settings.json`.

### Configuration compatibility
`data\settings.json` carries a schema version. Older settings without a version are upgraded in memory. Settings from a newer unsupported version are treated as read-only by this build so unknown fields and custom asset paths cannot be discarded.

---

## 4. Test Plan

### Automated Verification (`AgentCompanionTests.exe`)
Covers:
1. **Secret redaction** (`sk-ant-...`, `sk-...`, `AIza...`, `ghp_...`, `Bearer ...`, `API_KEY=...`, `--token ...`).
2. **Live Win32 PEB inspection** (executable path, command line, current directory on x64).
3. **Canonical agent detection:** The engine filters sub-agent command flags, rejects descendant duplicates, and keeps at most one canonical agent per family. Raw adapter detection may observe multiple processes before this filtering step.
4. **Artifact & transcript parsing** across Claude JSONL, Codex JSONL, Cursor logs, and real Antigravity `transcript.jsonl` format.
5. **Event-driven `FileSystemWatcher` + Crash vs Clean Exit** (`HandleProcessExit(pid, 137)` -> `Errored`, `HandleProcessExit(pid, 0)` -> `Finished`).
6. **Custom PNG persistence** across `CompanionSettings.Save` / `Load`.

### Manual Interactive Test Plan (Windows Terminal)
1. **Multiple Agent Families:** Open Windows Terminal tabs with different agent families in separate projects and verify one canonical tile per family appears.
2. **Tray-only hide/restore:** Click **HIDE** and verify the companion window disappears completely; use the tray menu **Show / Hide Companion Bar**, tray left-click, or tray double-click to restore it.
3. **Multiple Windows Terminal Windows & Focus:** Open two separate Windows Terminal windows (`project-alpha` and `project-beta`), click each row in the companion panel -> verify the corresponding Windows Terminal window comes to the foreground.
4. **Agent Exit vs. Crash:** Exit one agent normally (`exit 0` -> `finished` `[confirmed]`, toast emitted), and kill/crash another (`Stop-Process` or non-zero exit -> `errored` `[confirmed]`, error toast emitted).
5. **Simulated Hook Events:** While `AgentCompanion.exe --demo` or normal mode is running, run `python scripts\simulate_agents.py` to emit hook JSONL events into `data\hooks\`.
