SnowPlowLoopTask = ADInheritsFrom(AbstractTask)

SnowPlowLoopTask.debug = true
SnowPlowLoopTask.STATE_DRIVING = {}
SnowPlowLoopTask.STATE_RECOVERY = {}
SnowPlowLoopTask.STUCK_TIME = 1800
SnowPlowLoopTask.OBSTACLE_STOP_TIME = 15000
SnowPlowLoopTask.RECOVERY_MAX_ATTEMPTS = 3

function SnowPlowLoopTask:new(vehicle, loopWayPoints, snowMarkers)
    local o = SnowPlowLoopTask:create()
    o.vehicle = vehicle
    o.loopWayPoints = loopWayPoints
    o.snowMarkers = snowMarkers or {}
    o.stuckTimer = AutoDriveTON:new()
    o.obstacleStopTimer = AutoDriveTON:new()
    o.obstacleWarningShown = false
    o.recoveryAttempts = 0
    o.recoveryManeuver = nil
    o.state = SnowPlowLoopTask.STATE_DRIVING
    o.lastState = nil
    SnowPlowLoopTask.setStateNames(o)
    return o
end

function SnowPlowLoopTask:setUp()
    ADSnowPlowUtil.applySnowPlowSpeedOverride(self.vehicle)
    ADSnowPlowUtil.activateSnowTools(self.vehicle)
    self.vehicle.ad.drivePathModule:setWayPoints(self.loopWayPoints)
    self:updateActiveSnowTargetSlot()
end

function SnowPlowLoopTask:update(dt)
    if self.lastState ~= self.state then
        SnowPlowLoopTask.debugMsg(self.vehicle, "SnowPlowLoopTask:update %s -> %s", tostring(self:getStateName(self.lastState)), tostring(self:getStateName()))
        self.lastState = self.state
    end

    if self.state == SnowPlowLoopTask.STATE_RECOVERY then
        local status, reason = self.recoveryManeuver:update(dt)
        if status == ADRecoveryManeuver.STATUS_RUNNING then
            return
        elseif status == ADRecoveryManeuver.STATUS_SUCCEEDED then
            SnowPlowLoopTask.debugMsg(self.vehicle, "SnowPlowLoopTask:update recovery finished")
            self.stuckTimer:timer(false)
            self.obstacleStopTimer:timer(false)
            self.vehicle.ad.specialDrivingModule:releaseVehicle()
            self.recoveryManeuver = nil
            self.state = SnowPlowLoopTask.STATE_DRIVING
        elseif status == ADRecoveryManeuver.STATUS_FAILED or status == ADRecoveryManeuver.STATUS_ABORTED then
            self:stopAfterRecoveryFailure(reason)
        end
        return
    elseif self.vehicle.ad.drivePathModule:isTargetReached() then
        self:finished()
    else
        ADSnowPlowUtil.activateSnowTools(self.vehicle)
        if self.vehicle.lastSpeedReal ~= nil and self.vehicle.lastSpeedReal > 0.5 then
            self.recoveryAttempts = 0
            self.obstacleStopTimer:timer(false)
            self.obstacleWarningShown = false
        end
        if self:checkForStuck(dt) then
            return
        end
        self:updateActiveSnowTargetSlot()
        self.vehicle.ad.drivePathModule:update(dt)
    end
end

function SnowPlowLoopTask:updateActiveSnowTargetSlot()
    local currentWayPointIndex = self.vehicle.ad.drivePathModule:getCurrentWayPointIndex()
    if currentWayPointIndex == nil then
        currentWayPointIndex = 1
    end

    local targetMarkersByWayPointId = {}
    for slot = 1, 3 do
        local marker = self.vehicle.ad.stateModule:getSnowPlowMarker(slot)
        if marker ~= nil and marker.id ~= nil then
            targetMarkersByWayPointId[marker.id] = { slot = slot, marker = marker }
        end
    end

    for index = currentWayPointIndex + 1, #self.loopWayPoints do
        local wayPoint = self.loopWayPoints[index]
        if wayPoint ~= nil and wayPoint.id ~= nil and targetMarkersByWayPointId[wayPoint.id] ~= nil then
            local marker = targetMarkersByWayPointId[wayPoint.id]
            self.vehicle.ad.stateModule:setCurrentSnowPlowMarkerSlot(marker.slot)
            return
        end
    end

    self.vehicle.ad.stateModule:setCurrentSnowPlowMarkerSlot(1)
end

