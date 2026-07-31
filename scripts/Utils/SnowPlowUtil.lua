ADSnowPlowUtil = {}

ADSnowPlowUtil.SERVICE_MARGIN = 1.15
ADSnowPlowUtil.SERVICE_MAX_PENDING_PAY = 1000000
ADSnowPlowUtil.SERVICE_MIN_SETTLE_PAY = 1
ADSnowPlowUtil.SERVICE_MAX_TICK_DISTANCE = 100
ADSnowPlowUtil.SERVICE_DEBUG_INTERVAL_MS = 30000
ADSnowPlowUtil.SERVICE_IDLE_GRACE_MS = 5000

function ADSnowPlowUtil.getSnowTools(vehicle)
    local tools = {}
    for _, implement in pairs(AutoDrive.getAllImplements(vehicle, true)) do
        if implement ~= nil then
            if implement.spec_snowPlow ~= nil
                or implement.spec_saltSpreader ~= nil
                or implement.spec_shovel ~= nil
            then
                table.insert(tools, implement)
            end
        end
    end
    return tools
end

function ADSnowPlowUtil.setSnowToolsLowered(vehicle, lowered)
    for _, tool in pairs(ADSnowPlowUtil.getSnowTools(vehicle)) do
        local method = nil
        local attacherVehicle = tool.getAttacherVehicle ~= nil and tool:getAttacherVehicle() or nil
        if attacherVehicle ~= nil and attacherVehicle.handleLowerImplementEvent ~= nil then
            method = "handleLowerImplementEvent"
            attacherVehicle:handleLowerImplementEvent(tool, lowered)
        elseif tool.setLoweredAll ~= nil then
            method = "setLoweredAll"
            tool:setLoweredAll(lowered)
        elseif tool.setLowered ~= nil then
            method = "setLowered"
            tool:setLowered(lowered)
        end

        vehicle.ad.snowPlowLastToolCommands = vehicle.ad.snowPlowLastToolCommands or {}
        local command = tostring(lowered)
        if method ~= nil and vehicle.ad.snowPlowLastToolCommands[tool] ~= command then
            local toolName = tool.getName ~= nil and tool:getName() or tostring(tool)
            AutoDrive.debugMsg(vehicle, "SnowPlow tool command: %s tool=%s method=%s", lowered and "lower" or "raise", tostring(toolName), method)
            vehicle.ad.snowPlowLastToolCommands[tool] = command
        end
    end
end

function ADSnowPlowUtil.getSnowToolLoweredState(tool)
    local attacherVehicle = tool.getAttacherVehicle ~= nil and tool:getAttacherVehicle() or nil
    if attacherVehicle ~= nil
        and attacherVehicle.getImplementByObject ~= nil
        and attacherVehicle.getJointMoveDown ~= nil
    then
        local implement = attacherVehicle:getImplementByObject(tool)
        if implement ~= nil and implement.jointDescIndex ~= nil then
            return attacherVehicle:getJointMoveDown(implement.jointDescIndex), "getJointMoveDown"
        end
    end

    if tool.getIsLowered ~= nil then
        return tool:getIsLowered(), "getIsLowered"
    elseif tool.getIsLoweredAll ~= nil then
        return tool:getIsLoweredAll(), "getIsLoweredAll"
    end

    return nil, "none"
end

function ADSnowPlowUtil.areSnowToolsInLoweredState(vehicle, expectedLowered)
    local tools = ADSnowPlowUtil.getSnowTools(vehicle)
    if #tools == 0 then
        return false
    end

    for _, tool in pairs(tools) do
        if ADSnowPlowUtil.getSnowToolLoweredState(tool) ~= expectedLowered then
            return false
        end
    end

    return true
end

function ADSnowPlowUtil.areSnowToolsRaised(vehicle)
    return ADSnowPlowUtil.areSnowToolsInLoweredState(vehicle, false)
end

function ADSnowPlowUtil.areSnowToolsLowered(vehicle)
    return ADSnowPlowUtil.areSnowToolsInLoweredState(vehicle, true)
end

