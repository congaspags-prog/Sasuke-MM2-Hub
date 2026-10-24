-- SASUKE MM2 HUB | SHARINGAN EDITION v1.0
-- Interface mobile • Aim/FOV • Silent Aim experimental • ESP de roles e GunDrop
-- Nao utiliza scripts externos, coleta de dados, tokens, webhooks ou auto farm.
-- Este arquivo inclui imagens enviadas pelo usuario (base64 no final).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer
if not LP then return end

local env = (type(getgenv)=="function" and getgenv()) or _G
if type(env.SasukeMM2) == "table" and type(env.SasukeMM2.Close) == "function" then
    pcall(env.SasukeMM2.Close)
end

local C = {
    bg=Color3.fromRGB(10, 9, 13), panel=Color3.fromRGB(24, 17, 23),
    accent=Color3.fromRGB(205, 28, 42), accent2=Color3.fromRGB(105, 19, 35),
    text=Color3.fromRGB(248, 241, 243), secondary=Color3.fromRGB(179, 157, 167),
    off=Color3.fromRGB(70, 49, 58), sheriff=Color3.fromRGB(68, 155, 255),
    murderer=Color3.fromRGB(246, 50, 65), innocent=Color3.fromRGB(224, 218, 239),
    gun=Color3.fromRGB(255, 208, 72)
}

local default = {
    aim=false, silent=false, showFOV=true, fov=140, smooth=30, wall=true,
    innocentESP=false, sheriffESP=false, murderESP=false, gunESP=false,
    espNames=true, low=true, background=true,
}
local cfg={}
for k,v in pairs(default) do cfg[k]=v end
local cfgPath="Sasuke_MM2_v1.json"
local storage=type(readfile)=="function" and type(writefile)=="function"
if storage then
    pcall(function()
        local old=HttpService:JSONDecode(readfile(cfgPath))
        if type(old)=="table" then
            for k,v in pairs(default) do
                if type(old[k])==type(v) then cfg[k]=old[k] end
            end
        end
    end)
end
-- Os modos de combate nao iniciam automaticamente apos outro crash.
cfg.aim=false
cfg.silent=false
cfg.fov=math.clamp(math.floor(cfg.fov),60,320)
cfg.smooth=math.clamp(math.floor(cfg.smooth),5,100)

local alive=true
local connections={}
local espObjects={}
local espChars={}
local roleMemory={}
local weaponType="NONE"
local targetPlayer=nil
local lastGun=nil
local lastError=""
local assetOK=false

local function connect(signal, fn)
    local x=signal:Connect(fn)
    table.insert(connections,x)
    return x
