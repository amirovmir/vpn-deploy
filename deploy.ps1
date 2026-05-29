param(
    [string]$IP,
    [string]$User,
    [string]$Password,
    [int]$Port = 22,
    [string]$Protocol = "vless-reality"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

# ── GUI input dialog ────────────────────────────────────────────────────────────

if (-not $IP -or -not $User -or -not $Password) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "VPN Deploy"
    $form.Size            = New-Object System.Drawing.Size(360, 260)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    function Add-Row([System.Windows.Forms.Form]$f, [string]$label, [int]$y, [bool]$masked = $false) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text     = $label
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $lbl.Size     = New-Object System.Drawing.Size(80, 20)
        $f.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point(110, ($y - 2))
        $txt.Size     = New-Object System.Drawing.Size(220, 22)
        if ($masked) { $txt.UseSystemPasswordChar = $true }
        $f.Controls.Add($txt)
        return $txt
    }

    $txtIP   = Add-Row $form "Server IP:"  20
    $txtUser = Add-Row $form "Username:"   60
    $txtPass = Add-Row $form "Password:"  100 $true
    $txtPort = Add-Row $form "SSH Port:"  140

    # Pre-fill from params or defaults
    if ($IP)       { $txtIP.Text   = $IP       }
    if ($User)     { $txtUser.Text = $User      }
    if ($Password) { $txtPass.Text = $Password  }
    $txtPort.Text = if ($Port -ne 0) { "$Port" } else { "22" }

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text     = "Deploy"
    $btnOK.Location = New-Object System.Drawing.Point(110, 185)
    $btnOK.Size     = New-Object System.Drawing.Size(100, 30)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton  = $btnOK
    $form.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text     = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(225, 185)
    $btnCancel.Size     = New-Object System.Drawing.Size(100, 30)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton      = $btnCancel
    $form.Controls.Add($btnCancel)

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }

    $IP       = $txtIP.Text.Trim()
    $User     = $txtUser.Text.Trim()
    $Password = $txtPass.Text
    $portVal  = $txtPort.Text.Trim()
    if ($portVal -match '^\d+$') { $Port = [int]$portVal }

    $form.Dispose()

    if (-not $IP -or -not $User -or -not $Password) {
        Write-Host "ERROR: IP, Username and Password are required." -ForegroundColor Red
        exit 1
    }
}

# ── helpers ────────────────────────────────────────────────────────────────────

$PLINK = "C:\Program Files\PuTTY\plink.exe"
$PSCP  = "C:\Program Files\PuTTY\pscp.exe"

function SSH([string]$Cmd) {
    $result = & $PLINK -ssh "${User}@${IP}" -P $Port -pw $Password -batch -no-antispoof $Cmd 2>&1
    return $result -join "`n"
}

function SCP([string]$Local, [string]$Remote) {
    & $PSCP -pw $Password -P $Port -q $Local "${User}@${IP}:${Remote}" 2>&1 | Out-Null
}

function Step([string]$Num, [string]$Title) {
    Write-Host ""
    Write-Host "[$Num] $Title" -ForegroundColor Cyan
}

function OK([string]$Msg)   { Write-Host "    OK: $Msg"      -ForegroundColor Green  }
function INFO([string]$Msg) { Write-Host "    $Msg"           -ForegroundColor Gray   }
function WARN([string]$Msg) { Write-Host "    WARN: $Msg"    -ForegroundColor Yellow }
function FAIL([string]$Msg) {
    Write-Host ""
    Write-Host "    ERROR: $Msg" -ForegroundColor Red
    exit 1
}

# ── [1/8] Validate prerequisites ───────────────────────────────────────────────

Step "1/8" "Validate prerequisites"

if (-not (Test-Path $PLINK)) { FAIL "plink.exe not found at: $PLINK`n    Install PuTTY from https://www.putty.org" }
if (-not (Test-Path $PSCP))  { FAIL "pscp.exe not found at: $PSCP`n    Install PuTTY from https://www.putty.org"  }
OK "plink.exe / pscp.exe found"

$ProtocolDir = Join-Path $ScriptDir "protocols\$Protocol"
if (-not (Test-Path $ProtocolDir)) {
    FAIL "Protocol '$Protocol' not found. Expected directory: $ProtocolDir"
}
OK "Protocol: $Protocol"

# ── [2/8] Test SSH connection ──────────────────────────────────────────────────

Step "2/8" "Test SSH connection"
INFO "Connecting to ${User}@${IP}:${Port} ..."

$connTest = SSH "echo CONN_OK"
if ($connTest -notmatch "CONN_OK") {
    FAIL "SSH connection failed. Server response:`n    $connTest"
}
OK "Connected"

# ── [3/8] Install Docker (idempotent) ─────────────────────────────────────────

Step "3/8" "Install Docker (idempotent)"

$setupScript = Join-Path $ScriptDir "scripts\setup-docker.sh"
SCP $setupScript "/tmp/vpn-setup-docker.sh"
$dockerOut = SSH "chmod +x /tmp/vpn-setup-docker.sh && bash /tmp/vpn-setup-docker.sh"
$dockerOut -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { INFO $_ }

$dockerCheck = SSH "docker --version 2>/dev/null || echo MISSING"
if ($dockerCheck -match "MISSING") { FAIL "Docker installation failed" }
OK "Docker ready"

