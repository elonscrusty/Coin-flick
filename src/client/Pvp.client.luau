--!strict
-- Pet Battle + training client boot (its own LocalScript so Main.client.luau stays untouched). See ui/PvpPanel.
require(script.Parent.ui.PvpPanel).start()
require(script.Parent.PetInspectTap).start() -- tap another player's pet to inspect it
