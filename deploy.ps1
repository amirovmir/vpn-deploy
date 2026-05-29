param(
    [string]$IP,
    [string]$User,
    [string]$Password,
    [int]$Port = 22,
    [string]$Protocol = "vless-reality",
    [string]$Domain,
    [string]$CloudflareToken
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

# ── GUI input dialog ────────────────────────────────────────────────────────────

$needsH2  = ($Protocol -eq "hysteria2")
$showGui  = (-not $IP -or -not $User -or -not $Password -or
             ($needsH2 -and (-not $Domain -or -not $CloudflareToken)))

if ($showGui) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "VPN Deploy"
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    function Add-Row([System.Windows.Forms.Form]$f, [string]$label, [int]$y, [bool]$masked = $false) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text     = $label
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $lbl.Size     = New-Object System.Drawing.Size(100, 20)
        $f.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point(125, ($y - 2))
        $txt.Size     = New-Object System.Drawing.Size(205, 22)
        if ($masked) { $txt.UseSystemPasswordChar = $true }
        $f.Controls.Add($txt)
        return $txt
    }

    $txtIP   = Add-Row $form "Server IP:"   20
    $txtUser = Add-Row $form "Username:"    60
    $txtPass = Add-Row $form "Password:"   100 $true
    $txtPort = Add-Row $form "SSH Port:"   140

    if ($IP)       { $txtIP.Text   = $IP      }
    if ($User)     { $txtUser.Text = $User     }
    if ($Password) { $txtPass.Text = $Password }
    $txtPort.Text = if ($Port -ne 0) { "$Port" } else { "22" }

    $txtDomain  = $null
    $txtCFToken = $null
    $btnY = 185

    if ($needsH2) {
        $txtDomain  = Add-Row $form "Domain:"     180
        $txtCFToken = Add-Row $form "CF Token:"   220 $true
        if ($Domain)          { $txtDomain.Text  = $Domain          }
        if ($CloudflareToken) { $txtCFToken.Text = $CloudflareToken }
        $btnY = 265
    }

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text         = "Deploy"
    $btnOK.Location     = New-Object System.Drawing.Point(110, $btnY)
    $btnOK.Size         = New-Object System.Drawing.Size(100, 30)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton  = $btnOK
    $form.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text         = "Cancel"
    $btnCancel.Location     = New-Object System.Drawing.Point(225, $btnY)
    $btnCancel.Size         = New-Object System.Drawing.Size(100, 30)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton      = $btnCancel
    $form.Controls.Add($btnCancel)

    $form.ClientSize = New-Object System.Drawing.Size(355, ($btnY + 50))

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
    if ($txtDomain)  { $Domain          = $txtDomain.Text.Trim() }
    if ($txtCFToken) { $CloudflareToken = $txtCFToken.Text.Trim() }

    $form.Dispose()

    if (-not $IP -or -not $User -or -not $Password) {
        Write-Host "ERROR: IP, Username and Password are required." -ForegroundColor Red; exit 1
    }
    if ($needsH2 -and (-not $Domain -or -not $CloudflareToken)) {
        Write-Host "ERROR: Domain and Cloudflare Token are required for hysteria2." -ForegroundColor Red; exit 1
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

function Step([string]$Num, [string]$Title) { Write-Host ""; Write-Host "[$Num] $Title" -ForegroundColor Cyan }
function OK([string]$Msg)   { Write-Host "    OK: $Msg"   -ForegroundColor Green  }
function INFO([string]$Msg) { Write-Host "    $Msg"        -ForegroundColor Gray   }
function WARN([string]$Msg) { Write-Host "    WARN: $Msg" -ForegroundColor Yellow }
function FAIL([string]$Msg) { Write-Host ""; Write-Host "    ERROR: $Msg" -ForegroundColor Red; exit 1 }

# ── [1/8] Validate prerequisites ───────────────────────────────────────────────

Step "1/8" "Validate prerequisites"

if (-not (Test-Path $PLINK)) { FAIL "plink.exe not found: $PLINK — install PuTTY from https://www.putty.org" }
if (-not (Test-Path $PSCP))  { FAIL "pscp.exe not found: $PSCP — install PuTTY from https://www.putty.org"  }
OK "plink.exe / pscp.exe found"

$ProtocolDir = Join-Path $ScriptDir "protocols\$Protocol"
if (-not (Test-Path $ProtocolDir)) { FAIL "Protocol '$Protocol' not found: $ProtocolDir" }

. "$ProtocolDir\protocol.ps1"
OK "Protocol: $Protocol  (container: $ContainerName)"

# ── [2/8] Test SSH connection ──────────────────────────────────────────────────

Step "2/8" "Test SSH connection"
INFO "Connecting to ${User}@${IP}:${Port} ..."
$connTest = SSH "echo CONN_OK"
if ($connTest -notmatch "CONN_OK") { FAIL "SSH failed: $connTest" }
OK "Connected"

# ── [3/8] Install Docker (idempotent) ─────────────────────────────────────────

Step "3/8" "Install Docker (idempotent)"
SCP (Join-Path $ScriptDir "scripts\setup-docker.sh") "/tmp/vpn-setup-docker.sh"
$dockerOut = SSH "chmod +x /tmp/vpn-setup-docker.sh && bash /tmp/vpn-setup-docker.sh"
$dockerOut -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { INFO $_ }
if ((SSH "docker --version 2>/dev/null || echo MISSING") -match "MISSING") { FAIL "Docker installation failed" }
OK "Docker ready"

# ── [4/8] Create remote directories ───────────────────────────────────────────

Step "4/8" "Create remote directories"
SSH "mkdir -p /opt/vpn && mkdir -p $ConfigDir" | Out-Null
OK "$ConfigDir ready"

# ── [5/8] Upload protocol files ───────────────────────────────────────────────

Step "5/8" "Upload protocol files"
@(
    @{ L = "$ProtocolDir\generate-keys.sh";   R = "/opt/vpn/generate-keys.sh"   }
    @{ L = "$ProtocolDir\docker-compose.yml"; R = "/opt/vpn/docker-compose.yml" }
) | ForEach-Object { SCP $_.L $_.R; INFO "Uploaded: $($_.R)" }
OK "All files uploaded"

# ── [6/8] Generate keys on remote ─────────────────────────────────────────────

Step "6/8" "Generate keys on remote server"

$envPrefix = "SERVER_IP='$IP'"
if ($Domain)          { $envPrefix += " DOMAIN='$Domain'"           }
if ($CloudflareToken) { $envPrefix += " CF_TOKEN='$CloudflareToken'" }

SSH "chmod +x /opt/vpn/generate-keys.sh" | Out-Null
$keysOut = SSH "$envPrefix bash /opt/vpn/generate-keys.sh"

$jsonLine = ($keysOut -split "`n" | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
if (-not $jsonLine) { FAIL "Key generation failed. Output:`n$keysOut" }

try   { $keys = $jsonLine | ConvertFrom-Json }
catch { FAIL "Failed to parse key JSON: $jsonLine" }

$keys.PSObject.Properties | Where-Object { $_.Name -ne "privateKey" } |
    ForEach-Object { OK "$($_.Name): $($_.Value)" }

# ── [7/8] Render config and start container ────────────────────────────────────

Step "7/8" "Write config and start container"

$configContent = Get-Content "$ProtocolDir\$ConfigTemplate" -Raw -Encoding UTF8
$keys.PSObject.Properties | ForEach-Object {
    $configContent = $configContent -replace "@@$($_.Name.ToUpper())@@", $_.Value
}

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configContent))
SSH "echo '$b64' | base64 -d > $ConfigRemote" | Out-Null
INFO "Config written to $ConfigRemote"

