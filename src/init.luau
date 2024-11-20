--!strict
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
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

export type InterfaceData = {
    SpinButton: ImageButton | TextButton,
    Flipper: ImageLabel,
    SliceTemplate: ImageLabel,
    SliceContainer: ImageLabel,
    MTXButtons: {ImageButton}
}

export type ConfigurationTable = {
    Rewards: {RewardData},
    Speed: number,
    DecayRate: number,
    Interface: InterfaceData
}

-- Return false if they don't have any spins, otherwise return the index of the reward the spin animation should land on
export type SpinCallback = () -> boolean | number
export type RewardCallback = (reward: RewardData) -> nil

-- Class
local Spinner = {}
Spinner.__index = Spinner

function Spinner.new(config: ConfigurationTable)
    local self = setmetatable({}, Spinner)

    -- External refs
    self.Configuration = config
    self.SpinButton = config.Interface.SpinButton
    self.Flipper = config.Interface.Flipper
    self.Container = config.Interface.SliceContainer
    self.MTXButtons = config.Interface.MTXButtons
    
    -- Internal refs
    self._sliceTemplate = config.Interface.SliceTemplate
    self._spinCallback = nil :: SpinCallback?
    self._rewardCallback = nil :: RewardCallback?
    self._activeSlices = {} :: {ImageLabel}
    self._stepped = nil :: RBXScriptConnection?
    self._flipperConnection = nil :: RBXScriptConnection?

    -- State
    self._animationAlpha = 0
    self._spinning = false
    self._requestingSpin = false
    self._canBuySpins = true

    -- Setup
    self:_initSpinner()

    -- Handle PolicyService
    self:_initPolicyService()

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


-- Ensure Player has access to paid random items, hide purchase buttons if not
function Spinner:_initPolicyService()
    local success, result = pcall(function()
        return PolicyService:GetPolicyInfoForPlayerAsync(Players.LocalPlayer)
    end)
    
    -- Async failed
    if not success then
        warn(result)
    
    -- Restricted
    elseif result.ArePaidRandomItemsRestricted then
        self._canBuySpins = false
        for _, button in self.MTXButtons do
            button.Visible = false
        end
    end
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

    -- variables
    local sliceRotation = 360 / #self.Configuration.Rewards
    local speed = self.Configuration.Speed :: number
    local isDecaying = false
    local currentIndex = self:_getCurrentIndex() :: number
    local lastIndex = currentIndex

    -- sfx
    local sound = Instance.new("Sound")
    sound.Parent = script
    sound.SoundId = "rbxassetid://9119713951"
    
    -- distance to be initially travelled
    local initialDistance = 360 * 5 -- force 2 spin minimum
    local distanceToTravel = initialDistance

    -- target reward may be a slice BEFORE the current index. handle this, and calculate distance to reward
    local slicesToReward = if rewardIndex - currentIndex >= 0 then rewardIndex - currentIndex else #self.Configuration.Rewards - rewardIndex
    local distanceToReward = sliceRotation * slicesToReward

    -- add extra spins for decay
    distanceToReward += 360 * 4

    -- assess full target angle, account for container's current angle
    local targetAngle = distanceToTravel + distanceToReward - (self.Container.Rotation % 360)

    -- apply initial rotation to flipper
    local flipperOffset = 15
    self.Flipper.Rotation = flipperOffset

    -- establish connection
    self._stepped = RunService.RenderStepped:Connect(function(deltaTime: number)
        -- determine if decay should begin, if so, add distancetoreward
        if math.floor(distanceToTravel) <= 0 and not isDecaying then
            distanceToTravel += distanceToReward
            isDecaying = true

        -- ended, snap to angle and cleanup
        elseif math.floor(distanceToTravel) <= 0 and isDecaying then
            if self._stepped then
                self.Container.Rotation = -targetAngle
                self._stepped:Disconnect()
                self._stepped = nil

                self._spinning = false
            end
            if self._flipperConnection then
                self.Flipper.Rotation = 0
                self._flipperConnection:Disconnect()
                self._flipperConnection = nil
            end
            if sound then
                sound:Destroy()
            end

            return
        end

        -- apply alpha to speed for decay
        if isDecaying then
            local alpha = TweenService:GetValue(distanceToTravel / distanceToReward, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
            alpha = math.clamp(alpha, 0.05, 1)
            speed = self.Configuration.Speed * alpha

            -- apply rotation to flipper if new slice is entered, and if alpha is low enough, setup auto-correcting listener
            if alpha <= 0.3 then
                if not self._flipperConnection then
                    self._flipperConnection = self.Flipper:GetPropertyChangedSignal("Rotation"):Connect(function() -- TODO clean this ugliness up @Michael
                        if self.Flipper.Rotation == flipperOffset then
                            task.wait(0.02)
                            self.Flipper.Rotation = 0
                        end
                    end)
                    self.Flipper.Rotation = 0
                end
            end
        end

        -- apply flipper effects if new slice was entered
        currentIndex = self:_getCurrentIndex()
        if currentIndex ~= lastIndex then
            lastIndex = currentIndex

            SoundService:PlayLocalSound(sound)
            self.Flipper.Rotation = flipperOffset
        end

        -- apply rotation
        self.Container.Rotation -= speed * deltaTime
        distanceToTravel -= speed * deltaTime
    end)
end

-- Returns the current reward index based on the animation angle
function Spinner:_getCurrentIndex(): number
    if self.Container.Rotation % 360 == 0 then
        return 1
    end

    local degreesPerIndex = 360 / #self.Configuration.Rewards
    local assessmentDegree = self.Container.Rotation % 360
    --local ccwIndex = math.round(assessmentDegree / degreesPerIndex) + 1 -- counter clockwise
    local cwIndex = math.abs(math.round(assessmentDegree / degreesPerIndex) - 1 - #self.Configuration.Rewards) -- clockwise

    return cwIndex
end

return Spinner