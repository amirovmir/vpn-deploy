function Build-ClientConfig {
    param(
        [Parameter(Mandatory)][object]$Keys,
        [Parameter(Mandatory)][string]$ServerIP
    )

    return @"
server: $($Keys.domain):443
auth: $($Keys.password)

tls:
  sni: $($Keys.domain)
  insecure: false

socks5:
  listen: 127.0.0.1:10808

http:
  listen: 127.0.0.1:10809

acl:
  inline:
    - direct(geoip:private)
    - direct(geoip:ru)
    - proxy(all)
"@
}
