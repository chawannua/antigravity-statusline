#Requires -Version 5.1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    $rawInput = [Console]::In.ReadToEnd()
    if (-not $rawInput -and $input) { $rawInput = $input | Out-String }
    if ([string]::IsNullOrWhiteSpace($rawInput)) { exit 0 }
    $payload = $rawInput | ConvertFrom-Json
} catch { exit 0 }

# --- Dark Blue Minimalist Palette ---
$ESC         = [char]27
$RESET       = "$ESC[0m"
$BOLD        = "$ESC[1m"
$C_DARK_BLUE = "$ESC[38;5;32m"   # Deep Sapphire Blue
$C_SLATE     = "$ESC[38;5;67m"   # Slate Blue
$C_MUTED     = "$ESC[38;5;244m"  # Graphite
$C_DARK      = "$ESC[38;5;238m"  # Dark gray
$C_WHITE     = "$ESC[38;5;253m"  # Crisp off-white
$C_WARN      = "$ESC[38;5;221m"  # Amber
$C_ALERT     = "$ESC[38;5;203m"  # Coral red

$GLYPH_AGY = [char]0x25C6  # ◆
$GLYPH_SEP = [char]0x00B7  # ·
$GLYPH_BAR = [char]0x2501  # ━
$GLYPH_GIT = [char]0x2387  # ⎇
$GLYPH_CLK = [char]0x23F1  # ⏱

$C_SEP = " ${C_MUTED}${GLYPH_SEP}${RESET} "

function Get-ResetTimeStrs([int64]$unixSeconds, [bool]$is7Day) {
    if (-not $unixSeconds) { return @{ Abs = ""; Rel = "" } }
    $target = [DateTimeOffset]::FromUnixTimeSeconds($unixSeconds)
    $now = [DateTimeOffset]::UtcNow
    $diff = $target - $now
    
    $localTime = $target.ToLocalTime()
    $absFmt = if ($is7Day) { 'ddd HH:mm' } else { 'HH:mm' }
    $timeAbs = $localTime.ToString($absFmt)
    
    $timeRel = ""
    if ($diff.TotalSeconds -le 0) { 
        $timeRel = "now" 
    } elseif ($diff.TotalMinutes -lt 1) { 
        $timeRel = "in <1m" 
    } else {
        $parts = @()
        if ($diff.Days -gt 0) {
            $parts += "$($diff.Days)d"
            if ($diff.Hours -gt 0) { $parts += "$($diff.Hours)h" }
        } elseif ($diff.Hours -gt 0) {
            $parts += "$($diff.Hours)h"
            if ($diff.Minutes -gt 0) { $parts += "$($diff.Minutes)m" }
        } else {
            $parts += "$($diff.Minutes)m"
        }
        $timeRel = "in " + ($parts -join ' ')
    }
    
    return @{ Abs = $timeAbs; Rel = $timeRel }
}

function Get-Bar([double]$pct, [int]$width = 10, $activeColor = $C_DARK_BLUE) {
    $p = [math]::Max(0.0, [math]::Min(100.0, $pct))
    $filled = [int][math]::Round(($p / 100.0) * $width)
    if ($filled -gt $width) { $filled = $width }
    $empty = $width - $filled
    $cBar = if ($p -ge 85.0) { $C_ALERT } elseif ($p -ge 65.0) { $C_WARN } else { $activeColor }
    $fStr = [string]$GLYPH_BAR * $filled
    $eStr = [string]$GLYPH_BAR * $empty
    return "${cBar}${fStr}${C_DARK}${eStr}${RESET}"
}

