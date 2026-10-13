-- Krittax Candy + Current-World Win + Anti-AFK v2
-- Runtime-discovery build based on the supplied 97824450589417 dump.
-- The dump contains bytecode, not map instances. Unresolved pads fail closed.
-- WinPadTouch is observed as a server -> client reward event, never fired.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local P = Players.LocalPlayer
assert(P, "Run after LocalPlayer loads")
local pg = P:WaitForChild("PlayerGui", 10)
assert(pg, "PlayerGui unavailable")
if pg:FindFirstChild("KrittaxCurrentWorld") then
    warn("Close the existing Krittax Current World UI first")
    return
end
local alive, winOn, candyOn, afkOn = true, false, false, false
local generation, receipts, misses = 0, 0, 0
local selected, selectedWorld, zoneCF, zoneWorld
local records, cons = {}, {}
local currentWorld, lastScan = nil, 0
local note, afkNote = "Scanning current world...", "Anti-AFK: OFF"
local cyan = Color3.fromRGB(71, 213, 222)
local blue = Color3.fromRGB(15, 80, 175)
local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function connect(signal, fn)
    local c = signal:Connect(fn)
    cons[#cons + 1] = c
    return c
end
local gui = make("ScreenGui", {Name="KrittaxCurrentWorld", ResetOnSpawn=false,
    DisplayOrder=9999, ZIndexBehavior=Enum.ZIndexBehavior.Sibling}, pg)
local panel = make("Frame", {Size=UDim2.fromOffset(350, 468),
    Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5),
    BackgroundColor3=Color3.fromRGB(17,41,74), BorderSizePixel=0}, gui)
make("UICorner", {CornerRadius=UDim.new(0,22)}, panel)
make("UIGradient", {Color=ColorSequence.new(Color3.fromRGB(21,80,105),
    Color3.fromRGB(13,35,78)), Rotation=35}, panel)
local scale = make("UIScale", {}, panel)
local function resize()
    local cam=workspace.CurrentCamera
    if cam then scale.Scale=math.max(0.2,math.min(1,
        (cam.ViewportSize.X-20)/350,(cam.ViewportSize.Y-20)/468)) end
end
local function label(text,y,h)
    return make("TextLabel", {Position=UDim2.fromOffset(18,y),
        Size=UDim2.new(1,-36,0,h), BackgroundTransparency=1,
        Text=text, TextColor3=Color3.fromRGB(235,250,255),
        Font=Enum.Font.GothamMedium, TextSize=14, TextWrapped=true},panel)
end
local function button(text,x,y,w,h,parent)
    local b=make("TextButton", {Text=text,Position=UDim2.fromOffset(x,y),
        Size=UDim2.fromOffset(w,h),BackgroundColor3=blue,BorderSizePixel=0,
        TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=14},parent or panel)
    make("UICorner",{CornerRadius=UDim.new(0,12)},b)
    return b
end
local header=label("Krittax Candy + Win",12,35)
header.Size=UDim2.fromOffset(232,35)
header.Active=true
local minimize=button("−",264,14,30,30)
local close=button("×",302,14,30,30)
local worldLabel=label("World: detecting...",56,28)
local stageLabel=label("Stage: scanning...",88,38)
local previous=button("◀",18,135,48,34)
local scanButton=button("RESCAN STAGES",74,135,202,34)
local nextButton=button("▶",284,135,48,34)
local winButton=button("AUTO WIN: OFF",18,182,314,42)
local candyButton=button("AUTO CANDY: OFF",18,234,314,42)
local saveButton=button("SAVE ORANGE ZONE",18,286,314,34)
local afkButton=button("ANTI-AFK: OFF",18,330,314,34)
local status=label("",374,74)
status.TextSize=12
local mini=button("K",24,110,54,54,gui)
mini.Visible=false
if type(getcustomasset)=="function" then
    local ok,asset=pcall(function() return getcustomasset("KrittaxIcon.jpg") end)
    if ok and type(asset)=="string" and asset~="" then
        mini.Text=""
        local icon=make("ImageLabel",{Size=UDim2.fromScale(1,1),
            BackgroundTransparency=1,Image=asset,ScaleType=Enum.ScaleType.Crop},mini)
        make("UICorner",{CornerRadius=UDim.new(0,12)},icon)
    end
