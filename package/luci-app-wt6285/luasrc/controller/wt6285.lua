module("luci.controller.wt6285", package.seeall)

local function shquote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- eSIM：启用/禁用 profile（本机发 APDU，不联网）
function action_esim()
	local act = luci.http.formvalue("act") or ""
	local iccid = (luci.http.formvalue("iccid") or ""):gsub("[^0-9]", "")

	if (act == "enable" or act == "disable") and #iccid >= 18 then
		luci.sys.exec(string.format(
			"flock -x /var/lock/wt6285-at.lock lua /usr/libexec/wt6285/esim.lua %s %s >/tmp/wt6285-esim.log 2>&1",
			act, iccid))
	end

	luci.template.render("wt6285/esim")
end

-- 旧入口跳转到「工具」下的标签页
function action_redirect_at() luci.http.redirect(luci.dispatcher.build_url("admin/modem/wt6285/tools/at")) end
function action_redirect_sms() luci.http.redirect(luci.dispatcher.build_url("admin/modem/wt6285/tools/sms")) end
function action_redirect_sim() luci.http.redirect(luci.dispatcher.build_url("admin/modem/wt6285/tools/sim")) end
function action_redirect_settings() luci.http.redirect(luci.dispatcher.build_url("admin/modem/wt6285/tools/settings")) end

-- AT 指令控制台：逐行执行，超时可按需调整（默认 10 秒）
function action_at()
	local cmd = luci.http.formvalue("cmd") or ""
	cmd = cmd:gsub("\r\n", "\n"):gsub("\r", "\n")

	local tmo = tonumber(luci.http.formvalue("tmo") or "") or 10
	if tmo < 3 then tmo = 3 end
	if tmo > 30 then tmo = 30 end

	local lines = {}
	for line in cmd:gmatch("[^\n]+") do
		local s = line:match("^%s*(.-)%s*$")
		if #s > 0 then lines[#lines + 1] = s end
	end

	-- 当前 AT 口与实际存在的串口，便于排查"口选错了"
	local atdev = (luci.sys.exec("uci -q get lpac.main.at_device") or ""):gsub("%s+$", "")
	local ports = (luci.sys.exec("ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | tr '\\n' ' '") or ""):gsub("%s+$", "")
	-- luci.fs 在新版 LuCI 里不存在，直接调它会整页 500；用 shell 判断字符设备。
	local atdev_ok = (atdev ~= "" and luci.sys.call("test -c " .. atdev) == 0)

	local out = {}
	local t0 = os.time()
	for _, l in ipairs(lines) do
		local started = os.clock()
		local res = luci.sys.exec(string.format("timeout %d /usr/libexec/wt6285/at.sh %s 2>&1", tmo, shquote(l))) or ""
		local cost = string.format("%.1f", os.clock() - started)
		res = res:gsub("%s+$", "")
		out[#out + 1] = string.format("=== %s === [%ss]", l, cost)
		out[#out + 1] = (#res > 0) and res or "(无输出)"
		out[#out + 1] = ""
	end

	luci.template.render("wt6285/at", {
		cmd = cmd,
		output = table.concat(out, "\n"),
		tmo = tmo,
		atdev = atdev,
		atdev_ok = atdev_ok,
		ports = ports
	})
end

-- 重启 4G 模块（后台执行，页面立即返回）
function action_restart()
	luci.sys.call("/usr/libexec/wt6285/modem-restart.sh >/tmp/wt6285-restart.log 2>&1 &")
	luci.http.redirect(luci.dispatcher.build_url("admin/modem/wt6285/status") .. "?restarted=1")
end

-- 硬复位：USB authorized 0/1，强制重新枚举
function action_restart_hard()
	luci.sys.call("/usr/libexec/wt6285/modem-restart.sh --hard >/tmp/wt6285-restart.log 2>&1 &")
	luci.http.redirect(luci.dispatcher.build_url("admin/modem/wt6285/status") .. "?restarted=hard")
end

function index()
	if not nixio.fs.access("/usr/libexec/wt6285/status.sh") then
		return
	end

	entry({"admin", "modem"}, firstchild(), _("移远模块"), 60).dependent = false
	entry({"admin", "modem", "wt6285"}, firstchild(), _("WT6285"), 10).dependent = false

	-- 两个独立页：状态、eSIM
	entry({"admin", "modem", "wt6285", "status"}, template("wt6285/status"), _("状态"), 10)
	entry({"admin", "modem", "wt6285", "esim"}, call("action_esim"), _("eSIM"), 20)

	-- 其余收进「工具」，作为标签页
	-- 用入口页而不是 firstchild 标签栏：LuCI 对 template/call/cbi 子节点
	-- 的标签渲染不稳定，实测只显示第一个子页，所以改成卡片入口
	entry({"admin", "modem", "wt6285", "tools"}, template("wt6285/tools"), _("工具"), 30)
	entry({"admin", "modem", "wt6285", "tools", "sim"}, cbi("wt6285/sim"), _("SIM 选择"), 10).leaf = true
	entry({"admin", "modem", "wt6285", "tools", "sms"}, template("wt6285/sms"), _("短信"), 20).leaf = true
	entry({"admin", "modem", "wt6285", "tools", "at"}, call("action_at"), _("AT 指令"), 30).leaf = true
	entry({"admin", "modem", "wt6285", "tools", "settings"}, cbi("wt6285/settings"), _("设置"), 40).leaf = true

	-- 重启动作（不显示在菜单里）
	entry({"admin", "modem", "wt6285", "restart"}, call("action_restart"))
	entry({"admin", "modem", "wt6285", "restart-hard"}, call("action_restart_hard"))

	-- 旧路径跳转：老的 /wt6285/at、/sms、/sim、/settings 书签不能失效
	entry({"admin", "modem", "wt6285", "at"}, call("action_redirect_at")).leaf = true
	entry({"admin", "modem", "wt6285", "sms"}, call("action_redirect_sms")).leaf = true
	entry({"admin", "modem", "wt6285", "sim"}, call("action_redirect_sim")).leaf = true
	entry({"admin", "modem", "wt6285", "settings"}, call("action_redirect_settings")).leaf = true
end