function ADSnowPlowUtil.monitorSnowToolState(vehicle, dt)
    if vehicle == nil or vehicle.ad == nil or dt == nil or dt <= 0 then
        return
    end

    vehicle.ad.snowPlowToolMonitorMs = (vehicle.ad.snowPlowToolMonitorMs or 0) + dt
    if vehicle.ad.snowPlowToolMonitorMs < 250 then
        return
    end
    vehicle.ad.snowPlowToolMonitorMs = 0

    local states = vehicle.ad.snowPlowObservedToolStates or {}
    for _, tool in pairs(ADSnowPlowUtil.getSnowTools(vehicle)) do
        local lowered, getter = ADSnowPlowUtil.getSnowToolLoweredState(tool)

        local state = lowered == nil and "unknown" or tostring(lowered)
        local toolName = tool.getName ~= nil and tool:getName() or tostring(tool)
        if states[tool] == nil then
            AutoDrive.debugMsg(vehicle, "SnowPlow tool observed lowered state: tool=%s state=%s getter=%s", tostring(toolName), state, getter)
        elseif states[tool] ~= state then
            AutoDrive.debugMsg(vehicle, "SnowPlow tool observed lowered state changed: tool=%s %s -> %s getter=%s", tostring(toolName), states[tool], state, getter)
        end
        states[tool] = state
    end
    vehicle.ad.snowPlowObservedToolStates = states
end

function ADSnowPlowUtil.forceActivateTool(tool)
    if tool.setIsTurnedOn ~= nil then
        tool:setIsTurnedOn(true)
    end

    if tool.spec_saltSpreader ~= nil and tool.setIsSprayerTurnedOn ~= nil then
        tool:setIsSprayerTurnedOn(true)
    end
end

function ADSnowPlowUtil.activateSnowTools(vehicle)
    ADSnowPlowUtil.setSnowToolsLowered(vehicle, true)

    for _, tool in pairs(ADSnowPlowUtil.getSnowTools(vehicle)) do
        ADSnowPlowUtil.forceActivateTool(tool)
    end
end

function ADSnowPlowUtil.raiseSnowTools(vehicle)
    ADSnowPlowUtil.setSnowToolsLowered(vehicle, false)
end

function ADSnowPlowUtil.createRecoveryProfile(toolsInitiallyLowered)
    local phases = {}
    local profile = {
        name = "snowPlowReverseLiftForwardLower",
        phases = phases
    }

    if not toolsInitiallyLowered then
        table.insert(phases, {name = "stopBeforeInitialLower", type = ADRecoveryManeuver.PHASE_STOP, maxSpeed = 0.00002, timeout = 5000})
        table.insert(phases, {name = "ensureLowered", type = ADRecoveryManeuver.PHASE_ACTION, action = function(_, vehicle)
            ADSnowPlowUtil.activateSnowTools(vehicle)
            return true
        end})
        table.insert(phases, {name = "verifyInitiallyLowered", type = ADRecoveryManeuver.PHASE_WAIT_FOR, minDuration = 3000, timeout = 8000, verify = function(_, vehicle)
            return ADSnowPlowUtil.areSnowToolsLowered(vehicle)
        end})
    end

    table.insert(phases, {name = "reverseWithToolDown", type = ADRecoveryManeuver.PHASE_MOVE, direction = -1, distance = 0.5, speed = 4, timeout = 5000})
    table.insert(phases, {name = "stopBeforeRaise", type = ADRecoveryManeuver.PHASE_STOP, maxSpeed = 0.00002, timeout = 5000})
    table.insert(phases, {name = "raiseTools", type = ADRecoveryManeuver.PHASE_ACTION, action = function(_, vehicle)
        ADSnowPlowUtil.raiseSnowTools(vehicle)
        return true
    end})
    table.insert(phases, {name = "verifyRaised", type = ADRecoveryManeuver.PHASE_WAIT_FOR, minDuration = 3000, timeout = 8000, verify = function(_, vehicle)
        return ADSnowPlowUtil.areSnowToolsRaised(vehicle)
    end})
    table.insert(phases, {name = "forwardWithToolsRaised", type = ADRecoveryManeuver.PHASE_MOVE, direction = 1, distance = 1.0, speed = 4, timeout = 5000})
    table.insert(phases, {name = "stopBeforeLower", type = ADRecoveryManeuver.PHASE_STOP, maxSpeed = 0.00002, timeout = 5000})
    table.insert(phases, {name = "lowerTools", type = ADRecoveryManeuver.PHASE_ACTION, action = function(_, vehicle)
        ADSnowPlowUtil.activateSnowTools(vehicle)
        return true
    end})
    table.insert(phases, {name = "verifyLowered", type = ADRecoveryManeuver.PHASE_WAIT_FOR, minDuration = 3000, timeout = 8000, verify = function(_, vehicle)
        return ADSnowPlowUtil.areSnowToolsLowered(vehicle)
    end})

    return profile
