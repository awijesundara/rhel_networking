# @summary Address family of an IP address / prefix.
function network::family(String[1] $address) >> Enum['ipv4', 'ipv6'] {
  if ':' in $address { 'ipv6' } else { 'ipv4' }
}
