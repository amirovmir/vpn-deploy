function Build-Uri {
    param(
        [Parameter(Mandatory)][object]$Keys,
        [Parameter(Mandatory)][string]$ServerIP
    )
    $remark = [Uri]::EscapeDataString("vpn-deploy-h2")
    return "hysteria2://$($Keys.password)@$($Keys.domain):443?sni=$($Keys.domain)#${remark}"
}
