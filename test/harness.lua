-- Offline end-to-end test for the Passive Picker. Builds a fake game in memory
-- (a fake game.dll image holding the signatures, a catalog, ownership, a
-- loadout screen with one player card, the player cache), a fake Gui and a
-- fake mouse, then runs the built mod against it frame by frame.
--   luajit test/harness.lua <built lua> <data/sigs.json> <scratch dir> [nofont|badinput|saved]   (stdin closed)
-- Windows calls are replaced with stand-ins, so this proves the mod's own
-- logic, not the game's layout or the engine calls.
local built, sigs_path, scratch, mode = arg[1], arg[2], arg[3], arg[4]
local ffi = require("ffi")
local bit = require("bit")

local failures = 0
local function check(ok, what)
	if ok then print("  ok    " .. what) else failures = failures + 1 print("  FAIL  " .. what) end
end

-- ---------------------------------------------------------------- fake memory
local buffers = {}
local function alloc(n)
	local b = ffi.new("uint8_t[?]", n)
	local at = tonumber(ffi.cast("uintptr_t", b))
	buffers[#buffers + 1] = { b = b, at = at, n = n }
	return at
end
local function w32(a, v) ffi.cast("uint32_t *", a)[0] = v end
local function r32(a) return tonumber(ffi.cast("uint32_t *", a)[0]) end
local function wf(a, v) ffi.cast("float *", a)[0] = v end
local function wptr(a, v) ffi.cast("uint64_t *", a)[0] = v end

-- signatures from the data file (flat objects, so patterns are enough)
local sigs = {}
do
	local f = assert(io.open(sigs_path)); local text = f:read("*a"); f:close()
	for obj in text:gmatch("%b{}") do
		sigs[#sigs + 1] = { name = obj:match('"name": "(.-)"'), hex = obj:match('"hex": "(.-)"'),
			symbol = obj:match('"symbol": "(.-)"'), off = tonumber(obj:match('"extract_offset": (%d+)')),
			stop = tonumber(obj:match('"extract_end": (%d+)')) }
	end
	assert(#sigs == 9 or #sigs == 8, "expected 9 signatures (8 in the public build), got " .. #sigs)
end
-- the public build is published under another name, so its files and its global carry that name
local NAME = #sigs == 8 and "SimpleArmorPassivePicker" or "PassivePicker"
-- default spot of the box on the loadout page (the public build starts above the EQUIPMENT button)
local BX, BY = 213, #sigs == 8 and 54 or -44
-- the box label is centered: where a label starts inside the 201-wide box at the default text size
local function TX(value) return (201 - #value * (#sigs == 8 and 15 or 13) * 0.55) / 2 end
-- the class box: as wide as the passive box, on the left half of the card (6 from each edge, 6 between)
local CBX = BX - 207

local IMAGE = 0x200000
local image = alloc(IMAGE)
w32(image + 0x3C, 0x100); w32(image + 0x100, 0x00004550); w32(image + 0x108, 12345); w32(image + 0x150, IMAGE)
local slot_of, next_slot, placed, next_code = {}, 0x100000, {}, 0x1000
slot_of.card_widget = image + 0x190000   -- a function, not a data slot: it needs room for its body
slot_of.input_consume = image + 0x1d0000   -- likewise: the mod reaches the consume-input function through a call to it
for _, s in ipairs(sigs) do
	local skip = mode == "nofont" and (s.symbol == "font" or s.symbol == "atlas" or s.symbol == "material")
	if not skip then
		local at = placed[s.hex]
		if not at then
			at = image + next_code; next_code = next_code + 0x1000; placed[s.hex] = at
			local p = ffi.cast("uint8_t *", at)
			for i = 1, #s.hex, 2 do p[(i - 1) / 2] = tonumber(s.hex:sub(i, i + 1), 16) end
		end
		if not slot_of[s.symbol] then slot_of[s.symbol] = image + next_slot; next_slot = next_slot + 16 end
		local rel = slot_of[s.symbol] - (at + s.stop)
		ffi.cast("int32_t *", at + s.off)[0] = rel
	end
end

-- the game's consume-input function: its global load and the three field offsets it clears
local consume_fn = slot_of.input_consume
local input_slot, input_obj = image + 0x180000, alloc(0x400)
do
	local p = ffi.cast("uint8_t *", consume_fn)
	p[40], p[41], p[42] = 0x48, 0x8B, 0x0D
	ffi.cast("int32_t *", consume_fn + 43)[0] = input_slot - (consume_fn + 47)
	p[60], p[61] = 0x28, 0x03; p[70], p[71] = 0x2C, 0x03; p[80], p[81] = 0x34, 0x03
	if mode == "badinput" then p[80] = 0x35 end
end
wptr(input_slot, input_obj)

-- the game's card refresh and the tile function it calls, with the call and the skip test the mod looks for
local refresh_fn, tiles_fn
for hex, at in pairs(placed) do if #hex == 800 then refresh_fn = at end end
local public = refresh_fn == nil   -- the public build's signature list has no card refresh: there is no redraw to test
if public then refresh_fn = image + 0x1f0000 end   -- still given a body below, so a public build that looked for it would find it
tiles_fn = image + 0x1a0000
do
	local call = { 0x49, 0x8D, 0x8E, 0xA0, 0xDB, 0, 0, 0x45, 0x0F, 0xB6, 0xC7, 0x49, 0x8B, 0xD4, 0xE8 }
	local p = ffi.cast("uint8_t *", refresh_fn + 0x185)
	for i, b in ipairs(call) do p[i - 1] = b end
	ffi.cast("int32_t *", refresh_fn + 0x194)[0] = tiles_fn - (refresh_fn + 0x198)
	local body = { 0x48, 0x8B, 0xA9, 0x08, 0x83, 0, 0, 0x41, 0x0F, 0xB6, 0xF0, 0x48, 0x8B, 0xFA, 0x48, 0x8B, 0xD9,
		0x48, 0x3B, 0xEA, 0x75, 0x0D, 0x44, 0x38, 0x81, 0x1C, 0x83, 0, 0, 0x0F, 0x84 }
	p = ffi.cast("uint8_t *", tiles_fn + 0x14)
	for i, b in ipairs(body) do p[i - 1] = b end
	if mode == "badinput" then p[3] = 0x09 end
end
-- the refresh's closing jump to the card layout function, that function's call to the picture routine, and its start
local layout_fn, thumbs_fn = image + 0x1b0000, image + 0x1c0000
do
	local function put(at, bytes) local p = ffi.cast("uint8_t *", at); for i, b in ipairs(bytes) do p[i - 1] = b end end
	put(refresh_fn + 0x252, { 0x45, 0x33, 0xC0, 0xB2, 0x01, 0x48, 0x8B, 0xCD, 0x48, 0x83, 0xC4, 0x60, 0x5D, 0xE9 })
	ffi.cast("int32_t *", refresh_fn + 0x260)[0] = layout_fn - (refresh_fn + 0x264)
	put(layout_fn + 0x224, { 0x80, 0xBB, 0x11, 0xEE, 0x01, 0, 0, 0x75, 0x15, 0x83, 0xBB, 0x18, 0xB8, 0x01, 0, 0x01,
		0x75, 0x0C, 0x48, 0x8D, 0x8B, 0xF8, 0x34, 0x01, 0, 0xE8 })
	ffi.cast("int32_t *", layout_fn + 0x23e)[0] = thumbs_fn - (layout_fn + 0x242)
	put(thumbs_fn, { 0x48, 0x8B, 0xC4, 0x55, 0x48, 0x81, 0xEC, 0xA0, 0, 0, 0, 0x48, 0x83, 0xB9, 0x08, 0x83, 0, 0, 0 })
end

-- catalog (also the customization manager) with three armors
-- each armor's body list: two bodies (types 0 and 1), pieces as { slot, kind, weight }
-- armor 1 is light, armor 2 mixes weights, armor 3 (worn) is medium
local ARMOR = {
	{ id = 530315896, p = 6, pieces = { { 2, 0, 0 }, { 4, 0, 0 }, { 5, 0, 0 }, { 2, 1, 0 } } },
	{ id = 3544585106, p = 3, pieces = { { 2, 0, 1 }, { 4, 0, 0 }, { 6, 2, 3 } } },
	{ id = 3672418116, p = 8, pieces = { { 2, 0, 1 }, { 4, 0, 1 }, { 7, 0, 1 }, { 2, 2, 0 }, { 9, 0, 3 } } },
}
local catalog = alloc(0x1000)
local kits = alloc(8 * #ARMOR)
for i, a in ipairs(ARMOR) do
	-- like the game's, records are only 4-byte aligned: armor 2 sits at 4 past an 8-byte boundary, and
	-- armor 1 so that its body list pointer (+48) straddles a cache line
	local room = alloc(256)
	local want = i == 1 and 12 or i == 2 and 4 or 0
	a.at = room + (want - room % 64) % 64
	w32(a.at, a.id); w32(a.at + 28, a.p); wptr(kits + (i - 1) * 8, a.at)
	a.list = alloc(48)
	for b = 0, 1 do
		local pieces = alloc(96 * #a.pieces)
		for k, piece in ipairs(a.pieces) do
			local at = pieces + (k - 1) * 96
			w32(at, 0x1000 + k); w32(at + 8, piece[1]); w32(at + 12, piece[2]); w32(at + 16, piece[3]); w32(at + 40, 0xabcd)
		end
		w32(a.list + b * 24, b); wptr(a.list + b * 24 + 8, pieces); w32(a.list + b * 24 + 16, #a.pieces)
	end
	wptr(a.at + 48, a.list); w32(a.at + 56, 2)
end
local function r64(a) return tonumber(ffi.cast("uint64_t *", a)[0]) end
-- the weights an armor's record points at now: { body1 = {w, w, ...}, body2 = ... } and its kinds and slots
local function weights(a)
	local list, out = r64(a.at + 48), {}
	for b = 0, r32(a.at + 56) - 1 do
		local pieces, n, ws = r64(list + b * 24 + 8), r32(list + b * 24 + 16), {}
		for k = 0, n - 1 do
			local at = pieces + k * 96
			ws[#ws + 1] = string.format("%d.%d.%d.%x", r32(at + 8), r32(at + 12), r32(at + 16), r32(at + 40))
		end
		out[#out + 1] = r32(list + b * 24) .. ":" .. table.concat(ws, " ")
	end
	return table.concat(out, " | ")
end
wptr(catalog, kits); w32(catalog + 8, #ARMOR)
wptr(slot_of.armor_catalog, catalog)
local rows = alloc(4 * 8)
for i = 0, 3 do w32(rows + i * 8, 0xffffffff) end
w32(rows + 3 * 8, 7); w32(rows + 3 * 8 + 4, 0)        -- player id 7 -> customization slot 0
wptr(catalog + 0x930, rows); w32(catalog + 0x938, 4); w32(catalog + 0x93c, 0xffffffff); w32(catalog + 0x940, 1)
local cache = catalog + 0x96c
w32(cache + 12, ARMOR[3].id); w32(cache + 0x3c, ARMOR[3].p); w32(catalog + 0xa7c + 12, ARMOR[3].id)

-- players
local players, player = alloc(0x200), alloc(0x40)
w32(players + 0x84, 1); w32(players + 0x88, 1); wptr(players + 0xe8, player); w32(player + 8, 7)
wptr(slot_of.players, players)

-- progression: armors 1 and 2 owned, armor 3 not
local progression = alloc(0xC0000)
w32(progression + 0x1ce0, #ARMOR)
for i, a in ipairs(ARMOR) do
	local e = progression + 0xb9ce4 + (i - 1) * 24
	w32(e, i - 1); w32(e + 8, a.id)
	w32(progression + 0x1ce4 + (i - 1) * 184 + 0x14, i < 3 and 2 or 0)
end
wptr(slot_of.progression, progression)

-- manager, loadout owner, the player card and its EQUIPMENT button
local manager, owner = alloc(0x7000), alloc(0x280000)
w32(manager + 0x62a0, 1); wptr(manager + 0x62a8, owner); w32(manager + 0x62b0, 0xe5)
wptr(slot_of.manager, manager)
w32(owner + 8, 1); w32(owner + 0x27d0, 0)
local payload = owner + 0x10
w32(payload + 0x12c, ARMOR[3].id)
local card = owner + 0x53a78 + 2 * 0x1ee18
wptr(card + 0x1edf0, payload); w32(card + 0x1edfc, 0)
local w8 = function (a, v) ffi.cast("uint8_t *", a)[0] = v end
local r8 = function (a) return ffi.cast("uint8_t *", a)[0] end
local card_widget = card + 0x5958 + 0xdba0     -- what the card's equipment tiles last drew: payload pointer and "local card" byte
w32(card + 0x5958 + 0x15ec0, 1); w8(card + 0x1ee11, 0); w32(card + 0x1b818, 1)   -- equipment page showing, card open and settled
w8(card + 0x1ee0c, 1); w8(card + 0x1ee0e, 0); wptr(card_widget + 0x8308, payload); w8(card_widget + 0x831c, 1)
local widget = card + 0x1b820
w32(widget, 0x10); wf(widget + 84, 1); wf(widget + 100, 1); wf(widget + 140, 1)
wf(widget + 148, 55); wf(widget + 156, 366); wf(widget + 36, 420); wf(widget + 40, 42)

-- font: two ids in the image, one behind a pointer
if mode ~= "nofont" then
	wptr(slot_of.font, 0x1111111122222222ULL); wptr(slot_of.atlas, 0x3333333344444444ULL)
	local holder = alloc(64); wptr(holder + 24, 0x5555555566666666ULL); wptr(slot_of.material, holder)
end

-- ---------------------------------------------------------------- fake Windows
local keys, mouse = {}, { x = 5, y = 5, down = false, focused = true }
local kernel = {
	VirtualQuery = function (address, region, size)
		local a = tonumber(ffi.cast("uintptr_t", address))
		local r = region[0]
		for _, b in ipairs(buffers) do
			if a >= b.at and a < b.at + b.n then
				r.base = ffi.cast("void *", b.at); r.size = b.n; r.state = 0x1000; r.protection = 0x04
				return size
			end
		end
		r.base = ffi.cast("void *", a - a % 4096); r.size = 4096; r.state = 0x10000; r.protection = 1
		return size
	end,
	GetModuleHandleA = function () return ffi.cast("void *", image) end,
	VirtualProtect = function () return 0 end,
	GetCurrentProcessId = function () return 42 end,
}
local window = ffi.cast("void *", 0x1234)
local user = {
	GetAsyncKeyState = function (vk) return keys[vk] and -32768 or 0 end,
	GetForegroundWindow = function () return mouse.focused and window or nil end,
	GetWindowThreadProcessId = function (_, pid) ffi.cast("uint32_t *", pid)[0] = 42 return 1 end,
	GetCursorPos = function (p) local q = ffi.cast("int32_t *", p) q[0], q[1] = mouse.x, mouse.y return 1 end,
	ScreenToClient = function () return 1 end,
	GetClientRect = function (_, p) local q = ffi.cast("int32_t *", p) q[0], q[1], q[2], q[3] = 0, 0, 1920, 1080 return 1 end,
}
ffi.load = function (name) return name == "kernel32" and kernel or user end

-- ---------------------------------------------------------------- fake engine
local MAIN, MENU = { "main" }, { "menu" }
local live = {}           -- surfaces that exist right now
local created, destroyed = 0, 0
local function callable(extra)
	return setmetatable(extra or {}, { __call = function (_, ...) return { ... } end })
end
rawset(_G, "stingray", {
	Application = { worlds = function () return { MAIN, MENU } end, main_world = function () return MAIN end },
	World = {
		create_screen_gui = function (world) created = created + 1
			local g = { world = world, rects = {}, texts = {} } live[g] = true return g end,
		destroy_gui = function (_, g) assert(live[g], "destroying a surface twice") destroyed = destroyed + 1 live[g] = nil end,
	},
	Gui = {
		resolution = function () return 1920, 1080 end,
		material = function () return {} end,
		rect = function (g, pos, size) g.rects[#g.rects + 1] = { x = pos[1], y = pos[2], w = size[1], h = size[2] } end,
		text = function (g, value, _, size, _, pos) g.texts[#g.texts + 1] = { text = value, size = size, x = pos[1], y = pos[2] } end,
		text_extents = function (_, value, _, size) return { 0, 0 }, { #value * size * 0.55, size } end,
	},
	Material = { set_scalar = function () end, set_vector2 = function () end, set_vector4 = function () end, set_texture = function () end },
	IdString64 = { from_hex = function (s) assert(#s == 16, "bad id " .. tostring(s)) return s end },
	Vector2 = callable({ x = function (v) return v[1] end }), Vector3 = callable(), Color = callable(),
	Mouse = { button_id = function () return 0 end, button = function () return mouse.down and 1 or 0 end },
})

local diverkit = { collapsed = false, visible = true }
rawset(_G, "CodexLoadouts", diverkit)
local frames = 0
rawset(_G, "update", function () frames = frames + 1 end)
local shut = false
rawset(_G, "shutdown", function () shut = true end)

-- ---------------------------------------------------------------- run
local getenv = os.getenv
os.getenv = function (name) if name == "LOCALAPPDATA" then return scratch end return getenv(name) end
os.execute('mkdir -p "' .. scratch .. '/CowboyBingus/Helldivers2/Logs"')
local LOGDIR = scratch .. "/CowboyBingus/Helldivers2/Logs/"
os.remove(LOGDIR .. NAME .. ".cfg")
os.remove(LOGDIR .. NAME .. ".saved")
local function saved_text() local f = io.open(LOGDIR .. NAME .. ".saved"); if not f then return "" end local t = f:read("*a"); f:close(); return t end
if mode == "saved" then
	-- a saved file from an earlier run: armor 3 kept on FORTIFIED and heavy, armor 1 on its own passive but medium
	-- (an older line without a class), plus rubbish and an armor that does not exist
	local f = assert(io.open(LOGDIR .. NAME .. ".saved", "w"))
	f:write("# old\r\n3672418116 = 3, 2   # x\r\nnonsense\r\n3672418116 = 999\r\n12345 = 6\r\n530315896 = 6\r\n3544585106 = 3, -\r\n"); f:close()
end
do   -- a log from the session before, and a stale one from the session before that
	local f = assert(io.open(LOGDIR .. NAME .. ".log", "w")); f:write("OLD SESSION\n"); f:close()
	f = assert(io.open(LOGDIR .. NAME .. ".previous.log", "w")); f:write("STALE\n"); f:close()
end
assert(assert(loadfile(built))() == true)
local update = rawget(_G, "update")
local function run(n) for _ = 1, n do update() end end
local function surface() local g, count = nil, 0 for s in pairs(live) do g = s count = count + 1 end return g, count end
local function find_text(g, value) for _, t in ipairs(g and g.texts or {}) do if t.text == value then return t end end end
local function point_at(gx, gy) mouse.x, mouse.y = math.floor(gx), math.floor(1080 - gy) end
local function click_at(gx, gy)
	point_at(gx, gy); mouse.down = false; run(2); mouse.down = true; run(2); mouse.down = false; run(2)
end
local function log_text() local f = assert(io.open(LOGDIR .. NAME .. ".log")); local t = f:read("*a"); f:close(); return t end
local picker = rawget(_G, #sigs == 8 and "SimpleArmorPassivePicker" or "JarvisPassivePicker")
local consumed = {}       -- every call the mod makes to the game's consume-input function
picker.test.native.executable = function (at) return at == consume_fn or at == refresh_fn or at == tiles_fn or at == layout_fn or at == thumbs_fn end
local refreshed, widget_rebuilds = {}, true   -- every card refresh the mod asks for; the fake game rebuilds unless told not to
picker.test.native.refresh = function (at, c, p, mine, card_mode)
	refreshed[#refreshed + 1] = { at = at, card = c, payload = p, mine = mine, mode = card_mode, flag = r8(card_widget + 0x831c) }
	if widget_rebuilds then w8(card_widget + 0x831c, 1) end
end
local pictured = {}   -- every call the mod makes to the game's picture routine
picker.test.native.thumbs = function (at, t) pictured[#pictured + 1] = { at = at, tiles = t, flag = r8(card_widget + 0x831c) } end
picker.test.native.consume = function (at, holder, action) consumed[#consumed + 1] = { at = at, holder = holder, action = action } end

print("discovery (" .. (mode or "normal") .. ")")
run(3000)
local text = log_text()
check(text:find("DISCOVERY OK", 1, true), "discovery finished")
check(text:find("2 body armors owned", 1, true), "two of three armors owned")
check(not text:find("stopped", 1, true), "nothing stopped")

if mode == "badinput" then
	print("consume function body differs")
	check(text:find("input: key blocking off, input function body differs", 1, true), "log says key blocking is off")
	click_at(55 + BX + 80, 366 + BY + 14); run(30)
	check(find_text(surface(), "FORTIFIED") ~= nil, "grid still opens")
	check(#consumed == 0, "the game function is never called")
	keys[0x41] = true; run(2); keys[0x41] = nil; run(2); keys[0x20] = true; run(2); keys[0x20] = nil; run(2)
	check(r32(ARMOR[3].at + 28) == 6, "keyboard pick still works")
	check(public or text:find("redraw: off, tile function body differs", 1, true), "log says the redraw is off when the tile function differs")
	w32(payload + 0x60, 777); run(80)
	check(#refreshed == 0, "no card refresh is asked for")
elseif mode == "saved" then
	print("hard-set passives from the saved file")
	check(r32(ARMOR[3].at + 28) == 3, "saved passive written into the armor record at start")
	check(r32(ARMOR[1].at + 28) == 6 and r32(ARMOR[2].at + 28) == 3, "other armors untouched")
	check(r32(cache + 0x3c) == 3, "worn armor's saved passive pushed to the player cache")
	check(text:find("hard set: 1 armor(s) given their saved class and passive", 1, true), "log counts one armor")
	check(weights(ARMOR[3]):find("^0:2%.0%.2%.abcd 4%.0%.2") ~= nil and r64(ARMOR[1].at + 48) == ARMOR[1].list and r64(ARMOR[2].at + 48) == ARMOR[2].list,
		"saved class written at start, other armors keep their own")
	check(find_text(surface(), "FORTIFIED [SET]") ~= nil and find_text(surface(), "ARMOR RATING 150 [SET]") ~= nil, "both boxes mark what is set (a 1.1.0 heavy line read as 150)")
	keys[0x78] = true; run(2); keys[0x78] = nil; run(40)
	check(r32(ARMOR[3].at + 28) == 3 and r32(cache + 0x3c) == 3, "F9 does nothing any more")
	click_at(55 + BX + 80, 366 + BY + 14)
	local own = find_text(surface(), "SERVO-ASSISTED *")
	click_at(own.x + 20, own.y + 2); point_at(1500, 200); run(40)
	check(r32(ARMOR[3].at + 28) == 8 and r32(cache + 0x3c) == 8, "a grid pick of the armor's own passive puts record and cache back")
	check(find_text(surface(), "SERVO-ASSISTED") ~= nil, "box drops the mark")
	keys[0x75] = true; run(2); keys[0x75] = nil; run(2)
	check(saved_text():find("3672418116 = 8, 150", 1, true), "F6 with only the rating changed saves the rating")
	check(find_text(surface(), "ARMOR RATING 150 [SET]") ~= nil and find_text(surface(), "SERVO-ASSISTED") ~= nil, "the rating box keeps its mark, the passive box has none")
	click_at(55 + CBX + 40, 366 + BY + 13)
	own = find_text(surface(), "ORIGINAL (100)")
	click_at(own.x + 10, own.y + 2); point_at(1500, 200); run(3)
	keys[0x75] = true; run(2); keys[0x75] = nil; run(2)
	check(not saved_text():find("3672418116", 1, true), "F6 on the armor's own class and passive forgets the saved one")
	check(not saved_text():find("3544585106", 1, true), "an entry with nothing changed is dropped")
	check(saved_text():find("12345 = 6", 1, true), "an entry for an armor this game does not have is kept")
	check(not saved_text():find("530315896", 1, true), "an entry equal to the armor's own passive is dropped")
elseif mode == "nofont" then
	print("box without the font signatures")
	local _, count = surface()
	check(count == 0, "no surface drawn")
	check(text:find("needs 'font' is off", 1, true), "log says the font feature is off")
	check(text:find("box: waiting, font signatures not found", 1, true), "log says the box is waiting")
	keys[0x77] = true; run(2); keys[0x77] = nil; run(2)
	check(r32(ARMOR[3].at + 28) == 8, "F8 does nothing any more")
	keys[0x79] = true; run(2); keys[0x79] = nil; run(2)
	check(r32(ARMOR[3].at + 28) == 8 and not log_text():find("F10", 1, true), "F10 does nothing any more")
else
	print("box")
	local g, count = surface()
	check(count == 1, "exactly one surface")
	local label = find_text(g, "SERVO-ASSISTED")
	check(label ~= nil, "box shows the worn armor's passive")
	check(label and label.x > 55 + BX and label.x < 55 + 420, "box sits at its default left edge")
	check(label and label.y > 366 + BY and label.y < 366 + BY + 26, "box sits at its default height")
	check(io.open(LOGDIR .. NAME .. ".cfg") ~= nil, "settings file written")

	print("hover, open, pick")
	local before = created
	run(300)
	check(created == before, "nothing redrawn while nothing changes")
	point_at(55 + BX + 80, 366 + BY + 14); run(3)
	check(created == before + 1, "one redraw on hover")
	click_at(55 + BX + 80, 366 + BY + 14)
	g = surface()
	check(find_text(g, "ARMOR PASSIVE   (* = this armor's own)   W A S D + SPACE") ~= nil, "grid opens on a click")
	check(find_text(g, "SERVO-ASSISTED *") ~= nil, "the unowned armor's own passive is offered and marked")
	check(find_text(g, "ENGINEERING KIT") ~= nil and find_text(g, "FORTIFIED") ~= nil, "owned passives listed")
	local cell = find_text(g, "ENGINEERING KIT")
	click_at(cell.x + 20, cell.y + 2)
	check(r32(ARMOR[3].at + 28) == 6, "pick written to the armor record")
	check(r32(cache + 0x3c) == 6, "pick written to the player cache")
	check(r32(ARMOR[1].at + 28) == 6 and r32(ARMOR[2].at + 28) == 3, "other armors untouched")
	g = surface()
	check(find_text(g, "ENGINEERING KIT") ~= nil and find_text(g, "FORTIFIED") == nil, "grid closed, box shows the pick")

	print("pick the armor's own passive, outside click, held button")
	click_at(55 + BX + 80, 366 + BY + 14)
	cell = find_text(surface(), "SERVO-ASSISTED *")
	click_at(cell.x + 20, cell.y + 2)
	check(r32(ARMOR[3].at + 28) == 8 and r32(cache + 0x3c) == 8, "own passive restored in record and cache")
	click_at(55 + BX + 80, 366 + BY + 14)
	check(find_text(surface(), "FORTIFIED") ~= nil, "grid open again")
	click_at(1500, 200)
	check(find_text(surface(), "FORTIFIED") == nil, "click outside closes the grid")
	check(r32(ARMOR[3].at + 28) == 8, "outside click changes nothing")
	-- a drag that starts outside and ends on the box is not a click
	point_at(1500, 200); mouse.down = false; run(2); mouse.down = true; run(2)
	point_at(55 + BX + 80, 366 + BY + 14); run(2); mouse.down = false; run(2)
	check(find_text(surface(), "FORTIFIED") == nil, "press elsewhere, release on the box: not a click")

	print("cache holding another armor")
	w32(cache + 12, ARMOR[1].id)
	click_at(55 + BX + 80, 366 + BY + 14)
	cell = find_text(surface(), "FORTIFIED")
	click_at(cell.x + 20, cell.y + 2)
	check(r32(ARMOR[3].at + 28) == 3, "record still written")
	check(r32(cache + 0x3c) == 8, "cache left alone when it holds a different armor")
	check(log_text():find("cache not written: it holds armor", 1, true), "and the log says so")
	w32(cache + 12, ARMOR[3].id)

	print("a settings file from before the class box")
	do
		local f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w"))
		f:write("# Passive Picker: where the box and the grid sit on the player card.\r\nbox_x = 133\r\nbox_y = " .. BY .. "\r\nbox_w = 166\r\neq_box_x = 134\r\ngrid_alpha = 99\r\n"); f:close()
		point_at(1500, 200); run(130)
		local h = assert(io.open(LOGDIR .. NAME .. ".cfg")); local t = h:read("*a"); h:close()
		check(t:find("box_x = 213\r\n", 1, true) and t:find("box_w = 201\r\n", 1, true) and t:find("eq_box_x = 213\r\n", 1, true) and t:find("class_w = 201\r\n", 1, true),
			"box spots reset once and the file rewritten with the class box")
		check(t:find("grid_alpha = 99\r\n", 1, true) and log_text():find("settings: file from before the class box", 1, true), "other settings kept, and the log says so")
		local label = find_text(surface(), "ARMOR RATING 100")
		check(label and math.abs(label.x - (55 + 6 + TX("ARMOR RATING 100"))) < 1.5, "the boxes split the card")
		f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); run(130)
	end

	print("settings re-read live")
	local f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w"))
	f:write("# moved\r\nbox_x = 10\r\nbox_y = -100\r\ngrid_cols = 9\r\nnonsense = 4\r\n"); f:close()
	point_at(1500, 200); run(130)
	label = find_text(surface(), "FORTIFIED")
	check(label and math.abs(label.x - (55 + 10 + TX("FORTIFIED"))) < 1.5 and label.y < 366 - 80, "box moved after the settings file changed")
	check(picker.test.parse_cfg("grid_cols = 9\ncell_h = 1\nbox_x = abc").grid_cols == 4, "columns clamped to 4")
	check(picker.test.parse_cfg("cell_h = 1").cell_h == 6, "tiny sizes clamped")
	check(picker.test.parse_cfg("").box_alpha == (#sigs == 8 and 195 or 215) and picker.test.parse_cfg("").grid_alpha == (#sigs == 8 and 170 or 238), "background defaults")
	check(picker.test.parse_cfg("box_alpha = 900\ngrid_alpha = -3").box_alpha == 255 and picker.test.parse_cfg("grid_alpha = -3").grid_alpha == 0, "background values kept between 0 and 255")
	check(picker.test.parse_cfg("box_x = abc").box_x == BX, "rubbish value falls back to the default")

	print("one box, whatever DiverKit's panel is doing")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\nbtn_x = 10\r\n"); f:close()
	w32(payload + 0x12c, ARMOR[1].id); point_at(1500, 200); run(130)
	check(r32(ARMOR[3].at + 28) == 8 and log_text():find("REVERT ", 1, true), "a pick is dropped once another armor is worn")
	for _, case in ipairs({ { "open", false }, { "collapsed", true }, { "absent", nil } }) do
		if case[1] == "absent" then rawset(_G, "CodexLoadouts", nil) else diverkit.collapsed = case[2] end
		run(3)
		g = surface()
		label = find_text(g, "ENGINEERING KIT")
		check(label and find_text(g, "PASSIVE") == nil and #g.texts == 2 and find_text(g, "ARMOR RATING 50") ~= nil, case[1] .. ": the two boxes and nothing else, no square button")
		check(label and label.x > 55 + BX and label.x < 55 + 420 and label.y > 366 + BY and label.y < 366 + BY + 26,
			case[1] .. ": box on the MISSION STRATAGEMS line")
		click_at(55 + 380, 366 + 174)
		check(find_text(surface(), "FORTIFIED") == nil, case[1] .. ": a click where the square button was does nothing")
		click_at(55 + BX + 80, 366 + BY + 13)
		check(find_text(surface(), "FORTIFIED") ~= nil, case[1] .. ": click on the box opens the grid")
		click_at(1500, 200)
	end
	rawset(_G, "CodexLoadouts", diverkit); diverkit.collapsed = false
	w32(payload + 0x12c, ARMOR[3].id); run(3)
	click_at(55 + BX + 80, 366 + BY + 14)
	cell = find_text(surface(), "FORTIFIED")
	click_at(cell.x + 20, cell.y + 2); point_at(1500, 200); run(3)

	print("keyboard in the grid")
	-- strip in use, armor 3 worn, its record at FORTIFIED (3). Grid: column 1 = ENGINEERING KIT, FORTIFIED; column 2 = SERVO-ASSISTED
	local W, A, S, D, SPACE = 0x57, 0x41, 0x53, 0x44, 0x20
	local function tap(vk) keys[vk] = true; run(2); keys[vk] = nil; run(2) end
	local function open_grid() click_at(55 + BX + 80, 366 + BY + 14); point_at(1500, 200); run(3) end
	local function is_open() return find_text(surface(), "ARMOR PASSIVE   (* = this armor's own)   W A S D + SPACE") ~= nil end
	check(r32(ARMOR[3].at + 28) == 3, "starting from FORTIFIED")
	tap(SPACE); tap(S)
	check(not is_open() and r32(ARMOR[3].at + 28) == 3, "keys do nothing while the grid is closed")
	open_grid(); tap(W); tap(SPACE)
	check(r32(ARMOR[3].at + 28) == 6 and r32(cache + 0x3c) == 6, "W then Space picks the passive above, record and cache")
	check(not is_open(), "Space closes the grid")
	open_grid(); tap(S); tap(S); tap(W); tap(SPACE)
	check(r32(ARMOR[3].at + 28) == 3, "S and W wrap around the column")
	open_grid(); tap(D); tap(S); tap(SPACE)
	check(r32(ARMOR[3].at + 28) == 8, "D moves to the next column, S stays inside a short column")
	open_grid(); tap(A); tap(SPACE)
	check(r32(ARMOR[3].at + 28) == 6, "A moves back a column")
	keys[D] = true; run(2); open_grid(); run(60); keys[D] = nil; run(2); tap(SPACE)
	check(r32(ARMOR[3].at + 28) == 6, "a key already held when the grid opens does not move the highlight")
	open_grid(); keys[S] = true; run(200); keys[S] = nil; run(2)
	check(is_open() and not log_text():find("stopped", 1, true), "holding a key repeats without trouble")
	cell = find_text(surface(), "SERVO-ASSISTED *")
	point_at(cell.x + 20, cell.y + 2); run(3); tap(SPACE)
	check(r32(ARMOR[3].at + 28) == 8, "the mouse moves the same highlight, Space picks it")
	open_grid(); tap(A)
	cell = find_text(surface(), "FORTIFIED")
	click_at(cell.x + 20, cell.y + 2)
	check(r32(ARMOR[3].at + 28) == 3, "a click still picks what is clicked, wherever the highlight is")
	mouse.focused = false; open_grid(); mouse.focused = true; run(3)
	check(not is_open(), "nothing opens while the window is not focused")
	point_at(1500, 200); run(3)

	print("class box and its grid")
	-- armor 3 (medium) worn, passive FORTIFIED
	local STOCK3 = weights(ARMOR[3])
	local CTITLE = "ARMOR RATING   W S + SPACE"
	local function class_open() return find_text(surface(), CTITLE) ~= nil end
	local function open_class() click_at(55 + CBX + 40, 366 + BY + 13); point_at(1500, 200); run(3) end
	local cbox = find_text(surface(), "ARMOR RATING 100")
	check(cbox and math.abs(cbox.x - (55 + 6 + TX("ARMOR RATING 100"))) < 1.5 and cbox.y > 366 + BY and cbox.y < 366 + BY + 26, "class box on the left half of the card, showing the armor's rating")
	local pbox = find_text(surface(), "FORTIFIED")
	check(pbox and math.abs(pbox.x - (55 + 213 + TX("FORTIFIED"))) < 1.5 and math.abs(pbox.y - cbox.y) < 0.5, "passive box on the right half, on the same line")
	do
		local lay = picker.test.layout({ x = 55, y = 366, w = 420, h = 42 }, {}, 1920, 1080, nil, nil, { 0, 1, 2, "own" })
		local c, b = lay.cbox, lay.box
		check(c.w == b.w and math.abs((c.x - 55) - 6) < 0.01 and math.abs(b.x - (c.x + c.w) - 6) < 0.01 and math.abs((55 + 420) - (b.x + b.w) - 6) < 0.01,
			"the two boxes are the same width with equal gaps at both edges and between them")
	end
	check(find_text(surface(), "FORTIFIED") ~= nil, "the passive box shows the passive alone")
	open_class()
	do
		local want, ok = { "50", "67", "83", "100", "133", "150", "ORIGINAL (100)" }, class_open()
		for _, v in ipairs(want) do ok = ok and find_text(surface(), v) ~= nil end
		check(ok and not find_text(surface(), "64") and not find_text(surface(), "79"), "rating grid: the stock ratings as near as three rated slots make them (64 and 70 both 67), and ORIGINAL")
	end
	check(not find_text(surface(), "100 *"), "no star marks")
	check(find_text(surface(), "ENGINEERING KIT") == nil and not is_open(), "no passives in it")
	local heavy = find_text(surface(), "150")
	click_at(heavy.x + 10, heavy.y + 2); point_at(1500, 200); run(3)
	check(not class_open() and find_text(surface(), "ARMOR RATING 150") ~= nil and find_text(surface(), "FORTIFIED") ~= nil, "a pick closes the grid, the boxes show ARMOR RATING 150 and the same passive")
	check(weights(ARMOR[3]) == "0:2.0.2.abcd 4.0.2.abcd 7.0.2.abcd 2.2.0.abcd 9.0.3.abcd | 1:2.0.2.abcd 4.0.2.abcd 7.0.2.abcd 2.2.0.abcd 9.0.3.abcd",
		"every rated piece heavy in both bodies; other kinds, the none weight and all other bytes untouched")
	local list_heavy = r64(ARMOR[3].at + 48)
	check(list_heavy ~= ARMOR[3].list and r32(ARMOR[3].at + 56) == 2, "the record points at a copy, body count unchanged")
	check(log_text():find("CLASS SA-25 Steel Trooper: ARMOR RATING 100 -> ARMOR RATING 150", 1, true) and log_text():find("  cache before ", 1, true), "log shows the change and the cache around it")
	check(r32(ARMOR[3].at + 28) == 3 and r32(r64(ARMOR[3].list + 8) + 16) == 1, "the passive and the game's own pieces are untouched")
	open_class(); click_at(55 + BX + 80, 366 + BY + 14); point_at(1500, 200); run(3)
	check(is_open() and not class_open(), "a click on the passive box switches to the passive grid")
	click_at(1500, 200)
	open_class(); local own = find_text(surface(), "ORIGINAL (100)"); click_at(own.x + 10, own.y + 2); point_at(1500, 200); run(3)
	check(r64(ARMOR[3].at + 48) == ARMOR[3].list and weights(ARMOR[3]) == STOCK3, "the armor's own class puts its own body list back")
	open_class(); heavy = find_text(surface(), "150"); click_at(heavy.x + 10, heavy.y + 2); point_at(1500, 200); run(3)
	check(r64(ARMOR[3].at + 48) == list_heavy, "the same copy is used again")
	open_class(); local odd = find_text(surface(), "67"); click_at(odd.x + 10, odd.y + 2); point_at(1500, 200); run(3)
	check(weights(ARMOR[3]) == "0:2.0.0.abcd 4.0.0.abcd 7.0.1.abcd 2.2.0.abcd 9.0.3.abcd | 1:2.0.0.abcd 4.0.0.abcd 7.0.1.abcd 2.2.0.abcd 9.0.3.abcd"
		and find_text(surface(), "ARMOR RATING 67") ~= nil, "an odd rating: slot 7 raised first, slots 2 and 4 light")
	open_class(); odd = find_text(surface(), "133"); click_at(odd.x + 10, odd.y + 2); point_at(1500, 200); run(3)
	check(weights(ARMOR[3]):find("^0:2%.0%.2%.abcd 4%.0%.1%.abcd 7%.0%.2") ~= nil, "133: two of three rated slots heavy, the last (slot 4) medium")
	open_class(); heavy = find_text(surface(), "150"); click_at(heavy.x + 10, heavy.y + 2); point_at(1500, 200); run(3)
	-- keyboard in the rating grid (50, 67, 83, 100, 133, 150, ORIGINAL), starting on 150
	open_class(); tap(W); tap(W); tap(SPACE)
	check(not class_open() and r64(ARMOR[3].at + 48) == ARMOR[3].list, "W W then Space picks two above (100, this armor's own, so its own pieces)")
	open_class(); tap(W); tap(W); tap(W); tap(W); tap(W); tap(W); tap(SPACE)
	check(weights(ARMOR[3]):find("^0:2%.0%.0") ~= nil and find_text(surface(), "ARMOR RATING 50") ~= nil, "from ORIGINAL up six to 50")
	open_class(); tap(W); tap(SPACE)
	check(r64(ARMOR[3].at + 48) == ARMOR[3].list, "W wraps from the top to ORIGINAL at the bottom")
	open_class(); tap(S); tap(D); tap(SPACE)
	check(weights(ARMOR[3]):find("^0:2%.0%.0") ~= nil, "S wraps from the bottom to the top, D stays in the one column")
	print("an armor that mixes weights")
	w32(payload + 0x12c, ARMOR[2].id); point_at(1500, 200); run(40)
	check(r64(ARMOR[3].at + 48) == ARMOR[3].list, "the class pick is dropped once another armor is worn")
	check(find_text(surface(), "ARMOR RATING 75") ~= nil, "class box shows the rating its own mixed pieces make (one medium of two rated)")
	open_class()
	check(find_text(surface(), "ORIGINAL (75)") and find_text(surface(), "75") and find_text(surface(), "125") and not find_text(surface(), "67"), "choices in steps of 25 for two rated slots")
	local m = find_text(surface(), "100"); click_at(m.x + 10, m.y + 2); point_at(1500, 200); run(3)
	check(weights(ARMOR[2]):find("^0:2%.0%.1%.abcd 4%.0%.1%.abcd 6%.2%.3") ~= nil, "a pick evens out the mix, the non-armor piece untouched")
	open_class(); m = find_text(surface(), "ORIGINAL (75)"); click_at(m.x + 10, m.y + 2); point_at(1500, 200); run(3)
	check(r64(ARMOR[2].at + 48) == ARMOR[2].list, "ORIGINAL puts its own pieces back")
	print("a body list changed by something else")
	local foreign = alloc(48); ffi.copy(ffi.cast("void *", foreign), ffi.cast("void *", ARMOR[2].list), 48); wptr(ARMOR[2].at + 48, foreign)
	run(3); check(find_text(surface(), "?") ~= nil, "class box shows the class as unknown")
	open_class(); m = find_text(surface(), "150"); click_at(m.x + 10, m.y + 2); point_at(1500, 200); run(3)
	check(r64(ARMOR[2].at + 48) == foreign and log_text():find("body list was changed by something else", 1, true), "left alone, and the log says so")
	wptr(ARMOR[2].at + 48, ARMOR[2].list)
	print("a record whose body list pointer crosses a cache line")
	w32(payload + 0x12c, ARMOR[1].id); point_at(1500, 200); run(40)
	open_class(); m = find_text(surface(), "150"); click_at(m.x + 10, m.y + 2); point_at(1500, 200); run(3)
	check(r64(ARMOR[1].at + 48) == ARMOR[1].list and log_text():find("CLASS WRITE FAILED on FS-37 Ravager: crosses a cache line", 1, true), "refused, and the log says why")
	check((ARMOR[2].at + 48) % 8 == 4 and log_text():find("CLASS FS-55 Devastator: ARMOR RATING 75 -> ARMOR RATING 100", 1, true), "a record only 4-byte aligned (armor 2) still took its picks")
	print("dragging the class box")
	w32(payload + 0x12c, ARMOR[3].id); point_at(1500, 200); run(40)
	local function drag2(x, y, dx, dy)
		point_at(x, y); mouse.down = false; run(2); mouse.down = true; run(2)
		point_at(x + dx / 2, y + dy / 2); run(2); point_at(x + dx, y + dy); run(2); mouse.down = false; run(3)
	end
	drag2(55 + CBX + 40, 366 + BY + 13, 0, 40)
	cbox = find_text(surface(), "ARMOR RATING 100")
	check(not class_open() and cbox and cbox.y > 366 + BY + 40, "a drag moves the class box and does not open its grid")
	local h = assert(io.open(LOGDIR .. NAME .. ".cfg")); local ct = h:read("*a"); h:close()
	check(ct:find("class_dx = -207\r\n", 1, true) and ct:find("class_dy = 40\r\n", 1, true) and ct:find("box_x = " .. BX .. "\r\n", 1, true), "its spot from the passive box is saved, the passive box stays")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); run(130)
	click_at(55 + BX + 80, 366 + BY + 14)
	cell = find_text(surface(), "FORTIFIED")
	click_at(cell.x + 20, cell.y + 2); point_at(1500, 200); run(3)
	check(r32(ARMOR[3].at + 28) == 3 and r64(ARMOR[3].at + 48) == ARMOR[3].list, "back to armor 3 on FORTIFIED, its own class")

	print("keeping the keys from the game")
	check(log_text():find("input: consume function at game.dll+0x", 1, true), "consume function found and checked")
	check(#consumed > 0, "it was called during the grid tests above")
	local clean, has_back, has_select = true, false, false
	for _, c in ipairs(consumed) do
		if c.at ~= consume_fn or c.holder ~= input_obj then clean = false end
		if c.action == 11 then has_back = true end
		if c.action == 10 then has_select = true end
	end
	check(clean, "always the right function and the game's input object")
	check(has_select and not has_back, "Select is swallowed, Back is left to the game")
	run(30); local n = #consumed; run(120)
	check(#consumed == n, "nothing swallowed while the grid is closed")
	open_grid(); n = #consumed; run(10)
	check(#consumed == n + 10 * 19, "19 menu actions swallowed every frame while it is open")
	tap(SPACE); run(30); n = #consumed; run(60)
	check(#consumed == n, "stops a few frames after the grid closes")
	wptr(input_slot, 0); open_grid(); n = #consumed; run(10)
	check(#consumed == n and is_open(), "no call when the game's input object is missing, grid unaffected")
	wptr(input_slot, input_obj); click_at(1500, 200)
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("block_keys = 0\r\n"); f:close()
	run(130); open_grid(); n = #consumed; run(10)
	check(#consumed == n, "block_keys = 0 turns it off")
	click_at(1500, 200)
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); run(130)
	check(not log_text():find("key blocking stopped", 1, true), "no blocking error in the log")

	print("screen changes")
	w32(owner + 0x2808, 1); run(12)
	local _, n = surface()
	check(n == 0, "hidden while the screen animates")
	w32(owner + 0x2808, 0); run(12)
	_, n = surface()
	check(n == 1, "back when it settles")
	wf(widget + 156, 935); run(12)
	_, n = surface()
	check(n == 0, "hidden while the button is at the slide-in position")
	wf(widget + 156, 366); run(12)
	w32(payload + 0x12c, ARMOR[1].id); run(3)
	check(find_text(surface(), "ENGINEERING KIT") ~= nil, "box follows an armor change")

	print("Equipment page")
	wf(widget + 156, 373); run(12)
	label = find_text(surface(), "ENGINEERING KIT")
	check(label and label.x > 55 + 213 and label.x < 55 + 213 + 201, "passive box on the right half of the card")
	check(label and label.y > 373 + 46 and label.y < 373 + 46 + 26, "box sits above the STRATAGEMS button")
	click_at(55 + 328, 373 - 30)
	check(find_text(surface(), "FORTIFIED") == nil, "a click where the box used to sit does nothing")
	click_at(55 + 213 + 100, 373 + 46 + 13)
	check(find_text(surface(), "FORTIFIED") ~= nil, "click on the moved box opens the grid")
	click_at(1500, 200)
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("eq_box_x = 10\r\neq_box_y = 100\r\n"); f:close()
	run(130)
	label = find_text(surface(), "ENGINEERING KIT")
	check(label and math.abs(label.x - (55 + 10 + TX("ENGINEERING KIT"))) < 1.5 and label.y > 373 + 100, "its Equipment-page spot can be moved in the settings file")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); run(130)
	wf(widget + 156, 366); run(12)
	label = find_text(surface(), "ENGINEERING KIT")
	check(label and label.x > 55 + BX and label.y > 366 + BY and label.y < 366 + BY + 26, "back on the MISSION STRATAGEMS line on the loadout page")
	w32(owner + 8, 0); run(12)
	_, n = surface()
	check(n == 0, "hidden on the landing map")
	mouse.focused = false; w32(owner + 8, 1); run(12)
	_, n = surface()
	check(n == 1, "still drawn when the window is not focused")
	mouse.focused = true

	print("dragging the box and the grid")
	local TITLE = "ARMOR PASSIVE   (* = this armor's own)   W A S D + SPACE"
	local function cfg_file() local h = assert(io.open(LOGDIR .. NAME .. ".cfg")); local t = h:read("*a"); h:close(); return t end
	local function drag(x, y, dx, dy)
		point_at(x, y); mouse.down = false; run(2); mouse.down = true; run(2)
		point_at(x + dx / 2, y + dy / 2); run(2); point_at(x + dx, y + dy); run(2); mouse.down = false; run(3)
	end
	point_at(1500, 200); run(3)
	local bx, by = 55 + BX + 80, 366 + BY + 14
	drag(bx, by, 3, 2)
	check(find_text(surface(), "FORTIFIED") ~= nil, "a press that barely moves is still a click")
	click_at(1500, 200)
	drag(bx, by, 120, 80)
	label = find_text(surface(), "ENGINEERING KIT")
	check(find_text(surface(), "FORTIFIED") == nil, "a drag on the box does not open the grid")
	check(label and math.abs(label.x - (55 + BX + TX("ENGINEERING KIT") + 120)) < 1.5 and label.y > 366 + BY + 80, "the box is dropped where the mouse let go")
	check(cfg_file():find("box_x = " .. (BX + 120) .. "\r\n", 1, true) and cfg_file():find("box_y = " .. (BY + 80) .. "\r\n", 1, true), "its new spot is saved in the settings file")
	check(cfg_file():find("eq_box_x = 213\r\n", 1, true), "the Equipment-page spot is not touched")
	run(130)
	label = find_text(surface(), "ENGINEERING KIT")
	check(label and math.abs(label.x - (55 + BX + TX("ENGINEERING KIT") + 120)) < 1.5, "it stays there after the settings are read again")
	click_at(bx + 120, by + 80)
	local title = find_text(surface(), TITLE)
	check(title ~= nil, "a click on the moved box opens the grid")
	drag(title.x + 50, title.y + 2, 30, -20)
	local title2 = find_text(surface(), TITLE)
	check(title2 and math.abs(title2.x - title.x - 30) < 1.5 and math.abs(title2.y - title.y + 20) < 1.5, "the grid is dragged by its title and stays open")
	check(cfg_file():find("grid_x = 30\r\n", 1, true) and cfg_file():find("grid_y = 254\r\n", 1, true), "the grid's new spot is saved")
	cell = find_text(surface(), "FORTIFIED")
	click_at(cell.x + 20, cell.y + 2)
	check(r32(ARMOR[1].at + 28) == 3, "a pick still works in the moved grid")
	wf(widget + 156, 373); run(12)
	drag(55 + 213 + 100, 373 + 46 + 13, -40, 30)
	check(cfg_file():find("eq_box_x = 173\r\n", 1, true) and cfg_file():find("eq_box_y = 76\r\n", 1, true) and cfg_file():find("box_x = " .. (BX + 120) .. "\r\n", 1, true),
		"on the Equipment page the drag moves that page's spot only")
	wf(widget + 156, 366); run(12)
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("drag = 0\r\n"); f:close(); point_at(1500, 200); run(130)
	drag(bx, by, 120, 80)
	label = find_text(surface(), "FORTIFIED")
	check(label and math.abs(label.x - (55 + BX + TX("FORTIFIED"))) < 1.5 and cfg_file() == "drag = 0\r\n", "drag = 0 locks everything in place")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); point_at(1500, 200); run(130)
	click_at(55 + BX + 80, 366 + BY + 14)
	cell = find_text(surface(), "ENGINEERING KIT *")
	click_at(cell.x + 20, cell.y + 2); point_at(1500, 200); run(3)
	check(r32(ARMOR[1].at + 28) == 6, "the dragged-about armor is back on its own passive")

	print("DiverKit held still under the box and the grid")
	diverkit.visible = true   -- the "absent" case above swapped the table out mid-hold
	point_at(1500, 200); run(12)
	check(diverkit.visible == true, "left alone while the mouse is elsewhere")
	point_at(55 + BX + 80, 366 + BY + 14); run(2)
	check(diverkit.visible == false, "held as soon as the mouse is on the box")
	mouse.down = true; run(2); mouse.down = false; run(2)
	check(diverkit.visible == false and find_text(surface(), "FORTIFIED") ~= nil, "held through the click that opens the grid")
	point_at(1500, 200); run(12)
	check(diverkit.visible == false, "held while the grid is open, wherever the mouse is")
	click_at(1500, 200); run(6)
	check(diverkit.visible == true, "let go once the grid is closed and the mouse is off the box")
	point_at(55 + BX + 80, 366 + BY + 14); run(2); w32(owner + 0x2808, 1); run(12)
	check(diverkit.visible == false, "not let go while the card is off screen")
	w32(owner + 0x2808, 0); point_at(1500, 200); run(24)
	check(diverkit.visible == true, "let go when the card is back")
	diverkit.visible = false; point_at(55 + BX + 80, 366 + BY + 14); run(4); point_at(1500, 200); run(12)
	check(diverkit.visible == false, "a DiverKit that hid itself is never switched on")
	diverkit.visible = true
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("hold_diverkit = 0\r\n"); f:close(); run(130)
	point_at(55 + BX + 80, 366 + BY + 14); run(4)
	check(diverkit.visible == true, "hold_diverkit = 0 turns it off")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); point_at(1500, 200); run(130)
	rawset(_G, "CodexLoadouts", nil); point_at(55 + BX + 80, 366 + BY + 14); run(4); point_at(1500, 200); run(6)
	check(not log_text():find("stopped", 1, true), "no trouble when DiverKit is not installed")
	rawset(_G, "CodexLoadouts", diverkit)

	print("hard set key")
	local F6 = 0x75
	local function press(vk) keys[vk] = true; run(2); keys[vk] = nil; run(2) end
	local function own_pick()
		click_at(55 + BX + 80, 366 + BY + 14)
		local own = find_text(surface(), "SERVO-ASSISTED *")
		click_at(own.x + 20, own.y + 2); point_at(1500, 200); run(3)
	end
	w32(payload + 0x12c, ARMOR[3].id); point_at(1500, 200); run(3); own_pick()
	check(r32(ARMOR[3].at + 28) == 8, "starting from the armor's own passive")
	press(F6)
	check(saved_text() == "" and log_text():find("has its own class and passive, nothing to save", 1, true), "F6 on an unchanged armor saves nothing")
	click_at(55 + BX + 80, 366 + BY + 14)
	cell = find_text(surface(), "FORTIFIED")
	click_at(cell.x + 20, cell.y + 2); point_at(1500, 200); run(3)
	check(find_text(surface(), "FORTIFIED") ~= nil and saved_text() == "", "a pick alone is not saved")
	press(F6)
	check(saved_text():find("3672418116 = 3", 1, true), "F6 saves the worn armor's passive")
	check(find_text(surface(), "FORTIFIED [SET]") ~= nil, "box marks it")
	print("a pick is dropped when another armor is worn")
	local function pick(name)
		click_at(55 + BX + 80, 366 + BY + 14)
		local c = find_text(surface(), name)
		click_at(c.x + 20, c.y + 2); point_at(1500, 200); run(3)
	end
	pick("ENGINEERING KIT"); run(200)
	check(r32(ARMOR[3].at + 28) == 6, "a pick stays while the same armor is worn")
	w32(payload + 0x12c, ARMOR[1].id); run(40)
	check(r32(ARMOR[3].at + 28) == 3, "a pick over a hard set falls back to the hard-set passive")
	pick("FORTIFIED")
	check(r32(ARMOR[1].at + 28) == 3, "the other armor takes a pick")
	w32(payload + 0x12c, ARMOR[3].id); run(40)
	check(r32(ARMOR[1].at + 28) == 6, "a pick without F6 falls back to the armor's own passive")
	check(r32(ARMOR[3].at + 28) == 3 and find_text(surface(), "FORTIFIED [SET]") ~= nil, "the hard-set armor still has its passive when worn again")
	check(saved_text():find("3672418116 = 3", 1, true) and not saved_text():find("530315896", 1, true), "the saved file is not touched by any of it")
	pick("ENGINEERING KIT")
	w32(owner + 8, 0); w32(manager + 0x62a0, 0); run(3); w32(payload + 0x12c, ARMOR[1].id); run(40)
	check(r32(ARMOR[3].at + 28) == 6, "nothing is put back while the loadout screen is closed and the player cache still holds that armor")
	w32(manager + 0x62a0, 1); w32(owner + 8, 1); run(40)
	check(r32(ARMOR[3].at + 28) == 3, "an armor change the cache did not show is caught when the loadout screen opens again")
	w32(payload + 0x12c, ARMOR[3].id); run(40)
	pick("ENGINEERING KIT")
	w32(owner + 8, 0); w32(manager + 0x62a0, 0); run(200)
	check(r32(ARMOR[3].at + 28) == 6, "away from the loadout screen the pick stays while the same armor is worn")
	w32(cache + 12, 0x12345); run(40)
	check(r32(ARMOR[3].at + 28) == 6, "a cache holding something that is not a known armor changes nothing")
	w32(cache + 12, ARMOR[1].id); run(40)
	check(r32(ARMOR[3].at + 28) == 3, "an armor change in the Armory (seen in the player cache) drops the pick")
	check(r32(ARMOR[1].at + 28) == 6 and r32(ARMOR[2].at + 28) == 3, "and touches no other armor")
	w32(cache + 12, ARMOR[3].id); w32(manager + 0x62a0, 1); w32(owner + 8, 1); run(40)
	check(find_text(surface(), "FORTIFIED [SET]") ~= nil, "back on the hard-set armor")

	w32(payload + 0x12c, ARMOR[1].id); run(3); press(F6)
	check(not saved_text():find("530315896", 1, true), "another armor on its own passive is not saved")
	w32(payload + 0x12c, ARMOR[3].id); run(3)
	click_at(55 + BX + 80, 366 + BY + 14)
	cell = find_text(surface(), "ENGINEERING KIT")
	click_at(cell.x + 20, cell.y + 2); point_at(1500, 200); run(3)
	check(find_text(surface(), "ENGINEERING KIT") ~= nil and saved_text():find("3672418116 = 3", 1, true), "a later pick shows, the saved one stays until F6")
	press(F6)
	check(saved_text():find("3672418116 = 6", 1, true), "F6 again saves the new one")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("set_key = 0\r\n"); f:close(); run(130)
	own_pick(); press(F6)
	check(r32(ARMOR[3].at + 28) == 8 and saved_text():find("3672418116 = 6", 1, true), "set_key = 0 turns the key off")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); run(130)
	press(F6)
	check(not saved_text():find("3672418116", 1, true), "F6 on the armor's own passive forgets the saved one")
	w32(owner + 8, 0); w32(manager + 0x62a0, 0); run(3); press(F6)
	check(log_text():find("key ignored: loadout screen not open", 1, true), "F6 away from the loadout screen does nothing")
	w32(manager + 0x62a0, 1); w32(owner + 8, 1); run(12)
end

if mode == nil or mode == "" then   -- leave armor 3 heavy, for shutdown to put back
	click_at(55 + CBX + 40, 366 + BY + 13)
	local h = find_text(surface(), "150")
	click_at(h.x + 10, h.y + 2); point_at(1500, 200); run(3)
	check(r64(ARMOR[3].at + 48) ~= ARMOR[3].list, "armor 3 left heavy before shutdown")
end
print("shutdown")
rawget(_G, "shutdown")()
local _, left = surface()
check(shut, "the game's own shutdown still ran")
check(left == 0, "surface removed")
check(r32(ARMOR[1].at + 28) == 6 and r32(ARMOR[2].at + 28) == 3 and r32(ARMOR[3].at + 28) == 8, "every record back to its own passive")
check(r64(ARMOR[1].at + 48) == ARMOR[1].list and r64(ARMOR[2].at + 48) == ARMOR[2].list and r64(ARMOR[3].at + 48) == ARMOR[3].list,
	"every record back on its own body list")
if public and (mode == nil or mode == "") then
	print("public build: no card redraw")
	w32(owner + 8, 1); w32(manager + 0x62a0, 1); w32(payload + 0x12c, ARMOR[3].id); point_at(1500, 200); run(80)
	w32(payload + 0x60, 4242); run(120); w32(payload + 0, 4243); run(120)
	check(#refreshed == 0 and #pictured == 0, "the game's card refresh and picture routine are never called")
	check(picker.test.redraw == nil, "no redraw state in the mod")
	check(not log_text():find("redraw", 1, true), "the log never mentions a redraw")
	local f = assert(io.open(LOGDIR .. NAME .. ".cfg")); local c = f:read("*a"); f:close()
	check(not c:find("redraw", 1, true), "the settings file has no redraw line")
	w32(payload + 0x60, 0); w32(payload + 0, 0)
elseif mode == nil or mode == "" then
	print("card redraw after a loadout change")
	local f
	w32(owner + 8, 1); w32(manager + 0x62a0, 1); w32(payload + 0x12c, ARMOR[3].id); point_at(1500, 200); run(80)
	check(log_text():find("redraw: card refresh at game.dll+", 1, true), "refresh function found and checked")
	local n = #refreshed; run(120)
	local np = #pictured
	check(#refreshed == n, "no refresh while nothing changes")
	w32(payload + 0x60, 4242); run(20)
	check(#refreshed == n, "not yet: it waits for the change to settle")
	w32(payload + 0, 4243); run(20)
	check(#refreshed == n, "a second change pushes the redraw out")
	run(40)
	local c = refreshed[#refreshed]
	check(#refreshed == n + 1, "one refresh after items changed under a card that stayed up")
	check(c.at == refresh_fn and c.card == card and c.payload == payload and c.mine == true and c.mode == false, "the game's own call is replayed with the card's own arguments")
	check(c.flag == 0 and r8(card_widget + 0x831c) == 1, "the skip byte is cleared for the call and back afterwards")
	check(log_text():find("redraw: equipment tiles redrawn after a loadout change, pictures rendered again", 1, true), "log says so")
	check(#pictured == np + 1 and pictured[#pictured].at == thumbs_fn and pictured[#pictured].tiles == card_widget and pictured[#pictured].flag == 1,
		"the picture routine is called once, on the tiles, after the refresh")
	w32(card + 0x5958 + 0x15ec0, 0); w32(payload + 0x60, 5001); run(80); w32(card + 0x5958 + 0x15ec0, 1)
	check(#pictured == np + 1 and log_text():find("pictures left for the page flip", 1, true), "no picture call while the stratagem page is showing")
	w8(card + 0x1ee11, 1); w32(payload + 0x60, 5002); run(80); w8(card + 0x1ee11, 0)
	check(#pictured == np + 1, "no picture call while the card is collapsing")
	w32(card + 0x1b818, 0); w32(payload + 0x60, 5003); run(80); w32(card + 0x1b818, 1)
	check(#pictured == np + 1, "no picture call in a card state the game would not call it in")
	n = #refreshed
	n = #refreshed; run(120)
	check(#refreshed == n, "and only one")
	w32(owner + 8, 0); run(3); w32(payload + 0x60, 4244); run(3); w32(owner + 8, 1); run(80)
	check(#refreshed == n, "a change made while the card was away is left to the game")
	wptr(card_widget + 0x8308, 0); w32(payload + 0x60, 4245); run(80); wptr(card_widget + 0x8308, payload)
	check(#refreshed == n, "no call when the game would not skip anyway")
	w8(card + 0x1ee0c, 0); w8(card_widget + 0x831c, 0); w32(payload + 0x60, 4246); run(80); w8(card + 0x1ee0c, 1); w8(card_widget + 0x831c, 1)
	check(#refreshed == n, "no call on a card that is not the local player's")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("redraw = 0\r\n"); f:close(); run(130)
	w32(payload + 0x60, 4247); run(80)
	check(#refreshed == n, "redraw = 0 turns it off")
	f = assert(io.open(LOGDIR .. NAME .. ".cfg", "w")); f:write("# defaults\r\n"); f:close(); run(130)
	widget_rebuilds = false; w32(payload + 0x60, 4248); run(80); widget_rebuilds = true
	check(#refreshed == n + 1 and r8(card_widget + 0x831c) == 1, "if the game does not rebuild, the byte is put back")
	check(log_text():find("redraw: off for this session, the game did not rebuild the tiles", 1, true), "and the redraw turns itself off")
	w32(payload + 0x60, 4249); run(80)
	check(#refreshed == n + 1, "no further calls this session")
	w32(payload + 0x60, 0); w32(payload + 0, 0)
end
do
	local f = io.open(LOGDIR .. NAME .. ".previous.log"); local t = f and f:read("*a") or ""; if f then f:close() end
	check(t == "OLD SESSION\n", "the last session's log is kept as the previous log, the older one is gone")
	check(not log_text():find("OLD SESSION", 1, true) and log_text():find(public and "Simple Armor Passive Picker " or "Passive Picker test ", 1, true) == 1, "the new log starts fresh")
end
check(not log_text():find("stopped", 1, true), "no error in the log")
print(string.format("surfaces created %d, destroyed %d, frames %d", created, destroyed, frames))
print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
if failures > 0 then print("---- log ----") print(log_text()) end
os.exit(failures == 0 and 0 or 1)
