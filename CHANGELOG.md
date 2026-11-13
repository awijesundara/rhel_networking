# Changelog

## 1.0.1

- NetworkManager reload and activation only run while NetworkManager is active.
- Bond and bridge members use the controller's `interface_name` when it differs from the title.
- VLANs follow their parent device's activation even when the parent's connection ID differs.
- Flat bonds with `reapply: true` also reactivate when a member profile changes.
- `network::interfaces` and flat bonds follow `network::ipv6_default_method`.
- Unknown `ethtool` keys fail compilation instead of producing a profile NetworkManager rejects.
- netplan (networkd) rejects mismatched IPv4/IPv6 DHCP overrides; ifupdown rejects
  `never_default` with DHCP and `ignore_auto_routes`, which it cannot enforce.
- Hosts without any connection compile on Puppet 8.
- Routing-rule `tos` and `ipproto`, route `options` values and routing-table names accept
  only plain values, so they cannot inject shell syntax into ifupdown hooks or escape
  `rt_tables.d`.
- ifupdown bonds list their members, so reactivating a bond keeps its members attached.
- A route metric of `-1` means the default, as in NetworkManager, on every backend.
- `network::route_table` creates `rt_tables.d` when used on its own.
- Raw settings (`keyfile_settings`, `ifcfg_settings`, `nm_settings`, `nm_conf_files`, `sysctl`,
  `sysconfig_network`), bond, bridge and ethtool option values, `zone`, `ethtool_opts`,
  `dns_search` and resource titles are validated, closing the remaining ways for data to
  add lines to generated files or leave the configuration directories.
- netplan: a new file is validated with `netplan generate` in a scratch copy before it
  replaces the working one, so a rejected file never reaches `/etc/netplan`.
- Legacy network-scripts bonds whose ID differs from their device are reactivated when a
  member changes.
- wicked: `ipv4_never_default` and `ipv4_route_metric` apply to DHCP; route metrics are kept
  on the default and static routes; `ignore_auto_routes`/`ignore_auto_dns` fail compilation.

## 1.0.0 (2026-11-13)

First release.

- Backends: NetworkManager keyfile (RHEL 9/10, any NetworkManager host), ifcfg and
  network-scripts (RHEL 7/8), netplan (Ubuntu), ifupdown (Debian), wicked (SUSE).
- Interfaces, bonds, VLANs, bridges, InfiniBand; IPv4/IPv6 addresses, DNS, static routes,
  policy routing rules, named routing tables, ethtool settings, sysctl.
- Hiera entry points `network::interfaces`, `bonds`, `connections`, `bridges`,
  `routing_tables`.
- Changes are written and reloaded without touching live links unless `reapply: true`.
- Input that could end up in commands or file paths (interface names, connection IDs,
  file names, option keys, descriptions) is validated before any file is written.
