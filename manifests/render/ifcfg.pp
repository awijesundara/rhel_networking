# @summary Write RHEL ifcfg-<dev>, route-/route6-<dev> and rule-/rule6-<dev> files.
# @api private
#
# Used by two backends:
#   ifcfg           - NetworkManager reads the files (ifcfg-rh plugin).
#   network_scripts - the legacy `network` service reads them (NM_CONTROLLED=no).
# Reference: /usr/share/doc/initscripts*/sysconfig.txt and `man nm-settings-ifcfg-rh`.
define network::render::ifcfg (
  Hash $profile,
  Hash $overrides = {},
) {
  assert_private()

  $p     = $profile
  $nm    = $network::nm_managed
  $dir   = $network::ifcfg_dir
  # Policy routing rules:
  #   network_scripts - rule-<dev> / rule6-<dev> files (read by ifup-routes).
  #   ifcfg (NM)      - ROUTING_RULE_N / ROUTING_RULE6_N keys inside ifcfg-<dev>. NetworkManager
  #                     does not read rule- files itself (NM >= 1.18: RHEL 7.7+, 8.1+).
  $v4_rules = $p['port'] ? { undef => $p['ipv4']['rules'], default => [] }
  $v6_rules = $p['port'] ? { undef => $p['ipv6']['rules'], default => [] }
  $nm_rule_keys = $nm ? {
    true    => Hash($v4_rules.map |$i, $r| { ["ROUTING_RULE_${$i + 1}", network::ip_rule($r)] })
      + Hash($v6_rules.map |$i, $r| { ["ROUTING_RULE6_${$i + 1}", network::ip_rule($r)] }),
    default => {},
  }
  # Shell-style ifcfg keys cannot carry a comment each, so explain the rules in the header.
  $rule_notes = $nm ? {
    true    => ($v4_rules.map |$i, $r| { network::comment($r).then |$c| { "ROUTING_RULE_${$i + 1}: ${c[2, -1]}" } }
      + $v6_rules.map |$i, $r| { network::comment($r).then |$c| { "ROUTING_RULE6_${$i + 1}: ${c[2, -1]}" } }
      ).filter |$n| { $n =~ NotUndef },
    default => [],
  }

  $label = $nm ? {
    true    => "NetworkManager ifcfg-rh plugin (inspect: nmcli connection show '${p['id']}')",
    default => "legacy network service, NM_CONTROLLED=no (inspect: ip addr show ${p['device']}; ip rule)",
  }
  # The ifcfg file explains its ROUTING_RULE_N keys; route-/rule- files explain themselves line by line.
  $header = network::header($p['source'], $label)

  # --- device -------------------------------------------------------------
  $physical = $p['type'] in ['ethernet', 'infiniband']
  $device = {
    'DEVICE'               => $p['device'],
    'NAME'                 => $p['id'],
    'UUID'                 => $p['uuid'],
    'TYPE'                 => $p['type'] ? {
      'ethernet' => 'Ethernet', 'bond' => 'Bond', 'vlan' => 'Vlan', 'bridge' => 'Bridge', 'infiniband' => 'InfiniBand',
    },
    'ONBOOT'               => $p['autoconnect'],
    'NM_CONTROLLED'        => $nm ? { true => undef, default => false },
    'AUTOCONNECT_PRIORITY' => $nm ? { true => $p['autoconnect_priority'], default => undef },
    'HWADDR'               => $physical ? { true => $p['mac_address'], default => undef },
    'MACADDR'              => $physical ? { true => undef, default => $p['mac_address'] },
    'MTU'                  => $p['mtu'],
    'ZONE'                 => $p['zone'],
    'ETHTOOL_OPTS'         => $p['ethtool_opts'],
  }

  $type_keys = $p['type'] ? {
    'bond'       => {
      'BONDING_MASTER' => true,
      'BONDING_OPTS'   => $p['bond_options'].map |$k, $v| { "${k}=${v}" }.join(' '),
    },
    'vlan'       => { 'VLAN' => true, 'PHYSDEV' => $p['vlan_parent'], 'VLAN_ID' => $p['vlan_id'] },
    'bridge'     => {
      'STP'           => $p['bridge_options']['stp'],
      'DELAY'         => $p['bridge_options']['forward-delay'],
      'BRIDGING_OPTS' => network::sysfs_opts($p['bridge_options'].filter |$k, $v| { !($k in ['stp', 'forward-delay']) }),
    },
    'infiniband' => {
      'CONNECTED_MODE' => $p['infiniband_mode'].then |$m| { $m == 'connected' },
    },
    default      => {},
  }

  $port_keys = $p['port'] ? {
    undef   => {},
    default => $p['port']['type'] ? {
      'bond'   => { 'MASTER' => $p['port']['controller'], 'SLAVE' => true },
      'bridge' => {
        'BRIDGE'        => $p['port']['controller'],
        'BRIDGING_OPTS' => network::sysfs_opts($p['port']['bridge_options']),
      },
    },
  }

  # --- layer 3 ------------------------------------------------------------
  if $p['port'] =~ NotUndef {
    $l3 = {}
    $files = {}
  } else {
    $v4 = $p['ipv4']
    $v6 = $p['ipv6']
    if !$nm and ($v4['route_table'] =~ NotUndef or $v6['route_table'] =~ NotUndef) {
      warning("${p['source']}: ipv4/ipv6_route_table is ignored by network-scripts; set 'table' on each route")
    }

    # Same layout nmcli writes: IPADDR/PREFIX for the first address, IPADDR1.. for the rest.
    # (NetworkManager ignores GATEWAY when the first address is written as IPADDR0.)
    $v4_addresses = $v4['addresses'].map |$i, $a| {
      $parts  = $a.split('/')
      $suffix = $i ? { 0 => '', default => String($i) }
      ({ "IPADDR${suffix}" => $parts[0], "PREFIX${suffix}" => $parts[1] })
    }.reduce({}) |$m, $h| { $m + $h }
    $dns = ($v4['dns'] + $v6['dns']).map |$i, $d| { ["DNS${$i + 1}", $d] }

    $ipv4 = {
      'BOOTPROTO'          => $v4['method'] ? { 'auto' => 'dhcp', 'shared' => 'shared', 'link-local' => 'autoip', default => 'none' },
    } + $v4_addresses + {
      'GATEWAY'            => $v4['gateway'],
      'DEFROUTE'           => $v4['never_default'] ? { true => false, default => undef },
      'IPV4_FAILURE_FATAL' => $v4['may_fail'].then |$f| { !$f },
      'PEERDNS'            => $v4['ignore_auto_dns'] ? { true => false, default => undef },
      'PEERROUTES'         => $v4['ignore_auto_routes'] ? { true => false, default => undef },
      'DOMAIN'             => $v4['dns_search'].empty ? { true => undef, default => $v4['dns_search'] },
      # NetworkManager and network-scripts name the metric differently.
      'IPV4_ROUTE_METRIC'  => $nm ? { true => $v4['route_metric'], default => undef },
      'METRIC'             => $nm ? { true => undef, default => $v4['route_metric'] },
      'IPV4_ROUTE_TABLE'   => $nm ? { true => $v4['route_table'], default => undef },
    } + Hash($dns)

    $ipv6 = $v6['method'] ? {
      'ignore'   => { 'IPV6INIT' => false },
      'disabled' => { 'IPV6INIT' => false, 'IPV6_DISABLED' => $nm ? { true => true, default => undef } },
      default    => {
        'IPV6INIT'             => true,
        'IPV6_AUTOCONF'        => $v6['method'] == 'auto',
        'DHCPV6C'              => ($v6['method'] == 'dhcp') ? { true => true, default => undef },
        'IPV6ADDR'             => $v6['addresses'][0],
        'IPV6ADDR_SECONDARIES' => ($v6['addresses'].length > 1) ? { true => $v6['addresses'][1, -1], default => undef },
        'IPV6_DEFAULTGW'       => $v6['gateway'],
        'IPV6_DEFROUTE'        => $v6['never_default'] ? { true => false, default => undef },
        'IPV6_FAILURE_FATAL'   => $v6['may_fail'].then |$f| { !$f },
        'IPV6_PEERDNS'         => $v6['ignore_auto_dns'] ? { true => false, default => undef },
        'IPV6_PEERROUTES'      => $v6['ignore_auto_routes'] ? { true => false, default => undef },
        'IPV6_ADDR_GEN_MODE'   => $v6['addr_gen_mode'],
        'IPV6_ROUTE_METRIC'    => $nm ? { true => $v6['route_metric'], default => undef },
        'IPV6_ROUTE_TABLE'     => $nm ? { true => $v6['route_table'], default => undef },
      },
    }
    $l3 = $ipv4 + $ipv6

    # route-/rule- files: one `ip route` / `ip rule` argument list per line,
    # each preceded by a comment when there is something to explain.
    $files = {
      'route'  => network::annotated($v4['routes'], $v4['routes'].map |$r| { network::ip_route($r, $p['device']) }),
      'route6' => network::annotated($v6['routes'], $v6['routes'].map |$r| { network::ip_route($r, $p['device']) }),
      'rule'   => $nm ? { true => [], default => network::annotated($v4_rules, $v4_rules.map |$r| { network::ip_rule($r) }) },
      'rule6'  => $nm ? { true => [], default => network::annotated($v6_rules, $v6_rules.map |$r| { network::ip_rule($r) }) },
    }
  }

  # --- write files --------------------------------------------------------
  $ensure_file = $p['ensure'] ? { 'present' => file, default => absent }
  $notify      = $nm ? { true => Exec['network: nmcli connection reload'], default => undef }
  $ifcfg_path  = "${dir}/ifcfg-${p['file_name']}"

  file { $ifcfg_path:
    ensure  => $ensure_file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('network/shellvars.epp', {
      header   => network::header($p['source'], $label, $rule_notes + [
        'uuid is derived from the host FQDN and the connection id, so it is stable across Puppet runs',
      ]),
      settings => $device + $type_keys + $port_keys + $l3 + $nm_rule_keys + $overrides,
    }),
    notify  => $notify,
  }

  # Always manage all four companion files, so stale routes/rules are removed
  # (under NetworkManager the rule- files are always removed, see above).
  $companions = ['route', 'route6', 'rule', 'rule6'].map |$kind| {
    $lines = $files[$kind].lest || { [] }
    $path  = "${dir}/${kind}-${p['file_name']}"
    file { $path:
      ensure  => ($p['ensure'] == 'present' and !$lines.empty) ? { true => file, default => absent },
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => epp('network/lines.epp', { header => $header, lines => $lines }),
      notify  => $notify,
    }
    File[$path]
  }

  # When going back from keyfile to ifcfg, remove this connection's keyfile.
  if $network::remove_foreign_files and $nm {
    file { "${network::keyfile_dir}/${p['id']}.nmconnection":
      ensure => absent,
      notify => $notify,
    }
  }

  # How the legacy network service must be driven (verified on EL7 and EL8):
  #   bond         ifdown/ifup the bond; `ifup bond0` re-adds its members.
  #   bond member  restart the bond instead (ifdown on a member alone is not enough).
  #   bridge       ifdown/ifup the bridge, then `ifup` each member; `ifup br0` does
  #                NOT re-attach members.
  #   bridge member  only `ifup` it: `ifdown` on a member tears the whole bridge down,
  #                and it comes back without its address.
  $legacy = !$nm
  $port_of = $p['port'].then |$port| { $port['type'] }

  if $legacy and $port_of == 'bond' {
    File[$ifcfg_path] ~> Exec <| title == "network: activate ${p['port']['controller']}" |>
  } else {
    $legacy_command = $port_of ? {
      'bridge' => "ifup '${p['file_name']}'",
      default  => (["ifdown '${p['file_name']}'", "ifup '${p['file_name']}'"]
        + ($p['type'] == 'bridge').then |$is_bridge| { $is_bridge ? { true => $p['ports'].map |$m| { "ifup '${m}'" }, default => [] } }
      ).join('; '),
    }
    network::activate { $title:
      profile => $p,
      files   => [File[$ifcfg_path]] + $companions,
      command => $nm ? {
        true    => $p['activation'] ? {
          'reapply' => "nmcli device reapply '${p['device']}'",
          default   => "nmcli connection up uuid '${p['uuid']}'",
        },
        default => $legacy_command,
      },
    }
  }
}
