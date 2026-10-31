module("luci.controller.wt6285", package.seeall)

function index()
	if not nixio.fs.access("/usr/libexec/wt6285/status.sh") then
		return
	end

	entry({"admin", "modem", "wt6285"}, firstchild(), _("WT6285 模块"), 60).dependent = false
	entry({"admin", "modem", "wt6285", "status"}, template("wt6285/status"), _("状态"), 10)
	entry({"admin", "modem", "wt6285", "sim"}, cbi("wt6285/sim"), _("SIM 选择"), 20)
	entry({"admin", "modem", "wt6285", "esim"}, template("wt6285/esim"), _("eSIM"), 30)
	entry({"admin", "modem", "wt6285", "sms"}, template("wt6285/sms"), _("短信"), 40)
	entry({"admin", "modem", "wt6285", "settings"}, cbi("wt6285/settings"), _("设置"), 50)
end
