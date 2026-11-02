#!/usr/bin/lua
-- WT6285 eSIM 本地操作：读 EID / 列 profile / 启用 / 禁用
-- 走 AT+CSIM 裸 APDU，不依赖 lpac，不需要联网
-- 用法: esim.lua info|list|enable <ICCID>|disable <ICCID>

local DEV = "/dev/ttyUSB1"
local SELECT_ISDR = "00A4040010A0000005591010FFFFFFFF8900000100"

local function run(cmd)
	local f = io.popen(cmd)
	local out = f:read("*a") or ""
	f:close()
	return out
end

local function bin2hex(s)
	return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end

local function hex2bin(h)
	return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end

-- 发一条 CSIM，返回十六进制应答（含 SW）
local function csim(hex)
	local out = run(string.format(
		"timeout 6 /usr/bin/sms_tool -d %s at 'AT+CSIM=%d,\"%s\"' 2>&1", DEV, #hex, hex))
	return out:match('%+CSIM: %d+,"([0-9A-Fa-f]*)"')
end

-- 收发 APDU，自动处理 61xx 续传；成功返回十六进制数据（不含 SW）
local function transmit(hex)
	local acc = ""
	for _ = 1, 8 do
		local r = csim(hex)
		if not r or #r < 4 then
			return nil, "noresponse"
		end
		local sw = r:sub(-4)
		local body = r:sub(1, #r - 4)
		local sw1 = tonumber(sw:sub(1, 2), 16)
		local sw2 = tonumber(sw:sub(3, 4), 16)

		if sw1 == 0x61 then
			acc = acc .. body
			hex = string.format("00C00000%02X", sw2)
		elseif sw1 == 0x90 and sw2 == 0x00 then
			return acc .. body
		else
			return nil, string.format("SW=%02X%02X", sw1, sw2)
		end
	end
	return nil, "loop"
end

local function select_isdr()
	local d, err = transmit(SELECT_ISDR)
	if not d then return false, err end
	return true
end

---------------------------------------------------------------- TLV

local function parse_tlv(buf, pos)
	local b = buf:byte(pos)
	if not b then return nil end
	local tag
	if b == 0xBF or b == 0x9F or b == 0x5F or b == 0xDF or b == 0x7F then
		tag = buf:sub(pos, pos + 1)
		pos = pos + 2
	else
		tag = buf:sub(pos, pos)
		pos = pos + 1
	end
	local l = buf:byte(pos)
	if not l then return nil end
	pos = pos + 1
	local len
	if l < 0x80 then
		len = l
	elseif l == 0x81 then
		len = buf:byte(pos); pos = pos + 1
	elseif l == 0x82 then
		len = buf:byte(pos) * 256 + buf:byte(pos + 1); pos = pos + 2
	else
		return nil
	end
	return tag, buf:sub(pos, pos + len - 1), pos + len
end

local function children(buf)
	local out = {}
	local pos = 1
	while pos <= #buf do
		local tag, val, nxt = parse_tlv(buf, pos)
		if not tag then break end
		out[#out + 1] = { tag = tag, val = val }
		pos = nxt
	end
	return out
end

-- ICCID 数字串 -> APDU 字节（BCD 半字节交换）
local function iccid_bcd(iccid)
	local out = {}
	for i = 1, #iccid, 2 do
		out[#out + 1] = iccid:sub(i + 1, i + 1) .. iccid:sub(i, i)
	end
	return table.concat(out)
end

---------------------------------------------------------------- 命令

local function get_eid()
	local ok, err = select_isdr()
	if not ok then return nil, err end

	local d, e = transmit("80E2910006BF3E035C015A")
	if not d then return nil, e end
	if os.getenv("ESIM_DEBUG") then print("raw_eid=" .. d) end

	local found
	for _, t in ipairs(children(hex2bin(d))) do
		if bin2hex(t.tag) == "BF3E" then
			for _, c in ipairs(children(t.val)) do
				if bin2hex(c.tag) == "5A" then
					found = bin2hex(c.val)
				end
			end
		end
	end
	if not found then return nil, "noeid" end
	return found
end

local function list_profiles()
	local ok, err = select_isdr()
	if not ok then return nil, err end

	local d, e = transmit("80E2910003BF2D00")
	if not d then return nil, e end
	if os.getenv("ESIM_DEBUG") then print("raw_list=" .. d) end

	local list = {}
	for _, t in ipairs(children(hex2bin(d))) do
		if bin2hex(t.tag) == "BF2D" then
			for _, c in ipairs(children(t.val)) do
				if bin2hex(c.tag) == "A0" then
					for _, p in ipairs(children(c.val)) do
						if bin2hex(p.tag) == "E3" then
							local item = { iccid = "", state = "?", name = "", aid = "" }
							for _, f in ipairs(children(p.val)) do
								if bin2hex(f.tag) == "5A" then
									-- 每个字节内半字节交换
									item.iccid = (bin2hex(f.val):gsub("(..)", function(b)
										return b:sub(2, 2) .. b:sub(1, 1)
									end))
								elseif bin2hex(f.tag) == "4F" then
									item.aid = bin2hex(f.val)
								elseif bin2hex(f.tag) == "9F70" then
									item.state = bin2hex(f.val)
								elseif bin2hex(f.tag) == "90" then
									item.name = f.val
								elseif bin2hex(f.tag) == "92" and item.name == "" then
									item.name = f.val
								end
							end
							list[#list + 1] = item
						end
					end
				end
			end
		end
	end
	return list
end

-- BF31 = EnableProfile, BF32 = DisableProfile
local function set_profile(tag_hex, iccid)
	if not iccid or #iccid < 18 then
		return false, "badiccid"
	end
	local ok, err = select_isdr()
	if not ok then return false, err end

	local bcd = iccid_bcd(iccid)
	local inner = "5A" .. string.format("%02X", #bcd / 2) .. bcd .. "810100"
	local a0 = "A0" .. string.format("%02X", #inner / 2) .. inner
	local der = tag_hex .. string.format("%02X", #a0 / 2) .. a0
	local apdu = "80E29100" .. string.format("%02X", #der / 2) .. der

	local d, e = transmit(apdu)
	if not d then return false, e end
	return true, "9000"
end

---------------------------------------------------------------- 主流程

local action = arg[1] or "info"

if action == "info" then
	local eid, err = get_eid()
	if not eid then
		print("error=" .. tostring(err)); os.exit(1)
	end
	print("eid=" .. eid)

elseif action == "list" then
	local list, err = list_profiles()
	if not list then
		print("error=" .. tostring(err)); os.exit(1)
	end
	print("count=" .. #list)
	for _, p in ipairs(list) do
		print(string.format("p=%s|%s|%s|%s", p.iccid, p.state, p.name, p.aid))
	end

elseif action == "enable" or action == "disable" then
	local tag = (action == "enable") and "BF31" or "BF32"
	local iccid = (arg[2] or ""):gsub("[^0-9A-Fa-f]", "")
	local ok, err = set_profile(tag, iccid)
	print(ok and "result=ok" or ("error=" .. tostring(err)))
	if not ok then os.exit(1) end

	-- 实测：AT+CFUN=1,1 不足以让基带重新附着，必须走 USB 重枚举 + ifup wan
	-- 9>&- 关闭继承来的锁 fd，否则后台重启脚本会与父进程的 flock 死锁
	run("sh -c '/usr/libexec/wt6285/modem-restart.sh --hard >/tmp/wt6285-esim-restart.log 2>&1 9>&- &'")
	print("resetting=hard")

else
	print("usage: esim.lua info|list|enable <ICCID>|disable <ICCID>")
	os.exit(2)
end
