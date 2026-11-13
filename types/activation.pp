# none    - write files only (NM still reloads profiles from disk)
# reapply - `nmcli device reapply` (non-disruptive, NM backends only)
# up      - `nmcli connection up` / `ifdown; ifup`
type Network::Activation = Enum['none', 'reapply', 'up']
