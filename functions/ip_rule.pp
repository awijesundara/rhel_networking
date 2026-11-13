# @summary Render a routing rule. The same syntax is accepted by `ip rule`,
#   ifcfg rule-/rule6- files and NM keyfile routing-ruleN keys.
function network::ip_rule(Network::Rule $rule) >> String {
  $tokens = [
    "priority ${rule['priority']}",
    $rule['not'] ? { true => 'not', default => undef },
    $rule['from'] ? { undef => undef, default => "from ${rule['from']}" },
    $rule['to'] ? { undef => undef, default => "to ${rule['to']}" },
    $rule['iif'] ? { undef => undef, default => "iif ${rule['iif']}" },
    $rule['oif'] ? { undef => undef, default => "oif ${rule['oif']}" },
    $rule['fwmark'] ? { undef => undef, default => "fwmark ${rule['fwmark']}" },
    $rule['tos'] ? { undef => undef, default => "tos ${rule['tos']}" },
    $rule['ipproto'] ? { undef => undef, default => "ipproto ${rule['ipproto']}" },
    $rule['sport'] ? { undef => undef, default => "sport ${rule['sport']}" },
    $rule['dport'] ? { undef => undef, default => "dport ${rule['dport']}" },
    $rule['uidrange'] ? { undef => undef, default => "uidrange ${rule['uidrange']}" },
    $rule['suppress_prefixlength'] ? {
      undef   => undef,
      default => "suppress_prefixlength ${rule['suppress_prefixlength']}",
    },
    $rule['table'] ? { undef => undef, default => "table ${network::table_id($rule['table'])}" },
    $rule['action'],
  ]
  $tokens.filter |$t| { $t =~ NotUndef }.join(' ')
}
