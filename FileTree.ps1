#Requires -Version 5.1

param(
    [string]$ParamsPath
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:timers = @{}
try {
    $script:timers['processStart'] = [System.Diagnostics.Process]::GetCurrentProcess().StartTime
} catch {
    $script:timers['processStart'] = Get-Date
}

$script:timers['P0'] = Get-Date
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  FileTree - 文件树生成工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

function Show-Notification {
    param([string]$Title, [string]$Text, [string]$Type = "info")
    try {
        $duration = if ($Type -in @("warning", "error")) { 5000 } else { 3000 }
        $body = @{ message = "$Title`: $Text"; notify_type = $Type; duration = $duration } | ConvertTo-Json -Compress
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Content-Type", "application/json")
        $wc.UploadString("http://127.0.0.1:9527/api/notify", "POST", $body) | Out-Null
    } catch {
        # 盒子未运行则静默忽略
    }
}

$script:BRANCH = [char]0x251C + [char]0x2500 + [char]0x2500 + ' '
$script:CORNER = [char]0x2514 + [char]0x2500 + [char]0x2500 + ' '
$script:PIPE   = [char]0x2502 + '   '
$script:SPACE4 = '    '

function Get-FolderTree {
    param(
        [string]$folderPath,
        [string]$indent = "",
        [bool]$isLast = $false
    )

    $folderName = [System.IO.Path]::GetFileName($folderPath)
    if ($isLast) {
        $output = $indent + $script:CORNER + $folderName
    } else {
        $output = $indent + $script:BRANCH + $folderName
    }

    try {
        $items = @(Get-ChildItem -LiteralPath $folderPath -Force -ErrorAction Stop | Sort-Object Name)
    } catch {
        return $output
    }

    $count = $items.Count
    $i = 0

    foreach ($item in $items) {
        $i++
        $isLastItem = ($i -eq $count)

        if ($isLast) {
            $newIndent = $indent + $script:SPACE4
        } else {
            $newIndent = $indent + $script:PIPE
        }

        if ($item.PSIsContainer) {
            $output += "`n" + (Get-FolderTree -folderPath $item.FullName -indent $newIndent -isLast $isLastItem)
        } else {
            if ($isLastItem) {
                $output += "`n" + $newIndent + $script:CORNER + $item.Name
            } else {
                $output += "`n" + $newIndent + $script:BRANCH + $item.Name
            }
        }
    }

    return $output
}

$script:timers['P0_fn'] = Get-Date

$paramsPath = $ParamsPath
if (-not $paramsPath -or -not (Test-Path -LiteralPath $paramsPath)) {
    Show-Notification -Title "文件树生成" -Text "未传入参数文件，请选中文件夹后通过右键菜单使用" -Type "warning"
    Write-Host "[错误] 未传入参数文件，请选中文件夹后通过右键菜单使用" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

$json = Get-Content -Path $paramsPath -Encoding UTF8 -Raw | ConvertFrom-Json
$folders = @($json.data.target_paths) | Where-Object { $_ }
$script:timers['P1'] = Get-Date

if ($folders.Count -eq 0) {
    Show-Notification -Title "文件树生成" -Text "未检测到文件夹路径，请选中文件夹后通过右键菜单使用" -Type "warning"
    Write-Host "[错误] 未检测到文件夹路径，请选中文件夹后通过右键菜单使用" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host "找到 $($folders.Count) 个文件夹，开始生成文件树..." -ForegroundColor Green
Write-Host ""

$treeTexts = @()
$details = @()
$successCount = 0
$failCount = 0

foreach ($folder in $folders) {
    if (Test-Path -LiteralPath $folder -PathType Container) {
        try {
            Write-Host "------------------------------" -ForegroundColor DarkGray
            Write-Host "文件夹: $folder" -ForegroundColor Yellow
            Write-Host "------------------------------" -ForegroundColor DarkGray
            $tree = "文件夹: $folder`n" + (Get-FolderTree -folderPath $folder)
            Write-Host $tree -ForegroundColor White
            $treeTexts += $tree
            $details += @{ input = $folder; status = "ok" }
            $successCount++
        } catch {
            Write-Host "[处理错误] $folder : $($_.Exception.Message)" -ForegroundColor Red
            $details += @{ input = $folder; status = "error"; error = $_.Exception.Message }
            $failCount++
        }
    } else {
        Write-Host "[跳过] $folder : 路径不存在或不是文件夹" -ForegroundColor Red
        $details += @{ input = $folder; status = "error"; error = "路径不存在或不是文件夹" }
        $failCount++
    }
}

$script:timers['P2'] = Get-Date

if ($treeTexts.Count -gt 0) {
    $finalText = $treeTexts -join "`n`n"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::SetText($finalText, [System.Windows.Forms.TextDataFormat]::UnicodeText)
}

$script:timers['P3'] = Get-Date

$notifyMsg = "处理完成: ${successCount}个文件夹成功"
if ($failCount -gt 0) {
    $notifyMsg += ", ${failCount}个失败"
}
Show-Notification -Title "文件树生成" -Text $notifyMsg -Type "success"

$t_process   = ($script:timers['P0'] - $script:timers['processStart']).TotalMilliseconds
$t_fn_def    = ($script:timers['P0_fn'] - $script:timers['P0']).TotalMilliseconds
$t_parse     = ($script:timers['P1'] - $script:timers['P0_fn']).TotalMilliseconds
$t_traverse  = ($script:timers['P2'] - $script:timers['P1']).TotalMilliseconds
$t_clipboard = ($script:timers['P3'] - $script:timers['P2']).TotalMilliseconds
$t_total     = ($script:timers['P3'] - $script:timers['processStart']).TotalMilliseconds

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  处理完成" -ForegroundColor Cyan
Write-Host "  成功: $successCount | 失败: $failCount | 总计: $($folders.Count)" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────" -ForegroundColor Cyan
Write-Host ("  进程启动 → 首行输出: {0,6:F2} ms" -f $t_process) -ForegroundColor Cyan
Write-Host ("  函数定义:            {0,6:F2} ms" -f $t_fn_def) -ForegroundColor Cyan
Write-Host ("  参数文件解析:        {0,6:F2} ms" -f $t_parse) -ForegroundColor Cyan
Write-Host ("  文件树遍历:          {0,6:F2} ms" -f $t_traverse) -ForegroundColor Cyan
Write-Host ("  剪贴板复制:          {0,6:F2} ms" -f $t_clipboard) -ForegroundColor Cyan
Write-Host "  ─────────────────────────────" -ForegroundColor Cyan
Write-Host ("  总耗时 (进程创建起): {0,6:F2} ms" -f $t_total) -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "文件树已复制到剪贴板。" -ForegroundColor Green
Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

$result = @{
    summary = @{
        total = $folders.Count
        success = $successCount
        fail = $failCount
    }
    details = $details
} | ConvertTo-Json -Compress

Write-Output $result
