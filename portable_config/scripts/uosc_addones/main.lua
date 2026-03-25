--[[

文档_ uosc_addones.conf

uosc 扩展脚本群组，需要安装脚本 uosc 作为前置依赖。
    子模块:
        menu_shader 用户着色器扩展菜单 - 简化与增强复数项的着色器的调用体验
        element_vcs 网格缩略图扩展菜单 - 预览与跳转

可用的快捷键示例（在 input.conf 中写入）：
 <KEY>   script-message uosc-menu-shader        # 打开着色器扩展菜单
 <KEY>   script-message uosc-menu-shader root   # 始终从根目录打开

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

-- ============================================================================
-- 兼容检查
-- ============================================================================

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

-- ============================================================================
-- 公共工具
-- ============================================================================

script_name = mp.get_script_name()

function normalize_path(p)
	if not p then return "" end
	return p:gsub("\\", "/"):gsub("/+", "/")
end

function path_key(p)
	return normalize_path(p):lower()
end

function get_extension(filename)
	return filename:match("%.([^%.]+)$")
end

function strip_extension(filename)
	return filename:match("^(.+)%.[^%.]+$") or filename
end

function join(base, child)
	return utils.join_path(base, child)
end

function sort_entries(entries)
	table.sort(entries, function(a, b)
		return a:lower() < b:lower()
	end)
end

-- ============================================================================
-- 加载子模块
-- ============================================================================

require("menu_shader")
require("element_vcs")

init = function()
	-- sub: menu_shader
	shader_menu_init()
	mp.register_script_message("shader-menu-event", handle_shader_menu_event)
	mp.register_script_message("uosc-menu-shader", handle_uosc_menu_shader)

	-- sub: vcs
	vcs_init()
	mp.register_script_message("uosc-element-vcs", handle_uosc_element_vcs)
end
