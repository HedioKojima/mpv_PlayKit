--[[

用户着色器扩展菜单 — uosc_addones 子模块

]]


local shader_base_path = ""
local use_relative_paths = false
local mounted_shaders = {}
local menu_type = "k7shader"
local last_submenu_id = nil
local initialized = false

local presets = {
	{str = "", list = {}},
	{str = "", list = {}},
	{str = "", list = {}},
}

local shader_item_actions = {
	{name = "set",     icon = "looks_one",          label = "独占"},
	{name = "toggle",  icon = "toggle_on",          label = "切换"},
	{name = "append",  icon = "playlist_add",       label = "追加"},
	{name = "prepend", icon = "vertical_align_top", label = "前插"},
	{name = "remove",  icon = "delete",             label = "移除"},
}

local shader_extensions = {}
local allow_no_ext = false

local function parse_extensions()
	shader_extensions = {}
	allow_no_ext = false
	local exts_str = opts.shader_exts:match("^%s*(.-)%s*$")
	if exts_str == "" then return end
	for ext in exts_str:gmatch("[^,%s]+") do
		if ext == "*" then
			allow_no_ext = true
		else
			shader_extensions[ext:lower()] = true
		end
	end
end

-- =============================================================================
-- =============================================================================

local function should_include_file(filename)
	if next(shader_extensions) == nil and not allow_no_ext then
		return true
	end
	local ext = get_extension(filename)
	if not ext then
		return allow_no_ext
	end
	return shader_extensions[ext:lower()] or false
end

