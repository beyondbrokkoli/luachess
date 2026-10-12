-- game/logic.lua
require("global")
require("game/move")
require("game/attack")

local directions = {}
directions[3] = {2,4,6,8}
directions[4] = {1,3,5,7}
directions[5] = {1,2,3,4,5,6,7,8}

-- ZERO-ALLOCATION RING BUFFERS

-- 1. The List Pool (Replaces table.insert and {})
local LIST_POOL_SIZE = 8192
local list_pool = {}
local list_cursor = 1
for i=1, LIST_POOL_SIZE do list_pool[i] = {} end

local function get_list()
    local l = list_pool[list_cursor]
    list_cursor = (list_cursor % LIST_POOL_SIZE) + 1
    -- Fast-clear the array so `#` operator and ipairs() still work perfectly
    for i=1, #l do l[i] = nil end
    return l
end

-- 2. The Piece Node Pool (Replaces p[l] = { id = s })
local NODE_POOL_SIZE = 8192
local node_pool = {}
local node_cursor = 1
for i=1, NODE_POOL_SIZE do node_pool[i] = {} end

local function get_piece_node(id)
    local n = node_pool[node_cursor]
    node_cursor = (node_cursor % NODE_POOL_SIZE) + 1
    n.id = id
    n.moves = nil
    return n
end

-- 3. The Special Node Pool (Replaces a.id = s and move.castles = ...)
-- We apply the loc metatable so that `move == kingPos` still evaluates correctly!
local SP_POOL_SIZE = 8192
local sp_pool = {}
local sp_cursor = 1
local loc_mt = getmetatable(loc:new(1,1))
for i=1, SP_POOL_SIZE do
    local sp = {}
    setmetatable(sp, loc_mt)
    sp_pool[i] = sp
end

local function get_atk_node(target_loc, id, origin_loc, dir)
    local a = sp_pool[sp_cursor]
    sp_cursor = (sp_cursor % SP_POOL_SIZE) + 1
    a.x = target_loc.x; a.y = target_loc.y
    a.id = id; a.loc = origin_loc; a.dir = dir

    a.castles = nil -- Sanitize ghost state
    a.enpas = nil
    return a
end

local function get_special_move(target_loc, castles_table)
    local sp = sp_pool[sp_cursor]
    sp_cursor = (sp_cursor % SP_POOL_SIZE) + 1
    sp.x = target_loc.x; sp.y = target_loc.y
    sp.castles = castles_table

    sp.id = nil; sp.loc = nil; sp.dir = nil; sp.enpas = nil -- Sanitize ghost state
    return sp
end

-- ENGINE LOGIC

function findKing(pos,turn)
    local id = hasTurn(8,turn) and 8 or -8
    local kingPos
    do8x8break(pos,function(s,l)
        if s==id then
             kingPos = l
             return true
        end
    end)
    return kingPos
end

function opponents(a,b)
    if not (a/abs(a)==b/abs(b)) then return true else return false end
end

-- Replaced recursion and table.insert with pooled lists and while loops
local function superVision(l,dir)
    local v = get_list()
    local s = l:move(dir)
    local count = 1
    while s do
        v[count] = s
        count = count + 1
        s = s:move(dir)
    end
    return v
end

local function aligned(a,b)
    for i=1,8 do
        local vision = superVision(a,i)
        for _,square in ipairs(vision) do
            if square==b then return i end
        end
    end
    return false
end

local function castles_free(pos,l,x,y,freshmap,id)
    local ks,qs = false,false
    local kingSpawnY
    if id==8 then kingSpawnY = 1
    elseif id == -8 then kingSpawnY = 8
    else print("ERROR CASTLES ID") end

    if freshmap[5][kingSpawnY] and freshmap[8][kingSpawnY] and pos[7][kingSpawnY]==0 and pos[6][kingSpawnY]==0 then
        ks = get_list()
        ks[1] = loc:new(5,kingSpawnY); ks[2] = loc:new(6,kingSpawnY); ks[3] = loc:new(7,kingSpawnY)
    end
    if freshmap[5][kingSpawnY] and freshmap[1][kingSpawnY] and pos[4][kingSpawnY]==0 and pos[3][kingSpawnY]==0 and pos[2][kingSpawnY]==0 then
        qs = get_list()
        qs[1] = loc:new(5,kingSpawnY); qs[2] = loc:new(4,kingSpawnY); qs[3] = loc:new(3,kingSpawnY)
    end
    return ks,qs
end

local function castles_safe(atk,cs)
    for _,a in pairs(atk) do
        if contains(cs,a) then return false end
    end
    return true
end

