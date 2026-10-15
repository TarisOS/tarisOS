#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# DNS for Settings > Network, through NetworkManager:
#   dns.sh                          print the provider (Automatic, Cloudflare, Google or Custom) and servers
#   dns.sh set <provider> [servers] use it (asks for your password); Custom takes the servers
set -euo pipefail

conf=/etc/NetworkManager/conf.d/20-taris-dns.conf

servers_in() {
  [[ -f $1 ]] || return 0
  awk -F= '/^[[:space:]]*\[global-dns-domain-\*\]/ { d = 1; next } /^[[:space:]]*\[/ { d = 0 } d && /^[[:space:]]*servers[[:space:]]*=/ { sub(/^[^=]*=/, ""); print; exit }' "$1"
}

if (($# == 0)); then
  servers=$(servers_in "$conf")
  case "$servers" in
  "") provider=Automatic ;;
  *1.1.1.1* | *cloudflare*) provider=Cloudflare ;;
  *8.8.8.8* | *dns.google*) provider=Google ;;
  *) provider=Custom ;;
  esac
  printf '%s\t%s\n' "$provider" "$servers"
  exit 0
fi

[[ $1 == set ]] || { echo "Usage: dns.sh [set <Automatic|Cloudflare|Google|Custom> [servers]]" >&2; exit 1; }
provider="${2:-}"
case "$provider" in
Automatic) servers="" ;;
Cloudflare) servers="1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001" ;;
Google) servers="8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844" ;;
Custom) servers=$(printf '%s' "${3:-}" | tr ' \t;' ',,,' | tr -s ',' | sed 's/^,//; s/,$//') ;;
*) echo "Unknown provider: $provider" >&2; exit 1 ;;
esac
[[ $provider == Custom && -z $servers ]] && { echo "Custom needs at least one server" >&2; exit 1; }

((EUID == 0)) || exec pkexec "$(realpath "$0")" "$@"

if [[ -n $servers ]]; then
  install -d -m 0755 "${conf%/*}"
  printf '[global-dns]\n\n[global-dns-domain-*]\nservers=%s\n' "$servers" >"$conf"
else
  rm -f "$conf"
fi

# Per-connection DNS too, so DHCP-provided servers don't win over the chosen ones
ipv4="" ipv6=""
for s in ${servers//,/ }; do
  if [[ $s == *:* ]]; then ipv6+="${ipv6:+ }$s"; else ipv4+="${ipv4:+ }$s"; fi
done
auto=$([[ -n $servers ]] && echo yes || echo no)
while IFS=: read -r uuid type; do
  [[ $type == 802-11-wireless || $type == 802-3-ethernet ]] || continue
  nmcli connection modify "$uuid" ipv4.ignore-auto-dns "$auto" ipv4.dns "$ipv4" ipv6.ignore-auto-dns "$auto" ipv6.dns "$ipv6" >/dev/null || true
done < <(nmcli -t -f UUID,TYPE connection show)

nmcli general reload conf >/dev/null 2>&1 || systemctl reload NetworkManager.service || true
while IFS=: read -r device type state; do
  [[ $state == connected && ($type == wifi || $type == ethernet) ]] && nmcli device reapply "$device" >/dev/null 2>&1 || true
done < <(nmcli -t -f DEVICE,TYPE,STATE device status)
systemctl reload systemd-resolved.service 2>/dev/null || systemctl try-restart systemd-resolved.service 2>/dev/null || true
nmcli general reload dns-full >/dev/null 2>&1 || true
