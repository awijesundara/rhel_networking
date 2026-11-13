# Connection name. Used in file names and commands, so it cannot contain '/', quotes,
# backslashes, '$', '`' or line breaks, and cannot start with '.' or '-'.
type Network::ConnectionId = Pattern[/\A[^.\-\/'"\\`$\r\n][^\/'"\\`$\r\n]*\z/]
