$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Fw = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
$Csc = Join-Path $Fw "csc.exe"
if (!(Test-Path $Csc)) {
    throw "csc.exe not found at $Csc"
}

$Refs = @(
    "/r:$Fw\System.dll",
    "/r:$Fw\System.Core.dll",
    "/r:$Fw\System.Drawing.dll",
    "/r:$Fw\System.Windows.Forms.dll",
    "/r:$Fw\System.Web.Extensions.dll",
    "/r:$Fw\System.Xaml.dll",
    "/r:$Fw\WPF\WindowsBase.dll",
    "/r:$Fw\WPF\PresentationCore.dll",
    "/r:$Fw\WPF\PresentationFramework.dll"
)

$CoreFiles = @(
    (Join-Path $Root "src\Models.cs"),
    (Join-Path $Root "src\SecretRedactor.cs"),
    (Join-Path $Root "src\Win32Native.cs"),
    (Join-Path $Root "src\ProcessScanner.cs"),
    (Join-Path $Root "src\WindowFocuser.cs"),
    (Join-Path $Root "src\adapters\IAgentAdapter.cs"),
    (Join-Path $Root "src\adapters\ClaudeCodeAdapter.cs"),
    (Join-Path $Root "src\adapters\CodexAdapter.cs"),
    (Join-Path $Root "src\adapters\CursorAdapter.cs"),
    (Join-Path $Root "src\adapters\AntigravityAdapter.cs"),
    (Join-Path $Root "src\CompanionEngine.cs"),
    (Join-Path $Root "src\TelegramBotService.cs"),
    (Join-Path $Root "src\NotificationService.cs"),
    (Join-Path $Root "src\Theme.cs"),
    (Join-Path $Root "src\CustomPngStudioWindow.cs"),
    (Join-Path $Root "src\CompanionWindow.cs")
)

$AppOut = Join-Path $Root "AgentCompanion.exe"
$TestOut = Join-Path $Root "AgentCompanionTests.exe"

Get-Process -Name AgentCompanion -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 250

Write-Host "Building $AppOut..."
& $Csc /nologo /optimize+ /platform:x64 /target:winexe /out:$AppOut @Refs @CoreFiles (Join-Path $Root "src\Program.cs")
if ($LASTEXITCODE -ne 0) { throw "AgentCompanion.exe build failed" }

Write-Host "Building $TestOut..."
& $Csc /nologo /debug+ /platform:x64 /target:exe /out:$TestOut @Refs @CoreFiles (Join-Path $Root "tests\CompanionTests.cs")
if ($LASTEXITCODE -ne 0) { throw "AgentCompanionTests.exe build failed" }

Write-Host "Build succeeded!"
