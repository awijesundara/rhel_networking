# Numeric table id, or a name defined in network::route_tables (or main/local/default)
type Network::Table = Variant[Integer[1, 4294967295], Pattern[/\A[A-Za-z_][\w.-]*\z/]]
