# @summary Physical bond member, named <bond>-<device>.
define network::bond_slave (
  Network::Ifname               $controller,
  Optional[Network::Ifname]     $interface_name = undef,
  Boolean                       $autoconnect    = true,
  Enum['present', 'absent']      $ensure         = 'present',
  Optional[String[1]]           $connection_id  = undef,
  Hash[String[1], Scalar]        $ethtool        = {},
) {
  include network

  $id = pick($connection_id, $title)
  network::connection { $title:
    id             => $id,
    uuid           => fqdn_uuid($id),
    interface_name => pick($interface_name, $title),
    controller     => $controller,
    port_type      => 'bond',
    autoconnect    => $autoconnect,
    ensure         => $ensure,
    ethtool        => $ethtool,
    activation     => 'none',
  }
}
