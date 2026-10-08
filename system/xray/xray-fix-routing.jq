# Rewrites dns + routing of the Xray client config and binds the "direct"
# outbound to the physical NIC. Inbounds and the proxy outbound (with secrets)
# are left untouched.
#
# Usage: jq --arg iface enp12s0 -f xray-fix-routing.jq config.json

# Direct traffic must leave via the NIC, not via the 0.0.0.0/1 + 128.0.0.0/1
# routes into tun0, otherwise it loops back into tun2socks -> xray.
(.outbounds[] | select(.tag == "direct")).streamSettings.sockopt.interface = $iface

# Xray's own resolver (used by IPIfNonMatch): DoH to Cloudflare via the proxy.
| .dns = {
    tag: "dns-module",
    queryStrategy: "UseIPv4",
    servers: ["https://1.1.1.1/dns-query"]
  }

# First matching rule wins; anything unmatched goes to the first outbound (proxy).
| .routing = {
    domainStrategy: "IPIfNonMatch",
    rules: [
      # Block QUIC so browsers fall back to TCP (sniffable, stable through the tunnel)
      {type: "field", network: "udp", port: "443", outboundTag: "block"},
      # Xray's own DNS queries always go through the proxy
      {type: "field", inboundTag: ["dns-module"], outboundTag: "proxy"},
      # LAN and private ranges
      {type: "field", ip: ["geoip:private"], outboundTag: "direct"},
      {type: "field", domain: ["geosite:private"], outboundTag: "direct"},
      # Russian zones by suffix (.ru, .su, .рф)
      {type: "field", domain: ["domain:ru", "domain:su", "domain:xn--p1ai"], outboundTag: "direct"},
      # Russian IPs (domains are resolved first thanks to IPIfNonMatch)
      {type: "field", ip: ["geoip:ru"], outboundTag: "direct"}
    ]
  }
