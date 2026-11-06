--[[
    Furina Hub  -  Forsaken  (PC + Mobile)
    PC: RightControl = menu, F6 = farm, End = panic
    Phone: tap the floating "F" button for the menu, the bolt button toggles farm

    Load (always the newest version):
      loadstring(game:HttpGet("https://raw.githubusercontent.com/banglajunaid9-ship-it/furina-hub-/main/FurinaHub.lua"))()

    Features
      Mobile     : touch-friendly window, draggable floating buttons, works on
                   phone executors that lack getconnections / fireproximityprompt
      Auto Farm  : Survivor AI (pathfinding to the best generator, auto-solves
                   all 4 puzzles, flees on line of sight) and Killer AI (predictive
                   chase, target commitment, auto-attack, optional abilities)
      Safe Mode  : no teleports, human timings, legit ranges, smart stamina,
                   anti-AFK; never hooks the game's metatables
      Auto Save  : every setting saves itself and restores next run
      Stats      : money earned, money/hour, rounds, puzzles, hits
      Server     : FPS boost (great on phones), auto-rejoin on disconnect,
                   server hop to the emptiest server, rejoin
      ESP        : killers, survivors, generators, items
      Visuals    : fullbright, no fog
      Theme      : Furina (sapphire / aqua / gold) or Classic
      Round Info : killer, survivors alive, generators done, round timer
      Spectate   : cycle the camera through the killer and survivors
      Alerts     : low-health warning
      Gears      : farm fetches gears for Gear generators, auto collect, gear ESP
      Auto Heal  : uses a Medkit when HP is low and the killer isn't close
      Danger     : red screen-edge vignette as the killer gets closer
      Tracers    : lines to killers / survivors (PC executors with Drawing)
      Camera     : custom FOV, unlocked zoom
      HUD        : FPS / ping / generators / killer bar, generator-done alerts
      Spectate   : auto spectate the killer when you're out
]]

----------------------------------------------------------------------
-- Lifecycle (safe to re-run: the previous copy unloads itself first)
----------------------------------------------------------------------
local genv = (getgenv and getgenv()) or _G
if genv.__FurinaHubUnload then pcall(genv.__FurinaHubUnload) end

local cleanups = {}
local alive = true
local function onCleanup(fn) table.insert(cleanups, fn) end
local function connect(sig, fn)
    local c = sig:Connect(fn)
    onCleanup(function() c:Disconnect() end)
    return c
end
local Window -- forward
local function unload()
    if not alive then return end
    alive = false
    for i = #cleanups, 1, -1 do pcall(cleanups[i]) end
    table.clear(cleanups)
    if Window then pcall(function() Window:Unload() end) end
    genv.__FurinaHubUnload = nil
end
genv.__FurinaHubUnload = unload
if STATE and STATE.onCleanup then STATE.onCleanup(unload) end

----------------------------------------------------------------------
-- Services / refs
----------------------------------------------------------------------
local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local Lighting     = game:GetService("Lighting")
local HttpService  = game:GetService("HttpService")
local TeleportSvc  = game:GetService("TeleportService")
local PathfindSvc  = game:GetService("PathfindingService")
local UIS          = game:GetService("UserInputService")
local GuiService   = game:GetService("GuiService")
while not Players.LocalPlayer do task.wait() end
local LP           = Players.LocalPlayer

local function try(fn, ...) local ok, r = pcall(fn, ...) if ok then return r end end

----------------------------------------------------------------------
-- Platform + executor compatibility
--   Phone executors often miss getconnections / fireproximityprompt /
--   mouse1click / gethui. Every use goes through these wrappers, which
--   fall back to plain Roblox APIs when the executor function is absent.
----------------------------------------------------------------------
local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled
local getconns = getconnections or get_signal_cons
local function connsOf(sig)
    if not getconns then return {} end
    local ok, r = pcall(getconns, sig)
    return (ok and type(r) == "table") and r or {}
end
local function hiddenUI()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then return cg end
    return LP:WaitForChild("PlayerGui")
end
local function safeParent(inst)
    if not pcall(function() inst.Parent = hiddenUI() end) or not inst.Parent then
        inst.Parent = LP:WaitForChild("PlayerGui")
    end
end
-- trigger a ProximityPrompt; falls back to the prompt's own hold input
local function firePrompt(p)
    if fireproximityprompt and pcall(fireproximityprompt, p) then return end
    pcall(function()
        p:InputHoldBegin()
        task.wait((p.HoldDuration or 0) + 0.05)
        p:InputHoldEnd()
    end)
end

-- Safe to run from auto-execute / right after a teleport: wait for the game
-- to finish loading and for every module we use to replicate.
if not game:IsLoaded() then game.Loaded:Wait() end
local function waitPath(root, path, timeout)
    local node = root
    for _, name in ipairs(path) do
        node = node and node:WaitForChild(name, timeout or 30)
    end
    return node
end
local function req(root, path)
    local m = waitPath(root, path)
    return m and try(require, m)
end
waitPath(RS, { "Systems", "Player", "Game", "Minigames" })
waitPath(RS, { "Modules", "Minigames" })
if not LP.Character then LP.CharacterAdded:Wait() end

