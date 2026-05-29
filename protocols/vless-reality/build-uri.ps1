function Build-VlessUri {
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter(Mandatory)][string]$PublicKey,
        [Parameter(Mandatory)][string]$ServerIP,
        [Parameter(Mandatory)][string]$ShortId,
        [string]$Sni    = "ads.x5.ru",
        [int]   $Port   = 443,
        [string]$Flow   = "xtls-rprx-vision",
        [string]$Remark = "vpn-deploy"
    )

    $params = "security=reality&sni=$Sni&fp=chrome&pbk=$PublicKey&sid=$ShortId&flow=$Flow&type=tcp"
    $remarkEncoded = [Uri]::EscapeDataString($Remark)

    return "vless://${Uuid}@${ServerIP}:${Port}?${params}#${remarkEncoded}"
}
