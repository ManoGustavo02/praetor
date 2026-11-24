-- Praetor menu: automod. Blocked words, exceptions, what happens to the
-- player and the GIF / link filter, with a box to test a message live.
local P = Praetor
local UI = P.UI
local C = UI.C
local S = P.S

local function multiline(parent, value, hint)
	local e = UI.Entry(parent, hint or "", value or "")
	e:SetMultiline(true)
	e:SetVerticalScrollbarEnabled(true)
	e:SetFont("Praetor.Mono")
	return e
end

local function note(parent, text)
	local l = UI.Label(parent, text, "Praetor.Small", C.muted)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:Dock(TOP)
	l:DockMargin(0, S(2), 0, S(6))
	return l
end

P.AddTab("automod", {
	cat = "moderation", icon = "eye", order = 4,
	can = function() return P.MyHas("automod") end,
	build = function(panel)
		local cur = {
			automod = P.Setting("automod") == true,
			automod_words = P.Setting("automod_words") or "",
			automod_allow = P.Setting("automod_allow") or "",
			automod_images = P.Setting("automod_images") == true,
			automod_image_words = P.Setting("automod_image_words") or "",
			automod_action = P.Setting("automod_action") or "block",
			automod_mute_min = P.Setting("automod_mute_min") or 5,
			automod_message = P.Setting("automod_message") or "",
			automod_alert = P.Setting("automod_alert") == true,
			automod_workshop = P.Setting("automod_workshop") == true,
			automod_staff = P.Setting("automod_staff") == true,
		}
		local retest

		-- right column: behaviour, images, test
		local right = UI.Scroll(panel)
		right:Dock(RIGHT)
		right:SetWide(S(380))
		right:DockMargin(S(12), 0, 0, 0)
		-- small screens: both columns share the space
		local baseThink = right.Think
		right.Think = function(s)
			if baseThink then baseThink(s) end
			local pw = panel:GetWide()
			local want = math.min(S(380), math.floor(pw * 0.48))
			if pw > 0 and s:GetWide() ~= want then s:SetWide(want) end
		end

		UI.Header(right, P.L("am_rules"), P.L("am_rules_sub")):Dock(TOP)
		local on = UI.Switch(right, P.L("am_on"), P.L("am_on_d"), cur.automod, function(v) cur.automod = v end)
		on:Dock(TOP)

		local actRow = vgui.Create("DPanel", right)
		actRow:Dock(TOP)
		actRow:SetTall(S(44))
		actRow:DockMargin(0, S(4), 0, 0)
		actRow.Paint = function(_, w, h) UI.Text(P.L("am_action"), "Praetor.BodyB", S(4), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		local act = UI.Combo(actRow, {
			{ "block", P.L("am_act_block") }, { "warn", P.L("am_act_warn") },
			{ "mute", P.L("am_act_mute") }, { "kick", P.L("am_act_kick") },
		}, cur.automod_action, function(v) cur.automod_action = v end)
		act:Dock(RIGHT)
		act:SetWide(S(190))
		act:DockMargin(0, S(5), 0, S(5))

		local muteRow = vgui.Create("DPanel", right)
		muteRow:Dock(TOP)
		muteRow:SetTall(S(44))
		muteRow.Paint = function(_, w, h) UI.Text(P.L("am_mute_min"), "Praetor.BodyB", S(4), h / 2, C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		local mute = UI.Entry(muteRow, "5", tostring(cur.automod_mute_min), function(v) cur.automod_mute_min = tonumber(v) or cur.automod_mute_min end)
		mute:SetNumeric(true)
		mute:Dock(RIGHT)
		mute:SetWide(S(90))
		mute:DockMargin(0, S(5), 0, S(5))

		local alert = UI.Switch(right, P.L("am_alert"), nil, cur.automod_alert, function(v) cur.automod_alert = v end)
		alert:Dock(TOP)
		local staffSw = UI.Switch(right, P.L("am_staff"), P.L("am_staff_d"), cur.automod_staff, function(v) cur.automod_staff = v end)
		staffSw:Dock(TOP)
		-- tells the reader that they themselves skip the filter right now
		local me = LocalPlayer()
		if (P.IsOwner(me) or P.MyHas("automod_bypass")) then
			local tip = vgui.Create("DPanel", right)
			tip:Dock(TOP)
			tip:DockMargin(0, S(4), 0, S(4))
			tip:SetTall(S(46))
			-- the warning only takes room while it shows (it left a big empty gap before)
			tip:SetVisible(not cur.automod_staff)
			local thinkBefore = right.Think
			right.Think = function(s2)
				thinkBefore(s2)
				local want = not cur.automod_staff
				if tip:IsVisible() ~= want then
					tip:SetVisible(want)
					s2:InvalidateLayout(true)
					if s2.GetCanvas then s2:GetCanvas():InvalidateLayout(true) end
				end
			end
			tip.Paint = function(_, w, h)
				UI.Round(0, 0, w, h, S(6), Color(C.amber.r, C.amber.g, C.amber.b, 28), Color(C.amber.r, C.amber.g, C.amber.b, 110))
				UI.Icon("warn", S(10), (h - 16) / 2, 16)
				local lines = UI.Wrap(P.L("am_you_bypass"), "Praetor.Tiny", w - S(44))
				for i, l in ipairs(lines) do UI.Text(l, "Praetor.Tiny", S(34), h / 2 + (i - (#lines + 1) / 2) * S(14), C.ivory, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
			end
		end

		local msgL = UI.Label(right, P.L("am_message"), "Praetor.BodyB", C.ivory)
		msgL:Dock(TOP)
		msgL:DockMargin(S(4), S(8), 0, 0)
		note(right, P.L("am_message_d"))
		local msg = UI.Entry(right, P.L("n_automod"), cur.automod_message, function(v) cur.automod_message = v end)
		msg:Dock(TOP)
		msg:SetTall(S(34))
		msg:DockMargin(0, 0, 0, S(14))

		UI.Header(right, P.L("am_images"), P.L("am_images_sub")):Dock(TOP)
		local imgOn = UI.Switch(right, P.L("am_images_on"), nil, cur.automod_images, function(v) cur.automod_images = v if retest then retest() end end)
		imgOn:Dock(TOP)
		local imgWords = multiline(right, cur.automod_image_words)
		imgWords:Dock(TOP)
		imgWords:SetTall(S(130))
		imgWords:DockMargin(0, S(4), 0, S(4))
		imgWords.OnChange = function(s) cur.automod_image_words = s:GetValue() if retest then retest() end end
		note(right, P.L("am_images_note"))

		UI.Header(right, P.L("am_ws"), P.L("am_ws_sub")):Dock(TOP)
		local wsOn = UI.Switch(right, P.L("am_ws_on"), P.L("am_ws_d"), cur.automod_workshop, function(v) cur.automod_workshop = v end)
		wsOn:Dock(TOP)
		-- which skin systems are installed (all of them are covered)
		local found = {}
		if Outfitter ~= nil or outfitter ~= nil then found[#found + 1] = "Outfitter" end
		if wardrobe ~= nil then found[#found + 1] = "Wardrobe" end
		if pac ~= nil or pace ~= nil then found[#found + 1] = "PAC3" end
		note(right, #found > 0 and P.L("am_ws_found2", { S = table.concat(found, ", ") }) or P.L("am_ws_any"))

		UI.Header(right, P.L("am_test"), P.L("am_test_sub")):Dock(TOP)
		local test = UI.Entry(right, P.L("am_test_hint"), "")
		test:Dock(TOP)
		test:SetTall(S(34))
		test:DockMargin(0, S(4), 0, 0)
		local result = vgui.Create("DPanel", right)
		result:Dock(TOP)
		result:SetTall(S(34))
		result:DockMargin(0, S(4), 0, S(10))
		result.text, result.col = "", C.muted
		result.Paint = function(s, w, h)
			if s.text == "" then return end
			UI.Rect(0, 0, w, h, C.panel2)
			UI.Rect(0, 0, S(4), h, s.col)
			UI.Text(UI.Fit(s.text, "Praetor.SmallB", w - S(16)), "Praetor.SmallB", S(12), h / 2, s.col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		retest = function()
			local t = test:GetValue()
			if P.Trim(t) == "" then result.text = "" return end
			local word, kind = P.AutoModScan(t, {
				words = cur.automod_words, allow = cur.automod_allow,
				images = cur.automod_images, image_words = cur.automod_image_words,
			})
			if word then
				result.text = P.L(kind == "image" and "am_test_hit_img" or "am_test_hit", { V = word })
				result.col = C.crimsonL
			else
				result.text = P.L("am_test_ok")
				result.col = C.laurel
			end
		end
		test.OnChange = retest

		-- bottom bar
		local bar = UI.Toolbar(panel, S(36))
		bar:Dock(BOTTOM)
		bar:DockMargin(0, S(8), 0, 0)
		UI.Tool(bar, UI.Button(bar, P.L("ui_save"), "primary", "eye", function()
			cur.automod_mute_min = math.max(1, tonumber(mute:GetValue()) or cur.automod_mute_min)
			P.Request("automod_set", { v = cur })
		end), S(160))
		if P.MyHas("logs") then
			UI.Tool(bar, UI.Button(bar, P.L("am_see_logs"), "ghost", "scroll", function()
				if IsValid(P.Menu) then P.Menu:SelectTab("logs", { cat = "automod" }) end
			end), S(200))
		end

		-- left: word lists
		local left = vgui.Create("DPanel", panel)
		left:Dock(FILL)
		left.Paint = nil
		UI.Header(left, P.L("am_words"), P.L("am_words_sub")):Dock(TOP)
		local where = note(left, P.L("am_where"))
		where:SetTextColor(C.amber)
		note(left, P.L("am_syntax"))
		local allowBox = vgui.Create("DPanel", left)
		allowBox:Dock(BOTTOM)
		allowBox:SetTall(S(170))
		allowBox:DockMargin(0, S(10), 0, 0)
		allowBox.Paint = nil
		UI.Header(allowBox, P.L("am_allow"), P.L("am_allow_sub")):Dock(TOP)
		local allow = multiline(allowBox, cur.automod_allow, "assassin\nclass*")
		allow:Dock(FILL)
		allow:DockMargin(0, S(4), 0, 0)
		allow.OnChange = function(s) cur.automod_allow = s:GetValue() retest() end
		local words = multiline(left, cur.automod_words, P.L("am_words_hint"))
		words:Dock(FILL)
		words:DockMargin(0, S(4), 0, 0)
		words.OnChange = function(s) cur.automod_words = s:GetValue() retest() end
	end,
})
