-- LocalScript di StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- remote event "!" effect
local idx   = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index")
local sleit = idx:FindFirstChild("sleitnick_net@0.2.0")
local net   = sleit:WaitForChild("net")
local RE_Exclaim  = net:FindFirstChild("RE/ReplicateTextEffect")

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
    local h,s,v=rgbToHsv(col)
    if v>0.88 and s<0.15 then return "common" end
    if hueIn(h,90,130) then return "uncommon" end
    if hueIn(h,190,230) then return "rare" end
    if hueIn(h,250,310) then return "epic" end
    if hueIn(h, 40, 65) then return "legendary" end
    if hueIn(h,   0, 15) or hueIn(h,350,360) then return "mythic" end
    return "secret"
end

local function isDesc(a,b)
    if not (a and b) then return false end
    local cur=a
    while cur do if cur==b then return true end cur=cur.Parent end
    return false
end

-- debug setiap event tanda seru
RE_Exclaim.OnClientEvent:Connect(function(...)
    local args={...}
    local td, attach, color
    local function scan(v)
        if typeof(v)=="table" then
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

    if td and td.Text=="!" and color then
        local char = LP.Character or LP.CharacterAdded:Wait()
        if attach and isDesc(attach,char) then
            local h,s,v=rgbToHsv(color)
            local rar=rarityFromColor(color)
            warn(string.format("[DEBUG] Text='!' Hue=%.1f Sat=%.2f Val=%.2f RGB=(%d,%d,%d) => %s",
                h,s,v,color.R*255,color.G*255,color.B*255, rar))
        end
    end
end)
