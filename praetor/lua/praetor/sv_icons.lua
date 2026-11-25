-- Praetor: custom pixel-art icons. Staff who manage ranks or tags draw them in
-- the icon editor (Ranks / Tags > icon > Create icon) and they can be used on
-- ranks and tags like the built-in ones.
--
-- An icon is 16x16 (pixel mode) or 32x32 (paint mode, `s` = 32): `px` has
-- s * s characters, "." for an empty pixel or a hex digit (0-f) pointing into
-- `pal`, a list of up to 16 colours ("rrggbb").
-- Names are "c_<number>", so they pass the normal icon name check.
local P = Praetor

local MAX_ICONS = 64
local SIZE = 16

P.CustomIcons = P.DB.Get("icons", {}) or {}
P.MaxCustomIcons = MAX_ICONS

local function save() P.DB.Set("icons", P.CustomIcons) end
local function broadcast() P.Send(nil, "icons", P.CustomIcons) end

local function clean(d)
	if not istable(d) then return nil end
	local px = d.px
	local size = tonumber(d.s) == 32 and 32 or SIZE
	if not isstring(px) or #px ~= size * size or not px:match("^[%.0-9a-f]+$") then return nil end
	if not px:find("[0-9a-f]") then return nil end -- nothing drawn
	if not istable(d.pal) or #d.pal < 1 or #d.pal > 16 then return nil end
	local pal = {}
	for i = 1, #d.pal do
		local h = d.pal[i]
		if not isstring(h) or not h:match("^%x%x%x%x%x%x$") then return nil end
		pal[i] = h:lower()
	end
	for ch in px:gmatch("[0-9a-f]") do
		if tonumber(ch, 16) + 1 > #pal then return nil end
	end
	return { n = P.Trim(P.Str(d.n or "", 24)), px = px, pal = pal, s = size ~= SIZE and size or nil }
end

P.Receive("icon_save", { perm = { "manage_ranks", "manage_tags", "manage_announce" }, rate = 1, max = 16384 }, function(ply, data)
	local icon = clean(data)
	if not icon then P.Notify(ply, "ic_bad", nil, "warn") return end
	local id = isstring(data.id) and data.id:match("^c_%d+$") and P.CustomIcons[data.id] and data.id or nil
	if not id then
		if table.Count(P.CustomIcons) >= MAX_ICONS then
			P.Notify(ply, "ic_full", { V = MAX_ICONS }, "warn")
			return
		end
		local n = tonumber(P.DB.Get("icons_next", { 1 })[1]) or 1
		while P.CustomIcons["c_" .. n] do n = n + 1 end
		P.DB.Set("icons_next", { n + 1 })
		id = "c_" .. n
	end
	icon.by = ply:SteamID64()
	icon.t = os.time()
	P.CustomIcons[id] = icon
	save()
	broadcast()
	P.Send(ply, "icon_saved", { id = id })
end)

P.Receive("icon_delete", { perm = { "manage_ranks", "manage_tags", "manage_announce" }, rate = 2 }, function(ply, data)
	local id = isstring(data.id) and data.id or ""
	if not P.CustomIcons[id] then return end
	P.CustomIcons[id] = nil
	save()
	broadcast()
end)

hook.Add("Praetor.UserLoaded", "Praetor.Icons", function(ply)
	if IsValid(ply) then P.Send(ply, "icons", P.CustomIcons) end
end)
