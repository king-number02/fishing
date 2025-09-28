--=== CONFIG ===
local CHARGE_ARG      = 1758981623.918268
local REQUEST_ARG1    = -1.233184814453125
local REQUEST_ARG2    = 0.9936770049557389

local DEFAULT_DELAY_COMPLETED = 1.00   -- detik: Completed X detik SETELAH Request
local DEFAULT_DELAY_CANCEL    = 0.08   -- detik: Cancel cepat setelah Request
local DEFAULT_DECISION_FALLBACK = "cancel" -- jika rarity belum terbaca: "cancel" / "complete"

-- Spam Completed (agar pasti ketarik)
local SPAM_COMPLETE_WINDOW   = 3.0   -- detik total spam setelah Completed pertama
local SPAM_COMPLETE_INTERVAL = 0.12  -- jeda antar spam Completed
local POST_ACTION_COOLDOWN   = 0.25  -- cooldown kecil setelah aksi
--===========================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

-- Remotes
local idx   = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index")
local sleit = idx:FindFirstChild("sleitnick_net@0.2.0")
assert(sleit, "[AutoFishing] net package tidak ditemukan")
local net   = sleit:WaitForChild("net")

local RF_Charge   = net:FindFirstChild("RF/ChargeFishingRod")
local RF_Request  = net:FindFirstChild("RF/RequestFishingMinigameStarted")
local RF_Cancel   = net:FindFirstChild("RF/CancelFishingInputs")
local RE_Complete = net:FindFirstChild("RE/FishingCompleted")
local RE_Exclaim  = net:FindFirstChild("RE/ReplicateTextEffect")
assert(RF_Charge and RF_Request and RF_Cancel and RE_Complete and RE_Exclaim, "[AutoFishing] Remote tidak lengkap")

-- === DETEKSI RARITAS "!" (local player only) ===
_G.FishIt_LastExclaimAt = 0
_G.FishIt_LastRarity    = nil

local function rgbToHsv(c)
    local r,g,b=c.R,c.G,c.B
    local maxv,minv=math.max(r,g,b),math.min(r,g,b)
    local d=maxv-minv
    local h,s,v=0,(maxv==0 and 0 or d/maxv),maxv
    if d~=0 then
        if maxv==r then h=((g-b)/d)%6
        elseif maxv==g then h=(b-r)/d+2
        else h=(r-g)/d+4 end
        h=h/6
    end
    return h*360,s,v
end
local function hueIn(h,lo,hi) return h>=lo and h<=hi end

local function rarityFromColor(col)
    local h,s,v = rgbToHsv(col)

    -- putih terang nyaris tanpa saturasi = common
    if v > 0.88 and s < 0.15 then
        return "common"
    end

    -- hijau muda / hijau murni (termasuk hue ~81.2)
    if h >= 78 and h <= 95 then
        return "uncommon"
    end

    -- biru murni (hindari teal): rare
    if h >= 205 and h <= 220 then
        return "rare"
    end

    -- ungu = epic
    if h >= 250 and h <= 310 then
        return "epic"
    end

    -- kuning = legendary
    if h >= 40 and h <= 65 then
        return "legendary"
    end

    -- merah = mythic
    if (h >= 0 and h <= 15) or (h >= 350 and h <= 360) then
        return "mythic"
    end

    -- sisanya (termasuk teal/hijau tosca, dll.) = secret
    return "secret"
end

local function isDesc(a,b)
    if not (a and b) then return false end
    local cur=a
    while cur do if cur==b then return true end cur=cur.Parent end
    return false
end

RE_Exclaim.OnClientEvent:Connect(function(...)
    local args={...}
    local td, attach, color
    local function scan(v)
        local t=typeof(v)
        if t=="table" then
            if v.TextData and typeof(v.TextData)=="table" then
                td=v.TextData
                if td.TextColor and typeof(td.TextColor)=="ColorSequence" then
                    local kps=td.TextColor.Keypoints
                    if #kps>=1 then color=kps[1].Value end
                end
                if td.AttachTo and typeof(td.AttachTo)=="Instance" then attach=td.AttachTo end
            end
            for _,vv in pairs(v) do scan(vv) end
        end
    end
    for _,a in ipairs(args) do scan(a) end

    if td and td.Text=="!" then
        local char = LP.Character or LP.CharacterAdded:Wait()
        if attach and isDesc(attach,char) and color then
            _G.FishIt_LastRarity    = rarityFromColor(color)
            _G.FishIt_LastExclaimAt = os.clock()
        end
    end
end)

