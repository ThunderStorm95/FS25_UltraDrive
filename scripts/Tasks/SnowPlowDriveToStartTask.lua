SnowPlowDriveToStartTask = ADInheritsFrom(DriveToDestinationTask)

SnowPlowDriveToStartTask.debug = true
SnowPlowDriveToStartTask.STATE_RECOVERY = 3
SnowPlowDriveToStartTask.STUCK_TIME = 1800
SnowPlowDriveToStartTask.RECOVERY_MAX_ATTEMPTS = 3

function SnowPlowDriveToStartTask:new(vehicle, destinationID)
    local o = SnowPlowDriveToStartTask:create()
    o.vehicle = vehicle
    o.destinationID = destinationID
    o.trailers = nil
    o.stuckTimer = AutoDriveTON:new()
    o.recoveryAttempts = 0
    o.recoveryManeuver = nil
    o.lastState = nil
    return o
end

function SnowPlowDriveToStartTask:setUp()
    ADSnowPlowUtil.applySnowPlowSpeedOverride(self.vehicle)
    ADSnowPlowUtil.activateSnowTools(self.vehicle)
    DriveToDestinationTask.setUp(self)
end

function SnowPlowDriveToStartTask:update(dt)
    if self.lastState ~= self.state then
        SnowPlowDriveToStartTask.debugMsg(self.vehicle, "SnowPlowDriveToStartTask:update %s -> %s destination=%s", tostring(self.lastState), tostring(self.state), tostring(self.destinationID))
        self.lastState = self.state
    end

    ADSnowPlowUtil.applySnowPlowSpeedOverride(self.vehicle)

    if self.state == SnowPlowDriveToStartTask.STATE_RECOVERY then
        local status, reason = self.recoveryManeuver:update(dt)
        if status == ADRecoveryManeuver.STATUS_RUNNING then
            return
        elseif status == ADRecoveryManeuver.STATUS_SUCCEEDED then
            SnowPlowDriveToStartTask.debugMsg(self.vehicle, "SnowPlowDriveToStartTask:update recovery finished destination=%s", tostring(self.destinationID))
            self.stuckTimer:timer(false)
            self.vehicle.ad.specialDrivingModule:releaseVehicle()
            self.recoveryManeuver = nil
            self.state = DriveToDestinationTask.STATE_DRIVING
        elseif status == ADRecoveryManeuver.STATUS_FAILED or status == ADRecoveryManeuver.STATUS_ABORTED then
            self:stopAfterRecoveryFailure(reason)
        end
        return
    end

    ADSnowPlowUtil.activateSnowTools(self.vehicle)
    if self.vehicle.lastSpeedReal ~= nil and self.vehicle.lastSpeedReal > 0.5 then
        self.recoveryAttempts = 0
    end
    if self.state == DriveToDestinationTask.STATE_DRIVING and self:checkForStuck(dt) then
        return
    end

    DriveToDestinationTask.update(self, dt)
end

function SnowPlowDriveToStartTask:checkForStuck(dt)
    local isStuck = self.vehicle.lastSpeedReal ~= nil
        and self.vehicle.lastSpeedReal <= 0.0002
        and not self.vehicle.ad.specialDrivingModule:isStoppingVehicle()
    self.stuckTimer:timer(isStuck, SnowPlowDriveToStartTask.STUCK_TIME, dt)

    if self.stuckTimer:done() then
        self.recoveryAttempts = self.recoveryAttempts + 1
        if self.recoveryAttempts > SnowPlowDriveToStartTask.RECOVERY_MAX_ATTEMPTS then
            SnowPlowDriveToStartTask.debugMsg(self.vehicle, "SnowPlowDriveToStartTask:recovery failed after %d attempts destination=%s", self.recoveryAttempts - 1, tostring(self.destinationID))
            self.vehicle.ad.taskModule:abortAllTasks()
            self.vehicle.ad.taskModule:addTask(StopAndDisableADTask:new(self.vehicle, ADTaskModule.DONT_PROPAGATE))
            return true
        end

        SnowPlowDriveToStartTask.debugMsg(self.vehicle, "SnowPlowDriveToStartTask:checkForStuck starting recovery attempt=%d destination=%s", self.recoveryAttempts, tostring(self.destinationID))
        self.stuckTimer:timer(false)
        self.recoveryManeuver = ADRecoveryManeuver:new(self.vehicle, ADSnowPlowUtil.createRecoveryProfile(ADSnowPlowUtil.areSnowToolsLowered(self.vehicle)))
        local started, reason = self.recoveryManeuver:start({
            attempt = self.recoveryAttempts,
            caller = "SnowPlowDriveToStartTask",
            destination = self.destinationID
        })
        if not started then
            self:stopAfterRecoveryFailure(reason)
            return true
        end
        self.state = SnowPlowDriveToStartTask.STATE_RECOVERY
        return true
    end

    return false
end

function SnowPlowDriveToStartTask:stopAfterRecoveryFailure(reason)
    SnowPlowDriveToStartTask.debugMsg(self.vehicle, "SnowPlowDriveToStartTask: recovery failed; stopping AutoDrive reason=%s destination=%s", tostring(reason), tostring(self.destinationID))
    self.vehicle.ad.taskModule:abortAllTasks()
    self.vehicle.ad.taskModule:addTask(StopAndDisableADTask:new(self.vehicle, ADTaskModule.DONT_PROPAGATE))
end

function SnowPlowDriveToStartTask:abort()
    if self.recoveryManeuver ~= nil then
        self.recoveryManeuver:abort("taskAbort")
        self.recoveryManeuver = nil
    end
    ADSnowPlowUtil.deactivateSnowTools(self.vehicle)
    ADSnowPlowUtil.clearSnowPlowSpeedOverride(self.vehicle)
end

function SnowPlowDriveToStartTask:finished(propagate)
    ADSnowPlowUtil.clearSnowPlowSpeedOverride(self.vehicle)
    self.vehicle.ad.taskModule:setCurrentTaskFinished(propagate)
end

function SnowPlowDriveToStartTask:getI18nInfo()
    if self.state == DriveToDestinationTask.STATE_PATHPLANNING then
        local actualState, maxStates, steps, max_pathfinder_steps = self.vehicle.ad.pathFinderModule:getCurrentState()
        return "$l10n_AD_task_pathfinding;" .. string.format(" %d / %d - %d / %d", actualState, maxStates, steps, max_pathfinder_steps)
    end
    return "$l10n_AD_task_drive_to_snow_start;"
end

function SnowPlowDriveToStartTask.debugMsg(vehicle, debugText, ...)
    if SnowPlowDriveToStartTask.debug then
        AutoDrive.debugMsg(vehicle, debugText, ...)
    end
end
