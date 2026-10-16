--!strict
-- Thumbnail for one ordinary-material category (Config.Materials), drawn from frames: no asset ids.
-- Found: the category's real colours. Unfound: one restrained silhouette that tells nothing about the material.
-- Quartz is a SOLID faceted chip (never a hollow geode); metallic specks are small bright flecks on grey stone.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local UI = require(script.Parent.UI)

local MaterialThumb = {}

local SILHOUETTE = Color3.fromRGB(208, 198, 180)
local SILHOUETTE_EDGE = Color3.fromRGB(190, 178, 156)

local function piece(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, rot: number, round: number): Frame
	local f = UI.frame(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		Rotation = rot,
	})
	UI.corner(f, round)
	return f
end

function MaterialThumb.make(parent: Instance, id: string, found: boolean, size: number, props: { [string]: any }?): Frame
	local mat = Config.Materials[id]
	local box = UI.frame(parent, { Name = "MaterialThumb", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	if props then
		for k, v in props do
			(box :: any)[k] = v
		end
	end
	local r = math.max(3, math.floor(size * 0.18))
	local look = if mat then mat.Look else "stone"
	if not found or not mat then
		-- silhouette: the same plain stone outline for every unknown entry
		piece(box, 0.5, 0.56, 0.78, 0.6, SILHOUETTE_EDGE, 0, r)
		piece(box, 0.5, 0.54, 0.7, 0.52, SILHOUETTE, 0, r)
		return box
	end
	local base = mat.Color
	local dark = base:Lerp(Color3.new(0, 0, 0), 0.28)
	local light = mat.Accent
	if look == "chip" then
		-- a solid faceted chip: two overlapping rotated blocks and a highlight facet
		piece(box, 0.5, 0.56, 0.62, 0.62, dark, 45, math.max(2, r - 2))
		piece(box, 0.5, 0.52, 0.56, 0.56, base, 45, math.max(2, r - 2))
		piece(box, 0.4, 0.4, 0.22, 0.22, light, 45, 2)
	else
		piece(box, 0.5, 0.58, 0.8, 0.58, dark, 0, r)
		piece(box, 0.5, 0.54, 0.72, 0.5, base, 0, r)
		piece(box, 0.38, 0.42, 0.26, 0.14, light:Lerp(base, 0.55), 0, 3)
		if look == "specks" then
			for _, p in { { 0.62, 0.5, 0.1 }, { 0.46, 0.62, 0.08 }, { 0.72, 0.62, 0.07 }, { 0.34, 0.54, 0.07 }, { 0.58, 0.4, 0.06 } } do
				piece(box, p[1], p[2], p[3], p[3], light, 0, 99)
			end
		end
	end
	return box
end

return MaterialThumb
