-- game/move.lua — Pool-backed move generators with promotion branching
--
-- All allocations go through logic_pools for DFS-safe pool reuse.
-- pawnM generates 4 promotion moves per destination square when a pawn
-- steps onto rank 1 or 8, so perft can traverse all underpromotion branches.

require("global")
local logic_pools = require("game/logic_pools")

-- MOVE GENERATORS (logic unchanged — only allocation strategy differs)
function visionM(pos,l,dir)
    local id = pos[l]
    local m = logic_pools.get_list()
    local idx = 1
    local s = l:move(dir)

    while s do
        if pos[s]==0 then
            m[idx] = s; idx = idx + 1
            s = s:move(dir)
        elseif opponents(id,pos[s]) then
            m[idx] = s; idx = idx + 1
            break
        else
            break
        end
    end
    return m
end

function pawnM(pos,l,fresh)
    local id = pos[l]
    local m = logic_pools.get_list()
    local idx = 1
    local forw, take
    if id < 0 then
        forw = 5; take = {4,6}
    else
        forw = 1; take = {2,8}
    end

    local s = l:move(forw)
    if s and pos[s]==0 then
        if s.y == 1 or s.y == 8 then
            -- Promotion: generate all 4 underpromotions
            m[idx] = logic_pools.get_prom_move(s, 5); idx = idx + 1 -- Queen
            m[idx] = logic_pools.get_prom_move(s, 4); idx = idx + 1 -- Rook
            m[idx] = logic_pools.get_prom_move(s, 3); idx = idx + 1 -- Bishop
            m[idx] = logic_pools.get_prom_move(s, 2); idx = idx + 1 -- Knight
            -- Do NOT add double-push — pawn already on promotion rank
        else
            m[idx] = s; idx = idx + 1
            if fresh then
                s = s:move(forw)
                if s and pos[s]==0 then
                    m[idx] = s; idx = idx + 1
                end
            end
        end
    end

    for _,dir in ipairs(take) do
        local t = l:move(dir)
        if t then
            if abs(pos[t])==7 then
                -- En passant capture: use pooled special-position node
                local sp = setmetatable({}, getmetatable(loc:new(1,1)))
                sp.x = t.x; sp.y = t.y
                sp.enpas = true; sp.castles = nil
                m[idx] = sp; idx = idx + 1
            elseif pos[t] ~= 0 then
                -- Normal capture
                if t.y == 1 or t.y == 8 then
                    -- Promotion via capture: generate all 4
                    m[idx] = logic_pools.get_prom_move(t, 5); idx = idx + 1 -- Queen
                    m[idx] = logic_pools.get_prom_move(t, 4); idx = idx + 1 -- Rook
                    m[idx] = logic_pools.get_prom_move(t, 3); idx = idx + 1 -- Bishop
                    m[idx] = logic_pools.get_prom_move(t, 2); idx = idx + 1 -- Knight
                else
                    m[idx] = t; idx = idx + 1
                end
            end
        end
    end
    return m
end

function knightM(pos,l)
    local id = pos[l]
    local m = logic_pools.get_list()
    local idx = 1
    for dir = 9, 16 do
        local s = l:move(dir)
        if s and ( pos[s]==0 or opponents(id,pos[s]) ) then
            m[idx] = s; idx = idx + 1
        end
    end
    return m
end

function kingM(pos,l,at)
    local id = pos[l]
    local m = logic_pools.get_list()
    local idx = 1
    for dir = 1, 8 do
        local s = l:move(dir)
        if s and ( pos[s]==0 or opponents(id,pos[s]) ) then
            if not contains(at, s) then
                m[idx] = s; idx = idx + 1
            end
        end
    end
    return m
end