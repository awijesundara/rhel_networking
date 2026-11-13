# Changelog

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
