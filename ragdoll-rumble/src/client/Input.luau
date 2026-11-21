--!strict
-- Keyboard + mouse, gamepad and touch input -> Fighter.Input

local UserInputService = game:GetService("UserInputService")

local Input = {}

local held = {
	left = false,
	right = false,
	up = false,
	down = false,
	attack = false,
	block = false,
}
local pressed = { jump = false, attack = false, throw = false }

Input.mode = "mouse" -- "mouse" | "gamepad" | "touch"
Input.touchMove = 0
Input.touchDown = false
Input.touchAttack = false
Input.touchBlock = false
local stick1 = Vector2.zero
local stick2 = Vector2.zero
local gamepadAttack = false
local gamepadBlock = false
local lastAim = Vector2.new(1, 0)

local KEYS_LEFT = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true }
local KEYS_RIGHT = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true }
local KEYS_JUMP = { [Enum.KeyCode.W] = true, [Enum.KeyCode.Up] = true, [Enum.KeyCode.Space] = true }
local KEYS_DOWN = { [Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true }
local KEYS_THROW = { [Enum.KeyCode.F] = true, [Enum.KeyCode.E] = true, [Enum.KeyCode.Q] = true }
local KEYS_ATTACK = { [Enum.KeyCode.J] = true, [Enum.KeyCode.Z] = true }
local KEYS_BLOCK = { [Enum.KeyCode.K] = true, [Enum.KeyCode.X] = true, [Enum.KeyCode.LeftShift] = true }

function Input.init(onToggleHelp: () -> ())
	UserInputService.InputBegan:Connect(function(io: InputObject, gpe: boolean)
		local kc = io.KeyCode
		local ut = io.UserInputType
		if ut == Enum.UserInputType.Keyboard then
			if gpe then
				return
			end
			Input.mode = "mouse"
			if KEYS_LEFT[kc] then
				held.left = true
			elseif KEYS_RIGHT[kc] then
				held.right = true
			elseif KEYS_JUMP[kc] then
				held.up = true
				pressed.jump = true
			elseif KEYS_DOWN[kc] then
				held.down = true
			elseif KEYS_THROW[kc] then
				pressed.throw = true
			elseif KEYS_ATTACK[kc] then
				held.attack = true
				pressed.attack = true
			elseif KEYS_BLOCK[kc] then
				held.block = true
			elseif kc == Enum.KeyCode.H then
				onToggleHelp()
			end
		elseif ut == Enum.UserInputType.MouseButton1 then
			if gpe then
				return
			end
			Input.mode = "mouse"
			held.attack = true
			pressed.attack = true
		elseif ut == Enum.UserInputType.MouseButton2 then
			if gpe then
				return
			end
			held.block = true
		elseif ut == Enum.UserInputType.Gamepad1 then
			Input.mode = "gamepad"
			if kc == Enum.KeyCode.ButtonA then
				held.up = true
				pressed.jump = true
			elseif kc == Enum.KeyCode.ButtonR2 or kc == Enum.KeyCode.ButtonR1 then
				gamepadAttack = true
				pressed.attack = true
			elseif kc == Enum.KeyCode.ButtonL2 or kc == Enum.KeyCode.ButtonL1 then
				gamepadBlock = true
			elseif kc == Enum.KeyCode.ButtonX or kc == Enum.KeyCode.ButtonB then
				pressed.throw = true
			elseif kc == Enum.KeyCode.ButtonSelect then
				onToggleHelp()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(io: InputObject)
		local kc = io.KeyCode
		local ut = io.UserInputType
		if ut == Enum.UserInputType.Keyboard then
			if KEYS_LEFT[kc] then
				held.left = false
			elseif KEYS_RIGHT[kc] then
				held.right = false
			elseif KEYS_JUMP[kc] then
				held.up = false
			elseif KEYS_DOWN[kc] then
				held.down = false
			elseif KEYS_ATTACK[kc] then
				held.attack = false
			elseif KEYS_BLOCK[kc] then
				held.block = false
			end
		elseif ut == Enum.UserInputType.MouseButton1 then
			held.attack = false
		elseif ut == Enum.UserInputType.MouseButton2 then
			held.block = false
		elseif ut == Enum.UserInputType.Gamepad1 then
			if kc == Enum.KeyCode.ButtonA then
				held.up = false
			elseif kc == Enum.KeyCode.ButtonR2 or kc == Enum.KeyCode.ButtonR1 then
				gamepadAttack = false
			elseif kc == Enum.KeyCode.ButtonL2 or kc == Enum.KeyCode.ButtonL1 then
				gamepadBlock = false
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.Gamepad1 then
			if io.KeyCode == Enum.KeyCode.Thumbstick1 then
				stick1 = Vector2.new(io.Position.X, io.Position.Y)
				Input.mode = "gamepad"
			elseif io.KeyCode == Enum.KeyCode.Thumbstick2 then
				stick2 = Vector2.new(io.Position.X, io.Position.Y)
				Input.mode = "gamepad"
			end
		elseif io.UserInputType == Enum.UserInputType.MouseMovement then
			if Input.mode == "gamepad" and io.Delta.Magnitude > 2 then
				Input.mode = "mouse"
			end
		end
	end)

	UserInputService.WindowFocusReleased:Connect(function()
		for k in held do
			held[k] = false
		end
		gamepadAttack, gamepadBlock = false, false
	end)

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		Input.mode = "touch"
	end
end

-- touch buttons call these
function Input.touchPress(name: string, down: boolean)
	Input.mode = "touch"
	if name == "jump" then
		held.up = down
		if down then
			pressed.jump = true
		end
	elseif name == "attack" then
		Input.touchAttack = down
		if down then
			pressed.attack = true
		end
	elseif name == "block" then
		Input.touchBlock = down
	elseif name == "throw" then
		if down then
			pressed.throw = true
		end
	end
end

-- Fill a fighter's input. `mouseWorld` is the world point under the cursor (mouse mode),
-- `autoTarget` is the nearest enemy position (used for gamepad/touch aim assist).
function Input.apply(input: any, neckX: number, neckY: number, facing: number, mouseWorld: Vector2?, autoTarget: Vector2?)
	local move = 0
	if held.left then
		move -= 1
	end
	if held.right then
		move += 1
	end
	local down = held.down
	if Input.mode == "gamepad" then
		if math.abs(stick1.X) > 0.3 then
			move = math.sign(stick1.X)
		end
		if stick1.Y < -0.65 then
			down = true
		end
	elseif Input.mode == "touch" then
		if math.abs(Input.touchMove) > 0.25 then
			move = math.sign(Input.touchMove)
		end
		down = down or Input.touchDown
	end
	input.moveX = move
	input.crouch = down
	input.jump = held.up
	input.attack = held.attack or gamepadAttack or Input.touchAttack
	input.block = held.block or gamepadBlock or Input.touchBlock

	if pressed.jump then
		input.jumpPressed = true
	end
	if pressed.attack then
		input.attackPressed = true
	end
	if pressed.throw then
		input.throwPressed = true
	end
	pressed.jump, pressed.attack, pressed.throw = false, false, false

	-- aim
	local aim: Vector2
	if Input.mode == "mouse" and mouseWorld then
		input.aimX, input.aimY = mouseWorld.X, mouseWorld.Y
		return
	elseif Input.mode == "gamepad" and stick2.Magnitude > 0.35 then
		aim = Vector2.new(stick2.X, stick2.Y).Unit
	elseif autoTarget then
		aim = (autoTarget - Vector2.new(neckX, neckY))
		if aim.Magnitude < 0.01 then
			aim = Vector2.new(facing, 0)
		else
			aim = aim.Unit
		end
	elseif move ~= 0 then
		aim = Vector2.new(move, 0)
	else
		aim = lastAim
	end
	lastAim = aim
	input.aimX = neckX + aim.X * 10
	input.aimY = neckY + aim.Y * 10
end

return Input
