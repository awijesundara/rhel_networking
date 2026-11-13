# @summary A bridge plus its port connections.
#
# @param ports Interface names to attach (use network::connection with controller for bonds/vlans).
# @param bridge_options Bridge settings (stp, priority, forward-delay, hello-time, max-age, ...).
# @param connection Extra network::connection parameters for the bridge itself (IPs, routes, rules, mtu, ...).
# @param port_defaults Extra network::connection parameters applied to every port.
# @param port_overrides Per-port parameters, keyed by interface name.
define network::bridge (
  Array[Network::Ifname, 1]       $ports,
  Hash[String[1], Scalar]         $bridge_options = { 'stp' => false },
  Enum['present', 'absent']       $ensure         = 'present',
  Hash[String[1], Any]            $connection     = {},
  Hash[String[1], Any]            $port_defaults  = {},
  Hash[String[1], Hash]           $port_overrides = {},
) {
  network::connection { $title:
    ensure         => $ensure,
    type           => 'bridge',
    ports          => $ports,
    bridge_options => $bridge_options,
    *              => $connection,
  }

  $ports.each |$port| {
    $override = $port_overrides[$port] ? { undef => {}, default => $port_overrides[$port] }
    network::connection { "${title}-port-${port}":
      ensure         => $ensure,
      type           => 'ethernet',
      interface_name => $port,
      controller     => $title,
      port_type      => 'bridge',
      *              => $port_defaults + $override,
    }
    # Bring the bridge up before (re)activating its ports.
    # (Collectors, because on some backends a port has no activation step of its own.)
    Network::Activate <| title == $title |> -> Network::Activate <| title == "${title}-port-${port}" |>
  }
}