local function attackgen(position,turn)
    local atk = get_list()
    local pos = Map:copy(position)
    local kingPos = findKing(pos,turn+1)
    pos[kingPos] = 0

    local atk_idx = 1
    scrollTurn(pos,turn,function(s,l)
        local abs_s = abs(s)
        if abs_s == 1 then
            local moves = pawnAT(pos,l)
            for _,m in ipairs(moves) do
                atk[atk_idx] = get_atk_node(m, s, l, m.dir)
                atk_idx = atk_idx + 1
            end
        elseif abs_s == 2 then
            local moves = knightAT(pos,l)
            for _,m in ipairs(moves) do
                atk[atk_idx] = get_atk_node(m, s, l, m.dir)
                atk_idx = atk_idx + 1
            end
        elseif abs_s >= 3 and abs_s <= 5 then
            for _,d in ipairs(directions[abs_s]) do
                local mlist = visionAT(pos,l,d)
                for _,m in ipairs(mlist) do
                    atk[atk_idx] = get_atk_node(m, s, l, d)
                    atk_idx = atk_idx + 1
                end
            end
        elseif abs_s == 8 then
            local moves = kingAT(pos,l)
            for _,m in ipairs(moves) do
                atk[atk_idx] = get_atk_node(m, s, l, m.dir)
                atk_idx = atk_idx + 1
            end
        end
    end)
    return atk
end

local function nextPiece(pos,l,dir)
    local s = l:move(dir)
    while s do
        if pos[s]==0 then s = s:move(dir)
        else return s end
    end
    return false
end

local function reverse(dir)
    local r = dir - 4
    if r <= 0 then return 8 - abs(r) else return r end
end

local function pinned(pos,pc,king)
    local toKing = aligned(pc,king)
    if not toKing then
        return false
    elseif nextPiece(pos,pc,toKing) == king then
        local away = reverse(toKing)
        local otherSide = nextPiece(pos,pc,away)
        if not otherSide then return false end
        local kingID = pos[king]
        if opponents(pos[otherSide],kingID) then
            local enemy = abs(pos[otherSide])
            if (enemy==3 or enemy==4 or enemy==5) and contains(directions[enemy],toKing) then
                local avail = get_list()
                local a_idx = 1
                local s = pc:move(away)
                while not (s==otherSide) do
                    avail[a_idx] = s; a_idx = a_idx + 1
                    s = s:move(away)
                end
                avail[a_idx] = otherSide; a_idx = a_idx + 1
                s = pc:move(toKing)
                while not (s==king) do
                    avail[a_idx] = s; a_idx = a_idx + 1
                    s = s:move(toKing)
                end
                return avail
            end
        end
    end
    return false
end

local function filterPin(mlist,insidePin)
    local filtered = get_list()
    local f_idx = 1
    for i,move in ipairs(mlist) do
        if contains(insidePin,move) then
            filtered[f_idx] = move
            f_idx = f_idx + 1
        end
    end
    return filtered
end

