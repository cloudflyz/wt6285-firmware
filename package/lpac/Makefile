include $(TOPDIR)/rules.mk

PKG_NAME:=lpac
PKG_VERSION:=2.3.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/estkme-group/lpac/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=661dffbd1e9e5732dab4a0bb0a9837d4906c8c66bd748bda262fe3e8d3e420f6

PKG_LICENSE:=AGPL-3.0-only LGPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=curl

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/lpac
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=eUICC eSIM Local Profile Assistant (AT+QMI backend)
  URL:=https://github.com/estkme-group/lpac
  DEPENDS:=+libcurl +ca-bundle +libpthread
endef

define Package/lpac/description
 lpac is a cross-platform local profile agent implementing SGP.22.
 Built with AT and QMI APDU backends; QMI is used to bypass AT+CCHO on EC200A.
endef

TARGET_CFLAGS += $(FPIC)
CMAKE_OPTIONS += \
	-DLPAC_WITH_APDU_AT=ON \
	-DLPAC_WITH_APDU_PCSC=OFF \
	-DLPAC_WITH_APDU_QMI=OFF \
	-DLPAC_WITH_APDU_QMI_QRTR=OFF \
	-DLPAC_WITH_APDU_MBIM=OFF \
	-DLPAC_WITH_HTTP_CURL=ON

define Package/lpac/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/lpac $(1)/usr/bin/lpac
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/lpac.config $(1)/etc/config/lpac
endef

$(eval $(call BuildPackage,lpac))
