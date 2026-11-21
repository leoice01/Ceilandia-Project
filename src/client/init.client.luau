--!strict

type LifecycleController = {
	Init: ((self: LifecycleController) -> ())?,
	Start: ((self: LifecycleController) -> ())?,
}

local controllersFolder = script:FindFirstChild("Controllers")
if not controllersFolder then
	return
end

local controllers: { LifecycleController } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local loaded = (require :: any)(child)
		if type(loaded) == "table" then
			table.insert(controllers, loaded :: LifecycleController)
		end
	end
end

for _, controller in controllers do
	if controller.Init and type(controller.Init) == "function" then
		controller:Init()
	end
end

for _, controller in controllers do
	local start = controller.Start
	if start and type(start) == "function" then
		task.spawn(start, controller)
	end
end
