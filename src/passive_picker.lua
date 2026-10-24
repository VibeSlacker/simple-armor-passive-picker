-- HD2-Addon: mods/jarvis/passive_picker
-- Passive Picker, test build 0.33, for Bingus Shared Loader v15+.
--
-- Picks the armor rating (50 light to 150 heavy) and the passive of the armor
-- worn on the pre-mission loadout screen, from two clickable boxes of the same
-- width that split your player card evenly (equal gaps at both edges and
-- between them): the class box on the left, the passive box on the right, on
-- the MISSION STRATAGEMS line (on the Equipment page, where that line gives way
-- to the gear tiles, above the STRATAGEMS button). Each box opens its own grid:
-- the ratings (50, 64, 70, 79, 100, 129, 150, as near as the armor's pieces
-- allow) and ORIGINAL (the armor's own pieces), or the passives
-- you own. The look of the armor is never touched. While a grid is
-- open the highlight moves with the mouse or with W/A/S/D, and Space or a
-- click picks and closes it.
-- A controller works too, read the way DiverKit and HD2 Transmog read theirs
-- (XInput: Xbox pads and every pad Steam Input hands the game; else a plain
-- Windows joystick, for a USB pad that only shows up as one). The right stick
-- click opens and closes the passive grid (pad_open in the settings file) and
-- the left stick click opens the rating grid (pad_open_rating); both, and the
-- hard set, can be rebound on the MODS tab of the game's binding pages when
-- Mod Bindings Menu is installed (a row used there replaces the settings-file
-- button for the session);
-- with a grid open the D-pad or the left stick moves the highlight, A picks,
-- B closes, Y hard sets (as F6 does), LB goes to the rating grid and RB to the
-- passive grid. A plain joystick's buttons are set by number in the settings
-- file (joy_*). The pad is only read while the player card is on screen.
-- While it is open the game's own menu is kept from hearing those keys, by
-- calling the game's "consume input" function (the one call this mod makes
-- into game code; block_keys = 0 in the settings file turns it off).
-- A passive pick makes two 4-byte writes, both read back: the passive number
-- in the armor's record (what the menus show and what a later equip copies)
-- and the passive in the game's "what this player is wearing" cache (what the
-- mission uses).
-- A rating pick never edits the game's own data. The armor's record points at
-- its body pieces, and every piece carries a weight (0 light, 1 medium,
-- 2 heavy). The pieces in slots 2, 4, 5, 6, 7, 8 and 9 make the rating:
-- 50 + 50 x their average weight (slots 1 and 3 count for nothing), and speed
-- and stamina follow it. That is how the odd stock ratings come about: 64 and
-- 79 are two and four medium pieces out of seven, 129 is three medium and four
-- heavy. The mod copies the pieces once per armor and rating, sets the weights
-- in the copy (slots 6, 7, 8, 9 raised first, then 2, 4, 5, the way the stock
-- odd armors have them), and swaps the record's pointer to the copy (only its
-- low 4 bytes when it can, so records whose pointer crosses a cache line change
-- too; read back). Copies are kept for the whole session and never freed, so the game
-- can never read freed memory. Records are put back when the game shuts down.
-- A pick belongs to the armor being worn: once another armor is worn, the one
-- left behind goes back to its own class and passive, or to its hard-set ones.
-- Away from the loadout screen (the ship's Armory) the worn armor is read from
-- the player cache.
-- The box and the grid can be dragged with the left mouse button (the grid by
-- its title line or any empty part); where they are dropped is saved in the
-- settings file. The box keeps one spot for the loadout page and one for the
-- Equipment page. drag = 0 in the settings file locks them.
-- DiverKit's loadout panel can sit under the box or the grid, and it reads the
-- mouse on its own. So while the mouse is on the box or the grid is open,
-- DiverKit is held still (its own "visible" flag is cleared, which makes it
-- skip its frame; its panel stays drawn) and a click here cannot also press one
-- of its buttons. hold_diverkit = 0 in the settings file turns that off.
-- Hard set: F6 on the loadout screen (set_key in the settings file) keeps the
-- worn armor's current class and passive on that armor from then on, across
-- game starts, by saving them in Logs/PassivePicker.saved and writing them back
-- at every start. F6 while the armor has its own class and passive again
-- forgets the saved ones.
--@PERSONAL_BEGIN@
-- Card redraw (personal build only, left out of the public build): when the
-- worn items change under a card that stayed on screen (a DiverKit preset
-- switch), the game's own card refresh is called again in a way it cannot
-- skip, so the tiles show the new items without a page flip.
-- redraw = 0 in the settings file turns that off.
--@PERSONAL_END@
-- Log:      Logs/PassivePicker.log (in the CowboyBingus log folder); the last
--           session's is kept as PassivePicker.previous.log, older ones go
-- Settings: Logs/PassivePicker.cfg (box and grid position; re-read while the
--           card is on screen, so it can be tuned without a restart)
--
-- How the game stores it (learned from HD2 Transmog 0.2.2 and DiverKit):
--   armor catalog -> array of 64-byte kit records: item id at +0, passive at
--                    +28, body list at +48 (pointer, body count, zero)
--   body list     -> 24-byte bodies: type at +0, piece list pointer at +8,
--                    piece count at +16
--   piece         -> 96 bytes: slot at +8, kind at +12 (0 = armor), weight at +16
--   progression   -> owned entries (24 bytes each) pointing at 184-byte states
--   loadout owner -> per-slot payload with the worn armor id at +0x12c
--   player card   -> one of four at owner+0x53a78, EQUIPMENT button widget at
--                    card+0x1b820 (used as the anchor for the box)

if rawget(_G, "JarvisPassivePicker") then return true end
local REVISION = "Passive Picker test 0.33"
local state = { revision = REVISION, frames = 0, status = "starting" }
rawset(_G, "JarvisPassivePicker", state)

local ffi = require("ffi")
local bit = require("bit")
local DIR = (os.getenv("LOCALAPPDATA") or ".") .. "/CowboyBingus/Helldivers2/Logs/"
local LOG = DIR .. "PassivePicker.log"
pcall(function () local old = DIR .. "PassivePicker.previous.log" os.remove(old) os.rename(LOG, old) end)
pcall(function () local f = io.open(LOG, "w") if f then f:write(REVISION .. "\n") f:close() end end)
local lines = 0
local function log(text)
	state.status = text
	lines = lines + 1
	if lines > 2000 then return end
	pcall(function ()
		local f = io.open(LOG, "a")
		if f then f:write("[frame " .. state.frames .. "] " .. text, "\n") f:close() end
	end)
end

-- ------------------------------------------------------------------ data
-- Filled in by build.py from data/*.json.
local SIGS = --@SIGS@
local PASSIVE_NAMES = --@PASSIVES@
local ARMORS = --@ARMORS@

-- Shared by the ownership report and the passive change further down.
local owned_passives = {}   -- sorted passive numbers from owned armors

local function passive_name(enum)
	return PASSIVE_NAMES[enum] or ("passive " .. tostring(enum))
end

-- ------------------------------------------------------------------ memory
pcall(ffi.cdef, [[
typedef struct {
  void *base; void *allocation_base; uint32_t allocation_protection;
  uint16_t partition; uint16_t reserved; size_t size;
  uint32_t state; uint32_t protection; uint32_t type;
} JarvisPPRegion;]])
pcall(ffi.cdef, "size_t VirtualQuery(const void *address, void *region, size_t size);")
pcall(ffi.cdef, "void *GetModuleHandleA(const char *name);")
pcall(ffi.cdef, "int VirtualProtect(void *a, size_t n, uint32_t p, uint32_t *old);")
pcall(ffi.cdef, "void *VirtualAlloc(void *a, size_t n, uint32_t type, uint32_t p);")
pcall(ffi.cdef, "short GetAsyncKeyState(int key);")
pcall(ffi.cdef, "void *GetForegroundWindow(void);")
pcall(ffi.cdef, "uint32_t GetWindowThreadProcessId(void *window, uint32_t *pid);")
pcall(ffi.cdef, "uint32_t GetCurrentProcessId(void);")
pcall(ffi.cdef, "int GetCursorPos(void *);")
pcall(ffi.cdef, "int ScreenToClient(void *, void *);")
pcall(ffi.cdef, "int GetClientRect(void *, void *);")
pcall(ffi.cdef, "int QueryPerformanceCounter(int64_t *count);")
pcall(ffi.cdef, "int QueryPerformanceFrequency(int64_t *rate);")
local kernel = ffi.load("kernel32")
local user = ffi.load("user32")
local MEM_COMMIT = 0x1000
local READABLE = { [0x02] = true, [0x04] = true, [0x08] = true, [0x20] = true, [0x40] = true, [0x80] = true }
local LOW, HIGH = 0x10000, 0x7FFFFFFFFFFF
local region = ffi.new("JarvisPPRegion[1]")
local RSIZE = ffi.sizeof(region[0])

local function query(addr)
	if type(addr) ~= "number" or addr < LOW or addr > HIGH then return nil end
	if kernel.VirtualQuery(ffi.cast("void *", addr), region, RSIZE) ~= RSIZE then return nil end
	local r = region[0]
	return tonumber(ffi.cast("uintptr_t", r.base)), tonumber(r.size),
		r.state == MEM_COMMIT and READABLE[tonumber(r.protection)] == true, tonumber(r.protection)
end

-- true when [a, a+n) is committed, readable memory (may span regions)
local function readable(a, n)
	local stop = a + n
	while a < stop do
		local b, s, ok = query(a)
		if not ok then return false end
		a = b + s
	end
	return true
end

local function u8(a) return ffi.cast("const uint8_t *", a)[0] end
local function u32(a) return tonumber(ffi.cast("const uint32_t *", a)[0]) end
local function f32(a) return tonumber(ffi.cast("const float *", a)[0]) end
local function ptr(a)
	local p = ffi.cast("const uint32_t *", a)
	local lo, hi = tonumber(p[0]), tonumber(p[1])
	if hi >= 32768 then return nil end
	local v = lo + hi * 4294967296
	if v < LOW then return nil end
	return v
end
local function need(a, n, what)
	if not (a and readable(a, n)) then error(what .. " unreadable", 0) end
	return a
end

-- ------------------------------------------------------------------ writing
-- The writes this mod makes: a 4-byte value (a passive) or an 8-byte pointer
-- (a body list), read back afterwards. The game's kit records are only 4-byte
-- aligned, so an 8-byte write is allowed anywhere inside one 64-byte cache line
-- (where x86 writes it in one piece, so no reader sees half of it), never
-- across two.
local oldprot, tmpprot = ffi.new("uint32_t[1]"), ffi.new("uint32_t[1]")
local function put(a, v, n)
	local _, _, ok, prot = query(a)
	if not ok or not readable(a, n) then return false, "unreadable" end
	if a % 4 ~= 0 then return false, "not aligned" end
	if a % 64 + n > 64 then return false, "crosses a cache line" end
	local unlocked = false
	if prot ~= 0x04 then
		if kernel.VirtualProtect(ffi.cast("void *", a), n, 0x04, oldprot) == 0 then
			return false, "page protection " .. tostring(prot) .. " could not be opened"
		end
		unlocked = true
	end
	if n == 8 then ffi.cast("uint64_t *", a)[0] = v else ffi.cast("uint32_t *", a)[0] = v end
	if unlocked then kernel.VirtualProtect(ffi.cast("void *", a), n, oldprot[0], tmpprot) end
	if (n == 8 and ptr(a) or u32(a)) ~= v then return false, "read-back differs" end
	return true, unlocked and ("page protection was " .. tostring(prot)) or "plain writable page"
end
local function put32(a, v) return put(a, v, 4) end
local function put64(a, v) return put(a, v, 8) end

-- A body list pointer is changed by writing only its low 4 bytes when the old
-- and new pointers share the top 4: one aligned 4-byte write, whole wherever
-- the record sits (about a third of the game's records have +48 across a
-- cache line, where the 8-byte write is refused). Otherwise the 8-byte write.
local function put_list(a, list)
	local now = ptr(a)
	if now and math.floor(now / 4294967296) == math.floor(list / 4294967296) then
		local ok, how = put32(a, list % 4294967296)
		if not ok then return false, how end
		if ptr(a) ~= list then return false, "read-back differs" end
		return true, how .. ", low 4 bytes"
	end
	return put64(a, list)
end

-- The copied pieces live in blocks placed in the same 4 GB window as the
-- game's own lists, so put_list can take the 4-byte route. That window is
-- nearly full in the real game (about 20 MB free, in holes of 64 KB to a few
-- MB), so each block is a free hole found with VirtualQuery, up to 1 MB of it,
-- and at most 4 MB per window (every armor at every rating is about 2 MB).
-- Never freed: the game may still be reading an older copy. When no block can
-- be placed, the copies go in Lua memory as before.
local BLOCK, BUDGET, GRAIN, MEM_FREE = 0x100000, 0x400000, 0x10000, 0x10000
local arenas = {}   -- top 4 bytes -> { at, size, used, total, cursor, full }
local function arena_grow(a, hi, n)
	local stop = (hi + 1) * 4294967296
	while a.cursor < stop and a.total + n <= BUDGET do
		if kernel.VirtualQuery(ffi.cast("void *", a.cursor), region, RSIZE) ~= RSIZE then return false end
		local base = tonumber(ffi.cast("uintptr_t", region[0].base))
		local after = math.min(base + tonumber(region[0].size), stop)
		if after <= a.cursor then return false end
		a.cursor = after
		if region[0].state == MEM_FREE then
			local at = base + (GRAIN - base % GRAIN) % GRAIN
			local len = math.min(BLOCK, BUDGET - a.total, math.floor(math.max(after - at, 0) / GRAIN) * GRAIN)
			if len >= n then
				local got = kernel.VirtualAlloc(ffi.cast("void *", at), len, 0x3000, 0x04)
				if got ~= nil and tonumber(ffi.cast("uintptr_t", got)) == at then
					a.at, a.size, a.used, a.total = at, len, 0, a.total + len
					if at + len < after then a.cursor = at + len end
					return true
				end
			end
		end
	end
	return false
end
local function arena_take(hi, n)
	local a = arenas[hi]
	if not a then a = { size = 0, used = 0, total = 0, cursor = hi * 4294967296 } arenas[hi] = a end
	if a.used + n > a.size then
		if a.full or not arena_grow(a, hi, n) then
			if not a.full then
				a.full = true
				log(string.format("copy memory: no free room left in window 0x%X; further copies in Lua memory, records across a cache line keep their rating", hi))
			end
			return nil
		end
		log(string.format("copy memory: %d KB at 0x%X, next to the game's lists", a.size / 1024, a.at))
	end
	local at = a.at + a.used
	a.used = a.used + n + (16 - n % 16) % 16
	return at
end

-- ------------------------------------------------------------------ keys
local pidbox = ffi.new("uint32_t[1]")
local function game_focused()
	local w = user.GetForegroundWindow()
	if w == nil then return false end
	user.GetWindowThreadProcessId(w, pidbox)
	return pidbox[0] == kernel.GetCurrentProcessId()
end
local held = {}
local function pressed(vk)
	local down = bit.band(user.GetAsyncKeyState(vk), 0x8000) ~= 0
	local edge = down and not held[vk]
	held[vk] = down
	return edge and game_focused()
end

-- Grid navigation keys: one step on the press, then steps while held. A key
-- marked -1 (already down when the grid opened) must be let go first.
local VK_W, VK_A, VK_S, VK_D, VK_SPACE = 0x57, 0x41, 0x53, 0x44, 0x20
local NAV_KEYS = { VK_W, VK_A, VK_S, VK_D, VK_SPACE }
local nav = {}
local function nav_block()
	for _, vk in ipairs(NAV_KEYS) do nav[vk] = -1 end
end
local function nav_step(vk, repeats)
	local down = bit.band(user.GetAsyncKeyState(vk), 0x8000) ~= 0
	local n = nav[vk] or 0
	if not down then n = 0 elseif n ~= -1 then n = n + 1 end
	nav[vk] = n
	return (n == 1 or (repeats and n > 24 and n % 5 == 0)) and game_focused()
end

-- ------------------------------------------------------------------ controller
-- Read only, never written to: XInput first, then a plain Windows joystick.
-- Each read gives the same named buttons, so the grid treats both alike.
-- While no pad is known the slots are tried every 15 frames at most (asking
-- about an empty slot is slow on some systems). Declared one by one: another
-- mod may have declared XInputGetState already, which would fail the lot.
pcall(ffi.cdef, "typedef struct { uint32_t packet; uint16_t buttons; uint8_t lt, rt; int16_t lx, ly, rx, ry; } JarvisPPPad;")
pcall(ffi.cdef, "typedef struct { uint32_t size, flags, x, y, z, r, u, v, buttons, count, pov, reserved1, reserved2; } JarvisPPJoy;")
pcall(ffi.cdef, "uint32_t XInputGetState(uint32_t index, void *state);")
pcall(ffi.cdef, "uint32_t joyGetPosEx(uint32_t id, void *info);")
local PAD_NAMES = { "up", "down", "left", "right", "pick", "close", "set", "prev", "next", "open", "open_rating" }
-- pad_open choices: right stick click, left stick click, Back/View, Start (XInput button bits)
local PAD_OPEN = { 0x80, 0x40, 0x20, 0x10 }
local STICK = 18000   -- how far a stick must lean to count as a direction, of 32767
local pads = { tried = false, dead = false, kind = nil, index = nil, next_scan = 0, joy_from = 0, said = 0, joy_held = {} }
local pad_buf = ffi.new("JarvisPPPad[1]")
local joy_buf = ffi.new("JarvisPPJoy[1]")
local pad_arg, joy_arg = ffi.cast("void *", pad_buf), ffi.cast("void *", joy_buf)

local function pad_libs()
	pads.tried = true
	local function find(names, symbol)
		for _, name in ipairs(names) do
			local loaded, lib = pcall(ffi.load, name)
			if loaded then
				local ok, present = pcall(function () return lib[symbol] ~= nil end)
				if ok and present then return lib, name end
			end
		end
	end
	local xname, jname
	pads.xinput, xname = find({ "xinput1_4", "xinput1_3", "xinput9_1_0" }, "XInputGetState")
	pads.winmm, jname = find({ "winmm" }, "joyGetPosEx")
	log(string.format("controller: XInput %s, plain joysticks %s", xname or "not available", jname and "through winmm" or "not available"))
end

-- c = the settings in use
local function xinput_read(i, c)
	if pads.xinput.XInputGetState(i, pad_arg) ~= 0 then return nil end
	local s = pad_buf[0]
	local b, lx, ly = tonumber(s.buttons), tonumber(s.lx), tonumber(s.ly)
	local function on(mask) return mask ~= nil and bit.band(b, mask) ~= 0 end
	return { up = on(0x1) or ly > STICK, down = on(0x2) or ly < -STICK, left = on(0x4) or lx < -STICK,
		right = on(0x8) or lx > STICK, pick = on(0x1000), close = on(0x2000), set = on(0x8000),
		prev = on(0x100), next = on(0x200), open = on(PAD_OPEN[c.pad_open]), open_rating = on(PAD_OPEN[c.pad_open_rating]) }
end

-- A plain joystick: buttons by number (as Windows counts them, from 1), the
-- hat in hundredths of a degree (65535 = centred), the stick from 0 to 65535.
local function joy_read(id, c)
	local j = joy_buf[0]
	j.size, j.flags = ffi.sizeof(joy_buf[0]), 0xFF
	if pads.winmm.joyGetPosEx(id, joy_arg) ~= 0 then return nil end
	local b, pov = tonumber(j.buttons), tonumber(j.pov)
	local x, y = tonumber(j.x) - 32767, tonumber(j.y) - 32767
	local function on(n) return n >= 1 and n <= 32 and bit.band(b, bit.lshift(1, n - 1)) ~= 0 end
	local hat = pov <= 36000
	-- the first buttons pressed go in the log, so a player can find their numbers
	local now = {}
	for n = 1, 32 do
		if on(n) then
			now[n] = true
			if not pads.joy_held[n] and pads.said < 20 then
				pads.said = pads.said + 1
				log(string.format("controller: joystick button %d pressed", n))
			end
		end
	end
	pads.joy_held = now
	return { up = (hat and (pov >= 31500 or pov <= 4500)) or y < -STICK, down = (hat and pov >= 13500 and pov <= 22500) or y > STICK,
		left = (hat and pov >= 22500 and pov <= 31500) or x < -STICK, right = (hat and pov >= 4500 and pov <= 13500) or x > STICK,
		pick = on(c.joy_pick), close = on(c.joy_close), set = on(c.joy_set), prev = on(c.joy_prev),
		next = on(c.joy_next), open = on(c.joy_open), open_rating = on(c.joy_open_rating) }
end

-- The pad's buttons this frame, or nil when there is none.
local function pad_read(c)
	if not pads.tried then pad_libs() end
	if pads.kind then
		local s
		if pads.kind == "xinput" then s = xinput_read(pads.index, c) else s = joy_read(pads.index, c) end
		if s then return s end
		log(string.format("controller: %s %d gone", pads.kind == "xinput" and "XInput pad" or "joystick", pads.index))
		pads.kind, pads.index, pads.next_scan = nil, nil, state.frames + 15
		return nil
	end
	if state.frames < pads.next_scan then return nil end
	pads.next_scan = state.frames + 15
	if pads.xinput then
		for i = 0, 3 do
			local s = xinput_read(i, c)
			if s then pads.kind, pads.index = "xinput", i; log("controller: XInput pad in slot " .. i) return s end
		end
	end
	if pads.winmm then
		-- four of the sixteen joystick ids per try, so all are seen within a second
		for k = 0, 3 do
			local id = (pads.joy_from + k) % 16
			local s = joy_read(id, c)
			if s then pads.kind, pads.index = "joy", id; log("controller: plain joystick " .. id .. " (no XInput pad)") return s end
		end
		pads.joy_from = (pads.joy_from + 4) % 16
	end
	return nil
end

-- Any doubt turns the controller off for the session; mouse and keys keep working.
local function pad_sample(c)
	if pads.dead then return nil end
	local ok, s = pcall(pad_read, c)
	if ok then return s end
	pads.dead = true
	log("controller: off for this session, " .. tostring(s))
end

-- The same step rule as the keys: one step on the press, then steps while
-- held; a button marked -1 (held when the grid opened or closed) must be let go first.
local pad_held = {}
local function pad_step(s, name, repeats)
	local down = s ~= nil and s[name] == true
	local n = pad_held[name] or 0
	if not down then n = 0 elseif n ~= -1 then n = n + 1 end
	pad_held[name] = n
	return (n == 1 or (repeats and n > 24 and n % 5 == 0)) and game_focused()
end
local function pad_block(all)
	for _, name in ipairs(PAD_NAMES) do if all or (name ~= "open" and name ~= "open_rating") then pad_held[name] = -1 end end
end
local function pad_busy(s)
	if not s then return false end
	for _, name in ipairs(PAD_NAMES) do if s[name] then return true end end
	return false
end

-- The rows on the game's bindings pages, through Mod Bindings Menu (optional; the
-- same way Chaos Divers does it). Registration is retried once a 60 frames for
-- 60 tries, since addons load in no fixed order. is_down is a level; the edge is
-- worked out here, once a frame in menu_poll. A row first used there replaces the
-- settings-file button (or key) of the same name until the game restarts; a row
-- left empty changes nothing.
local MENU_CATEGORY = "Passive Picker"
local MENU_ROWS = {
	{ name = "open", id = "vibeslacker.sapp.open_passive", label = "Open Passive Grid" },
	{ name = "open_rating", id = "vibeslacker.sapp.open_rating", label = "Open Rating Grid" },
	{ name = "hard_set", id = "vibeslacker.sapp.hard_set", label = "Hard Set Armor" },
}
local menu = { tries = 0, next_try = 0, pending = #MENU_ROWS, edge = {}, taken = {} }
local function menu_api()
	local m = rawget(_G, "ModBindingsMenu")
	if type(m) ~= "table" or rawget(m, "api") ~= 1 or type(rawget(m, "version")) ~= "number" or m.version < 2 then return nil end
	return m
end
local function menu_poll()
	menu.edge = {}
	local m = menu_api()
	if not m then return end
	if menu.pending > 0 and menu.tries < 60 and state.frames >= menu.next_try then
		menu.next_try, menu.tries = state.frames + 60, menu.tries + 1
		for _, row in ipairs(MENU_ROWS) do
			if not row.done then
				local ok, accepted, why = pcall(m.register_binding, row.id, row.label, nil, { category = MENU_CATEGORY })
				if ok and accepted == true then
					row.done, menu.pending = true, menu.pending - 1
					log("bindings: \"" .. row.label .. "\" is on the game's bindings page under MODS > " .. MENU_CATEGORY:upper())
				else
					local note = "bindings: the page refused \"" .. row.label .. "\" (" .. tostring(ok and why or accepted) .. ")"
					if note ~= row.last then row.last = note; log(note) end
				end
			end
		end
	end
	for _, row in ipairs(MENU_ROWS) do
		if row.done then
			local ok, down = pcall(m.is_down, row.id)
			if not ok or down == nil then row.was = nil
			else
				down = down == true
				if down and row.was == false and game_focused() then
					menu.edge[row.name] = true
					if not menu.taken[row.name] then
						menu.taken[row.name] = true
						log("bindings: \"" .. row.label .. "\" was used; only it counts from now on (the settings-file button is ignored until the game restarts)")
					end
				end
				row.was = down
			end
		end
	end
end

-- ------------------------------------------------------------------ signatures
local function unhex(h)
	local t = {}
	for i = 1, #h, 2 do t[#t + 1] = tonumber(h:sub(i, i + 1), 16) end
	return t
end

local base, image_size
local scan = nil      -- { cursor, hits = {name -> {rva,...}} }
local sig_at = {}     -- signature name -> address of its one match
local globals = nil   -- name -> absolute address of the global slot

local function prepare_scan()
	local handle = kernel.GetModuleHandleA("game.dll")
	if handle == nil then error("game.dll not loaded", 0) end
	base = tonumber(ffi.cast("uintptr_t", handle))
	need(base, 0x1000, "game.dll header")
	local pe = base + u32(base + 0x3C)
	need(pe, 0x100, "game.dll PE header")
	if u32(pe) ~= 0x00004550 then error("game.dll PE signature missing", 0) end
	image_size = u32(pe + 0x50)
	if image_size < 0x100000 or image_size > 0x20000000 then error("game.dll size rejected", 0) end
	state.pe_timestamp = u32(pe + 8)
	for _, s in ipairs(SIGS) do
		s.bytes, s.maskb, s.anchorb = unhex(s.hex), unhex(s.mask), unhex(s.anchor)
		local a = s.anchorb
		s.key = a[1] + a[2] * 256 + a[3] * 65536 + a[4] * 16777216
		s.hits = {}
	end
	scan = { cursor = base }
	log(string.format("game.dll at 0x%X, size %d, stamp %d; scanning for %d signatures",
		base, image_size, state.pe_timestamp, #SIGS))
end

local function matches(s, at)
	local p = ffi.cast("const uint8_t *", at)
	local b, m = s.bytes, s.maskb
	for i = 1, #b do
		if m[i] ~= 0 and p[i - 1] ~= b[i] then return false end
	end
	return true
end

local SLICE = 0.004
local function scan_step()
	local deadline = os.clock() + SLICE
	local stop_all = base + image_size
	while os.clock() < deadline do
		if scan.cursor >= stop_all then return true end
		local b, s, ok = query(scan.cursor)
		if not b or s <= 0 then return true end
		local rend = math.min(b + s, stop_all)
		if ok then
			local from = scan.cursor
			local to = math.min(rend, from + 262144)
			local p = ffi.cast("const uint8_t *", from)
			local last = to - from - 4
			-- overlap of 256 bytes into the next chunk is handled by 'tail' below
			for i = 0, last do
				local v = p[i] + p[i + 1] * 256 + p[i + 2] * 65536 + p[i + 3] * 16777216
				for k = 1, #SIGS do
					local sig = SIGS[k]
					if v == sig.key then
						local start = from + i - sig.anchor_offset
						if start >= base and start + #sig.bytes <= stop_all
							and readable(start, #sig.bytes) and matches(sig, start) then
							sig.hits[#sig.hits + 1] = start
						end
					end
				end
			end
			-- step back 3 bytes so a key straddling two chunks is not missed
			scan.cursor = (to < rend) and (to - 3) or rend
		else
			scan.cursor = rend
		end
	end
	return false
end

local function resolve_globals()
	globals = {}
	for _, s in ipairs(SIGS) do
		local seen, count, first = {}, 0, nil
		for _, at in ipairs(s.hits) do
			if not seen[at] then seen[at] = true; count = count + 1; first = first or at end
		end
		if count ~= 1 and s.optional then
			log(string.format("signature %s matched %d times; the feature that needs '%s' is off", s.name, count, s.symbol))
		elseif count ~= 1 then
			error(string.format("signature %s matched %d times (need exactly 1)", s.name, count), 0)
		end
		if count == 1 then
		sig_at[s.name] = first
		local rel = u32(first + s.extract_offset)
		if rel >= 2147483648 then rel = rel - 4294967296 end
		local slot = first + s.extract_end + rel
		if slot < base or slot + 8 > base + image_size then
			error("signature " .. s.name .. " points outside game.dll", 0)
		end
		if globals[s.symbol] and globals[s.symbol] ~= slot then
			error("signatures disagree about " .. s.symbol, 0)
		end
		globals[s.symbol] = slot
		log(string.format("signature %s at game.dll+0x%X -> %s slot game.dll+0x%X",
			s.name, first - base, s.symbol, slot - base))
		end
	end
end

-- ------------------------------------------------------------------ game input
-- The game's own "consume input" function, as HD2 Transmog 0.2.2 uses it:
-- consume(input singleton, action << 32, -1) makes the game's menus ignore
-- that menu action for the frame. The singleton sits behind a global that the
-- function itself loads (its one "mov rcx, [rip+x]").
-- Menu actions for game build 25480438 (directions, select, tabs), from
-- Transmog's log on this machine; 11, Back, is left to the game on purpose.
local MENU_ACTIONS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 15, 18, 19, 27, 28, 29, 30 }
local EXECUTABLE = { [0x10] = true, [0x20] = true, [0x40] = true, [0x80] = true }
local consume_type = ffi.typeof("void (*)(void *, uint64_t, float)")
local action_values = {}
local native = {
	executable = function (at)
		local _, _, _, protection = query(at)
		return EXECUTABLE[protection] == true
	end,
	consume = function (at, holder, action)
		local value = action_values[action]
		if not value then value = ffi.new("uint64_t", action * 4294967296); action_values[action] = value end
		ffi.cast(consume_type, at)(ffi.cast("void *", holder), value, -1)
	end,
}
local input = nil     -- { fn, global } once the function has been checked
local function resolve_input()
	local fn = globals and globals.input_consume   -- found through one of the game's own calls to it
	if not fn then return end
	local ok, why = pcall(function ()
		local LENGTH = 155
		need(fn, LENGTH, "input function")
		if not native.executable(fn) then error("input function is not code", 0) end
		local p = ffi.cast("const uint8_t *", fn)
		local global, marks = nil, {}
		for i = 0, LENGTH - 8 do
			if i >= 20 and p[i] == 0x48 and p[i + 1] == 0x8B and p[i + 2] == 0x0D then
				if global then error("more than one global load in the input function", 0) end
				local rel = u32(fn + i + 3)
				if rel >= 2147483648 then rel = rel - 4294967296 end
				global = fn + i + 7 + rel
			end
			-- the three fields it clears per action: +0x328, +0x32c, +0x334
			if p[i + 1] == 0x03 and p[i + 2] == 0 and p[i + 3] == 0 then marks[p[i]] = true end
		end
		if not (marks[0x28] and marks[0x2C] and marks[0x34]) then error("input function body differs", 0) end
		if not global then error("input global not found", 0) end
		if global < base or global + 8 > base + image_size or global % 8 ~= 0 then error("input global outside game.dll", 0) end
		need(global, 8, "input global")
		input = { fn = fn, global = global }
	end)
	if ok then log(string.format("input: consume function at game.dll+0x%X, input global game.dll+0x%X", fn - base, input.global - base))
	else log("input: key blocking off, " .. tostring(why)) end
end

-- Keeps the game's menus from hearing the menu keys this frame. back = Back
-- too (11), while a controller drives the grid, so the B that closes it does
-- not also leave the screen. Any doubt turns the feature off for the session;
-- the grid keeps working.
local BACK = 11
local block = { dead = false, frames = 0, said = false }
local function block_keys(back)
	if block.dead or not input then return end
	local ok, why = pcall(function ()
		local holder = ptr(need(input.global, 8, "input global"))
		if not holder then return end
		need(holder, 0x340, "input singleton")
		for _, action in ipairs(MENU_ACTIONS) do native.consume(input.fn, holder, action) end
		if back then native.consume(input.fn, holder, BACK) end
		block.frames = block.frames + 1
		if not block.said then block.said = true; log(string.format("input: blocking the game's menu keys while the grid is open (singleton 0x%X)", holder)) end
	end)
	if not ok then
		block.dead = true
		log("input: key blocking stopped, " .. tostring(why))
	end
end

--@PERSONAL_BEGIN@
-- ------------------------------------------------------------------ card redraw
-- DiverKit asks the game to refresh the player card after a preset switch, but
-- the card's equipment tiles skip the work when they are handed the loadout
-- they already hold (same payload pointer, same "local card" byte;
-- game.dll+0x18991a0 in build 25480438), so the six tiles keep the old items
-- until the page is flipped. The fix replays the game's own last refresh call
-- with that byte cleared first; the tiles then rebuild and the game writes the
-- byte back itself. That only corrects the tiles' item ids: their pictures
-- are rendered by a separate routine (game.dll+0x1898ab0) that the game runs
-- when the equipment page is shown, so the fix calls that too, under the same
-- two conditions the game checks before its own call. Any doubt turns the
-- feature off for the session.
local refresh_type = ffi.typeof("void (*)(void *, void *, bool, bool)")
native.refresh = function (at, card, payload, mine, mode)
	ffi.cast(refresh_type, at)(ffi.cast("void *", card), ffi.cast("void *", payload), mine, mode)
end
local thumbs_type = ffi.typeof("void (*)(void *)")
native.thumbs = function (at, tiles) ffi.cast(thumbs_type, at)(ffi.cast("void *", tiles)) end
-- in the refresh: lea rcx,[r14+0xdba0] / movzx r8d,r15b / mov rdx,r12 / call <tiles>
local TILES_CALL_AT, TILES_CALL = 0x185, { 0x49, 0x8D, 0x8E, 0xA0, 0xDB, 0, 0, 0x45, 0x0F, 0xB6, 0xC7, 0x49, 0x8B, 0xD4, 0xE8 }
-- the tiles' skip test: mov rbp,[rcx+0x8308] ... cmp rbp,rdx / jne / cmp [rcx+0x831c],r8b / je
local TILES_AT, TILES_CHECK = 0x14, { 0x48, 0x8B, 0xA9, 0x08, 0x83, 0, 0, 0x41, 0x0F, 0xB6, 0xF0, 0x48, 0x8B, 0xFA, 0x48, 0x8B, 0xD9,
	0x48, 0x3B, 0xEA, 0x75, 0x0D, 0x44, 0x38, 0x81, 0x1C, 0x83, 0, 0, 0x0F, 0x84 }
local TILES_OFFSET, TILES_PAYLOAD, TILES_FLAG = 0x5958 + 0xdba0, 0x8308, 0x831c
-- the picture routine is reached the way the game reaches it: the refresh ends in a jump to the card's
-- layout function (xor r8d,r8d / mov dl,1 / mov rcx,rbp / add rsp,0x60 / pop rbp / jmp <layout>), which
-- calls it (cmp byte [rbx+0x1ee11],0 / jne / cmp dword [rbx+0x1b818],1 / jne / lea rcx,[rbx+0x134f8] / call <pictures>)
local LAYOUT_JUMP_AT, LAYOUT_JUMP = 0x252, { 0x45, 0x33, 0xC0, 0xB2, 0x01, 0x48, 0x8B, 0xCD, 0x48, 0x83, 0xC4, 0x60, 0x5D, 0xE9 }
local THUMBS_CALL_AT, THUMBS_CALL = 0x224, { 0x80, 0xBB, 0x11, 0xEE, 0x01, 0, 0, 0x75, 0x15, 0x83, 0xBB, 0x18, 0xB8, 0x01, 0, 0x01,
	0x75, 0x0C, 0x48, 0x8D, 0x8B, 0xF8, 0x34, 0x01, 0, 0xE8 }
-- its start: mov rax,rsp / push rbp / sub rsp,0xa0 / cmp qword [rcx+0x8308],0
local THUMBS_CHECK = { 0x48, 0x8B, 0xC4, 0x55, 0x48, 0x81, 0xEC, 0xA0, 0, 0, 0, 0x48, 0x83, 0xB9, 0x08, 0x83, 0, 0, 0 }
local CARD_PAGE, CARD_COLLAPSING, CARD_STATE = 0x5958 + 0x15ec0, 0x1ee11, 0x1b818   -- page 1 = equipment
local ITEM_FIELDS = { 0, 0x60, 0xc0, 0x124, 0x128, 0x12c }   -- primary, pistol, grenade, helmet, cape, armor
local redraw = { fn = nil, thumbs = nil, dead = false, last = nil, due = nil, count = 0 }
local function same_bytes(at, want)
	local p = ffi.cast("const uint8_t *", at)
	for i = 1, #want do if p[i - 1] ~= want[i] then return false end end
	return true
end
local function resolve_redraw()
	local fn = sig_at.card_refresh
	if not fn then return end
	local tiles, thumbs
	local ok, why = pcall(function ()
		need(fn, TILES_CALL_AT + #TILES_CALL + 4, "card refresh function")
		if not native.executable(fn) then error("refresh function is not code", 0) end
		if not same_bytes(fn + TILES_CALL_AT, TILES_CALL) then error("card refresh function body differs", 0) end
		local rel = fn + TILES_CALL_AT + #TILES_CALL
		tiles = rel + 4 + ffi.cast("const int32_t *", rel)[0]
		if tiles < base or tiles >= base + image_size then error("tile function is outside game.dll", 0) end
		need(tiles, TILES_AT + #TILES_CHECK, "tile function")
		if not native.executable(tiles) then error("tile function is not code", 0) end
		if not same_bytes(tiles + TILES_AT, TILES_CHECK) then error("tile function body differs", 0) end
		local function follow(from, at, want, what)
			need(from, at + #want + 4, what)
			if not same_bytes(from + at, want) then error(what .. " body differs", 0) end
			local rel = from + at + #want
			local to = rel + 4 + ffi.cast("const int32_t *", rel)[0]
			if to < base or to >= base + image_size then error(what .. " leads outside game.dll", 0) end
			if not native.executable(to) then error(what .. " leads outside code", 0) end
			return to
		end
		local layout = follow(fn, LAYOUT_JUMP_AT, LAYOUT_JUMP, "card refresh tail")
		thumbs = follow(layout, THUMBS_CALL_AT, THUMBS_CALL, "card layout function")
		need(thumbs, #THUMBS_CHECK, "picture function")
		if not same_bytes(thumbs, THUMBS_CHECK) then error("picture function body differs", 0) end
		redraw.fn, redraw.thumbs = fn, thumbs
	end)
	if ok then log(string.format("redraw: card refresh at game.dll+0x%X, tile function game.dll+0x%X, picture function game.dll+0x%X",
		fn - base, tiles - base, thumbs - base))
	else log("redraw: off, " .. tostring(why)) end
end
--@PERSONAL_END@

-- ------------------------------------------------------------------ catalog
-- An armor's body list as the game left it: its pointer, and its bodies with
-- their pieces copied out. rated = the rating slots it has, in the order they
-- are raised; class = its stock rating.
-- Rating = 50 + 50 x the average weight of the pieces in the rated slots
-- (checked against every armor's listed rating, 2026-10-18).
local RATED = { 6, 7, 8, 9, 2, 4, 5 }
local RATINGS = { 50, 64, 70, 79, 100, 129, 150 }
local function class_name(c) return c == "own" and "ORIGINAL" or c and tostring(c) or "?" end
local function round(x) return math.floor(x + 0.5) end
-- weight units (one per step up from light) for rating r on this armor, and the rating k units give
local function units(st, r) return math.max(0, math.min(2 * #st.rated, round((r - 50) * #st.rated / 50))) end
local function rating_of(st, k) return round(50 + 50 * k / #st.rated) end

local function read_bodies(at)
	local list, n = ptr(at + 48), u32(at + 56)
	if not list or n < 1 or n > 8 or u32(at + 60) ~= 0 then return nil, "body list rejected" end
	if not readable(list, n * 24) then return nil, "body list unreadable" end
	local bodies, slots, torso = {}, {}, false
	for b = 0, n - 1 do
		local head = list + b * 24
		local pieces, count = ptr(head + 8), u32(head + 16)
		if not pieces or count < 1 or count > 20 or u32(head + 20) ~= 0 then return nil, "body rejected" end
		if not readable(pieces, count * 96) then return nil, "pieces unreadable" end
		local body = { head = ffi.string(ffi.cast("const char *", head), 24), count = count,
			raw = ffi.string(ffi.cast("const char *", pieces), count * 96), armor = {} }
		for i = 0, count - 1 do
			local p = pieces + i * 96
			local slot, kind, weight = u32(p + 8), u32(p + 12), u32(p + 16)
			if slot > 9 or kind > 2 or weight > 3 then return nil, "piece fields rejected" end
			if kind == 0 and weight <= 2 then
				body.armor[#body.armor + 1] = { i, slot }
				if slot == 2 then torso = true end
				slots[slot] = math.max(slots[slot] or 0, weight)
			end
		end
		bodies[#bodies + 1] = body
	end
	if not torso then return nil, "no torso piece" end
	local rated, sum = {}, 0
	for _, slot in ipairs(RATED) do
		if slots[slot] then rated[#rated + 1] = slot sum = sum + slots[slot] end
	end
	local st = { list = list, count = n, bodies = bodies, rated = rated }
	st.class = rating_of(st, sum)
	return st
end

local records = nil   -- item id -> { at, passive }
local function read_catalog()
	local catalog = ptr(need(globals.armor_catalog, 8, "armor catalog slot"))
	if not catalog then return nil, "armor catalog not created yet" end
	need(catalog, 12, "armor catalog")
	local first, n = ptr(catalog), u32(catalog + 8)
	if not first or n < 1 or n > 2048 then return nil, "armor catalog empty or out of bounds" end
	need(first, n * 8, "kit slots")
	local out, armors, changed, unknown = {}, 0, 0, 0
	local classes, noclass = {}, 0
	for i = 0, n - 1 do
		local at = ptr(first + i * 8)
		if not at then error("kit pointer missing", 0) end
		need(at, 64, "kit record")
		local item, passive = u32(at), u32(at + 28)
		local default = ARMORS[item]
		if default then
			armors = armors + 1
			if default.p ~= passive then
				changed = changed + 1
				log(string.format("  note: %s holds %s, reference says %s", default.n,
					passive_name(passive), passive_name(default.p)))
			end
			local rec = { at = at, item = item, passive = passive, name = default.n, default = default.p }
			local stock, why = read_bodies(at)
			if stock then
				rec.stock = stock
				classes[stock.class] = (classes[stock.class] or 0) + 1
			else
				noclass = noclass + 1
				log(string.format("  note: %s has no class change (%s)", default.n, why))
			end
			out[item] = rec
		else
			unknown = unknown + 1
		end
	end
	log(string.format("catalog: %d kits, %d body armors recognised, %d other kits, %d armors differ from reference",
		n, armors, unknown, changed))
	local counts = {}
	for r, k in pairs(classes) do counts[#counts + 1] = { r, k } end
	table.sort(counts, function (a, b) return a[1] < b[1] end)
	for i, v in ipairs(counts) do counts[i] = v[1] .. " x" .. v[2] end
	log(string.format("ratings: %s, %d unreadable", table.concat(counts, ", "), noclass))
	return out
end

-- ------------------------------------------------------------------ ownership
local function read_owned()
	local progression = ptr(need(globals.progression, 8, "progression slot"))
	if not progression then return nil, "progression not created yet" end
	need(progression + 0x1ce0, 4, "progression count")
	local count = u32(progression + 0x1ce0)
	if count < 1 or count > 4096 then return nil, "progression empty or out of bounds" end
	local owned, total = {}, 0
	for i = 0, count - 1 do
		local entry = progression + 0xb9ce4 + i * 24
		need(entry, 12, "progression entry")
		local index, item = u32(entry), u32(entry + 8)
		if index >= count then error("progression index rejected", 0) end
		local rec = records[item]
		if rec then
			local st = progression + 0x1ce4 + index * 184
			need(st, 184, "progression state")
			local status = u32(st + 0x14)
			if (status == 2 or status == 4) and u8(st + 0xb4) == 0 and not owned[item] then
				owned[item] = true
				total = total + 1
			end
		end
	end
	return owned, total, count
end

local function report_owned(owned, total, count)
	log(string.format("ownership: %d progression entries, %d body armors owned", count, total))
	local by_passive = {}
	for item in pairs(owned) do
		local rec = records[item]
		by_passive[rec.passive] = (by_passive[rec.passive] or 0) + 1
	end
	local enums = {}
	for enum in pairs(by_passive) do enums[#enums + 1] = enum end
	table.sort(enums)
	owned_passives = enums
	log(string.format("owned passives: %d", #enums))
	for _, enum in ipairs(enums) do
		log(string.format("  %2d  %-34s on %d owned armor(s)", enum, passive_name(enum), by_passive[enum]))
	end
end

-- ------------------------------------------------------------------ loadout
-- What is worn on the pre-mission loadout screen. Returns a short text key
-- so the log only gets a line when something changes.
local function read_loadout()
	local manager = ptr(need(globals.manager, 8, "manager slot"))
	if not manager then return "manager not created" end
	if not readable(manager + 0x62a0, 24) then return "manager bucket unreadable" end
	local bucket = manager + 0x62a0
	if u32(bucket) ~= 1 or u32(bucket + 16) ~= 0xe5 then return "loadout screen not open" end
	local owner = ptr(bucket + 8)
	if not owner or not readable(owner, 0x2810) then return "loadout owner unreadable" end
	local view, slot = u32(owner + 8), u32(owner + 0x27d0)
	if slot >= 4 then return "loadout slot not assigned" end
	local payload = owner + slot * 0x9f0 + 0x10
	if not readable(payload, 0x140) then return "loadout payload unreadable" end
	local armor = u32(payload + 0x12c)
	local rec = records and records[armor]
	if not rec then
		return string.format("loadout open: view %d, slot %d, armor id %08x (not a recognised body armor)", view, slot, armor)
	end
	if not readable(rec.at, 64) or u32(rec.at) ~= armor then return "worn armor record moved" end
	return string.format("loadout open: view %d, slot %d, wearing %s (%08x), passive now %s, default %s",
		view, slot, rec.name, armor, passive_name(u32(rec.at + 28)), passive_name(rec.default)), rec
end

-- ------------------------------------------------------------------ player cache
-- The customization manager (the same object as the armor catalog) keeps, per
-- player, what is equipped right now: 68 bytes, armor id at +12, armor passive
-- at +0x3c. The game fills it when armor is equipped. Layout from HD2 Transmog.
local function read_cache()
	if not globals.players then return nil, "players signature not found" end
	local manager = ptr(need(globals.armor_catalog, 8, "armor catalog slot"))
	local players = ptr(need(globals.players, 8, "players slot"))
	if not manager or not players then return nil, "managers not created" end
	if not readable(players + 0x84, 0x70) then return nil, "players manager unreadable" end
	local total, locals = u32(players + 0x84), u32(players + 0x88)
	if total < 1 or total > 4 or locals ~= 1 then return nil, "no single local player" end
	local player = ptr(players + 0xe8)
	if not player or not readable(player + 8, 4) then return nil, "local player unreadable" end
	local player_id = u32(player + 8)
	if not readable(manager + 0x930, 0x400) then return nil, "customization manager unreadable" end
	local entries, capacity = ptr(manager + 0x930), u32(manager + 0x938)
	local empty, multiplier = u32(manager + 0x93c), u32(manager + 0x940)
	if not entries or capacity < 1 or capacity > 4096 or bit.band(capacity, capacity - 1) ~= 0 then
		return nil, "player lookup rejected"
	end
	if not readable(entries, capacity * 8) then return nil, "player lookup unreadable" end
	local start = ((player_id % capacity) * (multiplier % capacity)) % capacity
	local index
	for probe = 0, math.min(capacity, 64) - 1 do
		local row = entries + ((start + probe) % capacity) * 8
		local key = u32(row)
		if key == player_id then index = u32(row + 4) break end
		if key == empty then break end
	end
	if not index or index >= 4 then return nil, "local player has no customization slot" end
	local cache = manager + 0x96c + index * 68
	return { at = cache, index = index, armor = u32(cache + 12), passive = u32(cache + 0x3c),
		request_armor = u32(manager + 0xa7c + index * 64 + 12) }
end

local function cache_text()
	local ok, c, why = pcall(read_cache)
	if not ok then return "cache: " .. tostring(c) end
	if not c then return "cache: " .. tostring(why) end
	return string.format("cache: slot %d, armor %08x, passive %s, requested armor %08x",
		c.index, c.armor, passive_name(c.passive), c.request_armor)
end

-- ------------------------------------------------------------------ passive change
local touched = {}          -- item id -> record, for every record this mod changed

local function set_passive(rec, enum)
	if type(enum) ~= "number" then log("no owned passive to switch to") return end
	local before = u32(rec.at + 28)
	if before == enum then log(rec.name .. " already has " .. passive_name(enum)) return end
	local ok, how = put32(rec.at + 28, enum)
	if ok then
		touched[rec.item] = rec
		log(string.format("SET %s: %s -> %s (%s)", rec.name, passive_name(before), passive_name(enum), how))
	else
		log(string.format("WRITE FAILED on %s: %s; left as %s", rec.name, how, passive_name(u32(rec.at + 28))))
	end
end

-- ------------------------------------------------------------------ class change
-- The armor's rating right now: the rating of one of this mod's copies, "own"
-- for the game's own body list, nil when something else swapped it.
local function class_now(rec)
	if not rec.stock then return nil end
	local list = ptr(rec.at + 48)
	if list == rec.stock.list then return "own" end
	for c, copy in pairs(rec.copies or {}) do if copy.list == list then return c end end
	return nil
end

-- What the box shows for a class value.
local function class_text(rec, c)
	if c == "own" then return rec.stock and ("ARMOR RATING " .. rec.stock.class) or "ORIGINAL" end
	if c == nil then return "?" end
	return "ARMOR RATING " .. c
end

-- The armor's pieces weighted for rating c, built once per armor and rating
-- and kept until the game closes. k units go out one step at a time over the
-- rated slots in order, all to medium first, then on to heavy; the pieces in
-- slots 1 and 3 keep their own weight.
local function class_copy(rec, c)
	rec.copies = rec.copies or {}
	if rec.copies[c] then return rec.copies[c] end
	local st = rec.stock
	local n, k, want = #st.rated, units(st, c), {}
	for j, slot in ipairs(st.rated) do want[slot] = (j <= k and 1 or 0) + (j <= k - n and 1 or 0) end
	local hi, keep = math.floor(st.list / 4294967296), {}
	local function room(n)
		local at = arena_take(hi, n)
		if at then return ffi.cast("uint8_t *", at) end
		local b = ffi.new("uint8_t[?]", n)
		keep[#keep + 1] = b
		return b
	end
	local lp = room(st.count * 24)
	for b, body in ipairs(st.bodies) do
		local pp = room(body.count * 96)
		ffi.copy(pp, body.raw, #body.raw)
		for _, a in ipairs(body.armor) do
			if want[a[2]] then ffi.cast("uint32_t *", pp + a[1] * 96 + 16)[0] = want[a[2]] end
		end
		ffi.copy(lp + (b - 1) * 24, body.head, 24)
		ffi.cast("uint64_t *", lp + (b - 1) * 24 + 8)[0] = ffi.cast("uintptr_t", pp)
	end
	local copy = { list = tonumber(ffi.cast("uintptr_t", lp)), keep = keep }
	rec.copies[c] = copy
	return copy
end

-- c = a rating, or "own" for the armor's own pieces. One pointer write. A
-- rating the armor's pieces cannot make goes to the nearest one they can.
local function set_class(rec, c)
	if not rec.stock then log(rec.name .. ": no class change for this armor") return end
	if c ~= "own" then c = rating_of(rec.stock, units(rec.stock, c)) end
	if c == rec.stock.class then c = "own" end
	local before = class_now(rec)
	if before == nil then log(rec.name .. ": body list was changed by something else; class left alone") return end
	if before == c then return end
	local list = c == "own" and rec.stock.list or class_copy(rec, c).list
	local ok, how = put_list(rec.at + 48, list)
	if ok then
		touched[rec.item] = rec
		log(string.format("CLASS %s: %s -> %s (%s)", rec.name, class_text(rec, before), class_text(rec, c), how))
	else
		log(string.format("CLASS WRITE FAILED on %s: %s; left as %s", rec.name, how, class_text(rec, class_now(rec))))
	end
end

local function restore_all()
	for _, rec in pairs(touched) do
		if readable(rec.at, 64) and u32(rec.at) == rec.item then
			if u32(rec.at + 28) ~= rec.default then put32(rec.at + 28, rec.default) end
			local c = class_now(rec)
			if c ~= nil and c ~= "own" then put_list(rec.at + 48, rec.stock.list) end
		end
	end
	touched = {}
end

-- The player cache entry as hex, for the log (what the game copied at equip).
local function cache_hex(c)
	return ffi.string(ffi.cast("const char *", c.at), 68):gsub(".", function (ch) return string.format("%02x", ch:byte()) end)
end

-- A passive pick from the grid: the record, then the player cache.
local function apply_pick(rec, enum)
	log(string.format("PICK %s: %s", rec.name, passive_name(enum)))
	set_passive(rec, enum)
	if u32(rec.at + 28) ~= enum then return end
	local read, c, why = pcall(read_cache)
	if not read then c, why = nil, c end
	if not c then log("cache not written: " .. tostring(why)) return end
	if c.armor ~= rec.item then
		log(string.format("cache not written: it holds armor %08x, the loadout says %08x", c.armor, rec.item))
		return
	end
	if c.passive == enum then return end
	local ok, how = put32(c.at + 0x3c, enum)
	log(ok and string.format("CACHE %s: %s -> %s (%s)", rec.name, passive_name(c.passive), passive_name(enum), how)
		or ("CACHE WRITE FAILED: " .. tostring(how)))
end

-- A class pick from the grid. The cache entry is logged around it, to show
-- whether the game keeps anything of the class there.
local function apply_class(rec, c)
	log(string.format("PICK %s: rating %s", rec.name, class_name(c)))
	local read, before = pcall(read_cache)
	set_class(rec, c)
	local again, after = pcall(read_cache)
	if read and before and again and after then
		log("  cache before " .. cache_hex(before))
		log("  cache after  " .. cache_hex(after))
	end
end

-- ------------------------------------------------------------------ hard set
-- Classes and passives kept on an armor until changed by hand, saved to a
-- file and written back into the armor records at every game start.
-- saved[item] = { p = passive or nil for its own, c = a rating or nil for its own }
local SAVED = DIR .. "PassivePicker.saved"
local saved = {}
local sync_dead = false

local function write_saved()
	pcall(function ()
		local f = io.open(SAVED, "wb")
		if not f then log("hard set: the saved file could not be written") return end
		f:write("# Passive Picker: rating and passive hard set on an armor.\r\n")
		f:write("# armor id = passive number, armor rating (50 to 150, - its own)\r\n")
		f:write("# Written when the hard-set key is pressed. With the game closed, delete a\r\n")
		f:write("# line, or this file, to give an armor its own class and passive back.\r\n")
		local items = {}
		for item in pairs(saved) do items[#items + 1] = item end
		table.sort(items)
		for _, item in ipairs(items) do
			local rec = records and records[item]
			local v = saved[item]
			local p = v.p or (rec and rec.default) or 0
			f:write(string.format("%.0f = %d, %s   # %s: %s, %s\r\n", item, p, v.c and tostring(v.c) or "-",
				rec and rec.name or "?", passive_name(p), v.c and ("rating " .. v.c) or "own rating"))
		end
		f:close()
	end)
end

local function load_saved()
	local f = io.open(SAVED, "r")
	if not f then return end
	local text = f:read("*a") or ""
	f:close()
	for line in text:gmatch("[^\r\n]+") do
		local item, enum, c = line:match("^%s*(%d+)%s*=%s*(%d+)%s*,?%s*([%d%-]*)")
		item, enum, c = tonumber(item), tonumber(enum), tonumber(c)
		-- a file from 1.1.0 kept the class: 0 light, 1 medium, 2 heavy
		if c and c <= 2 then c = 50 + 50 * c end
		if item and enum and PASSIVE_NAMES[enum] then saved[item] = { p = enum, c = c } end
	end
end

-- Drops what equals the armor's own, so an entry only holds real changes.
local function trim(rec, v)
	if v.p == rec.default then v.p = nil end
	if v.c ~= nil and rec.stock then v.c = rating_of(rec.stock, units(rec.stock, v.c)) end
	if v.c ~= nil and (not rec.stock or v.c == rec.stock.class) then v.c = nil end
	return (v.p or v.c ~= nil) and v or nil
end

-- At game start: every saved class and passive goes back into its record.
local function apply_saved()
	load_saved()
	local count = 0
	for item, v in pairs(saved) do
		local rec = records[item]
		if rec then
			saved[item] = trim(rec, v)
			if saved[item] then
				if v.p then set_passive(rec, v.p) end
				if v.c then set_class(rec, v.c) end
				count = count + 1
			end
		end
	end
	log(string.format("hard set: %d armor(s) given their saved class and passive", count))
end

-- The player cache may have been filled before the record was written (the
-- armor worn at game start), so the worn armor's saved passive is pushed there.
local function sync_saved(rec)
	local enum = saved[rec.item] and saved[rec.item].p
	if sync_dead or not enum or u32(rec.at + 28) ~= enum then return end
	local read, c = pcall(read_cache)
	if not read or not c or c.armor ~= rec.item or c.passive == enum then return end
	local ok, how = put32(c.at + 0x3c, enum)
	if ok then log(string.format("CACHE %s: %s -> %s (hard set, %s)", rec.name, passive_name(c.passive), passive_name(enum), how))
	else sync_dead = true; log("CACHE WRITE FAILED: " .. tostring(how)) end
end

-- A pick is for the armor being worn. Once another armor is seen worn (on the
-- loadout screen, or in the player cache while that screen is closed), every
-- other armor this mod changed goes back to its hard-set class and passive, or
-- to its own when it has none.
local worn_item = nil
local function revert_others(rec)
	if worn_item == rec.item then return end
	worn_item = rec.item
	-- the stock pieces of each armor worn, once: slot.kind.weight per piece, per body type
	if rec.stock and not rec.logged then
		rec.logged = true
		local parts = {}
		for _, body in ipairs(rec.stock.bodies) do
			local p = {}
			for i = 0, body.count - 1 do
				local raw = body.raw:sub(i * 96 + 9, i * 96 + 20)
				p[#p + 1] = string.format("%d.%d.%d", raw:byte(1), raw:byte(5), raw:byte(9))
			end
			parts[#parts + 1] = string.format("type %d: %s", body.head:byte(1), table.concat(p, " "))
		end
		log(string.format("PIECES %s (%s): %s", rec.name, class_name(rec.stock.class), table.concat(parts, " | ")))
	end
	for item, other in pairs(touched) do
		local v = saved[item] or {}
		local want = v.p or other.default
		if item ~= rec.item and readable(other.at, 64) and u32(other.at) == item then
			if u32(other.at + 28) ~= want then
				local before = u32(other.at + 28)
				local ok, how = put32(other.at + 28, want)
				log(ok and string.format("REVERT %s: %s -> %s (another armor is worn, %s)", other.name, passive_name(before), passive_name(want), how)
					or string.format("REVERT FAILED on %s: %s; left as %s", other.name, tostring(how), passive_name(u32(other.at + 28))))
			end
			local c = v.c == nil and "own" or v.c
			if other.stock and class_now(other) ~= c then set_class(other, c) end
		end
	end
end

-- The hard-set key: keep the worn armor's class and passive as they are now,
-- or forget the saved ones when the armor has its own again.
local function hard_set(rec)
	local c = class_now(rec)
	local v = trim(rec, { p = u32(rec.at + 28), c = (c ~= "own") and c or nil })
	if v then
		saved[rec.item] = v
		write_saved()
		log(string.format("HARD SET %s: %s, %s", rec.name, class_text(rec, c), passive_name(u32(rec.at + 28))))
		sync_saved(rec)
	elseif saved[rec.item] then
		saved[rec.item] = nil
		write_saved()
		log(string.format("HARD SET cleared on %s: back to its own class and passive", rec.name))
	else
		log("hard set: " .. rec.name .. " has its own class and passive, nothing to save")
	end
end

-- ------------------------------------------------------------------ settings
-- Positions are in card units (the card is 420 wide), measured from the
-- lower-left corner of the EQUIPMENT button; x goes right, y goes up.
local CFG = DIR .. "PassivePicker.cfg"
local SETTINGS = {
	{ "box_x", 213, "passive box: left edge (213 = right half of the card)" },
	{ "box_y", -44, "passive box: bottom edge (negative = below the EQUIPMENT button)" },
	{ "box_w", 201, "passive box: width" },
	{ "class_w", 201, "class box: width" },
	{ "class_dx", -207, "class box: left edge, from the passive box's left edge (-207 = the left half of the card, the same gap as at the edges)" },
	{ "class_dy", 0, "class box: bottom edge, from the passive box's bottom edge" },
	{ "box_h", 26, "both boxes: height" },
	{ "box_text", 13, "both boxes: text size" },
	{ "equip_y", 370, "the Equipment page is showing when the button sits at or above this screen height (366 on the loadout page, 373 on the Equipment page)" },
	{ "eq_box_x", 213, "passive box on the Equipment page: left edge (213 = right half of the card)" },
	{ "eq_box_y", 46, "passive box on the Equipment page: bottom edge (46 = just above the STRATAGEMS button)" },
	{ "grid_x", 0, "grid: left edge" },
	{ "grid_y", 274, "grid: bottom edge (274 = just above DiverKit's 15-slot panel)" },
	{ "grid_cols", 2, "grid: columns (1 to 4)" },
	{ "cell_w", 210, "grid: width of one passive" },
	{ "class_cell_w", 210, "class grid: width" },
	{ "cell_h", 17, "grid: height of one passive" },
	{ "grid_text", 12, "grid: text size" },
	{ "box_alpha", 215, "box: how solid its black background is (0 = see-through, 255 = solid)" },
	{ "grid_alpha", 238, "grid: how solid its black background is (0 = see-through, 255 = solid)" },
	{ "set_key", 117, "hard-set key, as a Windows key number (117 = F6, 116 = F5, 118 = F7, 0 = off): keeps the worn armor's current class and passive on that armor across game starts" },
	{ "drag", 1, "1 = the box and the grid can be dragged with the left mouse button and the new spot is saved here, 0 = locked in place" },
	{ "hold_diverkit", 1, "1 = DiverKit ignores the mouse while it is on a box or a grid is open (so a click here cannot press a DiverKit button underneath), 0 = off" },
--@PERSONAL_BEGIN@
	{ "redraw", 1, "1 = redraw the player card after a loadout preset switch so it shows the new items without flipping pages, 0 = off" },
--@PERSONAL_END@
	{ "block_keys", 1, "1 = keep W/A/S/D and Space (and the controller's buttons) away from the game's own menu while the grid is open, 0 = off" },
	{ "pad", 1, "1 = a controller can open and use the grids, 0 = off (the controller is not read at all)" },
	{ "pad_open", 1, "controller button that opens and closes the passive grid: 1 = right stick click, 2 = left stick click (DiverKit uses it too), 3 = Back/View, 4 = Start, 0 = none. In a grid: D-pad or left stick moves, A picks, B closes, Y hard sets, LB = rating grid, RB = passive grid" },
	{ "pad_open_rating", 0, "controller button that opens and closes the rating grid, chosen like pad_open (0 = none, and it must not be the same as pad_open; 2 = left stick click is what DiverKit uses, so it is off in this build). Can also be set on the MODS tab of the game's binding pages when Mod Bindings Menu is installed" },
	{ "joy_open", 12, "plain joystick only (a USB pad Windows does not show as an Xbox pad): button number that opens the grid. The log names each button you press" },
	{ "joy_pick", 2, "plain joystick: button number that picks (A)" },
	{ "joy_close", 3, "plain joystick: button number that closes the grid (B)" },
	{ "joy_set", 4, "plain joystick: button number that hard sets (Y)" },
	{ "joy_open_rating", 0, "plain joystick: button number that opens the rating grid (0 = none)" },
	{ "joy_prev", 5, "plain joystick: button number for the rating grid (LB)" },
	{ "joy_next", 6, "plain joystick: button number for the passive grid (RB)" },
}
local cfg, cfg_text, cfg_rev = {}, nil, 0
for _, s in ipairs(SETTINGS) do cfg[s[1]] = s[2] end

local function parse_cfg(text)
	local out = {}
	for _, s in ipairs(SETTINGS) do out[s[1]] = s[2] end
	for line in text:gmatch("[^\r\n]+") do
		local key, value = line:match("^%s*([%a_]+)%s*=%s*(%-?[%d%.]+)")
		value = tonumber(value)
		if key and out[key] ~= nil and value and value > -5000 and value < 5000 then out[key] = value end
	end
	out.grid_cols = math.max(1, math.min(4, math.floor(out.grid_cols)))
	out.set_key = math.max(0, math.min(255, math.floor(out.set_key)))
	out.box_alpha = math.max(0, math.min(255, math.floor(out.box_alpha)))
	out.grid_alpha = math.max(0, math.min(255, math.floor(out.grid_alpha)))
	out.pad_open = math.max(0, math.min(4, math.floor(out.pad_open)))
	out.pad_open_rating = math.max(0, math.min(4, math.floor(out.pad_open_rating)))
	for _, key in ipairs({ "joy_open", "joy_open_rating", "joy_pick", "joy_close", "joy_set", "joy_prev", "joy_next" }) do
		out[key] = math.max(0, math.min(32, math.floor(out[key])))
	end
	-- one button cannot open both grids
	if out.pad_open_rating == out.pad_open then out.pad_open_rating = 0 end
	if out.joy_open_rating == out.joy_open then out.joy_open_rating = 0 end
	for _, key in ipairs({ "box_w", "box_h", "box_text", "cell_w", "cell_h", "grid_text", "class_w", "class_cell_w" }) do
		out[key] = math.max(6, out[key])
	end
	return out
end

-- Writes the settings file: the defaults, or the settings in use.
local function write_cfg(values)
	pcall(function ()
		local w = io.open(CFG, "wb")
		if not w then return end
		w:write("# Passive Picker: where the boxes and the grids sit on the player card.\r\n")
		w:write("# Card units (the card is 420 wide), from the lower-left corner of the\r\n")
		w:write("# EQUIPMENT button; x goes right, y goes up. Read again every 2 seconds\r\n")
		w:write("# while the card is on screen. Delete this file to get the defaults back.\r\n")
		for _, s in ipairs(SETTINGS) do
			w:write(string.format("%s = %s\r\n", s[1], tostring(values and values[s[1]] or s[2])), "#   " .. s[3] .. "\r\n")
		end
		w:close()
	end)
end

-- Returns true when the settings changed. Writes the file with the defaults
-- the first time.
local function load_cfg()
	local f = io.open(CFG, "r")
	if not f then
		if cfg_text == nil then
			cfg_text = ""
			write_cfg(nil)
		end
		return false
	end
	local text = f:read("*a") or ""
	f:close()
	if text == cfg_text then return false end
	cfg_text = text
	cfg = parse_cfg(text)
	-- a settings file written before the class box (its old first line): the
	-- passive box takes its new spot and width once, so the two boxes split
	-- the card evenly
	if text:find("where the box and the grid sit on the player card", 1, true) then
		for _, sdef in ipairs(SETTINGS) do
			if sdef[1] == "box_x" or sdef[1] == "box_w" or sdef[1] == "eq_box_x" then cfg[sdef[1]] = sdef[2] end
		end
		write_cfg(cfg)
		log("settings: file from before the class box; box spots reset so the two boxes split the card")
	end
	cfg_rev = cfg_rev + 1
	return true
end

-- ------------------------------------------------------------------ player card
-- Where the local player's card is on the loadout screen and what is worn.
-- nil while the card is not up, is animating, or shows something unexpected.
-- Layout from DiverKit's screen check.
local function find_card()
	if not readable(globals.manager, 8) then return nil end
	local manager = ptr(globals.manager)
	if not manager or not readable(manager + 0x62a0, 24) then return nil end
	local bucket = manager + 0x62a0
	if u32(bucket) ~= 1 or u32(bucket + 16) ~= 0xe5 then return nil end
	local owner = ptr(bucket + 8)
	if not owner or not readable(owner, 0x2810) then return nil end
	if u32(owner + 8) ~= 1 then return nil end                       -- 1 = the stratagem loadout view
	if not readable(owner + 0x273990, 1) then return nil end
	if u8(owner + 0x273990) ~= 0 or u8(owner + 0x2808) ~= 0 then return nil end   -- screen animating
	local slot = u32(owner + 0x27d0)
	if slot >= 4 then return nil end
	local payload = owner + slot * 0x9f0 + 0x10
	if not readable(payload, 0x140) then return nil end
	local card
	for i = 0, 3 do
		local candidate = owner + 0x53a78 + i * 0x1ee18
		if readable(candidate + 0x1edf0, 16) and ptr(candidate + 0x1edf0) == payload
			and u32(candidate + 0x1edfc) == slot then
			if card then return nil end
			card = candidate
		end
	end
	if not card then return nil end
	local widget = card + 0x1b820                                     -- the EQUIPMENT button
	if not readable(widget, 164) or bit.band(u32(widget), 0x10) == 0 then return nil end
	local opacity, sx, sy = f32(widget + 84), f32(widget + 100), f32(widget + 140)
	if not (opacity >= 0.995 and opacity <= 1.01 and sx >= 0.3 and sx <= 4 and math.abs(sx - sy) < 0.01) then
		return nil
	end
	local x, y, w, h = f32(widget + 148), f32(widget + 156), f32(widget + 36) * sx, f32(widget + 40) * sy
	if not (x >= 0 and x <= 32768 and y >= 0 and y <= 32768 and w >= 100 and w <= 32768 and h >= 10 and h <= 32768) then
		return nil
	end
	local armor = u32(payload + 0x12c)
	local rec = records and records[armor]
	if not rec or not readable(rec.at, 64) or u32(rec.at) ~= armor then return nil end
	return { x = x, y = y, w = w, h = h, rec = rec, slot = slot, card = card, payload = payload }
end

-- ------------------------------------------------------------------ box and grid
-- Drawn with the game's own Gui, the way DiverKit draws its panel: a screen
-- surface in the menu world, the game's font, and the mouse read from Windows.
-- A surface keeps what was drawn on it, so it is only rebuilt when something
-- visible changes.
local engine = rawget(_G, "stingray")
-- the hover description: its text (passive number -> lines), and how many seconds the cursor
-- (or the pad's highlight) rests on a passive before it shows
local TIP = { delay = 0.5, desc = --@DESCS@ }
TIP.wall = os.clock   -- the same clock the slicer above trusts
local ui = { open = false, dead = false, visible = false, notes = 0 }

local function id_hex(a)   -- the 8 bytes at a as 16 hex digits
	local p = ffi.cast("const uint32_t *", a)
	local lo, hi = tonumber(p[0]), tonumber(p[1])
	if lo == 0 and hi == 0 then return nil end
	return string.format("%08x%08x", hi, lo)
end

local function read_handles()
	if not (globals.font and globals.atlas and globals.material) then return nil, "font signatures not found" end
	if not (readable(globals.font, 8) and readable(globals.atlas, 8) and readable(globals.material, 8)) then
		return nil, "font slots unreadable"
	end
	local holder = ptr(globals.material)
	if not holder or not readable(holder + 24, 8) then return nil, "font material not ready" end
	local font, atlas, material = id_hex(globals.font), id_hex(globals.atlas), id_hex(holder + 24)
	if not (font and atlas and material) then return nil, "font not ready" end
	return { font = font, atlas = atlas, material = material, key = font .. atlas .. material }
end

local function ui_clear()
	if ui.gui and ui.world and engine then
		local alive = false
		for _, w in ipairs(engine.Application.worlds() or {}) do if w == ui.world then alive = true end end
		if alive then engine.World.destroy_gui(ui.world, ui.gui) end
	end
	ui.gui, ui.world, ui.sig = nil, nil, nil
end

-- The owned passives plus the armor's own, by name.
local function grid_list(rec)
	if ui.list and ui.list_item == rec.item and ui.list_count == #owned_passives then return ui.list end
	local seen, list = {}, {}
	for _, enum in ipairs(owned_passives) do
		if not seen[enum] then seen[enum] = true; list[#list + 1] = enum end
	end
	if not seen[rec.default] then list[#list + 1] = rec.default end
	table.sort(list, function (a, b)
		local x, y = passive_name(a), passive_name(b)
		if x == y then return a < b end
		return x < y
	end)
	ui.list, ui.list_item, ui.list_count = list, rec.item, #owned_passives
	return list
end

-- The rating choices: the stock ratings, each as near as this armor's pieces
-- can make it (an armor with fewer rated slots has coarser steps), and
-- ORIGINAL (the armor's own pieces). Empty for an armor whose body list could
-- not be read.
local function class_list(rec)
	if not rec.stock then return {} end
	local out, seen = {}, {}
	for _, r in ipairs(RATINGS) do
		local v = rating_of(rec.stock, units(rec.stock, r))
		if not seen[v] then seen[v] = true out[#out + 1] = v end
	end
	out[#out + 1] = "own"
	return out
end

-- Screen rectangles for the two boxes (passive and class) and, when one is
-- open, its grid. open = "passive", "class" or nil. Regions later in the list
-- win a hit test.
local TITLE_H = 20
local RATING_BIG = 1.3   -- the rating grid's rows and text run this much larger than the passive grid's
local function layout(card, list, gw, gh, open, drag, classes)
	local s = card.w / 420
	local out = { s = s, regions = {}, cells = {}, open = open }
	local function clamp(v, low, high) return math.max(low, math.min(v, math.max(low, high))) end
	-- while one of them is being dragged it follows the mouse
	local function moved(key) if drag and drag.key == key then return drag.dx, drag.dy end return 0, 0 end
	classes = classes or {}
	if open == "class" and #classes == 0 then open = nil end
	if open then
		local items = open == "class" and classes or list
		local cols = open == "class" and 1 or cfg.grid_cols
		local cw = open == "class" and cfg.class_cell_w or cfg.cell_w
		local rows = math.max(1, math.ceil(#items / cols))
		local ch = open == "class" and cfg.cell_h * RATING_BIG or cfg.cell_h
		local w, h = cols * cw * s, (rows * ch + TITLE_H) * s
		local dx, dy = moved("grid")
		local x = clamp(card.x + cfg.grid_x * s + dx, 2, gw - w - 2)
		local y = clamp(card.y + cfg.grid_y * s + dy, 2, gh - h - 2)
		out.grid = { x = x, y = y, w = w, h = h, key = "grid" }
		out.regions[#out.regions + 1] = out.grid
		for i, v in ipairs(items) do
			local col, row = math.floor((i - 1) / rows), (i - 1) % rows
			local cell = { x = x + col * cw * s, y = y + h - TITLE_H * s - (row + 1) * ch * s,
				w = cw * s, h = ch * s }
			if open == "class" then cell.key, cell.class = "c:" .. tostring(v), v
			else cell.key, cell.enum = "p:" .. v, v end
			out.cells[#out.cells + 1] = cell
			out.regions[#out.regions + 1] = cell
		end
	end
	local bw, bh = cfg.box_w * s, cfg.box_h * s
	-- the button the box hangs off sits a little higher on the Equipment page
	local equip = card.y / s >= cfg.equip_y
	local bx, by = equip and cfg.eq_box_x or cfg.box_x, equip and cfg.eq_box_y or cfg.box_y
	local dx, dy = moved("box")
	out.equip = equip
	out.box = { x = clamp(card.x + bx * s + dx, 0, gw - bw), y = clamp(card.y + by * s + dy, 0, gh - bh),
		w = bw, h = bh, key = "box", text = cfg.box_text }
	out.regions[#out.regions + 1] = out.box
	-- the class box keeps its place next to the passive box
	if #classes > 0 then
		local cw = cfg.class_w * s
		local cx, cy = moved("cbox")
		out.cbox = { x = clamp(out.box.x + cfg.class_dx * s + cx, 0, gw - cw), y = clamp(out.box.y + cfg.class_dy * s + cy, 0, gh - bh),
			w = cw, h = bh, key = "cbox", text = cfg.box_text }
		out.regions[#out.regions + 1] = out.cbox
	end
	return out
end

local function hit(regions, x, y)
	for i = #regions, 1, -1 do
		local r = regions[i]
		if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return r.key end
	end
end

-- Mouse position in Gui units (origin bottom-left) and the left button.
local point, client = ffi.new("int32_t[2]"), ffi.new("int32_t[4]")
local point_arg, client_arg = ffi.cast("void *", point), ffi.cast("void *", client)
local function pointer_sample(gw, gh)
	local window = user.GetForegroundWindow()
	if window == nil then return nil end
	user.GetWindowThreadProcessId(window, pidbox)
	if pidbox[0] ~= kernel.GetCurrentProcessId() then return nil end
	if user.GetCursorPos(point_arg) == 0 or user.ScreenToClient(window, point_arg) == 0
		or user.GetClientRect(window, client_arg) == 0 then return nil end
	local w, h = client[2] - client[0], client[3] - client[1]
	local x, y = point[0], point[1]
	if w <= 0 or h <= 0 or x < 0 or y < 0 or x >= w or y >= h then return nil end
	local down
	local mouse = engine.Mouse
	local ok, value = pcall(function () return mouse.button(mouse.button_id("left")) end)
	if ok then down = value == true or (type(value) == "number" and value > 0)
	else down = bit.band(user.GetAsyncKeyState(1), 0x8000) ~= 0 end
	return { x = x * gw / w, y = (h - y) * gh / h, down = down }
end

-- A click is a press and a release over the same region. A button already
-- held when the card appears or the window regains focus never counts.
local function pointer_step(sample, over)
	if not sample then ui.previous, ui.armed = nil, nil return nil end
	local clicked
	if ui.previous ~= nil then
		if sample.down and not ui.previous then ui.armed = over end
		if not sample.down and ui.previous then
			if over and over == ui.armed then clicked = over end
			ui.armed = nil
		end
	end
	ui.previous = sample.down
	return clicked
end

local function draw(card, lay, handles, hover, gw, gh, tip)
	local App, World, Gui = engine.Application, engine.World, engine.Gui
	local target
	local main = App.main_world()
	for _, w in ipairs(App.worlds() or {}) do if w ~= main then target = w break end end
	if not target then ui_clear() return end
	local rec = card.rec
	local current = u32(rec.at + 28)
	local class = class_now(rec)
	local kept = saved[rec.item]
	local sig = string.format("%.1f,%.1f,%.1f,%.1f|%d,%d|%s|%d,%d,%d|%s|%s|%d", card.x, card.y, card.w, card.h,
		gw, gh, handles.key, rec.item, current, rec.default, tostring(lay.grid ~= nil), tostring(hover), cfg_rev)
		.. "|" .. tostring(class) .. "|" .. (kept and (tostring(kept.p) .. "," .. tostring(kept.c)) or "-")
		.. string.format("|%.1f,%.1f|%.1f,%.1f|%s", lay.box.x, lay.box.y, lay.grid and lay.grid.x or 0, lay.grid and lay.grid.y or 0, tostring(lay.open))
		.. (lay.cbox and string.format("|%.1f,%.1f", lay.cbox.x, lay.cbox.y) or "") .. (ui.pad_mode and "|pad" or "") .. "|tip=" .. tostring(tip)
	if ui.world == target and ui.sig == sig then return end
	ui_clear()
	local gui = World.create_screen_gui(target, "scale", 1, 1)
	if not gui then error("screen surface unavailable", 0) end
	ui.gui, ui.world = gui, target
	local ids = engine.IdString64.from_hex
	local font, material = ids(handles.font), ids(handles.material)
	local ink = Gui.material(gui, material)
	if not ink then error("font material unavailable", 0) end
	-- the font material's settings, as DiverKit sets them for plain text
	local function slot(h) return ids(h .. "00000000") end
	for _, h in ipairs({ "8035c266", "5e8455fe", "309e7783", "82b803a8" }) do
		engine.Material.set_scalar(ink, slot(h), 0)
	end
	engine.Material.set_vector2(ink, slot("e13777ce"), engine.Vector2(1, -1))
	engine.Material.set_vector4(ink, slot("7701209e"), engine.Color(0, 0, 0, 0))
	engine.Material.set_texture(ink, slot("88bac99b"), ids(handles.atlas))
	local function color(r, g, b, a) return engine.Color(a or 255, r, g, b) end
	local gold, white, muted = color(255, 225, 0), color(238, 242, 246), color(153, 171, 184)
	local function rect(r, c, z)
		Gui.rect(gui, engine.Vector3(r.x, r.y, z or 960), engine.Vector2(r.w, r.h), c)
	end
	local function outline(r, c, t)
		rect({ x = r.x, y = r.y, w = r.w, h = t }, c, 962)
		rect({ x = r.x, y = r.y + r.h - t, w = r.w, h = t }, c, 962)
		rect({ x = r.x, y = r.y, w = t, h = r.h }, c, 962)
		rect({ x = r.x + r.w - t, y = r.y, w = t, h = r.h }, c, 962)
	end
	local function measure(value, size)
		local lo, hi = Gui.text_extents(gui, value, font, size)
		if not (lo and hi) then return #value * size * 0.5, 0 end
		return engine.Vector2.x(hi) - engine.Vector2.x(lo), engine.Vector2.x(lo)
	end
	-- one line of text inside r, shrunk to fit its width; middle = centered, else from the left
	local function text(value, r, size, c, pad, middle, z)
		local room = r.w - 2 * pad
		local lo, hi = Gui.text_extents(gui, value, font, size)
		if lo and hi then
			local wide = engine.Vector2.x(hi) - engine.Vector2.x(lo)
			if wide > room and wide > 0 then size = size * room / wide end
		end
		local x = r.x + pad
		if middle then
			local width, left = measure(value, size)
			x = math.max(x, r.x + (r.w - width) / 2 - left)
		end
		Gui.text(gui, value, font, size, material,
			engine.Vector3(x, r.y + (r.h - size * 0.7) / 2, z or 963), c)
	end
	local function centered(value, r, baseline, size, c)
		local width, left = measure(value, size)
		Gui.text(gui, value, font, size, material, engine.Vector3(r.x + (r.w - width) / 2 - left, baseline, 963), c)
	end
	local s = lay.s
	local t = math.max(1, s)
	-- the passive box, as in SAPP: [SET] when F6 saved the passive worn now
	local box = lay.box
	rect(box, color(0, 0, 0, cfg.box_alpha))
	outline(box, (hover == "box" or lay.open == "passive") and gold or muted, t)
	local pset = kept and kept.p == current
	text(passive_name(current) .. (pset and " [SET]" or ""), box, box.text * s, current ~= rec.default and gold or white, 6 * s, true)
	-- the class box
	local cbox = lay.cbox
	if cbox then
		rect(cbox, color(0, 0, 0, cfg.box_alpha))
		outline(cbox, (hover == "cbox" or lay.open == "class") and gold or muted, t)
		local cset = kept and kept.c ~= nil and kept.c == class
		text(class_text(rec, class) .. (cset and " [SET]" or ""), cbox, cbox.text * s, class ~= "own" and gold or white, 6 * s, true)
	end
	if lay.grid then
		local grid = lay.grid
		rect(grid, color(0, 0, 0, cfg.grid_alpha))
		outline(grid, gold, t)
		-- the keys of whatever was used last: the controller's, or the keyboard's
		local title
		if ui.pad_mode then
			title = lay.open == "class" and "ARMOR RATING   A PICK   B CLOSE   RB PASSIVE"
				or "ARMOR PASSIVE   (* = own)   A PICK   B CLOSE   Y SET   LB RATING"
		else
			title = lay.open == "class" and "ARMOR RATING   W S + SPACE"
				or "ARMOR PASSIVE   (* = this armor's own)   W A S D + SPACE"
		end
		text(title, { x = grid.x, y = grid.y + grid.h - TITLE_H * s, w = grid.w, h = TITLE_H * s }, 12 * s, muted, 6 * s)
		for _, cell in ipairs(lay.cells) do
			if hover == cell.key then rect(cell, color(70, 70, 70, 255), 961) end
			local on, label
			if cell.class ~= nil then
				on = cell.class == class
				label = cell.class == "own" and ("ORIGINAL (" .. rec.stock.class .. ")") or tostring(cell.class)
			else
				on = cell.enum == current
				label = passive_name(cell.enum)
				if cell.enum == rec.default then label = label .. " *" end
			end
			-- the pick is a solid gold bar with dark text; the bar the cursor sits on gets a gold frame just outside it; the rating grid is centered and larger
			if on then rect(cell, gold, 962) end
			if hover == cell.key then
				local frame = math.max(2, 2 * s)
				outline({ x = cell.x - frame, y = cell.y - frame, w = cell.w + 2 * frame, h = cell.h + 2 * frame }, gold, frame)
			end
			local rating = cell.class ~= nil
			text(label, cell, cfg.grid_text * (rating and RATING_BIG or 1) * s, on and color(12, 12, 12) or white, 6 * s, rating)
		end
	end
	if tip then
		-- the description panel: just right of the grid, top level with the highlighted row (right of the box when the grid is closed); on the left when the screen has no room below
		local enum = tip == "box" and current or tonumber(tip:sub(3))
		local size, head = cfg.grid_text * s, (cfg.grid_text + 2) * s
		local pw = 280 * s
		local room = pw - 16 * s
		local lines = {}
		for _, para in ipairs(TIP.desc[enum] or { "No description." }) do
			local line = "-"
			for word in para:gmatch("%S+") do
				local try = line .. " " .. word
				if line ~= "-" and line ~= "" and measure(try, size) > room then
					lines[#lines + 1] = line
					line = word
				else
					line = try
				end
			end
			lines[#lines + 1] = line
		end
		local lh = size * 1.5
		local ph = 8 * s + head * 1.6 + #lines * lh
		local row, edge = lay.box, lay.box
		if lay.grid then
			edge = lay.grid
			for _, cell in ipairs(lay.cells) do if cell.key == tip then row = cell end end
		end
		local px, py = edge.x + edge.w + 8 * s, row.y + row.h - ph
		if px + pw > gw then px = edge.x - pw - 8 * s end
		px = math.max(0, math.min(px, gw - pw))
		py = math.max(0, math.min(py, gh - ph))
		local panel = { x = px, y = py, w = pw, h = ph }
		rect(panel, color(0, 0, 0, math.max(cfg.grid_alpha, 235)), 970)
		for _, r in ipairs({ { panel.x, panel.y, panel.w, t }, { panel.x, panel.y + panel.h - t, panel.w, t },
				{ panel.x, panel.y, t, panel.h }, { panel.x + panel.w - t, panel.y, t, panel.h } }) do
			rect({ x = r[1], y = r[2], w = r[3], h = r[4] }, gold, 971)
		end
		text(passive_name(enum), { x = panel.x, y = panel.y + panel.h - head * 1.6 - 4 * s, w = panel.w, h = head * 1.6 }, head, gold, 8 * s, false, 972)
		for i, line in ipairs(lines) do
			text(line, { x = panel.x, y = panel.y + panel.h - head * 1.6 - 4 * s - i * lh, w = panel.w, h = lh }, size, white, 8 * s, false, 972)
		end
	end
	ui.sig = sig
end

-- At most a few explanatory lines in the log, and never the same one twice in a row.
local function ui_note(text)
	if text == ui.last_note or ui.notes >= 60 then return end
	ui.last_note, ui.notes = text, ui.notes + 1
	log(text)
end

-- Holds DiverKit still, or lets it go. Only a flag this mod cleared itself is
-- ever set again, and only while the player card is on screen.
local function hold_diverkit(want)
	local dk = rawget(_G, "CodexLoadouts")
	if type(dk) ~= "table" then ui.held = false return end
	if want then
		ui.free_frames = 0
		if dk.visible == true then
			dk.visible = false
			ui.held = true
			if not ui.held_said then ui.held_said = true; log("diverkit: held still while the mouse is on a box or a grid is open") end
		end
	elseif ui.held then
		ui.free_frames = (ui.free_frames or 0) + 1
		if ui.free_frames >= 3 then
			if dk.visible == false then dk.visible = true end
			ui.held = false
		end
	end
end

-- A drag has ended: where the box or the grid now sits goes into the settings.
local function drag_drop(card, lay)
	local s = lay.s
	local function units(v) return math.floor(v / s * 10 + 0.5) / 10 end
	if ui.drag.key == "box" then
		local kx, ky = lay.equip and "eq_box_x" or "box_x", lay.equip and "eq_box_y" or "box_y"
		cfg[kx], cfg[ky] = units(lay.box.x - card.x), units(lay.box.y - card.y)
		log(string.format("moved: box on the %s page to %s,%s", lay.equip and "Equipment" or "loadout", tostring(cfg[kx]), tostring(cfg[ky])))
	elseif ui.drag.key == "cbox" and lay.cbox then
		cfg.class_dx, cfg.class_dy = units(lay.cbox.x - lay.box.x), units(lay.cbox.y - lay.box.y)
		log(string.format("moved: class box to %s,%s from the passive box", tostring(cfg.class_dx), tostring(cfg.class_dy)))
	elseif lay.grid then
		cfg.grid_x, cfg.grid_y = units(lay.grid.x - card.x), units(lay.grid.y - card.y)
		log(string.format("moved: grid to %s,%s", tostring(cfg.grid_x), tostring(cfg.grid_y)))
	end
	write_cfg(cfg)
	cfg_rev = cfg_rev + 1
end

local function ui_hide()
	if ui.visible then ui_note("box: hidden (card not on screen)") end
	ui_clear()
	ui.visible, ui.open, ui.previous, ui.armed, ui.sel = false, nil, nil, nil, nil
	ui.press, ui.drag, ui.was_down = nil, nil, nil
	-- a pad button held while the card comes back must be let go first
	pad_block(true)
end

local function ui_step()
	if not engine then ui_note("box off: the game's Gui is unavailable") ui.dead = true return end
	if not ui.visible and state.frames % 10 ~= 0 then return end
	local card = find_card()
	if not card then ui_hide() return end
	local gw, gh = engine.Gui.resolution()
	-- same guard as DiverKit: the button sits near the top while the screen slides in
	if gh - (card.y + card.h) < 146 * (card.w / 420) then ui_hide() return end
	if not ui.handles or state.frames % 60 == 0 then
		local handles, why = read_handles()
		if not handles then ui_note("box: waiting, " .. tostring(why)) ui_hide() return end
		ui.handles = handles
	end
	if not ui.visible or state.frames % 120 == 0 then load_cfg() end
	if not ui.visible then
		ui.visible = true
		ui_note(string.format("box: card at %.1f,%.1f size %.1fx%.1f, screen %dx%d, slot %d, wearing %s",
			card.x, card.y, card.w, card.h, gw, gh, card.slot, card.rec.name))
	end
	local list, classes = grid_list(card.rec), class_list(card.rec)
	if ui.open == "class" and #classes == 0 then ui.open = nil end
	local function relayout() return layout(card, list, gw, gh, ui.open, nil, classes) end
	local lay = layout(card, list, gw, gh, ui.open, ui.drag, classes)
	local sample = pointer_sample(gw, gh)
	-- the controller: any of its buttons makes it the one the grid's title speaks
	-- for, until the mouse really moves
	local pad = cfg.pad ~= 0 and pad_sample(cfg) or nil
	if pad_busy(pad) then ui.pad_mode = true
	elseif ui.pad_mode and sample and ui.mx and math.abs(sample.x - ui.mx) + math.abs(sample.y - ui.my) > 4 then ui.pad_mode = false end
	local hover = sample and hit(lay.regions, sample.x, sample.y) or nil
	local clicked = pointer_step(sample, hover or (ui.open and sample and "outside") or nil)
	-- a press on a box or on the grid's own background that then moves is a drag, not a click
	if sample and cfg.drag ~= 0 then
		if sample.down and ui.was_down == false and (hover == "box" or hover == "cbox" or hover == "grid") then
			ui.press = { key = hover, x = sample.x, y = sample.y }
		elseif sample.down and ui.press then
			local dx, dy = sample.x - ui.press.x, sample.y - ui.press.y
			if ui.drag or math.abs(dx) + math.abs(dy) > 6 * lay.s then ui.drag = { key = ui.press.key, dx = dx, dy = dy } end
		elseif not sample.down and ui.press then
			if ui.drag then
				drag_drop(card, lay)
				clicked = nil
				ui.drag = nil
				lay = relayout()
				hover = hit(lay.regions, sample.x, sample.y)
			end
			ui.press = nil
		end
		ui.was_down = sample.down
	else
		ui.press, ui.drag, ui.was_down = nil, nil, nil
	end
	local function class_of_key(key) local v = key:sub(3) return v == "own" and "own" or tonumber(v) end
	if clicked then
		if clicked == "box" then ui.open = ui.open ~= "passive" and "passive" or nil
		elseif clicked == "cbox" then ui.open = ui.open ~= "class" and "class" or nil
		elseif clicked == "outside" then ui.open = nil
		elseif clicked:sub(1, 2) == "p:" then
			apply_pick(card.rec, tonumber(clicked:sub(3)))
			ui.open = nil
		elseif clicked:sub(1, 2) == "c:" then
			apply_class(card.rec, class_of_key(clicked))
			ui.open = nil
		end
		lay = relayout()
		hover = sample and hit(lay.regions, sample.x, sample.y) or nil
	end
	-- the controller's open button (or its row on the bindings page) opens the passive grid, or closes
	-- whichever is open; the rating button opens the rating grid, or closes it, or switches to it from the passive grid
	local open_pass = pad_step(pad, "open", false) and not menu.taken.open or menu.edge.open
	local open_rate = pad_step(pad, "open_rating", false) and not menu.taken.open_rating or menu.edge.open_rating
	if open_pass or open_rate then
		if open_pass then ui.open = not ui.open and "passive" or nil
		elseif ui.open == "class" then ui.open = nil
		elseif #classes > 0 then ui.open = "class" end
		ui.sel = nil
		lay = relayout()
		hover = sample and hit(lay.regions, sample.x, sample.y) or nil
	end
	if ui.open then
		-- one highlight, moved by the mouse or by W/A/S/D; Space picks it
		local items = ui.open == "class" and classes or list
		local cols_wanted = ui.open == "class" and 1 or cfg.grid_cols
		local sel = ui.sel
		if not sel or ui.sel_key ~= card.rec.item .. ui.open then
			sel = 1
			if ui.open == "class" then
				local c = class_now(card.rec)
				for i, v in ipairs(items) do if v == c then sel = i end end
			else
				local current = u32(card.rec.at + 28)
				for i, enum in ipairs(items) do if enum == current then sel = i end end
			end
			ui.sel_key = card.rec.item .. ui.open
		end
		if sample and (sample.x ~= ui.mx or sample.y ~= ui.my) and hover and hover:find("^[pc]:") then
			for _, cell in ipairs(lay.cells) do
				if cell.key == hover then for i, v in ipairs(items) do if v == (cell.class ~= nil and cell.class or cell.enum) then sel = i end end end
			end
		end
		local rows = math.max(1, math.ceil(#items / cols_wanted))
		local cols = math.ceil(#items / rows)
		local col, row = math.floor((sel - 1) / rows), (sel - 1) % rows
		-- every key and button is stepped each frame, so none misses its press
		local kw, ks, ka, kd = nav_step(VK_W, true), nav_step(VK_S, true), nav_step(VK_A, true), nav_step(VK_D, true)
		local pu, pd, pl, pr = pad_step(pad, "up", true), pad_step(pad, "down", true), pad_step(pad, "left", true), pad_step(pad, "right", true)
		local kpick, ppick, pclose = nav_step(VK_SPACE, false), pad_step(pad, "pick", false), pad_step(pad, "close", false)
		local pset, pprev, pnext = pad_step(pad, "set", false), pad_step(pad, "prev", false), pad_step(pad, "next", false)
		if kw or ks or ka or kd or kpick then ui.pad_mode = false end
		if kw or pu then
			row = row - 1
			if row < 0 then row = rows - 1 end
		end
		if ks or pd then
			row = row + 1
			if row >= rows or col * rows + row + 1 > #items then row = 0 end
		end
		if ka or pl then col = (col - 1) % cols end
		if kd or pr then col = (col + 1) % cols end
		sel = math.max(1, math.min(#items, col * rows + row + 1))
		ui.sel = sel
		if pset then hard_set(card.rec) end
		local switch = (pprev and #classes > 0 and "class") or (pnext and "passive") or nil
		if kpick or ppick then
			if ui.open == "class" then apply_class(card.rec, items[sel]) else apply_pick(card.rec, items[sel]) end
			ui.open, ui.sel = nil, nil
		elseif pclose then
			ui.open, ui.sel = nil, nil
		elseif switch and switch ~= ui.open then
			ui.open, ui.sel = switch, nil
		end
		if not ui.open or switch then
			lay = relayout()
			hover = sample and hit(lay.regions, sample.x, sample.y) or nil
		else
			hover = (ui.open == "class" and "c:" or "p:") .. tostring(items[sel])
		end
	end
	if not ui.open then
		ui.sel = nil
		nav_block()
		pad_block(false)
	end
	-- while the grid is open, and a few frames after it closes so the key that closed it is not heard either
	-- (for as long as a pad button stays held); Back as well while the controller drives it
	if ui.open then
		ui.block_until = state.frames + 10
		if ui.pad_mode then ui.back_until = state.frames + 10 end
	elseif ui.block_until and state.frames <= ui.block_until and pad_busy(pad) then
		ui.block_until = state.frames + 10
		if ui.back_until and state.frames <= ui.back_until then ui.back_until = state.frames + 10 end
	end
	if cfg.block_keys ~= 0 and ui.block_until and state.frames <= ui.block_until then
		block_keys(ui.back_until ~= nil and state.frames <= ui.back_until)
	end
	if sample then ui.mx, ui.my = sample.x, sample.y end
	-- held from the moment the mouse is on the box, so DiverKit sees neither the press nor the release
	local busy = ui.open or hover ~= nil or ui.drag ~= nil or (sample ~= nil and sample.down and ui.armed ~= nil)
	if cfg.hold_diverkit ~= 0 and busy then hold_diverkit(true)
	elseif not (sample and sample.down) then hold_diverkit(false) end
	-- the description: after the cursor (or the highlight) has rested on one passive for TIP_DELAY seconds
	local tip_key = hover and ui.open ~= "class" and not ui.drag and not ui.press and (hover == "box" or hover:find("^p:")) and hover or nil
	if tip_key ~= ui.tip_key then ui.tip_key, ui.tip_at, ui.tip_shown = tip_key, tip_key and TIP.wall() or nil, false end
	if tip_key and not ui.tip_shown and TIP.wall() - ui.tip_at >= TIP.delay then ui.tip_shown = true end
	local tip = tip_key and ui.tip_shown and tip_key or nil
	draw(card, lay, ui.handles, hover, gw, gh, tip)
end

-- for the offline test harness only
state.test = { parse_cfg = parse_cfg, layout = layout, hit = hit, ui = ui, native = native, block = block }
--@PERSONAL_BEGIN@
state.test.redraw = redraw
--@PERSONAL_END@

-- ------------------------------------------------------------------ driver
local previous_update = rawget(_G, "update")
if type(previous_update) ~= "function" then
	log("stopped: game update callback unavailable")
	return true
end

local phase, wait, last_loadout, retries = "start", 240, nil, 0
--@PERSONAL_BEGIN@
-- Runs every frame in the watch phase. Only a change seen between two frames
-- with the card up counts: a change made through the game's own selector, or
-- while the card was away, is already drawn by the game.
local function redraw_step()
	if redraw.dead or not redraw.fn then return end
	local c = cfg.redraw == 1 and find_card()
	if not c then redraw.last, redraw.due = nil, nil return end
	local last, fresh, changed = redraw.last, false, false
	if not last or last.payload ~= c.payload then
		last = { payload = c.payload }
		redraw.last, redraw.due, fresh = last, nil, true
	end
	for i = 1, #ITEM_FIELDS do
		local v = u32(c.payload + ITEM_FIELDS[i])
		if last[i] ~= v then last[i] = v; changed = true end
	end
	if fresh then return end
	if changed then redraw.due = state.frames + 30 return end
	if not redraw.due or state.frames < redraw.due then return end
	redraw.due = nil
	local card, payload = c.card, c.payload
	local tiles = card + TILES_OFFSET
	need(tiles + TILES_PAYLOAD, 0x18, "card tiles")
	local mine, mode = u8(card + 0x1ee0c), u8(card + 0x1ee0e)
	if mine ~= 1 or mode > 1 then return end                               -- not the local player's card
	if ptr(tiles + TILES_PAYLOAD) ~= payload or u8(tiles + TILES_FLAG) ~= mine then return end   -- the game would not skip
	local _, _, ok, prot = query(tiles + TILES_FLAG)
	if not ok or prot ~= 0x04 then error("card tiles are not plain writable memory", 0) end
	local flag = ffi.cast("uint8_t *", tiles + TILES_FLAG)
	flag[0] = 0
	local called, why = pcall(native.refresh, redraw.fn, card, payload, true, mode == 1)
	if flag[0] ~= mine then
		flag[0] = mine
		error(called and "the game did not rebuild the tiles" or tostring(why), 0)
	end
	-- the pictures: only on the equipment page (showing that page renders them anyway), and only in the
	-- card state in which the game itself calls the routine
	local pictures = "pictures left for the page flip"
	need(card + CARD_PAGE, 4, "card page"); need(card + CARD_STATE, 4, "card state")
	if u32(card + CARD_PAGE) == 1 and u8(card + CARD_COLLAPSING) == 0 and u32(card + CARD_STATE) == 1
		and ptr(tiles + TILES_PAYLOAD) == payload then
		local drawn, err = pcall(native.thumbs, redraw.thumbs, tiles)
		if not drawn then error("picture routine failed: " .. tostring(err), 0) end
		pictures = "pictures rendered again"
	end
	redraw.count = redraw.count + 1
	log(string.format("redraw: equipment tiles redrawn after a loadout change, %s (%d this session)", pictures, redraw.count))
end
--@PERSONAL_END@

local function tick()
	state.frames = state.frames + 1
	if phase == "dead" then return end
	if wait > 0 then wait = wait - 1 return end
	if phase == "start" then
		prepare_scan(); phase = "scan"
	elseif phase == "scan" then
		if scan_step() then
			resolve_globals(); resolve_input()
--@PERSONAL_BEGIN@
			resolve_redraw()
--@PERSONAL_END@
			phase = "catalog"
		end
	elseif phase == "catalog" then
		local out, why = read_catalog()
		if out then records = out; phase = "owned"; retries = 0
		else
			retries = retries + 1
			if retries == 1 or retries % 20 == 0 then log("waiting: " .. why) end
			wait = 180
		end
	elseif phase == "owned" then
		local owned, total, count = read_owned()
		if owned and total > 0 then
			report_owned(owned, total, count)
			apply_saved()
			log("DISCOVERY OK - on the player card: click the box, or the controller's right stick (pad_open) for passives and left stick (pad_open_rating) for the rating grid; both rebindable on the MODS tab. Keys: F6 (set_key) = hard set the worn armor's class and passive")
			phase = "watch"
		else
			retries = retries + 1
			if retries == 1 or retries % 20 == 0 then log("waiting: " .. tostring(total or "no owned armor seen yet")) end
			wait = 180
		end
	elseif phase == "watch" then
		menu_poll()
		if not ui.dead then
			local ok, err = pcall(ui_step)
			if not ok then
				ui.dead = true
				log("box stopped on error: " .. tostring(err) .. " (saved hard sets and the hard-set key still work)")
				pcall(ui_clear)
			end
		end
--@PERSONAL_BEGIN@
		local drawn, why = pcall(redraw_step)
		if not drawn then
			redraw.dead = true
			log("redraw: off for this session, " .. tostring(why))
		end
--@PERSONAL_END@
		-- the worn armor is read twice a second on the loadout screen, once a second elsewhere (in a mission)
		local set = (cfg.set_key >= 1 and pressed(cfg.set_key)) or menu.edge.hard_set
		if set or state.frames % (ui.visible and 30 or 60) == 0 then
			local text, rec = read_loadout()
			if rec and set then hard_set(rec)
			elseif set then log("key ignored: " .. text) end
			if rec then revert_others(rec); sync_saved(rec)
			else
				local read, c = pcall(read_cache)
				local worn = read and c and records[c.armor]
				if worn then revert_others(worn) end
			end
			if rec and set then text = read_loadout() end
			if rec then text = text .. ", class " .. class_text(rec, class_now(rec)) .. " | " .. cache_text() end
			if text ~= last_loadout then last_loadout = text; log(text) end
		end
	end
end

-- The mod's own cost: only tick() is timed (not the game's or other mods'
-- updates, which this wrapper also calls), and the average is logged once a
-- minute, so a frame-time tool's number can be checked against it.
local qpc = ffi.new("int64_t[1]")
local rate = (pcall(function () return kernel.QueryPerformanceFrequency(qpc) end) and tonumber(qpc[0]) or 0)
local function now() kernel.QueryPerformanceCounter(qpc) return tonumber(qpc[0]) end
local cost = { spent = 0, worst = 0, frames = 0 }
if rate <= 0 or not pcall(now) then rate = 0 end
local function timed_tick()
	if rate == 0 then return pcall(tick) end
	local t0 = now()
	local ok, err = pcall(tick)
	local t1 = now()
	local d = t1 - t0
	cost.spent, cost.frames = cost.spent + d, cost.frames + 1
	if d > cost.worst then cost.worst = d end
	cost.from = cost.from or t0
	if t1 - cost.from >= 60 * rate then
		log(string.format("cost: own work %.3f ms per second over %.0f s (%d frames, worst frame %.3f ms)",
			cost.spent * 1000 / (t1 - cost.from), (t1 - cost.from) / rate, cost.frames, cost.worst * 1000 / rate))
		cost.spent, cost.worst, cost.frames, cost.from = 0, 0, 0, t1
	end
	return ok, err
end

-- after the game's own update (and the mods before this one) has run
local function after(ok, ...)
	local fine, err = timed_tick()
	if not fine then
		log("stopped on error: " .. tostring(err))
		phase = "dead"
	end
	if not ok then error((...), 0) end
	return ...
end
rawset(_G, "update", function (...) return after(pcall(previous_update, ...)) end)

local previous_shutdown = rawget(_G, "shutdown")
if type(previous_shutdown) == "function" then
	rawset(_G, "shutdown", function (...)
		pcall(ui_clear)
		pcall(restore_all)
		pcall(log, "shutdown: every changed armor put back")
		return previous_shutdown(...)
	end)
end

log("loaded (" .. REVISION .. ")")
return true
