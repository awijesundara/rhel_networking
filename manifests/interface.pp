# @summary Ethernet interface with flat parameters (the usual Hiera entry point).
# reapply means connection reactivation, matching the original API.
# ipv4_method defaults to manual when ipv4_address is set, otherwise auto (DHCP).
# A gateway with ipv4_never_default: true is kept for routes; no default route is added.
define network::interface (
  Optional[Enum['manual', 'auto', 'disabled']]    $ipv4_method            = undef,
  Optional[Variant[String, Array[String]]]        $ipv4_address           = undef,
  Optional[String]                                $ipv4_gateway           = undef,
  Array[String]                                   $ipv4_dns               = [],
  Optional[Integer]                               $ipv4_route_metric      = undef,
  Boolean                                         $ipv4_never_default     = false,
  Optional[Integer]                               $mtu                    = undef,
  Boolean                                         $autoconnect            = true,
  Enum['present', 'absent']                       $ensure                 = 'present',
  Array[Network::Route]                           $routes                 = [],
  Array[Network::Routing_rule]                    $routing_rules          = [],
  Hash                                            $ethtool                = {},
  String                                          $ipv6_method            = 'auto',
  Boolean                                         $reapply                = false,
  Optional[String]                                $connection_id          = undef,
) {
  include network

  $id = pick($connection_id, $title)
  network::connection { $title:
    id                 => $id,
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
    ethtool            => $ethtool,
    ipv6_method        => $ipv6_method,
    ipv6_addr_gen_mode => $network::flat_addr_gen_mode,
    activation         => $reapply ? { true => 'up', default => 'none' },
  }
}
