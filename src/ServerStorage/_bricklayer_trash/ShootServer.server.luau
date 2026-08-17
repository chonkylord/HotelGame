local DebrisService = game:GetService("Debris")
local IconURL = script.Parent.TextureId
local Tool = script.Parent

--------Main Events----------
local Events = Tool:WaitForChild("Events")
local ShootEvent = Events:WaitForChild("ShootRE")
local CreateBulletEvent = Events:WaitForChild("CreateBullet")

pcall(function()
	script.Parent:FindFirstChild("ThumbnailCamera"):Destroy()
	script.Parent:WaitForChild("READ ME"):Destroy()
	
	if not workspace:FindFirstChild("BulletFolder") then
	local BulletsFolder = Instance.new("Folder", workspace)
	BulletsFolder.Name = "BulletsFolder"
	end
end)
	
function TagHumanoid(humanoid, player)
	if humanoid.Health > 0 then
	while humanoid:FindFirstChild('creator') do
		humanoid:FindFirstChild('creator'):Destroy()
	end 
	
	local creatorTag = Instance.new("ObjectValue")
	creatorTag.Value = player
	creatorTag.Name = "creator"
	creatorTag.Parent = humanoid
	DebrisService:AddItem(creatorTag, 1.5)

	local weaponIconTag = Instance.new("StringValue")
	weaponIconTag.Value = IconURL
	weaponIconTag.Name = "icon"
		weaponIconTag.Parent = creatorTag
	end
end

function CreateBullet(bulletPos)
	if not workspace:FindFirstChild("BulletFolder") then
		local BulletFolder = Instance.new("Folder")
		BulletFolder.Name = "Bullets"
	end
	local bullet = Instance.new('Part', workspace.BulletsFolder)
	bullet.FormFactor = Enum.FormFactor.Custom
	bullet.Size = Vector3.new(0.1, 0.1, 0.1)
	bullet.BrickColor = BrickColor.new("Black")
	bullet.Shape = Enum.PartType.Block
	bullet.CanCollide = false
	bullet.CFrame = CFrame.new(bulletPos)
	bullet.Anchored = true
	bullet.TopSurface = Enum.SurfaceType.Smooth
	bullet.BottomSurface = Enum.SurfaceType.Smooth
	bullet.Name = 'Bullet'
	DebrisService:AddItem(bullet, 2.5)
	
	local shell = Instance.new("Part")
	shell.CFrame = Tool.Handle.CFrame * CFrame.fromEulerAnglesXYZ(1.5,0,0)
	shell.Size = Vector3.new(1,1,1)
	shell.BrickColor = BrickColor.new(226)
	shell.Parent = game.Workspace.BulletsFolder
	shell.CFrame = script.Parent.Handle.CFrame
	shell.CanCollide = false
	shell.Transparency = 0
	shell.BottomSurface = 0
	shell.TopSurface = 0
	shell.Name = "Shell"
	shell.Velocity = Tool.Handle.CFrame.lookVector * 35 + Vector3.new(math.random(-10,10),20,math.random(-10,20))
	shell.RotVelocity = Vector3.new(0,200,0)
	DebrisService:AddItem(shell, 1)
	
	local shellmesh = Instance.new("SpecialMesh")
	shellmesh.Scale = Vector3.new(.15,.4,.15)
	shellmesh.Parent = shell
end

ShootEvent.OnServerEvent:Connect(function(plr, hum ,damage)
	hum:TakeDamage(damage)
	TagHumanoid(hum, plr)
end)

CreateBulletEvent.OnServerEvent:Connect(function(plr, pos)
	CreateBullet(pos)
end)