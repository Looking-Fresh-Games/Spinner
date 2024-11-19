--!strict
local RunService = game:GetService("RunService")
--[[
    Spinner.lua
    Author: Zach Curtis (InfinityDesign)

    Description: Modular ability spinner =
]]--

-- Services

-- Types
export type RewardData = {
    Icon: string,
    Probability: number,
    Color: Color3,
}

export type ConfigurationTable = {
    Rewards: {RewardData},
    AngularVelocity: number,
    DecayRate: number,
}

-- Return false if they don't have any spins, otherwise return the index of the reward the spin animation should land on
export type SpinCallback = () -> boolean | number
export type RewardCallback = (reward: RewardData) -> nil

-- Class
local Spinner = {}
Spinner.__index = Spinner

function Spinner.new(config: ConfigurationTable, spinButton: ImageButton | TextButton, flipper: ImageLabel, slice: ImageLabel, sliceContainer: ImageLabel | Frame)
    local self = setmetatable({}, Spinner)

    -- External refs
    self.Configuration = config
    self.SpinButton = spinButton
    self.Flipper = flipper
    self.Container = sliceContainer
    
    -- Internal refs
    self._sliceTemplate = slice
    self._spinCallback = nil :: SpinCallback?
    self._rewardCallback = nil :: RewardCallback?
    self._activeSlices = {} :: {ImageLabel}
    self._stepped = nil :: RBXScriptConnection?

    -- State
    self._animationAlpha = 0
    self._spinning = false
    self._requestingSpin = false

    -- Setup
    self:_initSpinner()

    return self
end

-- Binds a function that is called to check if the local player can spin
function Spinner:BindSpinCallback(spinCallback: SpinCallback)
    self._spinCallback = spinCallback
end

-- Binds the function that is called with the results of the spin
function Spinner:BindRewardCallback(rewardCallback: RewardCallback)
    self._rewardCallback = rewardCallback
end

-- Used to force a spin externally, such as in ProcessReceipt
function Spinner:ForceSpin(rewardIndex: number)
    self:_spin(rewardIndex)
end


-- Setup the spinner UI, mostly just adding the slices around the 
function Spinner:_initSpinner()
    -- Angle per slice based on the number of rewards
    local sliceRotation = 360 / #self.Configuration.Rewards

    -- Iterate the rewards and create a slice element for each one
    for index: number, rewardData: RewardData in self.Configuration.Rewards :: {RewardData} do
        local slice = self._sliceTemplate:Clone()
        local rewardIcon = slice:FindFirstChild("RewardIcon") :: ImageLabel?

        if rewardIcon then
            rewardIcon.Image = rewardData.Icon
        end

        slice.Rotation = (index - 1) * sliceRotation
        slice.ImageColor3 = rewardData.Color
        slice.Visible = true
        slice.Parent = self.Container
    end

    -- Player is attempting to spin the spinner
    self.SpinButton.Activated:Connect(function(_inputObject: InputObject)
        -- Debounce
        if 
            self._spinning == true
            or self._spinCallback == nil
            or self._requestingSpin == true 
        then
            return
        end

        -- Debounce the request to the server
        self._requestingSpin = true

        -- Callback returns false if they don't have any spins left, or the reward index selected on the server
        local callbackResult = self._spinCallback()

        -- Free up the request debounce
        self._requestingSpin = false

        if type(callbackResult) == "number" then
            self:_spin(callbackResult)
        end
    end)
end

-- Spin the wheel
function Spinner:_spin(rewardIndex: number)
    self._spinning = true

    local sliceRotation = 360 / #self.Configuration.Rewards
    
    local currentIndex = self:_getCurrentIndex()
    local distanceToTarget -- Distance to the target in angles

    if rewardIndex > currentIndex then
        distanceToTarget = (rewardIndex - currentIndex) * sliceRotation
    else
        distanceToTarget = (rewardIndex + #self.Configuration.Rewards) * sliceRotation
    end

    -- Distance to target in alpha
    local alphaToTarget = 360 / distanceToTarget

    print("weeeeeeee")

    self._stepped = RunService.RenderStepped:Connect(function(deltaTime: number)

    end)

    self._spinning = false
end

-- Returns the current reward index based on the animation angle
function Spinner:_getCurrentIndex(): number
    if self._animationAlpha == 0 then
        return 1
    end

    local alphaPerIndex = 1 / #self.Configuration.Rewards

    return math.round(self._animationAlpha / alphaPerIndex) + 1
end

return Spinner