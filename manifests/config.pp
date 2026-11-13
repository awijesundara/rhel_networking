# @summary Global configuration: NM conf.d, purging, rt_tables, sysctl, /etc/sysconfig/network.
# @api private
class network::config {
  assert_private()

  if $network::nm_managed {
    # conf.d changes are applied with a NetworkManager reload (SIGHUP), not a restart.
    $nm_daemon = $network::manage_service ? { true => Service['NetworkManager'], default => undef }
    file { "${network::nm_conf_dir}/99-network.conf":
      ensure  => $network::nm_settings.empty ? { true => absent, default => file },
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => epp('network/ini.epp', {
        header   => network::header('Hiera network::nm_settings', 'NetworkManager daemon (apply: systemctl reload NetworkManager)'),
        sections => $network::nm_settings,
      }),
      notify  => $nm_daemon,
    }
    $network::nm_conf_files.each |$fname, $sections| {
      file { "${network::nm_conf_dir}/${fname}":
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => epp('network/ini.epp', {
          header   => network::header("Hiera network::nm_conf_files['${fname}']", 'NetworkManager daemon (apply: systemctl reload NetworkManager)'),
          sections => $sections,
        }),
        notify  => $nm_daemon,
      }
    }
  }

  if $network::purge_connections {
    $dir = $network::backend ? {
      'keyfile'  => $network::keyfile_dir,
      'ifupdown' => $network::ifupdown_dir,
      'netplan'  => $network::netplan_dir,
      default    => $network::ifcfg_dir,
    }
    file { $dir:
      ensure  => directory,
      recurse => true,
      purge   => true,
      force   => false,
      ignore  => $network::backend ? {
        'keyfile'  => [],
        'ifupdown' => [],
        'netplan'  => $network::purge_ignore.filter |$i| { $i =~ /\.yaml/ },
        # Protect wicked/networkig globals and helper trees, even with custom ignores.
        'wicked' => $network::purge_ignore + ['config', 'dhcp', 'ifsysctl', 'scripts', 'providers', '*.d', 'xml', '*.xml', '*.template'],
        default  => $network::purge_ignore,
      },
      notify  => $network::nm_managed ? { true => Exec['network: nmcli connection reload'], default => undef },
    }
  }

  if $network::backend == 'keyfile' and !$network::purge_connections {
    file { $network::keyfile_dir:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0700',
    }
  }

  if $network::backend == 'netplan' {
    unless $network::purge_connections {
      file { $network::netplan_dir:
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }
    }
    file { dirname($network::netplan_state_dir):
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0700',
    }
    file { $network::netplan_state_dir:
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0700',
      recurse => true,
      purge   => true,   # forget devices that are no longer managed
    }
  }

  if $network::backend == 'ifupdown' {
    unless $network::purge_connections {
      file { $network::ifupdown_dir:
        ensure => directory,
      }
    }
    file_line { 'network-interfaces-source':
      path => '/etc/network/interfaces',
      line => "source ${network::ifupdown_dir}/*",
    }
  }

  unless $network::all_route_tables.empty {
    ensure_resource('file', ['/etc/iproute2', $network::rt_tables_dir], {
      'ensure' => 'directory', 'owner' => 'root', 'group' => 'root', 'mode' => '0755',
    })
  }

  unless $network::routing_tables.empty {
    file { '/etc/iproute2/rt_tables':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => epp('network/rt_tables.epp', { routing_tables => $network::routing_tables }),
    }
  }

  unless $network::sysctl.empty {
    file { '/etc/sysctl.d/90-network.conf':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => "${network::header('Hiera network::sysctl', 'systemd-sysctl at boot (apply now: sysctl -p /etc/sysctl.d/90-network.conf)')}${network::sysctl.map |$k, $v| { "${k} = ${v}\n" }.join('')}",
    }
    ~> exec { 'network: sysctl -p 90-network.conf':
      command     => 'sysctl -p /etc/sysctl.d/90-network.conf',
      path        => ['/usr/sbin', '/sbin', '/usr/bin', '/bin'],
      refreshonly => true,
    }
  }

  if $network::sysconfig_network.empty and $network::backend == 'network_scripts' {
    # ifup/ifdown source this file and fail without it. Normally the installer creates it;
    # create a minimal one only if it is missing, never touch an existing one.
    file { '/etc/sysconfig/network':
      ensure  => file,
      replace => false,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => "# Created by Puppet (network) because it was missing; ifup/ifdown need it.\nNETWORKING=yes\n",
    }
  }

  unless $network::sysconfig_network.empty {
    file { 'network-scripts and NetworkManager (global defaults)':
      path    => '/etc/sysconfig/network',
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => epp('network/shellvars.epp', {
        header   => network::header('Hiera network::sysconfig_network', 'network-scripts and NetworkManager (global defaults)'),
        settings => $network::sysconfig_network,
      }),
    }
  }
}
