local m, s, o

m = Map("ec200a", translate("模块设置"), translate("频率锁定、IMEI 与定时重启。修改 IMEI 可能违反当地法规，请自行确认。"))

s = m:section(TypedSection, "ec200a", translate("模块"))
s.anonymous = true

o = s:option(Flag, "modify_band", translate("启用频率锁定"))
o.rmempty = false

o = s:option(Value, "band_hex", translate("Band 掩码 (hex)"))
o.datatype = "and(hexstring)"
o:depends("modify_band", "1")

o = s:option(Flag, "modify_imei", translate("启用 IMEI 修改"))
o.rmempty = false
o.description = translate("警告：修改 IMEI 可能违反当地法规，且写错会导致模块无法注册。")

o = s:option(Value, "IMEI", translate("IMEI (15 位)"))
o.datatype = "and(integer,rangelength(15,15))"
o:depends("modify_imei", "1")

function m.on_after_commit(self)
	luci.sys.call("/etc/init.d/ec200a restart >/dev/null 2>&1")
end

return m
