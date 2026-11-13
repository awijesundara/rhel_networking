# @summary The comment block written at the top of every generated file, so an
#   admin reading the file on the server knows where it came from, what reads it,
#   and how to change it. `notes` are extra explanation lines.
function network::header(String[1] $source, String[1] $read_by, Array[String] $notes = []) >> String {
  if ([$source, $read_by] + $notes).any |$text| { $text =~ /[\r\n]/ } {
    fail("network: line breaks are not allowed in resource titles or descriptions (${source[0, 40]}...)")
  }
  $note_lines = $notes.map |$n| { "# ${n}\n" }.join('')
  @("HEADER")
  # ---------------------------------------------------------------------
  # Managed by Puppet (module: network). Local edits are overwritten.
  # Source : ${source}
  # Read by: ${read_by}
  # To change this file, edit the Hiera data for the source above.
  ${note_lines}# ---------------------------------------------------------------------
  | HEADER
}
