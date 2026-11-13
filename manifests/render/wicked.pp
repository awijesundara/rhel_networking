# @summary Write SUSE wicked files: /etc/sysconfig/network/ifcfg-<dev>, ifroute-<dev>, ifrule-<dev>.
# @api private
#
# Reference: `man ifcfg`, `man ifroute`, `man ifcfg-bonding`, `man ifcfg-bridge`, `man ifcfg-vlan`.
# DNS is global on SUSE (NETWORKIG_DNS_STATIC_SERVERS in /etc/sysconfig/network/config).
define network::render::wicked (
  Hash $profile,
  Hash $overrides = {},
) {
  assert_private()

  $p      = $profile
  $dev    = $p['device']
  $dir    = $network::ifcfg_dir
  $header = network::header($p['source'], "wicked, interface ${dev} (inspect: wicked show-config ${dev}; ip rule)")

  # --- device -------------------------------------------------------------
  $type_keys = $p['type'] ? {
    # Unlike RHEL, SUSE lists the bond/bridge members on the controller.
    'bond'       => {
      'BONDING_MASTER'      => true,
      'BONDING_MODULE_OPTS' => $p['bond_options'].map |$k, $v| { "${k}=${v}" }.join(' '),
    } + Hash($p['ports'].map |$i, $port| { ["BONDING_SLAVE_${i}", $port] }),
    'vlan'       => { 'ETHERDEVICE' => $p['vlan_parent'], 'VLAN_ID' => $p['vlan_id'] },
    'bridge'     => {
      'BRIDGE'              => true,
      'BRIDGE_PORTS'        => $p['ports'],
      'BRIDGE_STP'          => $p['bridge_options']['stp'] ? { true => 'on', false => 'off', default => undef },
      'BRIDGE_FORWARDDELAY' => $p['bridge_options']['forward-delay'],
    },
    'infiniband' => { 'IPOIB_MODE' => $p['infiniband_mode'] },
    default      => {},
  }

  # --- layer 3 ------------------------------------------------------------
  if $p['port'] =~ NotUndef {
    # Bond/bridge members: no addresses, brought up together with the controller.
    $startmode = 'hotplug'
    $bootproto = 'none'
    $addresses = {}
    $routes    = []
    $rules     = []
    $ipv6_settings = {}
    $sysctl_lines = []
  } else {
    $v4 = $p['ipv4']
    $v6 = $p['ipv6']
    $startmode = $p['autoconnect'] ? { true => 'auto', default => 'manual' }
    # Wicked permits static addresses alongside any dynamic BOOTPROTO.
    # Keep the two families independent: static IPv4 must not suppress DHCPv6.
    $protocols = [
      $v4['method'] ? { 'auto' => 'dhcp4', 'link-local' => 'autoip', default => undef },
      $v6['method'] ? { 'auto' => 'dhcp6+auto6', 'dhcp' => 'dhcp6', default => undef },
    ].filter |$protocol| { $protocol =~ NotUndef }
    $bootproto = $protocols.empty ? { true => 'static', default => $protocols.join('+') }
    if $p['ensure'] == 'present' {
      if $v4['ignore_auto_routes'] or $v6['ignore_auto_routes'] or $v4['ignore_auto_dns'] or $v6['ignore_auto_dns'] {
        fail("${p['source']}: wicked cannot express ipv4/ipv6_ignore_auto_routes or ignore_auto_dns; use a NetworkManager backend")
      }
      if $v6['never_default'] and $v6['method'] in ['auto', 'dhcp'] {
        fail("${p['source']}: wicked cannot express ipv6_never_default with automatic IPv6; use static addressing or a NetworkManager backend")
      }
    }
    $dhcp4 = $v4['method'] == 'auto'
    $ipv6_settings = {
      'DHCLIENT6_MODE'             => $v6['method'] ? { 'auto' => 'auto', 'dhcp' => 'managed', default => undef },
      # Verified with `wicked show-config`: removes default-route from the DHCP update list,
      # and sets the priority (metric) of DHCP routes.
      'DHCLIENT_SET_DEFAULT_ROUTE' => ($dhcp4 and $v4['never_default']) ? { true => false, default => undef },
      'DHCLIENT_ROUTE_PRIORITY'    => $dhcp4 ? { true => $v4['route_metric'], default => undef },
    }
    # Wicked reads system sysctl files while building its configuration and applies
    # these values on ifreload, including for virtual interfaces not created yet.
    # Slash notation preserves dots in VLAN interface names.
    $sysctl_prefix = "net/ipv6/conf/${dev}"
    $sysctl_lines = [
      "${sysctl_prefix}/disable_ipv6 = ${$v6['method'] ? { 'disabled' => 1, default => 0 }}",
      "${sysctl_prefix}/accept_ra = ${$v6['method'] ? { 'auto' => 2, 'dhcp' => 2, default => 0 }}",
      "${sysctl_prefix}/autoconf = ${$v6['method'] ? { 'auto' => 1, default => 0 }}",
    ]
    $addresses = Hash(($v4['addresses'] + $v6['addresses']).map |$i, $a| { ["IPADDR_${i}", $a] })

    if !($v4['dns'] + $v6['dns']).empty {
      warning("${p['source']}: wicked reads DNS from /etc/sysconfig/network/config; 'dns' is ignored here")
    }

    # ifroute: "DESTINATION GATEWAY NETMASK DEVICE [OPTIONS]", '-' = not set.
    # As in NetworkManager, the connection's route metric applies to every route without its own.
    $default_routes = [[$v4, '0.0.0.0/0'], [$v6, '::/0']].filter |$f| { $f[0]['gateway'] =~ NotUndef and !$f[0]['never_default'] }
      .map |$f| {
        regsubst(network::wicked_route({ 'destination' => $f[1], 'gateway' => $f[0]['gateway'], 'metric' => $f[0]['route_metric'] }
          .filter |$k, $v| { $v =~ NotUndef }, $dev), '\\A\\S+', 'default')
      }
    $all_routes = $v4['routes'].map |$r| { ($r['metric'] =~ Undef and $v4['route_metric'] =~ NotUndef) ? { true => $r + { 'metric' => $v4['route_metric'] }, default => $r } }
      + $v6['routes'].map |$r| { ($r['metric'] =~ Undef and $v6['route_metric'] =~ NotUndef) ? { true => $r + { 'metric' => $v6['route_metric'] }, default => $r } }
    $routes = $default_routes + network::annotated($all_routes, $all_routes.map |$r| { network::wicked_route($r, $dev) })
    # ifrule: "ipv4|ipv6 <ip rule arguments>"
    $all_rules = $v4['rules'] + $v6['rules']
    $rules = network::annotated($all_rules, $all_rules.map |$r| { "${network::rule_family($r)} ${network::ip_rule($r)}" })
  }

  $settings = {
    'NAME'            => $p['id'],
    'STARTMODE'       => $startmode,
    'BOOTPROTO'       => $bootproto,
    'MTU'             => $p['mtu'],
    'LLADDR'          => $p['mac_address'],
    'ZONE'            => $p['zone'],
    'ETHTOOL_OPTIONS' => $p['ethtool_opts'],
  } + $addresses + $type_keys + $ipv6_settings + $overrides

  # --- write files --------------------------------------------------------
  $present = $p['ensure'] == 'present'
  $contents = {
    "${dir}/ifcfg-${dev}"   => [$present, epp('network/shellvars.epp', { header => $header, settings => $settings })],
    "${dir}/ifroute-${dev}" => [$present and !$routes.empty, epp('network/lines.epp', { header => $header, lines => $routes })],
    "${dir}/ifrule-${dev}"  => [$present and !$rules.empty, epp('network/lines.epp', { header => $header, lines => $rules })],
    "/etc/sysctl.d/90-network-${p['id']}.conf" => [$present and !$sysctl_lines.empty, epp('network/lines.epp', {
      header => $header,
      lines  => $sysctl_lines,
    })],
  }
  $files = $contents.map |$path, $spec| {
    file { $path:
      ensure  => $spec[0] ? { true => file, default => absent },
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => $spec[1],
    }
    File[$path]
  }

  network::activate { $title:
    profile => $p,
    files   => $files,
    command => "wicked ifreload '${dev}'",
  }
}
