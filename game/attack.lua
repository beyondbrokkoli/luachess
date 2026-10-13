-- game/attack.lua — HARNESS EDITION (fresh allocations, no ring buffers)
local function get_list()
    return {}
end

local loc_mt = getmetatable(loc:new(1,1))

local function get_sp(l, dir)
    local sp = setmetatable({}, loc_mt)
    sp.x = l.x; sp.y = l.y
    sp.dir = dir
    return sp
end

-- ATTACK GENERATORS (unchanged logic)
function visionAT(pos,l,dir)
    local a = get_list()
    local idx = 1
    local s = l:move(dir)

    while s do
        a[idx] = s; idx = idx + 1
        if pos[s] ~= 0 then break end
        s = s:move(dir)
    end
    return a
end

function pawnAT(pos,l)
    local id = pos[l]
    local a = get_list()
    local idx = 1
    local take = (id < 0) and {4,6} or {2,8}

    for _,dir in ipairs(take) do
        local s = l:move(dir)
        if s then
            a[idx] = get_sp(s, dir)
            idx = idx + 1
        end
    end
    return a
end

function knightAT(pos,l)
    local a = get_list()
    local idx = 1
    for dir = 9, 16 do
        local s = l:move(dir)
        if s then
            a[idx] = get_sp(s, dir)
            idx = idx + 1
        end
    end
    return a
end

function kingAT(pos,l)
    local a = get_list()
    local idx = 1
    for dir = 1, 8 do
        local s = l:move(dir)
        if s then
            a[idx] = get_sp(s, dir)
            idx = idx + 1
        end
    end
    return a
end
