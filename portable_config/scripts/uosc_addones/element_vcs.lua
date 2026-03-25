--[[

VCS扩展菜单 — uosc_addones 子模块

]]


local vcs_active = false
local vcs_overlay = nil
local selected = 1               -- 当前选中索引 (1-based)
local times = {}                 -- 时间码列表
local frame_count = 0            -- 实际帧数
local frame_loaded = {}          -- { [0-based_index] = true }
local grid = nil                 -- 网格布局信息
local phantom_open = false       -- 幽灵菜单是否打开
local osd_w_cached = 0           -- 打开时的 OSD 尺寸
local osd_h_cached = 0

-- 来自 thumb_engine-bat-info 广播的批量配置
local te_vcs = {
	bat_overlay_ids = nil,
	bat_path        = nil,
}

-- =============================================================================
-- =============================================================================

local function format_time(seconds)
	if not seconds or seconds < 0 then seconds = 0 end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	else
		return string.format("%d:%02d", m, s)
	end
end

local function format_timestamp(seconds)
	if not seconds or seconds < 0 then seconds = 0 end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%04.1f", h, m, s)
	else
		return string.format("%d:%04.1f", m, s)
	end
end

local function parse_overlay_ids_count(str)
	local count = 0
	if not str or str == "" then return count end
	for id_str in str:gmatch("[^,]+") do
		local id = tonumber(id_str:match("^%s*(%d+)%s*$"))
		if id and id >= 0 and id <= 63 then
			count = count + 1
		end
	end
	return count
end

local function ass_escape(str)
	if not str then return "" end
	return str:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}")
end

-- =============================================================================
-- 时间码计算
-- =============================================================================

