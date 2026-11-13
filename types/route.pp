type Network::Route = Struct[{
  destination           => Stdlib::IP::Address,
  Optional[gateway]     => Stdlib::IP::Address::Nosubnet,
  Optional[metric]      => Integer[0, 4294967295],
  Optional[table]       => Network::Table,
  Optional[src]         => Stdlib::IP::Address::Nosubnet,
  Optional[onlink]      => Boolean,
  Optional[mtu]         => Integer[68],
  Optional['type']        => Enum['unicast', 'local', 'blackhole', 'unreachable', 'prohibit', 'throw'],
  # Extra attributes passed verbatim (keyfile: routeN_options k=v; ifcfg: "k v")
  Optional[options]     => Hash[Network::OptionKey, Variant[Integer, Boolean, Pattern[/\A[^\s'"\\`$]+\z/]]],
  # Free text; written as a comment next to the entry in the generated files.
  Optional[description] => Network::Description,
}]
