# @summary Format and double-quote a value for an ifcfg (shell) file.
function network::ifcfg_value(Any $value) >> String {
  if String($value) =~ /[\r\n]/ {
    fail("network: line breaks are not allowed in generated settings: ${String($value)[0, 40]}...")
  }
  $s = $value ? {
    Boolean => $value ? { true => 'yes', default => 'no' },
    Array   => $value.join(' '),
    default => String($value),
  }
  $escaped = regsubst($s, '(["\\\\$`])', '\\\\\\1', 'G')
  "\"${escaped}\""
}
