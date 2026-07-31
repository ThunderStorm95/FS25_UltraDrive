ADCircularRouteUtil = {}

ADCircularRouteUtil.MIN_SNOW_LOOP_DISTANCE = 300
ADCircularRouteUtil.MAX_SNOW_LOOP_CANDIDATES = 40
ADCircularRouteUtil.MAX_SNOW_LOOP_SEARCH_EXPANSIONS = 2000
ADCircularRouteUtil.MAX_SNOW_PLOW_MARKERS = 3

function ADCircularRouteUtil.createMarkerLoop(vehicle, firstMarker, secondMarker)
    if firstMarker == nil or firstMarker.id == nil then
        return nil, "missingStartMarker"
    end

    if secondMarker ~= nil and secondMarker.id ~= nil and secondMarker.id ~= firstMarker.id then
        local toSecond = ADGraphManager:pathFromTo(firstMarker.id, secondMarker.id)
        local toFirst = ADGraphManager:pathFromTo(secondMarker.id, firstMarker.id)

        if toSecond == nil or #toSecond == 0 then
            return nil, "missingOutboundPath"
        end
        if toFirst == nil or #toFirst == 0 then
            return nil, "missingReturnPath"
        end

        local markerLoop = ADCircularRouteUtil.concatPaths(toSecond, toFirst)
        if ADCircularRouteUtil.isValidLoop(markerLoop) then
            return markerLoop, nil
        end

        local fallbackLoop, fallbackReason = ADCircularRouteUtil.findBestScoredCycle(vehicle, firstMarker.id, AutoDrive.getSetting("snowPlowMaxCycleWaypoints", vehicle))
        if ADCircularRouteUtil.isValidLoop(fallbackLoop) then
            return fallbackLoop, nil
        end

        return nil, fallbackReason or "invalidClosedLoop"
    end

    return ADCircularRouteUtil.findBestScoredCycle(vehicle, firstMarker.id, AutoDrive.getSetting("snowPlowMaxCycleWaypoints", vehicle))
end

function ADCircularRouteUtil.createMarkerLoopChain(vehicle, firstMarker, secondMarker)
    local loopWayPoints, reason = ADCircularRouteUtil.createMarkerLoop(vehicle, firstMarker, secondMarker)
    if not ADCircularRouteUtil.isValidLoop(loopWayPoints) then
        return nil, reason
    end

    return {
        {
            wayPoints = loopWayPoints,
            description = ADCircularRouteUtil.describeLoop(loopWayPoints)
        }
    }, nil
end

function ADCircularRouteUtil.createSnowPlowLoopChain(vehicle, markers)
    markers = markers or {}
    ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow route request: markerCount=%d markers=%s", #markers, ADCircularRouteUtil.describeMarkers(markers))

    if #markers < 2 then
        return nil, "missingMultiStopMarkers"
    end

    if #markers > ADCircularRouteUtil.MAX_SNOW_PLOW_MARKERS then
        return nil, "tooManyMultiStopMarkers"
    end

    local loopWayPoints, reason = ADCircularRouteUtil.createMultiStopLoop(vehicle, markers)
    if ADCircularRouteUtil.isValidLoop(loopWayPoints) then
        return ADCircularRouteUtil.createRouteChain(loopWayPoints, "multiStop", ADCircularRouteUtil.getMarkerRouteLabel(markers), true, markers[1], markers[1].id), nil
    end

    return nil, reason or "invalidMultiStopLoop"
end

function ADCircularRouteUtil.createRouteChain(loopWayPoints, routeType, routeLabel, driveToStartBeforeLoop, startMarker, startWayPointId)
    return {
        {
            wayPoints = loopWayPoints,
            description = ADCircularRouteUtil.describeLoop(loopWayPoints),
            routeType = routeType,
            routeLabel = routeLabel,
            driveToStartBeforeLoop = driveToStartBeforeLoop,
            startMarker = startMarker,
            startWayPointId = startWayPointId or (startMarker ~= nil and startMarker.id) or (loopWayPoints ~= nil and loopWayPoints[1] ~= nil and loopWayPoints[1].id) or nil
        }
    }
end

