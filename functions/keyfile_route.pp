# @summary Render one route as keyfile keys: routeN and (optionally) routeN_options.
function network::keyfile_route(Integer[1] $index, Network::Route $route) >> Hash[String, String] {
  $family = network::family($route['destination'])
  $plen   = $family ? { 'ipv6' => 128, default => 32 }
  $none   = $family ? { 'ipv6' => '::', default => '0.0.0.0' }
  $dest   = ('/' in $route['destination']) ? {
    true    => $route['destination'],
    default => "${route['destination']}/${plen}",
  }
  $gateway = $route['gateway'] ? { undef => $none, default => $route['gateway'] }

  $value = $route['metric'] ? {
    undef   => $route['gateway'] ? { undef => $dest, default => "${dest},${gateway}" },
    default => "${dest},${gateway},${route['metric']}",
  }

  $extra = $route['options'] ? { undef => {}, default => $route['options'] }
  $opts = ({
    'table'  => $route['table'] ? { undef => undef, default => network::table_id($route['table']) },
    'src'    => $route['src'],
    'onlink' => $route['onlink'],
    'mtu'    => $route['mtu'],
    'type'   => $route['type'],
  } + $extra).filter |$k, $v| { $v =~ NotUndef }

  if $opts.empty {
    { "route${index}" => $value }
  } else {
    {
      "route${index}"         => $value,
      "route${index}_options" => $opts.map |$k, $v| { "${k}=${network::keyfile_value($v)}" }.join(','),
    }
  }
}
