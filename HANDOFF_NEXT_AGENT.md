# Terminal Agent Companion — Project Handoff & Continuation Notes

**Workspace:** `C:\Users\alins\terminal-agent-companion`  
**Target Environment:** Windows 11 (x64, native Windows only, no WSL), .NET Framework 4.8 (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`), Python 3.11.9 (stdlib only).  
**Last Updated:** 2026-11-14 (after chibi icon slotting + Brutalist UI rework pass)

---

## 1. Verified File & Binary Inventory

```text
C:\Users\alins\terminal-agent-companion\
├── AgentCompanion.exe                                  # STALE binary (3:48 AM, 114,176 B) — locked during last build!
├── AgentCompanion.new.exe                              # Latest Brutalist build (8:24 AM, 119,296 B)
├── AgentCompanionTests.exe                             # Latest test binary (8:24 AM, 140,288 B; 51/51 assertions pass)
├── AgentCompanionTests.pdb
├── CLAUDE.md                                           # Persistent project instructions for Claude Code
├── HANDOFF_NEXT_AGENT.md                               # This handoff file
├── build.ps1                                           # Compiles AgentCompanion.exe & AgentCompanionTests.exe (includes src\Theme.cs)
├── README.md
├── start.bat                                           # Builds if missing, launches AgentCompanion.exe
├── assets\defaults\
│   ├── .gitkeep
│   ├── agent-{claude,codex,cursor,antigravity}.png     # STILL old 3:43 AM sprites (generate_default_pngs.py not re-run yet)
│   ├── agent-{claude,codex,cursor,antigravity}-{idle,thinking,running_command,editing_files,waiting_approval,finished,errored}.png
│   └── companion-{idle,thinking,running_command,editing_files,waiting_approval,finished,errored}.png
├── data\
│   ├── settings.json                                   # All 21 extracted chibi icons + 3 defaults registered; IconSize=64
│   ├── custom_pngs\
│   │   ├── {claude,codex,antigravity}-default.png      # Base family fallbacks (copied from idle)
│   │   └── {claude,codex,antigravity}-{idle,thinking,running_command,editing_files,waiting_approval,finished,errored}.png (21 sprites)
│   └── hooks\.gitkeep
├── docs\superpowers\
│   ├── plans\2026-11-14-terminal-agent-companion.md
│   └── specs\2026-11-14-terminal-agent-companion-design.md
├── scripts\
│   ├── generate_default_pngs.py                        # Rewritten for flat badges, NOT yet executed onto assets\defaults\
│   └── simulate_agents.py
├── src\
│   ├── Theme.cs                                        # NEW: Brutalist design tokens, HardShadow, MakeButton, MakeTag
│   ├── CompanionEngine.cs                              # Sub-agent exclusion + strict 1-per-family deduplication
│   ├── CompanionWindow.cs                              # Brutalist dock + drawer + 1.3x extra-visible avatars in #F5F5EE frames
│   ├── CustomPngStudioWindow.cs                        # Brutalist Studio restyle (still has _groupCombo & minor text clipping)
│   ├── Models.cs                                       # GroupInstances default -> true
│   ├── NotificationService.cs
│   ├── ProcessScanner.cs                               # ToolHelp32 + x64 PEB reader (CommandLine, CurrentDirectory, WT_SESSION)
│   ├── Program.cs                                      # --dump-detected, --render-preview <dir>, --demo
│   ├── SecretRedactor.cs
│   ├── Win32Native.cs
│   ├── WindowFocuser.cs
│   └── adapters\
│       ├── IAgentAdapter.cs
│       ├── ClaudeCodeAdapter.cs
│       ├── CodexAdapter.cs
│       ├── CursorAdapter.cs
│       └── AntigravityAdapter.cs
└── tests\
    └── CompanionTests.cs                               # 51 assertions pass; missing dedicated FilterSubAgentsAndDeduplicate tests
```

---

## 2. What Has Been Completed & Verified

### A. Core Detection, Focus & Redaction Engine
- **Win32 Process + x64 PEB Inspection (`src\ProcessScanner.cs`, `src\Win32Native.cs`, `src\WindowFocuser.cs`, `src\adapters\*.cs`):**
  - Enumerates processes via `CreateToolhelp32Snapshot`, reads x64 PEB (`NtQueryInformationProcess` + `ReadProcessMemory`) for `ImagePathName`, `CommandLine`, `CurrentDirectory`, and `WT_SESSION`.
  - Walks parent process chain (`agent -> shell -> OpenConsole/conhost -> WindowsTerminal.exe`) to bind project folder and focus the owning Windows Terminal window (`SetForegroundWindow`).
  - `SecretRedactor.cs` redacts API keys/tokens from command lines and summaries.
- **Sub-Agent Filtering & 1-Per-Family Deduplication (`src\CompanionEngine.cs`, `src\Models.cs`):**
  - `CompanionEngine.FilterSubAgentsAndDeduplicate(IList<AgentInstance> rawDetected, Dictionary<int, ProcessInfo> snapshot)` excludes `--subagent`, `subagent`, `--worker`, `--parent-pid`, `--internal-worker`, and `agentapi` command lines plus any candidate with an agent ancestor PID within 12 hops.
  - Deduplicates strictly to **at most 1 canonical instance per `AgentFamily`**, normalized to `InstanceId = ModelHelpers.FamilyKey(family)`.
  - `AgentDisplayConfig.GroupInstances` default changed to `true`.

### B. Extracted & Slotted Chibi Agent Icons (`data\custom_pngs\`, `data\settings.json`)
- Extracted, aligned, and cleaned **21 character sprites** across `Claude Code` (`claude-*`), `Codex` (`codex-*`), and `Antigravity` (`antigravity-*`) for all 7 states (`idle`, `thinking`, `running_command`, `editing_files`, `waiting_approval`, `finished`, `errored`), plus 3 family fallback PNGs (`*-default.png`).
- All 24 PNGs are stored in `data\custom_pngs\` and wired in `data\settings.json` (`AgentFamilyPngs` + `AgentStatePngs`), with `IconSize = 64` and `DisplayStyle = "IconAndState"` for all 4 families.
- Verified end-to-end in WPF `--render-preview` screenshots.

### C. Brutalist UI Rework (`src\Theme.cs`, `src\CompanionWindow.cs`, `src\CustomPngStudioWindow.cs`, `build.ps1`)
- Created **`src\Theme.cs`** and registered it in `build.ps1`:
  - Flat dark/paper brutalist tokens: `Black` (`#0A0A0A`), `Panel` (`#141414`), `Paper` (`#F5F5EE`), `Muted` (`#AAAAA2`), `Accent` (`#FFE600`).
  - Typography & icons: `Theme.Mono` (`Cascadia Mono, Consolas, Courier New`) and `Theme.Icons` (`Segoe MDL2 Assets`).
  - Zero rounded corners (`CornerRadius(0)`), zero gradients, zero blur (`Theme.HardShadow` uses `BlurRadius = 0`), square `2px` buttons inverting to yellow `#FFE600` on hover (`Theme.MakeButton`), and solid flat uppercase state tags (`Theme.MakeTag`).
- Updated **`src\CompanionWindow.cs`**:
  - Dock (`_modelsDock`) and drawer (`_expandedPanel`, widened to `520`) use `3px` `#F5F5EE` borders, `#0A0A0A` backgrounds, and hard offset shadows.
  - **Extra-visible avatars:** Floating dock tiles render sprites at `1.3x` (`cfg.IconSize * 1.3` = `83px` at default `64px`) inside `#F5F5EE` cream-paper square frames with `3px` black borders (`BuildModelTile`); expanded drawer rows render `56px` sprites inside `#F5F5EE` frames (`BuildAgentRow`).
  - Dock `WrapPanel` `MaxWidth` expanded up to `Math.Min(1100.0, waW - 80.0)` so all 4 model tiles render in a single horizontal row (`629x211`).
  - `--render-preview` uses simulated `1920x1032` work area (`_simWorkW`, `_simWorkH`) and propagates `System.Windows.Documents.TextElement.SetFontFamily(..., Theme.Mono)` onto detached render roots.
- Updated **`src\CustomPngStudioWindow.cs`** to brutalist colors/buttons (`Theme.MakeButton`, `#0A0A0A`/`#141414`/`#F5F5EE`/`#FFE600`).
- **Build & Test Status:**
  - `AgentCompanionTests.exe` rebuilt at 8:24 AM and **passes all 51 assertions** (`ALL TESTS PASSED (51 assertions verified)`).
  - `AgentCompanion.new.exe` rebuilt at 8:24 AM (`build.ps1` could not overwrite `AgentCompanion.exe` while a live process held a file lock, so the previous session compiled `AgentCompanion.new.exe` instead).

---

## 3. Remaining Work & Known Issues to Fix

Inspecting the latest rendered previews (`C:\Users\alins\.gemini\antigravity-cli\brain\d08bca8a-edc5-4e90-a740-7b0428e9b15f\brutal_previews\`) and source files shows these remaining items:

1. **Land the Main Binary (`AgentCompanion.exe`):**
   - `AgentCompanion.exe` is still the stale `3:48 AM` build; `AgentCompanion.new.exe` is the `8:24 AM` build.
   - Ensure no `AgentCompanion` process is running, build via `build.ps1` so `AgentCompanion.exe` is up to date, and delete `AgentCompanion.new.exe`.

2. **Regenerate Default Fallback Sprites (`assets\defaults\*.png`):**
   - `assets\defaults\*.png` are still the old `3:43 AM` circular/glowing sprites (visible on the `Cursor` tile in the latest dock preview).
   - `scripts\generate_default_pngs.py` was rewritten for flat badges, and should also be checked/updated if you want sharp brutalist square corners (`r = 0` or minimal) instead of `16px` rounded corners, then executed (`python scripts\generate_default_pngs.py`) to overwrite `assets\defaults\*.png`.

3. **Resolve `_collapsedPill` vs Tray-Only Hide/Restore (`src\CompanionWindow.cs`):**
   - `_collapsedPill` (`"Models Online"` yellow badge) is still in `src\CompanionWindow.cs` (lines 56–57, 210–227, 604–630, 1417–1453) and appears as the cyan `Pill Rect` in `preview-desktop-placement.png`.
   - Finish the requested tray hide/restore behavior: clicking `HIDE` should hide the window completely (`Visibility = Visibility.Hidden`, `_settings.IsCollapsed = true`) with no floating pill left on screen, and `_trayIcon` should provide `"Show / Hide Companion Bar"` (plus left-click / double-click restore) in its context menu to bring the bar back cleanly (`Visibility.Visible`, `ApplyAnchoredPosition()`, `Activate()`). Update `RenderAllPreviews` / `RenderDesktopPlacement` accordingly so they don't reference `_collapsedPill`.

4. **Polish `src\CustomPngStudioWindow.cs` (Observed in `preview-studio.png`):**
   - Remove the obsolete `Instances:` (`_groupCombo`) selector (lines 243–255), since `CompanionEngine.FilterSubAgentsAndDeduplicate` strictly outputs 1 canonical instance per `AgentFamily` (also note `data\settings.json` has `cursor.GroupInstances: false`, which becomes irrelevant once `BuildFloatingModelItems` or the engine enforces 1-per-family).
   - Fix `_styleCombo` (`Width = 160`) clipping `"Icon + Model & State"` at the dropdown arrow (widen to ~`185`–`195` or tighten label width).
   - Fix state card title truncation (`"Claude Code > Default Base Icon  [c..."`) so `[custom]` is not clipped by the `CHOOSE .PNG...` / `RESET` buttons.

5. **Polish `src\CompanionWindow.cs` Expanded Drawer Row Layout (Observed in `preview-expanded.png`):**
   - In `BuildAgentRow`, `"Files: billing/ledger.ts, billing/ledger.test.ts • Elapsed:..."` truncates the `Elapsed:` time on the same line. Split `Elapsed:` into its own right-aligned or separate line so elapsed time is never clipped by long file paths.
   - Check drawer height/padding so all 4 model rows fit cleanly without awkward partial clipping of the 4th card (`ANTIGRAVITY (1)`), or ensure clean scroll margins.

6. **Expand Automated Tests (`tests\CompanionTests.cs`):**
   - Add unit tests for `CompanionEngine.FilterSubAgentsAndDeduplicate` covering:
     - Exclusion of `--subagent` / `--worker` / `--parent-pid` / `--internal-worker` / `agentapi` command lines.
     - Exclusion of child processes whose `ParentPid` chain leads to another candidate agent.
     - Strict 1-instance-per-`AgentFamily` deduplication (`InstanceId` normalized to `ModelHelpers.FamilyKey(family)`).
   - Keep `TestProcessDetectionAndMultiInstance` (adapter-level) and `TestFloatingModelGroupingAndVisibility` passing.

---

## 4. Critical Pitfalls & Constraints

1. **C# 5 Compiler Only (`csc.exe` 4.8.x):**
   - `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` only supports **C# 5**.
   - **NEVER** use `$"..."` string interpolation, `?.` null-conditional operators, `=>` expression-bodied methods/properties, `nameof(...)`, or pattern matching (`is Type x`). Use `string.Format`, classic null checks, `delegate { ... }`, etc.
2. **WPF / WinForms / System.Drawing Namespace Collisions:**
   - `CompanionWindow.cs` uses both WinForms and WPF. Preserve the existing type aliases (`WinForms`, `WpfBrush`, `WpfBrushes`, `WpfColor`, `WpfImage`, `WpfRectangle`, `System.Drawing.Icon`, `System.Windows.Documents.TextElement`).
3. **File Locks & Sandbox Permissions:**
   - Stop any running `AgentCompanion` process before running `build.ps1` (line 43 of `build.ps1` attempts this automatically, but a locked exe can still fail compilation if running in another session).
   - Check `python scripts\generate_default_pngs.py` succeeds without `PermissionError` on `assets\defaults\*.png`.

---

## 5. Ready-to-Use Prompt for Claude Code

```text
Read CLAUDE.md and HANDOFF_NEXT_AGENT.md in C:\Users\alins\terminal-agent-companion first, then finish the remaining work cleanly:

1. Regenerate default fallback sprites: inspect scripts\generate_default_pngs.py (align corners/style with the flat brutalist aesthetic in src\Theme.cs if needed) and run it so assets\defaults\*.png no longer contain old circular/glowing sprites (visible on Cursor).
2. Finish hide/restore behavior in src\CompanionWindow.cs:
   - Remove _collapsedPill completely; clicking HIDE should hide the window (Visibility.Hidden, IsCollapsed = true) with zero floating pill left on screen.
   - Add "Show / Hide Companion Bar" plus left-click/double-click restore on _trayIcon to toggle visibility back on cleanly.
   - Update RenderAllPreviews and RenderDesktopPlacement so they no longer reference _collapsedPill.
3. Polish UI issues observed in the brutalist previews:
   - In src\CompanionWindow.cs (BuildAgentRow), prevent long Files lists from truncating the Elapsed time.
   - In src\CustomPngStudioWindow.cs, remove the obsolete Instances (_groupCombo) dropdown, widen _styleCombo so "Icon + Model & State" doesn't clip, and ensure "[custom]" in state card titles isn't clipped by buttons.
4. Update tests\CompanionTests.cs with unit tests for CompanionEngine.FilterSubAgentsAndDeduplicate (CLI flag exclusion, parent-PID ancestor exclusion, 1-per-family deduplication).
5. Remember C# 5 only (no $"" interpolation, no ?., no nameof, no => members).
6. Stop any running AgentCompanion, delete stale AgentCompanion.new.exe, run build.ps1 to update AgentCompanion.exe and AgentCompanionTests.exe, run AgentCompanionTests.exe (100% pass), run AgentCompanion.exe --render-preview to visually verify all previews, and test --dump-detected.
```
