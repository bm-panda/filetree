#Requires -Version 5.1

param(
    [string]$ParamsPath
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

$paramsPath = $ParamsPath
if (-not $paramsPath -or -not (Test-Path -LiteralPath $paramsPath)) {
    Show-Notification -Title "文件树生成" -Text "未传入参数文件，请选中文件夹后通过右键菜单使用" -Type "warning"
    exit 0
}

$json = Get-Content -Path $paramsPath -Encoding UTF8 | ConvertFrom-Json
$folders = @($json.data.target_paths) | Where-Object { $_ }

if ($folders.Count -eq 0) {
    Show-Notification -Title "文件树生成" -Text "未检测到文件夹路径，请选中文件夹后通过右键菜单使用" -Type "warning"
    exit 0
}

$treeTexts = @()
$details = @()
$successCount = 0
$failCount = 0

foreach ($folder in $folders) {
    if (Test-Path -LiteralPath $folder -PathType Container) {
        try {
            $tree = "文件夹: $folder`n" + (Get-FolderTree -folderPath $folder)
            $treeTexts += $tree
            $details += @{ input = $folder; status = "ok" }
            $successCount++
        } catch {
            $details += @{ input = $folder; status = "error"; error = $_.Exception.Message }
            $failCount++
        }
    } else {
        $details += @{ input = $folder; status = "error"; error = "路径不存在或不是文件夹" }
        $failCount++
    }
}

if ($treeTexts.Count -gt 0) {
    $finalText = $treeTexts -join "`n`n"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::SetText($finalText, [System.Windows.Forms.TextDataFormat]::UnicodeText)
}

$notifyMsg = "处理完成: ${successCount}个文件夹成功"
if ($failCount -gt 0) {
    $notifyMsg += ", ${failCount}个失败"
}
Show-Notification -Title "文件树生成" -Text $notifyMsg -Type "success"

$result = @{
    summary = @{
        total = $folders.Count
        success = $successCount
        fail = $failCount
    }
    details = $details
} | ConvertTo-Json -Compress

Write-Output $result
