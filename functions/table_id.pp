# @summary Resolve a route table reference (number or name) to its numeric id.
function network::table_id(Network::Table $table) >> Integer {
  $builtin = { 'main' => 254, 'local' => 255, 'default' => 253 }
  if $table =~ Integer {
    $table
  } elsif $table in $network::all_route_tables {
    $network::all_route_tables[$table]
  } elsif $table in $builtin {
    $builtin[$table]
  } else {
    fail("network: route table '${table}' is not defined in network::route_tables or network::routing_tables")
  }
}
