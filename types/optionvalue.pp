# Value of a bond, bridge or ethtool option: a number, a boolean or one plain token
# (e.g. 802.3ad, layer3+4, 10.0.0.1,10.0.0.2). No spaces, quotes or shell characters.
type Network::OptionValue = Variant[Integer, Boolean, Pattern[/\A[A-Za-z0-9_.:,+\/-]+\z/]]
