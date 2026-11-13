# network

Puppet module that configures Linux networking from Hiera: interfaces, bonds, VLANs,
bridges, routes, policy routing and NIC tuning.

| OS | Backend | Writes |
|---|---|---|
| RHEL / Rocky / Alma / Oracle 9, 10 | `keyfile` | `/etc/NetworkManager/system-connections/` |
| RHEL / CentOS / Rocky / Alma / Oracle 7, 8 | `ifcfg` | `/etc/sysconfig/network-scripts/` |
| Ubuntu 22.04, 24.04 | `netplan` | `/etc/netplan/90-network.yaml` |
| Debian 11, 12 | `ifupdown` | `/etc/network/interfaces.d/` |
| SLES 15 | `wicked` | `/etc/sysconfig/network/` |

## Installation

```ruby
# Puppetfile
mod 'puppetlabs/stdlib', '9.6.0'
mod 'puppetlabs/concat', '9.0.2'
mod 'network', :git => 'https://github.com/awijesundara/rhel_networking.git', :tag => 'v1.0.2'
```

Puppet 7 or 8. Add `include network` to the node and describe its interfaces in Hiera.

## How changes are applied

- Puppet writes the files and reloads them. **Live links are not touched**; changes take
  effect at the next activation, NetworkManager restart or reboot.
- `reapply: true` applies a change at once. The link drops briefly: use a maintenance window.
- Invalid data fails the run before any file is written.

## Examples

### Two uplinks with policy routing

`eth1` holds the default route. Traffic from `eth0`'s network leaves via `eth0`.

```yaml
network::routing_tables:
  1000: mgmt
network::sysctl:
  net.ipv4.conf.all.rp_filter: 2          # required with one table per uplink

network::interfaces:
  eth0:
    ipv4_address: '%{::ip_main}/23'
    ipv4_gateway: '10.68.184.1'
    ipv4_never_default: true
    routes:
      - { destination: '10.67.180.0/24', gateway: '10.68.184.1', description: 'mgmt infra' }
      - { destination: '10.68.184.0/23', table: mgmt }
      - { destination: '0.0.0.0/0', gateway: '10.68.184.1', table: mgmt }
    routing_rules:
      - { priority: 1000, from: '10.68.184.0/23', table: mgmt }
  eth1:
    ipv4_address: '%{::ip_internal}/23'
    ipv4_gateway: '10.68.172.1'
```

### LACP bond with a VLAN

```yaml
network::bonds:
  bond0:
    slaves: [ens1f0, ens1f1]
    ipv4_address: '10.0.0.10/24'
    ipv4_gateway: '10.0.0.1'
    mtu: 9000
    bond_mode: '802.3ad'
    bond_lacp_rate: fast
    bond_xmit_hash_policy: 'layer3+4'

network::connections:
  bond0.200:
    type: vlan
    vlan_id: 200
    vlan_parent: bond0
    ipv4_addresses: ['192.0.2.10/24']
```

### Active-backup bond (one fixed path)

Traffic always uses `ens2f0` while it is up, so latency does not depend on hashing.

```yaml
network::bonds:
  bond1:
    slaves: [ens2f0, ens3f0]                # one port on each NIC
    ipv4_address: '10.1.0.10/24'
    ipv4_never_default: true
    bond_mode: active-backup
    bond_miimon: 100
    bond_primary: ens2f0
    bond_primary_reselect: 0                # return to the primary as soon as it is back
```

### Solarflare / low-latency NIC

Larger rings, no interrupt coalescing, no receive aggregation. Applied when the connection
activates; RHEL 7 applies only the `feature-*` settings. Onload is not managed by this module.

```yaml
network::interfaces:
  ens1f0np0:
    ipv4_address: '10.20.0.10/24'
    ipv4_never_default: true
    ipv6_method: disabled
    mtu: 1500
    ethtool:
      ring-rx: 4096
      ring-tx: 4096
      coalesce-adaptive-rx: 0
      coalesce-rx-usecs: 0
      coalesce-tx-usecs: 0
      feature-gro: false
      feature-lro: false
    routes:
      - { destination: '224.0.0.0/4', description: 'market data multicast' }

network::sysctl:
  net.core.busy_poll: 50
  net.core.busy_read: 50
  net.ipv4.conf.ens1f0np0.rp_filter: 0      # accept multicast from any source
```

### PTP interface

A dedicated, static interface for PTP traffic. `ptp4l` and `phc2sys` are configured
outside this module (e.g. a linuxptp module).

```yaml
network::interfaces:
  ens4f0:
    ipv4_address: '10.30.0.10/24'
    ipv4_never_default: true
    ipv6_method: disabled
    ethtool:
      coalesce-adaptive-rx: 0
      coalesce-rx-usecs: 0
    routes:
      - { destination: '224.0.1.129/32', description: 'PTP primary multicast' }
      - { destination: '224.0.0.107/32', description: 'PTP peer delay multicast' }
```

More in [examples/](examples/).

## Reference

**`network::interfaces` and `network::bonds`**

| Parameter | Default | |
|---|---|---|
| `ipv4_address` | – | CIDR, or a list |
| `ipv4_method` | `manual` with an address, else `auto` | `manual`, `auto`, `disabled` |
| `ipv4_gateway` | – | |
| `ipv4_never_default` | `false` | Keep the gateway for routes, add no default route |
| `ipv4_dns` | `[]` | |
| `ipv4_route_metric` | – | |
| `mtu` | – | |
| `routes`, `routing_rules` | `[]` | See below |
| `ethtool` | `{}` | `feature-*`, `ring-*`, `coalesce-*`, `pause-*`, `channels-*`, `eee-*` |
| `ipv6_method` | `ipv6_default_method` | `auto`, `dhcp`, `manual`, `disabled`, `ignore` |
| `connection_id` | interface name | |
| `autoconnect` | `true` | |
| `reapply` | `false` | Apply changes at once |
| `ensure` | `present` | |

Bonds also take `slaves`, `bond_mode` (`802.3ad`), `bond_miimon` (`100`), `bond_lacp_rate`,
`bond_xmit_hash_policy`, `bond_primary`, `bond_primary_reselect`.

**Routes:** `destination` (required), `gateway`, `metric`, `table`, `src`, `description`.

**Routing rules:** `priority` (required), `from`, `to`, `table`, `iif`, `oif`, `fwmark`.

**Class:** `routing_tables`, `sysctl`, `ipv6_default_method` (`auto`), `backend`,
`manage_service` (`true`), `manage_packages` (`true`), `purge_connections` (`false`),
`netplan_renderer` (`networkd`).

## Notes

- **Adopting a RHEL host:** an existing profile with another name stays active until
  Puppet's profile is activated once. Use `reapply: true` in a maintenance window, then
  `nmcli connection delete <old>`.
- **Ubuntu:** netplan supports only offload `ethtool` settings, and rules need `from`/`to`
  and `table`. Unsupported settings fail the run.
- **Removing a bond member:** `network::bond_slave { 'bond0-eth2': ensure => absent }`.
- Upgrading from an earlier network module: [MIGRATING.md](MIGRATING.md).

## Checking a server

```bash
nmcli -t -f NAME,UUID,FILENAME connection show
ip route show table all; ip -N rule show
cat /proc/net/bonding/bond0
ethtool -g ens1f0np0; ethtool -c ens1f0np0       # rings, coalescing
```
