function Build-ClientConfig {
    param(
        [Parameter(Mandatory)][object]$Keys,
        [Parameter(Mandatory)][string]$ServerIP
    )

    return [ordered]@{
        log = [ordered]@{ loglevel = "warning" }

        inbounds = @(
            [ordered]@{
                tag      = "socks"
                listen   = "127.0.0.1"
                port     = 10808
                protocol = "socks"
                settings = [ordered]@{ auth = "noauth"; udp = $true }
            }
            [ordered]@{
                tag      = "http"
                listen   = "127.0.0.1"
                port     = 10809
                protocol = "http"
                settings = [ordered]@{ allowTransparent = $false }
            }
        )

        outbounds = @(
            [ordered]@{
                tag      = "proxy"
                protocol = "vless"
                settings = [ordered]@{
                    vnext = @(
                        [ordered]@{
                            address = $ServerIP
                            port    = 443
                            users   = @(
                                [ordered]@{
                                    id         = $Keys.uuid
                                    encryption = "none"
                                    flow       = "xtls-rprx-vision"
                                }
                            )
                        }
                    )
                }
                streamSettings = [ordered]@{
                    network  = "tcp"
                    security = "reality"
                    realitySettings = [ordered]@{
                        serverName  = "ads.x5.ru"
                        fingerprint = "chrome"
                        publicKey   = $Keys.publicKey
                        shortId     = $Keys.shortId
                    }
                }
            }
            [ordered]@{ tag = "direct"; protocol = "freedom" }
            [ordered]@{ tag = "block";  protocol = "blackhole" }
        )

        routing = [ordered]@{
            domainStrategy = "IPIfNonMatch"
            rules = @(
                [ordered]@{ type = "field"; outboundTag = "direct"; ip     = @("geoip:private") }
                [ordered]@{ type = "field"; outboundTag = "direct"; domain = @("geosite:ru")    }
                [ordered]@{ type = "field"; outboundTag = "direct"; ip     = @("geoip:ru")      }
            )
        }
    } | ConvertTo-Json -Depth 20
}
