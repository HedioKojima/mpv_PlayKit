--[[

属性检查扩展菜单 — uosc_addones 子模块

]]


local menu_type = "k7prop"
local initialized = false
local cached_names = nil

local extra_props = {
	"current-tracks/audio",
	"current-tracks/video",
	"current-tracks/sub",
	"current-tracks/sub2",
}

-- =============================================================================
-- =============================================================================

local function get_prop_names()
	if cached_names then return cached_names end

	local names = mp.get_property_native("property-list", {})
	for _, ep in ipairs(extra_props) do
		names[#names + 1] = ep
	end
	table.sort(names)

	cached_names = names
	return names
end

local function build_items()
	local names = get_prop_names()
	local show_values = opts.prop_show_values
	local items = {}

	if show_values then
		local msg_level_backup = mp.get_property("msg-level")
		mp.set_property("msg-level",
			msg_level_backup == "" and "cplayer=no"
			or msg_level_backup .. ",cplayer=no")

		for _, name in ipairs(names) do
			local val = stringify(mp.get_property_native(name))
			if #val > 64 then val = truncate_hint(val) end
			items[#items + 1] = {
				title = name,
				hint = val,
				value = name,
			}
		end

		mp.set_property("msg-level", msg_level_backup)
	else
		for _, name in ipairs(names) do
			items[#items + 1] = {
				title = name,
				value = name,
			}
		end
	end

	return items
end

-- =============================================================================
-- 菜单
-- =============================================================================

local prop_actions = {
	{name = "copy", icon = "content_copy", label = "复制属性名与值"},
	{name = "show", icon = "visibility",   label = "OSD 显示完整值"},
}

local function build_menu_data()
	local items = build_items()
	return {
		type = menu_type,
		title = "属性检查扩展菜单",
		hint = tostring(#items) .. " 项",
		search_style = "palette",
		search_submenus = false,
		curtain = false,
		callback = {script_name, "prop-menu-event"},
		item_actions = prop_actions,
		item_actions_place = "outside",
		items = items,
	}
end

-- =============================================================================
-- =============================================================================

function handle_prop_menu_event(json_str)
	if not initialized then return end
	local event = utils.parse_json(json_str)
	if not event then return end

	if event.type == "activate" then
		local prop_key = event.value
		if type(prop_key) ~= "string" then return end

		local action = event.action or opts.prop_action_prefer

		local msg_level_backup = mp.get_property("msg-level")
		mp.set_property("msg-level",
			msg_level_backup == "" and "cplayer=no"
			or msg_level_backup .. ",cplayer=no")

		local val = stringify(mp.get_property_native(prop_key))

		mp.set_property("msg-level", msg_level_backup)

		if action == "copy" then
			mp.set_property("clipboard/text", prop_key .. " = " .. val)
			mp.osd_message("已复制: " .. prop_key, 2)

		else -- "show" 或默认行为
			local display = prop_key .. " = " .. val
			if #display > 100 then
				mp.commandv("expand-properties", "show-text",
					"${osd-ass-cc/0}{\\fs9}${osd-ass-cc/1}" .. display, "8000")
			else
				mp.commandv("show-text", display, "8000")
			end
		end
	end
end

function handle_uosc_menu_prop()
	if not initialized then return end
	local menu_data = build_menu_data()
	local json_str = utils.format_json(menu_data)
	mp.commandv("script-message-to", "uosc", "open-menu", json_str)
end

local function on_file_change()
	mp.commandv("script-message-to", "uosc", "close-menu", menu_type)
end

function prop_menu_init()
	initialized = true
	mp.register_event("file-loaded", on_file_change)
end
