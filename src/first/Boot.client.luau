--!strict
-- ReplicatedFirst entry: shows the FIND THE GEODE! title/loading screen as early as possible.
-- All logic lives in the LoadingScreen module (the offline preview drives it from a scene).
require(script.Parent:WaitForChild("LoadingScreen")).run()
