--[[

辅助函数 — uosc_addones 子模块

]]


-- =============================================================================
-- 路径
-- =============================================================================

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

-- =============================================================================
-- 字符串
-- =============================================================================

-- 将任意值序列化为可读字符串
function stringify(v)
	if v == nil then return "nil" end
	if type(v) == "table" then return utils.format_json(v) or tostring(v) end
	return tostring(v)
end

-- UTF-8 安全截断
function utf8_truncate(s, max_bytes)
	if #s <= max_bytes then return s end
	local pos = max_bytes
	while pos > 0 and s:byte(pos) >= 0x80 and s:byte(pos) < 0xC0 do
		pos = pos - 1
	end
	if pos > 0 and s:byte(pos) >= 0xC0 then
		pos = pos - 1
	end
	return s:sub(1, pos)
end

-- 截断并追加省略号（字节阈值，默认 64/61）
function truncate_hint(s, threshold, cut)
	threshold = threshold or 64
	cut = cut or (threshold - 3)
	if #s <= threshold then return s end
	return utf8_truncate(s, cut) .. "..."
end

-- 格式化时间戳
function format_time(seconds, use_hours)
	if not seconds or seconds < 0 then seconds = 0 end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	if use_hours then
		return string.format("%d:%02d:%02d", h, m, s)
	else
		return string.format("%d:%02d", m, s)
	end
end
