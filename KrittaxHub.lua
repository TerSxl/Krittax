-- Krittax HUB V1 - Manga Fighting, experimental client build.
-- Attack contract recovered from supplied AttackTargeting bytecode.
-- Gate entry uses an existing ProximityPrompt; no guessed gate remote calls.
-- Run the entire file. No external UI library or HTTP loader is required.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "Run this on the client")
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.KrittaxHub and type(env.KrittaxHub.Destroy) == "function" then
    pcall(env.KrittaxHub.Destroy)
end
local hub = {}
env.KrittaxHub = hub
local settings = {Farm=false, Gate=false, Enemy="All", World="All", Method="Tween", Speed=75, Position="Behind", Distance=5, Priority="Farm > Gate"}
hub.Settings = settings
local alive, target, commanded, lastAttack, lastGate = true, nil, nil, 0, 0
local connections, gateAttempts = {}, setmetatable({}, {__mode="k"})
local pendingPrompt
local function cancelPrompt()
    if pendingPrompt and pendingPrompt.Parent then pcall(function() pendingPrompt:InputHoldEnd() end) end
    pendingPrompt = nil
end
local status = "Ready - select enemy and enable Autofarm"
local realm, zones
for _, entry in ipairs({{"WorldRealm", "realm"}, {"ZoneData", "zones"}}) do
    local module = RS:FindFirstChild(entry[1])
    if module and module:IsA("ModuleScript") then
        local ok, result = pcall(require, module)
        if ok and type(result) == "table" then
            if entry[2] == "realm" then realm = result else zones = result end
        end
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
    target = nil
    cancelPrompt()
    release()
    status = "Stopped"
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
local function worldMatches(model)
    return settings.World == "All" or zoneOf(model) == settings.World
end
local function validEnemy(model)
    local folder = workspace:FindFirstChild("Enemies")
    return model and folder and model.Parent == folder and enemyAlive(model)
end
local function chooseEnemy(r, bossName)
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then return nil end
    local best, distance = nil, math.huge
    for _, enemy in ipairs(folder:GetChildren()) do
        local matches = bossName and (enemy.Name == bossName or enemy:GetAttribute("EnemyId") == bossName or enemy:GetAttribute("DisplayName") == bossName)
            or (not bossName and (settings.Enemy == "All" or enemy.Name == settings.Enemy))
        if matches and enemyAlive(enemy) and worldMatches(enemy) then
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
local function fight(r, enemy, dt)
    local b = body(enemy)
    if not b then return end
    local d = settings.Distance
    local offsets = {Behind=Vector3.new(0,0,d), Front=Vector3.new(0,0,-d), Above=Vector3.new(0,d,0), Under=Vector3.new(0,-d,0)}
    local pos = b.CFrame:PointToWorldSpace(offsets[settings.Position])
    local look = CFrame.lookAt(pos, b.Position, (settings.Position == "Above" or settings.Position == "Under") and b.CFrame.LookVector or Vector3.yAxis)
    move(r, look, dt)
    local attack = remote()
    if not attack then status = "Missing ReplicatedStorage.AttackCommand" return end
    local range = math.max(0, (tonumber(attack:GetAttribute("MaxDistance")) or 110) - 2)
    if (r.Position - b.Position).Magnitude > range then status = "Moving to " .. enemy.Name return end
    -- Reassert slowly, without the game's click-to-toggle Release behavior.
    if commanded ~= enemy or os.clock() - lastAttack >= 2 then
        if commanded ~= enemy then release() end
        attack:FireServer(enemy)
        commanded, lastAttack = enemy, os.clock()
    end
    status = "Farming: " .. enemy.Name
end
local function gatePosition(gate)
    local cf = gate:GetAttribute("GateCFrame")
    if typeof(cf) == "CFrame" then return cf.Position end
    return gate:GetPivot().Position
end
local function chooseGate(r)
    local best, distance = nil, math.huge
    -- WorldGateController watches direct children of Workspace.
    for _, gate in ipairs(workspace:GetChildren()) do
        if gate.Name == "WorldGate" and gate:IsA("Model") and worldMatches(gate) then
            local state = gate:GetAttribute("State")
            local expiry = tonumber(gate:GetAttribute("ExpiresAt"))
            if (state == "Open" or state == "Active") and (not expiry or expiry > workspace:GetServerTimeNow()) then
                local attempt = gateAttempts[gate]
                if state == "Active" or not attempt or os.clock() - attempt > 15 then
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
        local boss = type(bossName) == "string" and chooseEnemy(r, bossName)
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
-- UI: compact black/purple layout inspired by the supplied reference.
local function make(class, parent, props)
    local object = Instance.new(class)
    for k,v in pairs(props or {}) do object[k]=v end
    object.Parent = parent
    return object