local Sprinting          = req(RS, { "Systems", "Character", "Game", "Sprinting" })
local GearsClientHandler = req(RS, { "Systems", "Player", "Game", "Spawners", "GearsClientHandler" })
local LockBoard          = req(RS, { "Modules", "Minigames", "LockBoard" })

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local Cfg = {
    -- safety / farm
    SafeMode = true, AntiAFK = true,
    FarmSurvivor = false, FarmKiller = false, FleeDist = 45, SmartStamina = true,
    AttackSlot = 1,
    -- generators
    AutoGen = false, GenDelay = 1.5, AutoEnterGen = false,
    -- survivor
    InfStamina = false, KillerWarn = false, WarnDist = 60,
    AutoPickup = false, PickupDist = 12,
    -- killer
    KillAura = false, AuraRange = 9, AuraDelay = 0.35, AutoChase = false,
    -- esp
    EspKillers = false, EspSurvivors = false, EspGens = false, EspItems = false,
    EspNames = true, EspDistance = true, EspHealth = true,
    KillerColor = Color3.fromRGB(255, 60, 60),
    SurvivorColor = Color3.fromRGB(120, 220, 255),
    GenColor = Color3.fromRGB(232, 199, 122),
    ItemColor = Color3.fromRGB(150, 255, 210),
    -- visuals
    Fullbright = false, NoFog = false,
    -- server / performance / mobile
    FpsBoost = false, AutoRejoin = false, FloatingButtons = IS_MOBILE,
    KillerAbilities = false,
    Theme = "Furina", LowHpAlert = true,
    -- v7 extras
    FarmGears = true, AutoGears = false, EspGears = false, GearColor = Color3.fromRGB(255, 170, 60),
    AutoHeal = false, HealAt = 50,
    DangerVignette = false, VignetteDist = 50,
    TracerKillers = false, TracerSurvivors = false,
    FovOn = false, Fov = 90, ZoomUnlock = false,
    Overlay = false, GenAlerts = true, AutoSpectate = false,
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function myRole()
    local c = LP.Character
    return c and c.Parent and c.Parent.Name -- "Killers" | "Survivors" | "Spectating"
end
local function rootOf(m)
    if not m then return nil end
    if m:IsA("BasePart") then return m end
    return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
end
local function myRoot() return rootOf(LP.Character) end
local function teamFolder(name)
    local p = workspace:FindFirstChild("Players")
    return p and p:FindFirstChild(name)
end
local function ingame()
    local m = workspace:FindFirstChild("Map")
    return m and m:FindFirstChild("Ingame")
end
local function dist(a, b) return (a - b).Magnitude end
local function setIf(o, k, v) if o[k] ~= v then o[k] = v end end -- skip same-value writes

local function notify(title, desc, life)
    if Window then
        pcall(function() Window:Notify({ Title = title, Description = desc, Lifetime = life or 4 }) end)
    end
end

----------------------------------------------------------------------
-- Farm state + sprint control
--   The sprint loop asks u0:IsSprintKeyHeld() every frame, so answering
--   "held" makes the game sprint through its own code path (speed tween,
--   footstep remote) with no key presses or window focus.
----------------------------------------------------------------------
local Farm = { sprint = false, status = "Idle", tired = false }

-- Session stats -------------------------------------------------------
local Stats = {
    startT = os.clock(), farmTime = 0, puzzles = 0, hits = 0,
    roundsSurvivor = 0, roundsKiller = 0, moneyStart = nil,
}
local function money()
    local ls = LP:FindFirstChild("leaderstats")
    local m = ls and ls:FindFirstChild("Money")
    return m and m.Value
end
Stats.moneyStart = money()
local function farming() return Cfg.FarmSurvivor or Cfg.FarmKiller end
local function autoSolveOn() return Cfg.AutoGen or Cfg.FarmSurvivor end

if Sprinting and type(Sprinting.IsSprintKeyHeld) == "function" then
    local origHeld = Sprinting.IsSprintKeyHeld
    Sprinting.IsSprintKeyHeld = function(...)
        if alive and Farm.sprint then return true end
        return origHeld(...)
    end
    onCleanup(function() Sprinting.IsSprintKeyHeld = origHeld end)
end

local function myHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

----------------------------------------------------------------------
-- Map tracking (generators + items), event driven instead of rescanning
----------------------------------------------------------------------
local Generators, Items, Gears = {}, {}, {}

local function isGenerator(d)
    return d:IsA("Model") and d.Name == "Generator" and d:FindFirstChild("Main") ~= nil
end
local function isItem(d)
    return d:IsA("Tool") -- map items (Medkit, BloxyCola) are Tools, not always with a Handle
end
local function track(d)
    if isGenerator(d) then Generators[d] = true
    elseif isItem(d) then Items[d] = true
    elseif d:IsA("Model") and d.Name == "Gear" then Gears[d] = true end -- gear pickups (for Gear generators)
end

local mapConns = {}
local function bindIngame(ig)
    for _, c in ipairs(mapConns) do c:Disconnect() end
    table.clear(mapConns); table.clear(Generators); table.clear(Items); table.clear(Gears)
    if not ig then return end
    for _, d in ipairs(ig:GetDescendants()) do track(d) end
    table.insert(mapConns, ig.DescendantAdded:Connect(function(d)
        task.defer(track, d) -- children (Main/Handle) may arrive a frame later
    end))
    table.insert(mapConns, ig.DescendantRemoving:Connect(function(d)
        Generators[d] = nil; Items[d] = nil; Gears[d] = nil
    end))
end
onCleanup(function() for _, c in ipairs(mapConns) do c:Disconnect() end end)

do
    local map = workspace:WaitForChild("Map", 10)
    if map then
        bindIngame(map:FindFirstChild("Ingame"))
        connect(map.ChildAdded, function(c) if c.Name == "Ingame" then bindIngame(c) end end)
    end
end

local function genPrompt(gen)
    local main = gen:FindFirstChild("Main")
    return main and main:FindFirstChildOfClass("ProximityPrompt")
end
local function genDone(gen)
    local p = genPrompt(gen)
    return p == nil or not p.Enabled
end
local function nearestGen(maxD)
    local r = myRoot(); if not r then return end
    local best, bd
    for g in pairs(Generators) do
        if g.Parent and not genDone(g) then
            local d = dist(g:GetPivot().Position, r.Position)
            if (not maxD or d <= maxD) and (not bd or d < bd) then best, bd = g, d end
        end
    end
    return best, bd
end

----------------------------------------------------------------------
-- Generator puzzle solvers
--   Each ClientMinigame class has Start(session); we wrap it so the
--   game opens its puzzle as normal, then we answer through the same
--   session.Network channel the game's own OnSolved/OnPress uses.
----------------------------------------------------------------------
-- Safe Mode makes every solve take a believable amount of time:
-- at least 2s, plus time proportional to how much "work" the puzzle is.
local function human(work)
    local base = math.max(0, Cfg.GenDelay)
    if Cfg.SafeMode then base = math.max(base, 2) + (work or 0) end
    task.wait(base + math.random() * 0.6)
end

-- Flow (numberlink). Server only checks: each pair joined, adjacent steps, no overlap.
local function solveFlow(size, pairsT)
    local function rc(c) return (c - 1) // size + 1, (c - 1) % size + 1 end
    local used = {}
    for _, p in pairs(pairsT) do used[p[1]] = true; used[p[2]] = true end

    local order = {}
    for id in pairs(pairsT) do table.insert(order, id) end
    table.sort(order, function(a, b)
        local ar, ac = rc(pairsT[a][1]); local br, bc = rc(pairsT[a][2])
        local cr, cc = rc(pairsT[b][1]); local dr, dc = rc(pairsT[b][2])
        return math.abs(ar - br) + math.abs(ac - bc) < math.abs(cr - dr) + math.abs(cc - dc)
    end)

    local function neighbours(c, goal)
        local r, col = rc(c); local gr, gc = rc(goal)
        local out = {}
        if r > 1 then table.insert(out, c - size) end
        if r < size then table.insert(out, c + size) end
        if col > 1 then table.insert(out, c - 1) end
        if col < size then table.insert(out, c + 1) end
        table.sort(out, function(a, b)
            local ar, ac = rc(a); local br, bc = rc(b)
            return math.abs(ar - gr) + math.abs(ac - gc) < math.abs(br - gr) + math.abs(bc - gc)
        end)
        return out
    end

    local paths, budget = {}, 300000
    local route
    route = function(k)
        if k > #order then return true end
        local id = order[k]
        local a, b = pairsT[id][1], pairsT[id][2]
        local path = { a }
        local function dfs(c)
            budget -= 1
            if budget <= 0 then return false end
            for _, n in ipairs(neighbours(c, b)) do
                if n == b then
                    path[#path + 1] = b
                    paths[id] = table.clone(path)
                    if route(k + 1) then return true end
                    paths[id] = nil
                    path[#path] = nil
                elseif not used[n] then
                    used[n] = true; path[#path + 1] = n
                    if dfs(n) then return true end
                    path[#path] = nil; used[n] = nil
                end
            end
            return false
        end
        return dfs(a)
    end
    if route(1) then return paths end
end
genv.__FurinaSolveFlow = solveFlow

local Solvers = {}

Solvers.FlowClientMinigame = function(s)
    local P = s.Network.Properties
    local paths = solveFlow(P:Get("GridSize"), P:Get("Pairs"))
    if not paths then notify("Auto Generator", "Flow puzzle: no solution found, solve it by hand.") return end
    local cells = 0
    for _, path in pairs(paths) do cells += #path end
    human(cells * 0.07)
    s.Network:FireServer("Submit", paths)
    Stats.puzzles += 1
end

Solvers.ConnectClientMinigame = function(s)
    local blobs = s.Network.Properties:Get("Blobs")
    local first, links = {}, {}
    for i, color in pairs(blobs) do
        local j = first[color]
        if j then table.insert(links, { math.min(i, j), math.max(i, j) }); first[color] = nil
        else first[color] = i end
    end
    human(#links * 0.35)
    s.Network:FireServer("Submit", links)
    Stats.puzzles += 1
end

Solvers.LockClientMinigame = function(s)
    if not LockBoard then return end
    local P = s.Network.Properties
    local cfg = P:Get("Config")
    if type(cfg) ~= "table" or type(cfg.Seed) ~= "number" then return end
    local board = LockBoard.new(cfg)
    local sync = try(function()
        return P:Connect("State", function(st)
            if type(st) == "table" and type(st.Presses) == "number" and board.State.Presses <= st.Presses then
                board:Apply(st)
            end
        end)
    end)
    task.wait(math.max(0, Cfg.GenDelay * 0.5))
    local deadline = os.clock() + 40
    while alive and autoSolveOn() and not board:IsBroken() and os.clock() < deadline do
        local now = workspace:GetServerTimeNow()
        if now >= cfg.StartTime then
            local d = (board:AngleAt(now) - board.State.Target) % 360
            d = math.min(d, 360 - d)
            if d <= (cfg.TargetSize or 20) / 4 + 1 then
                if board:Press(now) then s.Network:FireServer("Press", now) end
                task.wait(0.12 + math.random() * 0.08)
            end
        end
        RunService.Heartbeat:Wait()
    end
    if board:IsBroken() then Stats.puzzles += 1 end
    if sync and typeof(sync) == "RBXScriptConnection" then sync:Disconnect()
    elseif type(sync) == "table" and sync.Disconnect then pcall(sync.Disconnect, sync) end
end

Solvers.GearClientMinigame = function(s)
    if GearsClientHandler and (try(function() return GearsClientHandler:Get() end) or 0) < 1 then
        notify("Auto Generator", "You need a gear for this generator. Find one on the map.")
        return
    end
    local turns = math.max(1, s.Network.Properties:Get("Turns") or 6)
    task.wait(math.max(Cfg.GenDelay, turns * 0.25))
    s.Network:FireServer("Screwed")
    Stats.puzzles += 1
end

-- Minigame classes keep their methods in a hidden table keyed by a
-- MinigameKey("ClassValues") sentinel; each session deep-clones it on creation,
-- so patching ClassValues.Start covers every future puzzle session.
local function classValues(cls)
    for k, v in next, cls do
        if type(v) == "table" and tostring(k) == "MinigameKey(ClassValues)" then return v end
    end
end

local hooked = {}
do
    local folder = RS:FindFirstChild("Systems") and RS.Systems.Player.Game:FindFirstChild("Minigames")
    for name, solver in pairs(Solvers) do
        local mod = folder and folder:FindFirstChild(name)
        local cls = mod and try(require, mod)
        local cv = cls and classValues(cls)
        if cv and type(cv.Start) == "function" then
            local orig = cv.Start
            cv.Start = function(session, ...)
                local res = table.pack(pcall(orig, session, ...))
                if alive and autoSolveOn() then
                    local ok = try(function() return session.Network.Properties:Get("FixerUserId") == LP.UserId end)
                    if ok then
                        task.spawn(function()
                            local good, err = pcall(solver, session)
                            if not good then warn("[FurinaHub] " .. name .. ": " .. tostring(err)) end
                        end)
                    end
                end
                if not res[1] then error(res[2], 0) end
                return table.unpack(res, 2, res.n)
            end
            hooked[name] = true
            onCleanup(function() cv.Start = orig end)
        else
            hooked[name] = false
        end
    end
end
genv.__FurinaHooked = hooked

----------------------------------------------------------------------
-- Attacking: call the ability button's own click handler (the same thing a
-- real click runs), so it works without window focus and the game builds
-- the UseActorAbility payload itself. Falls back to a real mouse click.
----------------------------------------------------------------------
local abCache, abT = nil, 0
local function abilityButtons(fresh)
    if not fresh and abCache and os.clock() - abT < 2 then
        local ok = true
        for _, b in ipairs(abCache) do if not b.Parent or not b.Visible then ok = false break end end
        if ok and #abCache > 0 then return abCache end
    end
    local list = (function()
    local mu = LP.PlayerGui:FindFirstChild("MainUI")
    local ac = mu and mu:FindFirstChild("AbilityContainer")
    if not ac then return {} end
    local list = {}
    for _, b in ipairs(ac:GetDescendants()) do
        if b:IsA("GuiButton") and b.Visible then
            -- without getconnections (phones) we can't see handlers, so keep every
            -- visible ability button and press it with the VirtualInputManager tap
            local n = getconns and (#connsOf(b.MouseButton1Click) + #connsOf(b.MouseButton1Down)) or 1
            if n > 0 then table.insert(list, b) end
        end
    end
    table.sort(list, function(a, b)
        if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
        return a.AbsolutePosition.X < b.AbsolutePosition.X
    end)
    return list
    end)()
    abCache, abT = list, os.clock()
    return list
end
genv.__FurinaAbilityButtons = abilityButtons

local function useAbilitySlot(slot)
    local b = abilityButtons()[slot or 1]
    if b then
        local fired = false
        for _, c in ipairs(connsOf(b.MouseButton1Click)) do
            if c.Function then task.spawn(c.Function); fired = true end
        end
        if not fired then
            for _, c in ipairs(connsOf(b.MouseButton1Down)) do
                if c.Function then task.spawn(c.Function); fired = true end
            end
            task.delay(0.06, function()
                for _, c in ipairs(connsOf(b.MouseButton1Up)) do
                    if c.Function then task.spawn(c.Function) end
                end
            end)
        end
        if fired then return true end
        -- no getconnections (common on phones): tap the button through
        -- VirtualInputManager like a real touch/click would
        local ok = pcall(function()
            local VIM = game:GetService("VirtualInputManager")
            local c = b.AbsolutePosition + b.AbsoluteSize / 2 + GuiService:GetGuiInset()
            VIM:SendMouseButtonEvent(c.X, c.Y, 0, true, game, 0)
            task.wait(0.03)
            VIM:SendMouseButtonEvent(c.X, c.Y, 0, false, game, 0)
        end)
        if ok then return true end
    end
    if mouse1click and (not isrbxactive or isrbxactive()) then mouse1click() return true end
    return false
end

local lastAttack = 0
local function auraRange() return Cfg.SafeMode and math.min(Cfg.AuraRange, 7.5) or Cfg.AuraRange end
local function attackInterval()
    local i = Cfg.SafeMode and math.max(Cfg.AuraDelay, 0.45) or Cfg.AuraDelay
    return i + (Cfg.SafeMode and math.random() * 0.15 or 0)
end
local nextAttackGap = 0.4
-- counts a hit when the closest survivor loses health right after our swing
local function nearestSurvivorHum()
    local f = teamFolder("Survivors"); local r = myRoot()
    if not f or not r then return end
    local best, bd
    for _, m in ipairs(f:GetChildren()) do
        local h = m:FindFirstChildOfClass("Humanoid"); local tr = rootOf(m)
        if h and tr and h.Health > 0 then
            local d = (tr.Position - r.Position).Magnitude
            if not bd or d < bd then best, bd = h, d end
        end
    end
    return best, bd
end
local function tryAttack()
    local now = os.clock()
    if now - lastAttack < nextAttackGap then return end
    lastAttack = now
    nextAttackGap = attackInterval()
    local h, d = nearestSurvivorHum()
    local before = h and h.Health
    useAbilitySlot(Cfg.AttackSlot)
    if h and d and d < 12 then
        task.delay(0.8, function()
            if h.Parent and h.Health < before - 1 then Stats.hits += 1 end
        end)
    end
end

local function faceTowards(pos)
    local r = myRoot(); if not r then return end
    local flat = Vector3.new(pos.X, r.Position.Y, pos.Z)
    if (flat - r.Position).Magnitude < 0.1 then return end
    local want = CFrame.lookAt(r.Position, flat)
    -- Safe Mode turns smoothly instead of snapping
    r.CFrame = Cfg.SafeMode and r.CFrame:Lerp(want, 0.35) or want
end

----------------------------------------------------------------------
-- Farm AI v3
--   Non-blocking design: a Mover that runs every frame (async pathfinding,
--   waypoint skipping, stuck recovery) and a Brain per role that re-decides
--   ~10x a second from live game state:
--     * generator progress / occupants / fakes read from the game's own
--       generator binders (Counter, MaxCounter, Completed, Occupants)
--     * killer threat = distance, closing speed, line of sight, predicted
--       position, so it flees early from a chase and ignores a killer
--       walking the other way behind a wall
--     * runs everywhere (sprint) while keeping a stamina reserve for escapes
----------------------------------------------------------------------
local WALK, JUMP = Enum.PathWaypointAction.Walk, Enum.PathWaypointAction.Jump
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshLosFilter()
    local pf = workspace:FindFirstChild("Players")
    local hits = workspace:FindFirstChild("Hitboxes")
    local list = {}
    if pf then table.insert(list, pf) end
    if hits then table.insert(list, hits) end
    losParams.FilterDescendantsInstances = list
end
refreshLosFilter()

local function clearLine(a, b)
    local dir = b - a
    if dir.Magnitude < 0.5 then return true end
    return workspace:Raycast(a, dir, losParams) == nil
end
-- walkable straight line: clear at waist and knee height, no big height change
local function walkableLine(from, to)
    if math.abs(to.Y - from.Y) > 4 then return false end
    return clearLine(from + Vector3.new(0, 0.5, 0), to + Vector3.new(0, 0.5, 0))
        and clearLine(from - Vector3.new(0, 1.6, 0), to - Vector3.new(0, 1.6, 0))
end

local function computePath(from, to)
    local path = PathfindSvc:CreatePath({ AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 4,
        Costs = { Water = 20 } })
    local ok = pcall(function() path:ComputeAsync(from, to) end)
    if ok and path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
end

-- Mover --------------------------------------------------------------
local Mover = { goal = nil, wps = nil, wpsGoal = nil, idx = 1, pathT = 0, computing = false,
    token = 0, repath = 1, lastPos = nil, lastMoveT = 0, stuckCount = 0, failedPaths = 0 }

function Mover.set(goal, repath)
    Mover.goal = goal
    Mover.repath = repath or 1
end
function Mover.stop()
    if Mover.goal then
        Mover.goal = nil
        local h, r = myHum(), myRoot()
        if h and r then h:MoveTo(r.Position) end
    end
    Mover.wps = nil
end
local function requestPath(from, to)
    if Mover.computing then return end
    Mover.computing = true
    Mover.token += 1
    local tok = Mover.token
    task.spawn(function()
        local w = computePath(from, to)
        Mover.computing = false
        if tok ~= Mover.token or not alive then return end
        if w then Mover.failedPaths = 0 else Mover.failedPaths += 1 end
        Mover.wps = w or { { Position = to, Action = WALK } }
        Mover.wpsGoal = to
        Mover.idx = (#Mover.wps > 1) and 2 or 1
        Mover.pathT = os.clock()
    end)
end
function Mover.update()
    local r, hum = myRoot(), myHum()
    local goal = Mover.goal
    if not r or not hum or not goal then return end
    local pos = r.Position

    -- stuck recovery: jump, then force a fresh path
    if not Mover.lastPos or (pos - Mover.lastPos).Magnitude > 1.2 then
        Mover.lastPos, Mover.lastMoveT, Mover.stuckCount = pos, os.clock(), 0
    elseif os.clock() - Mover.lastMoveT > 0.9 then
        Mover.stuckCount += 1
        hum.Jump = true
        Mover.wps = nil
        Mover.lastMoveT = os.clock()
        if Mover.stuckCount >= 3 then -- sidestep out of corners
            local side = r.CFrame.RightVector * (math.random() < 0.5 and -6 or 6)
            hum:MoveTo(pos + side)
            return
        end
    end

    -- close and nothing in the way: run straight at it (smooth, no zig-zag)
    if (goal - pos).Magnitude < 70 and walkableLine(pos, goal) then
        hum:MoveTo(goal)
        return
    end

    if not Mover.wps or os.clock() - Mover.pathT > Mover.repath
        or (Mover.wpsGoal and (Mover.wpsGoal - goal).Magnitude > 6) then
        requestPath(pos, goal)
    end
    local wps = Mover.wps
    if not wps then hum:MoveTo(goal) return end

    -- skip ahead to the farthest waypoint we can run to directly
    for j = math.min(#wps, Mover.idx + 5), Mover.idx + 1, -1 do
        local w = wps[j]
        if w.Action == WALK and walkableLine(pos, w.Position + Vector3.new(0, 2.5, 0)) then
            Mover.idx = j
            break
        end
    end
    local wp = wps[Mover.idx]
    if wp then
        if wp.Action == JUMP then hum.Jump = true end
        hum:MoveTo(wp.Position)
        local flat = Vector3.new(wp.Position.X - pos.X, 0, wp.Position.Z - pos.Z)
        if flat.Magnitude < 3.5 then Mover.idx += 1 end
    else
        hum:MoveTo(goal)
    end
end

-- Sprint policy ------------------------------------------------------
-- reserve: fraction of stamina to keep for escapes while just travelling
local function setRun(wantRun, reserve)
    if not wantRun then Farm.sprint = false return end
    if Cfg.InfStamina or not Sprinting or not Cfg.SmartStamina then Farm.sprint = true return end
    local frac = (Sprinting.Stamina or 0) / math.max(1, Sprinting.MaxStamina or 100)
    -- hysteresis around the reserve so it doesn't flicker on/off
    if frac <= reserve then Farm.tired = true
    elseif frac >= math.min(0.95, reserve + 0.25) then Farm.tired = false end
    Farm.sprint = not Farm.tired
end

-- World model ----------------------------------------------------------
local GenBinder = req(RS, { "Systems", "Player", "Game", "Generators", "GeneratorClientBinder" })
local genRunning
if GenBinder then
    for k, v in next, GenBinder do
        if tostring(k) == "BinderKey(Running)" then genRunning = v end
    end
end

-- live generator list straight from the game's binders (falls back to the map scan)
local function liveGenerators()
    local list = {}
    if genRunning then
        for inst, obj in pairs(genRunning) do
            if typeof(inst) == "Instance" and inst.Parent and inst.Name == "Generator" then
                local P = obj.Network and obj.Network.Properties
                local ok, counter, maxc, done, occ = pcall(function()
                    return P:Get("Counter"), P:Get("MaxCounter"), P:Get("Completed"), P:Get("Occupants")
                end)
                local main = inst:FindFirstChild("Main")
                if ok and main and not done and (maxc or 0) > 0 then
                    table.insert(list, { inst = inst, main = main, pos = main.Position,
                        progress = (counter or 0) / maxc, occupants = occ or {} })
                end
            end
        end
    end
    if #list == 0 then
        for g in pairs(Generators) do
            if g.Parent and not genDone(g) and g:FindFirstChild("Main") then
                table.insert(list, { inst = g, main = g.Main, pos = g.Main.Position, progress = 0, occupants = {} })
            end
        end
    end
    return list
end

local function killersInfo()
    local out = {}
    local f = teamFolder("Killers")
    if not f then return out end
    for _, m in ipairs(f:GetChildren()) do
        local h = m:FindFirstChildOfClass("Humanoid"); local kr = rootOf(m)
        if m ~= LP.Character and kr and h and h.Health > 0 then
            local vel = kr.AssemblyLinearVelocity
            table.insert(out, { model = m, root = kr, pos = kr.Position, vel = Vector3.new(vel.X, 0, vel.Z) })
        end
    end
    return out
end

-- danger of standing at `pos`: predicted killer position 0.8s ahead
local function dangerAt(pos, killers)
    local d = 0
    for _, k in ipairs(killers) do
        local future = k.pos + k.vel * 0.8
        local dist_ = math.min((future - pos).Magnitude, (k.pos - pos).Magnitude)
        d += math.max(0, 1 - dist_ / 110) ^ 2
    end
    return d
end

local function threatTo(myPos, killers)
    local best
    for _, k in ipairs(killers) do
        local toMe = myPos - k.pos
        local dist_ = toMe.Magnitude
        local closing = dist_ > 0.1 and k.vel:Dot(toMe.Unit) or 0 -- studs/s toward me
        local los = clearLine(k.pos + Vector3.new(0, 1.5, 0), myPos + Vector3.new(0, 1.5, 0))
        local t = { k = k, dist = dist_, closing = closing, los = los }
        if not best or dist_ < best.dist then best = t end
    end
    return best
end

local function inPuzzle() return LP.PlayerGui:FindFirstChild("PuzzleUI") ~= nil end
local function gearsHeld()
    return (GearsClientHandler and try(function() return GearsClientHandler:Get() end)) or 0
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- gears lying on the map: nearest one whose pickup prompt is live
local function gearPrompt(gm)
    local p = gm:FindFirstChildWhichIsA("ProximityPrompt", true)
    return (p and p.Enabled) and p or nil
end
local function nearestGear(myPos, killers)
    local best, bd, bp
    for gm in pairs(Gears) do
        local root = gm.Parent and rootOf(gm)
        local p = root and gearPrompt(gm)
        if p then
            local d = (root.Position - myPos).Magnitude
            if killers and dangerAt(root.Position, killers) > 0.6 then d += 200 end -- don't walk into the killer
            if not bd or d < bd then best, bd, bp = root, d, p end
        end
    end
    return best, bd, bp
end
local lastGearFire = 0
local function grabGear(p)
    if os.clock() - lastGearFire < 1 then return end
    lastGearFire = os.clock()
    task.spawn(firePrompt, p)
end

-- Survivor brain -------------------------------------------------------
local S = { mode = "idle", gen = nil, side = nil, genPickT = 0, fleeGoal = nil, fleePickT = 0,
    enterT = 0, enterTries = 0, cooldown = {}, fleeing = false }

local function freeSide(g)
    local positions = g.inst:FindFirstChild("Positions")
    if not positions then return g.pos end
    local r = myRoot()
    local best, bd
    for _, part in ipairs(positions:GetChildren()) do
        if part:IsA("BasePart") then
            local taken = g.occupants[part.Name] and g.occupants[part.Name] ~= LP.UserId
            if not taken then
                local d = r and (part.Position - r.Position).Magnitude or 0
                if not bd or d < bd then best, bd = part, d end
            end
        end
    end
    return best and best.Position or nil
end

local function scoreGen(g, myPos, killers)
    if (S.cooldown[g.inst] or 0) > os.clock() then return nil end
    if g.inst:GetAttribute("Puzzle") == "GearServerMinigame" and gearsHeld() < 1 then return nil end
    local occCount = 0
    for _, uid in pairs(g.occupants) do if uid ~= LP.UserId then occCount += 1 end end
    if occCount >= 3 then return nil end
    local travel = (g.pos - myPos).Magnitude
    local danger = dangerAt(g.pos, killers)
    -- lower is better: travel time, danger near it, bonus for nearly finished
    -- gens and for teaming up (shared gens finish faster)
    return travel + danger * 220 - g.progress * 60 - occCount * 12
end

local function pickFleeGoal(myPos, killers, threat)
    local pf = workspace:FindFirstChild("Players")
    rayParams.FilterDescendantsInstances = pf and { pf } or {}
    local away = threat and Vector3.new(myPos.X - threat.k.pos.X, 0, myPos.Z - threat.k.pos.Z)
    away = (away and away.Magnitude > 0.1) and away.Unit or Vector3.new(1, 0, 0)
    local best, bestScore
    for ring = 1, 2 do
        local radius = ring == 1 and 45 or 80
        for i = 1, 20 do
            local ang = (i / 20) * math.pi * 2
            local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
            local probe = myPos + dir * radius
            local hit = workspace:Raycast(probe + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), rayParams)
            if hit and hit.Normal.Y > 0.6 then
                local spot = hit.Position + Vector3.new(0, 3, 0)
                local score = -dangerAt(spot, killers) * 300
                score += dir:Dot(away) * 60 -- run away, not past the killer
                -- prefer spots that break line of sight from the killer
                if threat and not clearLine(threat.k.pos + Vector3.new(0, 1.5, 0), spot) then score += 45 end
                -- prefer open running room (not a dead end)
                if walkableLine(myPos, spot) then score += 15 end
                if not bestScore or score > bestScore then best, bestScore = spot, score end
            end
        end
    end
    return best
end

local function survivorBrain()
    local r, hum = myRoot(), myHum()
    if not r or not hum then return end
    local myPos = r.Position
    local killers = killersInfo()
    local threat = threatTo(myPos, killers)

    -- threat assessment with hysteresis
    local flee = false
    if threat then
        local chased = threat.los and threat.closing > 4
        if S.fleeing then
            flee = threat.dist < Cfg.FleeDist * 1.6 and (threat.los or threat.dist < Cfg.FleeDist)
        else
            flee = threat.dist < Cfg.FleeDist * 0.7
                or (threat.dist < Cfg.FleeDist and (threat.los or threat.closing > 2))
                or (chased and threat.dist < Cfg.FleeDist * 1.5)
        end
    end
    S.fleeing = flee

    if flee then
        S.mode = "flee"
        if not S.fleeGoal or os.clock() - S.fleePickT > 1.2 or (S.fleeGoal - myPos).Magnitude < 6 then
            S.fleeGoal = pickFleeGoal(myPos, killers, threat)
            S.fleePickT = os.clock()
        end
        Farm.status = ("Running from killer (%d studs%s)"):format(threat.dist, threat.los and ", sees you" or "")
        setRun(true, 0.03) -- spend everything when escaping
        if S.fleeGoal then Mover.set(S.fleeGoal, 0.6) end
        return
    end
    S.fleeGoal = nil

    -- repairing: hold still; only bail if the killer is coming
    if inPuzzle() then
        S.mode = "repair"
        Farm.status = "Repairing generator"
        setRun(false)
        Mover.stop()
        return
    end

    local gens = liveGenerators()

    -- gears: Gear generators can't be fixed without one, so fetch a gear when
    -- one of those is still open (or when one is lying close by anyway)
    if Cfg.FarmGears and gearsHeld() < 1 then
        local needGear = false
        for _, g in ipairs(gens) do
            if g.inst:GetAttribute("Puzzle") == "GearServerMinigame" then needGear = true break end
        end
        local gr, gd, gp = nearestGear(myPos, killers)
        if gr and gd < 200 and (gd < 25 or (needGear and gd < 160)) then
            S.mode = "gear"
            if gd <= gp.MaxActivationDistance - 0.5 then
                Mover.stop(); setRun(false)
                Farm.status = "Picking up gear"
                grabGear(gp)
            else
                Farm.status = ("Getting a gear (%d studs)"):format(gd)
                setRun(true, 0.4)
                Mover.set(gr.Position, 1.2)
            end
            return
        end
    end

    -- choose the best generator (stick with the current one unless clearly worse)
    local best, bestScore, curScore
    for _, g in ipairs(gens) do
        local sc = scoreGen(g, myPos, killers)
        if sc then
            if S.gen and g.inst == S.gen.inst then curScore = sc; S.gen = g end
            if not bestScore or sc < bestScore then best, bestScore = g, sc end
        end
    end
    if not curScore or (bestScore and bestScore < curScore - 25) then S.gen = best end
    local g = S.gen
    if not g then
        S.mode = "hide"
        Farm.status = "All generators done - keeping distance"
        -- drift away from danger without wasting stamina
        if threat and threat.dist < 90 then
            S.fleeGoal = S.fleeGoal or pickFleeGoal(myPos, killers, threat)
            if S.fleeGoal then Mover.set(S.fleeGoal, 1) end
            setRun(true, 0.5)
        else
            Mover.stop(); setRun(false)
        end
        return
    end

    local spot = freeSide(g) or g.pos
    local dToSpot = (spot - myPos).Magnitude
    local dToMain = (g.pos - myPos).Magnitude
    if dToSpot > 2.5 and dToMain > 6.5 then
        S.mode = "travel"
        Farm.status = ("Running to generator %d%% (%d studs)"):format(g.progress * 100, dToMain)
        setRun(true, 0.4) -- run, but keep 40% for an escape
        Mover.set(spot, 1.2)
        return
    end

    -- at the generator: stop, then press the prompt like a player would
    S.mode = "enter"
    Mover.stop()
    setRun(false)
    local p = genPrompt(g.inst)
    if p and p.Enabled and os.clock() - S.enterT > 1.6 and dToMain <= p.MaxActivationDistance - 0.5 then
        S.enterT = os.clock()
        S.enterTries += 1
        Farm.status = "Starting repair"
        task.delay(0.15 + math.random() * 0.25, function()
            if alive and Cfg.FarmSurvivor and not inPuzzle() then task.spawn(firePrompt, p) end
        end)
        if S.enterTries >= 4 then -- side busy / rejected: try another gen for a bit
            S.cooldown[g.inst] = os.clock() + 10
            S.enterTries = 0
            S.gen = nil
        end
    end
end

-- Killer brain ---------------------------------------------------------
local K = { target = nil, targetT = 0, lastDist = nil, progressT = 0, blacklist = {}, abilT = 0, abilIdx = 1 }

local function survivorsInfo()
    local out = {}
    local f = teamFolder("Survivors")
    if not f then return out end
    for _, m in ipairs(f:GetChildren()) do
        local h = m:FindFirstChildOfClass("Humanoid"); local tr = rootOf(m)
        if tr and h and h.Health > 0 and (K.blacklist[m] or 0) < os.clock() then
            local v = tr.AssemblyLinearVelocity
            table.insert(out, { model = m, root = tr, pos = tr.Position, vel = Vector3.new(v.X, 0, v.Z),
                hp = h.Health / math.max(1, h.MaxHealth) })
        end
    end
    return out
end

local function killerBrain()
    local r, hum = myRoot(), myHum()
    if not r or not hum then return end
    local myPos = r.Position
    local survivors = survivorsInfo()

    if #survivors == 0 then
        -- nobody visible: patrol the generator closest to finishing
        local gens = liveGenerators()
        table.sort(gens, function(a, b) return a.progress > b.progress end)
        local g = gens[1]
        if g then
            Farm.status = ("Patrolling generator %d%%"):format(g.progress * 100)
            Mover.set(g.pos, 1.5)
            setRun(true, 0.35)
        else
            Farm.status = "No survivors found"
            Mover.stop(); setRun(false)
        end
        return
    end

    -- score targets: close, wounded, stationary (repairing)
    local best, bestScore, cur, curScore
    for _, sv in ipairs(survivors) do
        local d = (sv.pos - myPos).Magnitude
        local score = d - (1 - sv.hp) * 35
        if sv.vel.Magnitude < 1 then score -= 18 end
        if K.target and sv.model == K.target.model then cur, curScore = sv, score end
        if not bestScore or score < bestScore then best, bestScore = sv, score end
    end
    -- commit to a chase: keep the current target for at least 4s, and after
    -- that only switch when someone is clearly better (or right next to us)
    local wounded = cur and cur.hp < 0.45 -- finish them: don't drop a nearly-dead target
    local committed = cur and (os.clock() - K.targetT < (wounded and 9 or 4))
    local clearlyBetter = cur and bestScore < curScore - (wounded and 70 or 30)
    local rightHere = best and (best.pos - myPos).Magnitude < 8 and cur and best.model ~= cur.model
    if cur and (committed or not clearlyBetter) and not rightHere then
        K.target = cur
    else
        K.target = best
        K.targetT = os.clock()
        K.lastDist = nil
        K.progressT = os.clock()
    end
    local t = K.target
    local d = (t.pos - myPos).Magnitude
    local name = t.model:GetAttribute("Username") or t.model.Name

    -- give up on targets we can't close in on (unreachable spots)
    if not K.lastDist or d < K.lastDist - 3 then
        K.lastDist = d
        K.progressT = os.clock()
    elseif os.clock() - K.progressT > 9 and d > 20 then
        K.blacklist[t.model] = os.clock() + 8
        K.target = nil
        return
    end

    -- predictive intercept: aim where they will be
    local mySpeed = math.max(12, hum.WalkSpeed)
    local lead = math.clamp(d / mySpeed, 0, 1.2)
    local aim = t.pos + t.vel * lead
    local range = auraRange()

    if d <= range + 1 then
        Farm.status = "Attacking " .. name
        hum:MoveTo(t.pos + t.vel * 0.15)
        faceTowards(t.pos + t.vel * 0.1)
        local look = r.CFrame.LookVector
        local to = Vector3.new(t.pos.X - myPos.X, 0, t.pos.Z - myPos.Z)
        if to.Magnitude < 0.1 or look:Dot(to.Unit) > 0.5 then tryAttack() end
        setRun(true, 0.2)
        Mover.goal = nil
        return
    end

    Farm.status = ("Chasing %s (%d studs)"):format(name, d)
    -- optional: cycle the killer's other abilities (slots 2+) during a close chase;
    -- the game ignores presses while an ability is on cooldown
    if Cfg.KillerAbilities and d <= 22 and os.clock() - K.abilT > 1.4 then
        local n = #abilityButtons()
        if n >= 2 then
            K.abilT = os.clock()
            K.abilIdx = (K.abilIdx % (n - 1)) + 2
            if K.abilIdx ~= Cfg.AttackSlot then useAbilitySlot(K.abilIdx) end
        end
    end
    setRun(true, d < 40 and 0.05 or 0.3) -- burn stamina when the catch is close
    Mover.set(aim, d < 30 and 0.3 or 0.8)
end

-- Driver ---------------------------------------------------------------
local brainT = 0
local lastRole
local function onRoleChanged(role)
    if role == "Survivors" then
        Stats.roundsSurvivor += 1
        local k = teamFolder("Killers")
        local km = k and k:GetChildren()[1]
        local kname = km and (km:GetAttribute("ActorDisplayName") or km.Name) or "unknown"
        notify("Round started", ("You're a Survivor. Killer: %s%s"):format(kname,
            Cfg.FarmSurvivor and " - survivor AI is on" or ""), 5)
    elseif role == "Killers" then
        Stats.roundsKiller += 1
        local c = LP.Character
        notify("Round started", ("You're the Killer (%s)%s"):format(c and (c:GetAttribute("ActorDisplayName") or c.Name) or "?",
            Cfg.FarmKiller and " - killer AI is on" or ""), 5)
    end
    S.gen, S.fleeGoal, S.fleeing = nil, nil, false
    K.target, K.lastDist = nil, nil
end
connect(RunService.Heartbeat, function(dt)
    if not alive then return end
    local role = myRole()
    if role ~= lastRole then
        local prev = lastRole
        lastRole = role
        if prev ~= nil then pcall(onRoleChanged, role) end
    end
    local active = (Cfg.FarmSurvivor and role == "Survivors") or (Cfg.FarmKiller and role == "Killers")
    if active then Stats.farmTime += dt end
    if not active then
        if Mover.goal then Mover.stop() end
        Farm.sprint = false
        if farming() then
            Farm.status = (role == "Spectating") and "Waiting for next round" or ("Idle (" .. tostring(role) .. ")")
        else
            Farm.status = "Off"
        end
        return
    end
    local now = os.clock()
    if now - brainT >= 0.1 then
        brainT = now
        local ok, err = pcall(role == "Survivors" and survivorBrain or killerBrain)
        if not ok then warn("[FurinaHub] brain: " .. tostring(err)) end
    end
    -- the mover stays paused while repairing, except to escape the killer
    if not inPuzzle() or S.mode == "flee" then
        local ok, err = pcall(Mover.update)
        if not ok then warn("[FurinaHub] mover: " .. tostring(err)) end
    end
end)
task.spawn(function()
    while alive do
        refreshLosFilter()
        for k, v in pairs(S.cooldown) do if v < os.clock() then S.cooldown[k] = nil end end
        for k, v in pairs(K.blacklist) do if v < os.clock() then K.blacklist[k] = nil end end
        task.wait(3)
    end
end)
onCleanup(function() Farm.sprint = false; pcall(Mover.stop) end)
genv.__FurinaFarm = Farm
genv.__FurinaCfg = Cfg
genv.__FurinaAI = { S = S, K = K, Mover = Mover, liveGenerators = liveGenerators }

----------------------------------------------------------------------
-- Anti-AFK (Roblox kicks after 20 idle minutes)
----------------------------------------------------------------------
do
    local disabled = {}
    for _, c in ipairs(connsOf(LP.Idled)) do
        if pcall(function() c:Disable() end) then table.insert(disabled, c) end
    end
    onCleanup(function() for _, c in ipairs(disabled) do pcall(function() c:Enable() end) end end)
    local VirtualUser = game:GetService("VirtualUser")
    connect(LP.Idled, function()
        if Cfg.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end)
end

----------------------------------------------------------------------
-- FPS Boost (big help on phones): turns off particles/trails/post effects
-- and drops render quality. Fully reversible.
----------------------------------------------------------------------
local Boost = { on = false, disabled = {}, conn = nil, savedQuality = nil, savedShadows = nil }
local FX = { ParticleEmitter = true, Trail = true, Smoke = true, Fire = true, Sparkles = true, Beam = true }
local POST = { BloomEffect = true, BlurEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true }
local function boostOne(d)
    if (FX[d.ClassName] or POST[d.ClassName]) and d.Enabled then
        Boost.disabled[d] = true
        d.Enabled = false
    end
end
local function setFpsBoost(on)
    if on == Boost.on then return end
    Boost.on = on
    if on then
        Boost.savedShadows = Lighting.GlobalShadows
        Lighting.GlobalShadows = false
        pcall(function()
            Boost.savedQuality = settings().Rendering.QualityLevel
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
        for _, d in ipairs(workspace:GetDescendants()) do boostOne(d) end
        for _, d in ipairs(Lighting:GetChildren()) do boostOne(d) end
        Boost.conn = workspace.DescendantAdded:Connect(function(d) task.defer(function() if Boost.on then boostOne(d) end end) end)
    else
        if Boost.conn then Boost.conn:Disconnect(); Boost.conn = nil end
        for d in pairs(Boost.disabled) do if d.Parent then pcall(function() d.Enabled = true end) end end
        table.clear(Boost.disabled)
        if Boost.savedShadows ~= nil then Lighting.GlobalShadows = Boost.savedShadows end
        pcall(function() settings().Rendering.QualityLevel = Boost.savedQuality or Enum.QualityLevel.Automatic end)
    end
end
onCleanup(function() setFpsBoost(false) end)

----------------------------------------------------------------------
-- Auto rejoin when disconnected / kicked by a server error
----------------------------------------------------------------------
local rejoining = false
local function rejoin(reason)
    if rejoining then return end
    rejoining = true
    warn("[FurinaHub] rejoining: " .. tostring(reason))
    task.wait(3)
    pcall(function() TeleportSvc:Teleport(game.PlaceId, LP) end)
    task.delay(15, function() rejoining = false end)
end
pcall(function()
    connect(GuiService.ErrorMessageChanged, function(msg)
        if Cfg.AutoRejoin and msg and msg ~= "" then rejoin(msg) end
    end)
end)
pcall(function()
    local overlay = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
    overlay = overlay and overlay:FindFirstChild("promptOverlay")
    if overlay then
        connect(overlay.ChildAdded, function(c)
            if Cfg.AutoRejoin and c.Name == "ErrorPrompt" then rejoin("error prompt") end
        end)
    end
end)

-- Server hop: emptiest (or random) public server that isn't this one
local function serverHop(emptiest)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok then return false, "couldn't reach the server list" end
    local okj, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not okj or type(data) ~= "table" or type(data.data) ~= "table" then return false, "bad server list" end
    local list = {}
    for _, sv in ipairs(data.data) do
        if sv.id ~= game.JobId and (sv.playing or 0) < (sv.maxPlayers or 0) and (sv.playing or 0) > 0 then
            table.insert(list, sv)
        end
    end
    if #list == 0 then return false, "no other servers with space" end
    local pick
    if emptiest then
        table.sort(list, function(a, b) return a.playing < b.playing end)
        pick = list[1]
    else
        pick = list[math.random(1, #list)]
    end
    TeleportSvc:TeleportToPlaceInstance(game.PlaceId, pick.id, LP)
    return true, ("%d/%d players"):format(pick.playing, pick.maxPlayers)
end

----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
local espRoot = Instance.new("Folder")
espRoot.Name = HttpService:GenerateGUID(false)
safeParent(espRoot)
onCleanup(function() espRoot:Destroy() end)

local Esp = {} -- [instance] = record

local function newEsp(target, anchor)
    local hl = Instance.new("Highlight")
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.7
    hl.OutlineTransparency = 0
    hl.Adornee = target
    hl.Parent = espRoot

    local bb = Instance.new("BillboardGui")
    bb.AlwaysOnTop = true
    bb.Size = UDim2.fromOffset(220, 36)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.LightInfluence = 0
    bb.Adornee = anchor
    bb.Parent = espRoot

    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Size = UDim2.fromScale(1, 1)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 13
    tl.TextStrokeTransparency = 0.35
    tl.Parent = bb
    return { hl = hl, bb = bb, tl = tl, seen = 0 }
end
local function dropEsp(k)
    local r = Esp[k]
    if r then r.hl:Destroy(); r.bb:Destroy(); Esp[k] = nil end
end

local tick_ = 0
local function espUpdate()
    tick_ += 1
    local me = myRoot()
    local myPos = me and me.Position

    local function show(target, color, text)
        local anchor = rootOf(target)
        if not anchor then return end
        local r = Esp[target]
        if not r then r = newEsp(target, anchor); Esp[target] = r end
        if r.bb.Adornee ~= anchor then r.bb.Adornee = anchor end
        if r.color ~= color then -- Highlight writes force an outline rebuild, so only on change
            r.color = color
            r.hl.FillColor, r.hl.OutlineColor, r.tl.TextColor3 = color, color, color
        end
        local parts = {}
        if Cfg.EspNames then table.insert(parts, text) end
        if Cfg.EspDistance and myPos then table.insert(parts, ("[%dm]"):format(dist(anchor.Position, myPos) // 1)) end
        local txt = table.concat(parts, " ")
        if r.tl.Text ~= txt then r.tl.Text = txt end
        setIf(r.bb, "Enabled", #parts > 0)
        r.seen = tick_
    end

    local function rigText(m)
        local h = m:FindFirstChildOfClass("Humanoid")
        local user = m:GetAttribute("Username")
        local actor = m:GetAttribute("ActorDisplayName") or m.Name
        local s = user and ("%s (%s)"):format(user, actor) or actor
        if Cfg.EspHealth and h then s ..= (" | %d HP"):format(math.max(0, h.Health) // 1) end
        return s
    end

    if Cfg.EspKillers then
        local f = teamFolder("Killers")
        if f then for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") and m ~= LP.Character then show(m, Cfg.KillerColor, rigText(m)) end
        end end
    end
    if Cfg.EspSurvivors then
        local f = teamFolder("Survivors")
        if f then for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") and m ~= LP.Character then show(m, Cfg.SurvivorColor, rigText(m)) end
        end end
    end
    if Cfg.EspGens then
        -- real repair progress straight from the game's generator binders
        for _, info in ipairs(liveGenerators()) do
            local g = info.inst
            local puzzle = tostring(g:GetAttribute("Puzzle") or ""):gsub("ServerMinigame", "")
            local label = ("Generator %d%%"):format(info.progress * 100)
            if puzzle ~= "" then label ..= " (" .. puzzle .. ")" end
            show(g, Cfg.GenColor, label)
        end
    end
    if Cfg.EspGears then
        for gm in pairs(Gears) do
            if gm.Parent and gearPrompt(gm) then show(gm, Cfg.GearColor, "Gear") end
        end
    end
    if Cfg.EspItems then
        for it in pairs(Items) do
            if it.Parent and it:IsDescendantOf(workspace.Map) then show(it, Cfg.ItemColor, it.Name) end
        end
    end

    for k, r in pairs(Esp) do
        if r.seen ~= tick_ or not k.Parent then dropEsp(k) end
    end
end

----------------------------------------------------------------------
-- Visuals
----------------------------------------------------------------------
local savedLighting
local FB_AMB = Color3.fromRGB(180, 180, 180)
local function applyLighting()
    if Cfg.Fullbright or Cfg.NoFog then
        savedLighting = savedLighting or {
            Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
            GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
        }
    end
    -- only write what differs: re-setting Lighting to the same value still makes
    -- the renderer rebuild lighting, which was the main source of stutter
    if Cfg.Fullbright then
        setIf(Lighting, "Brightness", 2); setIf(Lighting, "ClockTime", 14); setIf(Lighting, "GlobalShadows", false)
        setIf(Lighting, "Ambient", FB_AMB); setIf(Lighting, "OutdoorAmbient", FB_AMB)
    end
    if Cfg.NoFog then
        setIf(Lighting, "FogEnd", 1e6); setIf(Lighting, "FogStart", 1e6)
        for _, a in ipairs(Lighting:GetChildren()) do
            if a:IsA("Atmosphere") then setIf(a, "Density", 0); setIf(a, "Haze", 0) end
        end
    end
end
local function restoreLighting()
    if not savedLighting then return end
    for k, v in pairs(savedLighting) do pcall(function() Lighting[k] = v end) end
    savedLighting = nil
end
onCleanup(restoreLighting)

----------------------------------------------------------------------
-- Main loops
----------------------------------------------------------------------
local lastEnter, lastPickup, warned = 0, 0, false

connect(RunService.Heartbeat, function()
    if not alive then return end
    -- infinite stamina (the game's own bypass flag)
    if Sprinting then
        if Cfg.InfStamina then
            Sprinting.StaminaLossDisabled = true
            if type(Sprinting.MaxStamina) == "number" then Sprinting.Stamina = Sprinting.MaxStamina end
        end
    end

    local role = myRole()
    local r = myRoot()
    if not r then return end
    local now = os.clock()

    -- killer: kill aura / chase
    if role == "Killers" and not Cfg.FarmKiller and (Cfg.KillAura or Cfg.AutoChase) then
        local f = teamFolder("Survivors")
        local best, bd
        if f then for _, m in ipairs(f:GetChildren()) do
            local h = m:FindFirstChildOfClass("Humanoid"); local tr = rootOf(m)
            if tr and h and h.Health > 0 then
                local d = dist(tr.Position, r.Position)
                if not bd or d < bd then best, bd = tr, d end
            end
        end end
        if best then
            local hum = LP.Character:FindFirstChildOfClass("Humanoid")
            if Cfg.AutoChase and hum and bd > auraRange() * 0.7 then hum:MoveTo(best.Position) end
            if Cfg.KillAura and bd <= auraRange() then
                faceTowards(best.Position)
                tryAttack()
            end
        end
    end

    -- survivor: auto enter generator
    if role == "Survivors" and Cfg.AutoEnterGen and not Cfg.FarmSurvivor and now - lastEnter > 1.5 then
        lastEnter = now
        local g = not inPuzzle() and nearestGen(12)
        local p = g and genPrompt(g)
        if p and p.Enabled and (p.Parent.Position - r.Position).Magnitude <= p.MaxActivationDistance - 0.5 then
            task.spawn(firePrompt, p)
        end
    end

    -- survivor: auto pickup
    if role == "Survivors" and Cfg.AutoPickup and now - lastPickup > 0.5 then
        lastPickup = now
        for it in pairs(Items) do
            local h = it.Parent and rootOf(it)
            if h and dist(h.Position, r.Position) <= Cfg.PickupDist then
                local p = it:FindFirstChildWhichIsA("ProximityPrompt", true)
                local okRange = not Cfg.SafeMode or (p and dist(h.Position, r.Position) <= p.MaxActivationDistance - 0.5)
                if p and p.Enabled and okRange then task.spawn(firePrompt, p) end
            end
        end
    end

    -- survivor: auto collect gears in range
    if role == "Survivors" and Cfg.AutoGears and now - lastPickup > 0.25 and gearsHeld() < 1 then
        for gm in pairs(Gears) do
            local root = gm.Parent and rootOf(gm)
            local p = root and gearPrompt(gm)
            if p and dist(root.Position, r.Position) <= p.MaxActivationDistance - 0.5 then grabGear(p) break end
        end
    end

    -- survivor: killer warning
    if role == "Survivors" and Cfg.KillerWarn then
        local f = teamFolder("Killers")
        local close
        if f then for _, m in ipairs(f:GetChildren()) do
            local kr = rootOf(m)
            if kr and dist(kr.Position, r.Position) <= Cfg.WarnDist then close = m:GetAttribute("ActorDisplayName") or m.Name break end
        end end
        if close and not warned then
            warned = true
            notify("⚠ Killer nearby", ("%s is within %d studs!"):format(close, Cfg.WarnDist), 3)
        elseif not close and warned then
            warned = false
        end
    end
end)

task.spawn(function()
    while alive do
        local anyEsp = Cfg.EspKillers or Cfg.EspSurvivors or Cfg.EspGens or Cfg.EspItems or Cfg.EspGears
        if anyEsp or next(Esp) then pcall(espUpdate) end
        if Cfg.Fullbright or Cfg.NoFog then pcall(applyLighting) end
        task.wait(anyEsp and 0.2 or 0.5)
    end
end)
onCleanup(function() for k in pairs(Esp) do dropEsp(k) end end)
onCleanup(function() if Sprinting then Sprinting.StaminaLossDisabled = false end end)

----------------------------------------------------------------------
-- UI (Maclib)
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Furina theme
--   Maclib draws with a #0f0f0f base and translucent white overlays/strokes.
--   We recolour those to a sapphire / aqua / gold palette (inspired by
--   Furina's Hydro colours) and keep re-applying as Maclib builds or
--   animates elements. "Classic" turns it off.
----------------------------------------------------------------------
local Furina = {
    base   = Color3.fromRGB(11, 26, 51),    -- deep sapphire
    glass  = Color3.fromRGB(168, 220, 255), -- pale aqua overlay
    text   = Color3.fromRGB(234, 246, 255), -- soft white-blue
    gold   = Color3.fromRGB(232, 199, 122), -- gold trim
    accent = Color3.fromRGB(79, 179, 255),  -- hydro blue
}
local function themeTarget()
    for _, g in ipairs(hiddenUI():GetChildren()) do
        local b = g:FindFirstChild("Base")
        if b and b:FindFirstChild("Sidebar") then return g, b end
    end
end
local themed = setmetatable({}, { __mode = "k" })
local function paint(d, on)
    if d:IsA("GuiObject") then
        local hex = d.BackgroundColor3:ToHex()
        if on then
            if hex == "0f0f0f" then themed[d] = themed[d] or {}; themed[d].bg = hex; d.BackgroundColor3 = Furina.base
            elseif hex == "ffffff" then themed[d] = themed[d] or {}; themed[d].bg = hex; d.BackgroundColor3 = Furina.glass end
        elseif themed[d] and themed[d].bg then
            d.BackgroundColor3 = Color3.fromHex(themed[d].bg)
        end
    end
    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
        if on and d.TextColor3:ToHex() == "ffffff" then
            themed[d] = themed[d] or {}; themed[d].text = true
            d.TextColor3 = (d.Text == "Furina Hub") and Furina.gold or Furina.text
        elseif not on and themed[d] and themed[d].text then
            d.TextColor3 = Color3.new(1, 1, 1)
        end
    end
    if d:IsA("UIStroke") then
        if on and d.Color:ToHex() == "ffffff" then themed[d] = themed[d] or {}; themed[d].stroke = true; d.Color = Furina.glass
        elseif not on and themed[d] and themed[d].stroke then d.Color = Color3.new(1, 1, 1) end
    end
    if d:IsA("ImageLabel") or d:IsA("ImageButton") then
        if on and d.ImageColor3:ToHex() == "ffffff" then themed[d] = themed[d] or {}; themed[d].img = true; d.ImageColor3 = Furina.glass
        elseif not on and themed[d] and themed[d].img then d.ImageColor3 = Color3.new(1, 1, 1) end
    end
end
local function applyTheme()
    local gui, base = themeTarget()
    if not gui then return end
    local on = Cfg.Theme == "Furina"
    for _, d in ipairs(gui:GetDescendants()) do pcall(paint, d, on) end
    local grad = base:FindFirstChild("FurinaGradient")
    if on and not grad then
        grad = Instance.new("UIGradient")
        grad.Name = "FurinaGradient"
        grad.Rotation = 120
        grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 205, 255))
        grad.Parent = base
    elseif not on and grad then
        grad:Destroy()
    end
end
task.spawn(function()
    -- keep up with tabs/elements Maclib creates later and colours it re-tweens
    local lastTheme
    while alive do
        if Cfg.Theme == "Furina" or lastTheme ~= Cfg.Theme then pcall(applyTheme) end
        lastTheme = Cfg.Theme
        task.wait(1.5)
    end
end)

----------------------------------------------------------------------
-- Round info, spectate, low-health alert
----------------------------------------------------------------------
local function roundInfo()
    local killers, survivorsAlive = {}, 0
    local kf, sf = teamFolder("Killers"), teamFolder("Survivors")
    for _, m in ipairs(kf and kf:GetChildren() or {}) do
        local user = m:GetAttribute("Username")
        table.insert(killers, (m:GetAttribute("ActorDisplayName") or m.Name) .. (user and (" (" .. user .. ")") or ""))
    end
    for _, m in ipairs(sf and sf:GetChildren() or {}) do
        local h = m:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 then survivorsAlive += 1 end
    end
    local total, done = 0, 0
    if genRunning then
        for inst, obj in pairs(genRunning) do
            if typeof(inst) == "Instance" and inst.Name == "Generator" then
                local ok, maxc, comp = pcall(function()
                    return obj.Network.Properties:Get("MaxCounter"), obj.Network.Properties:Get("Completed")
                end)
                if ok and (maxc or 0) > 0 then
                    total += 1
                    if comp then done += 1 end
                end
            end
        end
    end
    local timer = RS:FindFirstChild("RoundTimer")
    return {
        killer = #killers > 0 and table.concat(killers, ", ") or "none (lobby)",
        survivors = survivorsAlive, gensDone = done, gensTotal = total,
        timer = timer and tostring(timer.Value) or "?",
    }
end

local Spectate = { idx = 0 }
local function spectateNext(killerOnly)
    local cam = workspace.CurrentCamera
    local list = {}
    for _, name in ipairs(killerOnly and { "Killers" } or { "Killers", "Survivors" }) do
        local f = teamFolder(name)
        for _, m in ipairs(f and f:GetChildren() or {}) do
            local h = m:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 and m ~= LP.Character then table.insert(list, { m = m, h = h }) end
        end
    end
    if #list == 0 then notify("Spectate", "Nobody to spectate right now.", 3) return end
    Spectate.idx = (Spectate.idx % #list) + 1
    local pick = list[Spectate.idx]
    cam.CameraSubject = pick.h
    notify("Spectate", ("Watching %s"):format(pick.m:GetAttribute("Username") or pick.m.Name), 2)
end
local function spectateSelf()
    local h = myHum()
    if h then workspace.CurrentCamera.CameraSubject = h end
end
onCleanup(spectateSelf)

do
    local lowWarned = false
    task.spawn(function()
        while alive do
            local h = myHum()
            if Cfg.LowHpAlert and h and myRole() == "Survivors" then
                local frac = h.Health / math.max(1, h.MaxHealth)
                if frac < 0.35 and h.Health > 0 and not lowWarned then
                    lowWarned = true
                    notify("Low health", ("You're at %d HP - play safe!"):format(h.Health), 4)
                elseif frac > 0.5 then
                    lowWarned = false
                end
            end
            task.wait(0.5)
        end
    end)
end

----------------------------------------------------------------------
-- Extras (v7): auto heal, danger vignette, tracers, camera FOV / zoom,
-- stats overlay, generator alerts, auto spectate killer
----------------------------------------------------------------------
local function killerNearest(pos)
    local best
    for _, k in ipairs(killersInfo()) do
        local d = (k.pos - pos).Magnitude
        if not best or d < best then best = d end
    end
    return best
end

-- Auto heal: use a Medkit when low, but only when the killer isn't close
-- (taking damage cancels the heal, so it would just waste it)
do
    local lastHeal = 0
    local function healTool()
        local function pick(c)
            if not c then return end
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and t.Name:find("Medkit") and not t.Name:find("Fake") then return t end
            end
        end
        return pick(LP.Character) or pick(LP:FindFirstChildOfClass("Backpack"))
    end
    task.spawn(function()
        while alive do
            task.wait(0.5)
            local h, r = myHum(), myRoot()
            if Cfg.AutoHeal and h and r and myRole() == "Survivors" and h.Health > 0
                and h.Health / math.max(1, h.MaxHealth) * 100 < Cfg.HealAt
                and os.clock() - lastHeal > 8 and not inPuzzle() then
                local kd = killerNearest(r.Position)
                local tool = (not kd or kd > 45) and healTool()
                if tool then
                    lastHeal = os.clock()
                    pcall(function()
                        if tool.Parent ~= LP.Character then h:EquipTool(tool); task.wait(0.35) end
                        tool:Activate()
                    end)
                    notify("Auto Heal", ("Using %s at %d HP"):format(tool.Name, h.Health), 3)
                end
            end
        end
    end)
end

-- Danger vignette: red screen edges that get stronger as the killer gets closer
local vigGui = Instance.new("ScreenGui")
vigGui.Name = HttpService:GenerateGUID(false):sub(1, 8)
vigGui.IgnoreGuiInset = true
vigGui.ResetOnSpawn = false
vigGui.DisplayOrder = -5
safeParent(vigGui)
onCleanup(function() vigGui:Destroy() end)
local vigEdges = {}
for _, e in ipairs({
    { UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0), 90 },     -- top
    { UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0.84), -90 }, -- bottom
    { UDim2.fromScale(0.12, 1), UDim2.fromScale(0, 0), 0 },      -- left
    { UDim2.fromScale(0.12, 1), UDim2.fromScale(0.88, 0), 180 }, -- right
}) do
    local f = Instance.new("Frame")
    f.Size, f.Position = e[1], e[2]
    f.BorderSizePixel = 0
    f.BackgroundColor3 = Color3.fromRGB(220, 20, 40)
    f.BackgroundTransparency = 1
    f.Parent = vigGui
    local g = Instance.new("UIGradient")
    g.Rotation = e[3]
    g.Transparency = NumberSequence.new(0, 1)
    g.Parent = f
    table.insert(vigEdges, f)
end
task.spawn(function()
    local cur = 1
    while alive do
        task.wait(0.1)
        local want = 1
        local r = myRoot()
        if Cfg.DangerVignette and r and myRole() == "Survivors" then
            local kd = killerNearest(r.Position)
            if kd and kd < Cfg.VignetteDist then
                local k = 1 - math.clamp((kd - 12) / math.max(1, Cfg.VignetteDist - 12), 0, 1)
                want = 1 - 0.15 - k * 0.55
            end
        end
        want = math.floor(want * 20 + 0.5) / 20 -- coarse steps: fewer UI writes
        if want ~= cur then
            cur = want
            for _, f in ipairs(vigEdges) do f.BackgroundTransparency = cur end
        end
    end
end)

-- Tracers (lines from the bottom of the screen to players). PC executors
-- with the Drawing library only; quietly does nothing elsewhere.
do
    local lines = {}
    local function drop(m) if lines[m] then pcall(function() lines[m]:Remove() end); lines[m] = nil end end
    onCleanup(function() for m in pairs(lines) do drop(m) end end)
    if Drawing and Drawing.new then
        connect(RunService.RenderStepped, function()
            if not (Cfg.TracerKillers or Cfg.TracerSurvivors) then
                if next(lines) then for m in pairs(lines) do drop(m) end end
                return
            end
            local cam = workspace.CurrentCamera
            local vp = cam.ViewportSize
            local from = Vector2.new(vp.X / 2, vp.Y - 4)
            local seen = {}
            for _, team in ipairs({ "Killers", "Survivors" }) do
                local on = (team == "Killers" and Cfg.TracerKillers) or (team == "Survivors" and Cfg.TracerSurvivors)
                local f = on and teamFolder(team)
                for _, m in ipairs(f and f:GetChildren() or {}) do
                    local rt = m ~= LP.Character and rootOf(m)
                    if rt then
                        local sp, vis = cam:WorldToViewportPoint(rt.Position)
                        local ln = lines[m]
                        if not ln then
                            local ok, l = pcall(Drawing.new, "Line")
                            if ok then ln = l; ln.Thickness = 1.5; ln.Transparency = 1; lines[m] = ln end
                        end
                        if ln then
                            seen[m] = true
                            ln.Visible = vis
                            if vis then
                                ln.From = from
                                ln.To = Vector2.new(sp.X, sp.Y)
                                ln.Color = team == "Killers" and Cfg.KillerColor or Cfg.SurvivorColor
                            end
                        end
                    end
                end
            end
            for m in pairs(lines) do if not seen[m] then drop(m) end end
        end)
    end
end

-- Camera: custom field of view and unlocked zoom distance
do
    local savedZoom = LP.CameraMaxZoomDistance
    local fovBound = false
    local function bindFov(on)
        if on and not fovBound then
            fovBound = true
            RunService:BindToRenderStep("FurinaFov", Enum.RenderPriority.Camera.Value + 1, function()
                local cam = workspace.CurrentCamera
                if cam and Cfg.FovOn then setIf(cam, "FieldOfView", Cfg.Fov) end
            end)
        elseif not on and fovBound then
            fovBound = false
            pcall(function() RunService:UnbindFromRenderStep("FurinaFov") end)
        end
    end
    onCleanup(function() bindFov(false); pcall(function() LP.CameraMaxZoomDistance = savedZoom end) end)
    task.spawn(function()
        local zoomWas = false
        while alive do
            bindFov(Cfg.FovOn)
            if Cfg.ZoomUnlock then
                if not zoomWas then savedZoom = LP.CameraMaxZoomDistance end
                setIf(LP, "CameraMaxZoomDistance", 60)
            elseif zoomWas then
                pcall(function() LP.CameraMaxZoomDistance = savedZoom end)
            end
            zoomWas = Cfg.ZoomUnlock
            task.wait(0.5)
        end
    end)
end

-- Stats overlay (FPS, ping, generators, killer, timer) + generator alerts
local ovGui = Instance.new("ScreenGui")
ovGui.Name = HttpService:GenerateGUID(false):sub(1, 8)
ovGui.ResetOnSpawn = false
ovGui.DisplayOrder = 50
safeParent(ovGui)
onCleanup(function() ovGui:Destroy() end)
local ovLabel = Instance.new("TextLabel")
ovLabel.AnchorPoint = Vector2.new(0.5, 0)
ovLabel.Position = UDim2.new(0.5, 0, 0, 4)
ovLabel.Size = UDim2.fromOffset(IS_MOBILE and 330 or 460, 22)
ovLabel.BackgroundColor3 = Color3.fromRGB(11, 26, 51)
ovLabel.BackgroundTransparency = 0.25
ovLabel.TextColor3 = Color3.fromRGB(234, 246, 255)
ovLabel.Font = Enum.Font.GothamBold
ovLabel.TextSize = IS_MOBILE and 11 or 13
ovLabel.Visible = false
ovLabel.Parent = ovGui
Instance.new("UICorner", ovLabel).CornerRadius = UDim.new(0, 6)
local ovStroke = Instance.new("UIStroke", ovLabel)
ovStroke.Color = Color3.fromRGB(232, 199, 122)
ovStroke.Transparency = 0.4
local frames = 0
connect(RunService.RenderStepped, function() frames += 1 end)
task.spawn(function()
    local lastT, lastDone, lastTotal = os.clock(), nil, 0
    while alive do
        task.wait(0.5)
        local now = os.clock()
        local fps = frames / math.max(0.01, now - lastT)
        frames, lastT = 0, now
        local info = roundInfo()
        -- generator alerts (only during a round, never for the first sample)
        if info.gensTotal > 0 then
            if lastDone and info.gensDone > lastDone and Cfg.GenAlerts then
                if info.gensDone >= info.gensTotal then
                    notify("Generators", "All generators done - head for the exits!", 5)
                else
                    notify("Generators", ("Generator finished (%d/%d)"):format(info.gensDone, info.gensTotal), 3)
                end
            end
            lastDone = info.gensDone
        else
            lastDone = nil
        end
        lastTotal = info.gensTotal
        ovLabel.Visible = Cfg.Overlay
        if Cfg.Overlay then
            local ping = (try(function() return LP:GetNetworkPing() end) or 0) * 1000
            local txt = ("FPS %d  |  Ping %dms  |  Gens %d/%d  |  Alive %d  |  %s"):format(
                fps + 0.5, ping, info.gensDone, info.gensTotal, info.survivors,
                info.gensTotal > 0 and ("Killer: " .. info.killer:sub(1, 26)) or "Lobby")
            if ovLabel.Text ~= txt then ovLabel.Text = txt end
        end
    end
end)

-- Auto spectate the killer while you're out of the round (switches only when
-- the camera is on yourself, so picking someone by hand still works)
task.spawn(function()
    while alive do
        task.wait(1)
        if Cfg.AutoSpectate and myRole() == "Spectating" then
            local cam = workspace.CurrentCamera
            local subj = cam.CameraSubject
            local mine = myHum()
            local onKiller = false
            local kf = teamFolder("Killers")
            if subj and subj:IsA("Humanoid") and kf and subj.Parent and subj.Parent.Parent == kf and subj.Health > 0 then
                onKiller = true
            end
            if not onKiller and (subj == nil or subj == mine or (subj:IsA("Humanoid") and subj.Health <= 0)) then
                for _, m in ipairs(kf and kf:GetChildren() or {}) do
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if h and h.Health > 0 then cam.CameraSubject = h break end
                end
            end
        end
    end
end)

local MacLib = loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"))()

Window = MacLib:Window({
    Title = "Furina Hub",
    Subtitle = IS_MOBILE and "Forsaken • Mobile" or "Forsaken • Auto Farm • ESP",
    Size = IS_MOBILE and UDim2.fromOffset(560, 340) or UDim2.fromOffset(820, 560),
    DragStyle = IS_MOBILE and 2 or 1, -- 2 = drag anywhere (touch)
    DisabledWindowControls = {},
    ShowUserInfo = true,
    Keybind = Enum.KeyCode.RightControl,
    AcrylicBlur = false, -- Maclib docs: the blur effect "can be detected"
})
Window.onUnloaded(function() task.defer(unload) end)
genv.__FurinaWindow = Window

local group = Window:TabGroup()
local tabs = {
    Farm    = group:Tab({ Name = "Auto Farm", Image = "rbxassetid://10734950309" }),
    Stats   = group:Tab({ Name = "Stats",   Image = "rbxassetid://10734950309" }),
    Main    = group:Tab({ Name = "Main",    Image = "rbxassetid://10734950309" }),
    Killer  = group:Tab({ Name = "Killer",  Image = "rbxassetid://10734950309" }),
    ESP     = group:Tab({ Name = "ESP",     Image = "rbxassetid://10734950309" }),
    Visuals = group:Tab({ Name = "Visuals", Image = "rbxassetid://10734950309" }),
    Misc    = group:Tab({ Name = "Misc",    Image = "rbxassetid://10734950309" }),
}

-- Auto Farm
local farmL = tabs.Farm:Section({ Side = "Left" })
farmL:Header({ Text = "Auto Farm" })
local statusLabel = farmL:Label({ Text = "Status: Off" })
local survFarmToggle, killFarmToggle
survFarmToggle = farmL:Toggle({ Name = "Survivor Farm (gens + flee)", Default = false, Callback = function(v)
    Cfg.FarmSurvivor = v
    if not v then Farm.sprint = false end
end }, "FarmSurvivor")
killFarmToggle = farmL:Toggle({ Name = "Killer Farm (chase + attack)", Default = false, Callback = function(v)
    Cfg.FarmKiller = v
    if not v then Farm.sprint = false end
end }, "FarmKiller")
farmL:Slider({ Name = "Flee When Killer Within", Default = 45, Minimum = 20, Maximum = 100, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.FleeDist = v end }, "FleeDist")
farmL:Toggle({ Name = "Fetch Gears For Gear Generators", Default = true, Callback = function(v) Cfg.FarmGears = v end }, "FarmGears")
farmL:Slider({ Name = "Attack Ability Slot", Default = 1, Minimum = 1, Maximum = 4, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.AttackSlot = v end }, "AttackSlot")
farmL:SubLabel({ Text = "Both can stay on: the AI plays whichever role you get each round. It runs everywhere, keeps a stamina reserve for escapes, reads real generator progress, flees on line of sight, and leads moving targets as killer." })

local farmR = tabs.Farm:Section({ Side = "Right" })
farmR:Header({ Text = "Safety" })
farmR:Toggle({ Name = "Safe Mode", Default = true, Callback = function(v) Cfg.SafeMode = v end }, "SafeMode")
farmR:SubLabel({ Text = "Blocks teleports, keeps solves 2s+ and human-paced, caps kill aura at 7.5 studs / 0.45s, only uses prompts in real range, turns smoothly." })
farmR:Toggle({ Name = "Smart Stamina (sprint like a player)", Default = true, Callback = function(v) Cfg.SmartStamina = v end }, "SmartStamina")
farmR:Toggle({ Name = "Anti-AFK", Default = true, Callback = function(v) Cfg.AntiAFK = v end }, "AntiAFK")

local function toggleFarm()
    local on = not (Cfg.FarmSurvivor or Cfg.FarmKiller)
    Cfg.FarmSurvivor, Cfg.FarmKiller = on, on
    pcall(function() survFarmToggle:UpdateState(on) end)
    pcall(function() killFarmToggle:UpdateState(on) end)
    if not on then Farm.sprint = false end
    notify("Auto Farm", on and "Enabled (both roles)" or "Disabled", 2)
end

farmR:Header({ Text = "Keybinds" })
farmR:Keybind({ Name = "Toggle Auto Farm", Default = Enum.KeyCode.F6, Callback = toggleFarm }, "FarmKey")
farmR:Keybind({ Name = "Panic: Unload Everything", Default = Enum.KeyCode.End, Callback = function()
    unload()
end }, "PanicKey")

task.spawn(function()
    local last
    while alive do
        local text = "Status: " .. Farm.status
        if text ~= last then pcall(function() statusLabel:UpdateName(text) end); last = text end
        task.wait(0.4)
    end
end)

-- Main / generators
-- Stats tab
local roundR = tabs.Stats:Section({ Side = "Right" })
roundR:Header({ Text = "This Round" })
local roundPara = roundR:Paragraph({ Header = "Round", Body = "..." })
roundR:Toggle({ Name = "Auto Spectate Killer When Out", Default = false, Callback = function(v) Cfg.AutoSpectate = v end }, "AutoSpectate")
roundR:Button({ Name = "Spectate Next Player", Callback = function() spectateNext(false) end })
roundR:Button({ Name = "Spectate Killer", Callback = function() spectateNext(true) end })
roundR:Button({ Name = "Camera Back To Me", Callback = spectateSelf })
task.spawn(function()
    while alive do
        local ok, info = pcall(roundInfo)
        if ok then
            pcall(function()
                roundPara:UpdateBody(table.concat({
                    "Killer: " .. info.killer,
                    ("Survivors alive: %d"):format(info.survivors),
                    ("Generators: %d / %d done"):format(info.gensDone, info.gensTotal),
                    "Timer: " .. info.timer,
                    "You are: " .. tostring(myRole()),
                }, "\n"))
            end)
        end
        task.wait(1)
    end
end)

local statL = tabs.Stats:Section({ Side = "Left" })
statL:Header({ Text = "This Session" })
local statPara = statL:Paragraph({ Header = "Stats", Body = "..." })
statL:Button({ Name = "Reset Stats", Callback = function()
    Stats.startT, Stats.farmTime, Stats.puzzles, Stats.hits = os.clock(), 0, 0, 0
    Stats.roundsSurvivor, Stats.roundsKiller, Stats.moneyStart = 0, 0, money()
end })
local function fmtTime(t)
    t = math.floor(t)
    return ("%dh %02dm %02ds"):format(t // 3600, (t % 3600) // 60, t % 60)
end
task.spawn(function()
    while alive do
        local m = money()
        if m and not Stats.moneyStart then Stats.moneyStart = m end -- leaderstats can load late
        local earned = (m and Stats.moneyStart) and (m - Stats.moneyStart) or 0
        local hours = math.max(Stats.farmTime, 1) / 3600
        local body = table.concat({
            ("Money earned: %d  (now %s)"):format(earned, m and tostring(m) or "?"),
            ("Money / hour farming: %d"):format(Stats.farmTime > 60 and earned / hours or 0),
            ("Rounds: %d survivor, %d killer"):format(Stats.roundsSurvivor, Stats.roundsKiller),
            ("Generator puzzles solved: %d"):format(Stats.puzzles),
            ("Killer hits landed: %d"):format(Stats.hits),
            ("Time farming: %s"):format(fmtTime(Stats.farmTime)),
            ("Session: %s"):format(fmtTime(os.clock() - Stats.startT)),
        }, "\n")
        pcall(function() statPara:UpdateBody(body) end)
        task.wait(1)
    end
end)

local gen = tabs.Main:Section({ Side = "Left" })
gen:Header({ Text = "Generators" })
gen:Toggle({ Name = "Auto Solve Puzzles", Default = false, Callback = function(v) Cfg.AutoGen = v end }, "AutoGen")
gen:Slider({ Name = "Solve Delay (s)", Default = 1.5, Minimum = 0, Maximum = 6, DisplayMethod = "Value", Precision = 1,
    Callback = function(v) Cfg.GenDelay = v end }, "GenDelay")
gen:Toggle({ Name = "Auto Enter Nearby Generator", Default = false, Callback = function(v) Cfg.AutoEnterGen = v end }, "AutoEnterGen")
gen:Button({ Name = "Teleport To Nearest Generator", Callback = function()
    if Cfg.SafeMode then notify("Safe Mode", "Teleport is blocked while Safe Mode is on.") return end
    local g = nearestGen()
    local r = myRoot()
    if not g or not r then notify("Generators", "No unfinished generator found.") return end
    local main = g:FindFirstChild("Main")
    local pos = (main and main.Position or g:GetPivot().Position)
    r.CFrame = CFrame.new(pos + (g:GetPivot().LookVector * 4) + Vector3.new(0, 3, 0), pos)
end })
gen:SubLabel({ Text = "Teleport only works with Safe Mode off. The server repositions anyone who leaves the map bounds." })

local surv = tabs.Main:Section({ Side = "Right" })
surv:Header({ Text = "Survivor" })
surv:Toggle({ Name = "Infinite Stamina", Default = false, Callback = function(v)
    Cfg.InfStamina = v
    if not v and Sprinting then Sprinting.StaminaLossDisabled = false end
end }, "InfStamina")
surv:Toggle({ Name = "Killer Nearby Warning", Default = false, Callback = function(v) Cfg.KillerWarn = v end }, "KillerWarn")
surv:Slider({ Name = "Warning Distance", Default = 60, Minimum = 20, Maximum = 200, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.WarnDist = v end }, "WarnDist")
surv:Toggle({ Name = "Auto Collect Gears", Default = false, Callback = function(v) Cfg.AutoGears = v end }, "AutoGears")
surv:Toggle({ Name = "Auto Heal (Medkit when low)", Default = false, Callback = function(v) Cfg.AutoHeal = v end }, "AutoHeal")
surv:Slider({ Name = "Heal Below HP %", Default = 50, Minimum = 15, Maximum = 90, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.HealAt = v end }, "HealAt")
surv:Toggle({ Name = "Danger Vignette (red edges)", Default = false, Callback = function(v) Cfg.DangerVignette = v end }, "DangerVignette")
surv:Slider({ Name = "Vignette Range", Default = 50, Minimum = 20, Maximum = 120, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.VignetteDist = v end }, "VignetteDist")
surv:Toggle({ Name = "Auto Pickup Items", Default = false, Callback = function(v) Cfg.AutoPickup = v end }, "AutoPickup")
surv:Slider({ Name = "Pickup Range", Default = 12, Minimum = 5, Maximum = 25, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.PickupDist = v end }, "PickupDist")

-- Killer
local kil = tabs.Killer:Section({ Side = "Left" })
kil:Header({ Text = "Killer" })
kil:Toggle({ Name = "Kill Aura", Default = false, Callback = function(v) Cfg.KillAura = v end }, "KillAura")
kil:Slider({ Name = "Aura Range", Default = 9, Minimum = 4, Maximum = 16, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.AuraRange = v end }, "AuraRange")
kil:Slider({ Name = "Attack Interval (s)", Default = 0.35, Minimum = 0.1, Maximum = 1.5, DisplayMethod = "Value", Precision = 2,
    Callback = function(v) Cfg.AuraDelay = v end }, "AuraDelay")
kil:Toggle({ Name = "Auto Chase Nearest Survivor", Default = false, Callback = function(v) Cfg.AutoChase = v end }, "AutoChase")
kil:Toggle({ Name = "Killer Farm: Use Other Abilities", Default = false, Callback = function(v) Cfg.KillerAbilities = v end }, "KillerAbilities")
kil:SubLabel({ Text = "Experimental: cycles your 2nd-4th abilities during close chases (each killer's kit differs)." })
kil:SubLabel({ Text = "Kill aura presses your first ability (M1) through the game's own button, so it works without window focus. Change the slot on the Auto Farm tab." })

-- ESP
local espL = tabs.ESP:Section({ Side = "Left" })
espL:Header({ Text = "Targets" })
espL:Toggle({ Name = "Killers", Default = false, Callback = function(v) Cfg.EspKillers = v end }, "EspKillers")
espL:Toggle({ Name = "Survivors", Default = false, Callback = function(v) Cfg.EspSurvivors = v end }, "EspSurvivors")
espL:Toggle({ Name = "Generators", Default = false, Callback = function(v) Cfg.EspGens = v end }, "EspGens")
espL:Toggle({ Name = "Items", Default = false, Callback = function(v) Cfg.EspItems = v end }, "EspItems")
espL:Toggle({ Name = "Gears", Default = false, Callback = function(v) Cfg.EspGears = v end }, "EspGears")
espL:Toggle({ Name = "Tracers: Killers" .. (Drawing and "" or " (PC only)"), Default = false, Callback = function(v) Cfg.TracerKillers = v end }, "TracerKillers")
espL:Toggle({ Name = "Tracers: Survivors" .. (Drawing and "" or " (PC only)"), Default = false, Callback = function(v) Cfg.TracerSurvivors = v end }, "TracerSurvivors")
espL:Divider()
espL:Toggle({ Name = "Show Names", Default = true, Callback = function(v) Cfg.EspNames = v end }, "EspNames")
espL:Toggle({ Name = "Show Distance", Default = true, Callback = function(v) Cfg.EspDistance = v end }, "EspDistance")
espL:Toggle({ Name = "Show Health", Default = true, Callback = function(v) Cfg.EspHealth = v end }, "EspHealth")

local espR = tabs.ESP:Section({ Side = "Right" })
espR:Header({ Text = "Colors" })
espR:Colorpicker({ Name = "Killer", Default = Cfg.KillerColor, Callback = function(c) Cfg.KillerColor = c end }, "KillerColor")
espR:Colorpicker({ Name = "Survivor", Default = Cfg.SurvivorColor, Callback = function(c) Cfg.SurvivorColor = c end }, "SurvivorColor")
espR:Colorpicker({ Name = "Generator", Default = Cfg.GenColor, Callback = function(c) Cfg.GenColor = c end }, "GenColor")
espR:Colorpicker({ Name = "Item", Default = Cfg.ItemColor, Callback = function(c) Cfg.ItemColor = c end }, "ItemColor")
espR:Colorpicker({ Name = "Gear", Default = Cfg.GearColor, Callback = function(c) Cfg.GearColor = c end }, "GearColor")

-- Visuals
local themeSec = tabs.Visuals:Section({ Side = "Right" })
themeSec:Header({ Text = "Theme" })
themeSec:Dropdown({ Name = "Menu Theme", Multi = false, Required = true, Options = { "Furina", "Classic" }, Default = 1,
    Callback = function(v) Cfg.Theme = v; pcall(applyTheme) end }, "Theme")
themeSec:Toggle({ Name = "Low Health Alert", Default = true, Callback = function(v) Cfg.LowHpAlert = v end }, "LowHpAlert")

local vis = tabs.Visuals:Section({ Side = "Left" })
vis:Header({ Text = "World" })
vis:Toggle({ Name = "Fullbright", Default = false, Callback = function(v)
    Cfg.Fullbright = v
    if not v and not Cfg.NoFog then restoreLighting() end
end }, "Fullbright")
vis:Toggle({ Name = "No Fog", Default = false, Callback = function(v)
    Cfg.NoFog = v
    if not v and not Cfg.Fullbright then restoreLighting() end
end }, "NoFog")
vis:Header({ Text = "Camera" })
vis:Toggle({ Name = "Custom FOV", Default = false, Callback = function(v) Cfg.FovOn = v end }, "FovOn")
vis:Slider({ Name = "Field Of View", Default = 90, Minimum = 60, Maximum = 120, DisplayMethod = "Value", Precision = 0,
    Callback = function(v) Cfg.Fov = v end }, "Fov")
vis:Toggle({ Name = "Unlock Camera Zoom", Default = false, Callback = function(v) Cfg.ZoomUnlock = v end }, "ZoomUnlock")
vis:Header({ Text = "HUD" })
vis:Toggle({ Name = "Stats Overlay (FPS / ping / gens)", Default = false, Callback = function(v) Cfg.Overlay = v end }, "Overlay")
vis:Toggle({ Name = "Generator Alerts", Default = true, Callback = function(v) Cfg.GenAlerts = v end }, "GenAlerts")

-- Misc
local misc = tabs.Misc:Section({ Side = "Left" })
misc:Header({ Text = "Misc" })
misc:Toggle({ Name = "FPS Boost (low graphics)", Default = false, Callback = function(v)
    Cfg.FpsBoost = v
    setFpsBoost(v)
end }, "FpsBoost")
misc:Button({ Name = "Unlock FPS", Callback = function()
    if setfpscap then setfpscap(999); notify("Misc", "FPS cap removed.") else notify("Misc", "Your executor has no setfpscap.") end
end })
misc:Toggle({ Name = "Auto Rejoin On Disconnect", Default = false, Callback = function(v) Cfg.AutoRejoin = v end }, "AutoRejoin")
misc:Button({ Name = "Server Hop (emptiest server)", Callback = function()
    local ok, info = serverHop(true)
    notify("Server Hop", ok and ("Joining a server with " .. info) or ("Failed: " .. tostring(info)), 4)
end })
misc:Button({ Name = "Server Hop (random server)", Callback = function()
    local ok, info = serverHop(false)
    notify("Server Hop", ok and ("Joining a server with " .. info) or ("Failed: " .. tostring(info)), 4)
end })
misc:Toggle({ Name = "Floating Buttons (mobile)", Default = IS_MOBILE, Callback = function(v)
    Cfg.FloatingButtons = v
    if genv.__FurinaFloating then genv.__FurinaFloating.Enabled = v end
end }, "FloatingButtons")
misc:Button({ Name = "Rejoin Server", Callback = function()
    TeleportSvc:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
end })
misc:Button({ Name = "Unload Hub", Callback = function() unload() end })

----------------------------------------------------------------------
-- Floating touch buttons: "F" opens/closes the menu, the bolt toggles the
-- farm. Both can be dragged anywhere; a drag never counts as a tap.
----------------------------------------------------------------------
do
    local gui = Instance.new("ScreenGui")
    gui.Name = HttpService:GenerateGUID(false)
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.Enabled = Cfg.FloatingButtons
    safeParent(gui)
    genv.__FurinaFloating = gui
    onCleanup(function() gui:Destroy() end)

    local function makeButton(text, pos, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(IS_MOBILE and 56 or 44, IS_MOBILE and 56 or 44)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = pos
        b.BackgroundColor3 = color
        b.BackgroundTransparency = 0.08
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = IS_MOBILE and 24 or 18
        b.AutoButtonColor = true
        b.Parent = gui
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        local stroke = Instance.new("UIStroke", b)
        stroke.Color = Furina.gold
        stroke.Thickness = 2
        local dragging, moved, startIn, startPos = false, false, nil, nil
        connect(b.InputBegan, function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging, moved, startIn, startPos = true, false, i.Position, b.Position
            end
        end)
        connect(UIS.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
                local d = i.Position - startIn
                if d.Magnitude > 10 then moved = true end
                if moved then
                    b.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end
        end)
        connect(UIS.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        return b, function() return moved end
    end

    local menuBtn, menuMoved = makeButton("F", UDim2.new(0, 60, 0.45, 0), Furina.base)
    menuBtn.TextColor3 = Furina.gold
    connect(menuBtn.Activated, function()
        if menuMoved() then return end
        pcall(function() Window:SetState(not Window:GetState()) end)
    end)
    local farmBtn, farmMoved = makeButton("⚡", UDim2.new(0, 60, 0.45, 70), Furina.base)
    connect(farmBtn.Activated, function()
        if farmMoved() then return end
        toggleFarm()
    end)
    task.spawn(function()
        while alive do
            local on = Cfg.FarmSurvivor or Cfg.FarmKiller
            farmBtn.BackgroundColor3 = on and Furina.accent or Furina.base
            task.wait(0.3)
        end
    end)
end

MacLib:SetFolder("FurinaHub")
-- one-time migration of settings saved by the old "Forsaken Hub" name
pcall(function()
    local old, new = "ForsakenHub/settings/autosave.json", "FurinaHub/settings/autosave.json"
    if isfile and isfile(old) and not isfile(new) then writefile(new, readfile(old)) end
end)
tabs.Misc:InsertConfigSection("Right")
tabs.Farm:Select()

----------------------------------------------------------------------
-- Auto save / auto load
--   Restores the last session's settings on start, then watches every
--   setting and saves to FurinaHub/settings/autosave.json ~1s after any
--   change (and once more on unload). A profile you pick as "autoload" in
--   the Config section still wins over the autosave.
----------------------------------------------------------------------
local AUTOSAVE = "autosave"
local loadingConfig = true
local function cfgFingerprint()
    local parts = {}
    for k, v in pairs(Cfg) do
        if typeof(v) == "Color3" then v = v:ToHex() end
        table.insert(parts, k .. "=" .. tostring(v))
    end
    table.sort(parts)
    return table.concat(parts, ";")
end
local function saveNow()
    if loadingConfig then return end
    local ok, err = pcall(function() return MacLib:SaveConfig(AUTOSAVE) end)
    if not ok then warn("[FurinaHub] autosave failed: " .. tostring(err)) end
end
do
    local restored = false
    local auto = MacLib.Folder and (MacLib.Folder .. "/settings/autoload.txt")
    if auto and isfile and isfile(auto) then
        pcall(function() MacLib:LoadAutoLoadConfig() end)
        restored = true
    elseif isfile and isfile(MacLib.Folder .. "/settings/" .. AUTOSAVE .. ".json") then
        local ok, res = pcall(function() return MacLib:LoadConfig(AUTOSAVE) end)
        restored = ok and res == true
    end
    task.delay(1.5, function()
        -- Maclib restores sliders/colours without firing their callbacks,
        -- so copy every restored value straight from the UI elements
        -- (every flag is named after its Cfg key).
        for flag, opt in pairs(MacLib.Options or {}) do
            if Cfg[flag] ~= nil then
                if opt.Class == "Toggle" and opt.State ~= nil then Cfg[flag] = opt.State
                elseif opt.Class == "Slider" and tonumber(opt.Value) then Cfg[flag] = tonumber(opt.Value)
                elseif opt.Class == "Colorpicker" and typeof(opt.Color) == "Color3" then Cfg[flag] = opt.Color
                elseif opt.Class == "Dropdown" and type(opt.Value) == "string" then Cfg[flag] = opt.Value end
            end
        end
        if Cfg.FpsBoost then setFpsBoost(true) end
        if genv.__FurinaFloating then genv.__FurinaFloating.Enabled = Cfg.FloatingButtons end
        loadingConfig = false
        notify("Furina Hub", restored and "Settings restored from your last session." or "Settings will auto-save as you change them.", 4)
    end)
end
task.spawn(function()
    local last = cfgFingerprint()
    local changedAt
    while alive do
        task.wait(0.5)
        if not loadingConfig then
            local fp = cfgFingerprint()
            if fp ~= last then last = fp; changedAt = os.clock() end
            if changedAt and os.clock() - changedAt > 1 then
                changedAt = nil
                saveNow()
            end
        else
            last = cfgFingerprint()
        end
    end
end)
table.insert(cleanups, 1, saveNow) -- runs last on unload: final save
genv.__FurinaMacLib = MacLib
genv.__FurinaStats = Stats

notify("Furina Hub", IS_MOBILE and "Loaded. Tap F for the menu, the bolt toggles farming." or "Loaded. RightControl = menu, F6 = farm, End = panic.", 5)
