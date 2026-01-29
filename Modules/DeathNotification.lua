local deathTracker = CreateFrame("Frame")
local dead = {} -- [unit] = true/false (last known)

local function IsGroupUnit(unit)
  return unit and (unit:match("^raid%d+$") or unit:match("^party%d+$"))
end

local function RefreshRoster()
  -- reset cache so we don't false-trigger on roster swaps
  wipe(dead)
  -- prime current roster state
  if IsInRaid() then
    for i=1, GetNumGroupMembers() do
      local u = "raid"..i
      dead[u] = UnitIsDeadOrGhost(u) and true or false
    end
  elseif IsInGroup() then
    for i=1, GetNumSubgroupMembers() do
      local u = "party"..i
      dead[u] = UnitIsDeadOrGhost(u) and true or false
    end
  end
end

local function OnUnitUpdate(unit)
  if not IsGroupUnit(unit) then return end
  if not UnitExists(unit) then return end

  local nowDead = UnitIsDeadOrGhost(unit) and true or false
  local wasDead = dead[unit]

  if wasDead == nil then
    dead[unit] = nowDead
    return
  end

  if (not wasDead) and nowDead then
    local name = UnitName(unit) or "Someone"
    ns.PlaySmartSound(ns.Sounds.Death)
    ns.Print(name .. " died")
  end

  dead[unit] = nowDead
end

deathTracker:RegisterEvent("GROUP_ROSTER_UPDATE")
deathTracker:RegisterEvent("PLAYER_ENTERING_WORLD")
deathTracker:RegisterEvent("UNIT_HEALTH")
deathTracker:RegisterEvent("UNIT_FLAGS")

deathTracker:SetScript("OnEvent", function(_, event, arg1)
  if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    RefreshRoster()
    return
  end
  OnUnitUpdate(arg1)
end)