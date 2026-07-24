ADRecoveryManeuver = {}

ADRecoveryManeuver.STATUS_RUNNING = "RUNNING"
ADRecoveryManeuver.STATUS_SUCCEEDED = "SUCCEEDED"
ADRecoveryManeuver.STATUS_FAILED = "FAILED"
ADRecoveryManeuver.STATUS_ABORTED = "ABORTED"

ADRecoveryManeuver.PHASE_MOVE = "MOVE"
ADRecoveryManeuver.PHASE_STOP = "STOP"
ADRecoveryManeuver.PHASE_ACTION = "ACTION"
ADRecoveryManeuver.PHASE_WAIT_FOR = "WAIT_FOR"

ADRecoveryManeuver.REASON_INVALID_PROFILE = "invalidProfile"
ADRecoveryManeuver.REASON_MOVEMENT_TIMEOUT = "movementTimeout"
ADRecoveryManeuver.REASON_STOP_TIMEOUT = "stopTimeout"
ADRecoveryManeuver.REASON_ACTION_UNSUPPORTED = "actionUnsupported"
ADRecoveryManeuver.REASON_ACTION_ERROR = "actionError"
ADRecoveryManeuver.REASON_VERIFICATION_TIMEOUT = "verificationTimeout"
ADRecoveryManeuver.REASON_VERIFICATION_ERROR = "verificationError"
ADRecoveryManeuver.REASON_ABORTED = "abortedByCaller"
ADRecoveryManeuver.SAFE_ACTION_MAX_SPEED = 0.00002

function ADRecoveryManeuver:new(vehicle, profile)
    local o = {
        vehicle = vehicle,
        profile = profile,
        context = nil,
        status = nil,
        reason = nil,
        phaseIndex = 0,
        phaseElapsed = 0,
        actionIssued = false,
        startX = nil,
        startZ = nil,
        directionX = nil,
        directionZ = nil,
        currentPhaseName = nil,
        currentDt = 0
    }
    setmetatable(o, {__index = self})
    return o
end

function ADRecoveryManeuver:validateProfile()
    if self.vehicle == nil or type(self.profile) ~= "table" then
        return false
    end
    if type(self.vehicle.components) ~= "table"
        or self.vehicle.components[1] == nil
        or self.vehicle.components[1].node == nil
        or self.vehicle.ad == nil
        or self.vehicle.ad.specialDrivingModule == nil
    then
        return false
    end
    local drivingModule = self.vehicle.ad.specialDrivingModule
    if type(drivingModule.stopVehicle) ~= "function"
        or type(drivingModule.update) ~= "function"
        or type(drivingModule.releaseVehicle) ~= "function"
    then
        return false
    end
    if type(self.profile.name) ~= "string" or self.profile.name == "" then
        return false
    end
    if type(self.profile.phases) ~= "table" or #self.profile.phases == 0 then
        return false
    end

    for index, phase in ipairs(self.profile.phases) do
        if type(phase) ~= "table" or type(phase.name) ~= "string" or phase.name == "" then
            return false
        elseif phase.type == ADRecoveryManeuver.PHASE_MOVE then
            if (phase.direction ~= -1 and phase.direction ~= 1)
                or type(phase.distance) ~= "number" or phase.distance <= 0
                or type(phase.speed) ~= "number" or phase.speed <= 0
                or type(phase.timeout) ~= "number" or phase.timeout <= 0
            then
                return false
            end
        elseif phase.type == ADRecoveryManeuver.PHASE_STOP then
            if type(phase.maxSpeed) ~= "number" or phase.maxSpeed <= 0
                or type(phase.timeout) ~= "number" or phase.timeout <= 0
            then
                return false
            end
        elseif phase.type == ADRecoveryManeuver.PHASE_ACTION then
            if type(phase.action) ~= "function" then
                return false
            end
            local previousPhase = self.profile.phases[index - 1]
            if previousPhase == nil or previousPhase.type ~= ADRecoveryManeuver.PHASE_STOP then
                return false
            end
        elseif phase.type == ADRecoveryManeuver.PHASE_WAIT_FOR then
            if type(phase.verify) ~= "function"
                or type(phase.timeout) ~= "number" or phase.timeout <= 0
                or phase.timeout ~= phase.timeout
                or phase.timeout == math.huge
                or phase.timeout == -math.huge
            then
                return false
            end
            local minDuration = phase.minDuration
            if minDuration == nil then
                minDuration = 0
            end
            if type(minDuration) ~= "number"
                or minDuration < 0
                or minDuration ~= minDuration
                or minDuration == math.huge
                or minDuration == -math.huge
                or minDuration > phase.timeout
            then
                return false
            end
            local previousPhase = self.profile.phases[index - 1]
            if previousPhase == nil or previousPhase.type ~= ADRecoveryManeuver.PHASE_ACTION then
                return false
            end
        else
            return false
        end
    end
    return true
