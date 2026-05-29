function Build-Uri {
    param(
        [Parameter(Mandatory)][object]$Keys,
        [Parameter(Mandatory)][string]$ServerIP
    )
    $params = "security=reality&sni=ads.x5.ru&fp=chrome&pbk=$($Keys.publicKey)&sid=$($Keys.shortId)&flow=xtls-rprx-vision&type=tcp"
    $remark = [Uri]::EscapeDataString("vpn-deploy")
    return "vless://$($Keys.uuid)@${ServerIP}:443?${params}#${remark}"
}
