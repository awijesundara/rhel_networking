# @summary Render one route in `ip route` syntax (ifcfg route-/route6- files).
function network::ip_route(Network::Route $route, Optional[String[1]] $dev = undef) >> String {
  $special = $route['type'] =~ NotUndef and $route['type'] != 'unicast'
  $extra   = $route['options'] ? { undef => {}, default => $route['options'] }
  $tokens  = [
    $special ? { true => $route['type'], default => undef },
    $route['destination'],
    $route['gateway'] ? { undef => undef, default => "via ${route['gateway']}" },
    ($dev =~ NotUndef and !$special) ? { true => "dev ${dev}", default => undef },
    $route['table'] ? { undef => undef, default => "table ${network::table_id($route['table'])}" },
    $route['metric'] ? { undef => undef, default => "metric ${route['metric']}" },
    $route['src'] ? { undef => undef, default => "src ${route['src']}" },
    $route['mtu'] ? { undef => undef, default => "mtu ${route['mtu']}" },
  ] + $extra.map |$k, $v| { "${k} ${v}" } + [
    $route['onlink'] ? { true => 'onlink', default => undef },
  ]
  $tokens.filter |$t| { $t =~ NotUndef }.join(' ')
}