function Get-QuotaBucket($rawPayload, [string]$type) {
    if ($null -eq $rawPayload) { return $null }
    $bucket = $null
    if ($type -eq "5h") {
        if ($rawPayload.quota -and $rawPayload.quota.'gemini-5h') { $bucket = $rawPayload.quota.'gemini-5h' }
        elseif ($rawPayload.quota -and $rawPayload.quota.'3p-5h' -and -not $rawPayload.quota.'3p-5h'.disabled) { $bucket = $rawPayload.quota.'3p-5h' }
        elseif ($rawPayload.rate_limits -and $rawPayload.rate_limits.five_hour) { $bucket = $rawPayload.rate_limits.five_hour }
        elseif ($rawPayload.quota -and $rawPayload.quota.five_hour) { $bucket = $rawPayload.quota.five_hour }
    } else {
        if ($rawPayload.quota -and $rawPayload.quota.'gemini-weekly') { $bucket = $rawPayload.quota.'gemini-weekly' }
        elseif ($rawPayload.quota -and $rawPayload.quota.'3p-weekly' -and -not $rawPayload.quota.'3p-weekly'.disabled) { $bucket = $rawPayload.quota.'3p-weekly' }
        elseif ($rawPayload.quota -and $rawPayload.quota.seven_day) { $bucket = $rawPayload.quota.seven_day }
        elseif ($rawPayload.rate_limits -and $rawPayload.rate_limits.seven_day) { $bucket = $rawPayload.rate_limits.seven_day }
        elseif ($null -ne $rawPayload.weekly_limit) { $bucket = $rawPayload.weekly_limit }
    }
    if ($null -eq $bucket) { return $null }

    $pct = 0.0
    $unixSec = 0
    $now = [DateTimeOffset]::UtcNow

    if ($bucket -is [double] -or $bucket -is [int] -or $bucket -is [long]) {
        $pct = [double]$bucket
    } elseif ($bucket -is [psobject] -or $bucket -is [hashtable]) {
        if ($bucket.disabled -eq $true) { return $null }
        if ($null -ne $bucket.used_percentage) {
            $pct = [double]$bucket.used_percentage
        } elseif ($null -ne $bucket.remaining_fraction) {
            $pct = [math]::Max(0.0, [math]::Min(100.0, (1.0 - [double]$bucket.remaining_fraction) * 100.0))
        }
        if ($bucket.reset_in_seconds) {
            $unixSec = $now.AddSeconds([double]$bucket.reset_in_seconds).ToUnixTimeSeconds()
        } elseif ($bucket.reset_time) {
            try { $unixSec = [DateTimeOffset]::Parse([string]$bucket.reset_time).ToUnixTimeSeconds() } catch {}
        } elseif ($bucket.resets_at) {
            $unixSec = [int64]$bucket.resets_at
        }
    }
    return @{ Pct = $pct; UnixSeconds = $unixSec }
}

function Format-Number($num) {
    if ($null -eq $num -or $num -le 0) { return "0" }
    if ($num -ge 1000000) { return "$([math]::Round($num / 1000000.0, 1))M" }
    elseif ($num -ge 1000) { return "$([math]::Round($num / 1000.0, 1))k" }
    else { return "$num" }
}

# 1. Model & Reasoning Tier
$modelName = "Gemini"
if ($payload.model -and $payload.model.display_name) { $modelName = $payload.model.display_name }
$modelSummary = ""
if ($payload.model -and $payload.model.param_summary) { $modelSummary = " ${C_MUTED}($($payload.model.param_summary))${RESET}" }
if ($payload.model -and $payload.model.max_mode) { $modelSummary += " ${C_ALERT}[MAX]${RESET}" }
$modelPart = "${C_DARK_BLUE}${GLYPH_AGY} ${C_WHITE}${BOLD}${modelName}${RESET}${modelSummary}"

# 2. Workspace Directory
$workDir = ""
if ($payload.workspace -and $payload.workspace.current_dir) { $workDir = $payload.workspace.current_dir }
elseif ($payload.cwd) { $workDir = $payload.cwd }

