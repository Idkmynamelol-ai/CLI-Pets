# Red Team & Security Audit Remediation Guide (`REDTEAM_FIXES.md`)

This document specifies all **9 verified security, logic, reliability, and spec-compliance findings** (`RT-01` through `RT-09`) identified during the audit of `C:\Users\alins\terminal-agent-companion`, along with exact remediation steps, regression tests, and verification commands.

---

## 0. Mandatory Environment & Compiler Constraints

- **OS / Runtime:** Native Windows 11 x64 (no WSL).
- **Compiler:** .NET Framework 4.8 C# compiler (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, `/platform:x64`).
- **STRICT C# 5 ONLY:** Do **NOT** use C# 6+ syntax (`$"..."` string interpolation, `?.`, `=>` expression-bodied members, `nameof(...)`, `is Type x` pattern matching, `using static`, target-typed `new()`). Use `string.Format(...)`, explicit null checks, and `delegate { ... }`.
- **UI & Asset Preservation:** Preserve the flat brutalist aesthetic in `src\Theme.cs` (`#0A0A0A`, `#141414`, `#F5F5EE`, `#AAAAA2`, `#FFE600`, `CornerRadius(0)`, zero gradients, zero blur). Do **NOT** overwrite custom sprites in `data\custom_pngs\` or their paths in `data\settings.json`.
- **Build Command:** Stop any running `AgentCompanion` process, then run:
  ```powershell
  powershell -ExecutionPolicy Bypass -File C:\Users\alins\terminal-agent-companion\build.ps1
  ```

---

## 1. High-Severity Fixes

### RT-01 — Fix `AntigravityAdapter` `USER_INPUT` Misclassification into `WaitingApproval` & Unredacted File Summary
- **Files:** `src\adapters\IAgentAdapter.cs`, `src\adapters\AntigravityAdapter.cs`
- **Problem:**
  1. `AntigravityAdapter.ParseLine` (`src\adapters\AntigravityAdapter.cs:144`) calls `TryParseStandardHookLine(line, filePath)` before its own `USER_INPUT` / `PLANNER_RESPONSE` logic, even on `transcript.jsonl`.
  2. `TryParseStandardHookLine` (`src\adapters\IAgentAdapter.cs:168`) reads `GetStr(obj, "type")` (`"USER_INPUT"`) as `evName`, and `MapHookOrToolToState` (`src\adapters\IAgentAdapter.cs:210`) checks `e.Contains("input")` **before** `e == "user_input"` (line 230). Because `"user_input".Contains("input")` is always `true`, every user prompt is falsely classified as `WaitingApproval` (`Confirmed`) and triggers false-positive approval balloon notifications, making line 230 (`IAgentAdapter.cs`) and lines 168–178 (`AntigravityAdapter.cs`) unreachable dead code.
  3. `AntigravityAdapter.cs:207-209` builds `ev.Summary = toolName + ": " + Path.GetFileName(path)` without `SecretRedactor.Redact(...)`.
- **Fix:**
  1. In `AdapterBase.TryParseStandardHookLine(string line, string filePath)` (`src\adapters\IAgentAdapter.cs:160-198`):
     - Restrict hook parsing so generic `"type"` fields in agent transcripts (outside `HooksDir`) are not treated as standard hook events — either return `null` when `!IsHookFilePath(filePath)` unless `"event"` or `"hook_event_name"` is explicitly present, or only check `GetStr(obj, "event") ?? GetStr(obj, "hook_event_name")` (and only fall back to `"type"` when `filePath` is inside `HooksDir`).
  2. In `AdapterBase.MapHookOrToolToState(string evName, string tool, out AgentState state)` (`src\adapters\IAgentAdapter.cs:200-243`):
     - Move the `Thinking` check (`if (e == "userpromptsubmit" || e == "thinking" || e == "user_input")`) **above** the `WaitingApproval` check.
     - Replace broad `e.Contains("input")` with explicit hook/state names (`e == "permissionrequest" || e == "waiting_input" || e == "input_required" || e.Contains("permission") || e.Contains("approval") || e.Contains("question")`).
  3. In `AntigravityAdapter.ParseLine` (`src\adapters\AntigravityAdapter.cs:144`):
     - Only call `TryParseStandardHookLine` when `filePath` is not a `transcript.jsonl` (or invoke `TryParseStandardHookLine` only after checking `USER_INPUT` / `PLANNER_RESPONSE` / `status == "ERROR"`).
  4. In `AntigravityAdapter.ParseLine` (`src\adapters\AntigravityAdapter.cs:207-209`):
     - Wrap `ev.Summary` in `SecretRedactor.Redact(...)`.

---

### RT-02 — Fix Self-Sabotaging `SubAgentCmdMarkers` Dropping `agentapi.bat` & Legitimate Prompts/Paths
- **Files:** `src\CompanionEngine.cs`
- **Problem:**
  - `AntigravityAdapter.IsAntigravityProcess` (`src\adapters\AntigravityAdapter.cs:79`) explicitly detects Antigravity sessions started via `agentapi.bat`.
  - `CompanionEngine.SubAgentCmdMarkers` (`src\CompanionEngine.cs:88-96`) contains bare `"subagent"` and bare `"agentapi"`, checked via case-insensitive `IndexOf` in `IsSubAgentCommandLine` (`src\CompanionEngine.cs:98-109`). This unconditionally drops every `agentapi.bat` Antigravity process and any primary agent whose working path or prompt happens to contain the word `"subagent"`.
- **Fix:**
  - In `CompanionEngine.SubAgentCmdMarkers` (`src\CompanionEngine.cs:88-96`) and `IsSubAgentCommandLine`:
    - Remove bare `"subagent"` and bare `"agentapi"`.
    - Match explicit sub-agent CLI flags/tokens only (e.g., `"--subagent"`, `"--worker"`, `"--parent-pid"`, `"--internal-worker"`, `"--agentapi-subagent"`, and token-delimited `" subagent "` if needed, while never matching `agentapi.bat` or folder/prompt substrings like `C:\src\subagent-refactor`).

---

### RT-03 — Fix `SecretRedactor` `--flag=value` Bypass & Missing Secret Patterns
- **Files:** `src\SecretRedactor.cs`
- **Problem:**
  1. `CliFlagPattern` (`src\SecretRedactor.cs:23-25`) requires whitespace `\s+` after the flag, so `--token=secret`, `--api-key=secret`, and `--auth-token=secret` completely bypass redaction.
  2. `KeyValuePattern` (`src\SecretRedactor.cs:19-21`) omits bare `TOKEN` and hyphenated flag names.
  3. URL userinfo credentials (`https://user:pass@host`), AWS keys (`AKIA...`/`ASIA...`), GitLab PATs (`glpat-...`), HuggingFace tokens (`hf_...`), and npm tokens (`npm_...`) are not redacted.
