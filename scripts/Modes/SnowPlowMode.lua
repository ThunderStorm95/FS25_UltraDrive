SnowPlowMode = ADInheritsFrom(AbstractMode)

SnowPlowMode.STATE_DRIVE_TO_START = 1
SnowPlowMode.STATE_LOOP = 2
SnowPlowMode.STATE_FINISHED = 3

function SnowPlowMode:new(vehicle)
    local o = SnowPlowMode:create()
    o.vehicle = vehicle
    SnowPlowMode.reset(o)
    return o
end

function SnowPlowMode:reset()
    if self.state ~= nil and self.state ~= SnowPlowMode.STATE_FINISHED then
        ADSnowPlowUtil.settleServicePay(self, "routeStopped")
        ADSnowPlowUtil.deactivateSnowTools(self.vehicle)
    end

    self:restoreSnowRouteState()
    self.loopWayPoints = nil
    self.loopChain = nil
    self.loopTask = nil
    self.startMarker = nil
    self.startWayPointId = nil
    self.driveToStartBeforeLoop = false
    self.loopRouteLabel = nil
    self.loopRouteType = nil
    self.previousSpeedLimit = nil
    self.previousFieldSpeedLimit = nil
    self.state = SnowPlowMode.STATE_FINISHED
    self.vehicle.ad.stateModule:setCurrentSnowPlowMarkerSlot(nil)
    ADSnowPlowUtil.startServiceSession(self)
end

function SnowPlowMode:start(user)
    if not self.vehicle.ad.stateModule:isActive() then
        self.vehicle:startAutoDrive()
    end

    local selectedMarkers = self:getSelectedSnowMarkers()
    local loopChain, reason = ADCircularRouteUtil.createSnowPlowLoopChain(self.vehicle, selectedMarkers)
    local firstLoop = loopChain ~= nil and loopChain[1] or nil
    local loopWayPoints = firstLoop ~= nil and firstLoop.wayPoints or nil

    if not ADCircularRouteUtil.isValidLoop(loopWayPoints) then
        local failureReason = reason or "invalidClosedLoop"
        self.vehicle.ad.isStoppingWithError = true
        ADCircularRouteUtil.logSnowRouteFailure(self.vehicle, selectedMarkers, failureReason)
        self.vehicle:stopAutoDrive()
        AutoDriveMessageEvent.sendMessageOrNotification(self.vehicle, ADMessagesManager.messageTypes.ERROR, "$l10n_AD_Driver_of; %s $l10n_AD_snow_plow_no_loop; %s", 5000, self.vehicle.ad.stateModule:getName(), tostring(failureReason))
        return
    end

    self.loopChain = loopChain
    self.loopWayPoints = loopWayPoints
    self.startMarker = firstLoop.startMarker or selectedMarkers[1]
    self.startWayPointId = firstLoop.startWayPointId or (self.startMarker ~= nil and self.startMarker.id) or (loopWayPoints[1] ~= nil and loopWayPoints[1].id)
    self.driveToStartBeforeLoop = firstLoop.driveToStartBeforeLoop == true
    self.loopRouteLabel = firstLoop.routeLabel
    self.loopRouteType = firstLoop.routeType
    self.vehicle.ad.stateModule:setLoopsDone(0)
    self:reportLoopPreview(loopWayPoints)
    ADSnowPlowUtil.startServiceSession(self)
    self:applySnowRouteState()

    if self.driveToStartBeforeLoop then
        self.state = SnowPlowMode.STATE_DRIVE_TO_START
        self.vehicle.ad.stateModule:setCurrentSnowPlowMarkerSlot(1)
        self.vehicle.ad.taskModule:addTask(SnowPlowDriveToStartTask:new(self.vehicle, self.startWayPointId))
    else
        self.state = SnowPlowMode.STATE_LOOP
        self.loopTask = SnowPlowLoopTask:new(self.vehicle, self.loopWayPoints, self:getSelectedSnowMarkers())
        self.vehicle.ad.taskModule:addTask(self.loopTask)
    end
end

function SnowPlowMode:getSelectedSnowMarkers()
    return self.vehicle.ad.stateModule:getSnowPlowMarkers()
end

function SnowPlowMode:handleFinishedTask()
    if self.state == SnowPlowMode.STATE_DRIVE_TO_START then
        self.state = SnowPlowMode.STATE_LOOP
        self.loopTask = SnowPlowLoopTask:new(self.vehicle, self.loopWayPoints, self:getSelectedSnowMarkers())
        self.vehicle.ad.taskModule:addTask(self.loopTask)
        return
    end

    local stateModule = self.vehicle.ad.stateModule
    stateModule:setLoopsDone(stateModule:getLoopsDone() + 1)
    ADSnowPlowUtil.settleServicePay(self, "loopCompleted")

    local loopCounter = stateModule:getLoopCounter()
    if loopCounter == 0 or stateModule:getLoopsDone() < loopCounter then
        self.loopTask = SnowPlowLoopTask:new(self.vehicle, self.loopWayPoints, self:getSelectedSnowMarkers())
        self.vehicle.ad.taskModule:addTask(self.loopTask)
    else
        self.state = SnowPlowMode.STATE_FINISHED
        stateModule:setCurrentSnowPlowMarkerSlot(nil)
        ADSnowPlowUtil.deactivateSnowTools(self.vehicle)
        self:restoreSnowRouteState()
        self.vehicle.ad.taskModule:addTask(StopAndDisableADTask:new(self.vehicle), ADTaskModule.DONT_PROPAGATE)
    end
end

function SnowPlowMode:monitorTasks(dt)
    if self.state ~= SnowPlowMode.STATE_FINISHED then
        ADSnowPlowUtil.applySnowPlowSpeedOverride(self.vehicle)
        ADSnowPlowUtil.accrueServicePay(self, dt)
    end
end

function SnowPlowMode:stop()
    ADSnowPlowUtil.settleServicePay(self, "routeStopped")
    ADSnowPlowUtil.deactivateSnowTools(self.vehicle)
    self:restoreSnowRouteState()
    self.vehicle.ad.stateModule:setCurrentSnowPlowMarkerSlot(nil)
    self.state = SnowPlowMode.STATE_FINISHED
end

function SnowPlowMode:applySnowRouteState()
    ADSnowPlowUtil.applySnowPlowSpeedOverride(self.vehicle)
    ADSnowPlowUtil.activateSnowTools(self.vehicle)
end

function SnowPlowMode:restoreSnowRouteState()
    ADSnowPlowUtil.clearSnowPlowSpeedOverride(self.vehicle)
end

function SnowPlowMode:reportLoopPreview(loopWayPoints)
    local loopDescription = ADCircularRouteUtil.describeLoop(loopWayPoints)
    local loopDistance = ADCircularRouteUtil.getLoopLength(loopWayPoints)
    local routeLabel = self.loopRouteLabel or (self.startMarker ~= nil and self.startMarker.name) or tostring(loopDescription.startWayPointId)

    AutoDrive.debugMsg(
        self.vehicle,
        "Snow loop selected: %s (%s) -> %d waypoints (distance=%.1fm, startWaypoint=%s, endWaypoint=%s)",
        tostring(routeLabel),
        tostring(self.loopRouteType),
        loopDescription.wayPointCount,
        loopDistance,
        tostring(loopDescription.startWayPointId),
        tostring(loopDescription.endWayPointId)
    )

    AutoDriveMessageEvent.sendMessageOrNotification(
        self.vehicle,
        ADMessagesManager.messageTypes.INFO,
        "Snow loop found: %s, %d waypoints",
        5000,
        tostring(routeLabel),
        loopDescription.wayPointCount
    )
end