end
local function mk(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local function corner(obj,r)
    mk("UICorner",obj,{CornerRadius=UDim.new(0,r or 8)})
end
local function stroke(obj, color, width)
    return mk("UIStroke",obj,{Color=color or C.accent,Thickness=width or 1,Transparency=.12})
end
local function save()
    if storage then pcall(function() writefile(cfgPath,HttpService:JSONEncode(cfg)) end) end
end

local function getToolRole(root)
    if not root then return nil end
    for _,obj in ipairs(root:GetChildren()) do
        if obj:IsA("Tool") then
            local n=obj.Name:lower()
            if n=="knife" or n:find("knife",1,true) then return "Murderer" end
            if n=="gun" or n:find("revolver",1,true) then return "Sheriff" end
        end
    end
    return nil
end
local function getRole(plr)
    if not plr then return "Unknown" end
    local char=plr.Character
    if not char then return "Unknown" end
    local mem=roleMemory[plr]
    if mem and mem.character~=char then mem=nil roleMemory[plr]=nil end
    local attr=plr:GetAttribute("Role") or char:GetAttribute("Role")
    if attr=="Murderer" or attr=="Sheriff" or attr=="Innocent" then
        roleMemory[plr]={character=char, role=attr}
        return attr
    end
    local role=getToolRole(char)
    if role then
        roleMemory[plr]={character=char,role=role}
        return role
    end
    if mem then return mem.role end
    -- Sem ferramenta visivel, nao e possivel confirmar que e inocente.
    return "Unknown"
end
local function localWeapon()
    local role=getToolRole(LP.Character)
    if role=="Sheriff" then return "GUN" end
    if role=="Murderer" then return "KNIFE" end
    return "NONE"
end
local function alivePart(plr)
    local ch=plr and plr.Character
    if not ch then return nil end
    local hum=ch:FindFirstChildWhichIsA("Humanoid")
    if not hum or hum.Health<=0 then return nil end
    return ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
end
local function visibleToCamera(ch,aimPos,camera)
    if not cfg.wall then return true end
    local from=camera.CFrame.Position
    local v=aimPos-from
    if v.Magnitude < .01 then return true end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={LP.Character,camera}
    params.IgnoreWater=true
    local hit=Workspace:Raycast(from,v,params)
    return not hit or (ch and hit.Instance:IsDescendantOf(ch))
end
local function selectTarget()
    local cam=Workspace.CurrentCamera
    if not cam or weaponType=="NONE" then return nil end
    local vp=cam.ViewportSize
    local center=Vector2.new(vp.X/2,vp.Y/2)
    local best,bestScore=nil,cfg.fov
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=LP then
            local part=alivePart(plr)
            if part then
                local role=getRole(plr)
                local allowed=(weaponType=="GUN" and role=="Murderer")
                    or (weaponType=="KNIFE" and role~="Murderer")
                if allowed then
                    local pt,onScreen=cam:WorldToViewportPoint(part.Position)
                    if onScreen and pt.Z>0 then
                        local d=(Vector2.new(pt.X,pt.Y)-center).Magnitude
                        if d<bestScore and visibleToCamera(plr.Character,part.Position,cam) then
                            bestScore=d
                            best=plr
                        end
                    end
                end
            end
        end
    end
    return best
end
local function aimPosition(part)
    if not part then return nil end
    local cam=Workspace.CurrentCamera
    if not cam then return part.Position end
    local t=math.clamp((part.Position-cam.CFrame.Position).Magnitude/360,0,.22)
    return part.Position + part.AssemblyLinearVelocity * t
end

-- Silent Aim usa uma interceptacao restrita aos remotes conhecidos: ShootGun e Throw.
-- Nao injeta disparos; so ajusta a posicao fornecida quando o jogador dispara.
-- Caso o jogo mude os argumentos, a funcao pode nao ter efeito.
local hookState=env.SasukeMM2SilentHook
if type(hookState)~="table" then
    hookState={installed=false,owner=nil}
    env.SasukeMM2SilentHook=hookState
end
local function setupSilentHook()
    if hookState.installed then return true end
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then
        lastError="Silent Aim nao suportado pelo executor"
        return false
    end
    local ok,err=pcall(function()
        local old
        local interceptor=function(self,...)
            local owner=hookState.owner
            if owner and owner.Enabled() and (type(checkcaller)~="function" or not checkcaller()) then
                local m=getnamecallmethod()
                local name=self.Name
                if (name=="ShootGun" and m=="InvokeServer") or
                   (name=="Throw" and m=="FireServer") then
                    local pos=owner.PositionFor(name)
                    if pos then
                        local args={...}
                        -- Remotes conhecidos do MM2 enviam uma posicao como segundo argumento.
                        if typeof(args[2])=="Vector3" then
                            args[2]=pos
                            return old(self,table.unpack(args))
                        end
                    end
                end
            end
            return old(self,...)
        end
        old=hookmetamethod(game,"__namecall",
            type(newcclosure)=="function" and newcclosure(interceptor) or interceptor)
        if not old then error("hook sem retorno") end
    end)
    if not ok then
        lastError="Falha no Silent Aim: "..tostring(err):sub(1,80)
        return false
    end
    hookState.installed=true
    return true
end
hookState.owner={
    Enabled=function() return alive and cfg.silent end,
    PositionFor=function(remoteName)
        if not alive or not cfg.silent then return nil end
        if remoteName=="ShootGun" and weaponType~="GUN" then return nil end
        if remoteName=="Throw" and weaponType~="KNIFE" then return nil end
        local p=alivePart(targetPlayer)
        return aimPosition(p)
    end
}

-- Imagens integradas ao arquivo para funcionar com uma unica colagem de codigo.
-- Precisam de writefile/getcustomasset; sem suporte, aparece o tema nativo.
local function b64decode(data)
    local abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup={}
    for i=1,#abc do lookup[abc:sub(i,i)]=i-1 end
    local out={}
    local n=0
    for i=1,#data,4 do
        local a=lookup[data:sub(i,i)]
        local b=lookup[data:sub(i+1,i+1)]
        local c=lookup[data:sub(i+2,i+2)]
        local d=lookup[data:sub(i+3,i+3)]
        if a and b then
            local x=a*262144+b*4096+(c or 0)*64+(d or 0)
            n=n+1
            out[n]=string.char(math.floor(x/65536)%256)
            if c then n=n+1 out[n]=string.char(math.floor(x/256)%256) end
            if d then n=n+1 out[n]=string.char(x%256) end
        end
    end
    return table.concat(out)
end
local function localImage(path,encoded)
    if type(writefile)~="function" or type(getcustomasset)~="function" then return nil end
    local ok,result=pcall(function()
        local found=type(isfile)=="function" and isfile(path)
        if not found then writefile(path,b64decode(encoded)) end
        return getcustomasset(path)
    end)
    if ok and type(result)=="string" then return result end
end
local LOGO_B64 = [=[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]=]
local BACK_B64 = [=[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]=]
local logoAsset=localImage("SasukeMM2_Sharingan.jpg",LOGO_B64)
local backAsset=localImage("SasukeMM2_Background.jpg",BACK_B64)
assetOK=(logoAsset~=nil and backAsset~=nil)
LOGO_B64=nil
BACK_B64=nil

local gui=mk("ScreenGui",nil,{Name="SasukeMM2Hub",ResetOnSpawn=false,
    IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local parented=pcall(function()
    if type(gethui)=="function" then gui.Parent=gethui() else gui.Parent=CoreGui end
end)
if not parented then gui.Parent=LP:WaitForChild("PlayerGui") end
local window=mk("Frame",gui,{Name="Window",BackgroundColor3=C.bg,
    Size=UDim2.fromOffset(322,430),Position=UDim2.new(.5,-161,.5,-215),
    BorderSizePixel=0,ClipsDescendants=true,Active=true})
corner(window,13)
stroke(window,C.accent,1.4)
local back=mk("ImageLabel",window,{Name="SasukeBackground",BackgroundTransparency=1,
    Size=UDim2.fromScale(1,1),Image=backAsset or "",ImageTransparency=.72,
    ScaleType=Enum.ScaleType.Crop,Visible=cfg.background and (backAsset~=nil),ZIndex=1})
mk("Frame",window,{Name="DarkOverlay",BackgroundColor3=C.bg,BackgroundTransparency=.48,
    BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=2})
local header=mk("Frame",window,{Name="Header",BackgroundColor3=C.panel,
    BackgroundTransparency=.06,BorderSizePixel=0,Size=UDim2.new(1,0,0,52),ZIndex=4,Active=true})
corner(header,12)
local logo=mk("ImageLabel",header,{Name="SharinganLogo",Position=UDim2.fromOffset(8,7),
    Size=UDim2.fromOffset(38,38),BackgroundColor3=C.bg,Image=logoAsset or "",
    ZIndex=6})
corner(logo,19)
if not logoAsset then mk("TextLabel",logo,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    Text="◎",TextColor3=C.accent,TextSize=32,Font=Enum.Font.GothamBold,ZIndex=7}) end
mk("TextLabel",header,{Position=UDim2.fromOffset(53,6),Size=UDim2.fromOffset(180,23),
    BackgroundTransparency=1,Text="SASUKE  MM2",TextColor3=C.text,
    Font=Enum.Font.GothamBold,TextSize=16,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=6})
mk("TextLabel",header,{Position=UDim2.fromOffset(53,29),Size=UDim2.fromOffset(180,16),
    BackgroundTransparency=1,Text="SHARINGAN EDITION  •  V1.0",TextColor3=C.secondary,
    Font=Enum.Font.GothamMedium,TextSize=9,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=6})
local function headButton(label,x)
    local b=mk("TextButton",header,{Position=UDim2.fromOffset(x,12),Size=UDim2.fromOffset(25,26),
        BackgroundColor3=C.off,Text=label,TextColor3=C.text,
        Font=Enum.Font.GothamBold,TextSize=16,ZIndex=7})
    corner(b,6)
    return b
end
local minBtn=headButton("−",262)
local closeBtn=headButton("×",291)

local tabs=mk("Frame",window,{Position=UDim2.fromOffset(8,61),Size=UDim2.fromOffset(306,36),
    BackgroundTransparency=1,ZIndex=5})
local views=mk("Frame",window,{Position=UDim2.fromOffset(9,104),
    Size=UDim2.fromOffset(304,306),BackgroundTransparency=1,ZIndex=5})
local tabItems={}
local panes={}
local activeTab="AIM"
local tabNames={"AIM","ESP","VISUAL","CONFIG"}
local function showTab(name)
    activeTab=name
    for tab,entry in pairs(tabItems) do
        entry.BackgroundColor3=(name==tab) and C.accent or C.panel
    end
    for tab,p in pairs(panes) do p.Visible=(tab==name) end
end
for i,name in ipairs(tabNames) do
    local b=mk("TextButton",tabs,{Position=UDim2.fromOffset((i-1)*78,0),
        Size=UDim2.fromOffset(72,34),Text=name,BackgroundColor3=C.panel,
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.text,ZIndex=6})
    corner(b,8)
    tabItems[name]=b
    connect(b.MouseButton1Click,function() showTab(name) end)
    local scroll=mk("ScrollingFrame",views,{BackgroundTransparency=1,
        Size=UDim2.fromScale(1,1),CanvasSize=UDim2.fromOffset(0,300),
        ScrollBarThickness=2,ScrollBarImageColor3=C.accent,
        BorderSizePixel=0,ZIndex=5,Visible=false,ScrollingDirection=Enum.ScrollingDirection.Y})
    local list=mk("UIListLayout",scroll,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,7)})
    connect(list:GetPropertyChangedSignal("AbsoluteContentSize"),function()
        scroll.CanvasSize=UDim2.fromOffset(0,list.AbsoluteContentSize.Y+8)
    end)
    panes[name]=scroll
