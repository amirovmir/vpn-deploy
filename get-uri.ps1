param(
    [string]$IP,
    [string]$User,
    [string]$Password,
    [int]$Port = 22,
    [string]$Protocol = "vless-reality"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

# ── GUI input dialog (если параметры не переданы) ──────────────────────────────

if (-not $IP -or -not $User -or -not $Password) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "VPN — Get URI"
    $form.Size            = New-Object System.Drawing.Size(360, 220)
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

    if ($IP)       { $txtIP.Text   = $IP      }
    if ($User)     { $txtUser.Text = $User     }
    if ($Password) { $txtPass.Text = $Password }
    $txtPort.Text = if ($Port -ne 0) { "$Port" } else { "22" }

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text         = "Get URI"
    $btnOK.Location     = New-Object System.Drawing.Point(110, 150)
    $btnOK.Size         = New-Object System.Drawing.Size(100, 30)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton  = $btnOK
    $form.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text         = "Cancel"
    $btnCancel.Location     = New-Object System.Drawing.Point(225, 150)
    $btnCancel.Size         = New-Object System.Drawing.Size(100, 30)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton      = $btnCancel
    $form.Controls.Add($btnCancel)

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }

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

function SSH([string]$Cmd) {
    $result = & $PLINK -ssh "${User}@${IP}" -P $Port -pw $Password -batch -no-antispoof $Cmd 2>&1
    return $result -join "`n"
}

# ── Read config from server ────────────────────────────────────────────────────

Write-Host ""
Write-Host "Connecting to ${User}@${IP}..." -ForegroundColor Cyan

$connTest = SSH "echo CONN_OK"
if ($connTest -notmatch "CONN_OK") {
    Write-Host "ERROR: SSH connection failed." -ForegroundColor Red; exit 1
}

$configRaw = SSH "cat /opt/vpn/xray/config.json 2>/dev/null || echo NOT_FOUND"
if ($configRaw -match "NOT_FOUND") {
    Write-Host "ERROR: Config not found at /opt/vpn/xray/config.json" -ForegroundColor Red
    Write-Host "       Run deploy.ps1 first." -ForegroundColor Yellow
    exit 1
}

# Extract fields via JSON parse on the server (avoids PowerShell multiline SSH issues)
$uuid       = SSH "cat /opt/vpn/xray/config.json | docker run --rm -i stedolan/jq -r '.inbounds[0].settings.clients[0].id' 2>/dev/null"

# Fallback: parse with python if jq image not available
if (-not $uuid -or $uuid -match "Error\|Unable\|Cannot") {
    $uuid    = SSH "python3 -c `"import json,sys; c=json.load(open('/opt/vpn/xray/config.json')); print(c['inbounds'][0]['settings']['clients'][0]['id'])`" 2>/dev/null"
    $privKey = SSH "python3 -c `"import json,sys; c=json.load(open('/opt/vpn/xray/config.json')); print(c['inbounds'][0]['streamSettings']['realitySettings']['privateKey'])`" 2>/dev/null"
    $shortId = SSH "python3 -c `"import json,sys; c=json.load(open('/opt/vpn/xray/config.json')); print(c['inbounds'][0]['streamSettings']['realitySettings']['shortIds'][0])`" 2>/dev/null"
} else {
    $privKey = SSH "cat /opt/vpn/xray/config.json | docker run --rm -i stedolan/jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' 2>/dev/null"
    $shortId = SSH "cat /opt/vpn/xray/config.json | docker run --rm -i stedolan/jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' 2>/dev/null"
}

$uuid    = $uuid.Trim()
$privKey = $privKey.Trim()
$shortId = $shortId.Trim()

if (-not $uuid -or -not $privKey -or -not $shortId) {
    Write-Host "ERROR: Could not parse config. Raw content:" -ForegroundColor Red
    Write-Host $configRaw
    exit 1
}

# Derive public key from private key using xray on the server
$keyOut    = SSH "docker run --rm teddysun/xray xray x25519 -i '$privKey' 2>/dev/null"
$publicKey = ($keyOut -split "`n" | Where-Object { $_ -match "Public key:" } | Select-Object -First 1) -replace ".*Public key:\s*", ""
$publicKey = $publicKey.Trim()

if (-not $publicKey) {
    Write-Host "ERROR: Could not derive public key." -ForegroundColor Red; exit 1
}

# ── Build and print URI ────────────────────────────────────────────────────────

$ProtocolDir = Join-Path $ScriptDir "protocols\$Protocol"
. "$ProtocolDir\build-uri.ps1"
. "$ProtocolDir\build-client-config.ps1"

$uri        = Build-VlessUri -Uuid $uuid -PublicKey $publicKey -ServerIP $IP -ShortId $shortId
$clientJson = Build-ClientConfig -Uuid $uuid -PublicKey $publicKey -ServerIP $IP -ShortId $shortId

$configFile = Join-Path $ScriptDir "client-$IP.json"
$clientJson | Set-Content $configFile -Encoding UTF8

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  VLESS URI" -ForegroundColor Green
Write-Host ""
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
