--!strict
-- Client-side mirror of what the server told us. Read-only for gameplay decisions.

local State = {
	Profile = nil :: any,
	Party = nil :: any,
	Invites = {} :: { any },
	Match = nil :: any, -- { Key, Round, Tier, Phase, EndsAt, Members, Tutorial, Rocks, Remaining, MyCracked }
	Results = nil :: any,
	Teleport = false, -- true in the Match place of Teleport mode (set by the server)
	Changed = Instance.new("BindableEvent"), -- (what: "Profile" | "Party" | "Match" | "Results")
}

-- Call after changing a field so listeners refresh.
function State.update(what: string)
	State.Changed:Fire(what)
end

return State