local function make_shader_cmd_path(abs_path)
	if use_relative_paths then
		local norm_abs = normalize_path(abs_path)
		local norm_base = normalize_path(shader_base_path)
		if norm_base:sub(-1) ~= "/" then
			norm_base = norm_base .. "/"
		end
		local rel = norm_abs:sub(#norm_base + 1)
		if rel then
			local dir = normalize_path(opts.shader_dir):gsub("/$", "")
			return dir .. "/" .. rel
		end
	end
	return abs_path
end

-- =============================================================================
-- =============================================================================

local function expand_shader_path(p)
	local norm = normalize_path(p)
	if norm:match("^~~/") or norm:match("^~~\\") then
		local expanded = mp.command_native({"expand-path", p})
		return expanded or p
	end
	return p
end

local function refresh_mounted_shaders()
	mounted_shaders = {}
	local shader_list = mp.get_property_native("glsl-shaders", {})
	if type(shader_list) == "table" then
		for _, p in ipairs(shader_list) do
			local expanded = expand_shader_path(p)
			mounted_shaders[path_key(expanded)] = p -- 保存原始路径
		end
	elseif type(shader_list) == "string" and shader_list ~= "" then
		for p in shader_list:gmatch("[^,]+") do
			local trimmed = p:match("^%s*(.-)%s*$")
			if trimmed ~= "" then
				local expanded = expand_shader_path(trimmed)
				mounted_shaders[path_key(expanded)] = trimmed
			end
		end
	end
end

local function is_shader_mounted(abs_path)
	return mounted_shaders[path_key(abs_path)] ~= nil
end

-- =============================================================================
-- =============================================================================

local PRESETS_FILENAME = "saved-glsl-list.json"

local function get_presets_filepath()
	local dir = opts.shader_cache_dir
	local expanded = mp.command_native({"expand-path", dir}) or dir
	return utils.join_path(expanded, PRESETS_FILENAME)
end

local function save_presets_to_file()
	local filepath = get_presets_filepath()
	local data = {}
	for i = 1, #presets do
		data[i] = {str = presets[i].str, list = presets[i].list}
	end
	local json = utils.format_json(data)
	if not json then
		msg.warn("序列化预设失败")
		return false
	end
	local f = io.open(filepath, "w")
	if not f then
		msg.warn("无法写入文件: " .. filepath)
		return false
	end
	f:write(json)
	f:close()
	msg.info("所有预设已保存到: " .. filepath)
	return true
end

local function load_presets_from_file()
	local filepath = get_presets_filepath()
	local f = io.open(filepath, "r")
	if not f then return false end
	local content = f:read("*a")
	f:close()
	local data = utils.parse_json(content)
	if type(data) ~= "table" then
		msg.warn("预设文件解析失败: " .. filepath)
		return false
	end
	for i = 1, #presets do
		local entry = data[i]
		if type(entry) == "table" and entry.list then
			presets[i].list = entry.list
			presets[i].str = entry.str or table.concat(entry.list, ",")
		end
	end
	-- msg.info("已加载: " .. filepath)
	return true
end

local function save_preset(index)
	presets[index].str = mp.get_property("glsl-shaders", "")
	local list = mp.get_property_native("glsl-shaders", {})
	presets[index].list = (type(list) == "table") and list or {}
	if opts.shader_preset_save == "persist" then save_presets_to_file() end
end

local function preset_is_empty(index)
	return #presets[index].list == 0
end

local function preset_hint(index)
	local count = #presets[index].list
	if count == 0 then return "空" end
	return tostring(count) .. " 项"
end

local function preset_label(index)
	local list = presets[index].list
	if #list == 0 then return "空" end
	local prefix = normalize_path(opts.shader_dir)
	if prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end
	local display = {}
	for i, p in ipairs(list) do
		local norm = normalize_path(p)
		if norm:sub(1, #prefix) == prefix then
			display[i] = norm:sub(#prefix + 1)
		else
			display[i] = p
		end
	end
	return table.concat(display, "\n")
end

local function build_preset_actions(index)
	return {
		{name = "info",  icon = "info",         label = preset_label(index)},
		{name = "save",  icon = "save",         label = "保存当前用户着色器队列到预设"},
		{name = "copy",  icon = "content_copy", label = "复制该预设到剪贴板"},
		{name = "clear", icon = "clear_all",    label = "重置预设"},
	}
end

local function build_preset_items()
	local items = {}
	items[#items + 1] = {
		title = "清空当前用户着色器队列",
		icon = "delete_sweep",
		value = "clr",
		bold = true,
		actions = {},
	}
	for i = 1, 3 do
		items[#items + 1] = {
			title = "应用临时配置 " .. i,
			hint = preset_hint(i),
			icon = preset_is_empty(i) and "bookmark_border" or "bookmark",
			value = "preset:" .. i,
			actions = build_preset_actions(i),
			actions_place = "outside",
			separator = (i == 3),
		}
	end
	return items
end

-- =============================================================================
-- =============================================================================

local function scan_directory(dir_path)
	local items = {}

	local dirs = utils.readdir(dir_path, "dirs")
	if dirs then
		sort_entries(dirs)
		for _, dirname in ipairs(dirs) do
			local subdir_path = join(dir_path, dirname)
			local sub_items = scan_directory(subdir_path)
			if #sub_items > 0 then
				items[#items + 1] = {
					title = "📂 " .. dirname .. "/",
					hint = tostring(#sub_items) .. " 项",
					items = sub_items,
					item_actions = shader_item_actions,
					item_actions_place = "outside",
				}
			end
		end
	end

	local files = utils.readdir(dir_path, "files")
	if files then
		sort_entries(files)
		for _, filename in ipairs(files) do
			if should_include_file(filename) then
				local full_path = join(dir_path, filename)
				local mounted = is_shader_mounted(full_path)
				local ext = get_extension(filename)
				local display_name = strip_extension(filename)
				local hint_text = ext and ("." .. ext) or ""

				items[#items + 1] = {
					title = display_name,
					hint = hint_text,
					icon = mounted and "check_box" or "check_box_outline_blank",
					value = full_path,
					active = mounted and 1 or nil,
				}
			end
		end
	end

    return items
end

-- =============================================================================
-- 主菜单
-- =============================================================================

local function build_menu_data()
	local items = build_preset_items()

	local shader_items = scan_directory(shader_base_path)
	if #shader_items == 0 then
		items[#items + 1] = {
			title = "未找到着色器文件",
			hint = shader_base_path,
			selectable = false,
			muted = true,
			icon = "info",
		}
	else
		for _, item in ipairs(shader_items) do
			items[#items + 1] = item
		end
	end

	return {
		type = menu_type,
		title = "用户着色器扩展菜单",
		keep_open = true,
		curtain = false,
		max_items = 15,
		callback = {script_name, "shader-menu-event"},
		item_actions = shader_item_actions,
		item_actions_place = "outside",
		items = items,
		search_submenus = true,
	}
end

-- =============================================================================
-- =============================================================================

local function shader_action(abs_path, action)
	local cmd_path = make_shader_cmd_path(abs_path)
	if action == "set" then
		mp.command('change-list glsl-shaders set "' .. cmd_path .. '"')
		-- msg.info("着色器 独占: " .. cmd_path)
	elseif action == "toggle" then
		mp.command('change-list glsl-shaders toggle "' .. cmd_path .. '"')
		-- msg.info("着色器 切换: " .. cmd_path)
	elseif action == "append" then
		mp.command('change-list glsl-shaders append "' .. cmd_path .. '"')
		-- msg.info("着色器 追加: " .. cmd_path)
	elseif action == "prepend" then
		mp.command('change-list glsl-shaders pre "' .. cmd_path .. '"')
		-- msg.info("着色器 前插: " .. cmd_path)
	elseif action == "remove" then
		mp.command('change-list glsl-shaders remove "' .. cmd_path .. '"')
		-- msg.info("着色器 移除: " .. cmd_path)
	end
end

local function preset_action(index, action)
	if action == "info" then
		mp.commandv("show-text", "配置 " .. index .. ":\n" .. preset_label(index), 3000)
	elseif action == "save" then
		save_preset(index)
		local count = #presets[index].list
		msg.info("保存配置 " .. index .. " (" .. count .. " 项)")
		-- mp.commandv("show-text", "配置 " .. index .. " 已保存 (" .. count .. " 项)", 2000)
	elseif action == "copy" then
		if preset_is_empty(index) then
			mp.commandv("show-text", "配置 " .. index .. " 为空", 2000)
		else
			local ok, err = mp.set_property("clipboard/text", presets[index].str)
			if ok then
				mp.commandv("show-text", "已复制到剪贴板", 2000)
			else
				msg.warn("剪贴板写入失败: " .. tostring(err))
				mp.commandv("show-text", "剪贴板写入失败", 2000)
			end
		end
	elseif action == "clear" then
		presets[index] = {str = "", list = {}}
		if opts.shader_preset_save == "persist" then save_presets_to_file() end
		-- msg.info("清空配置 " .. index)
		-- mp.commandv("show-text", "配置 " .. index .. " 已清空", 2000)
	else
		mp.commandv("change-list", "glsl-shaders", "set", presets[index].str)
		-- msg.info("应用配置 " .. index .. " (" .. #presets[index].list .. " 项)")
		-- mp.commandv("show-text", "已应用配置 " .. index, 2000)
		mp.command('show-text "应用用户着色器队列: \n${glsl-shaders}"')
	end
end

local function update_menu()
	refresh_mounted_shaders()
	local menu_data = build_menu_data()
	local json = utils.format_json(menu_data)
	mp.commandv("script-message-to", "uosc", "update-menu", json)
end

-- =============================================================================
-- =============================================================================

local function open_shader_menu()
	refresh_mounted_shaders()
	local menu_data = build_menu_data()
	local json = utils.format_json(menu_data)
	mp.commandv("script-message-to", "uosc", "open-menu", json, last_submenu_id or "")
end

function handle_shader_menu_event(json)
	if not initialized then return end
	local event = utils.parse_json(json)
	if not event then return end

	if event.type == "activate" then
		local value = event.value
		if not value or value == "" then return end

		last_submenu_id = event.menu_id

		local preset_index = value:match("^preset:(%d+)$")
		if value == "clr" then
			mp.command("change-list glsl-shaders clr \"\"")
			msg.info("清空全部用户着色器")
		elseif preset_index then
			preset_index = tonumber(preset_index)
			preset_action(preset_index, event.action)
		else
			local action = event.action or opts.shader_action_prefer
			shader_action(value, action)
		end
		mp.add_timeout(0.05, update_menu)
	elseif event.type == "back" then
		-- 行为存疑
		last_submenu_id = nil
		mp.commandv("script-message-to", "uosc", "close-menu", menu_type)
	elseif event.type == "close" then
		if event.menu_id and event.menu_id ~= "{root}" then
			last_submenu_id = event.menu_id
		else
			last_submenu_id = nil
		end
	end
end

function handle_uosc_menu_shader(mode)
	if not initialized then return end
	if mode == "root" then last_submenu_id = nil end
	open_shader_menu()
end

-- =============================================================================
-- =============================================================================

function shader_menu_init()
	parse_extensions()
	local dir = opts.shader_dir
	local norm_dir = normalize_path(dir)

	if norm_dir:match("^~~/") or norm_dir:match("^~~\\") or norm_dir == "~~" then
		use_relative_paths = true
		shader_base_path = mp.command_native({"expand-path", dir})
		if not shader_base_path then
			msg.error("无法展开路径: " .. dir)
			return
		end
	else
		use_relative_paths = false
		shader_base_path = dir
	end

	-- msg.info("用户着色器目录: " .. shader_base_path)
	-- msg.info("路径模式: " .. (use_relative_paths and "相对路径 (~~)" or "绝对路径"))

	if opts.shader_preset_save == "persist" then
		load_presets_from_file()
	end

	local info = utils.file_info(shader_base_path)
	if not info or not info.is_dir then
		msg.warn("用户着色器目录不存在: " .. shader_base_path)
	end

	initialized = true
end
