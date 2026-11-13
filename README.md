# network

Puppet module that configures Linux networking from Hiera: interfaces, bonds, VLANs,
bridges, static routes and policy routing.

| OS | Backend | Files written |
|---|---|---|
| RHEL, Rocky, Alma, Oracle 9 and 10 | `keyfile` | `/etc/NetworkManager/system-connections/*.nmconnection` |
| RHEL, CentOS, Rocky, Alma, Oracle 7 and 8 | `ifcfg` | `/etc/sysconfig/network-scripts/ifcfg-*`, `route-*` |
| Ubuntu 22.04 and 24.04 | `netplan` | `/etc/netplan/90-network.yaml` |
| Debian 11 and 12 | `ifupdown` | `/etc/network/interfaces.d/*` |
| SLES 15 | `wicked` | `/etc/sysconfig/network/ifcfg-*`, `ifroute-*` |

The backend follows the OS; set `network::backend` to override it.

## Installation

```ruby
# Puppetfile
mod 'puppetlabs/stdlib', '9.6.0'
mod 'puppetlabs/concat', '9.0.2'
mod 'network', :git => 'https://github.com/awijesundara/rhel_networking.git', :tag => 'v1.0.0'
```

Requires Puppet 7 or 8. Add `include network` to the node, then describe its interfaces in
Hiera. Hosts managed by an earlier network module: see [MIGRATING.md](MIGRATING.md).

## Example

Two uplinks: `eth1` carries the default route, `eth0` serves the management networks and
answers on its own routing table.

```yaml
---
network::routing_tables:
  1000: mgmt
  1010: prod

network::sysctl:
  net.ipv4.conf.all.rp_filter: 2      # needed with one routing table per uplink

network::interfaces:
  eth0:
    ipv4_address: '%{::ip_main}/23'
    ipv4_gateway: '10.68.184.1'
    ipv4_never_default: true          # not the default gateway
    routes:
      - destination: '10.67.180.0/24'
        gateway: '10.68.184.1'
        description: 'mgmt infra'     # kept as a comment in the generated file
      - destination: '10.68.184.0/23'
        table: mgmt
      - destination: '0.0.0.0/0'
        gateway: '10.68.184.1'
        table: mgmt
    routing_rules:
      - priority: 1000
        from: '10.68.184.0/23'
        table: mgmt

  eth1:
    ipv4_address: '%{::ip_internal}/23'
    ipv4_gateway: '10.68.172.1'       # default gateway
    routes:
      - destination: '0.0.0.0/0'
        gateway: '10.68.172.1'
        table: prod
      - destination: '10.68.172.0/23'
        table: prod
    routing_rules:
      - priority: 1010
        from: '10.68.172.0/23'
        table: prod
```

A bond, and a VLAN on top of it:

