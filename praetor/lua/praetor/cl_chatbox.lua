-- Praetor: the chat box. Steam avatar, name, animated rank / custom tags,
-- images and GIFs from allowed hosts, command suggestions and message history.
-- Right click a message: reply, mention, copy, profile, hide the player,
-- moderation and (staff) delete it for everyone.
-- Only active when the chat mode is "praetor" (see cl_chat.lua).
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local imagesVar = CreateClientConVar("praetor_chat_images", "1", true, false, "Show images and GIFs in the Praetor chat")
local wsVar = CreateClientConVar("praetor_chat_workshop", "1", true, false, "Show a preview of Workshop links in the Praetor chat")

local CB = P.ChatBox or {}
P.ChatBox = CB

local MAX_LINES = 150
local MAX_IMAGES = 8
local SHOW_TIME = 12
local MAX_CHARS = 126

CB.lines = CB.lines or {}
local lines = CB.lines

local function active() return P.ChatMode and P.ChatMode() == "praetor" end

-- players whose messages this client hides (kept between sessions)
CB.ignored = CB.ignored or util.JSONToTable(cookie.GetString("praetor_chat_ignore", "") or "") or {}
local function saveIgnored() cookie.Set("praetor_chat_ignore", util.TableToJSON(CB.ignored)) end

-- ------------------------------------------------------------------ building lines

local function seg(kind, t) t.kind = kind return t end

local LINK_COL = Color(110, 170, 255)
local LINK_HOV = Color(170, 205, 255)
local WS_H = 92

-- Workshop items linked in the chat: name, description, picture and author
local WS = {}
local function wsInfo(id)
	local e = WS[id]
	if e then return e end
	e = { state = "loading", id = id }
	WS[id] = e
	if not steamworks or not steamworks.FileInfo then e.state = "fail" return e end
	steamworks.FileInfo(id, function(info)
		if not info or not info.title or info.title == "" or info.error then e.state = "fail" return end
		e.state = "ok"
		e.title = info.title
		local d = tostring(info.description or "")
		d = d:gsub("%[[^%]]*%]", " "):gsub("https?://%S+", ""):gsub("[\r\n\t]+", " "):gsub("%s%s+", " ")
		e.desc = P.Trim(d)
		e.size = tonumber(info.size)
		e.tags = isstring(info.tags) and info.tags or nil
		if info.previewid and steamworks.Download then
			steamworks.Download(info.previewid, true, function(path)
				if not path then return end
				local ok, mat = pcall(AddonMaterial, path)
				if ok and mat and not mat:IsError() then e.mat = mat end
			end)
		end
		if info.owner and steamworks.RequestPlayerInfo then
			steamworks.RequestPlayerInfo(info.owner, function(name) if name and name ~= "" then e.owner = name end end)
		end
	end)
	return e
end
P.WorkshopInfo = wsInfo

local function wsID(text)
	text = tostring(text or "")
	return text:match("steamcommunity%.com/sharedfiles/filedetails/%?[^%s]-id=(%d+)")
		or text:match("steamcommunity%.com/workshop/filedetails/%?[^%s]-id=(%d+)")
end

local function sizeText(b)
	if not b or b <= 0 then return nil end
	if b >= 1024 ^ 3 then return string.format("%.1f GB", b / 1024 ^ 3) end
	if b >= 1024 ^ 2 then return string.format("%.1f MB", b / 1024 ^ 2) end
	return string.format("%d KB", math.max(1, math.floor(b / 1024)))
end

