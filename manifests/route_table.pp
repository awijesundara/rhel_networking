# @summary A named routing table in /etc/iproute2/rt_tables.d.
define network::route_table (
  Integer[1, 4294967295]    $id,
  Enum['present', 'absent'] $ensure = 'present',
  Pattern[/\A[A-Za-z_][\w.-]*\z/] $table_name = $title,
) {
  include network

  ensure_resource('file', ['/etc/iproute2', $network::rt_tables_dir], {
    'ensure' => 'directory', 'owner' => 'root', 'group' => 'root', 'mode' => '0755',
  })
  file { "${network::rt_tables_dir}/${table_name}.conf":
    ensure  => $ensure ? { 'present' => file, default => absent },
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "${network::header("Network::Route_table[${title}]", "ip / iproute2, maps table number to name (inspect: ip route show table ${table_name})")}${id}\t${table_name}\n",
  }
}
