# @summary A "# ..." line explaining a route or rule: its description plus the
#   name of the routing table, if one was referenced by name. Undef if nothing to say.
function network::comment(Hash $entry) >> Optional[String] {
  $table = $entry['table'] =~ String ? {
    true    => "table ${network::table_id($entry['table'])} = ${entry['table']}",
    default => undef,
  }
  $parts = [$entry['description'], $table].filter |$p| { $p =~ NotUndef }
  $parts.empty ? { true => undef, default => "# ${parts.join(' | ')}" }
}