-- ====== GUI ======
local rarList={"common","uncommon","rare","epic","legendary","mythic","secret"}
local selected={common=true,uncommon=true,rare=true,epic=true,legendary=true,mythic=true,secret=true}

-- builder GUI (safe untuk respawn)
local gui, frame, dCompBox, dCancBox, statusLbl, lastLbl, startBtn, stopBtn
local minimized=false

local function ensureParented(g)
    -- coba CoreGui (kadang dibatasi), jika gagal pakai PlayerGui
    local ok=pcall(function() g.Parent = game:GetService("CoreGui") end)
    if not ok then
        g.Parent = LP:WaitForChild("PlayerGui")
    end
end

local function buildGui()
    if gui and gui.Parent then return end
    gui = Instance.new("ScreenGui")
    gui.Name = "AutoFishingGUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    ensureParented(gui)

    frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0,300,0,360)
    frame.Position = UDim2.new(0,20,0,200)
    frame.BackgroundColor3 = Color3.fromRGB(30,30,30)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner",frame).CornerRadius = UDim.new(0,10)

    local title=Instance.new("TextLabel",frame)
    title.Size=UDim2.new(1,-36,0,22)
    title.Position=UDim2.new(0,6,0,6)
    title.BackgroundTransparency=1
    title.Text="Auto Fishing (Filter + Spam)"
    title.TextColor3=Color3.fromRGB(255,255,255)
    title.Font=Enum.Font.GothamBold
    title.TextSize=16
    title.TextXAlignment=Enum.TextXAlignment.Left

    -- tombol minimize
    local miniBtn=Instance.new("TextButton",frame)
    miniBtn.Size=UDim2.new(0,24,0,24)
    miniBtn.Position=UDim2.new(1,-28,0,4)
    miniBtn.Text="-"
    miniBtn.BackgroundColor3=Color3.fromRGB(80,80,80)
    miniBtn.TextColor3=Color3.new(1,1,1)
    miniBtn.Font=Enum.Font.GothamBold
    miniBtn.TextSize=16
    miniBtn.Parent=frame
    Instance.new("UICorner",miniBtn).CornerRadius=UDim.new(0,6)
    minimized=false
    miniBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        for _,child in ipairs(frame:GetChildren()) do
            if child ~= miniBtn and child:IsA("GuiObject") then
                child.Visible = not minimized
            end
        end
        miniBtn.Text = minimized and "+" or "-"
        frame.Size = minimized and UDim2.new(0,300,0,32) or UDim2.new(0,300,0,360)
    end)

    statusLbl=Instance.new("TextLabel",frame)
    statusLbl.Size=UDim2.new(1,-12,0,18)
    statusLbl.Position=UDim2.new(0,6,0,28)
    statusLbl.BackgroundTransparency=1
    statusLbl.Text="Status: Idle"
    statusLbl.TextColor3=Color3.fromRGB(210,210,210)
    statusLbl.Font=Enum.Font.Gotham
    statusLbl.TextSize=14
    statusLbl.TextXAlignment=Enum.TextXAlignment.Left

    lastLbl=Instance.new("TextLabel",frame)
    lastLbl.Size=UDim2.new(1,-12,0,18)
    lastLbl.Position=UDim2.new(0,6,0,46)
    lastLbl.BackgroundTransparency=1
    lastLbl.Text="Last: -"
    lastLbl.TextColor3=Color3.fromRGB(200,200,140)
    lastLbl.Font=Enum.Font.Gotham
    lastLbl.TextSize=14
    lastLbl.TextXAlignment=Enum.TextXAlignment.Left

    local dCompLbl=Instance.new("TextLabel",frame)
    dCompLbl.Size=UDim2.new(0,160,0,18)
    dCompLbl.Position=UDim2.new(0,6,0,70)
    dCompLbl.BackgroundTransparency=1
    dCompLbl.Text="Delay Completed (s):"
    dCompLbl.TextColor3=Color3.fromRGB(200,200,200)
    dCompLbl.Font=Enum.Font.Gotham
    dCompLbl.TextSize=13
    dCompLbl.TextXAlignment=Enum.TextXAlignment.Left

    dCompBox=Instance.new("TextBox",frame)
    dCompBox.Size=UDim2.new(0,70,0,22)
    dCompBox.Position=UDim2.new(0,170,0,70)
    dCompBox.Text=tostring(DEFAULT_DELAY_COMPLETED)
    dCompBox.BackgroundColor3=Color3.fromRGB(40,40,50)
    dCompBox.TextColor3=Color3.fromRGB(255,255,255)
    dCompBox.ClearTextOnFocus=false
    dCompBox.Font=Enum.Font.Gotham
    dCompBox.TextSize=13
    Instance.new("UICorner",dCompBox).CornerRadius=UDim.new(0,6)

    local dCancLbl=Instance.new("TextLabel",frame)
    dCancLbl.Size=UDim2.new(0,160,0,18)
    dCancLbl.Position=UDim2.new(0,6,0,94)
    dCancLbl.BackgroundTransparency=1
    dCancLbl.Text="Delay Cancel (s):"
    dCancLbl.TextColor3=Color3.fromRGB(200,200,200)
    dCancLbl.Font=Enum.Font.Gotham
    dCancLbl.TextSize=13
    dCancLbl.TextXAlignment=Enum.TextXAlignment.Left

    dCancBox=Instance.new("TextBox",frame)
    dCancBox.Size=UDim2.new(0,70,0,22)
    dCancBox.Position=UDim2.new(0,170,0,94)
    dCancBox.Text=tostring(DEFAULT_DELAY_CANCEL)
    dCancBox.BackgroundColor3=Color3.fromRGB(40,40,50)
    dCancBox.TextColor3=Color3.fromRGB(255,255,255)
    dCancBox.ClearTextOnFocus=false
    dCancBox.Font=Enum.Font.Gotham
    dCancBox.TextSize=13
    Instance.new("UICorner",dCancBox).CornerRadius=UDim.new(0,6)

    startBtn=Instance.new("TextButton",frame)
    startBtn.Size=UDim2.new(0,120,0,28)
    startBtn.Position=UDim2.new(0,6,0,122)
    startBtn.Text="Start"
    startBtn.BackgroundColor3=Color3.fromRGB(60,180,90)
    startBtn.TextColor3=Color3.new(1,1,1)
    startBtn.Font=Enum.Font.GothamSemibold
    startBtn.TextSize=14
    Instance.new("UICorner",startBtn).CornerRadius=UDim.new(0,8)

    stopBtn=Instance.new("TextButton",frame)
    stopBtn.Size=UDim2.new(0,120,0,28)
    stopBtn.Position=UDim2.new(0,150,0,122)
    stopBtn.Text="Stop"
    stopBtn.BackgroundColor3=Color3.fromRGB(200,70,70)
    stopBtn.TextColor3=Color3.new(1,1,1)
    stopBtn.Font=Enum.Font.GothamSemibold
    stopBtn.TextSize=14
    Instance.new("UICorner",stopBtn).CornerRadius=UDim.new(0,8)

    -- Toggle rarity (2 kolom)
    local function mkToggle(i,name)
        local col=(i%2==1) and 6 or 156
        local row=math.floor((i-1)/2)
        local y=158+row*28
        local btn=Instance.new("TextButton",frame)
        btn.Size=UDim2.new(0,138,0,24)
        btn.Position=UDim2.new(0,col,0,y)
        btn.BackgroundColor3=selected[name] and Color3.fromRGB(60,160,90) or Color3.fromRGB(55,55,65)
        btn.Text=name.." : "..(selected[name] and "ON" or "OFF")
        btn.TextColor3=Color3.new(1,1,1)
        btn.Font=Enum.Font.Gotham
        btn.TextSize=13
        Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)
        btn.MouseButton1Click:Connect(function()
            selected[name]=not selected[name]
            btn.BackgroundColor3=selected[name] and Color3.fromRGB(60,160,90) or Color3.fromRGB(55,55,65)
            btn.Text=name.." : "..(selected[name] and "ON" or "OFF")
        end)
    end
    for i,name in ipairs(rarList) do mkToggle(i,name) end

    -- Drag support (frame bisa digeser)
    local dragging=false
    local dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

