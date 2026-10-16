--!strict
-- Every flip, heads, skull and button gets a sound, with a little random
-- pitch so it never gets boring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local Sounds = {}

local sounds: { [string]: Sound } = {}
local rng = Random.new()

function Sounds.init()
	local folder = Instance.new("Folder")
	folder.Name = "CoinFlickSounds"
	for name, id in Config.Sounds do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Volume = 0.6
		sound.Parent = folder
		sounds[name] = sound
	end
	folder.Parent = SoundService
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
