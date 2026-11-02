module("luci.controller.wt6285", package.seeall)

local function shquote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- AT 指令控制台：逐行执行，带 6 秒超时
function action_at()
	local cmd = luci.http.formvalue("cmd") or ""
	cmd = cmd:gsub("\r\n", "\n"):gsub("\r", "\n")

	local lines = {}
	for line in cmd:gmatch("[^\n]+") do
		local s = line:match("^%s*(.-)%s*$")
		if #s > 0 then lines[#lines + 1] = s end
	end

	local out = {}
	for _, l in ipairs(lines) do
		local res = luci.sys.exec("timeout 6 /usr/libexec/wt6285/at.sh " .. shquote(l) .. " 2>&1") or ""
		res = res:gsub("%s+$", "")
		out[#out + 1] = "=== " .. l .. " ==="
		out[#out + 1] = (#res > 0) and res or "(无输出)"
		out[#out + 1] = ""
	end

	luci.template.render("wt6285/at", {
		cmd = cmd,
		output = table.concat(out, "\n")
	})
end

function index()
	if not nixio.fs.access("/usr/libexec/wt6285/status.sh") then
		return
	end

	entry({"admin", "modem"}, firstchild(), _("移远模块"), 60).dependent = false
	entry({"admin", "modem", "wt6285"}, firstchild(), _("WT6285"), 10).dependent = false
	entry({"admin", "modem", "wt6285", "status"}, template("wt6285/status"), _("状态"), 10)
	entry({"admin", "modem", "wt6285", "sim"}, cbi("wt6285/sim"), _("SIM 选择"), 20)
	entry({"admin", "modem", "wt6285", "esim"}, template("wt6285/esim"), _("eSIM"), 30)
	entry({"admin", "modem", "wt6285", "sms"}, template("wt6285/sms"), _("短信"), 40)
	entry({"admin", "modem", "wt6285", "at"}, call("action_at"), _("AT 指令"), 45)
	entry({"admin", "modem", "wt6285", "settings"}, cbi("wt6285/settings"), _("设置"), 50)
end
