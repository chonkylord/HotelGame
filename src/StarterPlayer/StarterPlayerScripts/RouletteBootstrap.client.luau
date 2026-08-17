--!strict
-- Tiny on purpose: the hidden-spinner presentation loads once from the shared
-- module while this LocalScript remains the normal StarterPlayer entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("RouletteClientUI"))