end

function ADRecoveryManeuver:start(context)
    if self.status ~= nil or not self:validateProfile() then
        return false, ADRecoveryManeuver.REASON_INVALID_PROFILE
    end

    self.context = context or {}
    self.status = ADRecoveryManeuver.STATUS_RUNNING
    self.reason = nil
    AutoDrive.debugMsg(
        self.vehicle,
        "RecoveryManeuver start profile=%s caller=%s attempt=%s",
        self.profile.name,
        tostring(self.context.caller),
        tostring(self.context.attempt)
    )
    self:enterPhase(1)
    return true, nil
end

function ADRecoveryManeuver:enterPhase(index)
    self.phaseIndex = index
    self.phaseElapsed = 0
    self.actionIssued = false

    if index > #self.profile.phases then
        self.currentPhaseName = nil
        self:stopVehicle(self.currentDt)
        self.vehicle.ad.specialDrivingModule:releaseVehicle()
        self.status = ADRecoveryManeuver.STATUS_SUCCEEDED
        AutoDrive.debugMsg(
            self.vehicle,
            "RecoveryManeuver succeeded profile=%s caller=%s attempt=%s",
            self.profile.name,
            tostring(self.context.caller),
            tostring(self.context.attempt)
        )
        return
    end

    local phase = self.profile.phases[index]
    self.currentPhaseName = phase.name
    if phase.type == ADRecoveryManeuver.PHASE_MOVE then
        self.vehicle.ad.specialDrivingModule:releaseVehicle()
        self:captureMovementStart()
    end
    local distance = phase.type == ADRecoveryManeuver.PHASE_MOVE and self:getSignedDistance(phase.direction) or nil
    AutoDrive.debugMsg(
        self.vehicle,
        "RecoveryManeuver phase profile=%s phase=%s index=%d attempt=%s elapsed=%.0f distance=%s direction=%s targetDistance=%s speed=%s timeout=%s",
        self.profile.name,
        phase.name,
        index,
        tostring(self.context.attempt),
        self.phaseElapsed,
        tostring(distance),
        tostring(phase.direction),
        tostring(phase.distance),
        tostring(phase.speed),
        tostring(phase.timeout)
    )
end

function ADRecoveryManeuver:captureMovementStart()
    self.startX, _, self.startZ = getWorldTranslation(self.vehicle.components[1].node)
    self.directionX, _, self.directionZ = AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
end

function ADRecoveryManeuver:getSignedDistance(direction)
    local x, _, z = getWorldTranslation(self.vehicle.components[1].node)
    local distance = (x - self.startX) * self.directionX + (z - self.startZ) * self.directionZ
    return direction < 0 and -distance or distance
end

function ADRecoveryManeuver:stopVehicle(dt)
    self.vehicle.ad.specialDrivingModule:stopVehicle()
    self.vehicle.ad.specialDrivingModule:update(dt or 0)
end

function ADRecoveryManeuver:updateMovePhase(phase, dt)
    local distance = self:getSignedDistance(phase.direction)
    if distance >= phase.distance then
        self:stopVehicle(dt)
        self:enterPhase(self.phaseIndex + 1)
    elseif self.phaseElapsed >= phase.timeout then
        self:fail(ADRecoveryManeuver.REASON_MOVEMENT_TIMEOUT)
    else
        local forwards = phase.direction > 0
        AutoDrive.driveInDirection(self.vehicle, dt, 30, 1, 0.2, 20, true, forwards, 0, phase.direction, phase.speed, 1)
    end
end

function ADRecoveryManeuver:updateStopPhase(phase, dt)
    self:stopVehicle(dt)
    if math.abs(self.vehicle.lastSpeedReal or 0) <= phase.maxSpeed then
        self:enterPhase(self.phaseIndex + 1)
    elseif self.phaseElapsed >= phase.timeout then
        self:fail(ADRecoveryManeuver.REASON_STOP_TIMEOUT)
    end
end

