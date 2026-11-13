# @summary Packages required by the selected backend.
# @api private
class network::install {
  assert_private()

  if $network::manage_packages {
    $base = $network::backend ? {
      'network_scripts' => $network::major ? { 7 => ['initscripts'], default => ['network-scripts'] },
      'ifupdown'        => ['ifupdown', 'ifenslave', 'bridge-utils', 'vlan'],
      'wicked'          => ['wicked'],
      'netplan'         => $network::netplan_renderer ? {
        'NetworkManager' => ['netplan.io', $network::nm_package],
        default          => ['netplan.io'],
      },
      default           => [$network::nm_package],
    }
    # ensure_packages: other modules may declare the same package.
    stdlib::ensure_packages($base + $network::extra_packages)
  }
}