end
local suppress=0
local function drag(handle,target,isMini)
    local held, origin, pos, touch
    connect(handle.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            held=true; origin=input.Position;pos=target.Position;touch=input
        end
    end)
    connect(UIS.InputChanged,function(input)
        if not held or (input~=touch and input.UserInputType~=Enum.UserInputType.MouseMovement) then return end
        local d=input.Position-origin
        if isMini and d.Magnitude>8 then suppress=os.clock()+0.4 end
        target.Position=UDim2.new(pos.X.Scale,pos.X.Offset+d.X,pos.Y.Scale,pos.Y.Offset+d.Y)
    end)
    connect(UIS.InputEnded,function(input)
        if input==touch or input.UserInputType==Enum.UserInputType.MouseButton1 then held=false end
    end)
end
drag(header,panel,false);drag(mini,mini,true)
connect(minimize.Activated,function() panel.Visible=false;mini.Visible=true end)
connect(mini.Activated,function()
    if os.clock()<suppress then return end
    mini.Visible=false;panel.Visible=true;resize()
end)
local shared=RS:WaitForChild("Shared",10)
local remotes=shared and shared:WaitForChild("Remotes",10)
local function remote(name)
    local r=remotes and remotes:FindFirstChild(name)
    return r and r:IsA("RemoteEvent") and r or nil
end
local dataController
local okData, dataResult=pcall(function()
    return require(RS:WaitForChild("Client",10):WaitForChild("DataController",10))
end)
if okData then dataController=dataResult end
local function data()
    if not dataController or type(dataController.getData)~="function" then return nil end
    local ok,d=pcall(dataController.getData)
    return ok and type(d)=="table" and d or nil
end
local function world()
    local d=data()
    local w=d and d.CurrentWorld
    if w==nil then w=P:GetAttribute("CurrentWorld") end
    if w==nil then return nil end
    if type(w)~="string" and type(w)~="number" then return nil end
    return tostring(w)
end
local function character()
    local c=P.Character
    return c,c and c:FindFirstChildOfClass("Humanoid"),c and c:FindFirstChild("HumanoidRootPart")
end
local function halt()
    local _,h,r=character()
    if h and r then h:Move(Vector3.zero,false);h:MoveTo(r.Position) end
