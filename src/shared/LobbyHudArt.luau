--!strict
-- carter's illustrated lobby buttons (ChatGPT, 2026-10-15). The PNGs are in art/ui/lobby_v2/ (cropped to the
-- button, max 1024 px). Each has its label, icon, rim and shadow painted in, so the client shows the picture whole
-- (no live text on top) and moves the whole button. Uploaded by the Studio helper 2026-10-15 (art/artmap.json maps
-- the same ids for the offline preview); id 0 = the drawn stand-in button (client/ui/LobbyHudV2).
-- Aspect = picture width / height (the layout fits each button to its picture).
-- LowPoly: carter's low-poly set (2026-10-15, art/ui/lobby_v2_lowpoly/, cropped to the visible button). A button
-- switches to it as soon as its Id is set (uploaded); until then it keeps the first set. Preview scene lobbyhud2
-- --set lowpoly=1 shows them early with preview-only ids (art/artmap.json 1015000001..8, never used in the game).

local LobbyHudArt = {}

export type Art = { Id: number, File: string, Aspect: number }

LobbyHudArt.Buttons = {
	Play = { Id = 96942072120823, File = "play.png", Aspect = 1024 / 375 },
	Train = { Id = 87524953826160, File = "train.png", Aspect = 1024 / 556 },
	Fight = { Id = 124576908457553, File = "fight.png", Aspect = 1024 / 506 },
	MyPets = { Id = 102245046728736, File = "my-pets.png", Aspect = 950 / 952 },
	PetBook = { Id = 109596211807745, File = "pet-book.png", Aspect = 1024 / 969 },
	Daily = { Id = 128022063635544, File = "daily.png", Aspect = 1024 / 992 },
	Spin = { Id = 84426205531752, File = "spin.png", Aspect = 975 / 989 },
	Shop = { Id = 95443335354858, File = "shop.png", Aspect = 1006 / 1024 },
} :: { [string]: Art }

LobbyHudArt.LowPoly = {
	Play = { Id = 114838950909512, File = "play.png", Aspect = 1024 / 342 },
	Train = { Id = 137572183122331, File = "train.png", Aspect = 1024 / 520 },
	Fight = { Id = 89518801391920, File = "fight.png", Aspect = 1024 / 534 },
	MyPets = { Id = 76720327418104, File = "my-pets.png", Aspect = 1024 / 963 },
	PetBook = { Id = 76401971573055, File = "pet-book.png", Aspect = 1003 / 924 },
	Daily = { Id = 71271807509237, File = "daily.png", Aspect = 1024 / 949 },
	Spin = { Id = 99517740835124, File = "spin.png", Aspect = 1012 / 980 },
	Shop = { Id = 114606500480158, File = "shop.png", Aspect = 1024 / 950 },
} :: { [string]: Art }

-- the picture a button shows now: the low-poly one once uploaded, else the first set
function LobbyHudArt.get(name: string): Art?
	local lp = LobbyHudArt.LowPoly[name]
	if lp and lp.Id > 0 then
		return lp
	end
	return LobbyHudArt.Buttons[name]
end

function LobbyHudArt.image(name: string): string?
	local a = LobbyHudArt.get(name)
	if a and a.Id > 0 then
		return "rbxassetid://" .. a.Id
	end
	return nil
end

return LobbyHudArt