-- the preview card under a message with a Workshop link
local function drawWs(id, x, y, w, alpha)
	local e = wsInfo(id)
	local h = S(WS_H) - S(8)
	local a = alpha
	UI.Round(x, y, w, h, S(10), Color(C.panel.r, C.panel.g, C.panel.b, 240 * a), Color(LINK_COL.r * 0.6, LINK_COL.g * 0.6, LINK_COL.b * 0.6, 220 * a))
	UI.Round(x + S(4), y + S(8), S(4), h - S(16), S(2), Color(LINK_COL.r, LINK_COL.g, LINK_COL.b, 255 * a))
	local ps = h - S(12)
	local px, py = x + S(10), y + S(6)
	if e.mat then
		surface.SetMaterial(e.mat)
		surface.SetDrawColor(255, 255, 255, 255 * a)
		surface.DrawTexturedRect(px, py, ps, ps)
		UI.Outline(px, py, ps, ps, Color(0, 0, 0, 120 * a))
	else
		UI.Round(px, py, ps, ps, S(8), Color(C.panel2.r, C.panel2.g, C.panel2.b, 255 * a))
		local bob = e.state == "loading" and (math.floor(RealTime() * 4) % 4) or 0
		UI.Icon(e.state == "fail" and "box_no" or "box", px + (ps - 32) / 2, py + (ps - 32) / 2 - bob, 32, Color(255, 255, 255, 160 * a))
	end
	local tx = px + ps + S(10)
	local tw = x + w - tx - S(10)
	UI.Icon("gear", tx, y + S(7), 16, Color(255, 255, 255, 170 * a))
	draw.SimpleText(P.L("chat_ws"), "Praetor.Tiny", tx + 20, y + S(15), Color(LINK_COL.r, LINK_COL.g, LINK_COL.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if e.state == "loading" then
		draw.SimpleText(P.L("chat_ws_loading"), "Praetor.Small", tx, y + S(40), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		return
	elseif e.state == "fail" then
		draw.SimpleText(P.L("chat_ws_item", { V = id }), "Praetor.ChatB", tx, y + S(40), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		return
	end
	draw.SimpleText(UI.Fit(e.title, "Praetor.ChatB", tw), "Praetor.ChatB", tx, y + S(34), Color(C.ivory.r, C.ivory.g, C.ivory.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if e.linesW ~= tw then
		e.lines = UI.Wrap(e.desc ~= "" and e.desc or "-", "Praetor.Tiny", tw)
		e.linesW = tw
	end
	for i = 1, math.min(2, #e.lines) do
		local l = e.lines[i]
		if i == 2 and #e.lines > 2 then l = UI.Fit(l .. " ...", "Praetor.Tiny", tw) end
		draw.SimpleText(l, "Praetor.Tiny", tx, y + S(50) + (i - 1) * S(13), Color(C.muted.r, C.muted.g, C.muted.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local info = {}
	if e.owner then info[#info + 1] = P.L("chat_ws_by", { S = e.owner }) end
	if sizeText(e.size) then info[#info + 1] = sizeText(e.size) end
	if e.tags then info[#info + 1] = (e.tags:gsub(",", ", ")) end
	draw.SimpleText(UI.Fit(table.concat(info, "  ·  "), "Praetor.Tiny", tw), "Praetor.Tiny", tx, y + h - S(10), Color(C.dim.r, C.dim.g, C.dim.b, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function textSegs(out, text, col, font)
	out[#out + 1] = seg("text", { text = tostring(text), col = col, font = font or "Praetor.Chat" })
end

-- url of an image this message may show, or nil
local function imageURL(meta)
	if not meta or not IsValid(meta.ply) then return nil end
	if not P.Setting("chat_images") or not imagesVar:GetBool() then return nil end
	if not P.Has(meta.ply, "chat_images") then return nil end
	local url = tostring(meta.text or ""):match("(https://[^%s]+)")
	if not url or #url > 300 then return nil end
	if not url:match("^https://[%w%-%._~:/%?#%[%]@!%$&%(%)%*%+,;=%%]+$") then return nil end
	local host = url:match("^https://([^/:%?#]+)")
	if not host then return nil end
	host = host:lower()
	local ok = false
	for h in tostring(P.Setting("chat_image_hosts") or ""):gmatch("[^,%s]+") do
		if host == h:lower() then ok = true break end
	end
	if not ok then return nil end
	local path = url:match("^https://[^/]+(/[^%?#]*)") or ""
	if not path:lower():match("%.png$") and not path:lower():match("%.jpe?g$") and not path:lower():match("%.gif$") and not path:lower():match("%.webp$") then
		return nil
	end
	return url
end

local imagePanels = {}

local function makeImage(line, url)
	-- old images become a plain link
	if #imagePanels >= MAX_IMAGES then
		local old = table.remove(imagePanels, 1)
		if IsValid(old) then old:Remove() end
	end
	local size = S(math.Clamp(tonumber(P.Setting("chat_image_size")) or 160, 60, 400))
	line.imgH = size
	line.img = url
	if not IsValid(CB.frame) then return end
	local html = vgui.Create("DHTML", CB.frame.lines)
	html:SetSize(size * 2, size)
	html:SetMouseInputEnabled(false)
	html:SetVisible(false)
	html:SetHTML(string.format([[<html><body style="margin:0;padding:0;overflow:hidden;background:transparent">
<img src="%s" style="max-height:%dpx;max-width:%dpx;display:block;border-radius:10px;border:2px solid #3c345c"></body></html>]], url, size, size * 2))
	line.html = html
	imagePanels[#imagePanels + 1] = html
end

-- does the message mention me? (@name, or the name as a whole word, 3+ letters)
local function mentionsMe(text, from)
	local me = LocalPlayer()
	if not IsValid(me) or from == me then return false end
	local nick = me:Nick():lower()
	if #nick < 3 then return false end
	local t = " " .. tostring(text or ""):lower() .. " "
	local s = t:find(nick, 1, true)
	if not s then return false end
	local before, after = t:sub(s - 1, s - 1), t:sub(s + #nick, s + #nick)
	return not before:match("[%w]") and not after:match("[%w]")
end

-- chat.AddText arguments (+ the meta set by cl_chat for player messages)
function CB.Add(args, meta)
	local line = { t = RealTime(), stamp = os.date("%H:%M"), segs = {}, plain = {} }
	local segs = line.segs
	if meta then
		line.ply = IsValid(meta.ply) and meta.ply or nil
		line.sid = line.ply and line.ply:SteamID64() or nil
		if line.sid and CB.ignored[line.sid] then return end
		line.bot = line.ply and line.ply:IsBot() or nil
		line.botName = line.bot and line.ply:Nick() or nil
		line.name = meta.name
		line.text = meta.text
		line.reply = meta.reply
		if meta.chan == "local" then textSegs(segs, P.L("chat_chan_local") .. "  ", C.sky, "Praetor.ChatB") end
		if meta.chan == "staff" then textSegs(segs, P.L("chat_chan_staff") .. "  ", C.crimsonL, "Praetor.ChatB") line.staff = true end
		if meta.dead then textSegs(segs, "*" .. P.L("chat_dead") .. "* ", C.crimsonL) end
		if meta.team then textSegs(segs, "(" .. P.L("chat_team") .. ") ", C.laurel) end
		if meta.rank then segs[#segs + 1] = seg("badge", { style = meta.rank, icon = meta.rankIcon }) end
		if meta.tag then segs[#segs + 1] = seg("badge", { style = meta.tag, icon = meta.tag.icon }) end
		textSegs(segs, meta.name, meta.nameCol or C.ivory, "Praetor.ChatB")
		textSegs(segs, ": ", C.muted)
		local url = imageURL(meta)
		local msg = meta.text
		if url and P.Trim(msg) == url then msg = "" end
		if msg ~= "" then textSegs(segs, msg, meta.textCol or color_white) end
		line.plain[1] = meta.name .. ": " .. meta.text
		if url then line.pendingImg = url end
		line.url = tostring(meta.text or ""):match("(https?://[^%s]+)")
		-- a reply to me also counts as a mention
		local me = LocalPlayer()
		line.mention = mentionsMe(meta.text, line.ply) or (line.reply ~= nil and IsValid(me) and line.reply.to == me:SteamID64() and line.ply ~= me)
		if line.mention then UI.Sound("chat") end
	else
		local col = color_white
		for _, v in ipairs(args) do
			if IsColor(v) or (istable(v) and v.r and v.g and v.b) then
				col = Color(v.r, v.g, v.b)
			elseif isentity(v) and IsValid(v) and v:IsPlayer() then
				textSegs(segs, v:Nick(), team.GetColor(v:Team()), "Praetor.ChatB")
				line.plain[#line.plain + 1] = v:Nick()
			elseif v ~= nil then
				textSegs(segs, tostring(v), col)
				line.plain[#line.plain + 1] = tostring(v)
			end
		end
	end
	line.plain = table.concat(line.plain)
	if #segs == 0 then return end
	local src = meta and tostring(meta.text or "") or line.plain
	line.url = line.url or src:match("(https?://[^%s]+)")
	local ws = wsID(src)
	if ws and wsVar:GetBool() then line.ws = ws wsInfo(ws) end
	-- lines from other addons (DarkRP OOC, other chat mods): the speaker is the
	-- first player passed to chat.AddText, or the name before ": "
	if not line.ply and not meta then
		local who
		for _, v in ipairs(args) do
			if isentity(v) and IsValid(v) and v:IsPlayer() then who = v break end
			if isstring(v) and v ~= "" then break end
		end
		if not who then
			local head = line.plain:match("^(.-): ")
			if head and #head <= 64 then
				head = P.Trim(head:gsub("^%(.-%)%s*", ""):gsub("^%*.-%*%s*", ""))
				for _, p in ipairs(player.GetAll()) do
					if p:Nick() == head then who = p break end
				end
			end
		end
		if IsValid(who) then
			line.ply = who
			line.sid = who:SteamID64()
			line.bot = who:IsBot() or nil
			line.botName = line.bot and who:Nick() or nil
			line.name = who:Nick()
			if line.sid and CB.ignored[line.sid] then return end
		end
	end
	if IsValid(line.ply) then line.frame = UI.AvatarFrame(line.ply) end
	lines[#lines + 1] = line
	if line.pendingImg then makeImage(line, line.pendingImg) line.pendingImg = nil end
	while #lines > MAX_LINES do
		local old = table.remove(lines, 1)
		if IsValid(old.html) then old.html:Remove() end
	end
	if IsValid(CB.frame) then
		CB.frame.lines.dirty = true
		if CB.open and CB.frame.lines.scroll > 0 then CB.frame.lines.unseen = (CB.frame.lines.unseen or 0) + 1 end
	end
end

function CB.Clear()
	for _, l in ipairs(lines) do if IsValid(l.html) then l.html:Remove() end end
	table.Empty(lines)
	imagePanels = {}
	if IsValid(CB.frame) then CB.frame.lines.scroll = 0 CB.frame.lines.dirty = true end
end

-- every chat.AddText also lands in the box
CB.OrigAddText = CB.OrigAddText or chat.AddText
function chat.AddText(...)
	if active() then
		local ok, err = pcall(CB.Add, { ... }, P.ChatMeta)
		if not ok then ErrorNoHalt("[Praetor] chat: " .. tostring(err) .. "\n") end
	end
	return CB.OrigAddText(...)
end

hook.Add("ChatText", "Praetor.ChatBox", function(_, _, text, kind)
	if not active() or kind == "chat" then return end
	if not text or P.Trim(text) == "" then return end
	CB.Add({ C.muted, text })
end)

-- a staff member deleted a message: it stays as "message deleted"
P.On("chat_deleted", function(d)
	for i = #lines, 1, -1 do
		local l = lines[i]
		if l.sid == d.sid and l.text == d.text and not l.deleted then
			-- lineSegs() keeps the badges and the name and replaces the message
			l.deleted = true
			l.url = nil
			if IsValid(l.html) then l.html:Remove() end
			l.img = nil
			l.layout = nil
			break
		end
	end
	if IsValid(CB.frame) then CB.frame.lines.dirty = true end
end)

-- ------------------------------------------------------------------ layout

local function fontH(font)
	surface.SetFont(font)
	local _, h = surface.GetTextSize("Ag")
	return h
end

-- the segments drawn for a line (a deleted message keeps only who sent it)
local function lineSegs(line)
	if not line.deleted then return line.segs end
	local out = {}
	for _, sg in ipairs(line.segs) do
		out[#out + 1] = sg
		if sg.kind == "text" and sg.text == ": " then break end
	end
	out[#out + 1] = seg("text", { text = P.L("chat_deleted"), col = C.dim, font = "Praetor.ChatSmall" })
	return out
end

-- splits a line into rows of items that fit in `width`
local function layoutLine(line, width)
	local rowH = fontH("Praetor.Chat") + S(4)
	local badgeH = rowH - S(4)
	local rows = { {} }
	local x = 0
	local stampW = 0
	if P.Setting("chat_timestamps") then
		surface.SetFont("Praetor.ChatSmall")
		stampW = surface.GetTextSize(line.stamp .. " ") + S(2)
	end
	local avW = ((line.sid and P.Setting("chat_avatars")) or line.annIcon) and (rowH + S(4)) or 0
	local indent = stampW + avW
	x = indent
	local function newRow() rows[#rows + 1] = {} x = S(10) end
	local function push(it, w)
		if x + w > width and x > indent and #rows[#rows] > 0 then newRow() end
		it.x = x
		it.w = w
		local r = rows[#rows]
		r[#r + 1] = it
		x = x + w
	end
	for _, sg in ipairs(lineSegs(line)) do
		if sg.kind == "badge" then
			local w = UI.BadgeWidth(sg.style, sg.icon, "Praetor.ChatTag", badgeH)
			push({ kind = "badge", style = sg.style, icon = sg.icon, h = badgeH }, w + S(4))
		else
			local font = UI.FontFor(sg.text, sg.font)
			surface.SetFont(font)
			for word in tostring(sg.text):gmatch("%S*%s*") do
				if word ~= "" then
					local w = surface.GetTextSize(word)
					local link = word:match("^(https?://%S+)")
					local col = link and LINK_COL or sg.col
					if w > width - S(10) then
						-- very long words are cut by characters
						local buf = ""
						for _, ch in ipairs(P.Chars(word)) do
							local try = buf .. ch
							if surface.GetTextSize(try) + x > width and buf ~= "" then
								push({ kind = "text", text = buf, col = col, font = font, link = link, uw = surface.GetTextSize(buf) }, surface.GetTextSize(buf))
								newRow()
								buf = ch
							else
								buf = try
							end
						end
						if buf ~= "" then push({ kind = "text", text = buf, col = col, font = font, link = link, uw = surface.GetTextSize(P.Trim(buf)) }, surface.GetTextSize(buf)) end
					else
						push({ kind = "text", text = word, col = col, font = font, link = link, uw = link and surface.GetTextSize(P.Trim(word)) or nil }, w)
					end
				end
			end
		end
	end
	-- the message this one answers, in a small line on top
	local top = line.reply and (fontH("Praetor.ChatSmall") + S(4)) or 0
	local h = top + #rows * rowH
	if line.ws then h = h + S(WS_H) end
	if line.img then h = h + line.imgH + S(6) end
	line.layout = { rows = rows, rowH = rowH, h = h, width = width, stampW = stampW, avW = avW, top = top }
end

-- ------------------------------------------------------------------ right click

local function voiceMuteLabel(ply) return ply:IsMuted() and P.L("chat_unmute_voice") or P.L("chat_mute_voice") end

local function lineMenu(line)
	local items = {}
	local ply = line.ply
	local me = LocalPlayer()
	if line.name then
		items[#items + 1] = { P.Upper(line.name), kind = "title" }
		if not line.deleted then
			items[#items + 1] = { P.L("chat_reply"), "reply", function() CB.SetReply(line) end }
		end
		if IsValid(ply) and ply ~= me then
			items[#items + 1] = { P.L("chat_mention"), "bolt", function() CB.Insert("@" .. ply:Nick() .. " ") end }
		end
	end
	local copy = { { P.L("chat_copy"), "copy", function() SetClipboardText(line.text or line.plain or "") P.Toast(P.L("copied"), "", "ok", 2) end } }
	if line.name then copy[#copy + 1] = { P.L("chat_copy_name"), "copy", function() SetClipboardText(line.name) P.Toast(P.L("copied"), line.name, "ok", 2) end } end
	if line.sid and not line.bot then
		local sid32 = util.SteamIDFrom64(line.sid)
		copy[#copy + 1] = { P.L("copy_steamid"), "copy", function() SetClipboardText(sid32) P.Toast(P.L("copied"), sid32, "ok", 2) end }
		copy[#copy + 1] = { P.L("copy_steamid64"), "copy", function() SetClipboardText(line.sid) P.Toast(P.L("copied"), line.sid, "ok", 2) end }
	end
	if line.img then copy[#copy + 1] = { P.L("chat_copy_link"), "copy", function() SetClipboardText(line.img) end } end
	if #copy == 1 then items[#items + 1] = copy[1] else items[#items + 1] = { P.L("chat_copy_menu"), "copy", nil, nil, copy } end
	if line.url then items[#items + 1] = { P.L("chat_open_link"), "send", function() gui.OpenURL(line.url) end } end

	if IsValid(ply) and ply ~= me then
		items[#items + 1] = false
		if not ply:IsBot() then items[#items + 1] = { P.L("open_profile"), "players", function() ply:ShowProfile() end } end
		items[#items + 1] = { voiceMuteLabel(ply), "mic", function() ply:SetMuted(not ply:IsMuted()) end }
		if line.sid then
			items[#items + 1] = { P.L("chat_hide_player"), "eye", function()
				CB.ignored[line.sid] = ply:Nick()
				saveIgnored()
				P.Toast(P.L("chat_hidden"), P.L("chat_hidden_d", { S = ply:Nick() }), "info", 5)
			end }
		end
		if P.Setting("reports") and not (P.BridgeInfo and P.BridgeInfo.bbx) and P.OpenReport then
			items[#items + 1] = { P.L("chat_report"), "flag", function() P.OpenReport(ply:Nick()) end, true }
		end
		-- moderation actions the player can use on this person
		local acts = {}
		for _, a in ipairs(P.QuickActions and P.QuickActions(ply) or {}) do acts[#acts + 1] = { a.label, a.icon, a.fn, a.danger } end
		if #acts > 0 then items[#items + 1] = { P.L("chat_moderate"), "shield", nil, nil, acts } end
	end
	if line.sid and line.text and not line.deleted and P.MyHas("chat_delete") then
		items[#items + 1] = false
		items[#items + 1] = { P.L("chat_delete"), "trash", function()
			P.Request("chat_delete", { sid = line.sid, text = line.text })
		end, true }
	end
	-- hidden players can be shown again from any line
	if next(CB.ignored) then
		local list = {}
		for sid, name in pairs(CB.ignored) do
			list[#list + 1] = { tostring(name), "eye", function() CB.ignored[sid] = nil saveIgnored() end }
		end
		items[#items + 1] = false
		items[#items + 1] = { P.L("chat_show_again"), "eye", nil, nil, list }
	end
	UI.Popup(items)
end

-- ------------------------------------------------------------------ the frame

local LINES = {}

function LINES:Init()
	self.scroll = 0
	self.dirty = true
	self.lineRects = {}
	self.unseen = 0
end

function LINES:OnMouseWheeled(d)
	if not CB.open then return end
	self.scroll = math.max(0, self.scroll + d * S(40))
	if self.scroll == 0 then self.unseen = 0 end
	return true
end

-- small window with the link of a GIF / picture: select it, copy it or open it
function CB.ShowLink(url)
	local m = UI.Modal(P.L("chat_img_link"), S(520), S(200))
	local e = UI.Entry(m.body, "", url)
	e:Dock(TOP)
	e:SetTall(S(36))
	e.OnChange = function(s) if s:GetValue() ~= url then s:SetValue(url) s:SelectAllText() end end
	timer.Simple(0, function() if IsValid(e) then e:RequestFocus() e:SelectAllText() end end)
	local hint = UI.Label(m.body, P.L("chat_img_link_d"), "Praetor.Tiny", C.dim)
	hint:Dock(TOP)
	hint:DockMargin(0, S(8), 0, 0)
	local open = UI.Button(m.foot, P.L("chat_open_link"), "primary", "send", function() gui.OpenURL(url) m:Close() end)
	open:Dock(RIGHT)
	open:SetWide(S(170))
	local copy = UI.Button(m.foot, P.L("chat_copy_link"), "ghost", "copy", function()
		SetClipboardText(url)
		P.Toast(P.L("copied"), url, "ok", 2)
	end)
	copy:Dock(RIGHT)
	copy:SetWide(S(150))
	copy:DockMargin(0, 0, S(8), 0)
end

function LINES:LineAt(my)
	for _, r in ipairs(self.lineRects) do
		if my >= r.y and my < r.y + r.h then return r.line end
	end
end

function LINES:OnMousePressed(code)
	if not CB.open then return end
	local mx, my = self:CursorPos()
	local w, h = self:GetSize()
	-- "new messages" pill
	if self.unseen > 0 and self.scroll > 0 and my > h - S(30) and math.abs(mx - w / 2) < S(90) then
		self.scroll = 0
		self.unseen = 0
		return
	end
	if code == MOUSE_LEFT then
		for _, r in ipairs(self.linkRects or {}) do
			if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
				UI.Sound("click")
				if r.img then CB.ShowLink(r.url) else gui.OpenURL(r.url) end
				return
			end
		end
	end
	local line = self:LineAt(my)
	if not line then return end
	if code == MOUSE_RIGHT then
		lineMenu(line)
	elseif code == MOUSE_LEFT and line.url and input.IsKeyDown(KEY_LCONTROL) then
		gui.OpenURL(line.url)
	end
end

function LINES:Paint(w, h)
	local open = CB.open
	local now = RealTime()
	local width = w - S(12)
	local y = h + self.scroll
	local rects = {}
	local links = {}
	local mx, my = self:CursorPos()
	local hovering = open and self:IsHovered()
	-- hide every image first, the visible ones are shown again below
	for _, l in ipairs(lines) do if IsValid(l.html) then l.html.wantVisible = false end end
	local shown = 0
	for i = #lines, 1, -1 do
		local line = lines[i]
		local alpha = 1
		if not open then
			local age = now - line.t
			local life = line.life or SHOW_TIME
			if age > life + 1 or shown >= 9 then break end
			if age > life then alpha = 1 - (age - life) end
		end
		-- a new message slides in from the left with a little spring
		local born = math.min(1, (now - line.t) / 0.32)
		local dx = born < 1 and math.floor((1 - UI.EaseBack(born)) * -S(26)) or 0
		alpha = alpha * math.min(1, born * 2.5)
		if self.dirty or not line.layout or line.layout.width ~= width then layoutLine(line, width) end
		local L = line.layout
		y = y - L.h - S(3)
		if y + L.h < 0 then break end
		shown = shown + 1
		if y < h then
			rects[#rects + 1] = { y = y, h = L.h, line = line }
			local a = 255 * alpha
			local pushed = dx ~= 0
			if pushed then
				local m = Matrix()
				m:Translate(Vector(dx, 0, 0))
				cam.PushModelMatrix(m, true)
			end
			-- mention: soft amber band; hover: soft light band
			if line.mention then
				UI.Round(S(2), y - S(1), w - S(4), L.h + S(2), S(8), Color(C.amber.r, C.amber.g, C.amber.b, 30 * alpha))
				UI.Round(S(2), y + S(2), S(4), L.h - S(4), S(2), Color(C.amber.r, C.amber.g, C.amber.b, a))
			elseif line.staff then
				UI.Round(S(2), y - S(1), w - S(4), L.h + S(2), S(8), Color(C.crimson.r, C.crimson.g, C.crimson.b, 26 * alpha))
				UI.Round(S(2), y + S(2), S(4), L.h - S(4), S(2), Color(C.crimsonL.r, C.crimsonL.g, C.crimsonL.b, a))
			elseif line.ann and line.annCol then
				-- announcement: a band in its own colour, like the staff messages
				local ac = line.annCol
				UI.Round(S(2), y - S(1), w - S(4), L.h + S(2), S(8), Color(ac.r, ac.g, ac.b, 34 * alpha))
				UI.Round(S(2), y + S(2), S(4), L.h - S(4), S(2), Color(ac.r, ac.g, ac.b, a))
			elseif hovering and my >= y and my < y + L.h then
				UI.Round(S(2), y - S(1), w - S(4), L.h + S(2), S(8), Color(255, 255, 255, 12))
			end
			local by = y + L.top
			if line.reply then
				local ry = y + L.top / 2
				local rx = S(6) + L.stampW + S(4)
				UI.Icon("reply", rx, ry - 6, 12, Color(255, 255, 255, 120 * alpha))
				local rtext = "@" .. tostring(line.reply.n or "") .. ": " .. tostring(line.reply.q or "")
				local rf = UI.FontFor(rtext, "Praetor.ChatSmall")
				draw.SimpleText(UI.Fit(rtext, rf, w - rx - S(26)), rf, rx + S(16), ry, Color(C.muted.r, C.muted.g, C.muted.b, a * 0.9), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			if L.stampW > 0 then
				draw.SimpleText(line.stamp, "Praetor.ChatSmall", S(6), by + L.rowH / 2, Color(C.dim.r, C.dim.g, C.dim.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			if L.avW > 0 and line.annIcon and not line.sid then
				-- announcement: its icon in the place of the avatar
				local sz = L.rowH - S(6)
				local ax = S(6) + L.stampW + S(2)
				local ac = line.annCol or C.bronze
				UI.Round(ax, by + S(3), sz, sz, sz / 2, Color(ac.r, ac.g, ac.b, 80 * alpha), Color(ac.r, ac.g, ac.b, a))
				UI.Icon(line.annIcon, ax + (sz - 16) / 2, by + S(3) + (sz - 16) / 2, 16, Color(255, 255, 255, a))
			elseif L.avW > 0 then
				-- framed picture (rank colour) on every message, not only the first
				local sz = L.rowH - S(6)
				local ax = S(6) + L.stampW + S(2)
				local frame = line.frame or C.lineL
				UI.DrawAvatar(line.sid, line.ply, ax, by + S(3), sz, a, frame, line.botName or line.name)
			end
			for ri, row in ipairs(L.rows) do
				local ry = by + (ri - 1) * L.rowH
				for _, it in ipairs(row) do
					local ix = S(6) + it.x
					if it.kind == "badge" then
						UI.Badge(it.style, it.icon, "Praetor.ChatTag", ix, ry + (L.rowH - it.h) / 2, it.h, a)
					else
						local col = it.col
						if it.link then
							local lw = it.uw or it.w
							local hov = open and hovering and mx >= ix and mx <= ix + lw and my >= ry and my < ry + L.rowH
							if hov then col = LINK_HOV end
							links[#links + 1] = { x = ix, y = ry, w = lw, h = L.rowH, url = it.link }
							surface.SetDrawColor(col.r, col.g, col.b, a * (hov and 1 or 0.55))
							surface.DrawRect(ix, ry + L.rowH / 2 + fontH(it.font) / 2 - S(2), lw, 1)
						end
						draw.SimpleText(it.text, it.font, ix + 1, ry + L.rowH / 2 + 1, Color(C.ink.r, C.ink.g, C.ink.b, a * 0.9), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						draw.SimpleText(it.text, it.font, ix, ry + L.rowH / 2, Color(col.r, col.g, col.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
				end
			end
			local extra = 0
			if line.ws then
				local cx = S(6) + L.avW + L.stampW
				local cw = math.min(width - L.avW - L.stampW, S(420))
				local cy = by + #L.rows * L.rowH + S(4)
				drawWs(line.ws, cx, cy, cw, alpha)
				links[#links + 1] = { x = cx, y = cy, w = cw, h = S(WS_H) - S(8), url = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. line.ws }
				extra = S(WS_H)
			end
			if line.img and IsValid(line.html) then
				line.html:SetPos(S(6) + L.avW + L.stampW, by + #L.rows * L.rowH + S(3) + extra)
				-- a click on the picture shows its link (the picture itself lets clicks through)
				links[#links + 1] = { x = S(6) + L.avW + L.stampW, y = by + #L.rows * L.rowH + S(3) + extra, w = math.min(line.html:GetWide(), width), h = line.imgH, url = line.img, img = true }
				line.html:SetAlpha(a)
				line.html.wantVisible = y >= 0 and y + L.h <= h
			end
			if pushed then cam.PopModelMatrix() end
		end
	end
	self.dirty = false
	self.lineRects = rects
	self.linkRects = links
	local overLink = false
	if hovering then
		for _, r in ipairs(links) do
			if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then overLink = true break end
		end
	end
	if self.overLink ~= overLink then self.overLink = overLink self:SetCursor(overLink and "hand" or "arrow") end
	-- don't scroll past the oldest line
	if open and y > 0 then self.scroll = math.max(0, self.scroll - y) end
	for _, l in ipairs(lines) do
		if IsValid(l.html) and l.html:IsVisible() ~= l.html.wantVisible then l.html:SetVisible(l.html.wantVisible) end
	end
	-- scrolled up and new messages arrived
	if open and self.scroll > 0 and self.unseen > 0 then
		local t = P.L("chat_new", { V = self.unseen })
		surface.SetFont("Praetor.Tiny")
		local tw = surface.GetTextSize(t) + S(24)
		local bob = math.floor(math.abs(math.sin(RealTime() * 4)) * S(3))
		UI.Comic(w / 2 - tw / 2, h - S(30) - bob, tw, S(22), S(11), C.bronze, C.ink, S(3))
		UI.Icon("chevdown", w / 2 - tw / 2 + S(4), h - S(30) - bob + S(3), 16)
		UI.Text(t, "Praetor.Tiny", w / 2 + S(6), h - S(19) - bob, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	elseif self.scroll == 0 then
		self.unseen = 0
	end
end

vgui.Register("PraetorChatLines", LINES, "DPanel")

-- DarkRP chat commands this player can use: { name = description }
local function rpCommands()
	if not (DarkRP and DarkRP.getChatCommands) then return {} end
	local out = {}
	local me = LocalPlayer()
	for name, c in pairs(DarkRP.getChatCommands() or {}) do
		local ok = true
		if isfunction(c.condition) then
			local fine, res = pcall(c.condition, me)
			ok = fine and res ~= false
		end
		if ok and isstring(name) then out[name:lower()] = isstring(c.description) and c.description or "" end
	end
	return out
end

-- Praetor words that open things and are not commands
local function praetorExtras()
	local t = { menu = "h_menu" }
	if P.Setting("reports") then t.report = "h_report" end
	return t
end

local function suggestions(text)
	local first = text:sub(1, 1)
	if first ~= "!" and first ~= "/" and first ~= P.Setting("prefix_silent") then return {} end
	local body = text:sub(2)
	local name = (body:match("^(%S*)") or ""):lower()
	local rpc = first == "/" and rpCommands() or {}
	if body:find("%s") then
		-- already typing arguments: show the usage of that command
		local c = P.ServerCmds[name]
		if c and P.CanRunId(c.id) then return { { id = c.id, usage = true } } end
		if rpc[name] then return { { id = name, rp = rpc[name] } } end
		return {}
	end
	local out, ids = {}, {}
	for id in pairs(P.ServerCmds) do
		if id:sub(1, #name) == name and P.CanRunId(id) and not P.ServerCmds[id].hid then ids[#ids + 1] = { id = id } end
	end
	for id, key in pairs(praetorExtras()) do
		if not P.ServerCmds[id] and id:sub(1, #name) == name then ids[#ids + 1] = { id = id, extra = key } end
	end
	for id, desc in pairs(rpc) do
		if not P.ServerCmds[id] and id:sub(1, #name) == name then ids[#ids + 1] = { id = id, rp = desc } end
	end
	table.sort(ids, function(a, b)
		-- an exact match first, then Praetor before DarkRP, then alphabetical
		if (a.id == name) ~= (b.id == name) then return a.id == name end
		if (a.rp ~= nil) ~= (b.rp ~= nil) then return a.rp == nil end
		return a.id < b.id
	end)
	for i = 1, math.min(#ids, 8) do out[i] = ids[i] end
	return out
end

-- @name suggestions: online players whose name starts with what was typed
local function mentionSuggestions(text)
	local word = text:match("@(%S*)$")
	if not word then return nil end
	word = word:lower()
	local out = {}
	for _, p in ipairs(player.GetAll()) do
		if p ~= LocalPlayer() and p:Nick():lower():sub(1, #word) == word then out[#out + 1] = { ply = p } end
		if #out >= 6 then break end
	end
	return out
end

-- "!kick jo" / "!goto ": online players for a player argument of a command
local function playerArgSuggestions(text)
	local pre = text:sub(1, 1)
	if pre ~= "!" and pre ~= "/" and pre ~= P.Setting("prefix_silent") then return nil end
	local body = text:sub(2)
	local parts = {}
	for w in body:gmatch("%S+") do parts[#parts + 1] = w end
	if #parts == 0 then return nil end
	local endsSpace = body:sub(-1) == " "
	local def = P.ServerCmds[parts[1]:lower()]
	if not def or not def.args then return nil end
	local idx = endsSpace and #parts or (#parts - 1)
	local a = idx >= 1 and def.args[idx]
	if not a or (a.t ~= "player" and a.t ~= "offline") then return nil end
	-- same matching as the server: no accents or symbols, names that start with
	-- the text first (so the first row is who the command will hit)
	local cur = P.FoldName(endsSpace and "" or parts[#parts])
	local starts, has = {}, {}
	for _, p in ipairs(player.GetAll()) do
		local n = P.FoldName(p:Nick())
		if cur == "" or n:sub(1, #cur) == cur then starts[#starts + 1] = { ply = p, arg = true }
		elseif n:find(cur, 1, true) then has[#has + 1] = { ply = p, arg = true } end
	end
	local out = starts
	for _, it in ipairs(has) do out[#out + 1] = it end
	while #out > 6 do table.remove(out) end
	return #out > 0 and out or nil
end

local function usage(id)
	local c = P.ServerCmds[id]
	if not c then return id end
	local parts = {}
	parts[1] = id
	for _, a in ipairs(c.args or {}) do
		local h = P.L("arg_" .. (a.h or a.t), nil, a.h or a.t)
		parts[#parts + 1] = a.o and ("[" .. h .. "]") or ("<" .. h .. ">")
	end
	return table.concat(parts, " ")
end

local sentHistory = {}

-- ------------------------------------------------------------------ voice button
-- Lua can't read the microphone (no speech to text in Garry's Mod), but the
-- button opens / closes the voice chat like the push-to-talk key.
local voiceOn = false
local function setVoice(on)
	voiceOn = on
	if permissions and permissions.EnableVoiceChat then
		permissions.EnableVoiceChat(on)
	else
		RunConsoleCommand(on and "+voicerecord" or "-voicerecord")
	end
end

-- ------------------------------------------------------------------ sending

local function send(text)
	text = P.Trim(text)
	if text == "" then return end
	table.insert(sentHistory, 1, text)
	if #sentHistory > 30 then sentHistory[31] = nil end
	local r = CB.reply
	local silent = P.Setting("prefix_silent") or ""
	local isCommand = text:sub(1, 1) == "!" or text:sub(1, 1) == "/" or (silent ~= "" and text:sub(1, #silent) == silent)
	local ch = CB.chan or "all"
	if isCommand then
		RunConsoleCommand("say", text)
	elseif ch == "staff" or ch == "local" then
		P.Request("chat_say", { text = text, ch = ch })
	elseif r then
		P.Request("chat_say", { text = text, team = ch == "team" or nil, to = r.sid, n = r.name, q = r.q })
	else
		RunConsoleCommand(ch == "team" and "say_team" or "say", text)
	end
	CB.reply = nil
end

-- the channels of the tabs: who gets the message
local CHANNELS = {
	{ id = "all", key = "chat_tab_all", icon = "players", col = function() return C.bronzeL end, ph = "chat_ph_all" },
	{ id = "team", key = "chat_tab_team", icon = "flag", col = function() return C.laurel end, ph = "chat_ph_team", tip = "chat_tip_team" },
	{ id = "local", key = "chat_tab_local", icon = "bubble", col = function() return C.sky end, ph = "chat_ph_local", tip = "chat_tip_local",
		can = function() return (P.Setting("chat_local_dist") or 0) > 0 end },
	{ id = "staff", key = "chat_tab_staff", icon = "shield", col = function() return C.crimsonL end, ph = "chat_ph_staff", tip = "chat_tip_staff",
		can = function() return P.MyHas("adminchat") end },
}
local function chanDef(id)
	for _, c in ipairs(CHANNELS) do if c.id == id then return c end end
	return CHANNELS[1]
end
local function chanUsable(c) return not c.can or c.can() end
function CB.SetChannel(id)
	local c = chanDef(id)
	if not chanUsable(c) then c = CHANNELS[1] end
	CB.chan = c.id
	CB.team = c.id == "team"
	if IsValid(CB.frame) and IsValid(CB.frame.entry) then CB.frame.entry:SetPlaceholderText(P.L(c.ph)) end
end

function CB.SetReply(line)
	if not line or not line.name then return end
	local q = tostring(line.text or "")
	CB.reply = { sid = line.sid or "0", name = line.name, q = P.Str and P.Str(q, 80) or q:sub(1, 80) }
	if not CB.open then CB.Open(CB.team) end
	if IsValid(CB.frame) then CB.frame.entry:RequestFocus() end
end

function CB.Insert(text)
	if not CB.open then CB.Open(CB.team) end
	local e = IsValid(CB.frame) and CB.frame.entry
	if not IsValid(e) then return end
	local cur = e:GetValue()
	if cur ~= "" and not cur:match("%s$") then cur = cur .. " " end
	e:SetText(cur .. text)
	e:SetCaretPos(#e:GetValue())
	e:RequestFocus()
end

local function build()
	-- A top-level panel (NOT parented to the HUD): HUD children can't take
	-- keyboard focus, which in 1.0.0 left the game stuck with the cursor out and
	-- typing going nowhere. Input is only enabled while the chat is open.
	local f = vgui.Create("EditablePanel")
	CB.frame = f
	f:SetMouseInputEnabled(false)
	f:SetKeyboardInputEnabled(false)
	local function size()
		local w = math.min(S(640), ScrW() - S(40))
		local h = math.min(S(360), math.floor(ScrH() * 0.44))
		f:SetSize(w, h)
		f:SetPos(S(22), ScrH() - h - math.floor(ScrH() * 0.17))
	end
	size()
	local OFF = S(5)
	f.Paint = function(s, w, h)
		if not CB.open then return end
		-- fades and grows in quickly when the chat opens
		local k = math.min(1, (RealTime() - (CB.openAt or 0)) / 0.16)
		w, h = w - OFF, h - OFF
		local bw = UI.BW()
		UI.Comic(0, 0, w, h, S(14), Color(C.bg.r, C.bg.g, C.bg.b, 196 * k), Color(C.lineL.r, C.lineL.g, C.lineL.b, 255 * k), OFF, 190 * k)
		-- header strip with the channel tabs on the left
		draw.RoundedBoxEx(S(12), bw, bw, w - bw * 2, S(40) - bw, Color(C.panel.r, C.panel.g, C.panel.b, 214 * k), true, true, false, false)
		UI.Rect(bw, S(40), w - bw * 2, bw, Color(C.line.r, C.line.g, C.line.b, 255 * k))
		-- players online: a chip with a breathing green dot
		local txt = #player.GetAll() .. " " .. P.L("online")
		surface.SetFont("Praetor.Tiny")
		local tw = surface.GetTextSize(txt) + S(30)
		local cx = w - S(10) - tw
		UI.Round(cx, S(9), tw, S(22), S(11), Color(C.panel2.r, C.panel2.g, C.panel2.b, 255 * k), Color(C.line.r, C.line.g, C.line.b, 255 * k))
		local pulse = (math.sin(RealTime() * 3) + 1) / 2
		local d = S(8)
		UI.Round(cx + S(10) - S(3) * pulse, S(20) - d / 2 - S(3) * pulse, d + S(6) * pulse, d + S(6) * pulse, (d + S(6) * pulse) / 2, Color(C.laurel.r, C.laurel.g, C.laurel.b, 70 * (1 - pulse) * k))
		UI.Round(cx + S(10), S(20) - d / 2, d, d, d / 2, Color(C.laurel.r, C.laurel.g, C.laurel.b, 255 * k))
		UI.Text(txt, "Praetor.Tiny", cx + S(22), S(20), Color(C.text.r, C.text.g, C.text.b, 255 * k), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	-- channel tabs: All / Team / Nearby / Staff (the last two only when they can be used)
	local tabs = vgui.Create("DPanel", f)
	tabs:SetPos(S(9), S(8))
	tabs:SetSize(S(440), S(26))
	tabs.Paint = nil
	tabs.btns = {}
	for _, def in ipairs(CHANNELS) do
		local b = vgui.Create("DButton", tabs)
		b:SetText("")
		b:Dock(LEFT)
		b:DockMargin(0, 0, S(4), 0)
		surface.SetFont("Praetor.SmallB")
		b:SetWide(S(42) + surface.GetTextSize(P.L(def.key)))
		if def.tip then b:SetTooltip(P.L(def.tip, { V = P.Setting("chat_local_dist") or 0 })) end
		b.anim = 0
		b.OnCursorEntered = function() UI.Sound("hover") end
		b.Paint = function(s, w, h)
			local on = (CB.chan or "all") == def.id
			local col = def.col()
			s.anim = UI.Lerp(s.anim, on and 1 or 0, 14)
			local bw, bh = w - S(2), h - S(2)
			if s.anim > 0.02 then
				local grow = math.floor((1 - s.anim) * S(8))
				UI.Round(grow + S(2), S(2), bw - grow * 2, bh, bh / 2, Color(C.ink.r, C.ink.g, C.ink.b, 210 * s.anim))
				UI.Round(grow, 0, bw - grow * 2, bh, bh / 2, Color(col.r, col.g, col.b, 255 * s.anim), Color(C.ink.r, C.ink.g, C.ink.b, 255 * s.anim))
			elseif s:IsHovered() then
				UI.Round(0, 0, bw, bh, bh / 2, Color(255, 255, 255, 14))
			end
			UI.Icon(def.icon, S(9), (bh - 16) / 2, 16, (on or s:IsHovered()) and color_white or Color(255, 255, 255, 160))
			UI.Text(P.L(def.key), "Praetor.SmallB", S(30), bh / 2, on and C.ink or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function()
			CB.SetChannel(def.id)
			UI.Sound("click")
			if IsValid(f.entry) then f.entry:RequestFocus() end
		end
		b.def = def
		tabs.btns[#tabs.btns + 1] = b
	end
	-- hides the tabs this player can't use (staff rank lost, nearby chat off...)
	tabs.Refresh = function()
		for _, b in ipairs(tabs.btns) do
			local want = chanUsable(b.def)
			if b:IsVisible() ~= want then b:SetVisible(want) tabs:InvalidateLayout() end
		end
	end
	f.tabs = tabs

	f.lines = vgui.Create("PraetorChatLines", f)
	f.lines:Dock(FILL)
	f.lines:DockMargin(S(4), S(46), S(4) + OFF, S(4))

	local bottom = vgui.Create("DPanel", f)
	bottom:Dock(BOTTOM)
	bottom:SetTall(S(40))
	bottom:DockMargin(S(8), 0, S(8) + OFF, S(8) + OFF)
	bottom.Paint = nil
	f.bottom = bottom

	-- "replying to" bar above the input
	local replyBar = vgui.Create("DPanel", f)
	replyBar:Dock(BOTTOM)
	replyBar:SetTall(S(26))
	replyBar:DockMargin(S(8), 0, S(8) + OFF, S(4))
	replyBar.Paint = function(_, w, h)
		local r = CB.reply
		if not r then return end
		UI.Round(0, 0, w, h, h / 2, Color(C.bronze.r, C.bronze.g, C.bronze.b, 40), C.bronze)
		UI.Icon("reply", S(10), (h - 16) / 2, 16)
		local t = P.L("chat_replying", { S = r.name }) .. "  " .. r.q
		local rf = UI.FontFor(t, "Praetor.Small")
		UI.Text(UI.Fit(t, rf, w - S(70)), rf, S(32), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local cancelReply = vgui.Create("DButton", replyBar)
	cancelReply:SetText("")
	cancelReply:Dock(RIGHT)
	cancelReply:SetWide(S(26))
	cancelReply.Paint = function(s, w, h)
		local col = s:IsHovered() and C.crimsonL or C.muted
		draw.NoTexture()
		surface.SetDrawColor(col)
		surface.DrawTexturedRectRotated(w / 2, h / 2, S(10), 2, 45)
		surface.DrawTexturedRectRotated(w / 2, h / 2, S(10), 2, -45)
	end
	cancelReply.DoClick = function() CB.reply = nil if IsValid(f.entry) then f.entry:RequestFocus() end end
	replyBar:SetVisible(false)
	f.replyBar = replyBar

	-- send button (drawn by hand: centred by the arrow's shape, not by a 16x16 box)
	local sendB = vgui.Create("DButton", bottom)
	sendB:SetText("")
	sendB.DoClick = function() if IsValid(f.entry) then f.entry:OnEnter() end end
	sendB.Paint = function(s, w, h)
		local col = chanDef(CB.chan).col()
		if s:IsHovered() then col = Color(math.min(255, col.r + 25), math.min(255, col.g + 25), math.min(255, col.b + 25)) end
		local off = S(3)
		local press = s:IsDown() and off or (s:IsHovered() and -1 or 0)
		w, h = w - off, h - off
		UI.Round(off, off, w, h, S(12), C.ink)
		UI.Round(press, press, w, h, S(12), col, C.ink)
		local sz = math.floor(h * 0.44)
		-- the eye sees the middle of an arrow 1/3 from its back, so it moves forward a little
		local cx, cy = w / 2 + sz * 0.1 + press, h / 2 + press
		draw.NoTexture()
		surface.SetDrawColor(C.ink)
		surface.DrawPoly({
			{ x = cx - sz * 0.5, y = cy - sz * 0.5 },
			{ x = cx + sz * 0.55, y = cy },
			{ x = cx - sz * 0.22, y = cy },
		})
		surface.DrawPoly({
			{ x = cx - sz * 0.22, y = cy },
			{ x = cx + sz * 0.55, y = cy },
			{ x = cx - sz * 0.5, y = cy + sz * 0.5 },
		})
	end
	sendB:Dock(RIGHT)
	sendB:SetWide(S(46))
	sendB:DockMargin(S(6), 0, 0, 0)
	sendB:SetTooltip(P.L("chat_send"))

	-- microphone (opens the voice chat while it is on)
	local mic = vgui.Create("DButton", bottom)
	mic:SetText("")
	mic:Dock(RIGHT)
	mic:SetWide(S(46))
	mic:DockMargin(S(6), 0, 0, 0)
	mic:SetTooltip(P.L("chat_mic_tip"))
	mic.Paint = function(s, w, h)
		local talking = IsValid(LocalPlayer()) and LocalPlayer():IsSpeaking()
		local on = voiceOn or talking
		local vol = talking and math.Clamp(LocalPlayer():VoiceVolume() * 3, 0, 1) or 0
		local fill = on and P.LerpColor(vol, Color(C.laurel.r * 0.6, C.laurel.g * 0.6, C.laurel.b * 0.6), C.laurel) or (s:IsHovered() and C.hover or C.panel2)
		local off = S(3)
		local press = s:IsDown() and off or 0
		w, h = w - off, h - off
		UI.Round(off, off, w, h, S(12), C.ink)
		UI.Round(press, press, w, h, S(12), fill, on and C.ink or (s:IsHovered() and C.lineL or C.line))
		-- the mic grows with the voice while talking
		w, h = w + press * 2, h + press * 2
		-- microphone drawn by hand in a light colour, so it reads on the dark button
		local ic = on and C.ink or ((s:IsHovered()) and color_white or Color(214, 220, 232))
		local u = math.max(1, math.floor(h / 18))
		local cx = math.floor(w / 2)
		local capW, capH = u * 6, u * 9
		local total = capH + u * 5
		local top = math.floor(h / 2 - total / 2)
		UI.Round(cx - capW / 2, top, capW, capH, math.floor(capW / 2), ic)
		surface.SetDrawColor(ic)
		local sw = u * 10
		local sy = top + u * 4
		surface.DrawRect(cx - sw / 2, sy, u, u * 3)
		surface.DrawRect(cx + sw / 2 - u, sy, u, u * 3)
		surface.DrawRect(cx - sw / 2 + u, sy + u * 3, u, u)
		surface.DrawRect(cx + sw / 2 - u * 2, sy + u * 3, u, u)
		surface.DrawRect(cx - sw / 2 + u * 2, sy + u * 4, sw - u * 4, u)
		surface.DrawRect(cx - math.floor(u / 2), sy + u * 5, u, u * 2)
		surface.DrawRect(cx - u * 2, sy + u * 7, u * 4, u)
	end
	mic.DoClick = function()
		-- the first time, GMod asks the player to allow the microphone in a window
		-- of its own: the chat closes so that window can be clicked
		if not voiceOn and permissions and permissions.IsGranted and not permissions.IsGranted("voicerecord") then
			CB.Close()
			permissions.EnableVoiceChat(true)
			P.Toast(P.L("chat_mic"), P.L("chat_mic_allow"), "info", 10)
			-- once allowed the mic goes off again: it is only on while the chat is open
			timer.Create("Praetor.MicAllow", 0.5, 120, function()
				if permissions.IsGranted("voicerecord") then
					timer.Remove("Praetor.MicAllow")
					if not CB.open then permissions.EnableVoiceChat(false) end
					P.Toast(P.L("chat_mic"), P.L("chat_mic_ok"), "ok", 6)
				end
			end)
			return
		end
		setVoice(not voiceOn)
		UI.Sound("click")
		if IsValid(f.entry) then f.entry:RequestFocus() end
	end

	-- the box: a frame with the channel icon on the left and the text field after
	-- it (the field used to run under the icon, so the first letters were hidden)
	local field = vgui.Create("DPanel", bottom)
	field:Dock(FILL)
	local entry = UI.Entry(field, P.L("chat_ph_all"), "")
	entry:Dock(FILL)
	field.Paint = function(s, w, h)
		local r = math.min(h / 2, S(12))
		UI.Round(0, 0, w, h, r, Color(C.bronze.r, C.bronze.g, C.bronze.b, 60))
		UI.Round(0, 0, w, h, r, Color(18, 13, 32), C.bronze)
		-- the channel icon on a small disc of its colour
		local col = chanDef(CB.chan).col()
		local d = h - S(14)
		UI.Round(S(7), S(7), d, d, d / 2, Color(col.r, col.g, col.b, 255), C.ink)
		UI.Icon(chanDef(CB.chan).icon, S(7) + (d - 16) / 2, S(7) + (d - 16) / 2, 16)
	end
	field.PerformLayout = function(s, w, h)
		entry:DockMargin(h - S(14) + S(12), 0, 0, 0)
	end
	field.OnMousePressed = function() if IsValid(entry) then entry:RequestFocus() end end
	-- the hint stays while typing nothing (it used to blink when the mouse was held
	-- on the chat); the frame is drawn by `field`, the entry only draws the text
	entry.keepPlaceholder = true
	entry.phX = S(2)
	entry.Paint = function(s, w, h)
		s:DrawTextEntryText(C.ivory, Color(142, 98, 255, 110), C.bronzeL)
		if s:GetText() == "" then
			draw.SimpleText(s:GetPlaceholderText() or "", s:GetFont(), S(2), h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	entry.PerformLayout = function(s) s:SetTextInset(S(2), 0) end
	entry:SetFont("Praetor.Chat")
	entry:SetHistoryEnabled(false)
	f.entry = entry
	entry.histPos = 0
	f.clickables = { tabs, bottom, replyBar, cancelReply, sendB, mic, field, entry, f.lines }
	for _, b in ipairs(tabs.btns) do f.clickables[#f.clickables + 1] = b end
	-- characters left, shown when close to the limit
	entry.PaintOver = function(s, w, h)
		local n = utf8.len(s:GetValue()) or 0
		if n > MAX_CHARS - 30 then
			UI.Text(tostring(MAX_CHARS - n), "Praetor.Tiny", w - S(8), h / 2, n >= MAX_CHARS and C.crimsonL or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	entry.OnTextChanged = function(s)
		local t = s:GetValue()
		if utf8.len(t) and utf8.len(t) > MAX_CHARS then
			local cut = P.Chars(t)
			s:SetText(table.concat(cut, "", 1, MAX_CHARS))
			s:SetCaretPos(MAX_CHARS)
		end
		local v = s:GetValue()
		CB.mentions = mentionSuggestions(v) or playerArgSuggestions(v)
		CB.sugg = CB.mentions and {} or suggestions(v)
		hook.Run("ChatTextChanged", v)
	end
	entry.OnEnter = function(s)
		send(s:GetValue())
		CB.Close()
	end
	entry.OnKeyCodeTyped = function(s, key)
		if key == KEY_ESCAPE then
			if CB.reply then CB.reply = nil return true end
			CB.Close()
			gui.HideGameUI()
			return true
		elseif key == KEY_ENTER or key == KEY_PAD_ENTER then
			s:OnEnter()
			return true
		elseif key == KEY_TAB then
			local m = CB.mentions
			local sugg = CB.sugg or {}
			if m and m[1] and IsValid(m[1].ply) and m[1].arg then
				-- player argument of a command: names with spaces go in quotes
				local nick = m[1].ply:Nick()
				if nick:find("%s") then nick = "\"" .. nick:gsub("\"", "") .. "\"" end
				local v = s:GetValue():gsub("%S*$", "", 1) .. nick .. " "
				s:SetText(v)
				s:SetCaretPos(#v)
				CB.mentions = nil
			elseif m and m[1] and IsValid(m[1].ply) then
				local v = s:GetValue():gsub("@%S*$", "@" .. m[1].ply:Nick() .. " ")
				s:SetText(v)
				s:SetCaretPos(#v)
				CB.mentions = nil
			elseif sugg[1] and not sugg[1].usage then
				local first = s:GetValue():sub(1, 1)
				s:SetText(first .. sugg[1].id .. " ")
				s:SetCaretPos(#s:GetValue())
			else
				local res = hook.Run("OnChatTab", s:GetValue())
				if isstring(res) then s:SetText(res) s:SetCaretPos(#res) end
			end
			timer.Simple(0, function() if IsValid(s) then s:RequestFocus() end end)
			return true
		elseif key == KEY_UP or key == KEY_DOWN then
			s.histPos = math.Clamp(s.histPos + (key == KEY_UP and 1 or -1), 0, #sentHistory)
			local t = s.histPos > 0 and sentHistory[s.histPos] or ""
			s:SetText(t)
			s:SetCaretPos(#t)
			return true
		end
	end

	-- command / @name suggestions above the input
	local sug = vgui.Create("DPanel", f)
	sug:SetMouseInputEnabled(false)
	f.sug = sug
	sug.Paint = function(s, w, h)
		if not CB.open then return end
		local rowH = S(26)
		local m = CB.mentions
		if m and #m > 0 then
			-- players: framed picture, name and rank badge
			local pH = S(32)
			local total = #m * pH + S(8)
			local y0 = h - total
			UI.Comic(0, y0, w - S(3), total - S(3), S(10), Color(C.panel.r, C.panel.g, C.panel.b, 250), C.lineL, S(3))
			for i, it in ipairs(m) do
				if IsValid(it.ply) then
					local y = y0 + S(4) + (i - 1) * pH
					if i == 1 then UI.Round(S(4), y, w - S(11), pH, pH / 2, Color(C.bronze.r, C.bronze.g, C.bronze.b, 50), C.bronze) end
					local sz = pH - S(8)
					UI.DrawAvatar(it.ply:SteamID64(), it.ply, S(10), y + S(4), sz, 255, UI.AvatarFrame(it.ply), it.ply:Nick())
					local style, icon = UI.PlayerRankStyle(it.ply)
					local bw = UI.BadgeWidth and UI.BadgeWidth(style, icon, "Praetor.Tiny", S(18)) or 0
					if bw > 0 then UI.Badge(style, icon, "Praetor.Tiny", w - bw - S(10), y + (pH - S(18)) / 2, S(18)) end
					local x = S(10) + sz + S(10)
					UI.Name((it.arg and "" or "@") .. it.ply:Nick(), "Praetor.SmallB", x, y + pH / 2, i == 1 and C.bronzeL or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, w - x - bw - S(20))
				end
			end
			if m[1] then UI.Text(P.L("chat_tab_hint"), "Praetor.Tiny", w - S(10), y0 - S(10), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
			return
		end
		local list = CB.sugg or {}
		if #list == 0 then return end
		local total = #list * rowH + S(8)
		local y0 = h - total
		UI.Comic(0, y0, w - S(3), total - S(3), S(10), Color(C.panel.r, C.panel.g, C.panel.b, 250), C.lineL, S(3))
		for i, it in ipairs(list) do
			local c = P.ServerCmds[it.id]
			local y = y0 + S(4) + (i - 1) * rowH
			if i == 1 then UI.Round(S(4), y, w - S(11), rowH, rowH / 2, Color(C.bronze.r, C.bronze.g, C.bronze.b, 50), C.bronze) end
			local label = (it.rp or it.extra) and it.id or usage(it.id)
			UI.Text(label, "Praetor.Small", S(10), y + rowH / 2, i == 1 and C.bronzeL or (it.rp and C.laurel or C.text), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			local help = ""
			if it.rp then help = it.rp ~= "" and it.rp or "DarkRP"
			elseif it.extra then help = P.L(it.extra)
			elseif c then help = P.L("h_" .. it.id, nil, c.help or "") end
			if help ~= "" then UI.Text(UI.Fit(help, "Praetor.Tiny", w * 0.45), "Praetor.Tiny", w - S(10), y + rowH / 2, C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
		end
	end
	f.PerformLayout = function(s, w, h)
		sug:SetPos(S(8), S(42))
		sug:SetSize(w - S(16) - OFF, h - S(42) - S(54) - OFF - (CB.reply and S(30) or 0))
	end
	f.Think = function(s)
		-- the reply bar shows up / hides with CB.reply
		local want = CB.open and CB.reply ~= nil
		if replyBar:IsVisible() ~= want then
			replyBar:SetVisible(want)
			s:InvalidateLayout()
		end
		tabs:SetVisible(CB.open == true)
		if CB.open then
			if tabs.Refresh then tabs.Refresh() end
			if not chanUsable(chanDef(CB.chan)) then CB.SetChannel("all") end
			-- the text box keeps the keyboard: a click on the messages, the
			-- background or a tab gives it back (menus and other windows keep theirs)
			-- (right away: waiting for the mouse button to be released made the box
			-- lose and get back the focus while the click was held)
			local kf = vgui.GetKeyboardFocus()
			if kf ~= s.entry and (not IsValid(kf) or CB.Inside(kf)) then
				s.entry:RequestFocus()
			end
			-- the tabs and the input bar fade in with the window
			local k = math.min(1, (RealTime() - (CB.openAt or 0)) / 0.2)
			if k < 1 or s.bottom:GetAlpha() < 255 then
				s.bottom:SetAlpha(255 * k)
				tabs:SetAlpha(255 * k)
			end
		end
	end
	f.OnScreenSizeChanged = size
	f.OnMousePressed = function() if IsValid(f.entry) then f.entry:RequestFocus() end end

	f:SetVisible(true)
	bottom:SetVisible(false)
	tabs:SetVisible(false)
	return f
end

-- is this panel the chat box or something inside it?
function CB.Inside(pnl)
	local f = CB.frame
	local n = 0
	while IsValid(pnl) and n < 40 do
		if pnl == f then return true end
		pnl = pnl:GetParent()
		n = n + 1
	end
	return false
end

function CB.Open(isTeam)
	if not active() then return end
	if not IsValid(CB.frame) then build() end
	local f = CB.frame
	if not CB.open then CB.openAt = RealTime() end
	CB.open = true
	-- the key picks the channel (say_team = Team); someone talking in the staff
	-- or nearby tab stays there when the chat is opened with the normal key
	if isTeam == true then CB.SetChannel("team")
	elseif CB.chan == "team" or not CB.chan then CB.SetChannel("all")
	else CB.SetChannel(CB.chan) end
	P.ChatIsOpen = true
	f:SetVisible(true)
	f:MakePopup()
	f:MoveToFront()
	f:SetMouseInputEnabled(true)
	f:SetKeyboardInputEnabled(true)
	-- the buttons get the mouse back one by one (closing the chat turns it off
	-- for the whole box; before, the tabs, send and mic stayed dead after that)
	for _, c in ipairs(f.clickables or {}) do if IsValid(c) then c:SetMouseInputEnabled(true) end end
	-- only the text box takes the keyboard: a click (or a held click) on the
	-- messages, a tab or a button no longer steals its focus
	for _, c in ipairs(f.clickables or {}) do if IsValid(c) and c ~= f.entry and c ~= f.bottom then c:SetKeyboardInputEnabled(false) end end
	f.entry:SetKeyboardInputEnabled(true)
	-- SetMouseInputEnabled reaches every child. The suggestion layer (on top of
	-- the messages) and the GIF pictures must stay click-through: before, a click
	-- on the messages landed on them and the text box lost the keyboard for good
	if IsValid(f.sug) then f.sug:SetMouseInputEnabled(false) end
	for _, l in ipairs(lines) do if IsValid(l.html) then l.html:SetMouseInputEnabled(false) end end
	f.bottom:SetVisible(true)
	f.entry:SetText("")
	f.entry.histPos = 0
	f.entry:RequestFocus()
	-- the bind that opened the chat is still being processed this frame; ask again
	timer.Simple(0, function()
		if CB.open and IsValid(f) and IsValid(f.entry) then f.entry:RequestFocus() end
	end)
	f.lines.scroll = 0
	f.lines.unseen = 0
	CB.sugg = {}
	CB.mentions = nil
	hook.Run("StartChat", CB.chan == "team")
end

function CB.Close()
	if not IsValid(CB.frame) then return end
	local f = CB.frame
	CB.open = false
	P.ChatIsOpen = false
	CB.sugg = {}
	CB.mentions = nil
	CB.reply = nil
	-- the mic button only stays on while the chat is open
	if voiceOn then setVoice(false) end
	f.bottom:SetVisible(false)
	f:SetMouseInputEnabled(false)
	f:SetKeyboardInputEnabled(false)
	f.lines.scroll = 0
	f:KillFocus()
	gui.EnableScreenClicker(false)
	CloseDermaMenus()
	hook.Run("FinishChat")
	hook.Run("ChatTextChanged", "")
end

function CB.IsOpen() return CB.open == true end

-- ------------------------------------------------------------------ engine hooks

hook.Add("PlayerBindPress", "Praetor.ChatBox", function(_, bind, pressed)
	if not pressed or not active() then return end
	bind = bind:lower()
	if bind:find("messagemode2", 1, true) then CB.Open(true) return true end
	if bind:find("messagemode", 1, true) then CB.Open(false) return true end
end)

-- a click on the empty screen (outside the chat and any other window) closes it,
-- like the default chat
local function clickedOutside(pnl)
	if not CB.open then return end
	if IsValid(pnl) and pnl ~= vgui.GetWorldPanel() and pnl ~= GetHUDPanel() then return end
	CB.Close()
end
hook.Add("VGUIMousePressed", "Praetor.ChatBox", function(pnl) clickedOutside(pnl) end)
hook.Add("GUIMousePressed", "Praetor.ChatBox", function() clickedOutside(nil) end)

-- Esc closes the chat and does not open the pause menu
hook.Add("OnPauseMenuShow", "Praetor.ChatBox", function()
	if CB.open then
		CB.Close()
		return false
	end
end)

hook.Add("HUDShouldDraw", "Praetor.ChatBox", function(name)
	if name == "CHudChat" and active() then return false end
end)

hook.Add("Think", "Praetor.ChatBoxBuild", function()
	if active() and not IsValid(CB.frame) and IsValid(LocalPlayer()) then build() end
	if IsValid(CB.frame) then
		-- Esc closes the chat without opening the pause menu
		if CB.open and input.IsKeyDown(KEY_ESCAPE) then
			CB.Close()
			gui.HideGameUI()
		end
		if CB.open and not active() then CB.Close() end
		-- hidden behind the pause menu (it is a top-level panel now)
		local want = active() and not gui.IsGameUIVisible()
		if CB.frame:IsVisible() ~= want then CB.frame:SetVisible(want) end
	end
end)

-- reloading the file (lua_openscript / autorefresh) replaces the old box
if IsValid(CB.frame) then CB.frame:Remove() CB.frame = nil CB.open = false end

hook.Add("Praetor.FontsBuilt", "Praetor.ChatBox", function()
	for _, l in ipairs(lines) do l.layout = nil end
	if IsValid(CB.frame) then CB.frame.lines.dirty = true end
end)

hook.Add("OnScreenSizeChanged", "Praetor.ChatBox", function()
	if IsValid(CB.frame) then CB.frame:Remove() end
	for _, l in ipairs(lines) do l.html = nil l.layout = nil l.img = nil end
	imagePanels = {}
	CB.open = false
end)

-- other addons that move things around the chat ask for its position
CB.OrigGetPos = CB.OrigGetPos or chat.GetChatBoxPos
CB.OrigGetSize = CB.OrigGetSize or chat.GetChatBoxSize
CB.OrigOpen = CB.OrigOpen or chat.Open
CB.OrigClose = CB.OrigClose or chat.Close

function chat.GetChatBoxPos()
	if active() and IsValid(CB.frame) then return CB.frame:GetPos() end
	return CB.OrigGetPos()
end

function chat.GetChatBoxSize()
	if active() and IsValid(CB.frame) then return CB.frame:GetSize() end
	return CB.OrigGetSize()
end

function chat.Open(mode)
	if active() then CB.Open(mode ~= 1) return end
	return CB.OrigOpen(mode)
end

function chat.Close()
	if active() then CB.Close() return end
	return CB.OrigClose()
end
