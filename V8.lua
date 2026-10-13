local SOURCE = [====[
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local HS = game:GetService("HttpService")
local PFS = game:GetService("PathfindingService")
local TS = game:GetService("TweenService")
local player = Players.LocalPlayer
assert(player,"LocalPlayer unavailable")
local pg = player:WaitForChild("PlayerGui",20)
assert(pg,"PlayerGui unavailable")
local env = type(getgenv)=="function" and getgenv() or _G
local function api(name)
    return env[name] or _G[name]
end
local rf,wf,mf,isf = api("readfile") or readfile,api("writefile") or writefile,api("makefolder") or makefolder,api("isfolder") or isfolder
local folder = "KrittaxAnimeZero"
local cfgPath = folder.."/config_"..tostring(game.GameId).."_"..tostring(player.UserId)..".json"
local scriptPath = folder.."/main.lua"
local VERSION = 2
local defaults = {
    version=VERSION,selection="Story/Hxh",chapter=1,floor=1,difficulty=1,players=1,
    autoQueue=false,autoFarm=false,autoRetry=false,antiAFK=true,resumeTeleport=true,
    range=6,pads={},hoverHeight=4,tweenSpeed=45,autoSkill=true,
    skill1=true,skill2=true,skill3=true,skill4=true,autoRubble=true,autoNextArea=true
}
local cfg = {}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function integer(n,lo,hi,fallback)
    return finite(n) and math.clamp(math.floor(n),lo,hi) or fallback
end
local function validate(data)
    assert(type(data)=="table" and data.version==VERSION,"Unsupported config version")
    local c={version=VERSION,pads={}}
    for k,v in pairs(defaults) do
        if type(v)=="boolean" then
            if type(data[k])=="boolean" then c[k]=data[k] else c[k]=v end
        end
    end
    c.selection=type(data.selection)=="string" and data.selection or defaults.selection
    c.chapter=integer(data.chapter,1,127,1)
    c.floor=integer(data.floor,1,65535,1)
    c.difficulty=integer(data.difficulty,1,4,1)
    c.players=integer(data.players,1,6,1)
    c.range=integer(data.range,3,12,6)
    c.hoverHeight=integer(data.hoverHeight,1,12,4)
    c.tweenSpeed=integer(data.tweenSpeed,10,120,45)
    if type(data.pads)=="table" then
        for k,p in pairs(data.pads) do
            if type(k)=="string" and type(p)=="table" and finite(p[1]) and finite(p[2]) and finite(p[3]) then
                c.pads[k]={p[1],p[2],p[3]}
            end
        end
    end
    return c
end
for k,v in pairs(defaults) do cfg[k]=type(v)=="table" and {} or v end
for _,name in ipairs({"KrittaxDungeonLobby","KrittaxAnimeZeroV2"}) do
    local old=pg:FindFirstChild(name)
    if old then
        local event=old:FindFirstChild("Cleanup")
        if event then event:Fire() end
        old:Destroy()
    end
end
local configMessage="Default settings • auto-load ready"
local lastGood
if type(rf)=="function" then
    for _,p in ipairs({cfgPath,cfgPath..".bak"}) do
        local ok,text=pcall(rf,p)
        if ok then
            local valid,value=pcall(function() return validate(HS:JSONDecode(text)) end)
            if valid then
                cfg,lastGood=value,text
                configMessage=p==cfgPath and "Previous config loaded" or "Backup config recovered"
                break
            else configMessage="Config invalid • using defaults / backup" end
        end
    end
else configMessage="readfile unavailable • automatic loading unavailable" end
local alive=true
local connections={}
local modules={}
local ready=false
local context="Loading"
local stage="Loading game modules…"
local configDirty=false
local savedAt=0
local packetRoom=nil
local queuePending=false
local queueToken=0
local queueBlocked=false
local padAttemptAt=nil
local triedPads={}
local nextPadScan=0
local lobbyStage="idle"
local held=false
local navigationGoal=nil
local controls=nil
local controlsDisabled=false
local hovering=nil
local targetId=nil
local skillBusy=false
local nextSkillAt=0
local skillSlot=0
local skillEpoch=0
local skillMessage="Auto Skill ready"
local refresh=function() end
local selectEntry
local diagnosticLines={"KRITTAX diagnostics v9", "PlaceId: "..tostring(game.PlaceId), "GameId: "..tostring(game.GameId)}
local function log(message)
    diagnosticLines[#diagnosticLines+1]=string.format("%.1f %s",os.clock(),tostring(message))
    if #diagnosticLines>100 then table.remove(diagnosticLines,4) end
end
local function say(s) stage=s end
local function boundedRequire(node)
    local done,ok,result=false,false,nil
    local worker=task.spawn(function()
        ok,result=pcall(require,node)
        done=true
    end)
    local deadline=os.clock()+15
    while alive and not done and os.clock()<deadline do task.wait(.1) end
    if not done then
        pcall(task.cancel,worker)
        error("Module load timed out: "..node:GetFullName())
    end
    if not ok then error("Module load failed: "..node:GetFullName().." | "..tostring(result)) end
    return result
end
local function track(c)
    if c~=nil then connections[#connections+1]=c end
    return c
end
local function ownFolder()
    assert(type(wf)=="function" and type(rf)=="function","readfile/writefile unavailable")
    if type(isf)=="function" and isf(folder) then return end
    if type(mf)=="function" then
        local ok,err=pcall(mf,folder)
        if not ok and not (type(isf)=="function" and isf(folder)) then error(err) end
    end
end
local function saveConfig()
    local ok,err=pcall(function()
        ownFolder()
        local text=HS:JSONEncode(cfg)
        if lastGood then wf(cfgPath..".bak",lastGood) end
        wf(cfgPath,text)
        assert(rf(cfgPath)==text,"Config readback mismatch")
        lastGood=text
    end)
    if ok then
        configDirty=false
        savedAt=os.clock()
        configMessage="Config saved + verified • auto-load ON"
    else
        configDirty=false
        configMessage="SAVE FAILED: "..tostring(err)
    end
    return ok
end
local function changed()
    configDirty=true
    refresh()
end
local function setAttack(value)
    if modules.character then
        if value or held then modules.character.setTouchHeld("Attack",value) end
    end
    held=value
end
local function stopHover()
    local f=hovering
    hovering=nil
    targetId=nil
    if not f then return end
    if f.tween then pcall(function() f.tween:Cancel() f.tween:Destroy() end) end
    if f.added then f.added:Disconnect() end
    if f.force then f.force:Destroy() end
    if f.orientation then f.orientation:Destroy() end
    if f.attachment then f.attachment:Destroy() end
    if f.humanoid and f.humanoid.Parent then f.humanoid.AutoRotate=f.autoRotate end
    for part,collision in pairs(f.collisions) do
        if part.Parent then part.CanCollide=collision end
    end
    if f.root and f.root.Parent then
        local root=f.root
        local look=root.CFrame.LookVector
        local flat=Vector3.new(look.X,0,look.Z)
        if flat.Magnitude<.01 then flat=Vector3.new(0,0,-1) end
        root.CFrame=CFrame.lookAt(root.Position,root.Position+flat.Unit)
        root.AssemblyAngularVelocity=Vector3.zero
    end
end
local function stopMove()
    local wasMoving=hovering~=nil or navigationGoal~=nil or controlsDisabled
    stopHover()
    navigationGoal=nil
    local character=player.Character
    local h=character and character:FindFirstChildOfClass("Humanoid")
    if wasMoving then
        if h then h:Move(Vector3.zero) h:MoveTo(h.RootPart and h.RootPart.Position or character:GetPivot().Position) end
        if controls and controlsDisabled then pcall(function() controls:Enable() end) end
        controlsDisabled=false
    end
end
local function moveTo(position)
    if controls and not controlsDisabled then
        local ok=pcall(function() controls:Disable() end)
        if ok then controlsDisabled=true else controls=nil end
    end
    navigationGoal=position
end
local function hoverTo(root,h,enemyPosition,id,approachPosition)
    navigationGoal=nil
    if hovering and hovering.root~=root then stopHover() end
    if not hovering then
        if controls and not controlsDisabled then
        local ok=pcall(function() controls:Disable() end)
        if ok then controlsDisabled=true else controls=nil end
    end
        h:Move(Vector3.zero)
        h:MoveTo(root.Position)
        local f={root=root,humanoid=h,autoRotate=h.AutoRotate,collisions={},lastUpdate=0}
        hovering=f
        h.AutoRotate=false
        local function noCollision(part)
            if part:IsA("BasePart") then
                f.collisions[part]=part.CanCollide
                part.CanCollide=false
            end
        end
        for _,part in ipairs(root.Parent:GetDescendants()) do noCollision(part) end
        f.added=root.Parent.DescendantAdded:Connect(noCollision)
        f.attachment=Instance.new("Attachment")
        f.attachment.Name="KrittaxHoverAttachment"
        f.attachment.Parent=root
        f.force=Instance.new("LinearVelocity")
        f.force.Name="KrittaxHoverVelocity"
        f.force.Attachment0=f.attachment
        f.force.RelativeTo=Enum.ActuatorRelativeTo.World
        f.force.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector
        f.force.VectorVelocity=Vector3.zero
        f.force.ForceLimitsEnabled=false
        f.force.Parent=root
        f.orientation=Instance.new("AlignOrientation")
        f.orientation.Name="KrittaxHoverOrientation"
        f.orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment
        f.orientation.Attachment0=f.attachment
        f.orientation.RigidityEnabled=true
        f.orientation.CFrame=root.CFrame
        f.orientation.Parent=root
    end
    local f=hovering
    h:Move(Vector3.zero)
    local goal=approachPosition or (enemyPosition+Vector3.new(0,cfg.hoverHeight,0))
    local orientation=CFrame.lookAt(goal,enemyPosition,approachPosition and Vector3.new(0,1,0) or Vector3.new(0,0,-1))
    f.orientation.CFrame=orientation
    root.AssemblyLinearVelocity=Vector3.zero
    root.AssemblyAngularVelocity=Vector3.zero
    local changedTarget=f.targetId~=id
    local moved=not f.destination or (goal-f.destination).Magnitude>1
    local speedChanged=f.speed~=cfg.tweenSpeed
    local ended=not f.tween or f.tween.PlaybackState~=Enum.PlaybackState.Playing
    local displaced=ended and (root.Position-goal).Magnitude>.6
    if changedTarget or ((moved or speedChanged or displaced) and os.clock()-f.lastUpdate>=.2) then
        if f.tween then f.tween:Cancel() f.tween:Destroy() end
        local duration=math.max(.08,(root.Position-goal).Magnitude/cfg.tweenSpeed)
        f.tween=TS:Create(root,TweenInfo.new(duration,Enum.EasingStyle.Linear),{CFrame=orientation})
        f.destination,f.targetId,f.lastUpdate,f.speed=goal,id,os.clock(),cfg.tweenSpeed
        f.tween:Play()
    end
    targetId=id
    return (root.Position-goal).Magnitude<=1.5
end
local function skillTick()
    if not cfg.autoSkill or skillBusy or os.clock()<nextSkillAt then return end
    local picked=nil
    for _=1,4 do
        skillSlot=skillSlot%4+1
        if cfg["skill"..skillSlot] then picked=skillSlot break end
    end
    if not picked then skillMessage="No skill slots enabled" return end
    if not modules.character or type(modules.character.performSkill)~="function" then
        cfg.autoSkill=false changed() skillMessage="Native skill controller unavailable" return
    end
    nextSkillAt=os.clock()+.6
    skillBusy=true
    setAttack(false)
    local epoch=skillEpoch
    task.spawn(function()
        if not alive or not cfg.autoFarm or not cfg.autoSkill or epoch~=skillEpoch then skillBusy=false return end
        local ok,result=pcall(modules.character.performSkill,picked)
        skillBusy=false
        if not alive or epoch~=skillEpoch then return end
        if not ok then
            cfg.autoSkill=false changed()
            skillMessage="Skill error: "..tostring(result)
        elseif result==false then
            skillMessage="Skill "..picked..": waiting for game conditions / cooldown"
        else
            skillMessage="Skill "..picked..": native controller called"
        end
    end)
end
local function shutdown()
    if not alive then return end
    alive=false
    skillEpoch=skillEpoch+1
    pcall(setAttack,false)
    stopMove()
    for _,c in ipairs(connections) do
        pcall(function()
            if type(c)=="function" then c() elseif c.Disconnect then c:Disconnect() elseif c.disconnect then c:disconnect() end
        end)
    end
    if configDirty then saveConfig() end
end
local textBlue=Color3.fromRGB(16,58,153)
local function make(class,parent,props)
    local x=Instance.new(class)
    for k,v in pairs(props or {}) do x[k]=v end
    if class=="TextLabel" or class=="TextButton" or class=="TextBox" then
        x.TextColor3=textBlue
        if class=="TextBox" then x.PlaceholderColor3=textBlue end
    end
    x.Parent=parent
    return x
end
local function round(x,r) make("UICorner",x,{CornerRadius=UDim.new(0,r or 15)}) end
local cyan,blue=Color3.fromRGB(130,229,235),Color3.fromRGB(170,202,248)
local function grad(x,a,b) make("UIGradient",x,{Color=ColorSequence.new(a or cyan,b or blue)}) end
local gui=make("ScreenGui",pg,{Name="KrittaxAnimeZeroV2",ResetOnSpawn=false,DisplayOrder=10000,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local cleanup=make("BindableEvent",gui,{Name="Cleanup"})
track(cleanup.Event:Connect(shutdown))
track(gui.Destroying:Connect(shutdown))
local panel=make("Frame",gui,{Size=UDim2.fromOffset(380,490),Position=UDim2.fromScale(.5,.5),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.08,BorderSizePixel=0})
round(panel,25)
grad(panel,Color3.fromRGB(207,248,247),Color3.fromRGB(163,191,224))
make("UIStroke",panel,{Color=cyan,Thickness=2,Transparency=.25})
local scale=make("UIScale",panel,{Scale=1})
local title=make("TextLabel",panel,{Size=UDim2.new(1,-110,0,48),Position=UDim2.fromOffset(16,7),BackgroundTransparency=1,Text="KRITTAX • ANIME ZERO",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(139,57,51),Active=true})
local function headerButton(text,x)
    local b=make("TextButton",panel,{Size=UDim2.fromOffset(36,34),Position=UDim2.new(1,x,0,14),BackgroundColor3=blue,Text=text,TextColor3=Color3.new(1,1,1),TextSize=22,Font=Enum.Font.GothamBold,BorderSizePixel=0})
    round(b,11) return b
end
local mini=headerButton("−",-90)
local close=headerButton("×",-47)
local icon=make("TextButton",gui,{Size=UDim2.fromOffset(58,58),Position=UDim2.fromOffset(16,100),BackgroundColor3=cyan,Text="K",TextColor3=Color3.new(1,1,1),TextSize=29,Font=Enum.Font.GothamBold,Visible=false,BorderSizePixel=0})
round(icon,14) grad(icon)
local ca=api("getcustomasset") or getcustomasset
if type(ca)=="function" then
    local ok,asset=pcall(ca,"KrittaxIcon.jpg")
    if ok and type(asset)=="string" then
        icon.Text=""
        local img=make("ImageLabel",icon,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Image=asset,ScaleType=Enum.ScaleType.Crop})
        round(img,14)
    end
end
local tabs=make("Frame",panel,{Size=UDim2.new(1,-28,0,34),Position=UDim2.fromOffset(14,60),BackgroundTransparency=1})
local body=make("ScrollingFrame",panel,{Size=UDim2.new(1,-28,1,-225),Position=UDim2.fromOffset(14,104),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y})
make("UIListLayout",body,{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder})
local status=make("TextLabel",panel,{Size=UDim2.new(1,-32,0,57),Position=UDim2.new(0,16,1,-114),BackgroundTransparency=1,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.fromRGB(24,54,78),TextSize=12,Font=Enum.Font.Gotham,Text="Loading…"})
local diskLabel=make("TextLabel",panel,{Size=UDim2.new(1,-32,0,24),Position=UDim2.new(0,16,1,-54),BackgroundTransparency=1,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=blue,TextSize=11,Font=Enum.Font.Gotham,Text=configMessage})
local resumeLabel=make("TextLabel",panel,{Size=UDim2.new(1,-32,0,24),Position=UDim2.new(0,16,1,-29),BackgroundTransparency=1,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=blue,TextSize=11,Font=Enum.Font.Gotham,Text="Teleport resume: checking…"})
local rows={}
local tab="Farm"
local function row(group,text,callback)
    local b=make("TextButton",body,{Size=UDim2.new(1,-4,0,45),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Text=text,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=14,TextWrapped=true,LayoutOrder=#rows+1})
    round(b,16) grad(b)
    rows[#rows+1]={widget=b,group=group}
    if callback then track(b.Activated:Connect(callback)) end
    return b
end
local tabButtons={}
for i,name in ipairs({"Lobby","Farm","Settings"}) do
    local b=make("TextButton",tabs,{Size=UDim2.new(1/3,-6,1,0),Position=UDim2.new((i-1)/3,0,0,0),BackgroundColor3=blue,Text=name,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=14,BorderSizePixel=0})
    round(b,11) tabButtons[name]=b
    track(b.Activated:Connect(function() tab=name body.CanvasPosition=Vector2.zero refresh() end))
end
local entries={
    {mode={Id="Story",DisplayName="Story"},map={Id="Hxh",DisplayName="Hxh",Chapters={1,2,3}}},
    {mode={Id="Infinite",DisplayName="Infinite"},map={Id="Zzz",DisplayName="ZZZ World"}},
    {mode={Id="Raid",DisplayName="Raid",FixedDifficulty=4},map={Id="BathTub",DisplayName="Spirit's Bathtub"}},
    {mode={Id="Raid",DisplayName="Raid",FixedDifficulty=4},map={Id="ShadowGate",DisplayName="Shadow Gate"}},
    {mode={Id="Trials",DisplayName="Trials"},map={Id="Trials",DisplayName="Trials",Floors=true}}
}
local function key(e) return e.mode.Id.."/"..e.map.Id end
selectEntry=function()
    for i,e in ipairs(entries) do if key(e)==cfg.selection then return e,i end end
    return nil,nil
end
local function editAllowed()
    if queuePending then say("Wait for the pending room request, or Stop All.") return false end
    return true
end
local mapButton=row("Lobby","Map",function()
    if not editAllowed() then return end
    local _,i=selectEntry()
    cfg.selection=key(entries[(i or 0)%#entries+1])
    cfg.chapter,cfg.floor=1,1
    changed()
end)
local stageRow=row("Lobby","",nil)
local stageLabel=make("TextLabel",stageRow,{Size=UDim2.new(.55,0,1,0),Position=UDim2.fromOffset(12,0),BackgroundTransparency=1,Text="Act / Floor",TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=14})
local stageInput=make("TextBox",stageRow,{Size=UDim2.new(.32,0,.72,0),Position=UDim2.fromScale(.64,.14),BackgroundColor3=Color3.fromRGB(230,245,255),TextColor3=Color3.new(1,1,1),Text="1",ClearTextOnFocus=false,Font=Enum.Font.GothamBold,TextSize=16,BorderSizePixel=0})
round(stageInput,10)
track(stageInput.FocusLost:Connect(function()
    local e=selectEntry()
    local n=tonumber(stageInput.Text)
    if e and editAllowed() and n and n==math.floor(n) then
        if e.map.Floors then cfg.floor=integer(n,1,65535,cfg.floor)
        elseif e.map.Chapters and table.find(e.map.Chapters,n) then cfg.chapter=n
        else say("Choose an act listed by the game.") end
        changed()
    end
    refresh()
end))
local names={"Easy","Medium","Hard","Nightmare"}
local diffButton=row("Lobby","Difficulty",function()
    if editAllowed() then cfg.difficulty=cfg.difficulty%4+1 changed() end
end)
local playerButton=row("Lobby","Players",function()
    if editAllowed() then cfg.players=cfg.players%6+1 changed() end
end)
local queueButton=row("Lobby","Auto Queue",function()
    cfg.autoQueue=not cfg.autoQueue queueBlocked=false padAttemptAt=nil triedPads={} nextPadScan=0 changed()
    if not cfg.autoQueue then stopMove() end
end)
row("Lobby","Queue pad: AUTO DETECT + WARP",function()
    say("Finds Start Here pads under Systems/QuqueRooms. No saved position required.")
end)
local farmButton=row("Farm","Auto Farm",function()
    cfg.autoFarm=not cfg.autoFarm changed()
    if not cfg.autoFarm then skillEpoch=skillEpoch+1 pcall(setAttack,false) stopMove() end
end)
local retryButton=row("Farm","Auto Retry",function() cfg.autoRetry=not cfg.autoRetry changed() end)
local nextAreaButton=row("Farm","Auto Next Area",function()
    cfg.autoNextArea=not cfg.autoNextArea changed()
    if not cfg.autoNextArea then pcall(setAttack,false) stopMove() end
end)
local rubbleButton=row("Farm","Auto Break Rubble",function()
    cfg.autoRubble=not cfg.autoRubble changed()
    pcall(setAttack,false) stopMove()
end)
local skillButton=row("Farm","Auto Skill",function()
    cfg.autoSkill=not cfg.autoSkill
    skillEpoch=skillEpoch+1
    changed()
end)
local slotButtons={}
for i=1,4 do
    local slot=i
    slotButtons[i]=row("Farm","Skill "..i,function()
        cfg["skill"..slot]=not cfg["skill"..slot]
        skillEpoch=skillEpoch+1
        changed()
    end)
end
local heightButton=row("Farm","Hover height",function()
    cfg.hoverHeight=cfg.hoverHeight%12+1 changed()
end)
local speedButton=row("Farm","Tween speed",function()
    cfg.tweenSpeed=cfg.tweenSpeed+5
    if cfg.tweenSpeed>120 then cfg.tweenSpeed=10 end
    changed()
end)
local skillStatus=row("Farm","Auto Skill ready",nil)
skillStatus.AutoButtonColor=false

local rangeButton=row("Farm","Attack range",function() cfg.range=cfg.range%12+1 if cfg.range<3 then cfg.range=3 end changed() end)
local antiButton=row("Settings","Anti-AFK",function() cfg.antiAFK=not cfg.antiAFK changed() end)
local resumeButton=row("Settings","Resume after teleport",function() cfg.resumeTeleport=not cfg.resumeTeleport changed() end)
row("Settings","SAVE CONFIG NOW",function() saveConfig() end)
local report=make("Frame",panel,{Size=UDim2.new(1,-16,1,-16),Position=UDim2.fromOffset(8,8),BackgroundColor3=Color3.fromRGB(231,246,255),Visible=false,ZIndex=20,BorderSizePixel=0})
round(report,18)
local reportBox=make("TextBox",report,{Size=UDim2.new(1,-20,1,-75),Position=UDim2.fromOffset(10,10),BackgroundTransparency=1,Text="",TextSize=12,Font=Enum.Font.Code,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,MultiLine=true,ClearTextOnFocus=false,TextEditable=false,ZIndex=21})
local function reportText()
    return table.concat(diagnosticLines,"\n").."\nContext: "..context.." | Ready: "..tostring(ready).."\nStatus: "..stage.."\n"..configMessage.."\nMovement backend: "..(controls and "PlayerModule + direct Tween" or "Direct Humanoid + Tween (PlayerModule optional)")
end
local copyReport=make("TextButton",report,{Size=UDim2.new(.63,-15,0,44),Position=UDim2.new(0,10,1,-54),BackgroundColor3=cyan,Text="COPY FULL ERROR",Font=Enum.Font.GothamBold,TextSize=13,ZIndex=21,BorderSizePixel=0})
round(copyReport,12)
local closeReport=make("TextButton",report,{Size=UDim2.new(.37,-15,0,44),Position=UDim2.new(.63,5,1,-54),BackgroundColor3=blue,Text="BACK",Font=Enum.Font.GothamBold,TextSize=13,ZIndex=21,BorderSizePixel=0})
round(closeReport,12)
track(closeReport.Activated:Connect(function() report.Visible=false end))
track(copyReport.Activated:Connect(function()
    local text=reportText()
    local clipboard=api("setclipboard") or setclipboard
    local ok,err=pcall(function() assert(type(clipboard)=="function","Clipboard unavailable") clipboard(text) end)
    if ok then copyReport.Text="COPIED" else
        local saved=pcall(function() ownFolder() wf(folder.."/diagnostics.txt",text) end)
        copyReport.Text=saved and "SAVED diagnostics.txt" or "COPY / SAVE FAILED"
        log(err)
    end
end))
row("Settings","SHOW / COPY ERROR",function()
    reportBox.Text=reportText()
    copyReport.Text="COPY FULL ERROR"
    report.Visible=true
end)

row("Settings","Config auto-load: ALWAYS ON",function() say("This account's saved settings load at startup. Changes auto-save locally.") end)
local function stopAll()
    cfg.autoFarm,cfg.autoRetry,cfg.autoQueue=false,false,false
    skillEpoch=skillEpoch+1
    queuePending=false queueToken=queueToken+1 queueBlocked=false
    pcall(setAttack,false) stopMove() changed() saveConfig()
    say("Stopped. Already-created rooms and server teleports are not cancelled.")
end
row("Farm","STOP ALL",stopAll)
row("Lobby","STOP ALL",stopAll)
refresh=function()
    nextAreaButton.Text="Auto Next Area: "..(cfg.autoNextArea and "ON" or "OFF")
    rubbleButton.Text="Auto Break Rubble: "..(cfg.autoRubble and "ON" or "OFF")
    for _,r in ipairs(rows) do r.widget.Visible=r.group==tab end
    for name,b in pairs(tabButtons) do b.BackgroundColor3=name==tab and cyan or blue end
    local e=selectEntry()
    mapButton.Text=e and (e.mode.DisplayName or e.mode.Id).." • "..(e.map.DisplayName or e.map.Id).."  ›" or "Saved map unavailable • tap to select"
    local d=e and (e.mode.FixedDifficulty or ((e.mode.Id=="Story" or e.mode.Id=="Infinite" or e.mode.Id=="Defend") and cfg.difficulty or 1)) or cfg.difficulty
    diffButton.Text="Difficulty: "..(names[d] or tostring(d))..(e and e.mode.FixedDifficulty and " (fixed)" or "  ›")
    playerButton.Text="Room capacity: "..cfg.players.." / 6  ›"
    stageLabel.Text=e and e.map.Floors and "Floor" or e and e.map.Chapters and ("Act ("..table.concat(e.map.Chapters,",")..")") or "Act: not used"
    if not stageInput:IsFocused() then stageInput.Text=tostring(e and e.map.Floors and cfg.floor or cfg.chapter) end
    stageInput.Visible=e~=nil and (e.map.Floors or e.map.Chapters~=nil) or false
    queueButton.Text="Auto Create + Start: "..(cfg.autoQueue and "ON" or "OFF")
    farmButton.Text="Auto Farm (Tween hover + M1): "..(cfg.autoFarm and "ON" or "OFF")
    skillButton.Text="Auto Skill: "..(cfg.autoSkill and "ON" or "OFF")
    for i,b in ipairs(slotButtons) do b.Text="Skill "..i..(i==4 and " / Ultimate" or "")..": "..(cfg["skill"..i] and "ON" or "OFF") end
    heightButton.Text="Hover height: "..cfg.hoverHeight.." studs above target  >"
    speedButton.Text="Tween speed: "..cfg.tweenSpeed.." studs/sec  >"
    retryButton.Text="Auto Retry same stage: "..(cfg.autoRetry and "ON" or "OFF")
    rangeButton.Text="Attack distance: "..cfg.range.." studs  ›"
    antiButton.Text="Anti-AFK: "..(cfg.antiAFK and "ON" or "OFF")
    resumeButton.Text="Resume after teleport: "..(cfg.resumeTeleport and "ON" or "OFF")
end
refresh()
track(mini.Activated:Connect(function() panel.Visible=false icon.Visible=true end))
track(close.Activated:Connect(function() stopAll() gui:Destroy() end))
local drag=nil
local suppressClickUntil=0
local function enableDrag(handle,target)
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            drag={input=input,start=input.Position,pos=target.Position,target=target,moved=false}
        end
    end))
end
enableDrag(title,panel) enableDrag(icon,icon)
track(UIS.InputChanged:Connect(function(input)
    local d=drag
    if not d then return end
    if input==d.input or (d.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then
        local diff=input.Position-d.start
        if diff.Magnitude>6 then d.moved=true suppressClickUntil=os.clock()+.3 end
        d.target.Position=UDim2.new(d.pos.X.Scale,d.pos.X.Offset+diff.X,d.pos.Y.Scale,d.pos.Y.Offset+diff.Y)
    end
end))
track(UIS.InputEnded:Connect(function(input)
    if drag and input==drag.input then if drag.moved then suppressClickUntil=os.clock()+.3 end drag=nil end
end))
track(icon.Activated:Connect(function()
    if os.clock()<suppressClickUntil then return end
    panel.Visible=true icon.Visible=false
end))
track(player.Idled:Connect(function()
    if not alive or not cfg.antiAFK then return end
    local ok,err=pcall(function()
        local v=game:GetService("VirtualUser")
        v:CaptureController() v:ClickButton2(Vector2.zero)
    end)
    if not ok then cfg.antiAFK=false changed() say("Anti-AFK unavailable: "..tostring(err)) end
end))
local queueFn=api("queue_on_teleport") or queue_on_teleport or api("queueonteleport") or queueonteleport
if type(queueFn)~="function" and type(env.syn)=="table" then queueFn=env.syn.queue_on_teleport end
local resumeMessage=type(queueFn)=="function" and "Available • will queue on teleport" or "Unavailable • rerun script after teleport"
local teleportQueued=false
local queueLoader=string.format([[if not game:IsLoaded() then game.Loaded:Wait() end local ok,c=pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(%q)) end) if not ok or not c.resumeTeleport then return end local ok,s=pcall(readfile,%q) if ok then local fn,e=loadstring(s) if fn then fn() else warn(e) end else warn("Krittax resume: "..tostring(s)) end]],cfgPath,scriptPath)
local function prepareResume()
    if not cfg.resumeTeleport or teleportQueued then return end
    if type(queueFn)~="function" then return end
    local ok,err=pcall(function()
        assert(type(rf)=="function","readfile unavailable")
        assert(#rf(scriptPath)>100,"Install the complete script before enabling resume")
        assert(saveConfig(),"Config save failed")
        queueFn(queueLoader)
    end)
    if ok then teleportQueued=true resumeMessage="Queued for the next teleport"
    else resumeMessage="FAILED: "..tostring(err) end
end
track(player.OnTeleport:Connect(function(state)
    if state==Enum.TeleportState.Started or state==Enum.TeleportState.InProgress then
        pcall(setAttack,false) stopMove() prepareResume()
    elseif state==Enum.TeleportState.Failed then
        resumeMessage="Teleport failed; queued resume status unknown"
    end
end))
local function moduleAt(root,path)
    local node=root
    for _,name in ipairs(path) do node=node:WaitForChild(name,12) assert(node,"Missing module: "..table.concat(path,"/")) end
    log("Loading "..node:GetFullName())
    say("Loading: "..table.concat(path,"/"))
    local result=boundedRequire(node)
    log("Loaded "..node:GetFullName().." -> "..type(result))
    return result
end
local function value(node)
    if node==nil then return nil end
    if type(node)=="table" and type(node.get)=="function" then return node:get() end
    return node
end
local function pauseError(err)
    log("ERROR: "..tostring(err))
    cfg.autoFarm,cfg.autoQueue,cfg.autoRetry=false,false,false
    skillEpoch=skillEpoch+1
    pcall(setAttack,false) stopMove() changed()
    say("PAUSED: "..tostring(err))
end
local function createRoom()
    if not cfg.autoQueue or queueBlocked or queuePending or packetRoom==nil or lobbyStage=="queued" or lobbyStage=="starting" or lobbyStage=="teleporting" then return end
    local e=selectEntry()
    if not e then queueBlocked=true say("Choose a map available in this lobby.") return end
    if e.map.Chapters and not table.find(e.map.Chapters,cfg.chapter) then queueBlocked=true say("Saved act is not available. Select a valid act.") return end
    local d=e.mode.FixedDifficulty or ((e.mode.Id=="Story" or e.mode.Id=="Infinite" or e.mode.Id=="Defend") and cfg.difficulty or 1)
    local payload={gamemode=e.mode.Id,map=e.map.Id,chapter=e.map.Chapters and cfg.chapter or 0,floor=e.map.Floors and cfg.floor or 0,difficulty=d,maxPlayers=cfg.players,friendsOnly=false,roomNumber=packetRoom}
    queuePending=true queueToken=queueToken+1 lobbyStage="creating"
    local token=queueToken
    say("Creating room… waiting for server confirmation")
    modules.lobbyPackets.createQuque:fire(payload)
    task.delay(20,function()
        if alive and token==queueToken and queuePending then
            queuePending=false queueBlocked=true cfg.autoQueue=false changed()
            say("Room not confirmed. Check unlocks / cooldown / game message. Auto Queue stopped.")
        end
    end)
end
local function startRoom()
    if not cfg.autoQueue or lobbyStage~="queued" then return end
    lobbyStage="starting"
    prepareResume()
    modules.lobbyPackets.startQuqueNow:fire()
    say("Room confirmed • Start requested")
end
local function setupLobby()
    modules.lobbyPackets=moduleAt(RS,{"lobby","packets"})
    modules.queueStates=moduleAt(RS,{"lobby","enums","ququeStatusEnum"})
    local enum=moduleAt(RS,{"lobby","enums","gamemodeSelectEnum"})
    local fresh={}
    for _,mode in pairs(enum.Gamemode) do
        for _,map in ipairs(mode.Maps or {}) do fresh[#fresh+1]={mode=mode,map=map} end
    end
    assert(#fresh>0,"No lobby maps available")
    table.sort(fresh,function(a,b) return key(a)<key(b) end)
    entries=fresh
    track(modules.lobbyPackets.toggleQuqueWindow:on(function(data)
        if not alive then return end
        if data.open then
            packetRoom=data.roomNumber padAttemptAt=nil
            if lobbyStage=="idle" then say("Queue detected • creating selected room") end
        else packetRoom=nil end
    end))
    track(modules.lobbyPackets.updateClientQuqueStatus:on(function(s)
        if not alive then return end
        local states=modules.queueStates.client
        if s==states.inQuque and queuePending then
            queuePending=false lobbyStage="queued" stopMove()
            say("Room confirmed")
        elseif s==states.teleporting then
            lobbyStage="teleporting" stopMove() prepareResume() say("Teleporting to dungeon…")
        elseif s==states.idle then
            queuePending=false lobbyStage="idle" queueToken=queueToken+1 padAttemptAt=nil triedPads={} nextPadScan=0
        end
    end))
    refresh()
end
local function setupDungeon()
    modules.run=moduleAt(RS,{"game","stores","runStore"})
    modules.enemies=moduleAt(RS,{"game","stores","enemyStore"})
    modules.runPackets=moduleAt(RS,{"game","packets","runPackets"})
    modules.character=moduleAt(player,{"PlayerScripts","game","controllers","characterController"})
    modules.interface=moduleAt(player,{"PlayerScripts","game","stores","interfaceStore"})
    assert(type(modules.character.setTouchHeld)=="function","Native attack control unavailable")
end
local rubbleCache=nil
local rubbleNextScan=0
local rubbleReason=""
local function rubbleHealth(node)
    while node and node~=game do
        local hp=node:GetAttribute("RubbleHealth")
        if finite(hp) then return hp end
        node=node.Parent
    end
    return nil
end
local function rubblePhysical(node)
    return node:IsA("BasePart") and node.Name~="Blocker" and node.Transparency<.95 and node.CanQuery
end
local function rubbleSurface(root,node)
    if not rubblePhysical(node) then return nil end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={node}
    -- Prefer a horizontal chest-height hit. Fall back to the mesh center.
    for _,point in ipairs({Vector3.new(node.Position.X,root.Position.Y,node.Position.Z),node.Position}) do
        local delta=point-root.Position
        if delta.Magnitude>.1 then
            local result=workspace:Raycast(root.Position,delta.Unit*(delta.Magnitude+node.Size.Magnitude),params)
            if result and result.Instance==node then return result end
        end
    end
    return nil
end
local rubbleLastReport=""
local rubbleProgressTarget=nil
local rubbleProgressHealth=nil
local rubbleProgressAt=0
local function findRubble(root)
    if os.clock()<rubbleNextScan then
        if rubbleCache and rubbleCache.Parent and rubblePhysical(rubbleCache) then
            local hp=rubbleHealth(rubbleCache)
            if finite(hp) and hp>0 then return rubbleCache end
        end
        return nil
    end
    rubbleNextScan=os.clock()+1
    rubbleCache=nil
    local world=workspace:FindFirstChild("World")
    if not world then rubbleReason="World not loaded" return nil end
    local bestDistance=math.huge
    local seen={}
    local notes={}
    local function consider(node)
        if not node or seen[node] or not rubblePhysical(node) then return end
        seen[node]=true
        local hp=rubbleHealth(node)
        if #notes<10 then notes[#notes+1]=node:GetFullName().." HP="..tostring(hp) end
        if not finite(hp) or hp<=0 then return end
        local surface=rubbleSurface(root,node)
        if not surface then return end
        local distance=(surface.Position-root.Position).Magnitude
        if distance<bestDistance then rubbleCache,bestDistance=node,distance end
    end
    for _,node in ipairs(world:GetDescendants()) do
        if node.Name=="Rubble" then
            consider(node)
            for _,part in ipairs(node:GetDescendants()) do consider(part) end
        elseif finite(node:GetAttribute("RubbleHealth")) then
            local geometry=node:FindFirstChild("Rubble")
            if geometry then
                consider(geometry)
                for _,part in ipairs(geometry:GetDescendants()) do consider(part) end
            elseif node:IsA("BasePart") then consider(node) end
        end
    end
    rubbleReason=rubbleCache and ("Rubble: "..rubbleCache:GetFullName()) or "No visible, queryable rubble surface with positive HP found"
    local report=rubbleReason.." | "..table.concat(notes," | ").." | workspace HP="..tostring(workspace:GetAttribute("RubbleHealth"))
    if report~=rubbleLastReport then rubbleLastReport=report log(report) end
    return rubbleCache
end
local function rubbleTick(root,h)
    local rubble=findRubble(root)
    if not rubble then return false end
    local surface=rubbleSurface(root,rubble)
    if not surface then
        setAttack(false) stopMove()
        say("No ray hit on actual rubble mesh • waiting")
        return true
    end
    local hit=surface.Position
    local direction=Vector3.new(surface.Normal.X,0,surface.Normal.Z)
    if direction.Magnitude<.1 then direction=Vector3.new(root.Position.X-hit.X,0,root.Position.Z-hit.Z) end
    if direction.Magnitude<.1 then direction=Vector3.new(0,0,1) end
    local goal=hit+direction.Unit*1.8
    local arrived=hoverTo(root,h,hit,rubble,goal)
    if not arrived or (root.Position-hit).Magnitude>3.5 then
        rubbleProgressTarget=nil
        setAttack(false) say("Approaching rubble surface • "..string.format("%.1f",(root.Position-hit).Magnitude).." studs")
    else
        local hp=rubbleHealth(rubble)
        if rubbleProgressTarget~=rubble or rubbleProgressHealth~=hp then
            rubbleProgressTarget,rubbleProgressHealth,rubbleProgressAt=rubble,hp,os.clock()
        elseif os.clock()-rubbleProgressAt>20 then
            setAttack(false) stopMove()
            cfg.autoFarm=false changed()
            log("Rubble attack had no HP change for 20s: "..rubble:GetFullName().." HP="..tostring(hp))
            say("Rubble HP not changing • Auto Farm paused. Send COPY FULL ERROR.")
            return true
        end
        setAttack(true)
        say("Hitting rubble mesh • HP "..tostring(hp).." • "..string.format("%.1f",(root.Position-hit).Magnitude).." studs")
    end
    return true
end
local areaNav={scanAt=0,target=nil,goal=nil,since=0,stamp=nil,arrivedAt=nil}
local function visibleGui(node)
    while node and node~=pg do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("LayerCollector") and not node.Enabled then return false end
        node=node.Parent
    end
    return true
end
local function areaDestination(root)
    local world=workspace:FindFirstChild("World")
    local zones=world and world:FindFirstChild("Areas")
    local chip=pg:FindFirstChild("NextAreaChip",true)
    local wanted=nil
    if chip and visibleGui(chip) then
        for _,label in ipairs(chip:GetDescendants()) do
            if label:IsA("TextLabel") and visibleGui(label) then
                wanted=tonumber(string.match(string.upper(label.Text),"AREA%s+(%d+)"))
                if wanted then break end
            end
        end
    end
    local marker=workspace:FindFirstChild("NextAreaMarker",true)
    local markerPosition=nil
    if marker then
        if marker:IsA("Attachment") then markerPosition=marker.WorldPosition
        elseif marker:IsA("BasePart") then markerPosition=marker.Position
        elseif marker:IsA("Model") then markerPosition=marker:GetPivot().Position end
    end
    local zone=zones and wanted and zones:FindFirstChild(tostring(wanted))
    -- Use the game's displayed destination, never blindly increment the area.
    if zone and zone:IsA("BasePart") then
        local entries=world:FindFirstChild("AreaEntries")
        local entry=entries and entries:FindFirstChild(tostring(wanted))
        local point=markerPosition
        if entry and entry:IsA("BasePart") then point=entry.Position
        elseif entry and entry:IsA("Attachment") then point=entry.WorldPosition end
        point=point or root.Position
        local localPoint=zone.CFrame:PointToObjectSpace(point)
        local half=zone.Size*.5
        local ix=math.max(0,half.X-math.min(3,half.X*.5))
        local iz=math.max(0,half.Z-math.min(3,half.Z*.5))
        local localY=zone.CFrame:PointToObjectSpace(root.Position).Y
        local iy=math.max(0,half.Y-.1)
        local goal=zone.CFrame:PointToWorldSpace(Vector3.new(math.clamp(localPoint.X,-ix,ix),math.clamp(localY,-iy,iy),math.clamp(localPoint.Z,-iz,iz)))
        return zone,goal,"Area "..wanted
    end
    if markerPosition then return marker,markerPosition,"NextAreaMarker" end
    return nil,nil,"No active Next Area marker / numbered zone found"
end
local function nextAreaTick(root,h,state)
    if not cfg.autoNextArea then areaNav.arrivedAt=nil areaNav.target=nil areaNav.goal=nil areaNav.scanAt=0 return false end
    if type(modules.interface.rubbleArmed)=="function" and modules.interface.rubbleArmed() then
        areaNav.target=nil areaNav.goal=nil areaNav.arrivedAt=nil
        setAttack(false) stopMove() say("Next Area waiting • Rubble still armed") return true
    end
    local remaining=value(state.remaining)
    if finite(remaining) and remaining>0 then return false end
    local stamp=tostring(value(state.area)).."/"..tostring(value(state.wave))
    if areaNav.stamp~=stamp then
        areaNav={scanAt=0,target=nil,goal=nil,since=os.clock(),stamp=stamp,arrivedAt=nil}
    end
    if os.clock()>=areaNav.scanAt then
        areaNav.scanAt=os.clock()+1
        local target,goal,label=areaDestination(root)
        if target~=areaNav.target then
            areaNav.target,areaNav.goal,areaNav.label=target,goal,label
            areaNav.since=os.clock() areaNav.arrivedAt=nil
            if target then log("Next Area target: "..target:GetFullName().." / "..stamp) end
        end
        if not target then setAttack(false) stopMove() say(label) return true end
    end
    if not areaNav.target or not areaNav.target.Parent or not areaNav.goal then return false end
    setAttack(false)
    local goal=areaNav.goal
    local look=Vector3.new(goal.X-root.Position.X,0,goal.Z-root.Position.Z)
    if look.Magnitude<.1 then look=Vector3.new(0,0,-1) end
    local arrived=hoverTo(root,h,goal+look.Unit,areaNav.target,goal)
    if arrived then
        areaNav.arrivedAt=areaNav.arrivedAt or os.clock()
        say("Inside "..areaNav.label.." • waiting for game to start next wave")
        if os.clock()-areaNav.arrivedAt>15 then
            stopMove() cfg.autoNextArea=false changed()
            log("Area entry not confirmed after 15s: "..areaNav.target:GetFullName().." state="..stamp)
            say("Next Area did not start • Auto Next Area paused. Send diagnostics.")
        end
    else
        areaNav.arrivedAt=nil
        say("Tween to "..areaNav.label.." • "..math.floor((root.Position-goal).Magnitude).." studs")
    end
    return true
end
local retryKey=nil
local retryAttempts=0
local nextRetryAt=0
local voteKey=nil
local startVoteKey=nil
local function dungeonTick()
    local state=modules.run.store.state
    local participant=state.participants:get(tostring(player.UserId))
    if not participant then setAttack(false) stopMove() say("Waiting for dungeon participant data…") return end
    local endShown=modules.interface.endScreenShown()
    local active=modules.run.isActive(player)
    if endShown and not active then
        setAttack(false) stopMove()
        if not cfg.autoRetry then say("Round ended • Auto Retry OFF") return end
        if workspace:GetAttribute("Mode")=="tutorial" then say("Tutorial result • Retry unavailable in the game's UI") return end
        local stamp=tostring(value(participant.finishedAt) or value(state.finishedAt)).."/"..tostring(value(state.chapter))
        if stamp~=retryKey then retryKey=stamp retryAttempts=0 nextRetryAt=0 end
        local travel=value(participant.travelStatus)
        local vote=state.resultVotes:get(tostring(player.UserId))
        vote=value(vote)
        if vote==1 then prepareResume() say("Retry vote confirmed • waiting for the game") return end
        if travel~="idle" then prepareResume() say("Result travel: "..tostring(travel).." • waiting") return end
        if retryAttempts<2 and os.clock()>=nextRetryAt then
            prepareResume()
            modules.runPackets.endAction:fire(1)
            retryAttempts=retryAttempts+1 nextRetryAt=os.clock()+3
            say("Retry requested • waiting for vote confirmation")
        elseif retryAttempts>=2 then say("Retry not confirmed • check the game's result screen") end
        return
    end
    local startAt=workspace:GetAttribute("StartVoteEndsAt")
    if cfg.autoFarm and not endShown and finite(startAt) and startAt-workspace:GetServerTimeNow()>.15 and modules.interface.hudShown() then
        if not player:GetAttribute("StartVoted") and startVoteKey~=startAt then
            modules.runPackets.startVote:fire()
            startVoteKey=startAt
        end
        setAttack(false) stopMove() say("Start vote sent • waiting for the game") return
    end
    if not active or endShown then setAttack(false) stopMove() say("Waiting for active round…") return end
    retryKey=nil retryAttempts=0
    if not cfg.autoFarm then areaNav.arrivedAt=nil areaNav.target=nil areaNav.goal=nil areaNav.scanAt=0 rubbleProgressTarget=nil setAttack(false) stopMove() say("Dungeon ready • Auto Farm OFF") return end
    local untilAt=value(state.voteEndsAt)
    if finite(untilAt) and untilAt>workspace:GetServerTimeNow() then
        setAttack(false) stopMove()
        if voteKey~=untilAt then
            modules.runPackets.voteDifficulty:fire(cfg.difficulty)
            voteKey=untilAt
        end
        say("Difficulty vote sent • waiting for round start") return
    end
    local ch=player.Character
    local root=ch and ch:FindFirstChild("HumanoidRootPart")
    local h=ch and ch:FindFirstChildOfClass("Humanoid")
    if not root or not h or h.Health<=0 then setAttack(false) stopMove() say("Waiting for character / respawn…") return end
    local best,dist,bestName,bestId=nil,math.huge,"Enemy",nil
    local locked=nil
    local enemyState=modules.enemies.store.state
    for id in pairs(enemyState:getAll()) do
        local entry=enemyState:get(id)
        if entry then
            local hp=value(entry.health)
            local pos=value(entry.position)
            if finite(hp) and hp>0 and typeof(pos)=="Vector3" then
                local distance=(root.Position-pos).Magnitude
                if id==targetId then locked={position=pos,distance=distance,name=tostring(value(entry.name) or id),id=id} end
                if distance<dist then best,dist,bestName,bestId=pos,distance,tostring(value(entry.name) or id),id end
            end
        end
    end
    if locked then best,dist,bestName,bestId=locked.position,locked.distance,locked.name,locked.id end
    if not best then
        if cfg.autoRubble and rubbleTick(root,h) then return end
        if nextAreaTick(root,h,state) then return end
        setAttack(false) stopMove()
        say("Waiting for enemies…"..(cfg.autoRubble and (" • "..rubbleReason) or "")) return
    end
    local arrived=hoverTo(root,h,best,bestId)
    if not arrived then
        setAttack(false)
        say("Tween to "..bestName.." • "..math.floor(dist).." studs")
    elseif dist>cfg.range then
        setAttack(false)
        say("Hovering too far to attack • lower Hover height or adjust Attack distance")
    else
        skillTick()
        setAttack(not skillBusy)
        say("Hover + attack: "..bestName..(cfg.autoSkill and " • Auto Skill ON" or ""))
    end
end
local function findQueuePad(root)
    local systems=workspace:FindFirstChild("Systems")
    local rooms=systems and systems:FindFirstChild("QuqueRooms")
    if not rooms then return nil,"QuqueRooms not loaded; waiting…" end
    local best,bestDistance=nil,math.huge
    for _,room in ipairs(rooms:GetChildren()) do
        local hitbox=room:FindFirstChild("JoinHitbox",true)
        if hitbox and hitbox:IsA("BasePart") and not triedPads[hitbox] then
            local available=false
            for _,label in ipairs(room:GetDescendants()) do
                if label:IsA("TextLabel") and label.Text=="Start Here" then
                    local visible=true
                    local node=label
                    while node and node~=room do
                        if node:IsA("GuiObject") and not node.Visible then visible=false break end
                        if node:IsA("LayerCollector") and not node.Enabled then visible=false break end
                        node=node.Parent
                    end
                    if visible then available=true break end
                end
            end
            if available then
                for _,other in ipairs(Players:GetPlayers()) do
                    local otherRoot=other~=player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
                    if otherRoot then
                        local offset=hitbox.CFrame:PointToObjectSpace(otherRoot.Position)
                        local half=hitbox.Size*.5
                        if math.abs(offset.X)<half.X+1 and math.abs(offset.Z)<half.Z+1 and math.abs(offset.Y)<half.Y+4 then available=false break end
                    end
                end
            end
            local distance=(hitbox.Position-root.Position).Magnitude
            if available and distance<bestDistance then best,bestDistance=hitbox,distance end
        end
    end
    return best,"No available Start Here pad loaded; waiting…"
end
local function lobbyTick()
    if not cfg.autoQueue then padAttemptAt=nil stopMove() return end
    if queueBlocked then stopMove() return end
    if lobbyStage=="queued" then startRoom() return end
    if queuePending or lobbyStage=="starting" or lobbyStage=="teleporting" then stopMove() return end
    if packetRoom~=nil then stopMove() createRoom() return end
    local ch=player.Character
    local root=ch and ch:FindFirstChild("HumanoidRootPart")
    local h=ch and ch:FindFirstChildOfClass("Humanoid")
    if not root or not h or h.Health<=0 then padAttemptAt=nil return end
    if padAttemptAt~=nil then
        if os.clock()-padAttemptAt<=8 then say("At queue pad • waiting for game room signal…") return end
        padAttemptAt=nil
        local attempts=0
        for _ in pairs(triedPads) do attempts=attempts+1 end
        log("No room signal after warp; attempts: "..attempts)
        if attempts>=3 then
            cfg.autoQueue=false queueBlocked=true changed()
            say("No room signal from 3 pads. Auto Queue stopped; send diagnostics.") return
        end
    end
    if os.clock()<nextPadScan then return end
    nextPadScan=os.clock()+2
    local hitbox,reason=findQueuePad(root)
    if not hitbox then say(reason) return end
    stopMove()
    h:Move(Vector3.zero)
    root.CFrame=root.CFrame+(hitbox.Position-root.Position)
    root.AssemblyLinearVelocity=Vector3.zero
    root.AssemblyAngularVelocity=Vector3.zero
    triedPads[hitbox]=true
    padAttemptAt=os.clock()
    log("Warped to "..hitbox:GetFullName().."; waiting for room signal")
    say("Warped into Start Here pad • waiting for Create menu…")
end

local route=nil
local routeGoal=nil
local waypoint=1
local computing=false
local lastCompute=0
local moveGeneration=0
local lastPosition=nil
local lastProgress=os.clock()
task.spawn(function()
    while alive do
        local ok,err=pcall(function()
            local goal=navigationGoal
            local ch=player.Character
            local root=ch and ch:FindFirstChild("HumanoidRootPart")
            local h=ch and ch:FindFirstChildOfClass("Humanoid")
            if not goal or not root or not h or h.Health<=0 then
                route=nil routeGoal=nil moveGeneration=moveGeneration+1 lastPosition=nil return
            end
            if not computing and os.clock()-lastCompute>1.2 and (not routeGoal or (goal-routeGoal).Magnitude>5 or not route) then
                computing=true lastCompute=os.clock()
                local generation=moveGeneration
                local start=root.Position
                task.spawn(function()
                    local success,result=pcall(function()
                        local path=PFS:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4})
                        path:ComputeAsync(start,goal)
                        if path.Status==Enum.PathStatus.Success then return path:GetWaypoints() end
                        return nil
                    end)
                    computing=false
                    if alive and navigationGoal and generation==moveGeneration then
                        route=success and result or nil routeGoal=goal waypoint=2
                    end
                end)
            end
            local target=goal
            if route and route[waypoint] then
                while route[waypoint] and (root.Position-route[waypoint].Position).Magnitude<3 do waypoint=waypoint+1 end
                if route[waypoint] then
                    target=route[waypoint].Position
                    if route[waypoint].Action==Enum.PathWaypointAction.Jump then h.Jump=true end
                end
            end
            h:MoveTo(target)
            if not lastPosition or (lastPosition-root.Position).Magnitude>1 then lastPosition=root.Position lastProgress=os.clock() end
            if os.clock()-lastProgress>2 then h.Jump=true route=nil lastProgress=os.clock() end
        end)
        if not ok then pauseError(err) end
        task.wait(.1)
    end
end)
task.spawn(function()
    local ok,err=pcall(function()
        local ps=player:WaitForChild("PlayerScripts",20)
        assert(ps,"PlayerScripts unavailable")
        -- Controls loading cannot block queue/retry/module setup.
        task.spawn(function()
            local success,reason=pcall(function()
                local pm=ps:FindFirstChild("PlayerModule")
                if not pm then log("PlayerModule absent; direct Humanoid + Tween enabled") return end
                local loaded=boundedRequire(pm)
                assert(type(loaded.GetControls)=="function","GetControls unavailable")
                local result=loaded:GetControls()
                assert(result and type(result.Disable)=="function" and type(result.Enable)=="function","Invalid controls API")
                if alive then controls=result log("Player controls ready") end
            end)
            if not success then log("Optional controls failed; using direct Humanoid + Tween: "..tostring(reason)) end
        end)
        local deadline=os.clock()+30
        while alive and os.clock()<deadline do
            local run=RS:FindFirstChild("game")
            local lobby=RS:FindFirstChild("lobby")
            local scripts=ps:FindFirstChild("game")
            if run and scripts then context="Dungeon" break end
            if lobby and ps:FindFirstChild("lobby") then context="Lobby" break end
            task.wait(.25)
        end
        if not alive then return end
        if context=="Dungeon" then setupDungeon()
        elseif context=="Lobby" then setupLobby()
        else error("Unsupported place; lobby/dungeon modules were not found") end
        if not alive then return end
        ready=true log(context.." modules ready") refresh()
        say(context.." ready • previous config loaded")
    end)
    if not ok then pauseError(err) end
end)
task.spawn(function()
    while alive do
        if configDirty and os.clock()-savedAt>.4 then saveConfig() end
        if ready then
            local ok,err=pcall(function()
                if context=="Dungeon" then dungeonTick() else lobbyTick() end
            end)
            if not ok then ready=false pauseError(err) end
        end
        if alive then
            local camera=workspace.CurrentCamera
            if camera then
                local v=camera.ViewportSize
                scale.Scale=math.max(.35,math.min(1,(v.X-24)/380,(v.Y-52)/490))
            end
            status.Text=context.." • "..stage
            skillStatus.Text=skillMessage
            diskLabel.Text=configMessage
            resumeLabel.Text="Teleport resume: "..(cfg.resumeTeleport and resumeMessage or "OFF")
        end
        task.wait(.15)
    end
end)
]====]
local env=type(getgenv)=="function" and getgenv() or _G
local wf=env.writefile or writefile
local rf=env.readfile or readfile
local mf=env.makefolder or makefolder
local isf=env.isfolder or isfolder
local installed,installError=pcall(function()
    assert(type(wf)=="function" and type(rf)=="function","File access unavailable; Config/teleport resume may not work")
    if not (type(isf)=="function" and isf("KrittaxAnimeZero")) and type(mf)=="function" then
        pcall(mf,"KrittaxAnimeZero")
    end
    wf("KrittaxAnimeZero/main.lua",SOURCE)
    assert(rf("KrittaxAnimeZero/main.lua")==SOURCE,"Script file verification failed")
end)
if not installed then warn("Krittax installation: "..tostring(installError)) end
local loader=env.loadstring or loadstring
assert(type(loader)=="function","loadstring unavailable in this environment")
local fn,err=loader(SOURCE,"@KrittaxAnimeZero/main.lua")
assert(fn,err)
fn()
