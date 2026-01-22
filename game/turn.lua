require("global")
require("game/logic")
local function endless(pos,from,to)
	if not (pos[to] == 0) then --taking a piece
		return false
	elseif abs(pos[from]) == 1 then --moving a pawn
		return false
	else
		return true
	end
end
local function algebraic(pos,l,s,enpas,castles,queen)
	if castles == 8 then
		return "0-0"
	elseif castles then
		return "0-0-0"
	elseif enpas then
		return letters[l.x].."x"..letters[s.x]..s.y
	elseif queen then
		return 	letters[s.x]..s.y.."="..names[abs(queen)]
	end
	if pos[s] == 0 then
		return names[abs(pos[l])]..letters[s.x]..s.y
	elseif abs(pos[l]) == 1 then
		return letters[l.x].."x"..letters[s.x]..s.y
	else
		return names[abs(pos[l])].."x"..letters[s.x]..s.y
	end
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
	map[rook] = map[rook0] --move the rook to new square
	map[rook0] = 0 --remove the rook from original square
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
local function validate(pc,s)
	if not pc then return false end
	for _,l in pairs(pc.moves) do
		if l==s and l.enpas then
			return true,true
		elseif l==s and l.castles then
			return true,nil,l.castles
		elseif l==s then
			return true
		end
	end
	return false
end
Turn = {}
function Turn:new(pos,turn,freshmap,eptoken,change,drawCount)
	local t = {}
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
		do8x8break(t.possible,function (s) if s and #s.moves>0 then stalemate = false return true end end)
		t.stalemate = stalemate
	end
	t.pos = pos
	t.turn = turn
	t.kingPos = findKing(pos,turn)
	t.freshmap = freshmap
	t.change = change
	t.move = turn%2==1 and math.floor(turn/2)+1 or turn/2 
	t.drawCount = drawCount or 0
	function t:make_move(l,s)
		local eptoken
		local pc = self.possible[l]
		local valid,ep,cs = validate(pc,s)
		if not valid then return false end
		local pos = self.pos
		local new,alg
		if cs then
			new, alg = castles(pos,l,s,cs[1],cs[2])
		elseif ep then
			new,alg = enpas(pos,l,s,loc:new(s.x,s.y-pc.id)) -- subtract capturing pawn
		elseif abs(pc.id)==1 and (s.y==1 or s.y==8) then
			local prom
			if love.keyboard.isDown("2") then
				prom = 2
			elseif love.keyboard.isDown("3") then
				prom = 3
			elseif love.keyboard.isDown("4") then
				prom = 4
			else
				prom = 5
			end
			new,alg = queening(pos,l,s,prom*pc.id)
		else
			new,alg = normal(pos,l,s)
		end
		alg = clearly(self.possible,l,s,alg)
		print(alg)
		-- new turn data
		if abs(new[s]) == 1 and abs(l.y-s.y)==2 then
			eptoken = loc:new( s.x, s.y-pc.id ) -- subtract pushed pawn
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
			drawCount = 0	--leaving it nil is okay, this is doubly unnecessary
		end
		return Turn:new(new,self.turn+1,fmap,eptoken,{l,s},drawCount),alg
	end
	return t
end