- **Fix:**
  1. Update `CliFlagPattern` to match both `=` and whitespace separators:
     ```csharp
     private static readonly Regex CliFlagPattern = new Regex(
         @"(?i)(--?(?:api[-_]?key|token|secret|password|passwd|auth[-_]?token|access[-_]?token|client[-_]?secret))(\s*=\s*|\s+)(""[^""]*""|'[^']*'|\S+)",
         RegexOptions.Compiled);
     ```
     with replacement `"$1$2[REDACTED]"`.
  2. Update `KeyValuePattern` to include `TOKEN` (`(?:API_KEY|ACCESS_TOKEN|AUTH_TOKEN|REFRESH_TOKEN|TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE_KEY|COOKIE)`).
  3. Add patterns to `DirectTokenPatterns` (or dedicated URL regex) for:
     - URL credentials: `(?i)((?:https?|postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp)://)[^/\s:@]+:[^/\s@]+@` replaced with `"$1[REDACTED]@"`.
     - AWS access keys: `\b(?:AKIA|ASIA)[0-9A-Z]{16}\b`.
     - GitLab PATs: `\bglpat-[A-Za-z0-9_-]{20,}\b`.
     - HuggingFace tokens: `\bhf_[A-Za-z0-9]{20,}\b`.
     - npm tokens: `\bnpm_[A-Za-z0-9]{20,}\b`.