function possible(pos,turn,freshmap,eptoken)
    local enpasMap
    if eptoken then
        enpasMap = Map:new(0)
        do8x8(pos,function(s,l) enpasMap[l] = s end)
        enpasMap[eptoken] = eptoken.id
    end
    local p = Map:new(false)
    scrollTurn(pos,turn,function(s,l,x,y)
        local abs_s = abs(s)
        local node = get_piece_node(s)

        if abs_s == 1 then
            node.moves = pawnM(enpasMap or pos,l,freshmap[l])
        elseif abs_s == 2 then
            node.moves = knightM(pos,l)
        elseif abs_s >= 3 and abs_s <= 5 then
            local moves = get_list()
            local m_idx = 1
            for _,d in ipairs(directions[abs_s]) do
                local mlist = visionM(pos,l,d)
                for _,m in ipairs(mlist) do
                    moves[m_idx] = m
                    m_idx = m_idx + 1
                end
            end
            node.moves = moves
        elseif abs_s == 8 then
            local atk = attackgen(pos,turn+1)
            node.moves = kingM(pos,l,atk)
            local ks, qs = castles_free(pos,l,x,y,freshmap,s)

            if ks and castles_safe(atk,ks) then
                local c_info = get_list()
                c_info[1] = loc:new(8,y); c_info[2] = ks[2]
                node.moves[#node.moves+1] = get_special_move(loc:new(7,y), c_info)
            end
            if qs and castles_safe(atk,qs) then
                local c_info = get_list()
                c_info[1] = loc:new(1,y); c_info[2] = qs[2]
                node.moves[#node.moves+1] = get_special_move(loc:new(3,y), c_info)
            end
        end
        p[l] = node
    end)

    local kingPos = findKing(pos,turn)
    scrollTurn(pos,turn,function(s,l)
        local pin = pinned(pos,l,kingPos)
        if pin then
            p[l].moves = filterPin(p[l].moves,pin)
        end
    end)

    -- EP PROOF PASS: an en-passant capture vacates TWO squares of one
    -- rank (the capturer leaves, the captured pawn vanishes) — a
    -- discovery the single-piece pin filter cannot see: with the
    -- captured pawn between capturer and king the pin scan sees no
    -- line, and with the king adjacent the away-scan hits the captured
    -- pawn (not a slider) and sees no pin either. Every ep capture is
    -- proven by playing it out — only a king-safe one survives.
    -- (pos3's f4xe3/f4xg3 next to the b4 rook, king on h4, generated
    -- both bogus captures — perft +2 at d2, and at d4 the leaked
    -- check even let a rook capture the king, crashing findKing.)
    scrollTurn(pos,turn,function(s,l)
        if abs(s) == 1 and p[l].moves then
            local keep = get_list()
            local n = 1
            local i = 1
            while p[l].moves[i] do
                local m = p[l].moves[i]
                if m.enpas then
                    -- Simulate the capture: remove capturer + captured pawn
                    local proof = Map:copy(pos)
                    proof[l] = 0
                    proof[loc:new(m.x, l.y)] = 0
                    local kp = findKing(proof,turn)
                    local safe = true
                    local atk = attackgen(proof,turn+1)
                    local j = 1
                    while atk[j] do
                        if atk[j] == kp then
                            safe = false
                            break
                        end
                        j = j + 1
                    end
                    if safe then
                        keep[n] = m
                        n = n + 1
                    end
                else
                    keep[n] = m
                    n = n + 1
                end
                i = i + 1
            end
            p[l].moves = keep
        end
    end)
    return p
end

function inCheck(pos,turn,freshmap,eptoken)
    local check = false
    local available = Map:new(false)
    local oppAT = attackgen(pos,turn+1)
    local kingPos = findKing(pos,turn)

    for i,move in ipairs(oppAT) do
        if move == kingPos then
            if check then
                local escape = kingM(pos,kingPos,oppAT)
                if #escape==0 then
                    return true,false,true
                else
                    available = Map:new(false)
                    local knode = get_piece_node(pos[kingPos])
                    knode.moves = escape
                    available[kingPos] = knode
                    return true, available, true
                end
            end
            check = true
            local P = possible(pos,turn,freshmap,eptoken)
            local kill, blocks = false, false

            do8x8(P,function(pc,l,x,y)
                if pc and not (abs(pc.id)==8) then
                    if contains(pc.moves, move.loc) then
                        kill = true
                        if not available[l] then
                            available[l] = get_piece_node(pc.id)
                            available[l].moves = get_list()
                        end
                        local mlist = available[l].moves
                        mlist[#mlist+1] = move.loc
                    end
                end
            end)

            if abs(move.id) > 2 then
                blocks = get_list()
                local b_idx = 1
                local _r = i - 1
                while _r>0 and oppAT[_r].dir == move.dir and oppAT[_r].loc == move.loc do
                    blocks[b_idx] = oppAT[_r]
                    b_idx = b_idx + 1
                    _r = _r - 1
                end

                if b_idx == 1 then
                    blocks = false
                else
                    local block_avail = false
                    do8x8(P,function(pc,l)
                        if pc and not (abs(pc.id)==8) then
                            for _,b in ipairs(blocks) do
                                if contains(pc.moves, b) then
                                    block_avail = true
                                    if not available[l] then
                                        available[l] = get_piece_node(pos[l])
                                        available[l].moves = get_list()
                                    end
                                    local mlist = available[l].moves
                                    mlist[#mlist+1] = b
                                end
                            end
                        end
                    end)
                    if not block_avail then blocks = false end
                end
            end

            local escape = kingM(pos,kingPos,oppAT)
            if #escape == 0 then
                escape = false
            else
                if not available[kingPos] then
                    available[kingPos] = get_piece_node(pos[kingPos])
                    available[kingPos].moves = get_list()
                end
                local klist = available[kingPos].moves
                for _,e in ipairs(escape) do
                    klist[#klist+1] = e
                end
            end

            if not (escape or blocks or kill) then
                return true,false
            end
        end
    end
    return check, available
end

function compare(a,b)
    local same = true
    do8x8break(a, function (s,l) if not (s==b[l]) then same = false return true end end)
    return same
end

function drawRepetition(timeline)
    local count = 1
    local i = #timeline
    local turn = timeline[i]
    local c = i-2
    local comp = timeline[c]
    while comp do
        if compare(turn.pos,comp.pos) then
            count= count+1
        end
        c = c - 2
        comp = timeline[c]
    end
    if count > 2 then return true else return false end
end
