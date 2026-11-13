# @summary Format a value for a NetworkManager keyfile / INI file.
function network::keyfile_value(Any $value) >> String {
  if String($value) =~ /[\r\n]/ {
    fail("network: line breaks are not allowed in generated settings: ${String($value)[0, 40]}...")
  }
  case $value {
    Boolean: { if $value { 'true' } else { 'false' } }
    Array:   { "${value.join(';')};" }
    default: { String($value) }
  }
}
