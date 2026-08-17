local imgs = {103740493,103804266,103804383}
for _,v in pairs(imgs) do
	game:GetService("ContentProvider"):Preload("http://www.roblox.com/asset/?ID="..v)
end

script.Parent.Parent.Changed:connect(function ()
	if script.Parent.Parent.Enabled == true then
		wait(0.09)
		script.Parent.Parent.Enabled = false
	end
end)

while true do
	for i = 1,#imgs do
		script.Parent.Image = "http://www.roblox.com/asset/?ID="..imgs[i]
		wait(0.03)
	end
end
