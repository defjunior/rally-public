local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Modules.Logger)

local RemoteBridge = {}
RemoteBridge.__index = RemoteBridge

local function walkPath(root, path)
	local node = root
	for segment in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(segment)
		if not node then
			return nil
		end
	end
	return node
end

function RemoteBridge.new(channel)
	local self = setmetatable({}, RemoteBridge)
	self.Channel = channel or "RemoteBridge"
	self.Remotes = ReplicatedStorage:WaitForChild("Remotes")
	return self
end

function RemoteBridge:Get(path)
	return walkPath(self.Remotes, path)
end

function RemoteBridge:GetRequired(path)
	local remote = self:Get(path)
	assert(remote, string.format("Missing remote at path %s", path))
	return remote
end

function RemoteBridge:Fire(path, ...)
	local remote = self:GetRequired(path)
	remote:FireServer(...)
end

function RemoteBridge:Invoke(path, ...)
	local remote = self:GetRequired(path)
	return remote:InvokeServer(...)
end

function RemoteBridge:Connect(path, callback)
	local remote = self:GetRequired(path)
	return remote.OnClientEvent:Connect(callback)
end

function RemoteBridge:Bind(path, callback)
	local remote = self:GetRequired(path)
	remote.OnClientInvoke = callback
	Logger.Info(self.Channel, string.format("bound OnClientInvoke for %s", path))
end

return RemoteBridge
