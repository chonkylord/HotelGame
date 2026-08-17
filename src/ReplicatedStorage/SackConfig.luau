--!strict
-- Shared tuning for the sack. The server enforces every number in here; the
-- client reads them only so the UI can draw the right number of slots and grey
-- out what is out of reach.

local SackConfig = {}

-- Dead Rails carries ten. So does this.
SackConfig.Capacity = 10

-- Anything wearing this tag can be bagged. It goes on an item at the moment it
-- becomes visible — food set out on a table gets it immediately, loot inside a
-- drawer or a crate only once that container has been opened, so nothing can be
-- pocketed through a shut lid.
SackConfig.CollectableTag = "Collectable"

-- Optional per-item restrictions. Ordinary loot has neither attribute. The
-- hidden roulette spinner uses both: it cannot be bagged before the Room 2 bed
-- is lifted, and afterward only Superman can put it in a sack.
SackConfig.LockedAttribute = "SackLocked"
SackConfig.RequiredClassAttribute = "SackClass"

-- How far you can be from something and still bag it. Generous, because you aim
-- with a crosshair in first person and the server re-checks anyway.
SackConfig.Reach = 14

SackConfig.RemotesFolder = "SackRemotes"
SackConfig.StoreEvent = "SackStore" -- client -> server: bag this instance
SackConfig.DropEvent = "SackDrop" -- client -> server: put slot n back in the world
SackConfig.UpdateEvent = "SackUpdate" -- server -> client: here is your sack

SackConfig.ToolName = "Sack"

-- What one entry looks like when the server describes the sack to the client.
-- Only the name: the readout is a counter, and anything you want to eat gets
-- dropped and clicked, which is how food already works everywhere else.
export type Slot = {
	name: string,
}

return SackConfig