function SnowPlowLoopTask:checkForStuck(dt)
    local isStuck = self.vehicle.lastSpeedReal ~= nil
        and self.vehicle.lastSpeedReal <= 0.0002
        and not self.vehicle.ad.specialDrivingModule:isStoppingVehicle()
    self.stuckTimer:timer(isStuck, SnowPlowLoopTask.STUCK_TIME, dt)

    local collisionDetectionModule = self.vehicle.ad.collisionDetectionModule
    local isObstacleStopped = self.vehicle.lastSpeedReal ~= nil
        and self.vehicle.lastSpeedReal <= 0.0002
        and self.vehicle.ad.specialDrivingModule:isStoppingVehicle()
        and collisionDetectionModule ~= nil
        and collisionDetectionModule.detectedObstable == true
    self.obstacleStopTimer:timer(isObstacleStopped, SnowPlowLoopTask.OBSTACLE_STOP_TIME, dt)

    if not isObstacleStopped then
        self.obstacleWarningShown = false
    end

    if self.obstacleStopTimer:done() and not self.obstacleWarningShown then
        local wayPointIndex = self.vehicle.ad.drivePathModule:getCurrentWayPointIndex()
        SnowPlowLoopTask.debugMsg(
            self.vehicle,
            "SnowPlowLoopTask: persistent obstacle; waiting speed=%.6f waypoint=%s",
            self.vehicle.lastSpeedReal or -1,
            tostring(wayPointIndex)
        )
        AutoDriveMessageEvent.sendMessageOrNotification(
            self.vehicle,
            ADMessagesManager.messageTypes.WARN,
            "Snow plow route blocked; waiting for obstacle to clear",
            10000
        )
        self.obstacleWarningShown = true
    end

    if self.stuckTimer:done() then
        return self:startRecovery("immobile")
    end

    return false
end

function SnowPlowLoopTask:startRecovery(reason)
    self.recoveryAttempts = self.recoveryAttempts + 1
    if self.recoveryAttempts > SnowPlowLoopTask.RECOVERY_MAX_ATTEMPTS then
        SnowPlowLoopTask.debugMsg(self.vehicle, "SnowPlowLoopTask:recovery failed after %d attempts", self.recoveryAttempts - 1)
        self:stopAfterRecoveryFailure("maxAttempts")
        return true
    end

    SnowPlowLoopTask.debugMsg(self.vehicle, "SnowPlowLoopTask: starting recovery reason=%s attempt=%d", tostring(reason), self.recoveryAttempts)
    self.stuckTimer:timer(false)
    self.obstacleStopTimer:timer(false)
    self.recoveryManeuver = ADRecoveryManeuver:new(self.vehicle, ADSnowPlowUtil.createRecoveryProfile(ADSnowPlowUtil.areSnowToolsLowered(self.vehicle)))
    local started, startReason = self.recoveryManeuver:start({
        attempt = self.recoveryAttempts,
        caller = "SnowPlowLoopTask",
        trigger = reason
    })
    if not started then
        self:stopAfterRecoveryFailure(startReason)
        return true
    end
    self.state = SnowPlowLoopTask.STATE_RECOVERY
    return true
end

function SnowPlowLoopTask:stopAfterRecoveryFailure(reason)
    SnowPlowLoopTask.debugMsg(self.vehicle, "SnowPlowLoopTask: recovery failed; stopping AutoDrive reason=%s", tostring(reason))
    self.vehicle.ad.taskModule:abortAllTasks()
    self.vehicle.ad.taskModule:addTask(StopAndDisableADTask:new(self.vehicle, ADTaskModule.DONT_PROPAGATE))
end

function SnowPlowLoopTask:abort()
    if self.recoveryManeuver ~= nil then
        self.recoveryManeuver:abort("taskAbort")
        self.recoveryManeuver = nil
    end
    ADSnowPlowUtil.deactivateSnowTools(self.vehicle)
    ADSnowPlowUtil.clearSnowPlowSpeedOverride(self.vehicle)
end

function SnowPlowLoopTask:finished(propagate)
    ADSnowPlowUtil.clearSnowPlowSpeedOverride(self.vehicle)
    self.vehicle.ad.taskModule:setCurrentTaskFinished(propagate)
end

function SnowPlowLoopTask:getI18nInfo()
    return "$l10n_AD_task_snow_plow_loop;"
end

function SnowPlowLoopTask:setStateNames()
    self.stateNames = {}
    self.stateNames[SnowPlowLoopTask.STATE_DRIVING] = "STATE_DRIVING"
    self.stateNames[SnowPlowLoopTask.STATE_RECOVERY] = "STATE_RECOVERY"
end

function SnowPlowLoopTask:getStateName(state)
    return self.stateNames[state or self.state]
end

function SnowPlowLoopTask.debugMsg(vehicle, debugText, ...)
    if SnowPlowLoopTask.debug then
        AutoDrive.debugMsg(vehicle, debugText, ...)
    end
end