buildGui()

-- Pastikan GUI tetap ada saat respawn (kalau engine mindah-mindah PlayerGui)
LP.CharacterAdded:Connect(function()
    if not gui or not gui.Parent then
        buildGui()
    end
end)

-- ====== HELPERS INVOKE ======
local function safeInvoke(fn, label)
    local ok, err = pcall(fn)
    if not ok then
        warn("[AutoFishing] "..label.." error:", err)
        if statusLbl then statusLbl.Text = "Status: "..label.." error" end
    end
    return ok
end
local function charge()   return safeInvoke(function() RF_Charge:InvokeServer(CHARGE_ARG) end, "Charge") end
local function request()  return safeInvoke(function() RF_Request:InvokeServer(REQUEST_ARG1,REQUEST_ARG2) end, "Request") end
local function cancel()   return safeInvoke(function() RF_Cancel:InvokeServer() end, "Cancel") end
local function complete() return safeInvoke(function() RE_Complete:FireServer() end, "Completed") end

-- ====== LOOP UTAMA ======
local running=false

local function runOnce(delayCompleted, delayCancel)
    if not frame or not frame.Parent then buildGui() end

    statusLbl.Text="Status: Charging"
    charge()
    statusLbl.Text="Status: Requesting"
    request()

    local tRequest = os.clock()

    -- Jendela kecil untuk "membaca" rarity (tanpa menunda aksi absolut)
    local decisionWindow = math.max(0.05, math.min(delayCompleted - 0.05, 0.60))
    local rar = nil
    while os.clock() - tRequest < decisionWindow do
        if _G.FishIt_LastExclaimAt > tRequest then
            rar = _G.FishIt_LastRarity
            break
        end
        task.wait(0.02)
    end
    lastLbl.Text = "Last: "..tostring(rar or "unknown")

    -- Tentukan aksi
    local action
    if rar and selected[rar] then
        action = "complete"
    elseif rar and not selected[rar] then
        action = "cancel"
    else
        action = DEFAULT_DECISION_FALLBACK
    end

    if action=="complete" then
        statusLbl.Text="Will Complete (spam)"
        -- Tunggu hingga tepat delayCompleted dari Request
        local waitLeft = delayCompleted - (os.clock() - tRequest)
        if waitLeft > 0 then task.wait(waitLeft) end

        -- Completed pertama
        complete()

        -- SPAM Completed sampai window habis
        local spamStart = os.clock()
        while os.clock() - spamStart < SPAM_COMPLETE_WINDOW do
            complete()
            task.wait(SPAM_COMPLETE_INTERVAL)
        end
    else
        statusLbl.Text="Will Cancel"
        local waitLeft = delayCancel - (os.clock() - tRequest)
        if waitLeft > 0 then task.wait(waitLeft) end
        cancel()
    end

    task.wait(POST_ACTION_COOLDOWN)
end

local function mainLoop()
    while running do
        local dComp = tonumber(dCompBox.Text) or DEFAULT_DELAY_COMPLETED
        local dCanc = tonumber(dCancBox.Text) or DEFAULT_DELAY_CANCEL
        if dComp < 0.05 then dComp = 0.05 end
        if dCanc < 0.01 then dCanc = 0.01 end
        runOnce(dComp, dCanc)
    end
    statusLbl.Text="Status: Idle"
end

startBtn.MouseButton1Click:Connect(function()
    if running then return end
    running=true
    statusLbl.Text="Status: Running"
    task.spawn(mainLoop)
end)

stopBtn.MouseButton1Click:Connect(function()
    running=false
    statusLbl.Text="Status: Stopping"
end)