function ADCircularRouteUtil.createMultiStopLoop(vehicle, markers)
    if markers == nil or #markers < 2 then
        return nil, "missingMultiStopMarkers"
    end

    local paths = {}
    for index, marker in ipairs(markers) do
        if marker == nil or marker.id == nil then
            ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow segment %d failed: missing marker", index)
            return nil, "missingMultiStopMarker"
        end

        local nextMarker = markers[index + 1] or markers[1]
        if nextMarker == nil or nextMarker.id == nil then
            ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow segment %d failed: missing next marker", index)
            return nil, "missingMultiStopMarker"
        end

        local fromName = ADCircularRouteUtil.getMarkerDebugName(marker)
        local toName = ADCircularRouteUtil.getMarkerDebugName(nextMarker)
        ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow segment %d/%d: %s -> %s", index, #markers, fromName, toName)

        local path = ADGraphManager:pathFromTo(markers[index].id, nextMarker.id)
        if path == nil or #path == 0 then
            ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow segment %d/%d failed: no path from %s to %s", index, #markers, fromName, toName)
            return nil, string.format("missingMultiStopPath %s -> %s", fromName, toName)
        end

        ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow segment %d/%d ok: %s -> %s waypoints=%d", index, #markers, fromName, toName, #path)
        table.insert(paths, path)
    end

    local loopWayPoints = ADCircularRouteUtil.concatPaths(unpack(paths))
    loopWayPoints = ADCircularRouteUtil.closeMultiStopLoop(loopWayPoints, markers[1])
    if not ADCircularRouteUtil.isValidLoop(loopWayPoints) then
        local loopDescription = ADCircularRouteUtil.describeLoop(loopWayPoints)
        ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow multi-stop loop invalid: waypoints=%d start=%s end=%s", loopDescription.wayPointCount, tostring(loopDescription.startWayPointId), tostring(loopDescription.endWayPointId))
        return nil, "invalidMultiStopLoop"
    end

    return loopWayPoints, nil
end

