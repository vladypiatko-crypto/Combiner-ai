--!strict
-- Shared client state + a tiny event bus for the UI modules.

local Store = {}

Store.myFid = 0
Store.isAdmin = false
Store.profile = nil :: any
Store.scores = {} :: { any }
Store.phase = "lobby"
Store.mapIndex = 0
Store.ready = false
Store.settings = {
	sfx = 1,
	shake = true,
	numbers = true,
	flashing = true, -- turn off to calm down the crate flashing
	fps = false,
	quickRolls = false, -- skip the long reveal for Common / Uncommon
}

local listeners: { [string]: { (...any) -> () } } = {}

function Store.on(name: string, fn: (...any) -> ())
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end

function Store.emit(name: string, ...: any)
	for _, fn in listeners[name] or {} do
		task.spawn(fn, ...)
	end
end

return Store