end

function ADSnowPlowUtil.deactivateSnowTools(vehicle)
    for _, tool in pairs(ADSnowPlowUtil.getSnowTools(vehicle)) do
        if tool.setIsTurnedOn ~= nil then
            tool:setIsTurnedOn(false)
        end

        if tool.setIsSprayerTurnedOn ~= nil then
            tool:setIsSprayerTurnedOn(false)
        end
    end

    if AutoDrive.getSetting("snowPlowRaiseOnStop", vehicle) then
        ADSnowPlowUtil.raiseSnowTools(vehicle)
    end
end

function ADSnowPlowUtil.applySnowPlowSpeedOverride(vehicle)
    if vehicle == nil or vehicle.ad == nil then
        return nil
    end

    local snowSpeed = AutoDrive.getSetting("snowPlowSpeed", vehicle)
    vehicle.ad.snowPlowSpeedOverride = snowSpeed
    return snowSpeed
end

function ADSnowPlowUtil.clearSnowPlowSpeedOverride(vehicle)
    if vehicle ~= nil and vehicle.ad ~= nil then
        vehicle.ad.snowPlowSpeedOverride = nil
    end
end

function ADSnowPlowUtil.getSnowPlowSpeedOverride(vehicle)
    if vehicle ~= nil and vehicle.ad ~= nil then
        return vehicle.ad.snowPlowSpeedOverride
    end

    return nil
end

