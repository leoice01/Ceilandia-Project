--!strict

type LifecycleService = {
	Init: ((self: LifecycleService) -> ())?,
	Start: ((self: LifecycleService) -> ())?,
}

local servicesFolder = script:FindFirstChild("Services")
if not servicesFolder then
	return
end

local services: { LifecycleService } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local loaded = (require :: any)(child)
		if type(loaded) == "table" then
			table.insert(services, loaded :: LifecycleService)
		end
	end
end

for _, service in services do
	if service.Init and type(service.Init) == "function" then
		service:Init()
	end
end

for _, service in services do
	local start = service.Start
	if start and type(start) == "function" then
		task.spawn(start, service)
	end
end
