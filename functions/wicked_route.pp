# @summary Render one route in SUSE ifroute-<if> syntax: DEST GATEWAY NETMASK DEVICE [OPTIONS].
function network::wicked_route(Network::Route $route, String[1] $dev) >> String {
  $extra = $route['options'] ? { undef => {}, default => $route['options'] }
  $opts  = [
    $route['table'] ? { undef => undef, default => "table ${network::table_id($route['table'])}" },
    $route['metric'] ? { undef => undef, default => "metric ${route['metric']}" },
    $route['src'] ? { undef => undef, default => "src ${route['src']}" },
    $route['mtu'] ? { undef => undef, default => "mtu ${route['mtu']}" },
    $route['type'] ? { undef => undef, 'unicast' => undef, default => "type ${route['type']}" },
    $route['onlink'] ? { true => 'onlink', default => undef },
  ] + $extra.map |$k, $v| { "${k} ${v}" }
  $gw = $route['gateway'] ? { undef => '-', default => $route['gateway'] }
  ([$route['destination'], $gw, '-', $dev] + $opts).filter |$t| { $t =~ NotUndef }.join(' ')
}
