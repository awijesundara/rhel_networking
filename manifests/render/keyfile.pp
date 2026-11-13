# @summary Write a NetworkManager keyfile (/etc/NetworkManager/system-connections/<id>.nmconnection).
# @api private
#
# Reference: `man nm-settings-keyfile`. Each hash below is one [section] of the file.
define network::render::keyfile (
  Hash $profile,
  Hash $overrides = {},
) {
  assert_private()

  $p      = $profile
  $legacy = $network::nm_legacy_port_keys   # NM < 1.46 spells controller/port as master/slave

  # [connection]
  $port_keys = $p['port'] ? {
    undef   => {},
    default => $legacy ? {
      true    => { 'master' => $p['port']['controller'], 'slave-type' => $p['port']['type'] },
      default => { 'controller' => $p['port']['controller'], 'port-type' => $p['port']['type'] },
    },
  }
  $autoconnect_ports = ($p['type'] in ['bond', 'bridge']) ? {
    true    => $legacy ? { true => { 'autoconnect-slaves' => 1 }, default => { 'autoconnect-ports' => 1 } },
    default => {},
  }
  $connection = {
    'id'                   => $p['id'],
    'uuid'                 => $p['uuid'],
    'type'                 => $p['type'],
    'interface-name'       => $p['device'],
    'autoconnect'          => $p['autoconnect'],
    'autoconnect-priority' => $p['autoconnect_priority'],
    'zone'                 => $p['zone'],
  } + $port_keys + $autoconnect_ports

  # Type specific sections. For physical NICs the MAC matches the device;
  # for virtual devices (bond, vlan, bridge) it sets the device's MAC.
  $type_sections = $p['type'] ? {
    'ethernet'   => { 'ethernet' => { 'mac-address' => $p['mac_address'], 'mtu' => $p['mtu'] } },
    'infiniband' => {
      'infiniband' => { 'mac-address' => $p['mac_address'], 'mtu' => $p['mtu'], 'transport-mode' => $p['infiniband_mode'] },
    },
    'bond'       => {
      'ethernet' => { 'cloned-mac-address' => $p['mac_address'], 'mtu' => $p['mtu'] },
      'bond'     => $p['bond_options'],
    },
    'vlan'       => {
      'ethernet' => { 'cloned-mac-address' => $p['mac_address'], 'mtu' => $p['mtu'] },
      'vlan'     => { 'id' => $p['vlan_id'], 'parent' => $p['vlan_parent'] },
    },
    'bridge'     => {
      'ethernet' => { 'mtu' => $p['mtu'] },
      'bridge'   => { 'mac-address' => $p['mac_address'] } + $p['bridge_options'],
    },
    'dummy'      => { 'ethernet' => { 'cloned-mac-address' => $p['mac_address'], 'mtu' => $p['mtu'] } },
  }
  $bridge_port = ($p['port'] =~ NotUndef and $p['port']['type'] == 'bridge') ? {
    true    => { 'bridge-port' => $p['port']['bridge_options'] },
    default => {},
  }
  $ethtool = $p['ethtool'].empty ? { true => {}, default => { 'ethtool' => $p['ethtool'] } }

  # [ipv4] / [ipv6]
  $ip = $p['port'] ? {
    undef   => {
      'ipv4' => network::keyfile_ip_section($p['ipv4']) + {
        'dns-search' => $p['ipv4']['dns_search'].empty ? { true => undef, default => $p['ipv4']['dns_search'] },
      },
      'ipv6' => network::keyfile_ip_section($p['ipv6']) + { 'addr-gen-mode' => $p['ipv6']['addr_gen_mode'] },
    },
    default => {},
  }

  # Merge user overrides last, section by section. An override value of undef removes the key.
  $generated = { 'connection' => $connection } + $type_sections + $bridge_port + $ethtool + $ip
  $sections  = $overrides.reduce($generated) |$merged, $section| {
    $merged + { $section[0] => ($merged[$section[0]].lest || { {} }) + $section[1] }
  }

  # Keyfile keys like route1 / routing-rule1 cannot carry comments, so explain them in the header.
  $notes = $p['port'] ? {
    undef   => ['ipv4', 'ipv6'].map |$family| {
      $p[$family]['routes'].map |$i, $r| { network::comment($r).then |$c| { "[${family}] route${$i + 1}: ${c[2, -1]}" } } +
      $p[$family]['rules'].map |$i, $r| { network::comment($r).then |$c| { "[${family}] routing-rule${$i + 1}: ${c[2, -1]}" } }
    }.flatten.filter |$n| { $n =~ NotUndef },
    default => ["This is a port of ${p['port']['controller']}; IP settings live on ${p['port']['controller']}."],
  }

  $path = "${network::keyfile_dir}/${p['id']}.nmconnection"
  file { $path:
    ensure  => $p['ensure'] ? { 'present' => file, default => absent },
    owner   => 'root',
    group   => 'root',
    mode    => '0600',   # NetworkManager ignores keyfiles readable by others
    content => epp('network/ini.epp', {
      header   => network::header($p['source'], "NetworkManager (inspect: nmcli connection show '${p['id']}')", ['uuid is stable across Puppet runs'] + $notes),
      sections => $sections,
    }),
    notify  => Exec['network: nmcli connection reload'],
  }

  # When migrating a RHEL host from ifcfg to keyfile, remove the old ifcfg files for this device.
  if $network::remove_foreign_files and $p['device'] =~ NotUndef and $network::family == 'RedHat' and $network::major < 10 {
    $old = ['ifcfg', 'route', 'route6', 'rule', 'rule6'].map |$kind| { "${network::ifcfg_dir}/${kind}-${p['file_name']}" }
    ensure_resource('file', $old, { ensure => absent, notify => Exec['network: nmcli connection reload'] })
  }

  network::activate { $title:
    profile => $p,
    files   => [File[$path]],
    command => $p['activation'] ? {
      'reapply' => "nmcli device reapply '${p['device']}'",
      default   => "nmcli connection up uuid '${p['uuid']}'",
    },
  }
}
