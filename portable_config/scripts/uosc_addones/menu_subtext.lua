--[[

字幕行扩展菜单 — uosc_addones 子模块

]]


local menu_type = "k7subtext"
local initialized = false

-- =============================================================================
-- 字幕提取
-- =============================================================================

local function clean_sub_line(line)
	return line:gsub("<.->", "")                  -- HTML 标签
	           :gsub("\\h+", " ")                 -- \h 标签
	           :gsub("{[\\=].-}", "")             -- ASS 格式标签
	           :gsub(".-]", "", 1)                -- 时间前缀
	           :gsub("^%s+", ""):gsub("%s+$", "") -- 首尾空白
	           :gsub("^m%s[mbl%s%-%d%.]+$", "")   -- 绘图指令
end

local function extract_subtitle_lines(callback)
	local sub = mp.get_property_native("current-tracks/sub")
	if not sub then
		msg.warn("未加载字幕轨")
		mp.osd_message("未加载字幕轨", 2)
		return
	end

	-- 处理 EDL 协议中的外部 URL
	if sub.external and sub["external-filename"] then
		local fname = sub["external-filename"]
		if fname:find("^edl://") then
			sub["external-filename"] = fname:match("https?://.*") or fname
		end
	end

	local args
	if sub.external then
		args = {
			"ffmpeg", "-loglevel", "error",
			"-i", sub["external-filename"],
			"-f", "lrc", "-map_metadata", "-1", "-fflags", "+bitexact", "-",
		}
	else
		local path = mp.get_property("path")
		if not path then
			msg.warn("无法获取媒体路径")
			return
		end
		args = {
			"ffmpeg", "-loglevel", "error",
			"-i", path,
			"-map", "s:" .. (sub["id"] - 1),
			"-f", "lrc", "-map_metadata", "-1", "-fflags", "+bitexact", "-",
		}
	end

	mp.command_native_async({
		name = "subprocess",
		capture_stdout = true,
		args = args,
	}, function(success, result)
		if not success or not result then
			msg.error("字幕提取失败")
			return
		end
		if result.error_string == "init" then
			msg.error("字幕提取失败：未找到 ffmpeg")
			mp.osd_message("字幕提取失败：未找到 ffmpeg", 3)
			return
		end
		if result.status ~= 0 then
			msg.error("字幕提取失败 (exit " .. tostring(result.status) .. ")")
			mp.osd_message("字幕提取失败", 3)
			return
		end
		callback(result.stdout, sub)
	end)
end

-- =============================================================================
-- =============================================================================

local subtext_actions = {
	{name = "copy", icon = "content_copy", label = "复制字幕文本"},
}

local function parse_and_open(raw_lrc, sub_info)
	local duration = mp.get_property_native("duration", math.huge)
	local delay = mp.get_property_native("sub-delay", 0)
	local time_pos = mp.get_property_native("time-pos", 0) - delay
	local use_hours = duration >= 3600

	local items = {}
	local selected_index = 1

	if opts.subtext_merge then
		-- 按时间戳收集文本，同一时刻的多行合并
		local time_map = {}   -- time_seconds -> {text1, text2, ...}
		local time_order = {}

		for line in raw_lrc:gmatch("[^\n]+") do
			local cleaned = clean_sub_line(line)
			local min_str = line:match("^%[(%d+)")
			local sec_str = line:match("^%[%d+:([%d%.]+)")
			if min_str and sec_str then
				local t = tonumber(min_str) * 60 + tonumber(sec_str)
				-- 跳过空行和纯图形字幕
				if sub_info.codec == "text" or (cleaned ~= "" and not cleaned:match("^%s+$")) then
					if not time_map[t] then
						time_map[t] = {}
						time_order[#time_order + 1] = t
					end
					-- 避免同一时刻的重复文本
					local exists = false
					for _, existing in ipairs(time_map[t]) do
						if existing == cleaned then exists = true; break end
					end
					if not exists then
						time_map[t][#time_map[t] + 1] = cleaned
					end
				end
			end
		end

		table.sort(time_order)

		for i, t in ipairs(time_order) do
			local texts = time_map[t]
			local display = table.concat(texts, " /// ")
			local title = display ~= "" and display or "—"
			items[#items + 1] = {
				title = truncate_hint(title, 80, 77),
				hint = format_time(t, use_hours),
				value = {time = t, text = display},
				active = false,
			}
			if t <= time_pos then
				selected_index = #items
			end
		end
	else
		-- 不合并，每条字幕行独立显示
		local entries = {}

		for line in raw_lrc:gmatch("[^\n]+") do
			local cleaned = clean_sub_line(line)
			local min_str = line:match("^%[(%d+)")
			local sec_str = line:match("^%[%d+:([%d%.]+)")
			if min_str and sec_str then
				local t = tonumber(min_str) * 60 + tonumber(sec_str)
				if sub_info.codec == "text" or (cleaned ~= "" and not cleaned:match("^%s+$")) then
					entries[#entries + 1] = {time = t, text = cleaned}
				end
			end
		end

		table.sort(entries, function(a, b) return a.time < b.time end)

		for i, e in ipairs(entries) do
			local title = e.text ~= "" and e.text or "—"
			items[#items + 1] = {
				title = truncate_hint(title, 80, 77),
				hint = format_time(e.time, use_hours),
				value = {time = e.time, text = e.text},
				active = false,
			}
			if e.time <= time_pos then
				selected_index = #items
			end
		end
	end

	if #items == 0 then
		msg.warn("未提取到有效字幕行")
		mp.osd_message("未提取到有效字幕行", 3)
		return
	end

	if items[selected_index] then
		items[selected_index].active = true
	end

	local menu_data = {
		type = menu_type,
		title = "字幕行扩展菜单",
		hint = sub_info.title or sub_info.lang or "",
		search_style = "palette",
		search_submenus = false,
		keep_open = true,
		curtain = false,
		selected_index = selected_index,
		callback = {script_name, "subtext-menu-event"},
		item_actions = subtext_actions,
		item_actions_place = "outside",
		items = items,
	}

	local json_str = utils.format_json(menu_data)
	mp.commandv("script-message-to", "uosc", "open-menu", json_str)
end

-- =============================================================================
-- =============================================================================

function handle_subtext_menu_event(json_str)
	if not initialized then return end
	local event = utils.parse_json(json_str)
	if not event then return end

	if event.type == "activate" then
		local val = event.value
		if type(val) ~= "table" then return end

		if event.action == "copy" then
			mp.set_property("clipboard/text", val.text or "")
			mp.osd_message("已复制字幕文本", 2)
			return
		end

		local t = val.time
		if type(t) ~= "number" then return end

		local delay = mp.get_property_native("sub-delay", 0)
		-- 当无视频轨或为纯图片时，额外偏移确保暂停状态下字幕可见
		if mp.get_property_native("current-tracks/video/image") ~= false then
			delay = delay + 0.05
		end
		mp.commandv("seek", t + delay, "absolute")
	end
end

function handle_uosc_menu_subtext()
	if not initialized then return end
	extract_subtitle_lines(parse_and_open)
end

local function on_file_change()
	mp.commandv("script-message-to", "uosc", "close-menu", menu_type)
end

function subtext_menu_init()
	initialized = true
	mp.register_event("file-loaded", on_file_change)
end
