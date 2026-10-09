# Fail-open for the personal VPN: traffic that would go to "proxy" is sent
# through a balancer. When the observatory sees the VPS as dead, the balancer
# falls back to "direct"; when the VPS recovers, traffic returns to it.
# Idempotent: safe to apply more than once.
#
# Usage: jq -f xray-failopen.jq config.json

.observatory = {
    subjectSelector: ["proxy"],
    probeUrl: "https://www.gstatic.com/generate_204",
    probeInterval: "30s",
    enableConcurrency: true
  }

| .routing.balancers = [{
    tag: "auto",
    selector: ["proxy"],
    fallbackTag: "direct",
    strategy: {type: "leastPing"}
  }]

# Xray's own DNS queries: via the balancer too, so they survive a dead VPS
| .routing.rules |= map(
    if .inboundTag == ["dns-module"] then del(.outboundTag) | .balancerTag = "auto" else . end)

# Explicit catch-all at the end (replaces the implicit "first outbound = proxy")
| .routing.rules |= map(select((.balancerTag == "auto" and .network == "tcp,udp") | not))
| .routing.rules += [{type: "field", network: "tcp,udp", balancerTag: "auto"}]
