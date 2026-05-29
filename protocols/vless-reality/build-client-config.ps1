function Build-ClientConfig {
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter(Mandatory)][string]$PublicKey,
        [Parameter(Mandatory)][string]$ServerIP,
        [Parameter(Mandatory)][string]$ShortId,
        [string]$Sni         = "ads.x5.ru",
        [int]   $Port        = 443,
        [string]$Flow        = "xtls-rprx-vision",
        [string]$Fingerprint = "chrome",
        [int]   $SocksPort   = 10808,
        [int]   $HttpPort    = 10809
    )

    return [ordered]@{
        log = [ordered]@{ loglevel = "warning" }

        inbounds = @(
            [ordered]@{
                tag      = "socks"
                listen   = "127.0.0.1"
                port     = $SocksPort
                protocol = "socks"
                settings = [ordered]@{ auth = "noauth"; udp = $true }
            }
            [ordered]@{
                tag      = "http"
                listen   = "127.0.0.1"
                port     = $HttpPort
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
                            port    = $Port
                            users   = @(
                                [ordered]@{
                                    id         = $Uuid
                                    encryption = "none"
                                    flow       = $Flow
                                }
                            )
                        }
                    )
                }
                streamSettings = [ordered]@{
                    network  = "tcp"
                    security = "reality"
                    realitySettings = [ordered]@{
                        serverName  = $Sni
                        fingerprint = $Fingerprint
                        publicKey   = $PublicKey
                        shortId     = $ShortId
                    }
                }
            }
            [ordered]@{ tag = "direct"; protocol = "freedom" }
            [ordered]@{ tag = "block";  protocol = "blackhole" }
        )

        routing = [ordered]@{
            domainStrategy = "IPIfNonMatch"
            rules = @(
                [ordered]@{ type = "field"; outboundTag = "direct"; ip      = @("geoip:private") }
                [ordered]@{ type = "field"; outboundTag = "direct"; domain  = @("geosite:cn")    }
                [ordered]@{ type = "field"; outboundTag = "direct"; ip      = @("geoip:cn")      }
            )
        }
    } | ConvertTo-Json -Depth 20
}
