# Moving existing hosts to network

Hosts already configured by an earlier network module move over with a prefix rename.
Never include `network` and the earlier module in the same catalog: both manage the same
connection profiles and services.

## Steps

1. In Hiera and manifests, rename the old module prefix to `network::` (for example
   `<old>::interfaces` becomes `network::interfaces`), and type references to
   `Network::Route` / `Network::Routing_rule`.
2. Keep resource titles, `connection_id` values, bond `slaves` and `connections_dir` as they
   are. Connection IDs, UUIDs and file names stay the same, so existing profiles are updated
   in place instead of duplicated.
3. Run `puppet agent -t --noop` on one host. Only the connection files should change; no
   profile should be removed and no `network: activate` command should run unless an
   interface sets `reapply: true`.
4. Apply on one canary host and check `nmcli -f NAME,UUID,FILENAME connection show`,
   `ip route show table all` and `ip rule show` before rolling out further.

## Behaviour to be aware of

- An interface with `ipv4_address` and no `ipv4_method` is configured as static (`manual`).
  Set `ipv4_method: auto` if a host really needs DHCP in addition to its static address.
- `ipv4_gateway` with `ipv4_never_default: true` keeps the gateway for routes but adds no
  default route to the main table.
- A bond's `ethtool` settings apply to the bond itself.
- On RHEL 9 and later, generated keyfiles carry `addr-gen-mode=default`.
- Changes are written and NetworkManager reloads them, but the live link is not touched
  unless the interface sets `reapply: true` (see the README section *How changes are applied*).
- Removing a member from `slaves` does not delete its profile; declare
  `network::bond_slave { '<bond>-<device>': ensure => absent }`.
- Ubuntu uses the `netplan` backend by default; set `network::backend: ifupdown` to keep
  ifupdown there.
