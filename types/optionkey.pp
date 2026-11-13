# Key of a bond, bridge or ethtool option, e.g. xmit_hash_policy, forward-delay, ring-rx.
type Network::OptionKey = Pattern[/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/]