end
local purple = Color3.fromRGB(151,50,245)
local gray = Color3.fromRGB(34,34,40)
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name="KrittaxHubV1", ResetOnSpawn=false, DisplayOrder=90, ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local window = make("Frame", gui, {Size=UDim2.fromOffset(570,440), Position=UDim2.new(0.5,-285,0.5,-220), BackgroundColor3=Color3.fromRGB(17,17,20), BorderSizePixel=0})
make("UICorner",window,{CornerRadius=UDim.new(0,12)})
make("UIStroke",window,{Color=Color3.fromRGB(62,56,71),Thickness=1})
local scale = make("UIScale",window,{Scale=1})
local function resize()
    local camera=workspace.CurrentCamera
    if camera then scale.Scale=math.min(1,math.max(0.25,math.min((camera.ViewportSize.X-20)/570,(camera.ViewportSize.Y-40)/440))) end
end
resize()
local function text(parent, value, position, size, fontSize)
    return make("TextLabel",parent,{Text=value,Position=position,Size=size,TextSize=fontSize or 13,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(220,216,228),BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left})
end
local title = text(window,"Krittax HUB",UDim2.fromOffset(18,8),UDim2.fromOffset(390,32),20)
title.Active=true
text(window,"MANGA FIGHTING  /  V1 EXPERIMENTAL",UDim2.fromOffset(18,37),UDim2.fromOffset(420,22),10)
local function button(parent, label, pos, size, callback)
    local b=make("TextButton",parent,{Text=label,Position=pos,Size=size,TextColor3=Color3.fromRGB(235,230,242),TextSize=12,Font=Enum.Font.Gotham,BackgroundColor3=gray,BorderSizePixel=0,AutoButtonColor=true})
    make("UICorner",b,{CornerRadius=UDim.new(0,6)})
    connect(b.Activated,callback)
    return b
end
local refreshUI
local reopen=button(gui,"K HUB",UDim2.fromOffset(14,80),UDim2.fromOffset(74,34),function() window.Visible=not window.Visible end)
reopen.BackgroundColor3=purple
button(window,"_",UDim2.new(1,-76,0,12),UDim2.fromOffset(26,26),function() window.Visible=false end)
button(window,"X",UDim2.new(1,-42,0,12),UDim2.fromOffset(26,26),function() hub.Destroy() end)
local left=make("Frame",window,{Position=UDim2.fromOffset(16,72),Size=UDim2.fromOffset(263,298),BackgroundTransparency=1})
local right=make("Frame",window,{Position=UDim2.fromOffset(291,72),Size=UDim2.fromOffset(263,298),BackgroundTransparency=1})
local updates={}
local function toggle(parent,label,key,y)
    local b
    b=button(parent,"",UDim2.fromOffset(0,y),UDim2.fromOffset(263,34),function()
        settings[key]=not settings[key]
        target=nil
        cancelPrompt()
        release()
        refreshUI()
    end)
    table.insert(updates,function() b.Text=label.."   "..(settings[key] and "ON" or "OFF");b.BackgroundColor3=settings[key] and purple or gray end)
end
local popup
local function choices(key)
    local values,seen={"All"},{All=true}
    local function add(v) if type(v)=="string" and v~="" and not seen[v] then seen[v]=true;table.insert(values,v) end end
    if key=="Enemy" then
        local folder=workspace:FindFirstChild("Enemies")
        if folder then for _,m in ipairs(folder:GetChildren()) do if m:IsA("Model") then add(m.Name) end end end
    else
        if zones and type(zones.Zones)=="table" then
            for _,z in pairs(zones.Zones) do if type(z)=="table" then add(z.id) end end
        end
        for _,m in ipairs(workspace:GetChildren()) do if m.Name=="WorldGate" then add(zoneOf(m)) end end
    end
    table.sort(values,function(a,b) if a=="All" then return b~="All" elseif b=="All" then return false else return a<b end end)
    return values
end
local function picker(parent,label,key,y,options)
    text(parent,label,UDim2.fromOffset(0,y),UDim2.fromOffset(260,18),11)
    local b
    b=button(parent,"",UDim2.fromOffset(0,y+21),UDim2.fromOffset(263,30),function()
        if popup then popup:Destroy();popup=nil end
        popup=make("Frame",window,{Position=UDim2.fromOffset(80,75),Size=UDim2.fromOffset(410,290),BackgroundColor3=Color3.fromRGB(25,23,31),BorderSizePixel=0,ZIndex=10})
        make("UICorner",popup,{CornerRadius=UDim.new(0,8)})
        local heading=text(popup,label,UDim2.fromOffset(12,4),UDim2.fromOffset(340,30),14);heading.ZIndex=11
        local close=button(popup,"X",UDim2.fromOffset(370,8),UDim2.fromOffset(28,26),function() if popup then popup:Destroy();popup=nil end end);close.ZIndex=11
        local list=make("ScrollingFrame",popup,{Position=UDim2.fromOffset(10,42),Size=UDim2.fromOffset(390,236),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=4,ZIndex=11})
        make("UIListLayout",list,{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})
        for i,v in ipairs(options or choices(key)) do
            local item=button(list,v,UDim2.new(),UDim2.new(1,-8,0,30),function()
                settings[key]=v;target=nil;cancelPrompt();release();popup:Destroy();popup=nil;refreshUI()
            end)
            item.ZIndex=12;item.LayoutOrder=i
        end
    end)
    table.insert(updates,function() b.Text=tostring(settings[key]).."   v" end)
