# @summary Manage Linux networking: NetworkManager (any distro), ifcfg/network-scripts (RHEL), netplan (Ubuntu), ifupdown (Debian), wicked (SUSE).
#
# @param backend
#   keyfile         - NetworkManager keyfiles (.nmconnection). RHEL 7-10. Default on 9/10.
#   ifcfg           - ifcfg files read by NetworkManager (ifcfg-rh). RHEL 7-9. Default on 7/8.
#   network_scripts - ifcfg files driven by the legacy `network` service (NM_CONTROLLED=no). RHEL 7/8.
#   ifupdown        - /etc/network/interfaces.d stanzas. Debian/Ubuntu (ifupdown or ifupdown2).
#   wicked          - /etc/sysconfig/network ifcfg/ifroute/ifrule files. SUSE.
#   netplan         - /etc/netplan/90-network-*.yaml, rendered by systemd-networkd or NetworkManager. Ubuntu, Debian.
# @param netplan_dir Directory of netplan files.
# @param netplan_file The one netplan file holding every managed device.
# @param netplan_state_dir Per-device copies used to activate only the devices that changed.
# @param netplan_renderer netplan backend daemon: networkd (Ubuntu Server) or NetworkManager (Ubuntu Desktop).
# @param ifupdown_reload_command
#   ifupdown only: run this instead of per-interface ifdown/ifup (e.g. 'ifreload -a' with ifupdown2).
# @param activation
#   Default activation for connections whose files change (see Network::Activation).
# @param nm_legacy_port_keys
#   Write master/slave-type/autoconnect-slaves instead of controller/port-type/autoconnect-ports.
# @param purge_connections
#   Remove connection files not managed by Puppet from the active backend's directory.
# @param remove_foreign_files
#   When a connection is written in one format, delete its file in the other format (eases ifcfg -> keyfile migration).
# @param nm_settings
#   Sections for /etc/NetworkManager/conf.d/99-network.conf, e.g. { main => { dns => 'none' } }.
# @param nm_conf_files
#   Extra conf.d files: { 'name.conf' => { section => { key => value } } }.
# @param interfaces Ethernet interfaces, created as network::interface resources.
# @param routing_tables ID-to-name mappings, managing /etc/iproute2/rt_tables.
# @param connections_dir NetworkManager keyfile directory (keyfile_dir is an override).
# @param service_ensure NetworkManager service state when manage_service is enabled.
# @param service_enable Whether NetworkManager is enabled at boot.
# @param route_tables
#   Named routing tables, written to rt_tables.d and usable by name in routes/rules.
# @param sysctl
#   Kernel parameters (e.g. rp_filter for policy routing) written to /etc/sysctl.d/90-network.conf.
# @param sysconfig_network
#   Full contents of /etc/sysconfig/network as KEY => value. Not managed when empty.
class network (
  Network::Backend                       $backend,
  Boolean                                $nm_legacy_port_keys,
  Network::Activation                    $activation           = 'none',
  Network::Ipv6Method                    $ipv6_default_method  = 'auto',
  String[1]                              $nm_package           = 'NetworkManager',
  Boolean                                $manage_packages      = true,
  Array[String[1]]                       $extra_packages       = [],
  Boolean                                $manage_service       = true,
  Enum['running', 'stopped']             $service_ensure       = 'running',
  Boolean                                $service_enable       = true,
  Stdlib::Absolutepath                   $connections_dir      = '/etc/NetworkManager/system-connections',
  Stdlib::Ensure::Service                $legacy_nm_ensure     = 'stopped',
  Stdlib::Absolutepath                   $keyfile_dir          = $connections_dir,
  Stdlib::Absolutepath                   $ifcfg_dir            = '/etc/sysconfig/network-scripts',
  Stdlib::Absolutepath                   $nm_conf_dir          = '/etc/NetworkManager/conf.d',
  Stdlib::Absolutepath                   $ifupdown_dir         = '/etc/network/interfaces.d',
  Optional[String[1]]                    $ifupdown_reload_command = undef,
  Stdlib::Absolutepath                   $netplan_dir          = '/etc/netplan',
  Enum['networkd', 'NetworkManager']     $netplan_renderer     = 'networkd',
  Stdlib::Absolutepath                   $netplan_file         = "${netplan_dir}/90-network.yaml",
  Stdlib::Absolutepath                   $netplan_state_dir    = '/var/lib/puppet-network/netplan',
  Stdlib::Absolutepath                   $rt_tables_dir        = '/etc/iproute2/rt_tables.d',
  Boolean                                $purge_connections    = false,
  Array[String[1]]                       $purge_ignore         = [
    'ifcfg-lo', 'ifup*', 'ifdown*', 'init.ipv6-global', 'network-functions*', 'readme-ifcfg-rh.txt',
  ],
  Boolean                                $remove_foreign_files = false,
  Hash[Pattern[/\A[A-Za-z0-9_.-]+\z/], Hash[Pattern[/\A[A-Za-z0-9_.-]+\z/], Any]] $nm_settings = {},
  Hash[Pattern[/\A[A-Za-z0-9][A-Za-z0-9_.-]*\.conf\z/], Hash[Pattern[/\A[A-Za-z0-9_.-]+\z/], Hash[Pattern[/\A[A-Za-z0-9_.-]+\z/], Any]]] $nm_conf_files = {},
  Hash[Pattern[/\A[A-Za-z_][\w.-]*\z/], Integer[1, 4294967295]] $route_tables = {},
  Hash[Pattern[/\A[A-Za-z0-9_.\/*-]+\z/], Variant[Integer, Pattern[/\A[^\r\n]*\z/]]] $sysctl = {},
  Hash[Pattern[/\A[A-Za-z_][A-Za-z0-9_]*\z/], Scalar] $sysconfig_network = {},
  Hash[String[1], Hash]                  $interfaces           = {},
  Hash[Variant[Integer[1, 4294967295], Pattern[/\A[1-9]\d*\z/]], Pattern[/\A[A-Za-z_][\w.-]*\z/]] $routing_tables = {},
  Hash[String[1], Hash]                  $connections          = {},
  Hash[String[1], Hash]                  $bonds                = {},
  Hash[String[1], Hash]                  $bridges              = {},
) {
  $family = $facts['os']['family']
  # Non-numeric releases (Debian testing reports e.g. 'trixie/sid') count as 0.
  $major  = $facts['os']['release']['major'] ? { /\A(\d+)/ => Integer($1), default => 0 }

  unless $facts['kernel'] == 'Linux' {
    fail("network: unsupported kernel ${facts['kernel']}")
  }
  # RHEL and its rebuilds (CentOS, Rocky, AlmaLinux, Oracle Linux, ...), but not Fedora or Amazon Linux.
  $rhel = $family == 'RedHat' and !($facts['os']['name'] in ['Fedora', 'Amazon'])
  $supported = $backend ? {
    'keyfile'         => true,
    'ifcfg'           => $rhel and $major in [7, 8, 9],
    'network_scripts' => $rhel and $major in [7, 8],
    'ifupdown'        => $family == 'Debian',
    'wicked'          => $family == 'Suse',
    'netplan'         => $family == 'Debian',
  }
  unless $supported {
    fail("network: backend '${backend}' is not available on ${facts['os']['name']} ${facts['os']['release']['full']}")
  }

  # routing_tables (ID-to-name) owns /etc/iproute2/rt_tables. Native
  # route_tables remains name-to-ID and writes independent rt_tables.d files.
  $compat_tables = $routing_tables.reduce({}) |$tables, $entry| {
    $tid = Integer($entry[0])
    $table_name = assert_type(Pattern[/\A[A-Za-z_][\w.-]*\z/], $entry[1])
    if $tid < 1 or $tid > 4294967295 or $tid in [253, 254, 255] or $table_name in ['unspec', 'default', 'main', 'local'] {
      fail('network::routing_tables: use non-reserved positive IDs and names')
    }
    if $table_name in $tables or $tid in $tables.values or $table_name in $route_tables or $tid in $route_tables.values {
      fail('network: routing_tables and route_tables must have unique names and IDs')
    }
    $tables + { $table_name => $tid }
  }
  $all_route_tables = $route_tables + $compat_tables

  $nm_managed = $backend == 'keyfile' or $backend == 'ifcfg'

  # Flat interface/bond keyfiles carry addr-gen-mode=default where NetworkManager
  # understands it (>= 1.40, i.e. RHEL 9 and later).
  $flat_addr_gen_mode = ($backend == 'keyfile' and $rhel and $major >= 9) ? { true => 'default', default => undef }

  contain network::install
  contain network::config
  contain network::service

  Class['network::install'] -> Class['network::config'] -> Class['network::service']

  if $nm_managed {
    # Every connection file change triggers a profile reload; activation execs run afterwards.
    exec { 'network: nmcli connection reload':
      command     => 'nmcli connection reload',
      path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      refreshonly => true,
      # With NetworkManager stopped (e.g. service_ensure: stopped) there is nothing to reload;
      # it reads the files when it starts.
      onlyif      => 'systemctl is-active --quiet NetworkManager',
      require     => Class['network::service'],
    }
  }

  if $backend == 'netplan' {
    concat { $netplan_file:
      owner   => 'root',
      group   => 'root',
      mode    => '0600',   # netplan warns about (and newer releases refuse) world-readable files
      # Check the new file together with the other netplan files in a scratch copy first,
      # so a file netplan cannot parse never replaces the working one.
      validate_cmd => $netplan_dir ? {
        '/etc/netplan' => "/bin/sh -c 'd=\$(mktemp -d) && mkdir \$d/etc && cp -a /etc/netplan \$d/etc/netplan && cp % \$d/etc/netplan/${basename($netplan_file)} && netplan generate --root-dir \$d; rc=\$?; rm -rf \$d; exit \$rc'",
        default        => undef,
      },
      require => Class['network::config'],
      notify  => Exec['network: netplan generate'],
    }
    concat::fragment { 'network: netplan header':
      target  => $netplan_file,
      order   => '00',
      content => "${network::header('Hiera network::interfaces / bonds / connections', 'netplan (inspect: netplan get; netplan status)')}network:\n  version: 2\n  renderer: ${netplan_renderer}\n",
    }
    # A changed netplan file is checked with `netplan generate` (it fails on invalid YAML or
    # settings); `netplan apply` then runs once for all connections that asked to be activated.
    exec { 'network: netplan generate':
      command     => 'netplan generate',
      path        => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
      refreshonly => true,
      require     => Class['network::service'],
    }
    -> exec { 'network: netplan apply':
      command     => 'netplan apply',
      path        => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
      refreshonly => true,
    }
  }

  # Ordering of a Puppet run:
  #   1. packages and base config, so connection files land in existing directories
  #   2. ALL connection files (so a bond never comes up before its port files exist)
  #   3. one `nmcli connection reload` (NetworkManager backends)
  #   4. activation of the connections whose files changed
  if $nm_managed {
    File <| tag == 'network::connection' |> -> Exec['network: nmcli connection reload']
  }
  Class['network::config'] -> File <| tag == 'network::connection' |>
  File <| tag == 'network::connection' |> -> Exec <| tag == 'network::activation' |>

  $route_tables.each |$name, $tid| {
    network::route_table { $name: id => $tid }
  }
  $interfaces.each |$name, $params| {
    network::interface { $name: * => $params }
  }
  $connections.each |$name, $params| {
    network::connection { $name: * => $params }
  }
  $bonds.each |$name, $params| {
    network::bond { $name: * => $params }
  }
  $bridges.each |$name, $params| {
    network::bridge { $name: * => $params }
  }
}
