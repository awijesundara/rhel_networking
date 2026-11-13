# @summary One network connection (an interface, bond, VLAN, bridge, ...).
#
# How it works, in three steps:
#   1. Validate the parameters (fail early with a clear message).
#   2. Build one "profile" hash with every default resolved.
#   3. Hand the profile to the renderer for the active backend:
#        keyfile                 -> network::render::keyfile   (NetworkManager .nmconnection)
#        ifcfg / network_scripts -> network::render::ifcfg     (RHEL ifcfg-/route-/rule- files)
#        ifupdown                -> network::render::ifupdown  (Debian/Ubuntu interfaces.d)
#        wicked                  -> network::render::wicked    (SUSE ifcfg-/ifroute-/ifrule-)
#        netplan                 -> network::render::netplan   (Ubuntu /etc/netplan)
#
# @param ensure present or absent. absent removes the files (and NM forgets the profile).
# @param id Connection name (NM `connection.id` / ifcfg NAME). Also the keyfile name.
# @param interface_name Kernel device name. Defaults to the title, except that keyfile physical
#   connections with mac_address and no interface_name bind by MAC only.
# @param file_name Suffix of ifcfg-/route-/rule- files. Defaults to interface_name, then id.
# @param uuid Connection UUID. Defaults to a stable UUID derived from the host FQDN and id.
# @param mac_address Match MAC (ethernet/infiniband) or cloned MAC (bond/vlan/bridge).
# @param controller Name of the bond/bridge this connection is a port of. Ports carry no IP config.
# @param port_type Kind of controller: bond or bridge.
# @param bond_options Bonding options, e.g. { mode => '802.3ad', miimon => 100, xmit_hash_policy => 'layer3+4' }.
# @param bridge_options NM bridge property names, e.g. { stp => false, 'forward-delay' => 0 }.
# @param bridge_port_options NM bridge-port property names, e.g. { priority => 32, 'path-cost' => 100 }.
# @param ipv4_method Defaults to manual when ipv4_addresses are given, otherwise auto.
# @param ipv4_route_table Table for all routes of this connection that don't set their own (NM only).
# @param ipv6_method Defaults to manual when ipv6_addresses are given, otherwise network::ipv6_default_method.
# @param dns Nameservers of either family.
# @param routes Static routes of either family; family is taken from the destination.
# @param rules Policy routing rules of either family.
# @param keyfile_settings Raw keyfile overrides { section => { key => value } }, merged last. A value of undef deletes the key.
# @param ifcfg_settings Raw ifcfg overrides { KEY => value }, merged last. A value of undef deletes the key.
# @param ports Member interfaces, for backends that list ports on the controller (ifupdown bridges, wicked bonds/bridges).
#   network::bond and network::bridge fill this in.
# @param netplan_settings Raw keys merged last into this device's netplan mapping, e.g. { 'optional' => true }.
# @param ifupdown_settings Extra raw lines for the ifupdown inet stanza (pre-up, post-up, ...).
# @param activation Overrides network::activation for this connection.
define network::connection (
  Enum['present', 'absent']                        $ensure                    = 'present',
  Network::ConnectionId                            $id                        = $title,
  Network::ConnectionType                          $type                      = 'ethernet',
  Optional[Network::Ifname]                        $interface_name            = undef,
  Optional[Pattern[/\A[A-Za-z0-9_][A-Za-z0-9_.@-]*\z/]] $file_name           = undef,
  Optional[Pattern[/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/]] $uuid             = undef,
  Boolean                                          $autoconnect               = true,
  Optional[Integer[-999, 999]]                     $autoconnect_priority      = undef,
  Optional[Stdlib::MAC]                            $mac_address               = undef,
  Optional[Integer[68, 65535]]                     $mtu                       = undef,
  Optional[Pattern[/\A[A-Za-z0-9_-]+\z/]]          $zone                      = undef,
  # ports
  Optional[Network::Ifname]                        $controller                = undef,
  Optional[Enum['bond', 'bridge']]                 $port_type                 = undef,
  # type specific
  Hash[Network::OptionKey, Network::OptionValue]   $bond_options              = {},
  Optional[Integer[0, 4094]]                       $vlan_id                   = undef,
  Optional[Network::Ifname]                        $vlan_parent               = undef,
  Hash[Network::OptionKey, Network::OptionValue]   $bridge_options            = {},
  Hash[Network::OptionKey, Network::OptionValue]   $bridge_port_options       = {},
  Optional[Enum['datagram', 'connected']]          $infiniband_transport_mode = undef,
  # IPv4
  Optional[Network::Ipv4Method]                    $ipv4_method               = undef,
  Array[Stdlib::IP::Address::V4::CIDR]             $ipv4_addresses            = [],
  Optional[Stdlib::IP::Address::V4::Nosubnet]      $ipv4_gateway              = undef,
  Optional[Integer[-1, 4294967295]]                $ipv4_route_metric         = undef,
  Optional[Network::Table]                         $ipv4_route_table          = undef,
  Boolean                                          $ipv4_never_default        = false,
  Optional[Boolean]                                $ipv4_may_fail             = undef,
  Boolean                                          $ipv4_ignore_auto_dns      = false,
  Boolean                                          $ipv4_ignore_auto_routes   = false,
  # IPv6
  Optional[Network::Ipv6Method]                    $ipv6_method               = undef,
  Array[Stdlib::IP::Address::V6::CIDR]             $ipv6_addresses            = [],
  Optional[Stdlib::IP::Address::V6::Nosubnet]      $ipv6_gateway              = undef,
  Optional[Integer[-1, 4294967295]]                $ipv6_route_metric         = undef,
  Optional[Network::Table]                         $ipv6_route_table          = undef,
  Boolean                                          $ipv6_never_default        = false,
  Optional[Boolean]                                $ipv6_may_fail             = undef,
  Boolean                                          $ipv6_ignore_auto_dns      = false,
  Boolean                                          $ipv6_ignore_auto_routes   = false,
  Optional[Enum['eui64', 'stable-privacy', 'default', 'default-or-eui64']] $ipv6_addr_gen_mode        = undef,
  # common L3
  Array[Stdlib::IP::Address::Nosubnet]             $dns                       = [],
  Array[Pattern[/\A[A-Za-z0-9_.-]+\z/]]           $dns_search                = [],
  Array[Network::Route]                            $routes                    = [],
  Array[Network::Rule]                             $rules                     = [],
  # ethtool (keyfile [ethtool] keys, e.g. { 'ring-rx' => 4096, 'feature-tso' => false }); translated to ETHTOOL_OPTS on ifcfg
  Hash[Network::OptionKey, Network::OptionValue]   $ethtool                   = {},
  Optional[Pattern[/\A[A-Za-z0-9 _.:;,\/+-]+\z/]]  $ethtool_opts              = undef,
  Array[Network::Ifname]                           $ports                     = [],
  # escape hatches
  Array[String[1]]                                 $ifupdown_settings         = [],
  Hash[Pattern[/\A[A-Za-z0-9_.-]+\z/], Hash[Pattern[/\A[A-Za-z0-9_.-]+\z/], Any]] $keyfile_settings = {},
  Hash[Pattern[/\A[A-Za-z_][A-Za-z0-9_]*\z/], Any] $ifcfg_settings            = {},
  Hash[String[1], Any]                             $netplan_settings          = {},
  Optional[Network::Activation]                    $activation                = undef,
) {

  include network

  $backend = $network::backend
  $is_port = $controller =~ NotUndef
  $device = $interface_name.lest || {
    ($backend == 'keyfile' and $type in ['ethernet', 'infiniband'] and $mac_address =~ NotUndef) ? {
      true    => undef,
      default => $title,
    }
  }

  # ---------------------------------------------------------------------------
  # 1. Validation
  # ---------------------------------------------------------------------------
  if $title =~ /[\r\n]/ {
    fail('network::connection: the resource title must not contain line breaks')
  }
  $where = "network::connection[${title}]"
  if $is_port and $port_type =~ Undef {
    fail("${where}: port_type (bond or bridge) is required when controller is set")
  }
  $has_l3 = !($ipv4_addresses.empty and $ipv6_addresses.empty and $routes.empty and $rules.empty and $dns.empty)
    or $ipv4_gateway =~ NotUndef or $ipv6_gateway =~ NotUndef
  if $is_port and $has_l3 {
    fail("${where}: this is a port of ${controller}; put IP addresses, gateways, DNS, routes and rules on ${controller} instead")
  }
  if $type == 'vlan' and ($vlan_id =~ Undef or $vlan_parent =~ Undef) {
    fail("${where}: a vlan needs both vlan_id and vlan_parent")
  }
  if $device =~ Undef and $backend != 'keyfile' {
    fail("${where}: the ${backend} backend needs interface_name")
  }
  if $type == 'dummy' and $backend != 'keyfile' {
    fail("${where}: dummy interfaces are only supported by the keyfile backend")
  }
  if $device =~ NotUndef and $device !~ Network::Ifname {
    fail("${where}: '${device}' is not a valid interface name (up to 15 letters, digits, '_', '.', '-'); set interface_name")
  }
  if $ipv6_addr_gen_mode =~ Pattern[/\Adefault/] and $backend != 'keyfile' {
    fail("${where}: ipv6_addr_gen_mode '${ipv6_addr_gen_mode}' is only supported by the keyfile backend (NetworkManager >= 1.40)")
  }
  # NetworkManager rejects a profile with an unknown [ethtool] key, so catch typos here.
  $bad_ethtool = $ethtool.keys.filter |$k| { $k !~ /\A(feature|ring|coalesce|pause|channels|eee)-[a-z0-9-]+\z/ }
  unless $bad_ethtool.empty {
    fail("${where}: unknown ethtool setting(s) ${bad_ethtool.join(', ')}; keys start with feature-, ring-, coalesce-, pause-, channels- or eee-")
  }
  if !$ethtool.empty and !($backend in ['keyfile', 'netplan', 'ifcfg', 'network_scripts']) {
    warning("${where}: 'ethtool' is not rendered by ${backend}; use 'ethtool_opts'")
  }

  # ---------------------------------------------------------------------------
  # 2. Build the profile: every default is decided here, once.
  # ---------------------------------------------------------------------------
  $ipv4_method_final = $ipv4_method ? {
    undef   => $ipv4_addresses.empty ? { true => 'auto', default => 'manual' },
    default => $ipv4_method,
  }
  $ipv6_method_wanted = $ipv6_method ? {
    undef   => $ipv6_addresses.empty ? { true => $network::ipv6_default_method, default => 'manual' },
    default => $ipv6_method,
  }
  # RHEL 7 ships NetworkManager 1.18, which has no ipv6.method=disabled (added in 1.20).
  # The closest it offers is 'ignore': NetworkManager leaves IPv6 on the interface alone.
  # To really switch IPv6 off there, also set net.ipv6.conf.all.disable_ipv6 in network::sysctl.
  $ipv6_method_final = ($ipv6_method_wanted == 'disabled' and $network::rhel and $network::major == 7) ? {
    true    => 'ignore',
    default => $ipv6_method_wanted,
  }
  if !$is_port and $ensure == 'present' {
    if $backend == 'ifupdown' and $ipv4_method_final in ['shared', 'link-local'] {
      fail("${where}: ipv4_method '${ipv4_method_final}' is not supported by ifupdown")
    }
    if $backend == 'ifupdown' and $ipv6_method_final in ['shared', 'link-local'] {
      fail("${where}: ipv6_method '${ipv6_method_final}' is not supported by ifupdown")
    }
    if $backend == 'wicked' and $ipv4_method_final == 'shared' {
      fail("${where}: ipv4_method 'shared' is not supported by wicked")
    }
    if $backend == 'wicked' and $ipv6_method_final in ['shared', 'ignore'] {
      fail("${where}: ipv6_method '${ipv6_method_final}' is not supported by wicked")
    }
  }
  # RHEL 7 ships NetworkManager 1.18, which cannot store a /0 route in a profile's route
  # list (keyfile turns it into /24, ifcfg drops it). Two /1 halves cover the same
  # addresses and win over any default route, so use them there. The legacy network
  # service handles /0 fine and is left alone.
  $split_default = $network::rhel and $network::major == 7 and $network::nm_managed
  $all_routes = $split_default ? {
    false   => $routes,
    default => $routes.map |$r| {
      $halves = $r['destination'] ? {
        /\A0\.0\.0\.0\/0\z/ => ['0.0.0.0/1', '128.0.0.0/1'],
        /\A::\/0\z/          => ['::/1', '8000::/1'],
        default             => undef,
      }
      $halves ? {
        undef   => [$r],
        default => $halves.map |$h| {
          $r + {
            'destination' => $h,
            'description' => "${r['description'].lest || { 'default route' }} (half ${h} of ${r['destination']}: RHEL 7 NetworkManager cannot store /0 routes)",
          }
        },
      }
    }.flatten,
  }
  $v4_routes = $all_routes.filter |$r| { network::family($r['destination']) == 'ipv4' }
  $v6_routes = $all_routes.filter |$r| { network::family($r['destination']) == 'ipv6' }
  $v4_dns    = $dns.filter |$d| { network::family($d) == 'ipv4' }
  $v6_dns    = $dns.filter |$d| { network::family($d) == 'ipv6' }

  # Combinations NetworkManager refuses to load (the profile would silently not appear in
  # `nmcli connection show`). They make no sense on the other backends either, so fail here.
  if !$is_port and $ensure == 'present' {
    if $ipv4_method_final == 'manual' and $ipv4_addresses.empty {
      fail("${where}: ipv4_method 'manual' needs at least one entry in ipv4_addresses")
    }
    if $ipv6_method_final == 'manual' and $ipv6_addresses.empty {
      fail("${where}: ipv6_method 'manual' needs at least one entry in ipv6_addresses")
    }
    if $ipv4_gateway =~ NotUndef and $ipv4_addresses.empty {
      fail("${where}: ipv4_gateway needs a static address in ipv4_addresses")
    }
    if $ipv6_gateway =~ NotUndef and $ipv6_addresses.empty {
      fail("${where}: ipv6_gateway needs a static address in ipv6_addresses")
    }
    if $ipv4_method_final == 'disabled' and !($ipv4_addresses.empty and $v4_routes.empty and $v4_dns.empty and $dns_search.empty) {
      fail("${where}: IPv4 is disabled on this connection but IPv4 addresses, routes, dns or dns_search are set")
    }
    if $ipv6_method_final in ['disabled', 'ignore'] and !($ipv6_addresses.empty and $v6_routes.empty and $v6_dns.empty) {
      fail("${where}: IPv6 is ${ipv6_method_final} on this connection but IPv6 addresses, routes or dns are set (set ipv6_method, or network::ipv6_default_method)")
    }
  }

  $profile = {
    'source'               => "Network::Connection[${title}]",
    'ensure'               => $ensure,
    'id'                   => $id,
    # The seed string is fixed: changing it would change every existing connection UUID.
    'uuid'                 => $uuid.lest || { network::uuid("netconf:${facts['networking']['fqdn']}:${id}") },
    'type'                 => $type,
    'device'               => $device,
    'file_name'            => [$file_name, $device, $id].filter |$x| { $x =~ NotUndef }[0],
    'autoconnect'          => $autoconnect,
    'autoconnect_priority' => $autoconnect_priority,
    'mac_address'          => $mac_address,
    'mtu'                  => $mtu,
    'zone'                 => $zone,
    'ethtool'              => $ethtool,
    'ethtool_opts'         => $ethtool_opts,
    'activation'           => $activation.lest || { $network::activation },
    # Set only when this connection is a member of a bond or bridge.
    'port'                 => $is_port ? {
      true    => { 'controller' => $controller, 'type' => $port_type, 'bridge_options' => $bridge_port_options },
      default => undef,
    },
    # Type specific settings.
    'ports'                => $ports,
    'bond_options'         => $bond_options,
    'bridge_options'       => $bridge_options,
    'vlan_id'              => $vlan_id,
    'vlan_parent'          => $vlan_parent,
    'infiniband_mode'      => $infiniband_transport_mode.lest || { 'datagram' },
    # Layer 3, split per address family. Ports get no layer 3 at all.
    'ipv4'                 => $is_port ? {
      true    => undef,
      default => {
        'method'             => $ipv4_method_final,
        'addresses'          => $ipv4_addresses,
        'gateway'            => $ipv4_gateway,
        'dns'                => $v4_dns,
        'dns_search'         => $dns_search,
        'routes'             => $v4_routes,
        'rules'              => $rules.filter |$r| { network::rule_family($r) == 'ipv4' },
        'route_metric'       => ($ipv4_route_metric == -1) ? { true => undef, default => $ipv4_route_metric },
        'route_table'        => $ipv4_route_table.then |$t| { network::table_id($t) },
        'never_default'      => $ipv4_never_default,
        'may_fail'           => $ipv4_may_fail,
        'ignore_auto_dns'    => $ipv4_ignore_auto_dns,
        'ignore_auto_routes' => $ipv4_ignore_auto_routes,
      },
    },
    'ipv6'                 => $is_port ? {
      true    => undef,
      default => {
        'method'             => $ipv6_method_final,
        'addresses'          => $ipv6_addresses,
        'gateway'            => $ipv6_gateway,
        'dns'                => $v6_dns,
        'routes'             => $v6_routes,
        'rules'              => $rules.filter |$r| { network::rule_family($r) == 'ipv6' },
        'route_metric'       => ($ipv6_route_metric == -1) ? { true => undef, default => $ipv6_route_metric },
        'route_table'        => $ipv6_route_table.then |$t| { network::table_id($t) },
        'never_default'      => $ipv6_never_default,
        'may_fail'           => $ipv6_may_fail,
        'ignore_auto_dns'    => $ipv6_ignore_auto_dns,
        'ignore_auto_routes' => $ipv6_ignore_auto_routes,
        'addr_gen_mode'      => $ipv6_addr_gen_mode,
      },
    },
  }

  if $profile['activation'] == 'reapply' and !$network::nm_managed {
    fail("${where}: activation 'reapply' needs a NetworkManager backend (keyfile or ifcfg)")
  }
  if $profile['activation'] == 'reapply' and $device =~ Undef {
    fail("${where}: activation 'reapply' requires interface_name; use 'up' for MAC-only matching")
  }

  # A VLAN sits on its parent: bring it up after the parent, and again whenever the parent is
  # restarted (restarting a parent removes the VLANs on top of it on the legacy service).
  if $type == 'vlan' {
    Exec <| tag == "network-device-${md5($vlan_parent)}" |> ~> Exec <| title == "network: activate ${id}" |>
  }

  # ---------------------------------------------------------------------------
  # 3. Render
  # ---------------------------------------------------------------------------
  case $backend {
    'keyfile': {
      network::render::keyfile { $title: profile => $profile, overrides => $keyfile_settings }
    }
    'ifcfg', 'network_scripts': {
      network::render::ifcfg { $title: profile => $profile, overrides => $ifcfg_settings }
    }
    'ifupdown': {
      network::render::ifupdown { $title: profile => $profile, extra_lines => $ifupdown_settings }
    }
    'netplan': {
      network::render::netplan { $title: profile => $profile, overrides => $netplan_settings }
    }
    'wicked': {
      network::render::wicked { $title: profile => $profile, overrides => $ifcfg_settings }
    }
    default: { fail("${where}: unknown backend ${backend}") }
  }
}
