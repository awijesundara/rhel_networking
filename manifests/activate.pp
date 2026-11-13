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

  if $profile['ensure'] == 'present' and $profile['activation'] != 'none' {
    exec { "network: activate ${profile['id']}":
      command     => $command,
      path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      provider    => shell,
      refreshonly => true,
      subscribe   => $files,
      require     => $network::nm_managed ? { true => Exec['network: nmcli connection reload'], default => undef },
    }
  }
}