end
local orderByPane={}
local function makeRow(parent,title,desc)
    orderByPane[parent]=(orderByPane[parent] or 0)+1
    local row=mk("Frame",parent,{BackgroundColor3=C.panel,BackgroundTransparency=.12,
        Size=UDim2.new(1,-5,0,52),BorderSizePixel=0,ZIndex=6,
        LayoutOrder=orderByPane[parent]})
    corner(row,8)
    mk("TextLabel",row,{Position=UDim2.fromOffset(10,5),Size=UDim2.new(1,-92,0,23),
        BackgroundTransparency=1,Text=title,TextColor3=C.text,TextSize=12,
        Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=7})
    mk("TextLabel",row,{Position=UDim2.fromOffset(10,28),Size=UDim2.new(1,-92,0,18),
        BackgroundTransparency=1,Text=desc,TextColor3=C.secondary,TextSize=9,
        Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=7})
    return row
end
local notes={}
local function toggle(parent,key,title,desc,onToggle)
    local row=makeRow(parent,title,desc)
    local b=mk("TextButton",row,{Position=UDim2.new(1,-67,.5,-15),
        Size=UDim2.fromOffset(57,30),BackgroundColor3=C.off,
        Text="OFF",TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=11,ZIndex=8})
    corner(b,7)
    local function draw()
        b.Text=cfg[key] and "ON" or "OFF"
        b.BackgroundColor3=cfg[key] and C.accent or C.off
    end
    draw()
    connect(b.MouseButton1Click,function()
        local wanted=not cfg[key]
        if onToggle and wanted and not onToggle() then return end
        cfg[key]=wanted
        draw()
        save()
    end)
    notes[key]=draw
    return row
