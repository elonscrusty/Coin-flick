-- Studio Play check (server command bar): why plot yard pets do not show. Prints, for every display pet on each
-- plot: its pivot, size, how many parts are visible, the plot Floor top and the first ground under it (any part,
-- CanQuery or not is not checked: plain raycast), and flags BURIED / TINY / HIDDEN / FAR.
for _, plot in workspace:GetDescendants() do
	local disp = plot:IsA("Model") and plot:GetAttribute("Plot") and plot:FindFirstChild("Display")
	if disp then
		local floor = plot:FindFirstChild("Floor", true)
		local top = if floor and floor:IsA("BasePart") then floor.Position.Y + floor.Size.Y / 2 else nil
		for _, m in disp:GetChildren() do
			if m:IsA("Model") then
				local cf, size = m:GetBoundingBox()
				local vis, n = 0, 0
				for _, p in m:GetDescendants() do
					if p:IsA("BasePart") and p.Name ~= "Stand" then
						n += 1
						if p.Transparency < 0.95 then vis += 1 end
					end
				end
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { disp }
				local hit = workspace:Raycast(cf.Position + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
				local gy = if hit then hit.Position.Y else nil
				local flags = {}
				if gy and gy > cf.Position.Y + size.Y / 2 then table.insert(flags, "BURIED under " .. hit.Instance:GetFullName()) end
				if size.Magnitude < 1 then table.insert(flags, "TINY") end
				if vis == 0 then table.insert(flags, "HIDDEN") end
				if floor and (cf.Position - floor.Position).Magnitude > math.max(floor.Size.X, floor.Size.Z) then table.insert(flags, "FAR from Floor") end
				print(("[YardCheck] %s %s pos=%s size=%s parts %d/%d visible floorTop=%s ground=%s %s"):format(
					plot.Name, m:FindFirstChild("Stand") and "yard" or "dome", tostring(cf.Position), tostring(size), vis, n,
					tostring(top), tostring(gy), table.concat(flags, ", ")))
			end
		end
	end
end
