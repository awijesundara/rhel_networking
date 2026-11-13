# @summary Write an Ubuntu netplan file (/etc/netplan/90-network-<dev>.yaml).
# @api private
#
# One file per connection; netplan merges every file in /etc/netplan, so a bond in one file
# can list ports declared in other files. Reference: `man netplan`, https://netplan.readthedocs.io.
# Everything a netplan file cannot express fails compilation instead of being dropped.
define network::render::netplan (
  Hash $profile,
  Hash $overrides = {},
) {
  assert_private()

  $p     = $profile
  $dev   = $p['device']
  $where = "network::connection[${title}] (netplan)"

  # --- device -------------------------------------------------------------
  $section = $p['type'] ? {
    'bond'   => 'bonds',
    'bridge' => 'bridges',
    'vlan'   => 'vlans',
    default  => 'ethernets',   # ethernet, infiniband
  }

  # Kernel bonding option names -> netplan names (`man netplan`, "Properties for device type bonds").
  $bond_keys = {
    'mode'              => 'mode',
    'miimon'            => 'mii-monitor-interval',
    'lacp_rate'         => 'lacp-rate',
    'xmit_hash_policy'  => 'transmit-hash-policy',
    'primary'           => 'primary',
    'primary_reselect'  => 'primary-reselect-policy',
    'updelay'           => 'up-delay',
    'downdelay'         => 'down-delay',
    'arp_interval'      => 'arp-interval',
    'arp_ip_target'     => 'arp-ip-targets',
    'arp_validate'      => 'arp-validate',
    'arp_all_targets'   => 'arp-all-targets',
    'ad_select'         => 'ad-select',
    'min_links'         => 'min-links',
    'num_grat_arp'      => 'gratuitous-arp',
    'num_unsol_na'      => 'gratuitous-arp',
    'all_slaves_active' => 'all-slaves-active',
    'fail_over_mac'     => 'fail-over-mac-policy',
    'packets_per_slave' => 'packets-per-slave',
    'resend_igmp'       => 'resend-igmp',
    'lp_interval'       => 'learn-packet-interval',
  }
  $bond_parameters = $p['bond_options'].reduce({}) |$memo, $opt| {
    $key = regsubst($opt[0], '-', '_', 'G')
    $name = $bond_keys[$key].lest || { fail("${where}: bond option '${opt[0]}' has no netplan equivalent") }
    $value = $key ? {
      'primary_reselect' => String($opt[1]) ? { '0' => 'always', '1' => 'better', '2' => 'failure', default => $opt[1] },
      'arp_ip_target'    => String($opt[1]).split(',').map |$t| { $t.strip },
      'all_slaves_active' => $opt[1] ? { Boolean => $opt[1], default => String($opt[1]) == '1' },
      default            => $opt[1],
    }
    $memo + { $name => $value }
  }

  # Bridge options use NetworkManager property names (see network::connection).
  $bridge_keys = {
    'stp'           => 'stp',
    'priority'      => 'priority',
    'forward-delay' => 'forward-delay',
    'hello-time'    => 'hello-time',
    'max-age'       => 'max-age',
    'ageing-time'   => 'ageing-time',
  }
  $bridge_parameters = $p['bridge_options'].reduce({}) |$memo, $opt| {
    $name = $bridge_keys[regsubst($opt[0], '_', '-', 'G')].lest || {
      fail("${where}: bridge option '${opt[0]}' has no netplan equivalent")
    }
    $memo + { $name => $opt[1] }
  }

  $type_keys = $p['type'] ? {
    'bond'       => {
      'interfaces' => $p['ports'],
      'parameters' => $bond_parameters.empty ? { true => undef, default => $bond_parameters },
    },
    'bridge'     => {
      'interfaces' => $p['ports'],
      'parameters' => $bridge_parameters.empty ? { true => undef, default => $bridge_parameters },
    },
    'vlan'       => { 'id' => $p['vlan_id'], 'link' => $p['vlan_parent'] },
    'infiniband' => { 'infiniband-mode' => $p['infiniband_mode'] },
    default      => {},
  }

  # A physical NIC with a MAC is matched by it (and renamed to `dev`); virtual devices get it set.
  $mac_keys = $p['mac_address'] ? {
    undef   => {},
    default => ($p['type'] in ['ethernet', 'infiniband']) ? {
      true    => { 'match' => { 'macaddress' => downcase($p['mac_address']) }, 'set-name' => $dev },
      default => { 'macaddress' => downcase($p['mac_address']) },
    },
  }

  # Keyfile [ethtool] feature names that netplan (networkd renderer) can set.
  $offload_keys = {
    'feature-rx'                    => 'receive-checksum-offload',
    'feature-tx'                    => 'transmit-checksum-offload',
    'feature-tso'                   => 'tcp-segmentation-offload',
    'feature-tx-tcp6-segmentation'  => 'tcp6-segmentation-offload',
    'feature-gso'                   => 'generic-segmentation-offload',
    'feature-gro'                   => 'generic-receive-offload',
    'feature-lro'                   => 'large-receive-offload',
  }
  $unmapped = $p['ethtool'].keys.filter |$k| { !($k in $offload_keys) }
  unless $unmapped.empty {
    warning("${where}: ethtool settings ${unmapped.join(', ')} have no netplan equivalent and are not applied")
  }
  $offloads = $p['ethtool'].filter |$k, $v| { $k in $offload_keys }.reduce({}) |$memo, $e| {
    $memo + { $offload_keys[$e[0]] => $e[1] ? { Boolean => $e[1], default => String($e[1]) in ['1', 'true', 'on'] } }
  }
  if $p['ethtool_opts'] =~ NotUndef {
    warning("${where}: ethtool_opts has no netplan equivalent and is not applied")
  }
  ['autoconnect_priority', 'zone'].each |$k| {
    if $p[$k] =~ NotUndef {
      warning("${where}: ${k} is NetworkManager-only and is not applied by netplan")
    }
  }

  $link_keys = {
    'mtu'             => $p['mtu'],
    'activation-mode' => $p['autoconnect'] ? { true => undef, default => 'manual' },
  } + $mac_keys + $offloads

  # --- layer 3 ------------------------------------------------------------
  if $p['port'] =~ NotUndef {
    if !$p['port']['bridge_options'].empty {
      fail("${where}: bridge_port_options are not supported by netplan; set path-cost/port-priority with netplan_settings on the bridge")
    }
    # Members carry no addresses; netplan brings them up as part of their bond/bridge.
    $l3_keys = { 'dhcp4' => false, 'dhcp6' => false, 'accept-ra' => false, 'link-local' => [] }
  } else {
    $v4 = $p['ipv4']
    $v6 = $p['ipv6']

    if $v4['method'] in ['shared'] or $v6['method'] in ['shared', 'ignore'] {
      fail("${where}: ipv4_method/ipv6_method '${v4['method']}'/'${v6['method']}' is not supported by netplan")
    }
    if $v4['never_default'] and $v4['method'] == 'auto' {
      fail("${where}: ipv4_never_default with DHCP is not supported by netplan; use ipv4_ignore_auto_routes")
    }
    if $v6['never_default'] and $v6['method'] in ['auto', 'dhcp'] {
      fail("${where}: ipv6_never_default with automatic IPv6 is not supported by netplan; use ipv6_ignore_auto_routes")
    }
    if $v4['may_fail'] =~ NotUndef or $v6['may_fail'] =~ NotUndef {
      warning("${where}: ipv4_may_fail/ipv6_may_fail are NetworkManager-only and are not applied by netplan")
    }

    $routes = [['0.0.0.0/0', $v4], ['::/0', $v6]].filter |$d| { $d[1]['gateway'] =~ NotUndef and !$d[1]['never_default'] }.map |$d| {
      network::netplan_route($d[1], { 'destination' => $d[0], 'gateway' => $d[1]['gateway'] })
    } + $v4['routes'].map |$r| { network::netplan_route($v4, $r) } + $v6['routes'].map |$r| { network::netplan_route($v6, $r) }

    $rules = ($v4['rules'] + $v6['rules']).map |$r| {
      $unsupported = ['not', 'iif', 'oif', 'ipproto', 'sport', 'dport', 'uidrange', 'suppress_prefixlength', 'action']
        .filter |$k| { $r[$k] =~ NotUndef and $r[$k] != false }
      unless $unsupported.empty {
        fail("${where}: routing rule priority ${r['priority']} uses ${unsupported.join(', ')}, which netplan does not support")
      }
      if $r['from'] =~ Undef and $r['to'] =~ Undef {
        fail("${where}: routing rule priority ${r['priority']} needs 'from' or 'to' on netplan")
      }
      if $r['table'] =~ Undef {
        fail("${where}: routing rule priority ${r['priority']} needs a table on netplan")
      }
      if $r['fwmark'] =~ String and '/' in $r['fwmark'] {
        fail("${where}: routing rule priority ${r['priority']}: netplan cannot express an fwmark mask")
      }
      if $r['tos'] =~ String and $r['tos'] !~ /\A(0x)?[0-9a-fA-F]+\z/ {
        fail("${where}: routing rule priority ${r['priority']}: netplan needs a numeric tos")
      }
      $entry = {
        'from'            => $r['from'],
        'to'              => $r['to'],
        'table'           => network::table_id($r['table']),
        'priority'        => $r['priority'],
        'mark'            => $r['fwmark'].then |$m| { Integer($m) },
        'type-of-service' => $r['tos'].then |$t| { Integer($t) },
      }
      $entry.filter |$k, $v| { $v =~ NotUndef }
    }

    $dhcp4 = $v4['method'] == 'auto'
    $dhcp6 = $v6['method'] in ['auto', 'dhcp']
    $overrides4 = {
      'use-dns'      => $v4['ignore_auto_dns'] ? { true => false, default => undef },
      'use-routes'   => $v4['ignore_auto_routes'] ? { true => false, default => undef },
      'route-metric' => $v4['route_metric'],
    }.filter |$k, $v| { $v =~ NotUndef }
    $overrides6 = {
      'use-dns'      => $v6['ignore_auto_dns'] ? { true => false, default => undef },
      'use-routes'   => $v6['ignore_auto_routes'] ? { true => false, default => undef },
      'route-metric' => $v6['route_metric'],
    }.filter |$k, $v| { $v =~ NotUndef }
    if $p['ensure'] == 'present' and $network::netplan_renderer == 'networkd' and $dhcp4 and $dhcp6 and $overrides4 != $overrides6 {
      fail("${where}: networkd requires identical IPv4 and IPv6 DHCP overrides; set matching ipv4/ipv6_route_metric, ignore_auto_dns and ignore_auto_routes, or disable one DHCP family")
    }
    $dns = $v4['dns'] + $v6['dns']

    $l3_keys = {
      'dhcp4'                   => $dhcp4,
      'dhcp4-overrides'         => ($dhcp4 and !$overrides4.empty) ? { true => $overrides4, default => undef },
      'dhcp6'                   => $dhcp6,
      'dhcp6-overrides'         => ($dhcp6 and !$overrides6.empty) ? { true => $overrides6, default => undef },
      # NetworkManager 'auto' is SLAAC (+ DHCPv6 when the router asks); 'dhcp' is DHCPv6 only.
      'accept-ra'               => $v6['method'] == 'auto',
      'link-local'              => (($v4['method'] == 'link-local') ? { true => ['ipv4'], default => [] })
        + (($v6['method'] == 'disabled') ? { true => [], default => ['ipv6'] }),
      'ipv6-address-generation' => $v6['addr_gen_mode'],
      'addresses'               => ($v4['addresses'] + $v6['addresses']).then |$a| { $a.empty ? { true => undef, default => $a } },
      'nameservers'             => ($dns.empty and $v4['dns_search'].empty) ? {
        true    => undef,
        default => {
          'addresses' => $dns.empty ? { true => undef, default => $dns },
          'search'    => $v4['dns_search'].empty ? { true => undef, default => $v4['dns_search'] },
        }.filter |$k, $v| { $v =~ NotUndef },
      },
      'routes'                  => $routes.empty ? { true => undef, default => $routes },
      'routing-policy'          => $rules.empty ? { true => undef, default => $rules },
    }
  }

  $device = ($type_keys + $link_keys + $l3_keys + $overrides).filter |$k, $v| { $v =~ NotUndef }

  $notes = ['ipv4', 'ipv6'].map |$family| {
    $p[$family].then |$f| {
      $f['routes'].map |$r| { network::comment($r).then |$c| { "route ${r['destination']}: ${c[2, -1]}" } } +
      $f['rules'].map |$r| { network::comment($r).then |$c| { "rule priority ${r['priority']}: ${c[2, -1]}" } }
    }.lest || { [] }
  }.flatten.filter |$n| { $n =~ NotUndef }

  # The device as YAML, indented to sit under its section in the shared netplan file.
  $yaml = regsubst(stdlib::to_yaml({ $dev => $device }), '\A---\n', '')
  $comments = (["${p['source']} (inspect: netplan get ${section}.${dev})"] + $notes).map |$n| { "# ${n}\n" }.join('')
  $block = "${comments}${yaml}".split("\n").map |$l| { "    ${l}\n" }.join('')

  if $p['ensure'] == 'present' {
    $order = { 'ethernets' => 10, 'bonds' => 20, 'bridges' => 30, 'vlans' => 40 }[$section]
    ensure_resource('concat::fragment', "network: netplan ${section}", {
      'target'  => $network::netplan_file,
      'order'   => "${order}-0",
      'content' => "  ${section}:\n",
    })
    concat::fragment { "network: netplan ${section} ${dev}":
      target  => $network::netplan_file,
      order   => "${order}-1-${dev}",
      content => $block,
    }
  }

  # netplan only reads all devices at once (it rejects references to devices defined in a later
  # file), so they share one file. This per-device copy changes only when this device's settings
  # change, so `netplan apply` runs for connections that ask to be activated, as on the other backends.
  $state = "${network::netplan_state_dir}/${regsubst($p['file_name'], '[^A-Za-z0-9_.-]', '_', 'G')}.yaml"
  file { $state:
    ensure  => $p['ensure'] ? { 'present' => file, default => absent },
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => "# Copy of ${dev} in ${network::netplan_file}; changes here trigger netplan apply.\n${yaml}",
  }
  if $p['activation'] != 'none' {
    File[$state] ~> Exec['network: netplan apply']
  }
}
