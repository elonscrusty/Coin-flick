--!strict
-- Cosmetic catalogue rules (brief section 15: cosmetics only). Pure helpers over Config.Products
-- and the profile's Cosmetics table; nothing here can change power, Cash, luck or speed.
-- A cosmetic is visible (and buyable) only when its ProductId is a real id (> 0); with every id
-- at 0 the Store tab is hidden and the game works exactly as before.

local Config = require(script.Parent.Config)

local Cosmetics = {}

export type Entry = {
	Id: string,
	Kind: string,
	Name: string,
	Desc: string,
	ProductId: number,
	PriceText: string,
	Head: Color3?,
	Accent: Color3?,
	Light: Color3?,
}

function Cosmetics.get(id: any): Entry?
	if type(id) ~= "string" then
		return nil
	end
	return (Config.Products :: any)[id]
end

function Cosmetics.visible(entry: Entry?): boolean
	return entry ~= nil and type(entry.ProductId) == "number" and entry.ProductId > 0
end

-- Visible catalogue in display order, optionally one kind.
function Cosmetics.list(kind: string?): { Entry }
	local out = {}
	for _, id in Config.CosmeticOrder do
		local e = Cosmetics.get(id)
		if e and Cosmetics.visible(e) and (kind == nil or e.Kind == kind) then
			table.insert(out, e)
		end
	end
	return out
end

function Cosmetics.anyVisible(): boolean
	return #Cosmetics.list() > 0
end

function Cosmetics.byProductId(productId: number): Entry?
	for _, id in Config.CosmeticOrder do
		local e = Cosmetics.get(id)
		if e and Cosmetics.visible(e) and e.ProductId == productId then
			return e
		end
	end
	return nil
end

function Cosmetics.empty(): { Owned: { [string]: boolean }, Equipped: { [string]: string }, Receipts: { [string]: boolean }, ReceiptOrder: { string } }
	return { Owned = {}, Equipped = {}, Receipts = {}, ReceiptOrder = {} }
end

function Cosmetics.owned(state: any, id: string): boolean
	return type(state) == "table" and type(state.Owned) == "table" and state.Owned[id] == true
end

-- The equipped cosmetic of a kind, only if it still exists, is owned and is visible.
function Cosmetics.equipped(state: any, kind: string): Entry?
	if type(state) ~= "table" or type(state.Equipped) ~= "table" then
		return nil
	end
	local id = state.Equipped[kind]
	local e = Cosmetics.get(id)
	if e and e.Kind == kind and Cosmetics.visible(e) and Cosmetics.owned(state, e.Id) then
		return e
	end
	return nil
end

-- Remembers a receipt id (idempotency key) and trims the oldest beyond `keep`.
function Cosmetics.rememberReceipt(state: any, key: string, keep: number)
	if state.Receipts[key] then
		return
	end
	state.Receipts[key] = true
	table.insert(state.ReceiptOrder, key)
	while #state.ReceiptOrder > keep do
		local old = table.remove(state.ReceiptOrder, 1)
		if old then
			state.Receipts[old] = nil
		end
	end
end

-- Recolours a held tool model. Hammers: Head + faces; Jackhammer: Body + shaft. Only colour.
function Cosmetics.applyToolSkin(tool: Instance, skin: Entry?)
	if not skin or skin.Kind ~= "ToolSkin" then
		return
	end
	local head, accent = skin.Head, skin.Accent
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			-- Part tools: Head / Body, FaceL / FaceR / Shaft / Collar. Kit tools: the steel head or
			-- amber body is the head colour, the bright steel faces and the bit are the accent.
			local n = d.Name
			if (n == "Head" or n == "Body" or n == "Steel" or n == "Amber_SmoothPlastic") and head then
				d.Color = head
			elseif (n == "FaceL" or n == "FaceR" or n == "Shaft" or n == "Collar" or n == "SteelLight" or n == "Bit") and accent then
				d.Color = accent
			end
		end
	end
end

local DEFAULT_SIDE = Color3.fromRGB(168, 117, 72) -- V4 wood
local DEFAULT_LIGHT = Color3.fromRGB(255, 220, 150)

-- Recolours one lobby alcove (frame sides + shelf lights). theme = nil restores the default.
function Cosmetics.applyAlcoveTheme(alcove: Instance, theme: Entry?)
	local side = DEFAULT_SIDE
	local light = DEFAULT_LIGHT
	if theme and theme.Kind == "GalleryTheme" then
		side = theme.Accent or side
		light = theme.Light or light
	end
	for _, d in alcove:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "SideL" or d.Name == "SideR" then
				d.Color = side
			elseif d.Name == "ShelfLight" then
				d.Color = light
			end
		end
	end
end

return Cosmetics