end
local function numeric(parent,key,title,desc,min,max,step,suffix)
    local row=makeRow(parent,title,desc)
    local minus=mk("TextButton",row,{Position=UDim2.new(1,-91,.5,-13),
        Size=UDim2.fromOffset(23,26),BackgroundColor3=C.off,
        Text="−",TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=14,ZIndex=8})
    local lbl=mk("TextLabel",row,{Position=UDim2.new(1,-66,.5,-13),
        Size=UDim2.fromOffset(39,26),BackgroundTransparency=1,
        TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=10,ZIndex=8})
    local plus=mk("TextButton",row,{Position=UDim2.new(1,-27,.5,-13),
        Size=UDim2.fromOffset(22,26),BackgroundColor3=C.off,
        Text="+",TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=14,ZIndex=8})
    corner(minus,5) corner(plus,5)
    local function set(v)
        cfg[key]=math.clamp(v,min,max)
        lbl.Text=tostring(cfg[key])..(suffix or "")
        save()
    end
    lbl.Text=tostring(cfg[key])..(suffix or "")
    connect(minus.MouseButton1Click,function() set(cfg[key]-step) end)
    connect(plus.MouseButton1Click,function() set(cfg[key]+step) end)
end
local function info(parent,title,desc)
    local row=makeRow(parent,title,desc)
    return row
