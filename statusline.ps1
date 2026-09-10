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

# 6. System Clock
$clockPart = "${C_MUTED}$([DateTime]::Now.ToString('HH:mm'))${RESET}"

# 7. Badges
$badges = @()
if ($payload.autorun) { $badges += "${C_ALERT}${BOLD}[AUTO]${RESET}" }
if ($payload.vim -and $payload.vim.mode) { $badges += "${C_WARN}[VIM:$($payload.vim.mode)]${RESET}" }

# Assemble Line 1
$line1Parts = @($modelPart, $dirPart, $gitPart)
if ($sessionPart) { $line1Parts += $sessionPart }
if ($elapsedPart) { $line1Parts += $elapsedPart }
$line1Parts += $clockPart
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

$BAR_WIDTH = 10
$filledChars = [int][math]::Round(($usedPct / 100.0) * $BAR_WIDTH)
if ($filledChars -gt $BAR_WIDTH) { $filledChars = $BAR_WIDTH }
if ($filledChars -lt 0) { $filledChars = 0 }
$emptyChars = $BAR_WIDTH - $filledChars

$cBar = if ($usedPct -ge 85.0) { $C_ALERT } elseif ($usedPct -ge 65.0) { $C_WARN } else { $C_DARK_BLUE }
$barFilled = [string]$GLYPH_BAR * $filledChars
$barEmpty  = [string]$GLYPH_BAR * $emptyChars
$bar = "${cBar}${barFilled}${C_DARK}${barEmpty}${RESET}"

$pctDisplay = "${cBar}$([math]::Round($usedPct, 1))%${RESET}"
$fIn  = Format-Number $inputTokens
$fMax = Format-Number $contextSize
$fOut = Format-Number $outputTokens
$tokenDetails = "${C_MUTED}(In: ${C_DARK_BLUE}${fIn}${C_MUTED} / ${fMax} | Out: ${C_DARK_BLUE}${fOut}${C_MUTED})${RESET}"
$ctxPart = "${C_MUTED}ctx:${RESET} ${bar} ${pctDisplay} ${tokenDetails}"

# Weekly Limit (7d Rate Limit / Quota)
$weekPct = 0.0
$weekResetStr = ""
if ($payload.rate_limits -and $payload.rate_limits.seven_day) {
    if ($null -ne $payload.rate_limits.seven_day.used_percentage) {
        $weekPct = [double]$payload.rate_limits.seven_day.used_percentage
    }
    if ($payload.rate_limits.seven_day.resets_at) {
        $localTime = [DateTimeOffset]::FromUnixTimeSeconds([int64]$payload.rate_limits.seven_day.resets_at).ToLocalTime()
        $weekResetStr = " ${C_MUTED}($($localTime.ToString('ddd HH:mm')))${RESET}"
    }
} elseif ($payload.quota -and $payload.quota.seven_day) {
    if ($null -ne $payload.quota.seven_day.used_percentage) {
        $weekPct = [double]$payload.quota.seven_day.used_percentage
    }
} elseif ($null -ne $payload.weekly_limit) {
    $weekPct = [double]$payload.weekly_limit
}

$W_BAR = 8
$wFilled = [int][math]::Round(($weekPct / 100.0) * $W_BAR)
if ($wFilled -gt $W_BAR) { $wFilled = $W_BAR }
if ($wFilled -lt 0) { $wFilled = 0 }
$wEmpty = $W_BAR - $wFilled

$cWeek = if ($weekPct -ge 85.0) { $C_ALERT } elseif ($weekPct -ge 65.0) { $C_WARN } else { $C_SLATE }
$wBarFilled = [string]$GLYPH_BAR * $wFilled
$wBarEmpty  = [string]$GLYPH_BAR * $wEmpty
$wBar = "${cWeek}${wBarFilled}${C_DARK}${wBarEmpty}${RESET}"
$weekPart = "${C_MUTED}7d:${RESET} ${wBar} ${cWeek}$([math]::Round($weekPct, 1))%${RESET}${weekResetStr}"

$versionBadge = if ($payload.version) { "${C_DARK_BLUE}agy v$($payload.version)${RESET}" } else { "${C_DARK_BLUE}agy${RESET}" }

$line2Parts = @($ctxPart, $weekPart, $versionBadge)
$line2 = ($line2Parts -join $C_SEP)

Write-Output $line1
Write-Output $line2
