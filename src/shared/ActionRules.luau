--!strict
-- The contextual primary action as ONE pure function (Master Prompt 4, section 26). The client reads
-- the server snapshot and the avatar's position, builds an `Inputs` table, and gets back exactly one
-- context: what the button says, what a press sends, and where (if anywhere) a route hint points.
-- The label and the request can never disagree because both come from this one result.
-- The server still validates every request (RoundRocks / RockService); nothing here is trusted.
--
-- Ids (visible): pickup take deposit crush machine collect sell bagfull closer
-- Ids (no button): wait securing none
-- Priority: sell hopper (only with rubble) > own table > pile > nothing. At the own table Deposit beats
-- crush; a running machine only ever deposits. A button is shown only where there is something useful:
-- `closer` appears only when a relevant place is just outside its range, never for scenery.
local ActionRules = {}

export type Inputs = {
	Phase: string?, -- nil outside a hunt
	Active: boolean, -- the pile view is live (round initialised, not over)
	HasStation: boolean,
	Basket: number,
	Capacity: number, -- basket capacity
	Queue: number, -- rocks in the tray
	QueueCapacity: number,
	Current: boolean, -- a rock is on the plate
	Machine: boolean, -- an automatic machine is installed AND not paused (it will ignore hand hits)
	MachineFull: boolean, -- machine state is "Full" (rubble storage blocked)
	Rubble: number,
	RubbleFull: boolean,
	NearHopper: boolean,
	AtTable: boolean, -- inside the own table's crush range (server range minus a margin)
	NearTable: boolean, -- within a few studs outside that range
	HasTarget: boolean, -- a pickable rock in reach (the one that would be outlined and sent)
	NearPile: boolean, -- within a few studs outside pickup reach of the pile
}

export type Context = { Id: string, Arrow: string? }

-- Ids that draw no button at all.
local HIDDEN = { wait = true, securing = true, none = true }
function ActionRules.visible(id: string): boolean
	return not HIDDEN[id]
end

function ActionRules.decide(i: Inputs): Context
	if i.Phase == nil or i.Phase == "Countdown" then
		return { Id = "wait" }
	elseif i.Phase == "RewardPending" or i.Phase == "Reveal" then
		return { Id = "securing" }
	elseif i.Phase ~= "Searching" or not i.Active or not i.HasStation then
		return { Id = "wait" }
	end
	local queued = i.Queue + (if i.Current then 1 else 0)
	if i.Rubble > 0 and i.NearHopper then
		return { Id = "sell" }
	end
	if i.AtTable then
		if i.Basket > 0 and i.Queue < i.QueueCapacity then
			return { Id = "deposit" }
		elseif i.Basket > 0 and not i.Machine then
			return { Id = if i.RubbleFull and not i.Current then "bagfull" else "crush" }
		elseif i.Basket > 0 then
			return { Id = "machine" }
		elseif i.Machine then
			return { Id = if i.MachineFull then "bagfull" else "machine", Arrow = "pile" }
		elseif queued > 0 then
			return { Id = if i.RubbleFull and not i.Current then "bagfull" else "crush" }
		end
		return { Id = "collect", Arrow = "pile" }
	end
	-- away from the table
	local wantsTable = i.Basket > 0 and (i.Basket >= i.Capacity or not i.HasTarget) or (queued > 0 and not i.Machine)
	if i.HasTarget then
		if i.Basket < i.Capacity then
			return { Id = "pickup" }
		end
		return { Id = "take", Arrow = "table" }
	end
	local arrow = if wantsTable then "table" elseif i.Basket == 0 and queued == 0 then "pile" else nil
	if wantsTable and i.NearTable then
		return { Id = "closer", Arrow = arrow }
	elseif not wantsTable and i.Basket < i.Capacity and i.NearPile then
		return { Id = "closer", Arrow = arrow }
	end
	return { Id = "none", Arrow = arrow }
end

return ActionRules