end

-- AIM e aba principal. Um mesmo Aimbot escolhe o alvo conforme Gun ou Knife.
toggle(panes.AIM,"aim","AIMBOT SHERIFF + MURDER","Mira assistida para arma/faca")
toggle(panes.AIM,"silent","SILENT AIM (BETA)","Ativado sob demanda; pode nao funcionar",setupSilentHook)
numeric(panes.AIM,"fov","FOV DO AIM","Raio em pixels",60,320,20,"px")
toggle(panes.AIM,"showFOV","MOSTRAR CIRCULO","Circulo vermelho no centro da tela")
numeric(panes.AIM,"smooth","SUAVIZACAO","5 = lento  /  100 = rapido",5,100,5,"")
toggle(panes.AIM,"wall","CHECAR PAREDE","Nao selecionar alvos ocultos")
info(panes.AIM,"ALVO AUTOMATICO","Sheriff: Murder | Murder: nao-Murder")

-- ESP: papéis não revelados aparecem como "?"; nao inventamos role.
toggle(panes.ESP,"innocentESP","ESP INOCENTE / ?","Sem papel confirmado aparece como ?")
toggle(panes.ESP,"sheriffESP","ESP SHERIFF","Azul | papel detectado")
toggle(panes.ESP,"murderESP","ESP MURDER","Vermelho | papel detectado")
toggle(panes.ESP,"gunESP","ESP GUN DROPPED","Arma caida no mapa em amarelo")
toggle(panes.ESP,"espNames","NOMES + PAPEIS","Exibir legenda acima dos jogadores")

-- VISUAL
toggle(panes.VISUAL,"background","FUNDO DO SASUKE","Usa a foto enviada se for suportada",function() return true end)
info(panes.VISUAL,"SHARINGAN DO HUB",assetOK and "Imagem original carregada" or "Icone alternativo ativo; requer getcustomasset")
info(panes.VISUAL,"TEMA VERMELHO / PRETO","Com fundo escuro, desenhado para celular")

-- CONFIG
toggle(panes.CONFIG,"low","MODO LEVE","Reduz consultas ao mapa e atualizacoes")
info(panes.CONFIG,"CONFIG SALVA AUTOMATICAMENTE",storage and "Disponivel: configuracoes salvas" or "Sem suporte a arquivos neste executor")
info(panes.CONFIG,"COMPATIBILIDADE","Silent Aim experimental; testes necessarios")
info(panes.CONFIG,"SEGURANCA","AIM e Silent Aim iniciam OFF")

local status=mk("TextLabel",window,{Position=UDim2.fromOffset(12,414),
    Size=UDim2.fromOffset(298,12),BackgroundTransparency=1,Text="Iniciando...",
    TextXAlignment=Enum.TextXAlignment.Center,TextColor3=C.secondary,
    Font=Enum.Font.GothamMedium,TextSize=10,ZIndex=7})

local fovCircle=mk("Frame",gui,{Name="AimFOV",AnchorPoint=Vector2.new(.5,.5),
    BackgroundTransparency=1,Size=UDim2.fromOffset(cfg.fov*2,cfg.fov*2),
    BorderSizePixel=0,Visible=false,ZIndex=30})
mk("UICorner",fovCircle,{CornerRadius=UDim.new(1,0)})
stroke(fovCircle,C.accent,1.5)