$homeDir = $env:USERPROFILE
$dirDisplay = "workspace"
if ($workDir) {
    if ($homeDir -and $workDir.StartsWith($homeDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $sub = $workDir.Substring($homeDir.Length)
        $dirDisplay = if ([string]::IsNullOrWhiteSpace($sub)) { "~" } else { "~" + $sub }
    } else {
        try { $dirDisplay = Split-Path -Path $workDir -Leaf } catch { $dirDisplay = $workDir }
    }
}
$dirPart = "${C_SLATE}${dirDisplay}${RESET}"

# 3. Git Status
$gitPart = ""
if ($workDir -and (Test-Path $workDir)) {
    try {
        $isGit = git -C $workDir rev-parse --is-inside-work-tree 2>$null
        if ($isGit -match "true") {
            $branch = (git -C $workDir branch --show-current 2>$null | Out-String).Trim()
            $hash = (git -C $workDir rev-parse --short HEAD 2>$null | Out-String).Trim()
            $status = (git -C $workDir status --porcelain 2>$null | Out-String).Trim()
            $dirtyMark = if ($status) { "${C_WARN}*${RESET}" } else { "" }
            $gitPart = "${C_SLATE}${GLYPH_GIT} ${branch}${dirtyMark}${RESET}"
            if ($hash) { $gitPart += " ${C_MUTED}(${hash})${RESET}" }
        }
    } catch {}
}
if (-not $gitPart) {
    $gitPart = "${C_MUTED}(local)${RESET}"
}

# 4. Session Identity (Only if custom name is set)
$sessionPart = ""
if ($payload.session_name) {
    $sessionPart = "${C_SLATE}[$($payload.session_name)]${RESET}"
}

# 5. Session Elapsed Time
$elapsedPart = ""
if ($payload.transcript_path -and (Test-Path $payload.transcript_path)) {
    try {
        $tFile = Get-Item $payload.transcript_path
        $diff = [DateTime]::UtcNow - $tFile.CreationTimeUtc
        $m = [math]::Floor($diff.TotalMinutes)
        $elapsedStr = if ($m -ge 60) { "$([math]::Floor($m/60))h $($m%60)m" } else { "${m}m" }
        $elapsedPart = "${C_MUTED}${GLYPH_CLK} ${elapsedStr}${RESET}"
    } catch {}
}

# Assemble Line 1
$line1Parts = @($modelPart, $dirPart, $gitPart)
if ($sessionPart) { $line1Parts += $sessionPart }
if ($elapsedPart) { $line1Parts += $elapsedPart }
if ($badges.Count -gt 0) { $line1Parts += ($badges -join " ") }
$line1 = ($line1Parts -join $C_SEP)

# --- Line 2: Context Window & Weekly Limit ---
$usedPct = 0.0
$inputTokens = 0
$outputTokens = 0
$contextSize = 1048576

if ($payload.context_window) {
    if ($null -ne $payload.context_window.used_percentage) { $usedPct = [double]$payload.context_window.used_percentage }
    if ($payload.context_window.total_input_tokens) { $inputTokens = $payload.context_window.total_input_tokens }
    if ($payload.context_window.total_output_tokens) { $outputTokens = $payload.context_window.total_output_tokens }
    if ($payload.context_window.context_window_size) { $contextSize = $payload.context_window.context_window_size }
}

$bar = Get-Bar -pct $usedPct -width 10 -activeColor $C_DARK_BLUE
$pctDisplay = "$([math]::Round($usedPct, 1))%"
$fIn  = Format-Number $inputTokens
$fMax = Format-Number $contextSize
$fOut = Format-Number $outputTokens
$tokenDetails = "${C_MUTED}(In: ${C_DARK_BLUE}${fIn}${C_MUTED} / ${fMax} | Out: ${C_DARK_BLUE}${fOut}${C_MUTED})${RESET}"
$cVal = if ($usedPct -ge 85.0) { $C_ALERT } elseif ($usedPct -ge 65.0) { $C_WARN } else { $C_DARK_BLUE }
$ctxPart = "${C_MUTED}ctx:${RESET} ${bar} ${cVal}${pctDisplay}${RESET} ${tokenDetails}"

# 5-Hour Limit / Quota
$b5 = Get-QuotaBucket $payload "5h"
$part5h = ""
if ($null -ne $b5) {
    $pct5 = $b5.Pct
    $bar5 = Get-Bar -pct $pct5 -width 8 -activeColor $C_DARK_BLUE
    $cVal5 = if ($pct5 -ge 85.0) { $C_ALERT } elseif ($pct5 -ge 65.0) { $C_WARN } else { $C_DARK_BLUE }
    $resetStr5 = ""
    if ($b5.UnixSeconds -gt 0) {
        $rStrs5 = Get-ResetTimeStrs $b5.UnixSeconds $false
        $resetStr5 = " ${C_MUTED}($($rStrs5.Abs) ${GLYPH_SEP} $($rStrs5.Rel))${RESET}"
    }
    $part5h = "${C_MUTED}5h:${RESET} ${bar5} ${cVal5}$([math]::Round($pct5, 1))%${RESET}${resetStr5}"
}

# Weekly Limit (7d Rate Limit / Quota)
$b7 = Get-QuotaBucket $payload "7d"
$part7d = ""
if ($null -ne $b7) {
    $pct7 = $b7.Pct
    $bar7 = Get-Bar -pct $pct7 -width 8 -activeColor $C_SLATE
    $cVal7 = if ($pct7 -ge 85.0) { $C_ALERT } elseif ($pct7 -ge 65.0) { $C_WARN } else { $C_SLATE }
    $resetStr7 = ""
    if ($b7.UnixSeconds -gt 0) {
        $rStrs7 = Get-ResetTimeStrs $b7.UnixSeconds $true
        $resetStr7 = " ${C_MUTED}($($rStrs7.Abs) ${GLYPH_SEP} $($rStrs7.Rel))${RESET}"
    }
    $part7d = "${C_MUTED}7d:${RESET} ${bar7} ${cVal7}$([math]::Round($pct7, 1))%${RESET}${resetStr7}"
}

$versionBadge = if ($payload.version) { "${C_DARK_BLUE}agy v$($payload.version)${RESET}" } else { "${C_DARK_BLUE}agy${RESET}" }

$line2Parts = @($ctxPart)
if ($part5h) { $line2Parts += $part5h }
if ($part7d) { $line2Parts += $part7d }
$line2Parts += $versionBadge
$line2 = ($line2Parts -join $C_SEP)

Write-Output $line1
Write-Output $line2
