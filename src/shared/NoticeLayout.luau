--!strict
-- Decisions of the notification column (client/ui/UI fitNotices / notify), pure so tests/test_notice_layout.luau can
-- check them: with a menu open the column shows at most ONE notice, and sits top-right under the menu header (or beside
-- the menu when there is room) rather than over the menu body.
local NoticeLayout = {}

NoticeLayout.SideMin = 230 -- logical width beside a menu that takes the notification column

-- How many cards may be on screen: one over an open menu, else `normal` (UI.MaxNotices).
function NoticeLayout.maxCards(menuOpen: boolean, normal: number): number
	return if menuOpen then 1 else normal
end

-- Where the column goes: "side" (beside the menu, no dialog), "corner" (top-right, under the menu header, no dialog
-- and no room beside it), or "hud" (no menu, or a dialog is open: the HUD spot, kept clear of the protected bands).
function NoticeLayout.mode(menuOpen: boolean, dialogOpen: boolean, sideGap: number): string
	if not menuOpen or dialogOpen then
		return "hud"
	end
	return if sideGap >= NoticeLayout.SideMin then "side" else "corner"
end

return NoticeLayout
