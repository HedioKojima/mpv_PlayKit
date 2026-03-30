--[[

文档_ https://github.com/hooke007/mpv_PlayKit/discussions/669

uosc 扩展脚本群组，需要安装脚本 uosc 作为前置依赖。
  功能性子模块:
    menu_shader  用户着色器扩展菜单 - 简化与增强复数项的着色器的调用体验
    menu_subtext 字幕行跳转扩展菜单 - 提取字幕文本并跳转到指定行
    menu_prop    属性检查器扩展菜单 - 查看与搜索 mpv 属性
    element_vcs  网格缩略图扩展菜单 - 预览与跳转

可用的快捷键示例（在 input.conf 中写入）：
 <KEY>   script-message uosc-menu-shader        # 打开着色器扩展菜单
 <KEY>   script-message uosc-menu-shader root   # 始终从根目录打开

 <KEY>   script-message uosc-menu-subtext       # 打开字幕行扩展菜单

 <KEY>   script-message uosc-menu-prop          # 打开属性检查扩展菜单

 <KEY>   script-message uosc-element-vcs toggle   # 开关VCS视图
 <KEY>   script-message uosc-element-vcs enable
 <KEY>   script-message uosc-element-vcs disable

]]


options = require("mp.options")
utils = require("mp.utils")
msg = require("mp.msg")

opts = {
	load = true,

	-- sub: menu_shader
	shader_dir           = "~~/shaders/",
	shader_exts          = "*,glsl,hook",
	shader_action_prefer = "set",
	shader_preset_save   = "session",
	shader_cache_dir     = "~~/",

	-- sub: subtext
	subtext_merge        = false,

	-- sub: prop
	prop_show_values     = false,
	prop_action_prefer   = "show",

	-- sub: vcs
	vcs_padding          = 30,
	vcs_tiles            = 12,
	vcs_chapter_mode     = false,

}
options.read_options(opts, nil)

if opts.load == false then
	msg.info("脚本已被初始化禁用")
	return
end

function incompat_check(full_str, tar_major, tar_minor, tar_patch)
	if full_str == "unknown" then
		return true
	end

	local clean_ver_str = full_str:gsub("^[^%d]*", "")
	local major, minor, patch = clean_ver_str:match("^(%d+)%.(%d+)%.(%d+)")
	major = tonumber(major)
	minor = tonumber(minor)
	patch = tonumber(patch or 0)
	if major < tar_major then
		return true
	elseif major == tar_major then
		if minor < tar_minor then
			return true
		elseif minor == tar_minor then
			if patch < tar_patch then
				return true
			end
		end
	end

	return false
end

-- =============================================================================
-- 兼容检查
-- =============================================================================

-- 原因：首个将gpu-next作为首选vo的版本
local min_major = 0
local min_minor = 41
local min_patch = 0
local mpv_ver_curr = mp.get_property_native("mpv-version", "unknown")
if incompat_check(mpv_ver_curr, min_major, min_minor, min_patch) then
	msg.warn("当前mpv版本 (" .. (mpv_ver_curr or "未知") .. ") 低于 " .. min_major .. "." .. min_minor .. "." .. min_patch .. "，已终止脚本。")
	return
end

-- uosc 版本检查
local uosc_min_major = 5
local uosc_min_minor = 12
local uosc_min_patch = 1
local uosc_ready = false
local init
mp.register_script_message("uosc-version", function(version)
	if uosc_ready then return end
	if incompat_check(version, uosc_min_major, uosc_min_minor, uosc_min_patch) then
		msg.warn("uosc版本 (" .. version .. ") 低于 " .. uosc_min_major .. "." .. uosc_min_minor .. "." .. uosc_min_patch .. "，已终止脚本。")
		return
	end
	uosc_ready = true
	init()
end)

-- =============================================================================
-- 加载子模块
-- =============================================================================

script_name = mp.get_script_name()

require("helper")
require("menu_shader")
require("menu_subtext")
require("menu_prop")
require("element_vcs")

init = function()
	-- sub: menu_shader
	shader_menu_init()
	mp.register_script_message("shader-menu-event", handle_shader_menu_event)
	mp.register_script_message("uosc-menu-shader", handle_uosc_menu_shader)

	-- sub: menu_subtext
	subtext_menu_init()
	mp.register_script_message("subtext-menu-event", handle_subtext_menu_event)
	mp.register_script_message("uosc-menu-subtext", handle_uosc_menu_subtext)

	-- sub: menu_prop
	prop_menu_init()
	mp.register_script_message("prop-menu-event", handle_prop_menu_event)
	mp.register_script_message("uosc-menu-prop", handle_uosc_menu_prop)

	-- sub: vcs
	vcs_init()
	mp.register_script_message("uosc-element-vcs", handle_uosc_element_vcs)
end
