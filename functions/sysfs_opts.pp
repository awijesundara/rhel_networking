# @summary Render NM-style options as space separated sysfs key=value pairs (BRIDGING_OPTS), or undef when empty.
function network::sysfs_opts(Hash[String[1], Scalar] $options) >> Optional[String] {
  if $options.empty {
    undef
  } else {
    $options.map |$k, $v| {
      $val = $v ? { true => 1, false => 0, default => $v }
      "${regsubst($k, '-', '_', 'G')}=${val}"
    }.join(' ')
  }
}