local minimized=false
local moving=false
local moveStart=nil
local windowStart=nil
local moveInput=nil
connect(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        moving=true
        moveStart=input.Position
        windowStart=window.Position
        moveInput=input
    end
end)
connect(UIS.InputChanged,function(input)
    if moving and moveStart and windowStart and
        (input==moveInput or (moveInput and moveInput.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseMovement)) then
        local d=input.Position-moveStart
        window.Position=UDim2.new(windowStart.X.Scale,windowStart.X.Offset+d.X,
            windowStart.Y.Scale,windowStart.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input==moveInput then moving=false moveInput=nil end
end)
connect(minBtn.MouseButton1Click,function()
    minimized=not minimized
    window.Size=UDim2.fromOffset(322,minimized and 52 or 430)
    minBtn.Text=minimized and "+" or "−"
end)
showTab("AIM")

local espGui=mk("Folder",gui,{Name="ESPGui"})
local function clearESP(plr)
    local old=espObjects[plr]
    if old then old:Destroy() espObjects[plr]=nil end
    espChars[plr]=nil
end
local function espColor(role)
    if role=="Murderer" then return C.murderer end
    if role=="Sheriff" then return C.sheriff end
    return C.innocent
end
local function updateESP()
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=LP then
            local ch=plr.Character
            local part=alivePart(plr)
            local role=getRole(plr)
            local show=part and ((role=="Murderer" and cfg.murderESP)
                or (role=="Sheriff" and cfg.sheriffESP)
                or ((role=="Unknown" or role=="Innocent") and cfg.innocentESP))
            if not show then
                clearESP(plr)
            else
                local entry=espObjects[plr]
                if not entry or entry.Parent~=espGui or espChars[plr]~=ch then
                    clearESP(plr)
                    -- highlight + legenda; nenhuma fisica ou colisao adicionada
                    entry=mk("Folder",espGui,{Name="ESP_"..plr.Name})
                    -- Personagem rastreado por referencia (sem APIs restritas).
                    espObjects[plr]=entry
                    espChars[plr]=ch
                    mk("Highlight",entry,{Name="Highlight",Adornee=ch,
                        DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
                        FillTransparency=.82,OutlineTransparency=0})
                    local b=mk("BillboardGui",entry,{Name="Label",Adornee=part,
                        Size=UDim2.fromOffset(170,26),StudsOffset=Vector3.new(0,2.7,0),
                        AlwaysOnTop=true,Enabled=cfg.espNames})
                    mk("TextLabel",b,{Size=UDim2.fromScale(1,1),
                        BackgroundTransparency=1,TextScaled=false,TextSize=12,
                        Font=Enum.Font.GothamBold,TextStrokeTransparency=.22})
                end
                local color=espColor(role)
                local h=entry:FindFirstChild("Highlight")
                local b=entry:FindFirstChild("Label")
                if h then h.FillColor=color h.OutlineColor=color h.Adornee=ch end
                if b then
                    b.Adornee=part b.Enabled=cfg.espNames
                    local t=b:FindFirstChildWhichIsA("TextLabel")
                    if t then
                        t.TextColor3=color
                        t.Text=plr.DisplayName.." | "..(role=="Unknown" and "?" or role)
                    end
                end
            end
        end
    end
end
connect(Players.PlayerRemoving,function(plr)
    clearESP(plr)
    roleMemory[plr]=nil
end)

-- GunDrop: a maior parte das versoes expõe um objeto com esse nome no mapa.
local gunESP=mk("Highlight",espGui,{Name="GunHighlight",FillColor=C.gun,
    OutlineColor=C.gun,FillTransparency=.55,OutlineTransparency=0,
    Enabled=false,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop})
local gunMarker=mk("BillboardGui",espGui,{Name="GunLabel",Size=UDim2.fromOffset(140,26),
    StudsOffset=Vector3.new(0,1.7,0),AlwaysOnTop=true,Enabled=false})
mk("TextLabel",gunMarker,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    Font=Enum.Font.GothamBold,TextSize=12,Text="GUN DROPPED",
    TextColor3=C.gun,TextStrokeTransparency=.25})
local knownGun=setmetatable({},{__mode="k"})
local function isDroppedGun(obj)
    if not obj or not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n=obj.Name:lower()
    return n=="gundrop" or n=="droppedgun" or n=="dropped_gun"