end
local function paint()
    winButton.Text=winOn and "AUTO WIN: ON" or "AUTO WIN: OFF"
    candyButton.Text=candyOn and "AUTO CANDY: ON" or "AUTO CANDY: OFF"
    afkButton.Text=afkOn and "ANTI-AFK: ON" or "ANTI-AFK: OFF"
    for b,on in pairs({[winButton]=winOn,[candyButton]=candyOn,[afkButton]=afkOn}) do
        b.BackgroundColor3=on and Color3.fromRGB(9,137,128) or blue
    end
    worldLabel.Text="World: "..(currentWorld or "not detected").." • AUTO"
    stageLabel.Text=selected and ("Stage "..selected.stage.." • Normal Win\n"..#records.." stages found")
        or ("Stage: none confirmed • "..#records.." stages found")
    status.Text=note.."\nReward confirmations: "..receipts.." • "..afkNote
end
local function say(s) note=s;paint() end
local function stop(message)
    winOn=false;candyOn=false;generation=generation+1;halt();say(message)
end
local function attrUp(o,key)
    while o and o~=workspace do
        local a=o:GetAttribute(key)
        if a~=nil then return a end
        o=o.Parent
    end
end
local function part(o)
    if o:IsA("BasePart") then return o end
    local trigger=o:FindFirstChild("Pad")
    if trigger and trigger:IsA("BasePart") then return trigger end
    local hit=o:FindFirstChild("Hitbox",true)
    if hit and hit:IsA("BasePart") then return hit end
    if o:IsA("Model") and o.PrimaryPart then return o.PrimaryPart end
    return o:FindFirstChildWhichIsA("BasePart",true)
end
local function stageNumber(o)
    local s=attrUp(o,"Stage")
    if tonumber(s) then return tonumber(s) end
    while o and o~=workspace do
        if CS:HasTag(o,"Stage") or o.Name:match("^[Ss]tage%d+$") then
            return tonumber(o.Name) or tonumber(o.Name:match("[Ss]tage[%s_%-]*(%d+)"))
        end
        o=o.Parent
    end
end
local function freePad(o)
    -- "Pad" and "Free" are present in OnboardingController's bytecode.
    -- Do not treat an arbitrary yellow part as a normal win pad.
    local kind=o:GetAttribute("Type") or o:GetAttribute("PadType")
    if tostring(kind):lower()=="free" or o.Name:lower()=="free" then return o end
    local child=o:FindFirstChild("Free")
    if child then return child end
end
local function scan(verbose)
    local w=world();currentWorld=w
    local byStage, stageWorlds={},{}
    local stages=CS:GetTagged("Stage")
    local seenStages={}
    for _,s in ipairs(stages) do seenStages[s]=true end
    -- These map names are verified in KrittaxPads_97824450589417.
    -- Scan live instances; do not reuse the old file's coordinates.
    local mapWorlds={Map="1",MapTest="2"}
    for i=3,10 do mapWorlds["Map"..i]=tostring(i) end
    local inheritedWorld={}
    for mapName,mapWorld in pairs(mapWorlds) do
        local map=workspace:FindFirstChild(mapName)
        local folder=map and map:FindFirstChild("Stages")
        if folder then
            for _,s in ipairs(folder:GetChildren()) do
                if s.Name:match("^[Ss]tage%d+$") then
                    inheritedWorld[s]=mapWorld
                    if not seenStages[s] then stages[#stages+1]=s;seenStages[s]=true end
                end
            end
        end
    end
    for _,s in ipairs(stages) do
        local n=tonumber(s:GetAttribute("Stage")) or tonumber(s.Name)
            or tonumber(s.Name:match("[Ss]tage[%s_%-]*(%d+)"))
        local sw=attrUp(s,"World") or inheritedWorld[s]
        if n and sw~=nil then
            stageWorlds[n]=stageWorlds[n] or {}
            stageWorlds[n][tostring(sw)]=true
        end
    end
    local pads=CS:GetTagged("Pad")
    local seenPads={}
    local explicitPadWorld={}
    for _,o in ipairs(pads) do seenPads[o]=true end
    for _,s in ipairs(stages) do
        local container=s:FindFirstChild("Pad")
        if container then
            explicitPadWorld[container]=attrUp(s,"World") or inheritedWorld[s]
            if not seenPads[container] then pads[#pads+1]=container;seenPads[container]=true end
        end
    end
    for _,o in ipairs(pads) do
        if o:IsDescendantOf(workspace) then
            local free=freePad(o)
            local n=stageNumber(o)
            local pw=attrUp(o,"World") or explicitPadWorld[o]
            if pw==nil and n and stageWorlds[n] then
                local only,count=nil,0
                for key in pairs(stageWorlds[n]) do only=key;count=count+1 end
                if count==1 then pw=only end
            end
            local p=free and part(free)
            if w and n and p and pw~=nil and tostring(pw)==w then
                local old=byStage[n]
                if not old then byStage[n]={stage=n,pad=p,world=w,source=o}
                elseif old.pad~=p then old.ambiguous=true end
            end
        end
    end
    records={}
    for _,record in pairs(byStage) do
        if not record.ambiguous then records[#records+1]=record end
    end
    table.sort(records,function(a,b) return a.stage<b.stage end)
    local oldStage=selectedWorld==w and selected and selected.stage or nil
    selected=nil
    for _,record in ipairs(records) do
        if record.stage==oldStage then selected=record end
    end
    if not selected then selected=records[1] end
    selectedWorld=w
    lastScan=os.clock()
    if verbose then
        print("[Krittax] CurrentWorld=",w,"Stage tags=",#CS:GetTagged("Stage"),"Pad tags=",#pads)
        for index,o in ipairs(pads) do
            if index>60 then break end
            print("[Krittax pad]",o:GetFullName(),"World=",attrUp(o,"World"),
                "Stage=",stageNumber(o),"Type=",o:GetAttribute("Type"),"PadType=",o:GetAttribute("PadType"))
        end
        say(not w and "CurrentWorld unavailable. Wait for the game to load."
            or (#records>0 and "Choose a stage, then turn AUTO WIN ON."
            or "No confirmed normal pads. Check console [Krittax pad] or use SAVE PAD below."))
    else paint() end
end
-- A verified manual fallback is needed if map attributes differ from the dump.
-- It records a physical normal pad, not a GUI coordinate or a guessed remote.
local manual={}
local manualButton=button("SAVE PAD",242,88,90,36)
stageLabel.Size=UDim2.fromOffset(212,38)
local function mergeManual()
    for _,record in ipairs(manual) do
        if record.world==currentWorld and record.pad.Parent then
            local found=false
            for _,auto in ipairs(records) do if auto.pad==record.pad then found=true end end
            if not found then records[#records+1]=record end
        end
    end
    table.sort(records,function(a,b) return a.stage<b.stage end)
    if not selected then selected=records[1] end
    paint()
end
connect(manualButton.Activated,function()
    if winOn or candyOn then say("Turn farming OFF before saving a pad.");return end
    currentWorld=world()
    local _,h,r=character()
    if not currentWorld or not h or h.Health<=0 or not r then say("World / character unavailable.");return end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={P.Character}
    local hit=workspace:Raycast(r.Position,Vector3.new(0,-12,0),params)
    local pad=hit and hit.Instance
    local n=pad and stageNumber(pad)
    if not pad or not n then say("Stand on the normal Win pad. A Stage attribute/tag is required.");return end
    local confirmed=false
    local o=pad
    while o and o~=workspace do
        local free=freePad(o)
        if free and (pad==free or pad:IsDescendantOf(free)) then confirmed=true;break end
        o=o.Parent
    end
    if not confirmed then say("This part is not identified as Free. Pad was not saved.");return end
    local pw=attrUp(pad,"World")
    if pw~=nil and tostring(pw)~=currentWorld then say("Pad belongs to another world.");return end
    for _,record in ipairs(manual) do
        if record.world==currentWorld and record.stage==n then record.pad=pad;selected=record;mergeManual();say("Updated Stage "..n);return end
    end
    local record={stage=n,pad=pad,world=currentWorld}
    manual[#manual+1]=record;selected=record;selectedWorld=currentWorld
    mergeManual();say("Saved normal pad for Stage "..n.." in World "..currentWorld)
end)
local function choose(delta)
    if winOn or candyOn then say("Turn farming OFF before changing stages.");return end
    if #records==0 then scan(true);mergeManual();return end
    local index=1
    for i,record in ipairs(records) do if record==selected then index=i end end
    selected=records[((index-1+delta)%#records)+1]
    selectedWorld=currentWorld;misses=0;say("Selected Stage "..selected.stage)
end
connect(previous.Activated,function() choose(-1) end)
connect(nextButton.Activated,function() choose(1) end)
connect(scanButton.Activated,function()
    stop("Rescanning...");scan(true);mergeManual()
end)
local winReward=remote("WinPadTouch")
local rewardSerial=0
local waitingReward=false
if winReward then
    connect(winReward.OnClientEvent,function()
        if alive and winOn and waitingReward and world()==selectedWorld then
            rewardSerial=rewardSerial+1;receipts=receipts+1
            paint()
        end
    end)
end
local function valid(token,c,mode)
    return alive and generation==token and P.Character==c
        and (mode=="win" and winOn or mode=="candy" and candyOn)
end
local function pause(seconds,token,c,mode)
    local finish=os.clock()+seconds
    while os.clock()<finish do
        if not valid(token,c,mode) then return false end
        if world()~=(mode=="win" and selectedWorld or zoneWorld) then return false end
        local _,h=character()
        if not h or h.Health<=0 then return false end
        task.wait(0.1)
    end
    return true
end
local function place(c,h,r,cf)
    h:Move(Vector3.zero,false);h:MoveTo(r.Position)
    c:PivotTo(cf)
    r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
end
local function farmWin(token,c,h,r)
    local record=selected
    if not record or not record.pad.Parent or record.world~=world() then
        stop("Selected pad is unavailable. RESCAN STAGES.");return
    end
    local pad=record.pad
    local height=pad.Size.Y/2+h.HipHeight+r.Size.Y/2+0.25
    local center=pad.Position+Vector3.new(0,height,0)
    local outside=center+pad.CFrame.LookVector*(pad.Size.Z/2+5)
    local rotation=r.CFrame.Rotation
    waitingReward=false
    place(c,h,r,CFrame.new(outside)*rotation)
    if not pause(0.8,token,c,"win") then return end
    local before=rewardSerial
    waitingReward=true
    say("Stage "..record.stage..": entering normal Win pad...")
    h:MoveTo(center)
    local finish=os.clock()+12
    while os.clock()<finish and valid(token,c,"win") and h.Health>0 and world()==record.world do
        if rewardSerial>before then break end
        h:MoveTo(center);task.wait(0.4)
    end
    waitingReward=false
    if not valid(token,c,"win") or h.Health<=0 then return end
    halt()
    if rewardSerial>before then
        misses=0;say("Reward confirmed. Repeating Stage "..record.stage)
        pause(2,token,c,"win")
    else
        misses=misses+1
        if misses>=3 then
            stop("No reward after 3 tries. Check stage completion / pad / server return.")
        else say("No reward confirmation ("..misses.."/3). Retrying...");pause(3,token,c,"win") end
    end
end
connect(winButton.Activated,function()
    if winOn then stop("Auto Win OFF");return end
    scan(false);mergeManual()
    if not currentWorld then say("CurrentWorld unavailable.");return end
    if P:GetAttribute("InEventWorld") or P:GetAttribute("InEventArena") then
        say("Return to a campaign world before Auto Win.");return
    end
    if not selected then say("No stage pad confirmed. RESCAN STAGES and check console.");return end
    if not winReward then say("WinPadTouch reward event unavailable. Re-run after loading.");return end
    candyOn=false;generation=generation+1;winOn=true;misses=0
    selectedWorld=currentWorld;halt();say("Auto Win ON • Stage "..selected.stage)
end)
local create,start,state=remote("PartyCreate"),remote("PartyStart"),remote("PartyState")
local creatorOpen,creatorClose=remote("PartyCreatorOpen"),remote("PartyCreatorClose")
local inParty,owner,promptOpen=false,false,false
local candyPhase,candyUntil,candyNext="idle",0,0
local away,returnedAt=false,nil
local function creatorVisible()
    local screen=pg:FindFirstChild("ScreenGui")
    local menus=screen and screen:FindFirstChild("Menus")
    local o=menus and menus:FindFirstChild("CreateParty")
    if not o then return false end
    while o and o~=pg do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o=o.Parent
    end
    return o==pg
end
local function sendCandyStart()
    if not candyOn or candyPhase~="creating" or not inParty or not owner
        or os.clock()<candyNext then return end
    candyPhase="starting";candyUntil=os.clock()+30;candyNext=os.clock()+10
    halt();say("Candy: Start sent; waiting for arena")
    start:FireServer()
end
if state then connect(state.OnClientEvent,function(active,isOwner)
    inParty=active==true;owner=isOwner==true
    if candyPhase=="starting" and not inParty then
        candyPhase="round"
        if candyOn then halt();say("Candy: party closed; waiting for death / return") end
    end
end) end
if creatorOpen then connect(creatorOpen.OnClientEvent,function() promptOpen=true end) end
if creatorClose then connect(creatorClose.OnClientEvent,function() promptOpen=false end) end
connect(saveButton.Activated,function()
    if winOn or candyOn then say("Turn farming OFF before saving zone.");return end
    local _,h,r=character()
    if not h or h.Health<=0 or not r or not creatorVisible() then
        say("Enter orange zone with Create Party open, then SAVE.");return
    end
    zoneWorld=world()
    if not zoneWorld then say("CurrentWorld unavailable.");return end
    zoneCF=r.CFrame;saveButton.Text="ORANGE ZONE SAVED ✓"
    candyPhase="idle";promptOpen=true;away=false;returnedAt=nil
    say("Candy zone saved for World "..zoneWorld)
end)
connect(candyButton.Activated,function()
    if candyOn then stop("Auto Candy OFF");return end
    if not zoneCF or zoneWorld~=world() then say("SAVE ORANGE ZONE in the current world first.");return end
    if not (create and start and state) then say("Party remotes unavailable.");return end
    if winOn then
        halt();candyPhase="idle";away=false;returnedAt=nil
    end
    winOn=false;candyOn=true;generation=generation+1;candyNext=os.clock()
    if candyPhase=="idle" or candyPhase=="entering" or candyPhase=="waitingMenu" then candyPhase="idle"
    elseif candyPhase=="creating" then candyUntil=os.clock()+20
    elseif candyPhase=="starting" then candyUntil=os.clock()+30 end
    say(candyPhase=="round" and "Candy: waiting for round end" or "Auto Candy ON")
end)
local function farmCandy(token,c,h,r)
    local now=os.clock()
    local distance=(r.Position-zoneCF.Position).Magnitude
    if candyPhase=="round" or candyPhase=="starting" then
        if distance>80 then
            if not away then halt() end
            away=true;returnedAt=nil;candyPhase="round"
            say("Candy: waiting for death / return; Auto remains ON");return
        elseif away and distance<=40 then
            returnedAt=returnedAt or now
            if now-returnedAt<2 then return end
            away=false;returnedAt=nil;inParty=false;owner=false
            candyPhase="idle";candyNext=now
            say("Candy: back at lobby; preparing next round")
        elseif creatorVisible() and distance<=15 then
            candyPhase="idle";candyNext=now;away=false;returnedAt=nil
        else
            returnedAt=nil
            if candyPhase=="round" then return end
        end
    end
    if candyPhase=="idle" or candyPhase=="waitingMenu" then
        if inParty then
            if owner then
                candyPhase="creating";candyUntil=now+20;candyNext=now;sendCandyStart()
            else halt();say("Candy: already in a party; waiting for owner") end
            return
        end
        if (creatorVisible() or promptOpen) and distance<=15 then
            candyPhase="creating";promptOpen=false;candyUntil=now+20;candyNext=now
            away=false;halt();say("Candy: Create sent: 4 players; waiting for Start permission")
            create:FireServer(4)
        elseif candyPhase=="waitingMenu" then
            if now>=candyUntil then
                halt();candyPhase="idle";candyNext=now+5;promptOpen=false
                say("Candy: party menu did not open; retrying in 5s")
            elseif now>=candyNext then
                h:MoveTo(zoneCF.Position);candyNext=now+2
                say("Candy: moving into saved zone; waiting for party menu")
            end
        elseif now>=candyNext then
            candyPhase="entering";promptOpen=false;halt()
            local outside=zoneCF.Position-zoneCF.LookVector*8
            place(c,h,r,CFrame.new(outside)*zoneCF.Rotation)
            say("Candy: warped near zone; moving inside")
            if not pause(0.8,token,c,"candy") then return end
            candyPhase="waitingMenu";candyUntil=os.clock()+15;candyNext=os.clock()+2
            h:MoveTo(zoneCF.Position)
        end
    elseif candyPhase=="creating" then
        sendCandyStart()
        if candyPhase=="creating" and now>=candyUntil then
            candyPhase="idle";candyNext=now+5;promptOpen=false
            say("Candy: Create not confirmed; retrying in 5s")
        end
    elseif candyPhase=="starting" and now>=candyUntil then
        if inParty and owner then
            candyPhase="creating";candyUntil=now+20;candyNext=now+5
            say("Candy: Start not confirmed; retrying in 5s")
        else candyUntil=now+15;say("Candy: waiting for arena / return; Auto remains ON") end
    end
end
local virtualUser
pcall(function() virtualUser=game:GetService("VirtualUser") end)
connect(afkButton.Activated,function()
    if not virtualUser then say("VirtualUser unavailable.");return end
    afkOn=not afkOn;afkNote=afkOn and "Anti-AFK: ON" or "Anti-AFK: OFF";paint()
end)
connect(P.Idled,function()
    if not alive or not afkOn then return end
    local ok,err=pcall(function()
        virtualUser:CaptureController();virtualUser:ClickButton2(Vector2.new(0,0))
    end)
    afkNote=ok and "Anti-AFK: idle action sent" or "Anti-AFK: action failed"
    if not ok then warn("[Krittax Anti-AFK] "..tostring(err)) end
    paint()
end)
local function cleanup()
    if not alive then return end
    winOn=false;candyOn=false;afkOn=false;generation=generation+1
    halt();alive=false
    for _,c in ipairs(cons) do c:Disconnect() end
end
connect(close.Activated,function() cleanup();gui:Destroy() end)
connect(gui.Destroying,cleanup)
connect(P.CharacterAdded,function()
    generation=generation+1;waitingReward=false
    inParty=false;owner=false;promptOpen=false;candyPhase="idle";away=false;returnedAt=nil
    candyNext=os.clock()+3
end)
task.spawn(function()
    local wasDead=false
    scan(true);mergeManual();resize()
    while alive do
        task.wait(0.3)
        local ok,err=pcall(function()
            local w=world()
            if w~=currentWorld then
                stop("World changed. Choose a stage in this world and turn ON.")
                selected=nil;selectedWorld=nil;scan(false);mergeManual()
                say("World changed. Choose a stage and turn AUTO WIN ON.")
            elseif not winOn and not candyOn and os.clock()-lastScan>5 then
                scan(false);mergeManual()
            end
            if winOn and (P:GetAttribute("InEventWorld") or P:GetAttribute("InEventArena")) then
                stop("Entered event area. Farming stopped.");return
            end
            local c,h,r=character()
            if not c or not h or not r or h.Health<=0 then
                wasDead=true
                if winOn or candyOn then say("Waiting for respawn; Auto remains ON") end
                return
            end
            if wasDead then
                wasDead=false;generation=generation+1
                inParty=false;owner=false;promptOpen=false;candyPhase="idle";away=false;returnedAt=nil;candyNext=os.clock()+3
                if winOn or candyOn then pause(3,generation,c,winOn and "win" or "candy") end
                return
            end
            if winOn then farmWin(generation,c,h,r)
            elseif candyOn then farmCandy(generation,c,h,r) end
        end)
        if not ok and alive then
            waitingReward=false
            if candyOn then
                halt();candyNext=os.clock()+5;promptOpen=false
                if candyPhase~="round" then candyPhase="idle" end
                say("Candy: error; retrying in 5s")
            else stop("Error: "..tostring(err):sub(1,110)) end
            warn("[Krittax] "..tostring(err))
        end
    end
end)
