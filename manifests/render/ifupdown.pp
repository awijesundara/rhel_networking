# @summary Write a Debian/Ubuntu ifupdown stanza to /etc/network/interfaces.d/<dev>.
# @api private
#
# Static routes and policy rules have no native ifupdown syntax, so they become
# `up ip route add ...` / `up ip rule add ...` hook lines, exactly what an admin
# would type by hand. Reference: `man interfaces`, `man interfaces-bond`.
define network::render::ifupdown (
  Hash          $profile,
  Array[String] $extra_lines = [],
) {
  assert_private()

  $p   = $profile
  $dev = $p['device']

  # --- device -------------------------------------------------------------
  $type_lines = $p['type'] ? {
    # The bond lists no slaves itself; each port says `bond-master <bond>`.
    'bond'   => ['bond-slaves none'] + $p['bond_options'].map |$k, $v| { "bond-${regsubst($k, '_', '-', 'G')} ${v}" },
    'vlan'   => ["vlan-raw-device ${p['vlan_parent']}"],
    'bridge' => ["bridge_ports ${p['ports'].empty ? { true => 'none', default => $p['ports'].join(' ') }}"]
      + $p['bridge_options'].map |$k, $v| {
        $key   = $k ? { 'forward-delay' => 'fd', default => regsubst($k, '-', '_', 'G') }
        $value = $v ? { true => 'on', false => 'off', default => $v }
        "bridge_${key} ${value}"
      },
    default  => [],
  }
  $port_lines = ($p['port'] =~ NotUndef and $p['port']['type'] == 'bond') ? {
    true    => ["bond-master ${p['port']['controller']}"],
    default => [],
  }
  $link_lines = [
    $p['mtu'].then |$m| { "mtu ${m}" },
    $p['mac_address'].then |$m| { "hwaddress ether ${m}" },
  ]

  # --- layer 3 ------------------------------------------------------------
  if $p['port'] =~ NotUndef {
    $inet_method  = 'manual'
    $inet_lines   = []
    $inet6_method = undef
    $inet6_lines  = []
  } else {
    $v4 = $p['ipv4']
    $v6 = $p['ipv6']

    $inet_method = $v4['method'] ? { 'manual' => 'static', 'auto' => 'dhcp', default => 'manual' }
    $inet_lines  = [
      ($v4['method'] == 'manual') ? { true => "address ${v4['addresses'][0]}", default => undef },
      ($v4['gateway'] =~ NotUndef and !$v4['never_default']) ? { true => "gateway ${v4['gateway']}", default => undef },
      $v4['route_metric'].then |$m| { "metric ${m}" },
      ($v4['dns'] + $v6['dns']).empty ? { true => undef, default => "dns-nameservers ${($v4['dns'] + $v6['dns']).join(' ')}" },
      $v4['dns_search'].empty ? { true => undef, default => "dns-search ${v4['dns_search'].join(' ')}" },
      ($v6['method'] != 'ignore') ? {
        # sysctl needs '/' instead of '.' inside interface names (bond0.200 -> bond0/200)
        true    => "pre-up sysctl -qw net.ipv6.conf.${regsubst($dev, '\.', '/', 'G')}.disable_ipv6=${$v6['method'] ? { 'disabled' => 1, default => 0 }}",
        default => undef,
      },
    ] + $v4['addresses'][1, -1].map |$a| { "up ip addr add ${a} dev ${dev}" }
      + network::annotated($v4['routes'], $v4['routes'].map |$r| { "up ip route add ${network::ip_route($r, $dev)}" })
      + network::annotated($v4['rules'], $v4['rules'].map |$r| { "up ip rule add ${network::ip_rule($r)}" })
      + $v4['rules'].map |$r| { "pre-down ip rule del ${network::ip_rule($r)}" }

    $inet6_method = $v6['method'] ? { 'manual' => 'static', 'auto' => 'auto', 'dhcp' => 'dhcp', default => undef }
    $inet6_lines  = [
      ($v6['method'] == 'manual') ? { true => "address ${v6['addresses'][0]}", default => undef },
      ($v6['gateway'] =~ NotUndef and !$v6['never_default']) ? { true => "gateway ${v6['gateway']}", default => undef },
    ] + $v6['addresses'][1, -1].map |$a| { "up ip -6 addr add ${a} dev ${dev}" }
      + network::annotated($v6['routes'], $v6['routes'].map |$r| { "up ip -6 route add ${network::ip_route($r, $dev)}" })
      + network::annotated($v6['rules'], $v6['rules'].map |$r| { "up ip -6 rule add ${network::ip_rule($r)}" })
      + $v6['rules'].map |$r| { "pre-down ip -6 rule del ${network::ip_rule($r)}" }
  }

  # --- assemble the stanza ------------------------------------------------
  $inet_body = ($type_lines + $port_lines + $link_lines + $inet_lines + $extra_lines).filter |$l| { $l =~ NotUndef }
  $stanza = [
    $p['autoconnect'] ? { true => "auto ${dev}", default => undef },
    "iface ${dev} inet ${inet_method}",
  ] + $inet_body.map |$l| { "    ${l}" } + (($inet6_method =~ Undef) ? {
    true    => [],
    default => ['', "iface ${dev} inet6 ${inet6_method}"]
      + $inet6_lines.filter |$l| { $l =~ NotUndef }.map |$l| { "    ${l}" },
  })

  # interfaces.d only sources names made of letters, digits, '_' and '-'.
  $path = "${network::ifupdown_dir}/${regsubst($p['file_name'], '[^A-Za-z0-9_-]', '_', 'G')}"
  file { $path:
    ensure  => $p['ensure'] ? { 'present' => file, default => absent },
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('network/lines.epp', {
      header => network::header($p['source'], "ifupdown, interface ${dev} (inspect: ifquery ${dev}; ip rule)"),
      lines  => $stanza.filter |$l| { $l =~ NotUndef },
    }),
  }

  network::activate { $title:
    profile => $p,
    files   => [File[$path]],
    command => $network::ifupdown_reload_command.lest || { "ifdown '${dev}'; ifup '${dev}'" },
  }
}
