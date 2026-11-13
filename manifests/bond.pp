# @summary A bond plus its port connections.
#
# @param slaves Bond member interface names (flat parameters).
# @param reapply Flat API: reactivate after changes; false only reloads profiles.
# @param ports Physical interface names using the native API.
# @param ethtool Flat API: ethtool settings of the bond itself. Native API: settings of every port.
# @param bond_options Kernel bonding options (mode, miimon, lacp_rate, xmit_hash_policy, ...).
# @param connection Extra network::connection parameters for the bond itself (IPs, routes, rules, mtu, ...).
# @param port_defaults Extra network::connection parameters applied to every port.
# @param port_overrides Per-port parameters, keyed by interface name.
define network::bond (
  Optional[Array[Network::Ifname, 1]]             $ports                  = undef,
  Hash[String[1], Scalar]                         $bond_options           = { 'mode' => '802.3ad', 'miimon' => 100 },
  Enum['present', 'absent']                       $ensure                 = 'present',
  Hash[String[1], Any]                            $connection             = {},
  Hash[String[1], Any]                            $port_defaults          = {},
  Hash[String[1], Hash]                           $port_overrides         = {},
  Hash[String[1], Scalar]                         $ethtool                = {},
  Optional[Array[Network::Ifname, 1]]             $slaves                 = undef,
  Enum['manual', 'auto', 'disabled']              $ipv4_method            = 'manual',
  Optional[Variant[String, Array[String]]]        $ipv4_address           = undef,
  Optional[String]                                $ipv4_gateway           = undef,
  Array[String]                                   $ipv4_dns               = [],
  Optional[Integer]                               $ipv4_route_metric      = undef,
  Boolean                                         $ipv4_never_default     = false,
  Optional[Integer]                               $mtu                    = undef,
  String                                          $bond_mode              = '802.3ad',
  Integer                                         $bond_miimon            = 100,
  Optional[String]                                $bond_lacp_rate         = undef,
  Optional[String]                                $bond_xmit_hash_policy  = undef,
  Optional[String]                                $bond_primary           = undef,
  Optional[Integer]                               $bond_primary_reselect  = undef,
  Boolean                                         $autoconnect            = true,
  Array[Network::Route]                           $routes                 = [],
  Array[Network::Routing_rule]                    $routing_rules          = [],
  String                                          $ipv6_method            = 'auto',
  Boolean                                         $reapply                = false,
  Optional[String]                                $connection_id          = undef,
) {
  include network

  if $slaves =~ NotUndef {
    if $ports =~ NotUndef or !$connection.empty or !$port_defaults.empty or !$port_overrides.empty or $bond_options != { 'mode' => '802.3ad', 'miimon' => 100 } {
      fail('network::bond: slaves uses flat parameters; do not combine it with ports, connection, bond_options or port overrides')
    }
    $flat_options = {
      'mode' => $bond_mode,
      'miimon' => $bond_miimon,
      'lacp_rate' => $bond_lacp_rate,
      'xmit_hash_policy' => $bond_xmit_hash_policy,
      'primary' => $bond_primary,
      'primary_reselect' => $bond_primary_reselect,
    }.filter |$entry| { $entry[1] =~ NotUndef }
    $id = pick($connection_id, $title)
    network::connection { $title:
      id                 => $id,
      type               => 'bond',
      ports              => $slaves,
      bond_options       => $flat_options,
      uuid               => fqdn_uuid($id),
      interface_name     => $title,
      ipv4_method        => $ipv4_method,
      ipv4_addresses     => [$ipv4_address].flatten.filter |$address| { $address =~ NotUndef },
      ipv4_gateway       => $ipv4_gateway,
      dns                => $ipv4_dns,
      ipv4_route_metric  => $ipv4_route_metric,
      ipv4_never_default => $ipv4_never_default,
      mtu                => $mtu,
      autoconnect        => $autoconnect,
      ensure             => $ensure,
      routes             => $routes,
      rules              => $routing_rules,
      ipv6_method        => $ipv6_method,
      ipv6_addr_gen_mode => $network::flat_addr_gen_mode,
      # With flat parameters, ethtool applies to the bond itself, not to its members.
      ethtool            => $ethtool,
      activation         => $reapply ? { true => 'up', default => 'none' },
    }
    $slaves.each |$slave| {
      network::bond_slave { "${title}-${slave}":
        interface_name => $slave,
        controller     => $title,
        ensure         => $ensure,
        autoconnect    => $autoconnect,
      }
    }
  } elsif $ports =~ NotUndef {
    network::connection { $title:
      ensure       => $ensure,
      type         => 'bond',
      ports        => $ports,
      bond_options => $bond_options,
      *            => $connection,
    }

    $ports.each |$port| {
      $override = $port_overrides[$port] ? { undef => {}, default => $port_overrides[$port] }
      network::connection { "${title}-port-${port}":
        ensure         => $ensure,
        type           => 'ethernet',
        interface_name => $port,
        controller     => $title,
        port_type      => 'bond',
        ethtool        => $ethtool,
        *              => $port_defaults + $override,
      }
      # Bring the bond up before (re)activating its ports.
      # (Collectors, because on some backends a port has no activation step of its own.)
      Network::Activate <| title == $title |> -> Network::Activate <| title == "${title}-port-${port}" |>
    }
  } else {
    fail('network::bond: specify slaves (flat interface) or ports (native interface)')
  }
}
