--!strict
-- Gold / Rainbow pet skins (owner, IMPORT_NOW4 pet_skins): same mesh, painted texture, eyes stay dark.
-- PetModel uses them for the Golden / Rainbow variants of the low-poly pets instead of the flat tint.
-- [species id] = { [variant] = texture }: Golden, Rainbow, and optionally Skeleton / SilverCosmic (a variant
-- without a skin falls back to the flat tint). Ids come from Studio uploads only, never made up.
local PetSkins: { [string]: { [string]: string } } = {
	Ashwing = { Golden = "rbxassetid://139107589087795", Rainbow = "rbxassetid://129938277255482", SilverCosmic = "rbxassetid://75749729361767", Skeleton = "rbxassetid://82132434875177" }, -- realistic colours 10-15
	AstralKitsune = { Golden = "rbxassetid://95569273212515", Rainbow = "rbxassetid://97954973153812", SilverCosmic = "rbxassetid://97774584907184", Skeleton = "rbxassetid://125989585630411" }, -- realistic colours 10-15
	AuroraHoot = { Golden = "rbxassetid://120965281949507", Rainbow = "rbxassetid://105544723489132", SilverCosmic = "rbxassetid://133226121540085", Skeleton = "rbxassetid://114726802371822" }, -- realistic colours 10-15
	Yetiboo = { Golden = "rbxassetid://135341892659978", Rainbow = "rbxassetid://129118802486999" },
	Bramblebat = { Golden = "rbxassetid://84879266574242", Rainbow = "rbxassetid://112254686295702", SilverCosmic = "rbxassetid://136005222759789", Skeleton = "rbxassetid://81139200030514" }, -- realistic colours 10-15
	Bunny = { Golden = "rbxassetid://105870313636483", Rainbow = "rbxassetid://82904144591367", SilverCosmic = "rbxassetid://128908060620653", Skeleton = "rbxassetid://114870297032335" }, -- realistic colours 10-15
	Cinderpup = { Golden = "rbxassetid://74308024546720", Rainbow = "rbxassetid://136471270275604", SilverCosmic = "rbxassetid://137979418197300", Skeleton = "rbxassetid://105477955342609" }, -- realistic colours 10-15
	Clovercrest = { Golden = "rbxassetid://79942629429714", Rainbow = "rbxassetid://70565978161052", SilverCosmic = "rbxassetid://80070441061549", Skeleton = "rbxassetid://136872270355747" }, -- realistic colours 10-15
	Cometpup = { Golden = "rbxassetid://127822608225383", Rainbow = "rbxassetid://88011084337262", SilverCosmic = "rbxassetid://104544301424353", Skeleton = "rbxassetid://131092067017532" }, -- realistic colours 10-15
	Elderhorn = { Golden = "rbxassetid://113145812673390", Rainbow = "rbxassetid://75572624381735", SilverCosmic = "rbxassetid://138193323873748", Skeleton = "rbxassetid://119126321500521" }, -- realistic colours 10-15
	DireWolf = { Golden = "rbxassetid://112583897816270", Rainbow = "rbxassetid://109920398414490", SilverCosmic = "rbxassetid://97008828297615", Skeleton = "rbxassetid://117125837255174" }, -- realistic colours 10-15
	Duskwing = { Golden = "rbxassetid://123113863751576", Rainbow = "rbxassetid://72640803923415", SilverCosmic = "rbxassetid://107116004399864", Skeleton = "rbxassetid://99402968495964" }, -- realistic colours 10-15
	Embergeist = { Golden = "rbxassetid://76486183647891", Rainbow = "rbxassetid://98593521759117", SilverCosmic = "rbxassetid://98917092904927", Skeleton = "rbxassetid://71827448737413" }, -- realistic colours 10-15
	Flarestrut = { Golden = "rbxassetid://122473812229937", Rainbow = "rbxassetid://70382941743201", SilverCosmic = "rbxassetid://124070564056315", Skeleton = "rbxassetid://83623496716667" }, -- realistic colours 10-15
	Frog = { Golden = "rbxassetid://107180980253732", Rainbow = "rbxassetid://85700870153194", SilverCosmic = "rbxassetid://97466983668785", Skeleton = "rbxassetid://103649264073036" }, -- realistic colours 10-15
	Frostbyte = { Golden = "rbxassetid://136306079055426", Rainbow = "rbxassetid://111248606154888", SilverCosmic = "rbxassetid://101934665294913", Skeleton = "rbxassetid://139067233250864" }, -- realistic colours 10-15
	FrostcrownDragon = { Golden = "rbxassetid://133001735237493", Rainbow = "rbxassetid://95170020623104", SilverCosmic = "rbxassetid://87442944189954", Skeleton = "rbxassetid://113905838705532" }, -- realistic colours 10-15
	GalaxyStrut = { Golden = "rbxassetid://125949706245202", Rainbow = "rbxassetid://112320372232125", SilverCosmic = "rbxassetid://125284233546960", Skeleton = "rbxassetid://100239891125204" }, -- realistic colours 10-15
	Griffin = { Golden = "rbxassetid://108147211679032", Rainbow = "rbxassetid://125251528715305", SilverCosmic = "rbxassetid://85787596564127", Skeleton = "rbxassetid://95665029028600" }, -- realistic colours 10-15
	Hailwing = { Golden = "rbxassetid://89621547654392", Rainbow = "rbxassetid://79757879118921", SilverCosmic = "rbxassetid://112976481320701", Skeleton = "rbxassetid://86610368603272" }, -- realistic colours 10-15
	Frostpaw = { Golden = "rbxassetid://72707760408120", Rainbow = "rbxassetid://92823883625391", SilverCosmic = "rbxassetid://113645478807980", Skeleton = "rbxassetid://124597219148936" }, -- realistic colours 10-15
	InfernalHydra = { Golden = "rbxassetid://119210617133837", Rainbow = "rbxassetid://133455299284879", SilverCosmic = "rbxassetid://73146318558140", Skeleton = "rbxassetid://99766991029630" }, -- realistic colours 10-15
	Magmaw = { Golden = "rbxassetid://94264528443725", Rainbow = "rbxassetid://127036931613552", SilverCosmic = "rbxassetid://132093563421856", Skeleton = "rbxassetid://129916751345633" }, -- realistic colours 10-15
	LunarTusk = { Golden = "rbxassetid://121811707126872", Rainbow = "rbxassetid://112812775895852", SilverCosmic = "rbxassetid://94981975390163", Skeleton = "rbxassetid://73569667747741" }, -- realistic colours 10-15
	Oakmaw = { Golden = "rbxassetid://138485714136013", Rainbow = "rbxassetid://92824810847340", SilverCosmic = "rbxassetid://98174081436516", Skeleton = "rbxassetid://116137381609833" }, -- realistic colours 10-15
	Obsidihorn = { Golden = "rbxassetid://124080207907782", Rainbow = "rbxassetid://79630667068515", SilverCosmic = "rbxassetid://108898344941427", Skeleton = "rbxassetid://122787689212609" }, -- realistic colours 10-15
	Moonhoot = { Golden = "rbxassetid://133948544337254", Rainbow = "rbxassetid://117925351528222" },
	Panda = { Golden = "rbxassetid://121556939130392", Rainbow = "rbxassetid://90258007052109", SilverCosmic = "rbxassetid://118682009883523", Skeleton = "rbxassetid://84104855364582" }, -- 1015 ALL mesh
	Pebblehorn = { Golden = "rbxassetid://116826177091623", Rainbow = "rbxassetid://117756053462731", SilverCosmic = "rbxassetid://99693006050428", Skeleton = "rbxassetid://135606129922550" }, -- realistic colours 10-15
	Phoenix = { Golden = "rbxassetid://112765458482539", Rainbow = "rbxassetid://80602558072147", SilverCosmic = "rbxassetid://74451100276708", Skeleton = "rbxassetid://81493001846423" }, -- realistic colours 10-15
	Puffquill = { Golden = "rbxassetid://108392579321384", Rainbow = "rbxassetid://85398339519808", SilverCosmic = "rbxassetid://87338040093792", Skeleton = "rbxassetid://81677337200132" }, -- realistic colours 10-15
	QuasarRex = { Golden = "rbxassetid://138646123948044", Rainbow = "rbxassetid://127184021373642", SilverCosmic = "rbxassetid://72491714849431", Skeleton = "rbxassetid://129451227041946" }, -- realistic colours 10-15
	Shark = { Golden = "rbxassetid://118421381232197", Rainbow = "rbxassetid://104652981504834", SilverCosmic = "rbxassetid://92854861419430", Skeleton = "rbxassetid://101769060814025" }, -- realistic colours 10-15
	Voltwing = { Golden = "rbxassetid://71149303864075", Rainbow = "rbxassetid://97921753258433" },
	SunpetalDrake = { Golden = "rbxassetid://84701627518614", Rainbow = "rbxassetid://70955524215114", SilverCosmic = "rbxassetid://93382491881493", Skeleton = "rbxassetid://130908059956008" }, -- realistic colours 10-15
	Thornback = { Golden = "rbxassetid://121013661633006", Rainbow = "rbxassetid://88407562624415", SilverCosmic = "rbxassetid://109237276808572", Skeleton = "rbxassetid://70816233135619" }, -- realistic colours 10-15
	Thornhoof = { Golden = "rbxassetid://94326990899945", Rainbow = "rbxassetid://134574299438110", SilverCosmic = "rbxassetid://78394284384892", Skeleton = "rbxassetid://78544033497668" }, -- realistic colours 10-15
	Hollowfang = { Golden = "rbxassetid://126969907940154", Rainbow = "rbxassetid://116949302164946" },
	Mossback = { Golden = "rbxassetid://97839171615666", Rainbow = "rbxassetid://90028140698979", SilverCosmic = "rbxassetid://92873870139086", Skeleton = "rbxassetid://118224248001811" }, -- realistic colours 10-15
	Honeyhoof = { Golden = "rbxassetid://71935682542124", Rainbow = "rbxassetid://108236277401338" },
	Vinetail = { Golden = "rbxassetid://138729478760947", Rainbow = "rbxassetid://72104420447420", SilverCosmic = "rbxassetid://90927322438302", Skeleton = "rbxassetid://108134982540078" }, -- realistic colours 10-15
	CosmicDragon = { Golden = "rbxassetid://138290074922308", Rainbow = "rbxassetid://74214244829375", SilverCosmic = "rbxassetid://71186684985091", Skeleton = "rbxassetid://140275137925772" }, -- realistic colours 10-15
	Waddlefrost = { Golden = "rbxassetid://103883568734330", Rainbow = "rbxassetid://136683255609334", SilverCosmic = "rbxassetid://129375796777692", Skeleton = "rbxassetid://86655728531288" }, -- realistic colours 10-15
	Zapstar = { Golden = "rbxassetid://121618109677915", Rainbow = "rbxassetid://132189334689964", SilverCosmic = "rbxassetid://132890082270751", Skeleton = "rbxassetid://106891632195883" }, -- realistic colours 10-15
	-- IMPORT_RAPTORS (raptors + space cat)
	Mosswhip = { Golden = "rbxassetid://139005560922944", Rainbow = "rbxassetid://116298718423288", SilverCosmic = "rbxassetid://125213919675734", Skeleton = "rbxassetid://88788138474159" }, -- realistic colours 10-15
	Shiverclaw = { Golden = "rbxassetid://105097473520115", Rainbow = "rbxassetid://106631307992866", SilverCosmic = "rbxassetid://139378570640000", Skeleton = "rbxassetid://107265821557795" }, -- realistic colours 10-15
	Emberclaw = { Golden = "rbxassetid://84758959095205", Rainbow = "rbxassetid://135488143517023", SilverCosmic = "rbxassetid://108768255701505", Skeleton = "rbxassetid://132286894230737" }, -- realistic colours 10-15
	Nebuclaw = { Golden = "rbxassetid://121592242367251", Rainbow = "rbxassetid://136259110933023", SilverCosmic = "rbxassetid://128683153987187", Skeleton = "rbxassetid://72260365431216" }, -- realistic colours 10-15
	SpaceCat = { Golden = "rbxassetid://113588656002409", Rainbow = "rbxassetid://137021624107383", SilverCosmic = "rbxassetid://79264508462795", Skeleton = "rbxassetid://137292182748078" }, -- realistic colours 10-15
	-- IMPORT_PETS_ALL (no earlier entry)
	FrostWyvern = { Golden = "rbxassetid://94562986501009", Rainbow = "rbxassetid://81670723870407", SilverCosmic = "rbxassetid://136846729015843", Skeleton = "rbxassetid://140507573879801" }, -- realistic colours 10-15
	LavaTRex = { Golden = "rbxassetid://124768172166278", Rainbow = "rbxassetid://74430583278762", SilverCosmic = "rbxassetid://98350205915742", Skeleton = "rbxassetid://121488646777844" }, -- realistic colours 10-15
	Mammoth = { Golden = "rbxassetid://121650286649606", Rainbow = "rbxassetid://90250437026178", SilverCosmic = "rbxassetid://89821284496342", Skeleton = "rbxassetid://107694232797627" }, -- realistic colours 10-15
	Ostrich = { Golden = "rbxassetid://95500871238805", Rainbow = "rbxassetid://73423789879399", SilverCosmic = "rbxassetid://125474310609813", Skeleton = "rbxassetid://72783674445850" }, -- realistic colours 10-15
	Raptor = { Golden = "rbxassetid://114262329132493", Rainbow = "rbxassetid://113677841454591", SilverCosmic = "rbxassetid://128462909129690", Skeleton = "rbxassetid://79434736121715" }, -- realistic colours 10-15
	StarPterodactyl = { Golden = "rbxassetid://107837967255244", Rainbow = "rbxassetid://93346821368402", SilverCosmic = "rbxassetid://93767073697696", Skeleton = "rbxassetid://72146701993320" }, -- 1015 ALL mesh
	Turtle = { Golden = "rbxassetid://105050598453615", Rainbow = "rbxassetid://88914275526469", SilverCosmic = "rbxassetid://72027537825258", Skeleton = "rbxassetid://119041163180796" }, -- realistic colours 10-15
}
return PetSkins
