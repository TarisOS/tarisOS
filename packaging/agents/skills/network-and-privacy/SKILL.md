---
name: network-and-privacy
description: >
  Networking and privacy on this TarisOS Mac: Wi-Fi and Ethernet, DNS, VPNs, sending everything
  through Tor, random hardware addresses, KDE Connect, and the firewall (letting something in).
  Triggers: Wi-Fi, wifi, network, internet, Ethernet, DNS, VPN, WireGuard, OpenVPN, NordVPN, Tor,
  Tor Browser, bridges, MAC address, KDE Connect, firewall, open a port, nftables, SSH server,
  can't connect.
---

# Network and Privacy

On a TarisOS development machine (`/etc/taris/dev-machine`), the development rules
(`/usr/share/taris/agent-rules-dev.md`) take precedence over this skill wherever they disagree.

## Wi-Fi, Ethernet and DNS

- Settings > Network, or NetworkManager from a terminal: `nmcli device`, `nmcli device wifi list`,
  `nmcli device wifi connect <ssid> --ask`.
- **DNS:** Settings > Network (Automatic, Cloudflare, Google or custom servers).
- The Wi-Fi channels and power allowed follow the country of the timezone, set by itself.
- After sleep, Wi-Fi that comes back wedged on some Macs is reloaded by itself. Wi-Fi that still
  fails: `journalctl -b -u NetworkManager`, `nmcli device`.

## VPNs

- **NordVPN:** installed on first use (`/usr/lib/taris/install-on-demand nordvpn`), then switched
  on in Settings > Network.
- **WireGuard:** NetworkManager has it built in:
  `nmcli connection import type wireguard file <file>.conf`.
- **OpenVPN:** `sudo pacman -Syu --needed networkmanager-openvpn`, then
  `nmcli connection import type openvpn file <file>.ovpn`.

## Tor

Everything can go through Tor: the taskbar's Tor icon, Settings > Network > Tor, or
`/usr/lib/taris/tor`:

```bash
/usr/lib/taris/tor on|off|status
/usr/lib/taris/tor newnym                          # new circuits (New identity)
/usr/lib/taris/tor bridges none|obfs4|snowflake|meek
/usr/lib/taris/tor isolate on|off                  # circuit isolation
/usr/lib/taris/tor mac on|off                      # a random hardware address on every connection
```

While it's on, the time is set through Tor too. Tor Browser (in the launcher) uses that Tor instead
of its own. Changing Tor's settings asks for the password, except switching it on and New identity.

## KDE Connect

KDE Connect (phones and other computers on the local network) is set up and allowed through the
firewall on local networks. Its window: `taris-qs -c taris ipc call kdeconnect open`.

## The firewall

Nothing gets in unless it answers something this Mac started; everything may go out. TarisOS's
rules are `/usr/share/taris/firewall.nft` (don't edit). Letting something in is the
administrator's own rule, in a file of its own in `/etc/taris/firewall.d/`, ending in `.nft`, with
lines of the input chain:

```bash
# e.g. a web server on port 8000, from the local network only
echo 'ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 8000 accept' |
  sudo tee /etc/taris/firewall.d/web.nft
sudo nft -c -f /usr/share/taris/firewall-user.nft   # check: no output means it's correct
sudo systemctl reload taris-firewall                # apply
sudo nft list table inet taris_firewall             # see what's in place
```

Open as little as possible: one port, from the local network when that's enough, and only with the
user's yes after saying what it exposes. A mistake in these files leaves them out and TarisOS's
rules in place. Removing the file and reloading closes it again.

**An SSH server** isn't installed. If the user wants one: `sudo pacman -Syu --needed openssh`,
`sudo systemctl enable --now sshd`, and a firewall rule for port 22 as above. Say first that it lets
anyone who reaches the Mac try to log in, and suggest keys instead of passwords.
