-- Praetor: screenshots of a player's screen, client side.
--  * when the server asks, the next frame is captured as a JPEG and sent in
--    pieces (nothing shows on this player's screen);
--  * the staff member gets the picture in a viewer: fit or 1:1 (move the mouse
--    to look around), who / when / resolution, and a warning when the game was
--    not the active window;
--  * "Screenshots" tab: the last ones taken on the server, with search.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local OP_ASK, OP_HEAD, OP_PART, OP_SEND = 1, 2, 3, 4
local CHUNK = 48000
local capture = render.Capture -- kept at load, before anything can swap it

-- ------------------------------------------------------------------ being captured

local function sendShot(id, data)
	local n = math.ceil(#data / CHUNK)
	net.Start("praetor_shot")
	net.WriteUInt(OP_HEAD, 3)
	net.WriteUInt(id, 32)
	net.WriteUInt(n, 8)
	net.WriteUInt(#data, 24)
	net.WriteUInt(math.min(ScrW(), 65535), 16)
	net.WriteUInt(math.min(ScrH(), 65535), 16)
	net.WriteBool(system.HasFocus())
	net.SendToServer()
	local i = 0
	timer.Create("Praetor.ShotUp." .. id, 0.08, n, function()
		i = i + 1
		local part = data:sub((i - 1) * CHUNK + 1, i * CHUNK)
		net.Start("praetor_shot")
		net.WriteUInt(OP_PART, 3)
		net.WriteUInt(id, 32)
		net.WriteUInt(i, 8)
		net.WriteUInt(#part, 16)
		net.WriteData(part, #part)
		net.SendToServer()
	end)
end

P.SendShot = sendShot

-- captures the next frame and gives the JPEG to cb (used by the report window,
-- before it opens, so the picture shows the game and not the window)
function P.CaptureFrame(cb, q)
	hook.Add("PostRender", "Praetor.ShotSelf", function()
		hook.Remove("PostRender", "Praetor.ShotSelf")
		local ok, data = pcall(capture, { format = "jpeg", quality = q or 70, x = 0, y = 0, w = ScrW(), h = ScrH() })
		cb(ok and isstring(data) and #data > 0 and data or nil)
	end)
end

-- ------------------------------------------------------------------ the viewer

local incoming = {} -- shot id -> { n, parts, got }
local metas = {}    -- shot id -> meta
local viewer

local function fmtSize(b)
	b = tonumber(b) or 0
	if b >= 1048576 then return string.format("%.1f MB", b / 1048576) end
	return string.format("%d KB", math.ceil(b / 1024))
end

local function openViewer(meta, mat)
	if IsValid(viewer) then viewer:Close() end
	local m = UI.Modal(P.L("sg_title", { S = meta.name or "?" }), math.floor(ScrW() * 0.86), math.floor(ScrH() * 0.88))
	viewer = m
	local zoom = false

	local info = vgui.Create("DPanel", m.body)
	info:Dock(TOP)
	info:SetTall(S(40))
	info:DockMargin(0, 0, 0, S(8))
	info.Paint = function(_, w, h)
		UI.DrawAvatar(meta.sid, player.GetBySteamID64(meta.sid or ""), 0, S(4), S(32), 255, C.line)
		UI.Text(meta.name or "?", "Praetor.BodyB", S(42), S(12), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		UI.Text(P.L("sg_by", { S = meta.by or "?", V = os.date("%d/%m/%Y %H:%M:%S", meta.t or os.time()) }), "Praetor.Tiny", S(42), S(30), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local right = (meta.w or 0) .. "x" .. (meta.h or 0) .. "  ·  " .. fmtSize(meta.size)
		UI.Text(right, "Praetor.Small", w, S(12), C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		if not meta.focus then
			UI.Icon("warn", w - S(16), S(22), 16, C.amber)
			UI.Text(P.L("sg_nofocus"), "Praetor.Tiny", w - S(22), S(30), C.amber, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	local pic = vgui.Create("DButton", m.body)
	pic:SetText("")
	pic:Dock(FILL)
	pic:SetCursor("hand")
	pic:SetTooltip(P.L("sg_zoom_tip"))
	pic.DoClick = function() zoom = not zoom end
	pic.Paint = function(s, w, h)
		UI.Round(0, 0, w, h, S(8), Color(6, 7, 9), C.line)
		local iw, ih = mat:Width(), mat:Height()
		if iw <= 0 or ih <= 0 then return end
		-- the texture may be resized by the engine: the size and shape come from the meta
		local rw, rh = (meta.w or 0) > 0 and meta.w or iw, (meta.h or 0) > 0 and meta.h or ih
		local u, v = 1, 1
		surface.SetMaterial(mat)
		surface.SetDrawColor(255, 255, 255)
		local x0, y0 = s:LocalToScreen(0, 0)
		render.SetScissorRect(x0 + 2, y0 + 2, x0 + w - 2, y0 + h - 2, true)
		if zoom and (rw > w or rh > h) then
			local mx, my = s:CursorPos()
			local fx, fy = math.Clamp(mx / w, 0, 1), math.Clamp(my / h, 0, 1)
			local dx = rw > w and -(rw - w) * fx or (w - rw) / 2
			local dy = rh > h and -(rh - h) * fy or (h - rh) / 2
			surface.DrawTexturedRectUV(dx, dy, rw, rh, 0, 0, u, v)
		else
			local k = math.min((w - S(8)) / rw, (h - S(8)) / rh)
			local dw, dh = rw * k, rh * k
			surface.DrawTexturedRectUV((w - dw) / 2, (h - dh) / 2, dw, dh, 0, 0, u, v)
		end
		render.SetScissorRect(0, 0, 0, 0, false)
		UI.Round(S(10), h - S(32), S(130), S(22), S(6), Color(0, 0, 0, 160))
		UI.Text(zoom and P.L("sg_mode_full") or P.L("sg_mode_fit"), "Praetor.Tiny", S(75), h - S(21), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local again = UI.Button(m.foot, P.L("sg_again"), "primary", "image", function()
		local ply = player.GetBySteamID64(meta.sid or "")
		if IsValid(ply) then P.RunCmd("screengrab", { meta.sid }) else P.Toast(P.L("sg_tab"), P.L("sg_offline"), "warn") end
	end)
	again:Dock(RIGHT)
	again:SetWide(S(150))
	if P.MyHas("view_sheet") then
		local sheet = UI.Button(m.foot, P.L("qa_sheet"), "ghost", "scroll", function()
			m:Close()
			P.OpenMenu("users", { sid = meta.sid })
		end)
		sheet:Dock(RIGHT)
		sheet:SetWide(S(120))
		sheet:DockMargin(0, 0, S(8), 0)
	end
	local del = UI.Button(m.foot, P.L("sg_delete"), "danger", "trash", function()
		UI.Confirm(P.L("sg_delete"), P.L("sg_delete_q"), function()
			P.Request("sg_del", { id = meta.id })
			if IsValid(m) then m:Close() end
			timer.Simple(0.3, function() if P.ShotsRefresh then P.ShotsRefresh() end end)
		end, true)
	end)
	del:Dock(LEFT)
	del:SetWide(S(120))
end

P.On("sg_meta", function(d)
	if not tonumber(d.id) then return end
	metas[d.id] = d
end)

net.Receive("praetor_shot", function()
	local op = net.ReadUInt(3)
	local id = net.ReadUInt(32)
	if op == OP_ASK then
		local q = net.ReadUInt(7)
		-- capture the next full frame
		hook.Add("PostRender", "Praetor.Shot", function()
			hook.Remove("PostRender", "Praetor.Shot")
			local ok, data = pcall(capture, { format = "jpeg", quality = q, x = 0, y = 0, w = ScrW(), h = ScrH() })
			if ok and isstring(data) and #data > 0 then sendShot(id, data) end
		end)
		return
	end
	if op ~= OP_SEND then return end
	local i, n, l = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(16)
	local part = net.ReadData(l)
	local job = incoming[id] or { n = n, parts = {}, got = 0 }
	incoming[id] = job
	if job.parts[i] then return end
	job.parts[i] = part
	job.got = job.got + 1
	if P.ShotProgress then P.ShotProgress(id, job.got / job.n) end
	if job.got < job.n then return end
	incoming[id] = nil
	local data = table.concat(job.parts)
	file.CreateDir("praetor_shots")
	local path = "praetor_shots/" .. id .. "_" .. math.floor(SysTime() * 1000) .. ".jpg"
	file.Write(path, data)
	local mat = Material("../data/" .. path, "smooth noclamp")
	local meta = metas[id] or { id = id, w = 0, h = 0 }
	if not mat or mat:IsError() then P.Toast(P.L("sg_tab"), P.L("err_sg_bad", { S = meta.name or "?" }), "warn") return end
	UI.Sound("ok")
	openViewer(meta, mat)
end)

-- the copies kept on this computer are cleaned when the game starts
hook.Add("Initialize", "Praetor.ShotClean", function()
	for _, f in ipairs(file.Find("praetor_shots/*.jpg", "DATA") or {}) do file.Delete("praetor_shots/" .. f) end
end)

-- ------------------------------------------------------------------ tab

P.AddTab("shots", {
	cat = "moderation", icon = "image", order = 3.5,
	can = function() return P.CanRunId and P.CanRunId("screengrab") end,
	build = function(panel)
		local list = {}
		local loading = {}

		local top = vgui.Create("DPanel", panel)
		top:Dock(TOP)
		top:SetTall(S(36))
		top:DockMargin(0, 0, 0, S(8))
		top.Paint = nil
		local take = UI.Button(top, P.L("sg_take"), "primary", "image", function()
			UI.Form(P.L("sg_take"), { { "ply", "player", P.L("sg_who"), nil } }, function(v)
				if not v.ply or v.ply == "" then return false end
				P.RunCmd("screengrab", { v.ply })
			end)
		end)
		take:Dock(RIGHT)
		take:SetWide(S(170))
		local search = UI.Entry(top, P.L("sg_search"), "")
		search:Dock(FILL)
		search:DockMargin(0, 0, S(8), 0)

		local sc = UI.Scroll(panel)
		sc:Dock(FILL)

		local function fill()
			if not IsValid(sc) then return end
			sc:Clear()
			if #list == 0 then
				local e = vgui.Create("DPanel", sc)
				e:Dock(TOP)
				e:SetTall(S(140))
				e.Paint = function(_, w, h)
					UI.Icon("image", w / 2 - 16, h / 2 - 34, 32, C.dim)
					UI.Text(P.L("sg_none"), "Praetor.BodyB", w / 2, h / 2 + S(10), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					UI.Text(P.L("sg_none_d"), "Praetor.Small", w / 2, h / 2 + S(32), C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				return
			end
			local lastDay
			for _, r in ipairs(list) do
				local day = os.date("%d/%m/%Y", r.t)
				if day ~= lastDay then
					lastDay = day
					local d = vgui.Create("DPanel", sc)
					d:Dock(TOP)
					d:SetTall(S(24))
					d:DockMargin(0, S(4), S(4), S(2))
					d.Paint = function(_, w, h)
						UI.Text(day, "Praetor.Tiny", 0, h / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						UI.Rect(S(78), math.floor(h / 2), w - S(78), 1, C.line)
					end
				end
				local row = vgui.Create("DButton", sc)
				row:SetText("")
				row:Dock(TOP)
				row:SetTall(S(52))
				row:DockMargin(0, 0, S(4), S(4))
				row.DoClick = function()
					loading[r.id] = 0
					P.Request("sg_get", { id = r.id })
				end
				row.DoRightClick = function()
					UI.Popup({
						{ P.L("sg_open"), "image", row.DoClick },
						{ P.L("copy_steamid"), "copy", function() SetClipboardText(util.SteamIDFrom64(r.sid or "0") or "") end },
						{ P.L("sg_delete"), "trash", function()
							UI.Confirm(P.L("sg_delete"), P.L("sg_delete_q"), function()
								P.Request("sg_del", { id = r.id })
								timer.Simple(0.3, function() if P.ShotsRefresh then P.ShotsRefresh() end end)
							end, true)
						end },
					})
				end
				row.Paint = function(s, w, h)
					UI.Round(0, 0, w, h, S(8), s:IsHovered() and C.hover or C.panel, C.line)
					UI.DrawAvatar(r.sid, player.GetBySteamID64(r.sid or ""), S(10), S(9), S(34), 255, C.line)
					UI.Text(UI.Fit(r.name or "?", "Praetor.BodyB", w * 0.4), "Praetor.BodyB", S(56), S(17), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					UI.Text(P.L("sg_by", { S = r.by or "?", V = os.date("%H:%M", r.t) }), "Praetor.Tiny", S(56), S(35), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local x = w - S(14)
					local p = loading[r.id]
					if p then
						UI.Round(x - S(120), h / 2 - S(3), S(120), S(6), S(3), C.panel2)
						UI.Round(x - S(120), h / 2 - S(3), S(120) * p, S(6), S(3), C.bronze)
					else
						UI.Text((r.w or 0) .. "x" .. (r.h or 0) .. "  ·  " .. fmtSize(r.size), "Praetor.Small", x, h / 2, C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
						if not r.focus then UI.Icon("warn", x - S(170), h / 2 - 8, 16, C.amber) end
					end
				end
			end
		end

		P.ShotProgress = function(id, frac)
			if loading[id] then loading[id] = frac >= 1 and nil or frac end
		end
		local function refresh() P.Request("sg_list", { q = search:GetValue() }) end
		P.ShotsRefresh = refresh
		P.On("sg_list", function(d)
			list = istable(d.list) and d.list or {}
			fill()
		end)
		search.OnEnter = refresh
		local nextQ
		search.OnChange = function() nextQ = RealTime() + 0.4 end
		panel.Think = function()
			if nextQ and RealTime() > nextQ then nextQ = nil refresh() end
		end
		fill()
		refresh()
	end,
})