# ── [4/8] Create remote directories ───────────────────────────────────────────

Step "4/8" "Create remote directories"
SSH "mkdir -p /opt/vpn/xray" | Out-Null
OK "/opt/vpn/xray created"

# ── [5/8] Upload protocol files ───────────────────────────────────────────────

Step "5/8" "Upload protocol files"

$files = @(
    @{ Local = "$ProtocolDir\generate-keys.sh";     Remote = "/opt/vpn/generate-keys.sh"     }
    @{ Local = "$ProtocolDir\config.template.json"; Remote = "/opt/vpn/config.template.json" }
    @{ Local = "$ProtocolDir\docker-compose.yml";   Remote = "/opt/vpn/docker-compose.yml"   }
)

foreach ($f in $files) {
    SCP $f.Local $f.Remote
    INFO "Uploaded: $($f.Remote)"
}
OK "All files uploaded"

# ── [6/8] Generate keys on remote ─────────────────────────────────────────────

Step "6/8" "Generate keys on remote server"
INFO "Pulling teddysun/xray and generating x25519 keypair + UUID..."

SSH "chmod +x /opt/vpn/generate-keys.sh" | Out-Null
$keysJson = SSH "bash /opt/vpn/generate-keys.sh"

# Extract the JSON line (last non-empty line, handles any docker pull output)
$jsonLine = ($keysJson -split "`n" | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
if (-not $jsonLine) {
    FAIL "Key generation failed. Output:`n$keysJson"
}

try {
    $keys = $jsonLine | ConvertFrom-Json
} catch {
    FAIL "Failed to parse key JSON: $jsonLine"
}

$uuid       = $keys.uuid
$privateKey = $keys.privateKey
$publicKey  = $keys.publicKey
$shortId    = $keys.shortId

if (-not $uuid -or -not $privateKey -or -not $publicKey -or -not $shortId) {
    FAIL "Incomplete keys received: $jsonLine"
}

OK "UUID:       $uuid"
OK "Public key: $publicKey"
OK "Short ID:   $shortId"

# Save keys locally for offline URI/config regeneration
$keysFile = Join-Path $ScriptDir "keys-$IP.json"
[ordered]@{ uuid = $uuid; publicKey = $publicKey; shortId = $shortId; ip = $IP } `
    | ConvertTo-Json | Set-Content $keysFile -Encoding UTF8

# ── [7/8] Render config and start container ────────────────────────────────────

Step "7/8" "Write config and start container"

$templatePath = "$ProtocolDir\config.template.json"
$configJson = (Get-Content $templatePath -Raw -Encoding UTF8) `
    -replace '@@UUID@@',        $uuid       `
    -replace '@@PRIVATE_KEY@@', $privateKey `
    -replace '@@SHORT_ID@@',    $shortId

# Transfer rendered config via base64 to avoid shell-quoting issues
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configJson))
SSH "echo '$b64' | base64 -d > /opt/vpn/xray/config.json" | Out-Null
INFO "Config written to /opt/vpn/xray/config.json"

$composeOut = SSH "cd /opt/vpn && docker compose up -d --force-recreate 2>&1"
$composeOut -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { INFO $_ }

# Verify container is running
Start-Sleep -Seconds 2
$containerStatus = SSH "docker ps --filter name=xray-vpn --format '{{.Status}}' 2>/dev/null"
if ($containerStatus -match "Up") {
    OK "Container: $($containerStatus.Trim())"
} else {
    WARN "Container status unclear. Checking logs..."
    $logs = SSH "docker logs xray-vpn --tail 20 2>&1"
    $logs -split "`n" | ForEach-Object { INFO $_ }
}

# Verify port 443
$portCheck = SSH "ss -tlnp 2>/dev/null | grep ':443 ' | head -1"
if ($portCheck -match "443") {
    OK "Port 443: LISTENING"
} else {
    WARN "Port 443 not detected yet (container may still be starting)"
}

# ── [8/8] Print VLESS URI ──────────────────────────────────────────────────────

Step "8/8" "Connection details"

. "$ProtocolDir\build-uri.ps1"
. "$ProtocolDir\build-client-config.ps1"

$uri        = Build-VlessUri -Uuid $uuid -PublicKey $publicKey -ServerIP $IP -ShortId $shortId
$clientJson = Build-ClientConfig -Uuid $uuid -PublicKey $publicKey -ServerIP $IP -ShortId $shortId

$configFile = Join-Path $ScriptDir "client-$IP.json"
$clientJson | Set-Content $configFile -Encoding UTF8

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  VPN DEPLOY COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "  Protocol : VLESS + Reality" -ForegroundColor White
Write-Host "  Server   : $IP`:443" -ForegroundColor White
Write-Host "  SNI      : ads.x5.ru" -ForegroundColor White
Write-Host ""
Write-Host "  VLESS URI:" -ForegroundColor Yellow
Write-Host "  $uri" -ForegroundColor White
Write-Host ""
Write-Host "  Client JSON: $configFile" -ForegroundColor Yellow
Write-Host "  (v2rayN: Servers -> Import custom config from file)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Import into: v2rayN (Win) · Shadowrocket (iOS)" -ForegroundColor Gray
Write-Host "               Hiddify · NekoBox (Android)" -ForegroundColor Gray
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Read-Host "  Press Enter to close"