---

### RT-04 — Harden Image Loading (`LoadBitmapNoLock`), Validate PNG Magic Bytes, & Block UNC Paths
- **Files:** `src\Models.cs`, `src\CustomPngStudioWindow.cs`
- **Problem:**
  1. `LoadBitmapNoLock` (`src\CustomPngStudioWindow.cs:60-81`) calls `File.ReadAllBytes` with no size cap, no PNG header check, and no `DecodePixelWidth` cap, exposing the UI thread to PNG decompression bombs (e.g., `32768x32768` `IHDR` allocating ~4 GB).
  2. `ResolveCompanionPng` and `ResolveAgentPng` (`src\Models.cs:311-377`) pass paths from `data\settings.json` directly to `File.Exists` / `LoadBitmapNoLock` without rejecting UNC paths (`\\server\share\...`), which can trigger outbound SMB / Net-NTLMv2 connections.
  3. `CreateSlotCard` (`src\CustomPngStudioWindow.cs:626`) accepts `.webp` / `.jpg` in `OpenFileDialog.Filter` and `CopyIntoCustomPngs` (`lines 690-704`) copies/renames them to `.png` without checking PNG magic bytes (`89 50 4E 47 0D 0A 1A 0A`).
- **Fix:**
  1. Add `public static bool IsSafeLocalFilePath(string path)` in `ModelHelpers` (`src\Models.cs`):
     - Return `false` if `string.IsNullOrWhiteSpace(path)`, if `path.StartsWith(@"\\")` or `path.StartsWith("//")` or `path.StartsWith(@"\??\")`, or if `!Path.IsPathRooted(path)` or `Uri.TryCreate` shows UNC (`uri.IsUnc`).
     - Verify `File.Exists(path)`.
     - Use `IsSafeLocalFilePath` inside `ResolveCompanionPng` and `ResolveAgentPng` instead of raw `File.Exists`.
  2. Add `public static bool HasValidPngHeader(string path)` (e.g., on `CustomPngStudioWindow` or `ModelHelpers`):
     - Check `!IsSafeLocalFilePath(path)` -> `false`.
     - Check `FileInfo(path).Length` is between `8` bytes and `10 * 1024 * 1024` bytes (`10 MB`).
     - Read first 8 bytes and verify `{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }`.
  3. Update `CustomPngStudioWindow.LoadBitmapNoLock(string filePath)` (`src\CustomPngStudioWindow.cs:60-81`):
     - Return `null` if `!ModelHelpers.IsSafeLocalFilePath(filePath)` or `!HasValidPngHeader(filePath)`.
     - Set `bmp.DecodePixelWidth = 256;` inside `BeginInit()` / `EndInit()` (with `CacheOption = BitmapCacheOption.OnLoad`).
  4. In `CustomPngStudioWindow.CreateSlotCard` (`line 626`): restrict `dlg.Filter = "PNG Images (*.png)|*.png";`.
  5. In `CopyIntoCustomPngs` (`lines 690-704`): verify `HasValidPngHeader(sourcePath)` before copying (and return `null` or refuse invalid files on drag-drop/browse if invalid).

---

## 2. Medium-High & Medium Fixes