end
local function trackGun(obj)
    if isDroppedGun(obj) then knownGun[obj]=true end
end
connect(Workspace.DescendantAdded,trackGun)
-- Busca inicial apenas pelo nome; sem criar enorme tabela de Descendants.
task.defer(function()
    local ok,gun=pcall(function()
        return Workspace:FindFirstChild("GunDrop",true)
            or Workspace:FindFirstChild("DroppedGun",true)
            or Workspace:FindFirstChild("Dropped_Gun",true)
    end)
    if ok and gun and alive then trackGun(gun) end
end)
local function updateGun()
    if not cfg.gunESP then gunESP.Enabled=false gunMarker.Enabled=false return end
    local root=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local nearest,dist=nil,math.huge
    local origin=root and root.Position or Vector3.zero
    for obj in pairs(knownGun) do
        if obj.Parent and obj:IsDescendantOf(Workspace) then
            local part=obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart",true)
            if part then
                local d=(part.Position-origin).Magnitude
                if d<dist then nearest=obj dist=d end
            end
        else
            knownGun[obj]=nil
        end
    end
    lastGun=nearest
    gunESP.Adornee=nearest
    gunESP.Enabled=(nearest~=nil)
    gunMarker.Adornee=nearest
    gunMarker.Enabled=(nearest~=nil)
end

local espClock=0
local aimClock=0
local slowClock=0
local function runUpdate(dt)
    if not alive then return end
    weaponType=localWeapon()
    local cam=Workspace.CurrentCamera
    if cam then
        local vp=cam.ViewportSize
        fovCircle.Position=UDim2.fromOffset(vp.X*.5,vp.Y*.5)
        local diameter=cfg.fov*2
        if fovCircle.Size.X.Offset~=diameter then
            fovCircle.Size=UDim2.fromOffset(diameter,diameter)
        end
    end
    fovCircle.Visible=(cfg.aim or cfg.silent) and cfg.showFOV and cam~=nil
    aimClock=aimClock+dt
    espClock=espClock+dt
    slowClock=slowClock+dt
    if aimClock >= (cfg.low and .18 or .10) then
        aimClock=0
        targetPlayer=(cfg.aim or cfg.silent) and selectTarget() or nil
    end
    if espClock >= (cfg.low and 1.0 or .5) then
        espClock=0
        pcall(updateESP)
        pcall(updateGun)
    end
    if slowClock >= .7 then
        slowClock=0
        local targetName=targetPlayer and targetPlayer.DisplayName or "nenhum"
        status.Text="WEAPON: "..weaponType.."  |  ALVO: "..targetName
        if cfg.background then back.Visible=(backAsset~=nil) else back.Visible=false end
    end
    if cfg.aim and cam and targetPlayer then
        local part=alivePart(targetPlayer)
        if part then
            local pos=aimPosition(part)
            local goal=CFrame.lookAt(cam.CFrame.Position,pos)
            local alpha=1-math.exp(-(cfg.smooth/8)*dt)
            cam.CFrame=cam.CFrame:Lerp(goal,math.clamp(alpha,0,1))
        end
    end
end
connect(RunService.RenderStepped,function(dt)
    if not alive then return end
    local ok,err=pcall(runUpdate,dt)
    if not ok then
        lastError=tostring(err)
        cfg.aim=false
        cfg.silent=false
        if notes.aim then notes.aim() end
        if notes.silent then notes.silent() end
        status.Text="AIM pausado por erro. Reinicie o hub."
    end
end)

local function close()
    if not alive then return end
    alive=false
    cfg.aim=false cfg.silent=false
    if hookState.owner and hookState.owner.Enabled then hookState.owner=nil end
    for _,con in ipairs(connections) do pcall(function() con:Disconnect() end) end
    for _,e in pairs(espObjects) do pcall(function() e:Destroy() end) end
    pcall(function() gui:Destroy() end)
    if env.SasukeMM2 and env.SasukeMM2.Close==close then env.SasukeMM2=nil end
end
connect(closeBtn.MouseButton1Click,close)
env.SasukeMM2={Close=close, Version="1.0", GetError=function() return lastError end}
save()