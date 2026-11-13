# @summary One route as a netplan `routes` entry. The connection's route metric and table
#   apply to every route without its own, as they do in NetworkManager.
function network::netplan_route(Hash $ip, Network::Route $route) >> Hash {
  $plen = network::family($route['destination']) ? { 'ipv6' => 128, default => 32 }
  ({
    'to'      => ('/' in $route['destination']) ? { true => $route['destination'], default => "${route['destination']}/${plen}" },
    'via'     => $route['gateway'],
    'metric'  => $route['metric'].lest || { $ip['route_metric'] },
    'table'   => $route['table'].then |$t| { network::table_id($t) }.lest || { $ip['route_table'] },
    'from'    => $route['src'],
    'on-link' => $route['onlink'],
    'mtu'     => $route['mtu'],
    'type'    => $route['type'] ? { 'unicast' => undef, default => $route['type'] },
  } + ($route['options'].lest || { {} })).filter |$k, $v| { $v =~ NotUndef }
}
