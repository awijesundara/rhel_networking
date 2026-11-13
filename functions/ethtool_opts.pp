# @summary Translate keyfile-style ethtool settings into ifcfg ETHTOOL_OPTS, e.g.
#   { 'ring-rx' => 4096, 'coalesce-rx-usecs' => 0, 'feature-gro' => false }
#   -> "-G eth0 rx 4096; -C eth0 rx-usecs 0; -K eth0 gro off".
#   Read by NetworkManager's ifcfg-rh plugin and by the legacy network service.
# `nm`: NetworkManager's ifcfg reader wants adaptive coalescing as 0/1 (it rejects the whole
#   profile otherwise); the legacy network service runs ethtool itself, which wants on/off.
function network::ethtool_opts(String[1] $dev, Hash $ethtool, Boolean $nm) >> Optional[String] {
  $groups = { 'feature' => '-K', 'ring' => '-G', 'coalesce' => '-C', 'pause' => '-A', 'channels' => '-L', 'eee' => '--set-eee' }
  $parts = $groups.map |$prefix, $flag| {
    $args = $ethtool.filter |$k, $v| { $k =~ "\\A${prefix}-" }.map |$k, $v| {
      $name = regsubst($k, "\\A${prefix}-", '')
      # Switches (features, pause, eee, adaptive coalescing) take on/off; the rest are numbers.
      $enabled = String($v) =~ /\A(true|1|on|yes)\z/
      $value = ($prefix in ['feature', 'pause', 'eee']) ? {
        true    => $enabled ? { true => 'on', default => 'off' },
        default => ($name =~ /\Aadaptive-/) ? {
          true    => $nm ? { true => ($enabled ? { true => '1', default => '0' }), default => ($enabled ? { true => 'on', default => 'off' }) },
          default => String($v),
        },
      }
      "${name} ${value}"
    }
    $args.empty ? { true => undef, default => "${flag} ${dev} ${args.join(' ')}" }
  }.filter |$x| { $x =~ NotUndef }
  $parts.empty ? { true => undef, default => $parts.join('; ') }
}
