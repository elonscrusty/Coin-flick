--!strict
-- Every flip, heads, skull and button gets a sound, with a little random
-- pitch so it never gets boring. Uses carter's uploaded sounds; if one will
-- not load, that sound quietly switches to its built-in fallback.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundPick = require(ReplicatedStorage.Shared.Util.SoundPick)

local Sounds = {}

local sounds: { [string]: Sound } = {}
local rng = Random.new()

function Sounds.init()
	local folder = Instance.new("Folder")
	folder.Name = "CoinFlickSounds"
	local toLoad: { Instance } = {}
	for name, def in Config.Sounds do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = SoundPick.source(def, false)
		sound.Volume = 0.6
		sound.Parent = folder
		sounds[name] = sound
		table.insert(toLoad, sound)
	end
	folder.Parent = SoundService
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(toLoad, function(contentId: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Success then
					return
				end
				for name, def in Config.Sounds do
					local sound = sounds[name]
					if sound and sound.SoundId == contentId then
						sound.SoundId = SoundPick.source(def, true)
					end
				end
			end)
		end)
		if not ok then
			warn("[Sounds] preload failed, using built-in sounds: " .. tostring(err))
			for name, def in Config.Sounds do
				sounds[name].SoundId = SoundPick.source(def, true)
			end
		end
	end)
end

function Sounds.play(name: string, volume: number?, pitch: number?)
	local sound = sounds[name]
	if not sound then
		return
	end
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = (pitch or 1) * rng:NextNumber(0.92, 1.08)
	SoundService:PlayLocalSound(sound)
end

return Sounds