local function calc_time_points(duration, chapter_list, chapter_mode, max_count)
	max_count = max_count or 9

	-- 章节模式
	if chapter_mode and chapter_list and #chapter_list > 0 then
		local t = {}
		for i = 1, math.min(max_count, #chapter_list) do
			t[i] = chapter_list[i].time or 0
		end
		return t
	end

	-- 均分模式
	local t = {}
	local prev = -1
	for i = 1, max_count do
		local time = duration * i / (max_count + 1)
		if time < 0.5 then time = 0.5 end
		if time > duration - 0.5 then time = duration - 0.5 end
		-- 极短视频：跳过与前一个重复的时间点
		if math.abs(time - prev) >= 0.1 then
			t[#t + 1] = time
			prev = time
		end
	end
	return t
end

-- =============================================================================
-- 缩略图尺寸 & 网格布局
-- =============================================================================

-- 行距系数
local LINE_HEIGHT_FACTOR = 1.4

-- 统一布局计算：预留区从 OSD 高度固定比例分配，不与缩略图互相影响
local function calc_cols(count)
	if count <= 4 then return 2
	elseif count <= 9 then return 3
	elseif count <= 16 then return 4
	else return 5 end
end

local function calc_layout(osd_w, osd_h, video_w, video_h, count, padding, cfg_w, cfg_h)
	cfg_w = cfg_w or 0
	cfg_h = cfg_h or 0
	local cols = calc_cols(count)
	local rows = math.ceil(count / cols)

	-- 预留区：OSD 高度的固定比例
	local top_h = math.floor(osd_h * 0.15)
	local bottom_h = math.floor(osd_h * 0.08)

	-- 字号从各自预留区高度推导
	local info_fs = math.floor(math.max(14, (top_h - 2 * padding) / (3 * LINE_HEIGHT_FACTOR)))
	local hint_fs = math.floor(math.max(12, bottom_h / (2 * LINE_HEIGHT_FACTOR)))

	-- 缩略图尺寸：占据中部空间
	local avail_w = osd_w - 2 * padding
	local avail_h = osd_h - top_h - bottom_h - 2 * padding

	local thumb_w
	if cfg_w > 0 then
		thumb_w = cfg_w
	else
		thumb_w = math.floor((avail_w - (cols - 1) * padding) / cols)
	end

	local thumb_h
	if cfg_h > 0 then
		thumb_h = cfg_h
	else
		thumb_h = math.floor(thumb_w * video_h / video_w)
	end

	-- 时间戳字号从缩略图宽度推导
	local ts_fs = math.floor(math.max(12, thumb_w * 0.08))
	local ts_height = math.floor(ts_fs * LINE_HEIGHT_FACTOR)

	-- 高度溢出检查
	local cell_h = thumb_h + ts_height
	local grid_h = rows * cell_h + (rows - 1) * padding
	if grid_h > avail_h and avail_h > 0 then
		local sf = avail_h / grid_h
		thumb_w = math.floor(thumb_w * sf)
		if cfg_h <= 0 then
			thumb_h = math.floor(thumb_w * video_h / video_w)
		end
		ts_fs = math.floor(math.max(12, thumb_w * 0.08))
		ts_height = math.floor(ts_fs * LINE_HEIGHT_FACTOR)
	end

	-- 确保尺寸偶数
	thumb_w = math.floor(thumb_w / 2) * 2
	thumb_h = math.floor(thumb_h / 2) * 2
	if thumb_w < 64 then thumb_w = 64 end
	if thumb_h < 36 then thumb_h = 36 end

	-- 计算网格位置
	local cell_w = thumb_w
	cell_h = thumb_h + ts_height
	local grid_w = cols * cell_w + (cols - 1) * padding
	grid_h = rows * cell_h + (rows - 1) * padding
	local avail_h = osd_h - top_h - bottom_h

	local start_x = math.floor((osd_w - grid_w) / 2)
	local start_y = top_h + math.floor((avail_h - grid_h) / 2)

	if start_y < top_h then start_y = top_h end
	if start_y + grid_h > osd_h - bottom_h then
		start_y = osd_h - bottom_h - grid_h
		if start_y < top_h then start_y = top_h end
	end

	local positions = {}
	for i = 0, count - 1 do
		local row = math.floor(i / cols)
		local col = i % cols

		local row_start = row * cols
		local row_count = math.min(cols, count - row_start)
		local row_offset = 0
		if row_count < cols then
			row_offset = math.floor((cols - row_count) * (cell_w + padding) / 2)
		end

		local x = start_x + col * (cell_w + padding) + row_offset
		local y = start_y + row * (cell_h + padding)
		positions[i + 1] = {math.floor(x), math.floor(y)}
	end

	return {
		cols = cols,
		rows = rows,
		positions = positions,
		thumb_w = thumb_w,
		thumb_h = thumb_h,
		ts_fs = ts_fs,
		ts_height = ts_height,
		info_fs = info_fs,
		hint_fs = hint_fs,
		top_h = top_h,
		bottom_h = bottom_h,
		grid_w = grid_w,
		grid_h = grid_h,
		start_x = start_x,
		start_y = start_y,
		count = count,
	}
end

-- =============================================================================
-- 文字层
-- =============================================================================

local function render_ass()
	if not vcs_overlay or not grid then return end

	local lines = {}

	-- 左上角信息栏
	local filename = mp.get_property("filename/no-ext", "") or ""
	local duration = mp.get_property_number("duration", 0)
	local vp = mp.get_property_native("video-params")
	local res_str = ""
	if vp and vp.w and vp.h and vp.w > 0 and vp.h > 0 then
		res_str = vp.w .. "×" .. vp.h
	end

	local info_lines = {}
	if filename ~= "" then
		info_lines[#info_lines + 1] = ass_escape(filename)
	end
	if duration > 0 then
		info_lines[#info_lines + 1] = format_time(duration)
	end
	if res_str ~= "" then
		info_lines[#info_lines + 1] = res_str
	end
	local info_text = table.concat(info_lines, "\\N")

	local pad = opts.vcs_padding
	local bord = math.max(1, math.floor(grid.info_fs * 0.08))
	lines[#lines + 1] = string.format(
		"{\\rDefault\\pos(%d,%d)\\an7\\fs%d\\1c&HFFFFFF&\\bord%s\\3c&H000000&\\shad0}%s",
		pad, pad, grid.info_fs, bord, info_text
	)

	-- 底部提示栏
	local sel_time_str = ""
	if times[selected] then
		sel_time_str = format_timestamp(times[selected])
	end
	local hint_text = string.format("[%d/%d]  %s  \\N↑↓←→ 导航  Enter 跳转  Esc 关闭",
		selected, grid.count, sel_time_str)

	local hint_bord = math.max(1, math.floor(grid.hint_fs * 0.08))
	lines[#lines + 1] = string.format(
		"{\\rDefault\\pos(%d,%d)\\an2\\fs%d\\1c&HCCCCCC&\\bord%s\\3c&H000000&\\shad0}%s",
		math.floor(osd_w_cached / 2), osd_h_cached - pad, grid.hint_fs, hint_bord, hint_text
	)

	-- 网格
	for i = 1, grid.count do
		local pos = grid.positions[i]
		if not pos then goto continue end

		local x, y = pos[1], pos[2]
		local w, h = grid.thumb_w, grid.thumb_h

		-- 占位符（未加载帧）
		if not frame_loaded[i - 1] then
			-- 灰色矩形
			lines[#lines + 1] = string.format(
				"{\\rDefault\\pos(%d,%d)\\an7\\1c&H303030&\\bord0\\shad0\\p1}m 0 0 l %d 0 %d %d 0 %d",
				x, y, w, w, h, h
			)
			-- 加载提示
			lines[#lines + 1] = string.format(
				"{\\rDefault\\pos(%d,%d)\\an5\\fs%d\\1c&H808080&\\bord0\\shad0}·····",
				x + math.floor(w / 2), y + math.floor(h / 2), grid.ts_fs
			)
		end

		-- 时间戳
		if times[i] then
			local ts_bord = math.max(1, math.floor(grid.ts_fs * 0.08))
			local ts_gap = math.max(4, math.floor(grid.ts_fs * 0.3))
			lines[#lines + 1] = string.format(
				"{\\rDefault\\pos(%d,%d)\\an8\\fs%d\\1c&HCCCCCC&\\bord%s\\3c&H000000&\\shad0}%s",
				x + math.floor(w / 2),
				y + h + ts_gap,
				grid.ts_fs,
				ts_bord,
				format_timestamp(times[i])
			)
		end

		-- 选中边框
		if i == selected then
			local bw = math.max(2, math.floor(grid.thumb_w * 0.01))
			lines[#lines + 1] = string.format(
				"{\\rDefault\\pos(%d,%d)\\an7\\1a&HFF&\\3c&H00AAFF&\\bord%d\\shad0\\p1}m 0 0 l %d 0 %d %d 0 %d",
				x - bw, y - bw, bw,
				w + 2 * bw, w + 2 * bw, h + 2 * bw, h + 2 * bw
			)
		end

		::continue::
	end

	vcs_overlay.data = table.concat(lines, "\n")
	vcs_overlay:update()
end

-- =============================================================================
-- 按键绑定
-- =============================================================================

local key_binding_names = {}
local mouse_observer_active = false
local resize_observer_active = false

local function on_mouse_move(_, mouse)
	if not mouse or not grid then return end
	local mx, my = mouse.x, mouse.y
	for i = 1, grid.count do
		local pos = grid.positions[i]
		if pos then
			if mx >= pos[1] and mx < pos[1] + grid.thumb_w and
			   my >= pos[2] and my < pos[2] + grid.thumb_h then
				if i ~= selected then
					selected = i
					render_ass()
				end
				return
			end
		end
	end
end

local function navigate(dx, dy)
	if not grid or frame_count == 0 then return end
	local cols = grid.cols
	local row = math.floor((selected - 1) / cols)
	local col = (selected - 1) % cols

	col = col + dx
	row = row + dy

	local max_rows = grid.rows
	if row < 0 then row = 0 end
	if row >= max_rows then row = max_rows - 1 end
	if col < 0 then col = 0 end
	if col >= cols then col = cols - 1 end

	local new_idx = row * cols + col + 1
	if new_idx > frame_count then new_idx = frame_count end
	if new_idx < 1 then new_idx = 1 end

	if new_idx ~= selected then
		selected = new_idx
		render_ass()
	end
end

-- forward declaration
local vcs_close

local function on_osd_resize()
	if not vcs_active then return end
	local w = mp.get_property_number("osd-width", 0)
	local h = mp.get_property_number("osd-height", 0)
	if w ~= osd_w_cached or h ~= osd_h_cached then
		vcs_close()
		-- mp.osd_message("VCS: 窗口尺寸变化，已关闭", 1)
	end
end

local function seek_and_close(index)
	if times[index] then
		mp.commandv("seek", tostring(times[index]), "absolute")
	end
	vcs_close()
end

local function select_current()
	seek_and_close(selected)
end

local function handle_click()
	local mouse = mp.get_property_native("mouse-pos")
	if not mouse or not grid then return end
	local mx, my = mouse.x, mouse.y

	for i = 1, grid.count do
		local pos = grid.positions[i]
		if pos then
			if mx >= pos[1] and mx < pos[1] + grid.thumb_w and
			   my >= pos[2] and my < pos[2] + grid.thumb_h then
				seek_and_close(i)
				return
			end
		end
	end

	-- 点击空白区域关闭
	vcs_close()
end

local function bind_keys()
	local binds = {
		{"UP",       "vcs-up",     function() navigate(0, -1) end,  {repeatable = true}},
		{"DOWN",     "vcs-down",   function() navigate(0, 1) end,   {repeatable = true}},
		{"LEFT",     "vcs-left",   function() navigate(-1, 0) end,  {repeatable = true}},
		{"RIGHT",    "vcs-right",  function() navigate(1, 0) end,   {repeatable = true}},
		{"ENTER",    "vcs-enter",  select_current},
		{"KP_ENTER", "vcs-enter2", select_current},
		{"ESC",      "vcs-esc",    function() vcs_close() end},
		{"MBTN_LEFT","vcs-click",  handle_click},
	}
	for _, b in ipairs(binds) do
		mp.add_forced_key_binding(b[1], b[2], b[3], b[4])
		key_binding_names[#key_binding_names + 1] = b[2]
	end
	mp.observe_property("mouse-pos", "native", on_mouse_move)
	mouse_observer_active = true
	mp.observe_property("osd-width", "number", on_osd_resize)
	mp.observe_property("osd-height", "number", on_osd_resize)
	resize_observer_active = true
end

local function unbind_keys()
	for _, name in ipairs(key_binding_names) do
		mp.remove_key_binding(name)
	end
	key_binding_names = {}
	if mouse_observer_active then
		mp.unobserve_property(on_mouse_move)
		mouse_observer_active = false
	end
	if resize_observer_active then
		mp.unobserve_property(on_osd_resize)
		resize_observer_active = false
	end
end

-- =============================================================================
-- 开关
-- =============================================================================

vcs_close = function()
	if not vcs_active then return end
	vcs_active = false

	if vcs_overlay then
		vcs_overlay:remove()
		vcs_overlay = nil
	end

	unbind_keys()

	mp.commandv("script-message-to", "thumb_engine", "batch_pause")

	if phantom_open then
		phantom_open = false
		mp.commandv("script-message-to", "uosc", "close-menu", "vcs")
	end
end

local function vcs_open()
	if vcs_active then
		vcs_close()
		return
	end

	local duration = mp.get_property_number("duration", 0)
	if duration <= 0 then
		-- mp.osd_message("VCS: 无法获取视频时长", 2)
		return
	end

	local vp = mp.get_property_native("video-params")
	if not vp or not vp.w or not vp.h or vp.w <= 0 or vp.h <= 0 then
		-- mp.osd_message("VCS: 无视频轨", 2)
		return
	end

	if mp.get_property_native("demuxer-via-network") then
		-- mp.osd_message("VCS: 不支持网络流", 2)
		return
	end

	local osd_w = mp.get_property_number("osd-width", 0)
	local osd_h = mp.get_property_number("osd-height", 0)
	if osd_w == 0 or osd_h == 0 then
		-- mp.osd_message("VCS: 无法获取 OSD 尺寸", 2)
		return
	end

	osd_w_cached = osd_w
	osd_h_cached = osd_h

	-- 初始化状态

	-- thumb_engine 广播尚未收到
	if not te_vcs.bat_overlay_ids then
		-- mp.osd_message("VCS: 等待 thumb_engine 就绪…", 2)
		mp.commandv("script-message-to", "thumb_engine", "thumb_engine-bat-info?")
		return
	end

	vcs_active = true
	selected = 1
	frame_loaded = {}

	-- 使用来自 thumb_engine 广播的批量配置
	local max_slots = parse_overlay_ids_count(te_vcs.bat_overlay_ids)
	if max_slots == 0 then
		-- mp.osd_message("VCS: overlay ID 配置无效", 2)
		vcs_active = false
		return
	end
	if max_slots > 25 then max_slots = 25 end

	-- 确定请求数量：vcs_tiles > 0 时使用用户指定值，否则回退到 overlay_ids 项数
	local tiles = math.floor(opts.vcs_tiles or 0)
	if tiles < 0 then tiles = 0 end
	if tiles > 25 then tiles = 25 end
	local req_count = tiles > 0 and math.min(tiles, max_slots) or max_slots

	-- 计算时间码
	local chapter_list = mp.get_property_native("chapter-list", {})
	times = calc_time_points(duration, chapter_list, opts.vcs_chapter_mode, req_count)
	frame_count = #times

	-- 限制帧数不超过 overlay_ids 数量
	if frame_count > max_slots then
		frame_count = max_slots
		local new_times = {}
		for i = 1, frame_count do new_times[i] = times[i] end
		times = new_times
	end

	-- 计算布局（缩略图尺寸、字号、预留区、网格位置一次完成）
	local padding = opts.vcs_padding
	-- 处理旋转元数据（90°/270° 时宽高互换）
	local vid_w, vid_h = vp.w, vp.h
	local rotate = mp.get_property_number("video-params/rotate", 0)
	if rotate % 180 == 90 then
		vid_w, vid_h = vid_h, vid_w
	end

	grid = calc_layout(osd_w, osd_h, vid_w, vid_h, frame_count, padding)
	local thumb_w, thumb_h = grid.thumb_w, grid.thumb_h

	-- 界面

	phantom_open = true
	mp.commandv("script-message-to", "uosc", "open-menu",
		utils.format_json({
			type = "vcs",
			title = "",
			items = {},
			phantom = true,
			on_close = {"script-message-to", script_name, "vcs-menu-closed"},
		})
	)

	vcs_overlay = mp.create_osd_overlay("ass-events")
	vcs_overlay.res_x = osd_w
	vcs_overlay.res_y = osd_h

	-- 暂停单帧预览
	mp.commandv("script-message-to", "thumb_engine", "thumbnail_clr")

	local positions_for_json = {}
	for i = 1, frame_count do
		positions_for_json[i] = grid.positions[i]
	end

	local batch_json = utils.format_json({
		requester = script_name,
		times = times,
		width = thumb_w,
		height = thumb_h,
		positions = positions_for_json,
		use_keyframe = true,
	})
	mp.commandv("script-message-to", "thumb_engine", "batch_gen", batch_json)

	render_ass()

	bind_keys()
end

-- =============================================================================
-- =============================================================================

local function on_batch_once(json_str)
	if not vcs_active then return end
	local data = utils.parse_json(json_str)
	if not data or type(data.index) ~= "number" then return end
	if data.index < 0 or data.index >= frame_count then return end

	frame_loaded[data.index] = true
	render_ass()
end

local function on_batch_done(json_str)
	if not vcs_active then return end
	local data = utils.parse_json(json_str)
	if data then
		msg.verbose("VCS batch done: " .. (data.completed or 0) .. "/" .. (data.total or 0))
	end
end

local function on_vcs_menu_closed()
	if vcs_active then
		phantom_open = false -- 已被关闭，不需要再次 close-menu
		vcs_active = false

		if vcs_overlay then
			vcs_overlay:remove()
			vcs_overlay = nil
		end
		unbind_keys()
		mp.commandv("script-message-to", "thumb_engine", "batch_pause")
	end
end

-- =============================================================================
-- =============================================================================

local function on_file_change()
	if vcs_active then
		vcs_close()
	end
	mp.commandv("script-message-to", "thumb_engine", "batch_clr")
end

local function on_shutdown()
	if vcs_active then
		vcs_close()
	end
	mp.commandv("script-message-to", "thumb_engine", "batch_clr", "rmdir")
end

-- =============================================================================
-- =============================================================================

-- 监听批量模式广播（不依赖 uosc_ready，确保不漏掉早期广播）
mp.register_script_message("thumb_engine-bat-info", function(json_str)
	local data = utils.parse_json(json_str)
	if not data then return end
	if data.bat_overlay_ids  ~= nil then te_vcs.bat_overlay_ids  = data.bat_overlay_ids  end
	if data.bat_path         ~= nil then te_vcs.bat_path         = data.bat_path         end
end)

function vcs_init()
	mp.register_script_message("batch_once", on_batch_once)
	mp.register_script_message("batch_done", on_batch_done)
	mp.register_script_message("vcs-menu-closed", on_vcs_menu_closed)

	mp.register_event("file-loaded", on_file_change)
	mp.register_event("shutdown", on_shutdown)
end

function handle_uosc_element_vcs(action)
	action = action or "toggle"
	if action == "toggle" then
		if vcs_active then vcs_close() else vcs_open() end
	elseif action == "enable" then
		if not vcs_active then vcs_open() end
	elseif action == "disable" then
		if vcs_active then vcs_close() end
	end
end
