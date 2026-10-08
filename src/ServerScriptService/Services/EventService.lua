local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteManifest = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("Net")
		:WaitForChild("RemoteManifest")
)

local EventService = {
	Name = "EventService",
}

local function ensureRoot()
	local root = ReplicatedStorage:FindFirstChild("Remotes")
	if root and not root:IsA("Folder") then
		root:Destroy()
		root = nil
	end
	if not root then
		root = Instance.new("Folder")
		root.Name = "Remotes"
		root.Parent = ReplicatedStorage
	end
	return root
end

local function ensureFolder(parent, name)
	local child = parent:FindFirstChild(name)
	if child then
		if child:IsA("Folder") then
			return child
		end
		child:Destroy()
	end

	child = Instance.new("Folder")
	child.Name = name
	child.Parent = parent
	return child
end

function EventService:_resolvePath(path, className, create)
	local root = ensureRoot()
	local node = root
	local parts = string.split(tostring(path or ""), "/")

	for index, part in ipairs(parts) do
		if part == "" then
			return nil
		end

		local leaf = index == #parts
		local child = node:FindFirstChild(part)
		if not child then
			if not create then
				return nil
			end
			child = Instance.new(leaf and className or "Folder")
			child.Name = part
			child.Parent = node
		elseif leaf and className and not child:IsA(className) then
			local compatible = (className == "RemoteEvent" and child:IsA("UnreliableRemoteEvent"))
				or (className == "UnreliableRemoteEvent" and child:IsA("RemoteEvent"))
			if not compatible then
				return nil
			end
		end

		if not leaf and not child:IsA("Folder") then
			if not create then
				return nil
			end
			child = ensureFolder(node, part)
		end

		node = child
	end

	return node
end

function EventService:EnsureRemote(path, className)
	return self:_resolvePath(path, className, true)
end

function EventService:EnsureRemotes(list)
	if type(list) ~= "table" then
		return
	end

	for _, entry in ipairs(list) do
		local path = entry.path or entry[1]
		local className = entry.className or entry[2]
		if path and className then
			self:EnsureRemote(path, className)
		end
	end
end

function EventService:EnsureManifest()
	local remotes = RemoteManifest
	if type(remotes) == "table" and type(remotes.GetAll) == "function" then
		self:EnsureRemotes(remotes:GetAll())
	elseif type(remotes) == "table" and type(remotes.Remotes) == "table" then
		self:EnsureRemotes(remotes.Remotes)
	end
end

function EventService:GetRoot()
	return ensureRoot()
end

function EventService:Init()
	self.Root = ensureRoot()
	self:EnsureManifest()
end

function EventService:Start()
	self.Root = ensureRoot()
	self:EnsureManifest()
end

return EventService
