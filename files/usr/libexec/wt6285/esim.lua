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

-- ---------------------------------------------------------------- 结果缓存
--
-- lpac 一次完整读取约 13 秒（停服务 + 清通道 + APDU），页面要 info+list 两次，
-- 叠加 smsd 每分钟抢同一把锁，很容易超过 uhttpd 的 script_timeout(60)，
-- 浏览器表现就是"页面打不开"。这里做 15 分钟缓存：
--   命中 → 立即返回；过期 → 先返回旧结果，再后台刷新。

local CACHE_TTL = 900

local function cache_path(action)
	return "/tmp/wt6285-esim-" .. action .. ".out"
end

local function read_file(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local c = f:read("*a")
	f:close()
	return c
end

local function write_file(p, c)
	local f = io.open(p, "w")
	if f then f:write(c) f:close() end
end

local function cache_age(p)
	local t = tonumber(run("stat -c %Y " .. p .. " 2>/dev/null") or "")
	local now = tonumber(run("date +%s") or "")
	if not t or not now then return nil end
	return now - t
end

local function last_lpa(out)
	local final = ""
	for line in out:gmatch("[^\n]+") do
		if line:match('"type":"lpa"') then final = line end
	end
	return final
end

-- ---------------------------------------------------------------- 操作日志
-- 页面要能看到"做了什么、结果如何"，否则出问题只能靠 SSH 翻现场。
local LOGF = "/root/wt6285-esim.log"

local function trim_log()
	-- 落盘在 /root，按大小轮转，避免长期运行把 flash 写满
	local sz = tonumber((run("stat -c %s " .. LOGF .. " 2>/dev/null") or ""):match("%d+") or "")
	if sz and sz > 65536 then
		run("mv " .. LOGF .. " " .. LOGF .. ".1 2>/dev/null")
	end
end

local function logline(msg)
	local ts = (run("date '+%m-%d %H:%M:%S'") or ""):gsub("%s+$", "")
	local f = io.open(LOGF, "a")
	if f then
		f:write(string.format("[%s] %s\n", ts, msg))
		f:close()
	end
	trim_log()
end

-- ---------------------------------------------------------------- 业务互斥
-- AT 口有 flock 串行化，但两个业务动作仍会互相覆盖（例如同时启用两个 profile）。
-- 用 mkdir 做原子锁，10 分钟视为陈旧自动清理。
local BUSY = "/var/lock/wt6285-esim.busy"
local LOCKED = false

local function read_lock_ts()
	local f = io.open(BUSY .. "/ts", "r")
	if not f then return nil end
	local line = f:read("*l")
	f:close()
	return tonumber((line or ""):match("^%s*(%d+)"))
end

local function lock_acquire()
	-- 两个坑（都实测踩过）：
	--  1. busybox 的 `stat -c %Y` 返回 0，按 mtime 判陈旧会把新锁当过期删掉
	--  2. 用 shell `cat` 读不存在的 ts，错误信息里的路径含 "wt6285"，
	--     被 match("%d+") 抓成时间戳 6285 → 永远判过期 → 锁形同虚设
	-- 所以时间戳只用 Lua 读文件，超时判断用 os.time()。
	local exists = (run("test -d " .. BUSY .. " >/dev/null 2>&1 && echo yes") or ""):match("yes")
	if exists then
		local ts = read_lock_ts()
		if not (ts and (os.time() - ts) > 600) then
			return false
		end
		run("rm -rf " .. BUSY)
	end
	if (run("mkdir " .. BUSY .. " >/dev/null 2>&1 && echo ok") or ""):match("ok") then
		local f = io.open(BUSY .. "/ts", "w")
		if f then f:write(tostring(os.time())) f:close() end
		LOCKED = true
		return true
	end
	return false
end

local function lock_release()
	if LOCKED then
		run("rm -rf " .. BUSY)
		LOCKED = false
	end
end

local function finish(code)
	lock_release()
	os.exit(code or 0)
end

local function shq(x)
	return "'" .. tostring(x):gsub("'", "'\\''") .. "'"
end

local function have_lpac()
	return run("test -x " .. LPAC_AT .. " && echo yes"):match("yes") ~= nil
end

-- ---------------------------------------------------------------- lpac 路径

local function clear_channels()
	local dev = (run("uci -q get lpac.main.at_device") or ""):gsub("%s+$", "")
	if dev == "" then dev = "/dev/ttyACM1" end
	for n = 1, 7 do
		run(string.format("sms_tool -d %s at \"AT+CCHC=%d\" >/dev/null 2>&1", dev, n))
	end
end

local function lpac_json(args)
	local out = run(LPAC_AT .. " " .. args)
	-- 刷机/复位后首次调用必现 euicc_init（卡还在初始化 + 启动阶段残留通道）。
	-- 这里清一遍通道、等 2 秒重试一次，避免每次开机都要人工介入。
	if out:match("euicc_init") then
		clear_channels()
		run("sleep 2")
		out = run(LPAC_AT .. " " .. args)
	end
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
			-- luci 模板按 01/00 判断启用状态（ASN.1 ProfileState 口径），
			-- 而 lpac 返回的是 enabled/disabled 字符串，这里统一转换，
			-- 否则页面一律显示"已禁用"。
			local st = field("profileState") or ""
			if st == "enabled" then
				st = "01"
			elseif st == "disabled" then
				st = "00"
			end
			list[#list + 1] = {
				iccid = iccid,
				state = st,
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
	logline(action .. " " .. iccid)
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
local FORCE = (arg[2] == "--refresh")

-- 命中缓存直接返回；过期则先回旧值、再后台刷新（页面永不干等 lpac）
local function serve_cache(act)
	local cp = cache_path(act)
	local age = cache_age(cp)
	local data = read_file(cp)
	if not data or #data == 0 then return false end
	if FORCE then return false end
	io.write(data)
	if age and age >= CACHE_TTL then
		run("setsid sh -c '/usr/libexec/wt6285/esim.lua " .. act .. " --refresh >/dev/null 2>&1' >/dev/null 2>&1 &")
	end
	return true
end

if (action == "info" or action == "list" or action == "notif-list") and serve_cache(action) then
	finish(0)
end

-- 变更类动作串行化：拿不到锁直接返回 busy，不排队
local mutation = (action == "download" or action == "delete" or action == "rename"
	or action == "enable" or action == "disable"
	or action == "notif-send" or action == "notif-remove" or action == "notif-process")
if mutation and not lock_acquire() then
	print("error=busy")
	finish(1)
end

if action == "info" then
	local eid, err
	if have_lpac() then
		eid, err = lpac_eid()
	else
		eid, err = get_eid_csim()
	end
	if not eid then
		print("error=" .. tostring(err))
		finish(1)
	end
	local out = "eid=" .. eid
	print(out)
	write_file(cache_path("info"), out)

elseif action == "list" then
	local list, err
	if have_lpac() then
		list, err = lpac_profiles()
	else
		list, err = nil, "lpac_missing"
	end
	if not list then
		print("error=" .. tostring(err))
		finish(1)
	end
	local buf = {"count=" .. #list}
	for _, p in ipairs(list) do
		buf[#buf + 1] = string.format("p=%s|%s|%s|%s", p.iccid, p.state, p.name, p.aid)
	end
	local out = table.concat(buf, "\n") .. "\n"
	print(out)
	write_file(cache_path("list"), out)

elseif action == "download" then
	-- lpac profile download -s <smdp+> -m <激活码> [-c <确认码>]
	local smdp = arg[2] or ""
	local ac   = arg[3] or ""
	local cc   = arg[4] or ""
	if smdp == "" or ac == "" then
		print("error=missing_params")
		finish(1)
	end
	-- 激活码属于凭据，日志只留前 4 位
	local ac_mask = (#ac > 4) and (ac:sub(1, 4) .. "***") or "***"
	logline("download 请求 smdp=" .. smdp .. " ac=" .. ac_mask)
	local cmd = "profile download -s " .. shq(smdp) .. " -m " .. shq(ac)
	if cc ~= "" then cmd = cmd .. " -c " .. shq(cc) end
	local out = run(LPAC_AT .. " " .. cmd)
	-- 只看最后一条 type=lpa 的终态：progress 事件里也带 "code":0，
	-- 用全局匹配会把"连接失败"误判成成功（实测不可达 SM-DP+ 曾返回 result=ok）。
	local final = ""
	for line in out:gmatch("[^\n]+") do
		if line:match('"type":"lpa"') then final = line end
	end
	if final ~= "" and final:match('"code":0') then
		run("rm -f /tmp/wt6285-esim-*.out")   -- 清缓存，页面直接看到新 profile
		logline("download 成功")
		print("result=ok")
	else
		local src = (final ~= "") and final or out
		local msg = src:match('"message":"([^"]*)"') or "download_failed"
		local dat = src:match('"data":"([^"]*)"') or ""
		logline("download 失败 " .. msg .. (dat ~= "" and (":" .. dat) or ""))
		print("error=" .. msg .. (dat ~= "" and (":" .. dat) or ""))
		finish(1)
	end

elseif action == "delete" then
	local iccid = (arg[2] or ""):gsub("[^0-9A-Fa-f]", "")
	if #iccid < 18 then
		print("error=badiccid")
		finish(1)
	end
	logline("delete " .. iccid)
	local out = run(LPAC_AT .. " profile delete " .. shq(iccid))
	local final = last_lpa(out)
	if final ~= "" and final:match('"code":0') then
		run("rm -f /tmp/wt6285-esim-*.out")
		print("result=ok")
	else
		local src = (final ~= "") and final or out
		print("error=" .. (src:match('"message":"([^"]*)"') or "delete_failed"))
		finish(1)
	end

elseif action == "rename" then
	-- lpac profile nickname <iccid> <new_name>
	local iccid = (arg[2] or ""):gsub("[^0-9A-Fa-f]", "")
	local name  = arg[3] or ""
	if #iccid < 18 then
		print("error=badiccid")
		finish(1)
	end
	if name == "" then
		print("error=emptyname")
		finish(1)
	end
	logline("rename " .. iccid .. " → " .. name)
	local out = run(LPAC_AT .. " profile nickname " .. shq(iccid) .. " " .. shq(name))
	local final = last_lpa(out)
	if final ~= "" and final:match('"code":0') then
		run("rm -f /tmp/wt6285-esim-*.out")
		print("result=ok")
	else
		local src = (final ~= "") and final or out
		print("error=" .. (src:match('"message":"([^"]*)"') or "rename_failed"))
		finish(1)
	end

elseif action == "notif-send" then
	-- lpac notification process <seq>：单条提交，处理完通知仍保留（不自动删）
	local seq = (arg[2] or ""):gsub("[^0-9]", "")
	if seq == "" then
		print("error=badseq")
		finish(1)
	end
	logline("notif-send seq=" .. seq)
	local out = run(LPAC_AT .. " notification process " .. seq)
	local final = last_lpa(out)
	if final ~= "" and final:match('"code":0') then
		run("rm -f /tmp/wt6285-esim-notif-list.out")
		logline("notif-send seq=" .. seq .. " 成功")
		print("result=ok")
	else
		local src = (final ~= "") and final or out
		local msg = src:match('"message":"([^"]*)"') or "notif_send_failed"
		logline("notif-send seq=" .. seq .. " 失败 " .. msg)
		print("error=" .. msg)
		finish(1)
	end

elseif action == "notif-remove" then
	-- lpac notification remove <seqNumber>
	local seq = (arg[2] or ""):gsub("[^0-9]", "")
	if seq == "" then
		print("error=badseq")
		finish(1)
	end
	logline("notif-remove seq=" .. seq)
	local out = run(LPAC_AT .. " notification remove " .. seq)
	local final = last_lpa(out)
	if final ~= "" and final:match('"code":0') then
		run("rm -f /tmp/wt6285-esim-notif-list.out")
		print("result=ok")
	else
		local src = (final ~= "") and final or out
		print("error=" .. (src:match('"message":"([^"]*)"') or "notif_remove_failed"))
		finish(1)
	end

elseif action == "notif-list" then
	local out = run(LPAC_AT .. " notification list")
	local final = last_lpa(out)
	if final == "" or not final:match('"code":0') then
		local src = (final ~= "") and final or out
		print("error=" .. (src:match('"message":"([^"]*)"') or "notif_failed"))
		finish(1)
	end
	-- 逐条抓 seqNumber / event / iccid（对象内无嵌套）
	local n = 0
	local buf = {}
	for obj in final:gmatch("(%{[^{}]*seqNumber[^{}]*%})") do
		local seq = obj:match('"seqNumber":(%d+)') or "?"
		-- lpac 实际字段名是 profileManagementOperation（install/enable/disable/delete），
		-- 不是 event；按错名字解析会全部显示成 "?"。
		local ev  = obj:match('"profileManagementOperation":"([^"]*)"')
			or obj:match('"event":"([^"]*)"') or "?"
		local ic  = obj:match('"iccid":"([0-9A-Fa-f]*)"') or ""
		n = n + 1
		buf[#buf + 1] = string.format("n=%s|%s|%s", seq, ev, ic)
	end
	buf[#buf + 1] = "count=" .. n
	local out_s = table.concat(buf, "\n") .. "\n"
	print(out_s)
	write_file(cache_path("notif-list"), out_s)

elseif action == "notif-process" then
	-- 注意：只提交，不删除。删不删由使用者逐条决定。
	logline("notif-process 全部")
	local out = run(LPAC_AT .. " notification process")
	local final = last_lpa(out)
	if final ~= "" and final:match('"code":0') then
		run("rm -f /tmp/wt6285-esim-notif-list.out")
		print("result=ok")
	else
		local src = (final ~= "") and final or out
		print("error=" .. (src:match('"message":"([^"]*)"') or "notif_process_failed"))
		finish(1)
	end

elseif action == "enable" or action == "disable" then
	local iccid = (arg[2] or ""):gsub("[^0-9A-Fa-f]", "")
	if #iccid < 18 then
		print("error=badiccid")
		finish(1)
	end

	local ok, err
	if have_lpac() then
		ok, err = lpac_set(action, iccid)
	else
		ok, err = false, "lpac_missing"
	end

	print(ok and "result=ok" or ("error=" .. tostring(err)))
	if not ok then
		logline(action .. " " .. iccid .. " 失败 " .. tostring(err))
		finish(1)
	end
	logline(action .. " " .. iccid .. " 成功")
	-- 启用/禁用会改变 profileState，必须让缓存失效，
	-- 否则页面最长 15 分钟仍显示旧状态
	run("rm -f /tmp/wt6285-esim-list.out /tmp/wt6285-esim-notif-list.out")

	-- 实测：AT+CFUN=1,1 不足以让基带重新附着，必须走 USB 重枚举 + ifup wan
	-- 9>&- 关闭继承来的锁 fd，否则后台重启脚本会与父进程的 flock 死锁
	run("sh -c '/usr/libexec/wt6285/modem-restart.sh --hard >/tmp/wt6285-esim-restart.log 2>&1 9>&- &'")
	print("resetting=hard")

else
	print("usage: esim.lua info|list|enable <ICCID>|disable <ICCID>")
	finish(2)
end
