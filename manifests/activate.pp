# @summary Bring a connection up again after its files changed.
# @api private
#
# Runs only when one of `files` changed (refreshonly), never on a quiet Puppet run.
define network::activate (
  Hash          $profile,
  Array         $files,
  String[1]     $command,
) {
  assert_private()

  $device_tag = $profile['device'].then |$device| { "network-device-${md5($device)}" }

  if $profile['ensure'] == 'present' and $profile['activation'] != 'none' {
    exec { "network: activate ${profile['id']}":
      command     => $command,
      tag         => ['network::activation', $device_tag].filter |$tag| { $tag =~ NotUndef },
      path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      provider    => shell,
      refreshonly => true,
      subscribe   => $files,
      require     => $network::nm_managed ? { true => Exec['network: nmcli connection reload'], default => undef },
      onlyif      => $network::nm_managed ? { true => 'systemctl is-active --quiet NetworkManager', default => undef },
    }
  }
}
