--[[
  AutoCook Return Fix
  - Records source containers more robustly (type + parent tile)
  - Tracks the base pot/pan when pulled from a world/furniture container
  - On stop: returns items still in inventory (leftover stacks, pot, unused pulls)
  - Fully consumed ingredients cannot be returned (expected)
  Set AutoCookReturnFix.Verbose = false after testing
]]

require "AutoCook"

AutoCookReturnFix = AutoCookReturnFix or {}
AutoCookReturnFix.Verbose = false -- set true to debug returns in console/DebugLog

local function log(msg)
    if AutoCookReturnFix.Verbose then
        print("[AutoCookReturnFix] " .. tostring(msg))
    end
end

local function captureContainer(container)
    if not container then
        return nil
    end
    local info = {
        container = container,
        type = nil,
        parent = nil,
        x = nil,
        y = nil,
        z = nil,
    }
    local ok, err = pcall(function()
        info.type = container:getType()
        local parent = container:getParent()
        if parent then
            info.parent = parent
            if parent.getX then
                info.x = parent:getX()
                info.y = parent:getY()
                info.z = parent:getZ()
            end
        end
    end)
    if not ok then
        log("captureContainer failed: " .. tostring(err))
        return nil
    end
    return info
end

local function containerStillUsable(container, player)
    if not container or not player then
        return false
    end
    local inv = player:getInventory()
    if container == inv then
        return false
    end
    local ok, usable = pcall(function()
        -- touch API; dead refs throw
        local _ = container:getType()
        return true
    end)
    return ok and usable
end

local function resolveContainer(player, info)
    if not info then
        return nil
    end
    if containerStillUsable(info.container, player) then
        return info.container
    end
    -- parent IsoObject still has a container
    if info.parent then
        local ok, c = pcall(function()
            if info.parent.getContainer then
                return info.parent:getContainer()
            end
            return nil
        end)
        if ok and containerStillUsable(c, player) then
            return c
        end
    end
    -- search currently accessible containers (open / nearby)
    local list = ISInventoryPaneContextMenu.getContainers(player)
    if not list then
        return nil
    end
    local fallback = nil
    for i = 0, list:size() - 1 do
        local c = list:get(i)
        if containerStillUsable(c, player) then
            local sameType = (not info.type) or (c:getType() == info.type)
            if sameType then
                local p = c:getParent()
                if info.x ~= nil and p and p.getX and p:getX() == info.x and p:getY() == info.y and p:getZ() == info.z then
                    return c
                end
                if not fallback then
                    fallback = c
                end
            end
        end
    end
    return fallback
end

local function findItemInInventory(player, entry)
    local inv = player:getInventory()
    if not inv or not entry then
        return nil
    end
    if entry.item then
        local ok, has = pcall(function()
            return inv:contains(entry.item)
        end)
        if ok and has then
            return entry.item
        end
    end
    if entry.itemId ~= nil then
        local items = inv:getItems()
        if items then
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it and it:getID() == entry.itemId then
                    return it
                end
            end
        end
    end
    return nil
end

local function alreadyTracked(self, item)
    if not self.returnToContainer or not item then
        return false
    end
    local id = nil
    pcall(function() id = item:getID() end)
    for _, entry in ipairs(self.returnToContainer) do
        if entry.item == item then
            return true
        end
        if id ~= nil and entry.itemId == id then
            return true
        end
    end
    return false
end

--- Replace: robust tracking
function AutoCook:addToReturnContainer(item)
    if not item or not self.playerObj then
        return
    end
    if not self.returnToContainer then
        self.returnToContainer = {}
    end
    if alreadyTracked(self, item) then
        return
    end

    local cont = nil
    pcall(function() cont = item:getContainer() end)
    local inv = self.playerObj:getInventory()
    -- only track pulls from outside the player inventory
    if not cont or cont == inv then
        log("skip track (already in inv or no container): " .. tostring(item:getName()))
        return
    end

    local entry = {
        item = item,
        itemId = nil,
        fullType = nil,
        name = "?",
        source = captureContainer(cont),
        isBase = false,
    }
    pcall(function()
        entry.itemId = item:getID()
        entry.fullType = item:getFullType()
        entry.name = item:getName()
    end)

    table.insert(self.returnToContainer, entry)
    log(string.format(
        "track '%s' id=%s from type=%s pos=%s,%s,%s",
        tostring(entry.name),
        tostring(entry.itemId),
        tostring(entry.source and entry.source.type),
        tostring(entry.source and entry.source.x),
        tostring(entry.source and entry.source.y),
        tostring(entry.source and entry.source.z)
    ))
end

--- Replace: resolve containers + find by id; queue transfers for leftovers only
function AutoCook:returnItemsToOriginalContainer()
    if not self.returnToContainer or not self.playerObj then
        return
    end
    local player = self.playerObj
    local inv = player:getInventory()
    log("return pass, entries=" .. tostring(#self.returnToContainer))

    for _, entry in ipairs(self.returnToContainer) do
        local item = findItemInInventory(player, entry)
        local dest = resolveContainer(player, entry.source)

        if not item then
            -- normal for fully consumed ingredients
            log("skip '" .. tostring(entry.name) .. "' (consumed or not in inventory)")
        elseif not dest then
            log("skip '" .. tostring(entry.name) .. "' (source container not found — open/nearby?)")
        elseif dest == inv then
            log("skip '" .. tostring(entry.name) .. "' (dest is player inv)")
        else
            log("queue transfer '" .. tostring(entry.name) .. "' -> " .. tostring(dest:getType()))
            local action = ISInventoryTransferAction:new(player, item, inv, dest, nil)
            ISTimedActionQueue.add(action)
        end
    end
end

--- Track base pot/pan once when it lives outside inventory
local _continue = AutoCook.continue
function AutoCook:continue()
    if self.playerObj and self.baseItem and not self._acrfBaseTracked then
        self._acrfBaseTracked = true
        local inv = self.playerObj:getInventory()
        local inInv = false
        pcall(function() inInv = inv:contains(self.baseItem) end)
        if not inInv then
            log("tracking base item for return: " .. tostring(self.baseItem:getName()))
            local before = #self.returnToContainer
            self:addToReturnContainer(self.baseItem)
            if self.returnToContainer[before + 1] then
                self.returnToContainer[before + 1].isBase = true
            end
        else
            log("base already in inventory; not tracking origin")
        end
    end
    return _continue(self)
end

local _new = AutoCook.new
function AutoCook:new(playerObj, recipe, baseItem)
    local o = _new(self, playerObj, recipe, baseItem)
    o._acrfBaseTracked = false
    if not o.returnToContainer then
        o.returnToContainer = {}
    end
    log("session start recipe=" .. tostring(recipe and recipe:getUntranslatedName()))
    return o
end

local _stop = AutoCook.stopAutoCook
function AutoCook:stopAutoCook()
    log("stopAutoCook — attempting returns")
    return _stop(self)
end

log("loaded (Verbose=" .. tostring(AutoCookReturnFix.Verbose) .. ")")

