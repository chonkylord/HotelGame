function onClicked (playerwhoclicked)
	script.Parent.Sound:Play()
end

script.Parent.ClickDetector.MouseClick:connect(onClicked)