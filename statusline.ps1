param(
    [Parameter(ValueFromPipeline=$true)]
    [string]$InputJson
)

if (-not $InputJson) {
    if ($args.Count -gt 0) { $InputJson = $args[0] } else { exit }
}

try { $data = $InputJson | ConvertFrom-Json } catch { exit }

$ESC = [char]27
$Reset = "$ESC[0m"
$Bold = "$ESC[1m"

$White = "$ESC[38;2;220;225;230m"
$Frost = "$ESC[38;2;143;188;187m"
$Slate = "$ESC[38;2;110;125;140m"
$Dark = "$ESC[38;2;76;86;106m"

$Sep = " ${Dark}?${Reset} "

$output = "${White}${Bold}$($data.agent)$Reset$Sep${Slate}$($data.status)$Reset"
Write-Host "$output" -NoNewline