function ADRecoveryManeuver:updateActionPhase(phase)
    self:stopVehicle(self.currentDt)
    if math.abs(self.vehicle.lastSpeedReal or 0) > ADRecoveryManeuver.SAFE_ACTION_MAX_SPEED then
        return
    end
    if self.actionIssued then
        return
    end
    self.actionIssued = true
    local ok, result = pcall(function()
        return phase.action(self.context, self.vehicle)
    end)
    if not ok or result == nil or (result ~= true and result ~= false) then
        self:fail(ADRecoveryManeuver.REASON_ACTION_ERROR)
    elseif result == false then
        self:fail(ADRecoveryManeuver.REASON_ACTION_UNSUPPORTED)
    else
        self:enterPhase(self.phaseIndex + 1)
    end
end

function ADRecoveryManeuver:updateWaitForPhase(phase)
    self:stopVehicle(self.currentDt)
    if math.abs(self.vehicle.lastSpeedReal or 0) > ADRecoveryManeuver.SAFE_ACTION_MAX_SPEED then
        if self.phaseElapsed >= phase.timeout then
            self:fail(ADRecoveryManeuver.REASON_VERIFICATION_TIMEOUT)
        end
        return
    end
    local minDuration = phase.minDuration
    if minDuration == nil then
        minDuration = 0
    end
    if self.phaseElapsed < minDuration then
        return
    end
    local ok, result = pcall(function()
        return phase.verify(self.context, self.vehicle)
    end)
    if not ok or (result ~= true and result ~= false) then
        self:fail(ADRecoveryManeuver.REASON_VERIFICATION_ERROR)
    elseif result == true then
        self:enterPhase(self.phaseIndex + 1)
    elseif self.phaseElapsed >= phase.timeout then
        self:fail(ADRecoveryManeuver.REASON_VERIFICATION_TIMEOUT)
    end
end

function ADRecoveryManeuver:update(dt)
    if self.status ~= ADRecoveryManeuver.STATUS_RUNNING then
        return self.status, self.reason
    end
    local phase = self.profile.phases[self.phaseIndex]
    self.currentDt = dt or 0
    self.phaseElapsed = self.phaseElapsed + self.currentDt
    if phase.type == ADRecoveryManeuver.PHASE_MOVE then
        self:updateMovePhase(phase, self.currentDt)
    elseif phase.type == ADRecoveryManeuver.PHASE_STOP then
        self:updateStopPhase(phase, self.currentDt)
    elseif phase.type == ADRecoveryManeuver.PHASE_ACTION then
        self:updateActionPhase(phase)
    elseif phase.type == ADRecoveryManeuver.PHASE_WAIT_FOR then
        self:updateWaitForPhase(phase)
    else
        self:fail(ADRecoveryManeuver.REASON_INVALID_PROFILE)
    end
    return self.status, self.reason
end

function ADRecoveryManeuver:getCurrentMoveDistance()
    local phase = self.profile ~= nil and self.profile.phases ~= nil and self.profile.phases[self.phaseIndex] or nil
    if phase ~= nil and phase.type == ADRecoveryManeuver.PHASE_MOVE and self.startX ~= nil then
        return self:getSignedDistance(phase.direction)
    end
    return nil
end

function ADRecoveryManeuver:fail(reason)
    if self.status ~= ADRecoveryManeuver.STATUS_RUNNING then
        return self.status, self.reason
    end
    local distance = self:getCurrentMoveDistance()
    self:stopVehicle(self.currentDt)
    self.status = ADRecoveryManeuver.STATUS_FAILED
    self.reason = reason
    AutoDrive.debugMsg(
        self.vehicle,
        "RecoveryManeuver failed profile=%s phase=%s index=%d reason=%s elapsed=%.0f attempt=%s distance=%s",
        self.profile.name,
        tostring(self.currentPhaseName),
        self.phaseIndex,
        tostring(reason),
        self.phaseElapsed,
        tostring(self.context.attempt),
        tostring(distance)
    )
    return self.status, self.reason
end

function ADRecoveryManeuver:abort(reason)
    if self.status ~= ADRecoveryManeuver.STATUS_RUNNING then
        return self.status, self.reason
    end
    local distance = self:getCurrentMoveDistance()
    self:stopVehicle(self.currentDt)
    self.status = ADRecoveryManeuver.STATUS_ABORTED
    self.reason = reason or ADRecoveryManeuver.REASON_ABORTED
    AutoDrive.debugMsg(
        self.vehicle,
        "RecoveryManeuver aborted profile=%s phase=%s index=%d reason=%s elapsed=%.0f attempt=%s distance=%s",
        self.profile.name,
        tostring(self.currentPhaseName),
        self.phaseIndex,
        tostring(self.reason),
        self.phaseElapsed,
        tostring(self.context.attempt),
        tostring(distance)
    )
    return self.status, self.reason
end