### RT-05 — Cap Log Tailing in `CompositeWatcherSubscription` & Tighten `CursorAdapter.ParseLine`
- **Files:** `src\adapters\IAgentAdapter.cs`, `src\adapters\CursorAdapter.cs`
- **Problem:**
  1. `CompositeWatcherSubscription.ReadNewLines` (`src\adapters\IAgentAdapter.cs:334-368`) resets `offset = 0` on truncation/creation and reads every line via `sr.ReadLine()` with no byte/line cap, calling `_onLine` in a tight loop and potentially flooding the WPF `Dispatcher` queue on large logs.
  2. `CursorAdapter.Subscribe` (`src\adapters\CursorAdapter.cs:63-93`) watches all `*.log` files under `%APPDATA%\Cursor\logs\` recursively, and `ParseLine` (`lines 104-128`) emits `StateConfidence.Confirmed` if any line anywhere contains `"approval"`, `"confirm"`, `"run_terminal_cmd"`, `"executing command"`, `"edit_file"`, or `"write_file"`, hijacking the active Cursor state via `MatchArtifactTarget` fallback.
- **Fix:**
  1. In `CompositeWatcherSubscription.ReadNewLines`:
     - If `fs.Length - offset > 256 * 1024`, jump `offset = fs.Length - 64 * 1024` and discard the first partial line (`sr.ReadLine()`) so newly seen large logs don't replay from byte `0`.
     - Cap reading per invocation (e.g., track lines read and process at most `100` lines per tick, or collect non-empty lines and keep only the tail `50` lines if exceeded, skipping lines longer than `64 * 1024` chars).
  2. In `CursorAdapter.ParseLine` (`src\adapters\CursorAdapter.cs:95-129`):
     - Keep `TryParseStandardHookLine` for `StateConfidence.Confirmed` JSON hook lines.
     - For plain `.log` lines, do **not** match generic words like `"confirm"` or `"approval"` across arbitrary Cursor UI/extension logs; require Cursor agent-specific patterns (e.g., `"cursor-agent"` with approval/confirm, or `"run_terminal_cmd"` / `"executing command"` / `"edit_file"` / `"write_file"` in an agent context) and mark plain-text log matches as `StateConfidence.Inferred` rather than `Confirmed`.

---

### RT-06 — Fix `_exitWaits` Native Handle Leak on Canonical PID Change, State Sync, & `Dispose()` Race
- **Files:** `src\CompanionEngine.cs`
- **Problem:**
  1. In `RefreshProcesses()` (`src\CompanionEngine.cs:276-290`), when `existing.Pid != det.Pid`, `existing.Pid` is overwritten and `RegisterProcessExitWait(det.Pid, ...)` is called **without unregistering/closing the previous PID's wait handle in `_exitWaits`**, leaking native `HANDLE`s and wait registrations.
  2. Also when `existing.Pid != det.Pid`, `existing.State`, `existing.Confidence`, `existing.TaskSummary`, and `existing.LastActivityAt` are not synced from `det`.
  3. In `RegisterProcessExitWait` (`line 355`) and `Dispose()` (`lines 803-811`), `UnregisterWaitEx(reg.WaitHandle, IntPtr.Zero)` is non-blocking, so immediately calling `CloseHandle(reg.ProcessHandle)` can race with a firing `CallbackKeepAlive`.
- **Fix:**
  1. Add a private helper `UnregisterExitWait(int pid)` (called under `lock (_sync)`) that looks up `pid` in `_exitWaits`, removes it, calls `UnregisterWaitEx(reg.WaitHandle, new IntPtr(-1))` (or safely handles `CloseHandle` after blocking wait/disposal check — note `UnregisterWaitEx(handle, new IntPtr(-1))` waits for callbacks if not called from the callback thread itself; in `HandleProcessExit` which runs on the wait callback thread, keep `IntPtr.Zero` and guard `if (_disposed)`).
  2. In `RefreshProcesses()` when `existing.Pid != det.Pid`:
     - Call `UnregisterExitWait(existing.Pid);` before assigning `existing.Pid = det.Pid;`.
     - Sync `existing.State = det.State; existing.Confidence = det.Confidence; existing.TaskSummary = det.TaskSummary; existing.LastActivityAt = det.LastActivityAt;`.
  3. In `RegisterProcessExitWait` callback (`line 355`): add `if (_disposed) return;` before calling `GetExitCodeProcess(hProc, out exitCode)`.

---

### RT-07 — Remove Double `GetState()` Under `_sync` Lock & Avoid 512 KB LOH Env Block Allocations
- **Files:** `src\CompanionEngine.cs`, `src\ProcessScanner.cs`
- **Problem:**
  1. `RefreshProcesses()` (`src\CompanionEngine.cs:236`) calls `adapter.GetState(det, snapshot)` for every detected process, and then calls `adapter.GetState(...)` **again inside `lock (_sync)`** (`lines 296, 307`), performing `EnumWindows` and PEB reads while holding `_sync`.
  2. `ProcessScanner.ReadPebDetails` / `ExtractEnvVar` (`src\ProcessScanner.cs:162-200`) reads up to `512 KB` and calls `Encoding.Unicode.GetString(envBytes).Split('\0')` on every poll cycle for every terminal descendant, causing Large Object Heap (LOH) churn for environment blocks $\ge 85\text{ KB}$.
- **Fix:**
  1. In `CompanionEngine.RefreshProcesses()`:
     - For a newly added entry (`else` branch at line 305), `det` already had `adapter.GetState(det, snapshot)` run at line 236 — do not call it a second time under `lock (_sync)`.
     - For an existing entry (`if` branch at line 274), avoid re-running `adapter.GetState(existing, snapshot)` if `existing` already holds `det` from the same snapshot pass, or update terminal/child state from `det` (which was already computed outside `lock (_sync)` at line 236) while preserving confirmed hook states (`existing.Confidence == StateConfidence.Confirmed && (DateTime.UtcNow - existing.LastActivityAt).TotalSeconds <= 3.0`).
  2. In `ProcessScanner.ReadPebDetails` / `ExtractEnvVar` (`src\ProcessScanner.cs:162-200`):
     - Cap `envSize` to `64 * 1024` (or scan `envBytes` in chunks/UTF-16LE byte span directly for `WT_SESSION=`) so `ExtractEnvVar` does not allocate a multi-hundred-KB string + `string[]` array on the LOH.

---

### RT-08 — Prevent Arbitrary Terminal Window Focus in `WindowFocuser.ResolveTerminalHwnd`
- **Files:** `src\WindowFocuser.cs`
- **Problem:**
  - `ResolveTerminalHwnd` (`src\WindowFocuser.cs:48-89`) initializes `bestScore = int.MinValue` and awards `+20` just for `CASCADIA_HOSTING_WINDOW_CLASS`. Clicking a Demo/Simulated tile (`TerminalPid == 0`) or an agent whose terminal closed focuses an unrelated Windows Terminal window.
- **Fix:**
  - Require `bestScore >= 25` (meaning at least `terminalPid`, `projectName`, or `agentFamilyName` matched in addition to window class); otherwise return `IntPtr.Zero`.

---

## 3. Low-Medium & Spec-Compliance Fixes

### RT-09 — Atomic Settings Save, Closure Bug Fix, Remove Spec-Violating Bounce Animation, Unmute Default, & Docs Sync
- **Files:** `src\Models.cs`, `src\CustomPngStudioWindow.cs`, `src\CompanionWindow.cs`, `data\settings.json`, `README.md`
- **Problems & Fixes:**
  1. **Atomic `settings.json` Save (`src\Models.cs:191-233`):**
     - In `CompanionSettings.Save(string path)`: write JSON to `path + ".tmp"` first, then replace `path` (`File.Copy(tmp, path, true); File.Delete(tmp);`) so a crash or concurrent save never corrupts `data\settings.json`.
     - In `CompanionSettings.Load(string path)`: if deserialization throws or returns `null` on an existing non-empty file, back it up to `path + ".corrupt.bak"` before falling back to `new CompanionSettings()`.
  2. **Mutated Closure Variable (`src\CustomPngStudioWindow.cs:627, 650-656`):**
     - `CreateSlotCard` mutates the `title` parameter (`title = "[custom] " + title;`), which changes the `OpenFileDialog.Title` captured by the `browseBtn.Click` closure at line 627 (`"Select PNG for [custom] ..."`). Use a separate local variable `string displayTitle = isCustom ? "[custom] " + title : title;` for `titleTxt.Text` and leave `title` untouched.
  3. **Spec Compliance — Remove Continuous Bounce/Scale Timer (`src\CompanionWindow.cs:698-752`, `CLAUDE.md:44`):**
     - `CLAUDE.md` specifies *"no bouncing/glowing overlays"*, but `_animTimer` (`OnAnimTick`) continuously bounces and scales dock tiles every `45ms`. Remove `_animTimer` / `OnAnimTick` (or keep tiles completely static/flat) so the UI strictly complies with `CLAUDE.md`.
  4. **Shipped Config Default (`data\settings.json:63`):**
     - Set `"Muted": false` in `data\settings.json` (preserving all `AgentFamilyPngs`, `AgentStatePngs`, and `ModelDisplayConfigs` paths) so notifications are enabled by default as documented.
  5. **Documentation Sync (`README.md:28-30, 104`):**
     - Update `README.md` to match the current implementation (tray-only hide/restore instead of collapse pill, `Model > Icon` studio button, and single canonical agent per family).

---

## 4. Required Automated Regression Tests (`tests\CompanionTests.cs`)

Add a dedicated `TestRedTeamSecurityRegressions()` method (and invoke it in `Main()`) in `tests\CompanionTests.cs` covering:
1. **RT-01 (`USER_INPUT` classification & summary redaction):**
   - `AntigravityAdapter.ParseLine("transcript.jsonl", "{\"type\":\"USER_INPUT\",\"content\":\"hello\"}")` returns `State == AgentState.Thinking` (never `WaitingApproval`).
   - `AntigravityAdapter.ParseLine` `PLANNER_RESPONSE` `write_file` redacts secrets in path/summary.
2. **RT-02 (`agentapi.bat` & `"subagent"` path survival):**
   - `CompanionEngine.FilterSubAgentsAndDeduplicate` keeps an `Antigravity` instance with `CommandLine = @"cmd.exe /c C:\Users\alins\.gemini\antigravity-cli\bin\agentapi.bat"` and a `ClaudeCode` instance with `CommandLine = @"claude.exe C:\src\subagent-refactor"`, while still excluding `--subagent`, `--worker`, `--parent-pid`, `--internal-worker`.
3. **RT-03 (`SecretRedactor` bypass closures):**
   - `SecretRedactor.Redact` strips `--token=secret123`, `--api-key=secret456`, `--auth-token=secret789`, `https://alice:s3cr3t@github.com/org/repo`, `glpat-1234567890abcdefghij`, `hf_abcdefghijklmnopqrstuvwxyz1234`, and `AKIAIOSFODNN7EXAMPLE`.
