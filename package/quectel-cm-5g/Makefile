include $(TOPDIR)/rules.mk

PKG_NAME:=quectel-cm-5g
PKG_VERSION:=1.6.4
PKG_RELEASE:=1

PKG_LICENSE:=Proprietary
PKG_LICENSE_FILES:=NOTICE

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/quectel-cm-5g
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Quectel Connect Manager (5G)
  URL:=https://github.com/Lienol/openwrt
  DEPENDS:=+libpthread +libjson-c
endef

define Package/quectel-cm-5g/description
 Quectel Connect Manager (5G variant), vendored from Lienol/openwrt qmodem.
 Upstream NOTICE permits modification and redistribution.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -O2 -Wall -I$(PKG_BUILD_DIR) \
		-o $(PKG_BUILD_DIR)/quectel-CM \
		$(PKG_BUILD_DIR)/QmiWwanCM.c \
		$(PKG_BUILD_DIR)/GobiNetCM.c \
		$(PKG_BUILD_DIR)/main.c \
		$(PKG_BUILD_DIR)/QCQMUX.c \
		$(PKG_BUILD_DIR)/QMIThread.c \
		$(PKG_BUILD_DIR)/util.c \
		$(PKG_BUILD_DIR)/qmap_bridge_mode.c \
		$(PKG_BUILD_DIR)/mbim-cm.c \
		$(PKG_BUILD_DIR)/device.c \
		$(PKG_BUILD_DIR)/atc.c \
		$(PKG_BUILD_DIR)/atchannel.c \
		$(PKG_BUILD_DIR)/at_tok.c \
		$(PKG_BUILD_DIR)/udhcpc.c \
		$(TARGET_LDFLAGS) -lpthread -ldl -lrt -ljson-c
endef

define Package/quectel-cm-5g/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/quectel-CM $(1)/usr/bin/quectel-CM
endef

$(eval $(call BuildPackage,quectel-cm-5g))