end
toggle(left,"Autofarm","Farm",0)
picker(left,"SELECT ENEMY (loaded enemies)","Enemy",44)
picker(left,"FARM METHOD","Method",108,{"Tween","Warp"})
picker(left,"POSITION","Position",172,{"Behind","Above","Front","Under"})
text(left,"Tween speed: 50 - 100 studs/sec",UDim2.fromOffset(0,237),UDim2.fromOffset(260,18),11)
local speed=make("TextBox",left,{Position=UDim2.fromOffset(0,259),Size=UDim2.fromOffset(263,30),Text="75",ClearTextOnFocus=false,TextSize=13,Font=Enum.Font.Gotham,TextColor3=Color3.new(1,1,1),BackgroundColor3=gray,BorderSizePixel=0})
make("UICorner",speed,{CornerRadius=UDim.new(0,6)})
connect(speed.FocusLost,function() settings.Speed=math.clamp(tonumber(speed.Text) or 75,50,100);speed.Text=tostring(settings.Speed) end)
toggle(right,"Auto Gate","Gate",0)
picker(right,"SELECT WORLD / ZONE","World",44)
picker(right,"PRIORITY","Priority",108,{"Farm > Gate","Gate > Farm"})
text(right,"Position distance: 2 - 20 studs",UDim2.fromOffset(0,177),UDim2.fromOffset(260,18),11)
local distance=make("TextBox",right,{Position=UDim2.fromOffset(0,198),Size=UDim2.fromOffset(263,30),Text="5",ClearTextOnFocus=false,TextSize=13,Font=Enum.Font.Gotham,TextColor3=Color3.new(1,1,1),BackgroundColor3=gray,BorderSizePixel=0})
make("UICorner",distance,{CornerRadius=UDim.new(0,6)})
connect(distance.FocusLost,function() settings.Distance=math.clamp(tonumber(distance.Text) or 5,2,20);distance.Text=tostring(settings.Distance) end)
local stopButton=button(right,"STOP ALL",UDim2.fromOffset(0,252),UDim2.fromOffset(263,37),function() stop();refreshUI() end)
stopButton.BackgroundColor3=Color3.fromRGB(115,39,66)
local statusLabel=text(window,status,UDim2.fromOffset(18,380),UDim2.fromOffset(532,32),11)
statusLabel.TextWrapped=true
text(window,"Right Ctrl: show/hide  |  End: stop  |  X: unload",UDim2.fromOffset(18,411),UDim2.fromOffset(530,18),10)
refreshUI=function() for _,update in ipairs(updates) do update() end end
refreshUI()
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
connect(player.CharacterRemoving,function() target=nil;cancelPrompt();release() end)
function hub.Destroy()
    if not alive then return end
    alive=false;stop()
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
    if uiTime>=0.3 then uiTime=0;statusLabel.Text=status;resize() end
    if accumulator<0.05 then return end
    local elapsed=accumulator;accumulator=0
    local ok,err=pcall(function()
        if not settings.Farm and not settings.Gate then return end
        local r=root()
        if not r then target=nil;release();status="Waiting for respawn";return end
        local gate=settings.Gate and chooseGate(r)
        if settings.Gate and settings.Priority=="Gate > Farm" and gate then target=nil;doGate(r,gate,elapsed);return end
        if settings.Farm then
            if not validEnemy(target) or not worldMatches(target) or (settings.Enemy~="All" and target.Name~=settings.Enemy) then
                target=chooseEnemy(r)
            end
            if target then fight(r,target,elapsed);return end
        end
        target=nil
        if gate then doGate(r,gate,elapsed);return end
        release();status="Waiting for matching enemies / Gate in selected zone"
    end)
    if not ok then stop();status="Stopped: "..tostring(err);warn("[Krittax HUB] "..tostring(err));refreshUI() end
end)
print("[Krittax HUB V1] Loaded. Autofarm and Gate are OFF. PlaceId="..tostring(game.PlaceId))
