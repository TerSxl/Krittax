-- KRITTAX ANDROID DIAGNOSTIC BUILD 1.3 - copy the entire file.
local player=game:GetService("Players").LocalPlayer
assert(player,"Join a game first")
local pg=player:WaitForChild("PlayerGui",10)
assert(pg,"PlayerGui missing")
for _,name in ipairs({"KrittaxTest","KrittaxAndroidTest","KrittaxBootPanel"}) do
    local old=pg:FindFirstChild(name);if old then old:Destroy() end
end
local panel=Instance.new("ScreenGui")
panel.Name="KrittaxBootPanel";panel.IgnoreGuiInset=true;panel.ResetOnSpawn=false;panel.DisplayOrder=10002
local box=Instance.new("TextBox")
box.Size=UDim2.new(0.92,0,0.22,0);box.Position=UDim2.new(0.04,0,0.04,0)
box.BackgroundColor3=Color3.fromRGB(40,20,65);box.TextColor3=Color3.new(1,1,1)
box.TextSize=15;box.TextWrapped=true;box.MultiLine=true;box.ClearTextOnFocus=false
box.Text="KRITTAX 1.3 - loader started";box.Parent=panel;panel.Parent=pg
local function report(message) box.Text="KRITTAX 1.3\n"..tostring(message);print(box.Text) end
local payload=[====[
local report = ...
local function startKrittaxHub()
-- Krittax HUB V1 - Manga Fighting, experimental client build.
-- Attack contract recovered from supplied AttackTargeting bytecode.
-- Gate entry uses an existing ProximityPrompt; no guessed gate remote calls.
-- Run the entire file. No external UI library or HTTP loader is required.
report("1/6 Services")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local player=Players.LocalPlayer
local deadline=os.clock()+15
while not player and os.clock()<deadline do task.wait(0.1);player=Players.LocalPlayer end
assert(player,"LocalPlayer not ready after 15 seconds; join the game and run again")
local playerGui=player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui",15)
assert(playerGui,"PlayerGui not ready after 15 seconds; run again after spawning")
local previousError=playerGui:FindFirstChild("KrittaxStartupError")
if previousError then previousError:Destroy() end
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.KrittaxHub and type(env.KrittaxHub.Destroy) == "function" then
    pcall(env.KrittaxHub.Destroy)
end
report("2/6 Session")
local hub = {}
local gui
env.KrittaxHub = hub
local settings = {Farm=false, Gate=false, Enemy="All", World="All", Method="Tween", Speed=75, Position="Behind", Distance=5, Priority="Farm > Gate"}
hub.Settings = settings
settings.Enemies={All=true}
settings.GateWorlds={All=true};settings.BossWorlds={All=true}
settings.Reequip=true;settings.SummonWorld="Ninja Zone"
local arrival,teamBusy,teamRestore=nil,false,nil
local summonBusy,summonOwned=false,false
local summonStatus="Auto Summon: stopped"
local stopSummon
local summonCancel=false
settings.WorldBoss,settings.GateInterrupt=false,true
local excursion,activeBoss,activeGate,gateStarted=nil,nil,nil,0
settings.AntiAFK, settings.Noclip = false, false
settings.SpeedEnabled, settings.JumpEnabled = false, false
settings.WalkSpeed, settings.JumpPower = 32, 75
local alive, target, commanded, lastAttack, lastGate = true, nil, nil, 0, 0
local connections, gateAttempts = {}, setmetatable({}, {__mode="k"})
local pendingPrompt
local function cancelPrompt()
    if pendingPrompt and pendingPrompt.Parent then pcall(function() pendingPrompt:InputHoldEnd() end) end
    pendingPrompt = nil
end
local status = "Ready - select enemy and enable Autofarm"
-- Optional modules must never block GUI startup.
local realm,zones
local moduleStatus="Optional game data: loading"
local function loadGameData()
    local pending=2
    for _,entry in ipairs({{"WorldRealm","realm"},{"ZoneData","zones"}}) do
        local finished=false
        task.spawn(function()
            local module=RS:FindFirstChild(entry[1])
            if module and module:IsA("ModuleScript") then
                local ok,result=pcall(require,module)
                if alive and ok and type(result)=="table" then
                    if entry[2]=="realm" then realm=result else zones=result end
                end
            end
            finished=true;pending=pending-1
            if pending==0 then moduleStatus="Optional data loaded: "..tostring(realm~=nil).." / "..tostring(zones~=nil) end
        end)
        task.delay(8,function()
            if alive and not finished then moduleStatus=entry[1].." delayed; GUI remains available";warn("[Krittax HUB] "..moduleStatus) end
        end)
    end
end
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end
local function root()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local part = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and part and part:IsA("BasePart") then return part end
end
-- Player modifiers keep independent snapshots so disabling one does not reset another.
local speedSaved, jumpSaved, collisionSaved = {}, {}, {}
local function restoreEntries(saved)
    for instance,properties in pairs(saved) do
        for property,value in pairs(properties) do pcall(function() instance[property]=value end) end
        saved[instance]=nil
    end
end
local function restorePlayer()
    restoreEntries(speedSaved);restoreEntries(jumpSaved);restoreEntries(collisionSaved)
end
local function applyPlayer()
    if not settings.SpeedEnabled then restoreEntries(speedSaved) end
    if not settings.JumpEnabled then restoreEntries(jumpSaved) end
    local useNoclip=settings.Noclip and not (arrival and arrival.reached)
    if not useNoclip then restoreEntries(collisionSaved) end
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then restorePlayer();return end
    if settings.SpeedEnabled then
        if not speedSaved[humanoid] then speedSaved[humanoid]={WalkSpeed=humanoid.WalkSpeed} end
        humanoid.WalkSpeed=math.clamp(tonumber(settings.WalkSpeed) or 32,0,150)
    end
    if settings.JumpEnabled then
        if not jumpSaved[humanoid] then jumpSaved[humanoid]={UseJumpPower=humanoid.UseJumpPower,JumpPower=humanoid.JumpPower} end
        humanoid.UseJumpPower=true
        humanoid.JumpPower=math.clamp(tonumber(settings.JumpPower) or 75,0,200)
    end
    if useNoclip then
        for _,part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if not collisionSaved[part] then collisionSaved[part]={CanCollide=part.CanCollide} end
                part.CanCollide=false
            end
        end
    end
end
local function remote()
    local r = RS:FindFirstChild("AttackCommand")
    if r and r:IsA("RemoteEvent") then return r end
end
local function release()
    local old = commanded
    commanded = nil
    if old and old.Parent then
        local r = remote()
        if r then pcall(function() r:FireServer(old, "Release") end) end
    end
end
local function stop()
    settings.Farm, settings.Gate = false, false
    settings.WorldBoss=false
    arrival=nil
    if teamRestore then teamRestore() end
    if stopSummon then stopSummon() end
    excursion,activeBoss,activeGate=nil,nil,nil
    settings.AntiAFK,settings.Noclip,settings.SpeedEnabled,settings.JumpEnabled=false,false,false,false
    restorePlayer()
    target = nil
    cancelPrompt()
    release()
    status = "Stopped"
end
-- Available before GUI construction, including partial startup failure.
function hub.Destroy()
    if not alive then return end
    alive=false;stop()
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    if gui then pcall(function() gui:Destroy() end) end
    if env.KrittaxHub==hub then env.KrittaxHub=nil end
end
local function body(model)
    local p = model:FindFirstChild("Hitbox") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if p and p:IsA("BasePart") then return p end
end
local function enemyAlive(model)
    if not model:IsA("Model") then return false end
    local h = model:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 or not body(model) then return false end
    if not model:FindFirstChildOfClass("ClickDetector") then return false end
    if realm and type(realm.Same) == "function" then
        local ok, same = pcall(realm.Same, player, model)
        if not ok or not same then return false end
    end
    return true
end
local function zoneOf(model)
    local z = model:GetAttribute("ZoneId") or model:GetAttribute("zoneId")
    if z ~= nil then return tostring(z) end
    if zones and type(zones.ZoneAt) == "function" then
        local p = model:IsA("Model") and body(model)
        if p then
            local ok, result = pcall(zones.ZoneAt, p.Position)
            if ok then
                if type(result) == "table" then return tostring(result.id or "") end
                if type(result) == "string" then return result end
            end
        end
    end
    return ""
end
local function eventWorldMatches(model,key)
    local selected=settings[key]
    local zone=zoneOf(model)
    if zone=="" and model:GetAttribute("WorldBoss")==true then zone=tostring(workspace:GetAttribute("WorldBossZone") or "Default") end
    if zone=="" or zone=="Default" then zone="Ninja Zone" end
    return selected.All==true or selected[zone]==true
end
local function worldMatches(model)
    return settings.World == "All" or zoneOf(model) == settings.World
end
local function validEnemy(model)
    local folder = workspace:FindFirstChild("Enemies")
    return model and folder and model.Parent == folder and enemyAlive(model)
end
local function selectedEnemy(enemy)
    return settings.Enemies.All==true or settings.Enemies[enemy.Name]==true
end
local function chooseWorldBoss(r)
    local folder=workspace:FindFirstChild("Enemies")
    local best,distance=nil,math.huge
    if folder then
        for _,enemy in ipairs(folder:GetChildren()) do
            if enemy:GetAttribute("WorldBoss")==true and enemyAlive(enemy) and eventWorldMatches(enemy,"BossWorlds") then
                local d=(r.Position-body(enemy).Position).Magnitude
                if d<distance then best,distance=enemy,d end
            end
        end
    end
    return best
end
local function chooseEnemy(r, bossName, gateZone)
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then return nil end
    local best, distance = nil, math.huge
    for _, enemy in ipairs(folder:GetChildren()) do
        local matches = bossName and (enemy.Name == bossName or enemy:GetAttribute("EnemyId") == bossName or enemy:GetAttribute("DisplayName") == bossName)
            or (not bossName and selectedEnemy(enemy) and enemy:GetAttribute("WorldBoss")~=true)
        if matches and enemyAlive(enemy) and ((bossName and (not gateZone or zoneOf(enemy)==gateZone)) or (not bossName and worldMatches(enemy))) then
            local d = (r.Position - body(enemy).Position).Magnitude
            if d < distance then best, distance = enemy, d end
        end
    end
    return best
end
local function move(r, destination, dt)
    if settings.Method == "Warp" then
        r.CFrame = destination
    else
        -- Linear interpolation with a bounded step: actual speed in studs/second.
        local d = (r.Position - destination.Position).Magnitude
        local speed = math.clamp(tonumber(settings.Speed) or 75, 50, 100)
        r.CFrame = r.CFrame:Lerp(destination, math.min(1, speed * math.min(dt, 0.1) / math.max(d, 0.001)))
    end
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
end
local function refreshTeam()
    if not settings.Reequip or teamBusy then return end
    local folder=RS:FindFirstChild("GachaRemotes")
    local equip=folder and folder:FindFirstChild("EquipCompanion")
    if not equip or not equip:IsA("RemoteEvent") then status="EquipCompanion missing";return end
    teamBusy=true
    local restored=false
    local function restore()
        if restored then return end
        restored=true
        local ok,err=pcall(function() equip:FireServer("EquipBest") end)
        teamBusy=false;teamRestore=nil
        if not ok then warn("[Krittax] EquipBest failed: "..tostring(err)) end
    end
    teamRestore=restore
    local ok,err=pcall(function() equip:FireServer("UnequipAll") end)
    if not ok then restore();status=tostring(err);return end
    -- Ordered RemoteEvent calls; allow server time to remove the old team.
    task.delay(0.4,restore)
end
local function fight(r,enemy,dt)
    local b=body(enemy)
    if not b then return end
    if not arrival or arrival.enemy~=enemy or arrival.root~=r then
        release()
        local d=settings.Distance
        local offsets={Behind=Vector3.new(0,0,d),Front=Vector3.new(0,0,-d),Above=Vector3.new(0,d,0),Under=Vector3.new(0,-d,0)}
        local pos=b.CFrame:PointToWorldSpace(offsets[settings.Position])
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        local excluded={player.Character,enemy}
        for _,name in ipairs({"Enemies","Companions"}) do local folder=workspace:FindFirstChild(name);if folder then table.insert(excluded,folder) end end
        params.FilterDescendantsInstances=excluded;params.RespectCanCollide=true
        local ground=workspace:Raycast(Vector3.new(pos.X,b.Position.Y+24,pos.Z),Vector3.new(0,-160,0),params)
        local h=player.Character:FindFirstChildOfClass("Humanoid")
        local height=(h and h.HipHeight or 2)+r.Size.Y/2+0.5
        local groundY=ground and ground.Position.Y or (b.Position.Y-height)
        local destination=Vector3.new(pos.X,groundY+height,pos.Z)
        arrival={enemy=enemy,root=r,destination=CFrame.new(destination),reached=false}
    end
    if not arrival.reached then
        move(r,arrival.destination,dt)
        if (r.Position-arrival.destination.Position).Magnitude>2 then status="Moving to "..enemy.Name;return end
        arrival.reached=true
        restoreEntries(collisionSaved)
        refreshTeam()
    end
    -- No CFrame / velocity writes after arrival. Gravity and normal controls resume.
    if teamBusy then status="Re-equipping best team";return end
    local attack=remote()
    if not attack then status="AttackCommand missing";return end
    local range=math.max(0,(tonumber(attack:GetAttribute("MaxDistance")) or 110)-2)
    if (r.Position-b.Position).Magnitude>range then status="Holding position - target out of range";return end
    if commanded~=enemy or os.clock()-lastAttack>=2 then attack:FireServer(enemy);commanded=enemy;lastAttack=os.clock() end
    status="Holding ground: "..enemy.Name
end
local function summonRequest(action)
    if summonBusy then return end
    local remotes=RS:FindFirstChild("GachaRemotes")
    local remote=remotes and remotes:FindFirstChild("AutoSummon")
    if not remote or not remote:IsA("RemoteFunction") then summonStatus="AutoSummon remote missing";return end
    summonBusy=true;summonStatus="Summon: requesting "..action
    local zone=settings.SummonWorld=="Ninja Zone" and "" or settings.SummonWorld
    local count=tonumber(remote:GetAttribute("DefaultCount")) or 10
    task.spawn(function()
        local ok,accepted,message=pcall(function()
            if action=="Stop" then return remote:InvokeServer("Stop") end
            return remote:InvokeServer("Start",{zoneId=zone,count=count})
        end)
        summonBusy=false
        if not ok then summonStatus="Summon error: "..tostring(accepted)
        elseif accepted==false then summonStatus="Summon rejected: "..tostring(message)
        else
            summonOwned=action=="Start"
            summonStatus=action=="Start" and "Summon requested: "..settings.SummonWorld or "Summon stopped"
        end
        if summonOwned and (not alive or summonCancel) then stopSummon() end
    end)
    task.delay(12,function() if summonBusy then summonStatus="Summon awaiting server; no duplicate request" end end)
end
stopSummon=function()
    summonCancel=true
    if summonOwned and not summonBusy then summonRequest("Stop") end
end
local function gatePosition(gate)
    local cf = gate:GetAttribute("GateCFrame")
    if typeof(cf) == "CFrame" then return cf.Position end
    return gate:GetPivot().Position
end
local function gateAlive(gate)
    if not gate or gate.Parent~=workspace or not eventWorldMatches(gate,"GateWorlds") then return false end
    local state=gate:GetAttribute("State")
    local expiry=tonumber(gate:GetAttribute("ExpiresAt"))
    return (state=="Open" or state=="Active") and (not expiry or expiry>workspace:GetServerTimeNow())
end
local function chooseGate(r)
    local best, distance = nil, math.huge
    -- WorldGateController watches direct children of Workspace.
    for _, gate in ipairs(workspace:GetChildren()) do
        if gate.Name == "WorldGate" and gate:IsA("Model") and eventWorldMatches(gate,"GateWorlds") then
            local state = gate:GetAttribute("State")
            local expiry = tonumber(gate:GetAttribute("ExpiresAt"))
            if (state == "Open" or state == "Active") and (not expiry or expiry > workspace:GetServerTimeNow()) then
                local attempt = gateAttempts[gate]
                if not attempt or os.clock() - attempt > 15 then
                    local d = (r.Position - gatePosition(gate)).Magnitude
                    if d < distance then best, distance = gate, d end
                end
            end
        end
    end
    return best
end
local function doGate(r, gate, dt)
    if gate:GetAttribute("State") == "Active" then
        local bossName = gate:GetAttribute("BossName")
        local boss = type(bossName) == "string" and chooseEnemy(r, bossName, zoneOf(gate))
        if boss then fight(r, boss, dt) else
            release()
            status = "Gate active - waiting for boss: " .. tostring(bossName or "unknown")
        end
        return
    end
    release()
    local prompt = gate:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then
        status = "Gate has no ProximityPrompt - entry needs live mapping"
        gateAttempts[gate] = os.clock()
        return
    end
    if not prompt.Enabled then status = "Waiting for Gate prompt" return end
    local parent = prompt.Parent
    local position = parent:IsA("Attachment") and parent.WorldPosition
        or (parent:IsA("BasePart") and parent.Position) or gatePosition(gate)
    local distance = (r.Position - position).Magnitude
    if distance > math.max(1, prompt.MaxActivationDistance - 1) then
        local delta = r.Position - position
        local offset = delta.Magnitude > 0 and delta.Unit * 2 or Vector3.new(0,0,2)
        move(r, CFrame.new(position + offset), dt)
        status = "Moving to Gate: " .. zoneOf(gate)
        return
    end
    if pendingPrompt or os.clock() - lastGate < 3 then return end
    lastGate = os.clock()
    if type(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
        status = "Gate entry requested - awaiting server"
    else
        pendingPrompt = prompt
        prompt:InputHoldBegin()
        task.delay(prompt.HoldDuration + 0.15, function()
            if pendingPrompt == prompt then
                if prompt.Parent then pcall(function() prompt:InputHoldEnd() end) end
                pendingPrompt = nil
            end
        end)
        status = "Holding Gate prompt - awaiting server"
    end
    gateAttempts[gate] = os.clock()
end
-- Compact sidebar UI inspired by the user's reference.
report("3/6 UI helpers")
local function make(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local purple=Color3.fromRGB(151,37,232)
local muted=Color3.fromRGB(129,126,137)
local gray=Color3.fromRGB(25,25,28)
report("4/6 Window")
gui=make("ScreenGui",playerGui,{Name="KrittaxHubV1",ResetOnSpawn=false,DisplayOrder=10001,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local window=make("Frame",gui,{AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(660,430),Position=UDim2.fromScale(0.5,0.5),BackgroundColor3=Color3.fromRGB(13,13,15),BorderSizePixel=0})
local function corner(obj,r) make("UICorner",obj,{CornerRadius=UDim.new(0,r or 6)}) end
local function stroke(obj) make("UIStroke",obj,{Color=Color3.fromRGB(38,38,43),Thickness=1}) end
corner(window,9);stroke(window)
local scale=make("UIScale",window,{Scale=1})
local function resize()
    local camera=workspace.CurrentCamera
    if camera then scale.Scale=math.min(1,math.max(0.2,math.min((camera.ViewportSize.X-24)/660,(camera.ViewportSize.Y-40)/430))) end
end
resize()
local function text(parent,value,pos,size,fontSize)
    return make("TextLabel",parent,{Text=value,Position=pos,Size=size,TextSize=fontSize or 11,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(215,213,221),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left})
end
local function button(parent,label,pos,size,fn)
    local b=make("TextButton",parent,{Text=label,Position=pos,Size=size,TextColor3=Color3.fromRGB(211,207,220),TextSize=11,Font=Enum.Font.Gotham,BackgroundColor3=gray,BorderSizePixel=0,AutoButtonColor=true})
    corner(b,5);connect(b.Activated,fn);return b
end
local sidebar=make("Frame",window,{Size=UDim2.new(0,151,1,0),BackgroundColor3=Color3.fromRGB(16,16,18),BorderSizePixel=0})
corner(sidebar,9)
make("Frame",window,{Position=UDim2.fromOffset(151,0),Size=UDim2.new(0,1,1,0),BackgroundColor3=Color3.fromRGB(31,31,35),BorderSizePixel=0})
local brand=text(sidebar,"Krittax",UDim2.fromOffset(16,13),UDim2.fromOffset(122,24),17);brand.Font=Enum.Font.GothamBold
text(sidebar,"HUB / MANGA FIGHTING",UDim2.fromOffset(17,37),UDim2.fromOffset(130,16),8).TextColor3=muted
local title=text(window,"Autofarm",UDim2.fromOffset(168,12),UDim2.fromOffset(395,24),16);title.Font=Enum.Font.GothamBold;title.Active=true
local subtitle=text(window,"Combat and farming features",UDim2.fromOffset(168,36),UDim2.fromOffset(390,18),10);subtitle.TextColor3=muted
make("Frame",window,{Position=UDim2.fromOffset(168,60),Size=UDim2.fromOffset(476,1),BackgroundColor3=Color3.fromRGB(35,35,39),BorderSizePixel=0})
make("Frame",window,{Position=UDim2.fromOffset(168,60),Size=UDim2.fromOffset(146,2),BackgroundColor3=purple,BorderSizePixel=0})
local refreshUI
local reopen=button(gui,"K HUB",UDim2.fromOffset(14,80),UDim2.fromOffset(68,30),function() window.Visible=not window.Visible end);reopen.BackgroundColor3=purple
button(window,"-",UDim2.fromOffset(600,15),UDim2.fromOffset(20,22),function() window.Visible=false end)
button(window,"x",UDim2.fromOffset(625,15),UDim2.fromOffset(20,22),function() hub.Destroy() end)
local pages,nav,updates={},{},{}
local popup
local function closePopup() if popup then popup:Destroy();popup=nil end end
local antiAFKPulse
local function changed() target=nil;arrival=nil;cancelPrompt();release();applyPlayer();refreshUI();if settings.AntiAFK and antiAFKPulse then antiAFKPulse() end end
local activePage="Autofarm"
local function showPage(name)
    closePopup();activePage=name
    for key,p in pairs(pages) do p.Visible=key==name end
    for key,b in pairs(nav) do b.BackgroundTransparency=key==name and 0 or 1;b.TextColor3=key==name and Color3.new(1,1,1) or muted end
    title.Text=name
    local descriptions={Autofarm="Combat and farming features",Movement="Follow position and travel controls",Gate="World gate and priority settings",Settings="Session controls and shortcuts"}
    subtitle.Text=descriptions[name]
end
local function category(label,y)
    text(sidebar,label,UDim2.fromOffset(18,y),UDim2.fromOffset(120,20),10)
    make("Frame",sidebar,{Position=UDim2.fromOffset(15,y+25),Size=UDim2.fromOffset(120,1),BackgroundColor3=Color3.fromRGB(33,33,37),BorderSizePixel=0})
end
category("Main",72);category("Player",159);category("Misc",245)
for _,spec in ipairs({{"Autofarm",105,"  +   Autofarm"},{"Movement",192,"  >   Movement"},{"Gate",278,"  #   World Gate"},{"Settings",312,"  :   Settings"}}) do
    local name=spec[1]
    pages[name]=make("Frame",window,{Position=UDim2.fromOffset(168,74),Size=UDim2.fromOffset(476,306),BackgroundTransparency=1,Visible=false})
    local b=button(sidebar,spec[3],UDim2.fromOffset(15,spec[2]),UDim2.fromOffset(121,27),function() showPage(name) end)
    b.TextXAlignment=Enum.TextXAlignment.Left;b.BackgroundColor3=purple;nav[name]=b
end
text(sidebar,"V1 / CUSTOM UI",UDim2.fromOffset(17,389),UDim2.fromOffset(125,17),9).TextColor3=muted
local function card(page,label,x,y,h)
    local c=make("Frame",pages[page],{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(232,h),BackgroundColor3=Color3.fromRGB(17,17,19),BorderSizePixel=0})
    corner(c,7);stroke(c)
    local head=text(c,label,UDim2.fromOffset(10,7),UDim2.fromOffset(212,21),11);head.Font=Enum.Font.GothamMedium
    make("Frame",c,{Position=UDim2.fromOffset(10,32),Size=UDim2.fromOffset(212,1),BackgroundColor3=Color3.fromRGB(32,32,36),BorderSizePixel=0})
    return c
end
local function toggle(parent,label,key,y)
    text(parent,label,UDim2.fromOffset(10,y),UDim2.fromOffset(163,25),10).TextColor3=muted
    local b=button(parent,"",UDim2.fromOffset(194,y+5),UDim2.fromOffset(27,15),function() settings[key]=not settings[key];changed() end)
    corner(b,8)
    local knob=make("Frame",b,{Size=UDim2.fromOffset(11,11),Position=UDim2.fromOffset(2,2),BackgroundColor3=Color3.fromRGB(224,221,231),BorderSizePixel=0});corner(knob,8)
    table.insert(updates,function() b.BackgroundColor3=settings[key] and purple or Color3.fromRGB(52,52,57);knob.Position=UDim2.fromOffset(settings[key] and 14 or 2,2) end)
end
local function choices(key)
    local values,seen={"All"},{All=true}
    local function add(v) if type(v)=="string" and v~="" and not seen[v] then seen[v]=true;table.insert(values,v) end end
    if key=="Enemy" then
        for name,enabled in pairs(settings.Enemies) do if enabled then add(name) end end
        local folder=workspace:FindFirstChild("Enemies")
        if folder then for _,m in ipairs(folder:GetChildren()) do if m:IsA("Model") then add(m.Name) end end end
    else
        add("Ninja Zone")
        for _,id in ipairs({"PirateZone","JujutsuZone","HXHZone","GrimoreZone","SinsZone"}) do add(id) end
        if key=="SummonWorld" then values={"Ninja Zone"};seen={All=true,["Ninja Zone"]=true};for _,id in ipairs({"PirateZone","JujutsuZone","HXHZone","GrimoreZone","SinsZone"}) do add(id) end end
        if zones and type(zones.Zones)=="table" then for _,z in pairs(zones.Zones) do if type(z)=="table" then add(z.id) end end end
        for _,m in ipairs(workspace:GetChildren()) do if m.Name=="WorldGate" then add(zoneOf(m)) end end
    end
    table.sort(values,function(a,b) if a=="All" then return b~="All" elseif b=="All" then return false else return a<b end end)
    return values
end
local function picker(parent,label,key,y,options)
    local multiKey=key=="Enemy" and "Enemies" or ((key=="GateWorlds" or key=="BossWorlds") and key or nil)
    text(parent,label,UDim2.fromOffset(10,y),UDim2.fromOffset(100,26),10).TextColor3=muted
    local b
    b=button(parent,"",UDim2.fromOffset(112,y+3),UDim2.fromOffset(109,21),function()
        closePopup()
        popup=make("Frame",window,{Position=UDim2.fromOffset(210,85),Size=UDim2.fromOffset(360,280),BackgroundColor3=Color3.fromRGB(20,19,24),BorderSizePixel=0,ZIndex=20});corner(popup,7);stroke(popup)
        local header=text(popup,label,UDim2.fromOffset(12,7),UDim2.fromOffset(300,25),13);header.ZIndex=21
        local exitButton=button(popup,"x",UDim2.fromOffset(326,9),UDim2.fromOffset(24,23),closePopup);exitButton.ZIndex=21
        local list=make("ScrollingFrame",popup,{Position=UDim2.fromOffset(10,42),Size=UDim2.fromOffset(340,228),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollBarImageColor3=purple,ZIndex=21})
        make("UIListLayout",list,{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder})
        local selectionButtons={}
        local function updateSelection()
            for name,item in pairs(selectionButtons) do
                local enabled=settings[multiKey][name]==true
                item.Text=(enabled and "[x]  " or "[ ]  ")..name
                item.BackgroundColor3=enabled and purple or gray
            end
        end
        for i,v in ipairs(options or choices(key)) do
            local item=button(list,v,UDim2.new(),UDim2.new(1,-8,0,29),function()
                if multiKey then
                    if v=="All" then settings[multiKey]={All=not settings[multiKey].All}
                    else settings[multiKey].All=nil;settings[multiKey][v]=not settings[multiKey][v] end
                    updateSelection();changed()
                else settings[key]=v;closePopup();changed() end
            end)
            item.ZIndex=22;item.LayoutOrder=i
            if multiKey then selectionButtons[v]=item
            elseif settings[key]==v then item.BackgroundColor3=purple end
        end
        if multiKey then header.Text=label.." - select multiple";updateSelection() end
    end)
    stroke(b);b.TextSize=9;b.TextTruncate=Enum.TextTruncate.AtEnd
    table.insert(updates,function()
        if multiKey then
            local count=0
            for name,enabled in pairs(settings[multiKey]) do if name~="All" and enabled then count=count+1 end end
            b.Text=settings[multiKey].All and "All  v" or (count==0 and "None selected  v" or tostring(count).." selected  v")
        else b.Text=tostring(settings[key]).."  v" end
    end)
end
local sliderDrag
local function slider(parent,label,key,min,max,y,suffix)
    text(parent,label,UDim2.fromOffset(10,y),UDim2.fromOffset(132,19),10).TextColor3=muted
    local value=make("TextBox",parent,{Position=UDim2.fromOffset(146,y),Size=UDim2.fromOffset(75,19),BackgroundTransparency=1,TextColor3=muted,Font=Enum.Font.Gotham,TextSize=9,TextXAlignment=Enum.TextXAlignment.Right,ClearTextOnFocus=false,Text=""})
    local track=make("Frame",parent,{Position=UDim2.fromOffset(10,y+25),Size=UDim2.fromOffset(211,5),BackgroundColor3=Color3.fromRGB(42,40,47),BorderSizePixel=0});corner(track,4)
    local fill=make("Frame",track,{Size=UDim2.new(),BackgroundColor3=purple,BorderSizePixel=0});corner(fill,4)
    local hit=make("TextButton",track,{Position=UDim2.fromOffset(0,-8),Size=UDim2.new(1,0,0,23),Text="",BackgroundTransparency=1,BorderSizePixel=0})
    local function setAt(x) settings[key]=math.floor(min+math.clamp((x-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)*(max-min)+0.5);refreshUI() end
    connect(hit.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then sliderDrag={input=input,setAt=setAt};setAt(input.Position.X) end
    end)
    connect(value.FocusLost,function() settings[key]=math.clamp(tonumber(value.Text:match("[%d.]+")) or settings[key],min,max);refreshUI() end)
    table.insert(updates,function() fill.Size=UDim2.fromScale((settings[key]-min)/(max-min),1);if not value:IsFocused() then value.Text=tostring(settings[key])..(suffix or "") end end)
end
connect(Input.InputChanged,function(input)
    if sliderDrag and (input==sliderDrag.input or input.UserInputType==Enum.UserInputType.MouseMovement) then sliderDrag.setAt(input.Position.X) end
end)
connect(Input.InputEnded,function(input) if sliderDrag and (input==sliderDrag.input or input.UserInputType==Enum.UserInputType.MouseButton1) then sliderDrag=nil end end)
report("5/6 Controls")
local farm=card("Autofarm","+  Autofarm",0,0,143)
slider(farm,"Tween speed","Speed",50,100,39," / 100")
toggle(farm,"Enable autofarm","Farm",78)
picker(farm,"Target enemy","Enemy",108)
local method=card("Autofarm",">  Farm Method",0,155,143)
picker(method,"Method","Method",39,{"Tween","Warp"})
picker(method,"Position","Position",68,{"Behind","Above","Front","Under"})
slider(method,"Distance","Distance",2,20,103," studs")
local gate=card("Autofarm","#  World Events",244,0,153)
toggle(gate,"Auto gate","Gate",39)
toggle(gate,"Interrupt farm for Gate","GateInterrupt",65)
toggle(gate,"Auto World Boss","WorldBoss",91)
picker(gate,"Gate worlds","GateWorlds",119)
local priority=card("Autofarm",":  Settings",244,165,133)
picker(priority,"Task priority","Priority",39,{"Farm > Gate","Gate > Farm"})
local hint=text(priority,"Boss first. Gate interrupts when ON.\nReturn to farm after events.\nPriority applies when interrupt is OFF.",UDim2.fromOffset(11,75),UDim2.fromOffset(210,50),10);hint.TextColor3=muted;hint.TextYAlignment=Enum.TextYAlignment.Top;hint.TextWrapped=true
local travel=card("Movement",">  Movement",0,0,192)
picker(travel,"Method","Method",39,{"Tween","Warp"})
slider(travel,"Tween speed","Speed",50,100,77," / 100")
picker(travel,"Position","Position",121,{"Behind","Above","Front","Under"})
slider(travel,"Distance","Distance",2,20,151," studs")
local modifiers=card("Movement",":  Player",244,0,298)
toggle(modifiers,"Custom walk speed","SpeedEnabled",39)
slider(modifiers,"Walk speed","WalkSpeed",0,150,71," / 150")
toggle(modifiers,"Custom jump power","JumpEnabled",114)
slider(modifiers,"Jump power","JumpPower",0,200,146," / 200")
toggle(modifiers,"Noclip","Noclip",190)
toggle(modifiers,"Anti-AFK","AntiAFK",222)
local note=text(modifiers,"Player only / all switches start OFF",UDim2.fromOffset(10,263),UDim2.fromOffset(212,20),9);note.TextColor3=muted
local gatePage=card("Gate","#  World Events",0,0,260)
toggle(gatePage,"Auto gate","Gate",39);toggle(gatePage,"Interrupt farm for Gate","GateInterrupt",69);toggle(gatePage,"Auto World Boss","WorldBoss",99)
picker(gatePage,"Gate worlds","GateWorlds",135);picker(gatePage,"Boss worlds","BossWorlds",169);picker(gatePage,"Priority","Priority",207,{"Farm > Gate","Gate > Farm"})
local teamCard=card("Movement","+  Team on arrival",0,204,94)
toggle(teamCard,"Unequip / Equip Best","Reequip",39)
local summonCard=card("Gate","+  Auto Summon",244,0,298)
picker(summonCard,"Summon world","SummonWorld",39)
button(summonCard,"Start auto summon",UDim2.fromOffset(10,80),UDim2.fromOffset(212,28),function() summonCancel=false;summonRequest("Start") end)
button(summonCard,"Stop auto summon",UDim2.fromOffset(10,115),UDim2.fromOffset(212,28),function() summonCancel=true;summonRequest("Stop") end)
local summonLabel=text(summonCard,summonStatus,UDim2.fromOffset(10,155),UDim2.fromOffset(212,66),10);summonLabel.TextWrapped=true
local costNote=text(summonCard,"Uses game currency. Server rules and existing Auto Sell settings apply.",UDim2.fromOffset(10,234),UDim2.fromOffset(212,52),10);costNote.TextWrapped=true
local session=card("Settings",":  Session",0,0,153)
button(session,"Stop all",UDim2.fromOffset(11,43),UDim2.fromOffset(210,30),function() stop();refreshUI() end)
button(session,"Hide window",UDim2.fromOffset(11,80),UDim2.fromOffset(210,25),function() window.Visible=false end)
button(session,"Unload HUB",UDim2.fromOffset(11,112),UDim2.fromOffset(210,25),function() hub.Destroy() end)
local afkCard=card("Settings",":  Anti-AFK diagnostics",0,165,133)
local afkLabel=text(afkCard,"Anti-AFK: OFF",UDim2.fromOffset(10,38),UDim2.fromOffset(212,47),9)
afkLabel.TextWrapped=true;afkLabel.TextYAlignment=Enum.TextYAlignment.Top
button(afkCard,"Enable + test now",UDim2.fromOffset(10,96),UDim2.fromOffset(212,25),function() settings.AntiAFK=true;refreshUI();if antiAFKPulse then antiAFKPulse(true) end end)
local keys=card("Settings",":  Shortcuts",244,0,153)
local kt=text(keys,"Right Ctrl    Show / hide\nEnd             Stop all\nK HUB         Reopen window\n\nDrag the page title to move.",UDim2.fromOffset(11,43),UDim2.fromOffset(208,99),10);kt.TextColor3=muted;kt.TextYAlignment=Enum.TextYAlignment.Top
make("Frame",window,{Position=UDim2.fromOffset(168,388),Size=UDim2.fromOffset(476,1),BackgroundColor3=Color3.fromRGB(32,32,36),BorderSizePixel=0})
local statusLabel=text(window,status,UDim2.fromOffset(168,393),UDim2.fromOffset(390,29),9);statusLabel.TextColor3=muted;statusLabel.TextWrapped=true
local stopButton=button(window,"Stop",UDim2.fromOffset(592,396),UDim2.fromOffset(52,24),function() stop();refreshUI() end);stopButton.TextColor3=Color3.fromRGB(215,152,178)
refreshUI=function() for _,update in ipairs(updates) do update() end end
report("6/6 Events")
refreshUI();showPage(activePage)

local dragging,dragStart,startPosition,dragTouch
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true;dragStart=input.Position;startPosition=window.Position;dragTouch=input
    end
end)
connect(Input.InputChanged,function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input==dragTouch) then
        local delta=input.Position-dragStart
        window.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,startPosition.Y.Scale,startPosition.Y.Offset+delta.Y)
    end
end)
connect(Input.InputEnded,function(input)
    if input==dragTouch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
connect(Input.InputBegan,function(input,processed)
    if processed or Input:GetFocusedTextBox() then return end
    if input.KeyCode==Enum.KeyCode.RightControl then window.Visible=not window.Visible
    elseif input.KeyCode==Enum.KeyCode.End then stop();refreshUI() end
end)
connect(player.CharacterRemoving,function() target=nil;arrival=nil;excursion=nil;activeBoss=nil;activeGate=nil;cancelPrompt();release();restorePlayer() end)
connect(Run.Stepped,function()
    if not alive then return end
    local ok,err=pcall(applyPlayer)
    if not ok then
        settings.SpeedEnabled,settings.JumpEnabled,settings.Noclip=false,false,false
        restorePlayer();status="Player controls stopped: "..tostring(err);refreshUI()
    end
end)
local lastIdleInput=-math.huge
local afkBusy=false
local afkRelease
local afkStatus="Anti-AFK: OFF"
local function releaseAFK()
    if afkRelease then pcall(afkRelease);afkRelease=nil end
    afkBusy=false
end
antiAFKPulse=function(force)
    if not alive or not settings.AntiAFK or afkBusy or (not force and os.clock()-lastIdleInput<30) then return end
    lastIdleInput=os.clock();afkBusy=true
    local camera=workspace.CurrentCamera
    local cf=camera and camera.CFrame or CFrame.new()
    local ok,err=pcall(function()
        local vu=game:GetService("VirtualUser")
        afkRelease=function() vu:Button2Up(Vector2.new(0,0),cf) end
        vu:Button2Down(Vector2.new(0,0),cf)
    end)
    local method="VirtualUser"
    if not ok then
        releaseAFK();afkBusy=true;method="VirtualInputManager"
        ok,err=pcall(function()
            local vim=game:GetService("VirtualInputManager")
            afkRelease=function() vim:SendKeyEvent(false,Enum.KeyCode.RightShift,false,game) end
            vim:SendKeyEvent(true,Enum.KeyCode.RightShift,false,game)
        end)
    end
    if not ok then
        releaseAFK();settings.AntiAFK=false
        afkStatus="Anti-AFK blocked: "..tostring(err)
        warn("[Krittax HUB] "..afkStatus);refreshUI();return
    end
    afkStatus="Anti-AFK: input sent via "..method.." (not verified)"
    task.delay(0.1,releaseAFK)
end
connect(player.Idled,function() antiAFKPulse() end)
local afkTimer=0
connect(Run.Heartbeat,function(dt)
    if not alive then return end
    if not settings.AntiAFK then
        if afkBusy then releaseAFK() end
        afkTimer=0
    else
        afkTimer=afkTimer+dt
        if afkTimer>=60 then afkTimer=0;antiAFKPulse() end
    end
    afkLabel.Text=settings.AntiAFK and afkStatus or (afkStatus:find("blocked",1,true) and afkStatus or "Anti-AFK: OFF")
end)
function hub.Destroy()
    if not alive then return end
    alive=false;stop();releaseAFK()
    if pendingPrompt and pendingPrompt.Parent then pcall(function() pendingPrompt:InputHoldEnd() end) end
    pendingPrompt=nil
    for _,c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
    if env.KrittaxHub==hub then env.KrittaxHub=nil end
end
local accumulator,uiTime=0,0
connect(Run.Heartbeat,function(dt)
    if not alive then return end
    uiTime=uiTime+dt;accumulator=accumulator+dt
    if uiTime>=0.3 then uiTime=0;statusLabel.Text=status;summonLabel.Text=summonStatus;resize() end
    if accumulator<0.05 then return end
    local elapsed=accumulator;accumulator=0
    local ok,err=pcall(function()
        if not settings.Farm and not settings.Gate and not settings.WorldBoss then
            excursion,activeBoss,activeGate=nil,nil,nil;release();return
        end
        local r=root()
        if not r then target=nil;release();status="Waiting for respawn";return end
        local function beginEvent()
            if settings.Farm and not excursion then
                excursion={root=r,position=r.CFrame,target=target,started=os.clock()}
            end
            if excursion then excursion.returnStarted=nil end
            target=nil
        end
        if not settings.WorldBoss or not validEnemy(activeBoss) or not eventWorldMatches(activeBoss,"BossWorlds") then activeBoss=nil end
        if settings.WorldBoss and not activeBoss then activeBoss=chooseWorldBoss(r) end
        if activeBoss then
            beginEvent();cancelPrompt()
            if activeGate then gateStarted=os.clock() end
            fight(r,activeBoss,elapsed)
            status="World Boss: "..activeBoss.Name
            return
        end
        if not settings.Gate or not gateAlive(activeGate) then
            if activeGate then cancelPrompt();release() end
            activeGate=nil
        end
        local gate=settings.Gate and (activeGate or chooseGate(r))
        if settings.Farm then
            if not validEnemy(target) or not worldMatches(target) or not selectedEnemy(target) or target:GetAttribute("WorldBoss")==true then
                target=chooseEnemy(r)
            end
        else target=nil end
        local wantsGate=gate and (activeGate~=nil or settings.GateInterrupt or settings.Priority=="Gate > Farm" or not target)
        if wantsGate then
            if activeGate~=gate then activeGate=gate;gateStarted=os.clock();release();cancelPrompt() end
            beginEvent()
            local gateState=gate:GetAttribute("State")
            local bossName=gate:GetAttribute("BossName")
            local boss=gateState=="Active" and type(bossName)=="string" and chooseEnemy(r,bossName,zoneOf(gate))
            if boss then gateStarted=os.clock() end
            local prompt=gate:FindFirstChildWhichIsA("ProximityPrompt",true)
            if (gateState=="Open" and not prompt) or os.clock()-gateStarted>90 then
                gateAttempts[gate]=os.clock();activeGate=nil;cancelPrompt();release()
                status="Gate unavailable - returning to farm"
            else
                doGate(r,gate,elapsed)
                return
            end
        end
        if excursion then
            release();cancelPrompt()
            if not settings.Farm or excursion.root~=r then excursion=nil
            elseif (r.Position-excursion.position.Position).Magnitude>3 then
                -- Bound the return attempt if the server refuses client movement.
                excursion.returnStarted=excursion.returnStarted or os.clock()
                if os.clock()-excursion.returnStarted<45 then
                    move(r,excursion.position,elapsed);status="Returning to farm position";return
                end
                excursion=nil
            else
                local previous=excursion.target
                if validEnemy(previous) and selectedEnemy(previous) and worldMatches(previous) then target=previous end
                excursion=nil
            end
        end
        if settings.Farm and target then fight(r,target,elapsed);return end
        release();status="Waiting for selected enemies / World Boss / Gate"
    end)
    if not ok then stop();status="Stopped: "..tostring(err);warn("[Krittax HUB] "..tostring(err));refreshUI() end
end)
task.defer(loadGameData)
print("[Krittax HUB V1.1] Loaded. Autofarm and Gate are OFF. PlaceId="..tostring(game.PlaceId))


end
startKrittaxHub()

]====]
-- END OF PAYLOAD: KRITTAX_ANDROID_13_COMPLETE
report("Compiling full script...")
if type(loadstring)~="function" then report("ERROR: loadstring is unavailable");return end
local compiled,fn,compileError=pcall(loadstring,payload,"KrittaxAndroid13")
if not compiled or type(fn)~="function" then report("COMPILE ERROR: "..tostring(compileError or fn));return end
local ok,err=pcall(fn,report)
if not ok then
    report("STARTUP ERROR - copy this text:\n"..tostring(err))
else
    report("GUI loaded. Closing this panel in 3 seconds.")
    task.delay(3,function()panel:Destroy()end)
end
-- KRITTAX_ANDROID_13_END
