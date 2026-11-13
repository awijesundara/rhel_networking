# Linux interface name: at most 15 characters, no whitespace, '/', ':' or quotes.
type Network::Ifname = Pattern[/\A[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}\z/]
