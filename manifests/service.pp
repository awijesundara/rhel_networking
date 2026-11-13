# @summary NetworkManager / network service state.
# @api private
class network::service {
  assert_private()

  if $network::manage_service {
    if $network::nm_managed {
      # conf.d changes take effect via SIGHUP; avoid a full NM restart.
      service { 'NetworkManager':
        ensure  => $network::service_ensure,
        enable  => $network::service_enable,
        restart => 'systemctl reload NetworkManager',
      }
    } elsif $network::backend == 'ifupdown' {
      service { 'networking': enable => true }
    } elsif $network::backend == 'netplan' {
      # netplan itself is no daemon; it hands its files to the renderer.
      $netplan_service = $network::netplan_renderer ? { 'NetworkManager' => 'NetworkManager', default => 'systemd-networkd' }
      service { $netplan_service:
        ensure => $network::service_ensure,
        enable => $network::service_enable,
      }
    } elsif $network::backend == 'wicked' {
      service { 'wicked': enable => true }
    } else {
      service { 'NetworkManager':
        ensure => $network::legacy_nm_ensure,
        enable => $network::legacy_nm_ensure == 'running',
      }
      # Enabled at boot only. Puppet never restarts it: `service network restart` drops every
      # interface; network re-activates just the connections whose files changed.
      service { 'network':
        enable => true,
      }
    }
  }
}
