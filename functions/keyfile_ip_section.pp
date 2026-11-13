# @summary Keys of a keyfile [ipv4] or [ipv6] section, built from one family of a profile.
function network::keyfile_ip_section(Hash $ip) >> Hash {
  $numbered = $ip['addresses'].map |$i, $a| { ["address${$i + 1}", $a] }
  $routes   = $ip['routes'].map |$i, $r| { network::keyfile_route($i + 1, $r) }.reduce({}) |$m, $h| { $m + $h }
  $rules    = $ip['rules'].map |$i, $r| { ["routing-rule${$i + 1}", network::ip_rule($r)] }

  ({ 'method' => $ip['method'] } + Hash($numbered) + {
    'gateway'            => $ip['gateway'],
    'dns'                => $ip['dns'].empty ? { true => undef, default => $ip['dns'] },
    'route-metric'       => $ip['route_metric'],
    'route-table'        => $ip['route_table'],
    # Only write booleans that differ from NetworkManager's defaults.
    'never-default'      => $ip['never_default'] ? { true => true, default => undef },
    'may-fail'           => $ip['may_fail'],
    'ignore-auto-dns'    => $ip['ignore_auto_dns'] ? { true => true, default => undef },
    'ignore-auto-routes' => $ip['ignore_auto_routes'] ? { true => true, default => undef },
  } + $routes + Hash($rules))
}