4. **RT-04 (UNC rejection & PNG magic validation):**
   - `ModelHelpers.IsSafeLocalFilePath(@"\\evil.example\share\icon.png")` returns `false`.
   - `CustomPngStudioWindow.LoadBitmapNoLock` returns `null` for a temp file containing non-PNG bytes (e.g., ASCII text renamed `.png`) and loads a valid PNG cleanly.
5. **RT-05 (`CursorAdapter` false-positive hardening):**
   - `CursorAdapter.ParseLine("renderer.log", "User clicked confirm dialog in UI")` returns `null` (or at most `StateConfidence.Inferred`, never `StateConfidence.Confirmed` `WaitingApproval`).
6. **RT-08 (`WindowFocuser.ResolveTerminalHwnd` unrelated window guard):**
   - Calling `WindowFocuser.ResolveTerminalHwnd(999999, "nonexistent-project-xyz-999", "NonExistentModelXYZ")` returns `IntPtr.Zero`.
7. **RT-09 (`CompanionSettings.Save` atomic persistence):**
   - Saving and reloading settings preserves all dictionaries without leaving `.tmp` files behind.

---

## 5. Verification Checklist (Run Before Finishing)

1. Confirm strict C# 5 compatibility (compile cleanly with `csc.exe` 4.8).
2. Stop any running `AgentCompanion` process, then run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File C:\Users\alins\terminal-agent-companion\build.ps1
   ```
3. Run the automated test suite and verify 100% pass:
   ```powershell
   C:\Users\alins\terminal-agent-companion\AgentCompanionTests.exe
   ```
4. Re-render offline previews and verify no visual regressions:
   ```powershell
   C:\Users\alins\terminal-agent-companion\AgentCompanion.exe --render-preview C:\Users\alins\terminal-agent-companion\previews
   ```
5. Verify live process scanning:
   ```powershell
   C:\Users\alins\terminal-agent-companion\AgentCompanion.exe --dump-detected | Out-String
   ```