function ADSnowPlowUtil.changeSnowPlowSpeed(vehicle, delta)
    if vehicle == nil or vehicle.ad == nil or delta == nil then
        return nil
    end

    local setting = AutoDrive.settings.snowPlowSpeed
    if setting == nil or setting.values == nil then
        return nil
    end

    local currentState = AutoDrive.getSettingState("snowPlowSpeed", vehicle) or setting.default or 1
    local nextState = math.max(1, math.min(#setting.values, currentState + delta))
    AutoDrive.setSettingState("snowPlowSpeed", nextState, vehicle)
    ADSnowPlowUtil.applySnowPlowSpeedOverride(vehicle)

    return AutoDrive.getSetting("snowPlowSpeed", vehicle)
end

function ADSnowPlowUtil.increaseSnowPlowSpeed(vehicle)
    return ADSnowPlowUtil.changeSnowPlowSpeed(vehicle, 1)
end

function ADSnowPlowUtil.decreaseSnowPlowSpeed(vehicle)
    return ADSnowPlowUtil.changeSnowPlowSpeed(vehicle, -1)
end

function ADSnowPlowUtil.ensureServiceL10n()
    if g_i18n == nil or g_i18n.texts == nil then
        return
    end

    local label = g_i18n.texts["snowPlowService"] or g_i18n.texts["finance_snowPlowService"] or "Snow plow service"
    g_i18n.texts["snowPlowService"] = label
    g_i18n.texts["finance_snowPlowService"] = label
end

function ADSnowPlowUtil.getServiceModName()
    return AutoDrive.currentModName or g_currentModName or "FS25_AutoDrive"
end

function ADSnowPlowUtil.getServiceMoneyType()
    ADSnowPlowUtil.ensureServiceL10n()

    if ADSnowPlowUtil.MONEY_TYPE_SNOW_SERVICE == nil and MoneyType ~= nil and MoneyType.register ~= nil then
        ADSnowPlowUtil.MONEY_TYPE_SNOW_SERVICE = MoneyType.register("other", "snowPlowService", ADSnowPlowUtil.getServiceModName())
    end

    return ADSnowPlowUtil.MONEY_TYPE_SNOW_SERVICE or MoneyType.AI
end

function ADSnowPlowUtil.getServiceFarmId(vehicle)
    if vehicle == nil then
        return nil
    end

    if vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil then
        local actualFarmId = vehicle.ad.stateModule:getActualFarmId()
        if actualFarmId ~= nil and actualFarmId > 0 then
            return actualFarmId
        end
    end

    if vehicle.getOwnerFarmId ~= nil then
        local ownerFarmId = vehicle:getOwnerFarmId()
        if ownerFarmId ~= nil and ownerFarmId > 0 then
            return ownerFarmId
        end
    end

    return nil
end

function ADSnowPlowUtil.getServiceDriverWageCost(dt)
    if dt == nil or dt <= 0 then
        return 0
    end

    local driverWages = AutoDrive.getSetting("driverWages") or 0
    local difficultyMultiplier = AutoDrive.getPriceMultiplier()
    local pricePerMs = AIJobFieldWork and AIJobFieldWork.getPricePerMs and AIJobFieldWork:getPricePerMs() or 0.0005

    return dt * difficultyMultiplier * driverWages * pricePerMs
end

function ADSnowPlowUtil.getServiceFuelPricePerLiter(fillType)
    if fillType ~= nil
        and g_currentMission ~= nil
        and g_currentMission.economyManager ~= nil
        and g_currentMission.economyManager.getPricePerLiter ~= nil
    then
        return g_currentMission.economyManager:getPricePerLiter(fillType) or 0
    end

    return 0
end

function ADSnowPlowUtil.getServiceHelperFuelCost(mode, dt)
    if mode == nil or mode.vehicle == nil or dt == nil or dt <= 0 then
        return 0
    end

    local vehicle = mode.vehicle
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if missionInfo == nil or missionInfo.helperBuyFuel ~= true then
        return 0
    end

    if vehicle.getIsAIActive == nil or not vehicle:getIsAIActive() then
        return 0
    end

    local spec = vehicle.spec_motorized
    if spec == nil
        or spec.consumers == nil
        or spec.motor == nil
        or spec.motor.maxRpm == nil
        or spec.motor.minRpm == nil
        or spec.motor.lastMotorRpm == nil
        or g_currentMission == nil
        or g_currentMission.economyManager == nil
        or g_currentMission.economyManager.getCostPerLiter == nil
        or FillType == nil
        or FillType.DIESEL == nil
    then
        return 0
    end

    local rpmRange = spec.motor.maxRpm - spec.motor.minRpm
    if rpmRange == 0 then
        return 0
    end

    local idleFactor = 0.5
    local rpmPercentage = (spec.motor.lastMotorRpm - spec.motor.minRpm) / rpmRange
    local rpmFactor = idleFactor + rpmPercentage * (1 - idleFactor)
    local loadFactor = math.max((spec.smoothedLoadPercentage or 0) * rpmPercentage, 0)
    local motorFactor = 0.5 * ((0.2 * rpmFactor) + (1.8 * loadFactor))

    local usageFactor = 1.5
    if missionInfo.fuelUsage == 1 then
        usageFactor = 1.0
    elseif missionInfo.fuelUsage == 3 then
        usageFactor = 2.5
    end

    local damage = vehicle.getVehicleDamage ~= nil and vehicle:getVehicleDamage() or 0
    if damage > 0 and Motorized ~= nil and Motorized.DAMAGED_USAGE_INCREASE ~= nil then
        usageFactor = usageFactor * (1 + damage * Motorized.DAMAGED_USAGE_INCREASE)
    end

    local helperFuelCost = 0
    mode.snowServiceHelperFuelUsage = mode.snowServiceHelperFuelUsage or {}

    for _, consumer in pairs(spec.consumers) do
        if consumer ~= nil
            and consumer.permanentConsumption
            and consumer.usage ~= nil
            and consumer.usage > 0
            and consumer.fillUnitIndex ~= nil
        then
            local fillType = consumer.fillType
            if vehicle.getFillUnitLastValidFillType ~= nil then
                fillType = vehicle:getFillUnitLastValidFillType(consumer.fillUnitIndex)
            end

            if fillType == FillType.DIESEL then
                local key = tostring(consumer.fillUnitIndex) .. ":" .. tostring(fillType)
                local pendingUsage = mode.snowServiceHelperFuelUsage[key]
                if pendingUsage == nil then
                    pendingUsage = consumer.fillLevelToChange or 0
                end

                pendingUsage = pendingUsage + (usageFactor * motorFactor * consumer.usage * dt)
                if math.abs(pendingUsage) > 1 then
                    helperFuelCost = helperFuelCost + (pendingUsage * (g_currentMission.economyManager:getCostPerLiter(fillType) or 0) * 1.5)
                    pendingUsage = 0
                end

                mode.snowServiceHelperFuelUsage[key] = pendingUsage
            end
        end
    end

    mode.snowServiceFuelCost = (mode.snowServiceFuelCost or 0) + helperFuelCost

    return helperFuelCost
end

function ADSnowPlowUtil.snapshotServiceFuelLevels(vehicle)
    local fuelLevels = {}

    if vehicle == nil
        or vehicle.spec_motorized == nil
        or vehicle.spec_motorized.consumers == nil
        or vehicle.getFillUnitFillLevel == nil
    then
        return fuelLevels
    end

    for _, consumer in pairs(vehicle.spec_motorized.consumers) do
        if consumer ~= nil and consumer.fillUnitIndex ~= nil and consumer.fillType ~= nil then
            local fillLevel = vehicle:getFillUnitFillLevel(consumer.fillUnitIndex)
            if fillLevel ~= nil then
                local key = tostring(consumer.fillUnitIndex) .. ":" .. tostring(consumer.fillType)
                fuelLevels[key] = {
                    fillUnitIndex = consumer.fillUnitIndex,
                    fillType = consumer.fillType,
                    fillLevel = fillLevel
                }
            end
        end
    end

    return fuelLevels
end

function ADSnowPlowUtil.getServiceFuelCost(mode)
    if mode == nil or mode.vehicle == nil then
        return 0
    end

    local currentFuelLevels = ADSnowPlowUtil.snapshotServiceFuelLevels(mode.vehicle)
    if mode.snowServiceFuelLevels == nil then
        mode.snowServiceFuelLevels = currentFuelLevels
        return 0
    end

    local fuelCost = 0
    for key, current in pairs(currentFuelLevels) do
        local previous = mode.snowServiceFuelLevels[key]
        if previous ~= nil and current.fillLevel < previous.fillLevel then
            local consumedLiters = previous.fillLevel - current.fillLevel
            fuelCost = fuelCost + (consumedLiters * ADSnowPlowUtil.getServiceFuelPricePerLiter(current.fillType))
        end
    end

    mode.snowServiceFuelLevels = currentFuelLevels
    mode.snowServiceFuelCost = (mode.snowServiceFuelCost or 0) + fuelCost

    return fuelCost
end

function ADSnowPlowUtil.startServiceSession(mode)
    mode.snowServicePendingPay = 0
    mode.snowServiceElapsedMs = 0
    mode.snowServiceProductiveMs = 0
    mode.snowServiceIdleMs = 0
    mode.snowServiceDistance = 0
    mode.snowServiceWageCost = 0
    mode.snowServiceFuelCost = 0
    mode.snowServiceFuelLevels = ADSnowPlowUtil.snapshotServiceFuelLevels(mode.vehicle)
    mode.snowServiceHelperFuelUsage = {}
    mode.snowServiceLastX = nil
    mode.snowServiceLastZ = nil
    mode.snowServiceLastDebugMs = 0
end

function ADSnowPlowUtil.isServiceProductive(mode, dt)
    local vehicle = mode.vehicle
    local isMoving = vehicle.lastSpeedReal ~= nil and math.abs(vehicle.lastSpeedReal) > 0.0002
    local isRecovering = mode.loopTask ~= nil
        and SnowPlowLoopTask ~= nil
        and mode.loopTask.state == SnowPlowLoopTask.STATE_RECOVERY

    if isMoving or isRecovering then
        mode.snowServiceIdleMs = 0
        return true
    end

    mode.snowServiceIdleMs = (mode.snowServiceIdleMs or 0) + dt
    return mode.snowServiceIdleMs <= ADSnowPlowUtil.SERVICE_IDLE_GRACE_MS
end

function ADSnowPlowUtil.accrueServicePay(mode, dt)
    if mode == nil or mode.vehicle == nil or dt == nil or dt <= 0 then
        return 0
    end

    if mode.snowServicePendingPay == nil then
        ADSnowPlowUtil.startServiceSession(mode)
    end

    local vehicle = mode.vehicle
    local tickDistance = 0
    local isProductive = ADSnowPlowUtil.isServiceProductive(mode, dt)
    local wageCost = isProductive and ADSnowPlowUtil.getServiceDriverWageCost(dt) or 0
    local fuelCost = ADSnowPlowUtil.getServiceFuelCost(mode)
    local helperFuelCost = ADSnowPlowUtil.getServiceHelperFuelCost(mode, dt)
    fuelCost = fuelCost + helperFuelCost
    local payAmount = (wageCost + fuelCost) * ADSnowPlowUtil.SERVICE_MARGIN

    if vehicle.components ~= nil and vehicle.components[1] ~= nil and vehicle.components[1].node ~= nil then
        local x, _, z = getWorldTranslation(vehicle.components[1].node)

        if mode.snowServiceLastX ~= nil and mode.snowServiceLastZ ~= nil then
            tickDistance = MathUtil.vector2Length(x - mode.snowServiceLastX, z - mode.snowServiceLastZ)
            if tickDistance <= ADSnowPlowUtil.SERVICE_MAX_TICK_DISTANCE then
                mode.snowServiceDistance = (mode.snowServiceDistance or 0) + tickDistance
            else
                tickDistance = 0
            end
        end

        mode.snowServiceLastX = x
        mode.snowServiceLastZ = z
    end

    mode.snowServiceElapsedMs = (mode.snowServiceElapsedMs or 0) + dt
    if isProductive then
        mode.snowServiceProductiveMs = (mode.snowServiceProductiveMs or 0) + dt
    end
    mode.snowServiceWageCost = (mode.snowServiceWageCost or 0) + wageCost
    mode.snowServicePendingPay = math.min(
        (mode.snowServicePendingPay or 0) + payAmount,
        ADSnowPlowUtil.SERVICE_MAX_PENDING_PAY
    )

    mode.snowServiceLastDebugMs = (mode.snowServiceLastDebugMs or 0) + dt
    if mode.snowServiceLastDebugMs >= ADSnowPlowUtil.SERVICE_DEBUG_INTERVAL_MS then
        AutoDrive.debugMsg(
            vehicle,
            "Snow plow service pending: $%.2f elapsed=%.1fs productive=%.1fs idle=%.1fs distance=%.1fm wageCost=%.2f fuelCost=%.2f lastTick=%.1fm",
            mode.snowServicePendingPay or 0,
            (mode.snowServiceElapsedMs or 0) / 1000,
            (mode.snowServiceProductiveMs or 0) / 1000,
            (mode.snowServiceIdleMs or 0) / 1000,
            mode.snowServiceDistance or 0,
            mode.snowServiceWageCost or 0,
            mode.snowServiceFuelCost or 0,
            tickDistance
        )
        mode.snowServiceLastDebugMs = 0
    end

    return payAmount
end

function ADSnowPlowUtil.settleServicePay(mode, reason)
    if mode == nil or mode.vehicle == nil then
        return 0
    end

    local vehicle = mode.vehicle
    local payAmount = math.floor((mode.snowServicePendingPay or 0) + 0.5)
    local farmId = ADSnowPlowUtil.getServiceFarmId(vehicle)

    if payAmount < ADSnowPlowUtil.SERVICE_MIN_SETTLE_PAY or farmId == nil then
        ADSnowPlowUtil.startServiceSession(mode)
        return 0
    end

    local moneyType = ADSnowPlowUtil.getServiceMoneyType()
    g_currentMission:addMoney(payAmount, farmId, moneyType, true)
    g_currentMission:showMoneyChange(moneyType, nil, false, farmId)
    AutoDrive.debugMsg(
        vehicle,
        "Snow plow service paid: +$%d reason=%s elapsed=%.1fs productive=%.1fs idle=%.1fs distance=%.1fm wageCost=%.2f fuelCost=%.2f margin=%.0f%%",
        payAmount,
        tostring(reason),
        (mode.snowServiceElapsedMs or 0) / 1000,
        (mode.snowServiceProductiveMs or 0) / 1000,
        (mode.snowServiceIdleMs or 0) / 1000,
        mode.snowServiceDistance or 0,
        mode.snowServiceWageCost or 0,
        mode.snowServiceFuelCost or 0,
        (ADSnowPlowUtil.SERVICE_MARGIN - 1) * 100
    )
    ADSnowPlowUtil.startServiceSession(mode)

    return payAmount
end
