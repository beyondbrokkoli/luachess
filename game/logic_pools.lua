-- game/logic_pools.lua — Depth-indexed pooled allocations for perft DFS
--
-- Perft's full-depth DFS holds ancestor states on the call stack. At depth 10
-- that's 10 frames deep, each allocating lists and nodes. A single global ring
-- buffer (8192 entries) overflows and corrupts earlier allocations.
--
-- Solution: pool[depth][cursor] — each recursion depth gets its own independent
-- allocator. The depth is set by the caller to self.turn (the ply number).
-- Siblings at the same ply naturally overwrite each other; when a branch
-- unwinds, its parent continues from the same depth value, so the pool slot
-- is reset before the next sibling is generated.

local pools = {}       -- pools[depth] = { cur = 0 }
local current_depth = 1  -- set by caller to self.turn; default 1 for game

-- Shared promotion node metatable (prom moves share the same identity type as loc)
local loc_mt = getmetatable(loc:new(1,1))

-- Internal: get or create the pool table for a given depth.
local function pool_at(depth)
    if not pools[depth] then
        pools[depth] = { cur = 0 }
    end
    return pools[depth]
end

-- Reset the cursor for a specific depth. Call this before generating a
-- sibling branch at a given ply so it reuses slots from scratch.
local function reset_depth(depth)
    if pools[depth] then
        pools[depth].cur = 0
    end
end

-- List: flat array (move lists, attack lists, etc.)
-- Fast-clear reused lists so # and ipairs() stop at the right length.
local function get_list()
    local p = pool_at(current_depth)
    p.cur = p.cur + 1

    local l = p[p.cur]
    if not l then
        l = {}
        p[p.cur] = l
    else
        -- Fast-clear ghost data from previous sibling branch
        for i = 1, #l do l[i] = nil end
    end

    return l
end

-- Special position (loc metatable): castling squares, en passant targets
local function get_special_pos(l, castles_table)
    local sp = setmetatable({}, loc_mt)
    sp.x = l.x; sp.y = l.y
    sp.castles = castles_table
    sp.id = nil; sp.loc = nil; sp.dir = nil; sp.enpas = nil
    return sp
end

-- Promotion move: perft generates 4 per destination square (Q, R, B, N)
local function get_prom_move(target_loc, prom_id)
    local sp = setmetatable({}, loc_mt)
    sp.x = target_loc.x; sp.y = target_loc.y
    sp.prom = prom_id
    -- Sanitize ghost data — these fields must not leak into other move types
    sp.castles = nil; sp.id = nil; sp.loc = nil; sp.dir = nil; sp.enpas = nil
    return sp
end

-- Piece node: { id, moves } for piece -> legal moves mapping
local function get_piece_node(id)
    local n = { id = id, moves = nil }
    return n
end

-- Attack node: loc metatable for identity comparison with kingPos
local function get_atk_node(target_loc, id, origin_loc, dir)
    local a = setmetatable({}, loc_mt)
    a.x = target_loc.x; a.y = target_loc.y
    a.id = id; a.loc = origin_loc; a.dir = dir; a.castles = nil; a.enpas = nil
    return a
end

-- Special move: loc metatable for castling move targets
local function get_special_move(target_loc, castles_table)
    local sp = setmetatable({}, loc_mt)
    sp.x = target_loc.x; sp.y = target_loc.y
    sp.castles = castles_table; sp.id = nil; sp.loc = nil
    sp.dir = nil; sp.enpas = nil
    return sp
end

-- Turn object: perft DFS creates one per ply — pool to avoid GC
local function get_turn()
    local p = pool_at(current_depth)
    p.cur = p.cur + 1
    if not p[p.cur] then
        p[p.cur] = setmetatable({ change = { false, false } }, { __index = require("game/turn") })
    end
    return p[p.cur]
end

-- Public API
return {
    current_depth = {
        get = function() return current_depth end,
        set = function(d) current_depth = d end
    };
    get_list = get_list;
    get_special_pos = get_special_pos;
    get_prom_move = get_prom_move;
    get_piece_node = get_piece_node;
    get_atk_node = get_atk_node;
    get_special_move = get_special_move;
    get_turn = get_turn;
    reset_depth = reset_depth;
}