# @summary Deterministic RFC 4122 (v3-style) UUID derived from a seed string.
function network::uuid(String[1] $seed) >> String {
  $h = md5($seed)
  "${h[0,8]}-${h[8,4]}-3${h[13,3]}-a${h[17,3]}-${h[20,12]}"
}
