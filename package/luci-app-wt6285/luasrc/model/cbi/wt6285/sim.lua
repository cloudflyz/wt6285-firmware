local m, s, o

m = Map("ec200a", translate("SIM 选择"), translate("切换外置卡与内置 SIM，切换后会复位模块。"))

s = m:section(TypedSection, "ec200a", "")
s.anonymous = true

o = s:option(ListValue, "sim_sel", translate("当前 SIM"))
o:value("0", translate("外置 SIM 卡"))
o:value("1", translate("内置 SIM1"))
o:value("2", translate("内置 SIM2"))

function m.on_after_commit(self)
	luci.sys.call("/usr/libexec/wt6285/sim.sh %s >/dev/null 2>&1"
		% (self.uci:get("ec200a", "ec200a", "sim_sel") or "0"))
end

return m