function ADCircularRouteUtil.closeMultiStopLoop(loopWayPoints, startMarker)
    if loopWayPoints == nil or startMarker == nil or startMarker.id == nil then
        return loopWayPoints
    end

    local firstWayPoint = loopWayPoints[1]
    local lastWayPoint = loopWayPoints[#loopWayPoints]
    if firstWayPoint ~= nil and lastWayPoint ~= nil and firstWayPoint.id ~= lastWayPoint.id and lastWayPoint.id == startMarker.id then
        local startWayPoint = ADGraphManager:getWayPointById(startMarker.id)
        if startWayPoint ~= nil then
            table.insert(loopWayPoints, 1, startWayPoint)
        end
    end

    return loopWayPoints
end

function ADCircularRouteUtil.getMarkerDebugName(marker)
    if marker == nil then
        return "<nil>"
    end

    return string.format("%s(id=%s)", tostring(marker.name), tostring(marker.id))
end

function ADCircularRouteUtil.describeMarkers(markers)
    local descriptions = {}

    for index, marker in ipairs(markers or {}) do
        table.insert(descriptions, string.format("%d:%s", index, ADCircularRouteUtil.getMarkerDebugName(marker)))
    end

    if #descriptions == 0 then
        return "<none>"
    end

    return table.concat(descriptions, ", ")
end

function ADCircularRouteUtil.logSnowRouteInfo(vehicle, message, ...)
    local formattedMessage = string.format(message, ...)
    Logging.info("[AutoDrive] %s", formattedMessage)

    if vehicle ~= nil and AutoDrive ~= nil and AutoDrive.debugMsg ~= nil then
        AutoDrive.debugMsg(vehicle, "%s", formattedMessage)
    end
end

function ADCircularRouteUtil.logSnowRouteFailure(vehicle, markers, reason)
    ADCircularRouteUtil.logSnowRouteInfo(vehicle, "Snow plow route failed: reason=%s markers=%s", tostring(reason), ADCircularRouteUtil.describeMarkers(markers))
end

function ADCircularRouteUtil.createOutAndBackLoop(vehicle, destinationMarker)
    if destinationMarker == nil or destinationMarker.id == nil then
        return nil, "missingStartMarker"
    end

    local startWayPointId = ADCircularRouteUtil.getNearestVehicleWayPointId(vehicle)
    if startWayPointId == nil then
        return nil, "missingVehicleStartWaypoint"
    end

    if startWayPointId == destinationMarker.id then
        return nil, "vehicleAlreadyAtDestination"
    end

    local toDestination = ADGraphManager:pathFromTo(startWayPointId, destinationMarker.id)
    if toDestination == nil or #toDestination == 0 then
        return nil, "missingOutboundPath"
    end

    local toStart = ADGraphManager:pathFromTo(destinationMarker.id, startWayPointId)
    if toStart == nil or #toStart == 0 then
        return nil, "missingReturnPath"
    end

    local loopWayPoints = ADCircularRouteUtil.concatPaths(toDestination, toStart)
    if not ADCircularRouteUtil.isValidLoop(loopWayPoints) then
        return nil, "invalidOutAndBackLoop"
    end

    return loopWayPoints, nil
end

function ADCircularRouteUtil.getNearestVehicleWayPointId(vehicle)
    if vehicle == nil or vehicle.getWayPointsDistance == nil then
        return nil
    end

    local closest = nil
    for _, item in pairs(vehicle:getWayPointsDistance()) do
        if item ~= nil and item.wayPoint ~= nil and item.wayPoint.id ~= nil and item.distance ~= nil then
            if closest == nil or item.distance < closest.distance then
                closest = item
            end
        end
    end

    return closest ~= nil and closest.wayPoint.id or nil
end

function ADCircularRouteUtil.getMarkerRouteLabel(markers)
    local names = {}
    for _, marker in ipairs(markers or {}) do
        table.insert(names, tostring(marker.name))
    end

    if markers ~= nil and markers[1] ~= nil then
        table.insert(names, tostring(markers[1].name))
    end

    return table.concat(names, " -> ")
end

function ADCircularRouteUtil.concatPaths(...)
    local loop = {}
    local paths = {...}

    for _, path in ipairs(paths) do
        for _, wayPoint in ipairs(path) do
            local lastWayPoint = loop[#loop]
            if lastWayPoint == nil or lastWayPoint.id ~= wayPoint.id then
                table.insert(loop, wayPoint)
            end
        end
    end

    return loop
end

function ADCircularRouteUtil.findLocalCycle(startWayPointId, maxDepth)
    maxDepth = maxDepth or 250

    local startWayPoint = ADGraphManager:getWayPointById(startWayPointId)
    if startWayPoint == nil then
        return nil, "missingStartWaypoint"
    end

    local queue = {
        { id = startWayPointId, path = { startWayPointId } }
    }
    local visited = {
        [startWayPointId] = true
    }

    while #queue > 0 do
        local item = table.remove(queue, 1)
        if #item.path <= maxDepth then
            local wayPoint = ADGraphManager:getWayPointById(item.id)
            if wayPoint ~= nil and wayPoint.out ~= nil then
                for _, nextId in pairs(wayPoint.out) do
                    if nextId == startWayPointId and #item.path >= 4 then
                        table.insert(item.path, startWayPointId)
                        local loop = ADCircularRouteUtil.wayPointIdsToWayPoints(item.path)
                        if loop == nil then
                            return nil, "missingCycleWaypoint"
                        end
                        return loop, nil
                    end

                    if visited[nextId] ~= true then
                        visited[nextId] = true
                        local newPath = {}
                        for _, pathId in ipairs(item.path) do
                            table.insert(newPath, pathId)
                        end
                        table.insert(newPath, nextId)
                        table.insert(queue, { id = nextId, path = newPath })
                    end
                end
            end
        end
    end

    return nil, "noCycleFound"
end

function ADCircularRouteUtil.findBestScoredCycle(vehicle, startWayPointId, maxDepth)
    maxDepth = maxDepth or 250

    local candidates, reason = ADCircularRouteUtil.collectCycleCandidates(startWayPointId, maxDepth)
    if candidates == nil or #candidates == 0 then
        return nil, reason or "noCycleFound"
    end

    local bestCandidate = nil
    local bestTinyCandidate = nil

    for _, candidate in ipairs(candidates) do
        if candidate.distance >= ADCircularRouteUtil.MIN_SNOW_LOOP_DISTANCE then
            if bestCandidate == nil or candidate.score > bestCandidate.score then
                bestCandidate = candidate
            end
        elseif bestTinyCandidate == nil or candidate.score > bestTinyCandidate.score then
            bestTinyCandidate = candidate
        end
    end

    bestCandidate = bestCandidate or bestTinyCandidate

    if bestCandidate ~= nil then
        AutoDrive.debugMsg(
            vehicle,
            "Snow loop selected: score=%.1f distance=%.1fm waypoints=%d candidates=%d",
            bestCandidate.score,
            bestCandidate.distance,
            #bestCandidate.wayPoints,
            #candidates
        )
        return bestCandidate.wayPoints, nil
    end

    return nil, "noCycleFound"
end

function ADCircularRouteUtil.collectCycleCandidates(startWayPointId, maxDepth)
    maxDepth = maxDepth or 250

    local startWayPoint = ADGraphManager:getWayPointById(startWayPointId)
    if startWayPoint == nil then
        return nil, "missingStartWaypoint"
    end

    local candidates = {}
    local queue = {
        {
            id = startWayPointId,
            path = { startWayPointId },
            visited = { [startWayPointId] = true }
        }
    }
    local expansions = 0

    while #queue > 0 and #candidates < ADCircularRouteUtil.MAX_SNOW_LOOP_CANDIDATES and expansions < ADCircularRouteUtil.MAX_SNOW_LOOP_SEARCH_EXPANSIONS do
        local item = table.remove(queue, 1)
        expansions = expansions + 1
        if #item.path <= maxDepth then
            local wayPoint = ADGraphManager:getWayPointById(item.id)
            if wayPoint ~= nil and wayPoint.out ~= nil then
                for _, nextId in pairs(wayPoint.out) do
                    if nextId == startWayPointId and #item.path >= 4 then
                        local cyclePath = {}
                        for _, pathId in ipairs(item.path) do
                            table.insert(cyclePath, pathId)
                        end
                        table.insert(cyclePath, startWayPointId)

                        local loopWayPoints = ADCircularRouteUtil.wayPointIdsToWayPoints(cyclePath)
                        if loopWayPoints == nil then
                            return nil, "missingCycleWaypoint"
                        end

                        table.insert(candidates, ADCircularRouteUtil.scoreLoopCandidate(loopWayPoints))
                    elseif item.visited[nextId] ~= true then
                        local newPath = {}
                        local newVisited = {}

                        for _, pathId in ipairs(item.path) do
                            table.insert(newPath, pathId)
                            newVisited[pathId] = true
                        end

                        table.insert(newPath, nextId)
                        newVisited[nextId] = true
                        table.insert(queue, { id = nextId, path = newPath, visited = newVisited })
                    end

                    if #candidates >= ADCircularRouteUtil.MAX_SNOW_LOOP_CANDIDATES then
                        break
                    end
                end
            end
        end
    end

    if #candidates == 0 then
        return nil, "noCycleFound"
    end

    return candidates, nil
end

function ADCircularRouteUtil.scoreLoopCandidate(loopWayPoints)
    local uniqueWayPoints = {}
    local uniqueCount = 0

    for _, wayPoint in ipairs(loopWayPoints) do
        if wayPoint ~= nil and wayPoint.id ~= nil and uniqueWayPoints[wayPoint.id] ~= true then
            uniqueWayPoints[wayPoint.id] = true
            uniqueCount = uniqueCount + 1
        end
    end

    local distance = ADCircularRouteUtil.getLoopLength(loopWayPoints)
    return {
        wayPoints = loopWayPoints,
        distance = distance,
        uniqueWayPointCount = uniqueCount,
        score = distance + (uniqueCount * 10)
    }
end

function ADCircularRouteUtil.getLoopLength(loopWayPoints)
    local distance = 0

    if loopWayPoints == nil then
        return distance
    end

    for index = 1, #loopWayPoints - 1 do
        local currentWayPoint = loopWayPoints[index]
        local nextWayPoint = loopWayPoints[index + 1]
        if currentWayPoint ~= nil and nextWayPoint ~= nil and currentWayPoint.x ~= nil and currentWayPoint.z ~= nil and nextWayPoint.x ~= nil and nextWayPoint.z ~= nil then
            distance = distance + MathUtil.vector2Length(currentWayPoint.x - nextWayPoint.x, currentWayPoint.z - nextWayPoint.z)
        end
    end

    return distance
end

function ADCircularRouteUtil.wayPointIdsToWayPoints(wayPointIds)
    local wayPoints = {}
    for _, wayPointId in ipairs(wayPointIds) do
        local wayPoint = ADGraphManager:getWayPointById(wayPointId)
        if wayPoint == nil then
            return nil
        end
        table.insert(wayPoints, wayPoint)
    end
    return wayPoints
end

function ADCircularRouteUtil.isValidLoop(loopWayPoints)
    if loopWayPoints == nil or #loopWayPoints < 3 then
        return false
    end

    local firstWayPoint = loopWayPoints[1]
    local lastWayPoint = loopWayPoints[#loopWayPoints]
    return firstWayPoint ~= nil and lastWayPoint ~= nil and firstWayPoint.id == lastWayPoint.id
end

function ADCircularRouteUtil.describeLoop(loopWayPoints)
    local description = {
        isValid = ADCircularRouteUtil.isValidLoop(loopWayPoints),
        wayPointCount = 0,
        startWayPointId = nil,
        endWayPointId = nil
    }

    if loopWayPoints ~= nil then
        description.wayPointCount = #loopWayPoints

        local firstWayPoint = loopWayPoints[1]
        if firstWayPoint ~= nil then
            description.startWayPointId = firstWayPoint.id
        end

        local lastWayPoint = loopWayPoints[#loopWayPoints]
        if lastWayPoint ~= nil then
            description.endWayPointId = lastWayPoint.id
        end
    end

    return description
end
