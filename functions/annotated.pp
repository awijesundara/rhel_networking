# @summary Interleave rendered route/rule lines with "# ..." comments explaining them
#   (description, routing table name). `lines[i]` is the rendering of `entries[i]`.
function network::annotated(Array[Hash] $entries, Array[String] $lines) >> Array[String] {
  $entries.map |$i, $e| {
    [network::comment($e), $lines[$i]].filter |$l| { $l =~ NotUndef }
  }.flatten
}
