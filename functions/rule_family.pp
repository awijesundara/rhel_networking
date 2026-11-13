# @summary Address family of a routing rule (explicit, or inferred from from/to).
function network::rule_family(Network::Rule $rule) >> Enum['ipv4', 'ipv6'] {
  if $rule['family'] =~ NotUndef {
    $rule['family']
  } elsif [$rule['from'], $rule['to']].any |$a| { $a =~ String and ':' in $a } {
    'ipv6'
  } else {
    'ipv4'
  }
}
