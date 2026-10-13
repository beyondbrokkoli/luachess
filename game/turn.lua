-- game/turn.lua
--
-- Turn objects are pooled (depth-indexed) during perft DFS to avoid GC churn.
-- The pool cursor resets on depth unwind so sibling branches start fresh.
--
-- Validation has dual identity: perft moves carry a .prom ID for exact matching;
-- human clicks carry no .prom, so validate() falls back to keyboard polling to
-- resolve which of the 4 promotion moves the player intended.

require("global")
require("game/logic")
local logic_pools = require("game/logic_pools")

local function endless(pos,from,to)
    if not (pos[to] == 0) then return false
    elseif abs(pos[from]) == 1 then return false
    else return true end
end

local function algebraic(pos,l,s,enpas,castles,queen)
    if castles == 8 then return "0-0"
    elseif castles then return "0-0-0"
    elseif enpas then return letters[l.x].."x"..letters[s.x]..s.y
    elseif queen then return letters[s.x]..s.y.."="..names[abs(queen)] end
    if pos[s] == 0 then return names[abs(pos[l])]..letters[s.x]..s.y
    elseif abs(pos[l]) == 1 then return letters[l.x].."x"..letters[s.x]..s.y
    else return names[abs(pos[l])].."x"..letters[s.x]..s.y end
end

local function clearly(moveMap,from,to,alg)
    local id = moveMap[from].id
    if abs(id)==1 or abs(id)==8 then return alg end
    local dif
    do8x8break(moveMap,function(s,l,x,y)
            if not s or l==from then return false end
            if s.id==id and contains(s.moves,to) then
                if dif then
                    dif = letters[from.x]..from.y
                    return true
                elseif not (l.x==from.x) then
                    dif = letters[from.x]
                else
                    dif = from.y
                end
            end
    end)
    if dif then
        local prefix=alg:sub(1,1)
        local suffix=alg:sub(2)
        alg=prefix..dif..suffix
    end
    return alg
end

local function normal(pos,l,s)
    local map = Map:copy(pos)
    map[s] = map[l]
    map[l] = 0
    return map, algebraic(pos,l,s)
end

local function castles(pos,l,s,rook0,rook)
    local map = Map:copy(pos)
    map[s] = map[l]
    map[l] = 0
    map[rook] = map[rook0]
    map[rook0] = 0
    return map, algebraic(pos,l,s,nil,rook0.x)
end

local function enpas(pos,l,s,e)
    local map = Map:copy(pos)
    map[s] = map[l]
    map[l] = 0
    map[e] = 0
    return map, algebraic(pos,l,s,true)
end

local function queening(pos,l,s,queen)
    local map = Map:copy(pos)
    map[s] = queen
    map[l] = 0
    return map, algebraic(pos,l,s,nil,nil,queen)
end

-- validate(pc, s) — dual identity:
--
--   PERFT: 's' is a literal move node from possible(). If it has .prom, we match
--          strictly — return the promotion ID so make_move() executes exactly that
--          underpromotion.
--
--   HUMAN: 's' is a raw coordinate (loc) clicked on the board. It has no .prom.
--          We fall back to polling love.keyboard.isDown() to resolve which of
--          the 4 promotion moves the player intended at that square.
local function validate(pc,s)
    if not pc then return false end
    for _,l in pairs(pc.moves) do
        if l==s then
            if l.prom then
                -- Promotable move exists in the list
                if s.prom then
                    -- PERFT branch: 's' carries a .prom ID — match strictly
                    if l.prom == s.prom then
                        return true, false, false, l.prom
                    end
                else
                    -- HUMAN branch: 's' is a naked coordinate — poll keyboard
                    local human_prom
                    if love.keyboard.isDown("2") then human_prom = 2
                    elseif love.keyboard.isDown("3") then human_prom = 3
                    elseif love.keyboard.isDown("4") then human_prom = 4
                    else human_prom = 5 end
                    if l.prom == human_prom then
                        return true, false, false, l.prom
                    end
                end
            elseif l.enpas then
                return true, true
            elseif l.castles then
                return true, nil, l.castles
            else
                return true
            end
        end
    end
    return false
end

-- TURN OBJECT (pooled)

Turn = {}
local Turn_mt = { __index = Turn }

function Turn:new(pos, turn, freshmap, eptoken, change_l, change_s, drawCount)
    local t = logic_pools.get_turn()

    t.inCheck = false
    t.doubleCheck = false
    t.checkmate = false
    t.stalemate = false
    t.draw = false

    local check,avail,double = inCheck(pos,turn,freshmap,eptoken)
    if check and avail then
        t.possible = avail
        t.inCheck = true
        t.doubleCheck = double
    elseif check and not avail then
        t.possible = Map:new(false)
        t.checkmate = true
        t.doubleCheck = double
    else
        t.possible = possible(pos,turn,freshmap,eptoken)
        local stalemate = true
        do8x8break(t.possible,function(s) if s and #s.moves>0 then stalemate = false return true end end)
        t.stalemate = stalemate
    end

    t.pos = pos
    t.turn = turn
    t.kingPos = findKing(pos,turn)
    t.freshmap = freshmap

    if change_l and change_s then
        t.change[1] = change_l
        t.change[2] = change_s
    else
        t.change[1] = false
        t.change[2] = false
    end

    t.move = turn%2==1 and math.floor(turn/2)+1 or turn/2
    t.drawCount = drawCount or 0

    return t
end

function Turn:make_move(l,s)
    local pc = self.possible[l]
    -- validate now returns 4 values: valid, ep, cs, prom
    local valid, ep, cs, prom = validate(pc,s)
    if not valid then return false end

    local pos = self.pos
    local new,alg

    if cs then
        new, alg = castles(pos,l,s,cs[1],cs[2])
    elseif ep then
        new,alg = enpas(pos,l,s,loc:new(s.x,s.y-pc.id))
    elseif prom then
        -- Execution via promotion ID — no keyboard polling
        new, alg = queening(pos,l,s,prom*pc.id)
    else
        new,alg = normal(pos,l,s)
    end

    alg = clearly(self.possible,l,s,alg)

    -- new turn data
    local eptoken = nil
    if abs(new[s]) == 1 and abs(l.y-s.y)==2 then
        eptoken = loc:new( s.x, s.y-pc.id )
        eptoken.id = 7*new[s]
    end

    local fmap = Map:copy(self.freshmap)
    fmap[l] = false
    fmap[s] = false
    if cs then
        fmap[ cs[1] ] = false
    end

    local drawCount
    if endless(pos,l,s) then
        drawCount = self.drawCount +1
    else
        drawCount = 0
    end

    -- Depth-indexed pool management:
    -- Save current depth, advance to next ply, reset the pool so the
    -- next Turn object reuses slots, then restore for parent branch.
    local prev_depth = logic_pools.current_depth.get()
    logic_pools.current_depth.set(self.turn + 1)
    logic_pools.reset_depth(self.turn + 1)

    local next_turn = Turn:new(new, self.turn+1, fmap, eptoken, l, s, drawCount)

    logic_pools.current_depth.set(prev_depth)

    return next_turn, alg
end

return Turn
