#!/usr/bin/env lua
-- eSIM 操作后端
--
-- 2026-11-06 实测修正：EC200A 不支持 AT+CSIM（+CME ERROR: 4），
-- 但支持 AT+CCHO/CGLA/CCHC 逻辑通道。因此这里优先走 lpac（AT 后端），
-- 通过 /usr/bin/lpac-at 调用——它会先停掉占用 AT 口的 wt6285 服务、
-- 按当前 USB 组成自动选口、跑完再拉回服务。
--
-- 保留 CSIM 分支作为旧固件/其他模组的兜底。

local DEV = os.getenv("WT6285_AT_PORT") or "/dev/ttyUSB1"
local LPAC_AT = "/usr/bin/lpac-at"

local function run(cmd)
	local f = io.popen(cmd .. " 2>&1")
	if not f then return "" end
	local out = f:read("*a") or ""
	f:close()
	return out
end

local function have_lpac()
	return run("test -x " .. LPAC_AT .. " && echo yes"):match("yes") ~= nil
end

-- ---------------------------------------------------------------- lpac 路径

local function lpac_json(args)
	local out = run(LPAC_AT .. " " .. args)
	-- 输出形如 {"type":"lpa","payload":{"code":0,"message":"success","data":...}}
	if not out:match('"code":0') then
		local msg = out:match('"message":"([^"]*)"') or "lpac_failed"
		return nil, msg
	end
	return out
end

local function lpac_eid()
	local out, err = lpac_json("chip info")
	if not out then return nil, err end
	local eid = out:match('"eidValue":"([0-9A-Fa-f]+)"')
	if not eid then return nil, "no_eid" end
	return eid
end

local function lpac_profiles()
	local out, err = lpac_json("profile list")
	if not out then return nil, err end
	local list = {}
	-- 逐个对象抓取：以 {"iccid": 开头，到 } 结束（字段内无嵌套对象）
	for obj in out:gmatch('(%{"iccid":[^}]*%})') do
		local function field(k)
			return obj:match('"' .. k .. '":"([^"]*)"')
		end
		local iccid = field("iccid")
		if iccid then
			list[#list + 1] = {
				iccid = iccid,
				state = field("profileState") or "",
				name  = field("profileNickname") or field("profileName") or "",
				spn   = field("serviceProviderName") or "",
				aid   = field("isdpAid") or "",
				class = field("profileClass") or "",
			}
		end
	end
	return list
end

local function lpac_set(action, iccid)
	local verb = (action == "enable") and "enable" or "disable"
	local out, err = lpac_json("profile " .. verb .. " " .. iccid)
	if not out then return false, err end
	return true, "ok"
end

-- ---------------------------------------------------------------- CSIM 兜底

local function bin2hex(s)
	return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end

local function hex2bin(h)
	return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end

local function csim(hex)
	local out = run(string.format("timeout 6 /usr/bin/sms_tool -d %s at 'AT+CSIM=%d,\"%s\"'",
		DEV, #hex, hex))
	return out:match('%+CSIM: %d+,"([0-9A-Fa-f]*)"')
end

local function transmit(hex)
	local r = csim(hex)
	if not r then return nil, "no_response" end
	local sw = r:sub(-4)
	local body = r:sub(1, -5)
	if sw == "9000" or sw:sub(1, 2) == "61" then
		return body, sw
	end
	return nil, "sw_" .. sw
end

local function select_isdr()
	local _, sw = transmit("00A4040007A0000005591010")
	if sw == "9000" or (sw and sw:sub(1, 2) == "61") then return true end
	return false, "isdr_" .. tostring(sw)
end

local function get_eid_csim()
	local ok, err = select_isdr()
	if not ok then return nil, err end
	local d = transmit("00CA004F00")
	if not d then return nil, "eid_read_failed" end
	-- BF20 容器内第 2 个 TLV 即 EID
	local i = d:find("BF20")
	if not i then return nil, "no_bf20" end
	local p = i + 4
	local eid = ""
	while p <= #d do
		local tag, len, vstart = d:sub(p, p + 1), tonumber(d:sub(p + 2, p + 3), 16), p + 4
		if not len then break end
		local val = d:sub(vstart, vstart + len * 2 - 1)
		if tag:upper() == "5A" then eid = val break end
		p = vstart + len * 2
	end
	return (#eid > 0) and eid or nil, "eid_parse"
end

-- ---------------------------------------------------------------- 主流程

local action = arg[1] or "info"

if action == "info" then
	local eid, err
	if have_lpac() then
		eid, err = lpac_eid()
	else
		eid, err = get_eid_csim()
	end
	if not eid then
		print("error=" .. tostring(err))
		os.exit(1)
	end
	print("eid=" .. eid)

elseif action == "list" then
	local list, err
	if have_lpac() then
		list, err = lpac_profiles()
	else
		list, err = nil, "lpac_missing"
	end
	if not list then
		print("error=" .. tostring(err))
		os.exit(1)
	end
	print("count=" .. #list)
	for _, p in ipairs(list) do
		print(string.format("p=%s|%s|%s|%s", p.iccid, p.state, p.name, p.aid))
	end

elseif action == "enable" or action == "disable" then
	local iccid = (arg[2] or ""):gsub("[^0-9A-Fa-f]", "")
	if #iccid < 18 then
		print("error=badiccid")
		os.exit(1)
	end

	local ok, err
	if have_lpac() then
		ok, err = lpac_set(action, iccid)
	else
		ok, err = false, "lpac_missing"
	end

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