```yaml
network::bonds:
  bond0:
    slaves: [ens1f0, ens1f1]
    ipv4_address: '10.0.0.10/24'
    ipv4_gateway: '10.0.0.1'
    ipv4_dns: ['10.0.0.53']
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

More in [examples/](examples/).

## How changes are applied

- A Puppet run writes the files and reloads them. **Live links are not touched**: new
  settings take effect when the interface is next activated, NetworkManager restarts
  (e.g. after a package update) or the host reboots.
- To apply a change immediately, set `reapply: true` on the interface. This drops its link
  briefly, so use it in a maintenance window. For `network::connections` and `bridges`, the
  same is set with `activation: up` (per connection or for the whole class).
- Invalid data, such as a bad address, an unknown routing table or a setting the backend
  cannot express, fails the Puppet run before any file is written.
- Nothing outside the managed connections is deleted unless `purge_connections: true`.
- A run without data changes executes no commands.

## Reference

### `network::interfaces` and `network::bonds`

| Parameter | Default | |
|---|---|---|
| `ipv4_address` | – | Address in CIDR form, or a list |
| `ipv4_method` | `manual` with an address, else `auto` | `manual`, `auto` (DHCP), `disabled` |
| `ipv4_gateway` | – | Gateway of this interface |
| `ipv4_never_default` | `false` | Keep the gateway for routes, but add no default route |
| `ipv4_dns` | `[]` | DNS servers |
| `ipv4_route_metric` | – | Metric of this interface's routes |
| `mtu` | – | |
| `routes` | `[]` | See *Routes* |
| `routing_rules` | `[]` | See *Routing rules* |
| `ethtool` | `{}` | e.g. `{ feature-gro: false, ring-rx: 4096 }` |
| `ipv6_method` | `ipv6_default_method` | `auto`, `dhcp`, `manual`, `disabled`, `ignore` |
| `connection_id` | interface name | Connection and file name |
| `autoconnect` | `true` | Bring up at boot |
| `reapply` | `false` | Apply changes immediately (see above) |
| `ensure` | `present` | `absent` removes the connection |

Bonds also take `slaves` (required), `bond_mode` (`802.3ad`), `bond_miimon` (`100`),
`bond_lacp_rate`, `bond_xmit_hash_policy`, `bond_primary` and `bond_primary_reselect`,
and default to `ipv4_method: manual`.

### Routes

| Key | |
|---|---|
| `destination` | Required. Network in CIDR form; `0.0.0.0/0` for a default route |
| `gateway` | Next hop |
| `metric` | Route metric |
| `table` | Table number, or a name from `routing_tables` |
| `src` | Preferred source address |
| `description` | Comment in the generated file |

### Routing rules

| Key | |
|---|---|
| `priority` | Required |
| `from`, `to` | Source, destination network |
| `table` | Table number or name |
| `iif`, `oif`, `fwmark` | Incoming interface, outgoing interface, firewall mark |

### Class parameters

| Parameter | Default | |
|---|---|---|
| `backend` | from the OS | `keyfile`, `ifcfg`, `network_scripts`, `netplan`, `ifupdown`, `wicked` |
| `routing_tables` | `{}` | Table number to name; replaces `/etc/iproute2/rt_tables` |
| `sysctl` | `{}` | Written to `/etc/sysctl.d/90-network.conf` |
| `ipv6_default_method` | `auto` | IPv6 method of every interface that sets none, e.g. `disabled` |
| `activation` | `none` | For `connections` and `bridges`: `none`, `up` or `reapply` |
| `manage_service` | `true` | Manage NetworkManager, systemd-networkd or wicked |
| `manage_packages` | `true` | Install the backend's packages |
| `purge_connections` | `false` | Delete connection files Puppet does not manage |
| `netplan_renderer` | `networkd` | Ubuntu: `networkd` or `NetworkManager` |

## Notes per OS

- **RHEL:** `ethtool` ring, coalesce and offload settings take effect when the connection
  activates (`reapply: true` or a reboot).
- **RHEL, adopting a host:** if an interface already has a NetworkManager profile under
  another name (for example from the installer), NetworkManager keeps using that one, also
  after a reboot, until Puppet's profile has been activated once. Adopt such a host in a
  maintenance window with `reapply: true`, then delete the old profile
  (`nmcli connection delete <name>`).
- **RHEL 7:** NetworkManager 1.18 cannot store `/0` routes; they are written as two `/1`
  routes. `ipv6_method: disabled` becomes `ignore`.
- **Ubuntu:** all interfaces share `/etc/netplan/90-network.yaml`, and `netplan apply`
  applies all of them at once. Files from cloud-init (`50-cloud-init.yaml`) still apply;
  remove them when Puppet should own the network. A new file is checked with
  `netplan generate` before it replaces the old one. netplan cannot express everything, so
  these fail the run: rules without `from`/`to` or `table`, rules with `iif`/`oif`,
  `ipv4_never_default` with DHCP. With the `networkd` renderer and both DHCP families
  enabled, IPv4 and IPv6 route metrics, `ignore_auto_dns` and `ignore_auto_routes`
  must match; mismatches fail compilation. Of `ethtool`, only offload settings are supported.
- **Debian / ifupdown:** automatic addressing cannot enforce `ipv4_never_default`
  or `ipv6_never_default`, and `ipv4_ignore_auto_routes` / `ipv6_ignore_auto_routes`
  are unsupported. These settings fail compilation rather than allowing unwanted routes.
- **SUSE / wicked:** `ignore_auto_routes`, `ignore_auto_dns`, and `ipv6_never_default`
  with automatic IPv6 fail compilation. DNS comes from `/etc/sysconfig/network/config`.
- **Bonds:** port profiles use a custom controller `interface_name` when supplied.
  With flat `reapply: true`, changes to managed port profiles reactivate the bond.
  Removing a member from `slaves` leaves its file in place; remove it with
  `network::bond_slave { 'bond0-eth2': ensure => absent }`.

## Checking a server

```bash
nmcli -t -f NAME,UUID,FILENAME connection show   # RHEL: connections and their files
netplan get                                       # Ubuntu: merged configuration
ip addr show
ip route show table all
ip -N rule show
cat /proc/net/bonding/bond0
```

Each generated file starts with a header naming the Puppet resource that wrote it.