if ($StrayProcess) { SSH "pkill -x '$StrayProcess' 2>/dev/null; sleep 1; true" | Out-Null }

$composeOut = SSH "cd /opt/vpn && docker compose up -d --force-recreate 2>&1"
$composeOut -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { INFO $_ }

Start-Sleep -Seconds 2
$status = SSH "docker ps --filter name=$ContainerName --format '{{.Status}}' 2>/dev/null"
if ($status -match "Up") {
    OK "Container: $($status.Trim())"
} else {
    WARN "Container may not be running. Logs:"
    SSH "docker logs $ContainerName --tail 20 2>&1" -split "`n" | ForEach-Object { INFO $_ }
}

# ── [8/8] Connection details ───────────────────────────────────────────────────

Step "8/8" "Connection details"

. "$ProtocolDir\build-uri.ps1"
. "$ProtocolDir\build-client-config.ps1"

$uri           = Build-Uri -Keys $keys -ServerIP $IP
$clientContent = Build-ClientConfig -Keys $keys -ServerIP $IP
$configFile    = Join-Path $ScriptDir "client-$IP-$Protocol.$ClientExt"
$clientContent | Set-Content $configFile -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  VPN DEPLOY COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "  Protocol : $Protocol" -ForegroundColor White
Write-Host "  Server   : $IP" -ForegroundColor White
Write-Host ""
Write-Host "  URI:" -ForegroundColor Yellow
Write-Host "  $uri" -ForegroundColor White
Write-Host ""
Write-Host "  Client config: $configFile" -ForegroundColor Yellow
Write-Host "  (v2rayN / Hiddify: Servers -> Import custom config from file)" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
try { Read-Host "  Press Enter to close" } catch { }
