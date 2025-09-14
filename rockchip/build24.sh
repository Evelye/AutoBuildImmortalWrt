#!/bin/bash
set -e  # 出现错误立即退出

# 日志文件
LOGFILE="/tmp/uci-defaults-log.txt"
exec > >(tee -a "$LOGFILE") 2>&1  # 同时输出到控制台和日志文件

echo "Starting 99-custom.sh at $(date)"

# 加载自定义包配置
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"

# 显示构建参数
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

# 创建 pppoe 配置目录
echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

# 创建 pppoe 配置文件
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "pppoe-settings 内容:"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 处理第三方软件包
if [ -n "$CUSTOM_PACKAGES" ]; then
  echo "🔄 正在同步第三方软件仓库..."
  if ! git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo; then
    echo "❌ 克隆仓库失败"
    exit 1
  fi

  # 拷贝 run 文件
  mkdir -p /home/build/immortalwrt/extra-packages
  if [ -d "/tmp/store-run-repo/run/arm64" ]; then
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
    echo "✅ Run files copied:"
    ls -lh /home/build/immortalwrt/extra-packages/*.run 2>/dev/null || echo "No .run files found"
  else
    echo "⚠️  arm64 目录不存在"
  fi

  # 准备包
  if [ -f "shell/prepare-packages.sh" ]; then
    sh shell/prepare-packages.sh
  else
    echo "❌ prepare-packages.sh 不存在"
    exit 1
  fi

  # 添加架构信息
  REPO_CONF="/home/build/immortalwrt/repositories.conf"
  if [ -f "$REPO_CONF" ]; then
    if ! grep -q "arch aarch64_generic" "$REPO_CONF"; then
      sed -i '1i arch aarch64_generic 10\narch aarch64_cortex-a53 15' "$REPO_CONF"
    fi
    echo "repositories.conf 内容:"
    cat "$REPO_CONF"
  else
    echo "❌ repositories.conf 不存在"
    exit 1
  fi
else
  echo "⚪️ 未选择任何第三方软件包"
fi

# 基础包列表
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"

# 可选包
[ "$INCLUDE_DOCKER" = "yes" ] && {
  PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
  echo "✅ 添加 Docker 相关包"
}

PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-dufs-zh-cn"

# 添加 Nikki 相关包
PACKAGES="$PACKAGES luci-app-nikki"
PACKAGES="$PACKAGES luci-i18n-nikki-zh-cn"
echo "✅ 添加 Nikki 相关包"

# 添加 MosDNS 相关包
PACKAGES="$PACKAGES luci-app-mosdns"
PACKAGES="$PACKAGES luci-i18n-mosdns-zh-cn"
PACKAGES="$PACKAGES mosdns"
echo "✅ 添加 MosDNS 相关包"

# 添加自定义包
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

echo "最终包列表: $PACKAGES"

# 创建 Nikki 配置文件
echo "创建 Nikki 配置文件..."
mkdir -p /home/build/immortalwrt/files/etc/nikki

# 基础 Nikki 配置
cat << 'EOF' > /home/build/immortalwrt/files/etc/nikki/config.yaml
# Nikki 基础配置
log:
  level: info
  output: /var/log/nikki.log

dns:
  enable: true
  listen: :53
  enhanced-mode: redir-host
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - 1.1.1.1
    - 8.8.8.8

proxy:
  - name: "direct"
    type: direct
  - name: "reject"
    type: reject

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "direct"

rules:
  - "MATCH,direct"
EOF

# 创建 Nikki 启动脚本
mkdir -p /home/build/immortalwrt/files/etc/init.d
cat << 'EOF' > /home/build/immortalwrt/files/etc/init.d/nikki
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1
NAME=nikki

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/nikki -c /etc/nikki/config.yaml
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall -9 nikki 2>/dev/null
}
EOF

chmod +x /home/build/immortalwrt/files/etc/init.d/nikki

# 创建 Nikki Luci 菜单配置文件
mkdir -p /home/build/immortalwrt/files/usr/share/luci/menu.d
cat << 'EOF' > /home/build/immortalwrt/files/usr/share/luci/menu.d/luci-app-nikki.json
{
    "admin/services/nikki": {
        "title": "Nikki",
        "order": 60,
        "action": {
            "type": "view",
            "path": "nikki"
        },
        "depends": {
            "acl": [ "luci-app-nikki" ],
            "uci": { "nikki": true }
        }
    }
}
EOF

echo "✅ Nikki 相关配置已创建"

# 创建 MosDNS 配置文件
echo "创建 MosDNS 配置文件..."
mkdir -p /home/build/immortalwrt/files/etc/mosdns

# MosDNS 主配置文件
cat << 'EOF' > /home/build/immortalwrt/files/etc/mosdns/config.yaml
log:
  level: info
  file: "/tmp/mosdns.log"

data_providers:
  - tag: geosite
    file: "/usr/share/v2ray/geosite.dat"
    auto_reload: true
  - tag: geoip
    file: "/usr/share/v2ray/geoip.dat"
    auto_reload: true

plugins:
  # 缓存
  - tag: cache
    type: cache
    args:
      size: 4096
      lazy_cache_ttl: 86400

  # 转发到本地服务器
  - tag: forward_local
    type: fast_forward
    args:
      upstream:
        - addr: "tls://223.5.5.5:853"
          enable_pipeline: true
        - addr: "tls://1.12.12.12:853"
          enable_pipeline: true

  # 转发到远程服务器
  - tag: forward_remote
    type: fast_forward
    args:
      upstream:
        - addr: "tls://8.8.4.4:853"
          enable_pipeline: true
        - addr: "tls://1.1.1.1:853"
          enable_pipeline: true

  # 序列执行
  - tag: seq
    type: sequence
    args:
      exec:
        - if: "has_resp()"
          exec: cache
        - forward_local
        - forward_remote

  # 主服务器
  - tag: main_server
    type: udp_server
    args:
      entry: seq
      listen: ":53"

  # 备用服务器
  - tag: alt_server
    type: tcp_server
    args:
      entry: seq
      listen: ":53"
EOF

# 创建 MosDNS 启动脚本
cat << 'EOF' > /home/build/immortalwrt/files/etc/init.d/mosdns
#!/bin/sh /etc/rc.common

START=95
STOP=10
USE_PROCD=1
NAME=mosdns

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/mosdns -c /etc/mosdns/config.yaml
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall -9 mosdns 2>/dev/null
}
EOF

chmod +x /home/build/immortalwrt/files/etc/init.d/mosdns

# 下载 Geo 数据库文件
echo "下载 MosDNS Geo 数据库文件..."
mkdir -p /home/build/immortalwrt/files/usr/share/v2ray

# 下载 geoip.dat
if wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O /home/build/immortalwrt/files/usr/share/v2ray/geoip.dat; then
    echo "✅ geoip.dat 下载成功"
else
    echo "❌ geoip.dat 下载失败"
fi

# 下载 geosite.dat
if wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O /home/build/immortalwrt/files/usr/share/v2ray/geosite.dat; then
    echo "✅ geosite.dat 下载成功"
else
    echo "❌ geosite.dat 下载失败"
fi

# 创建 MosDNS Luci 菜单配置文件
cat << 'EOF' > /home/build/immortalwrt/files/usr/share/luci/menu.d/luci-app-mosdns.json
{
    "admin/services/mosdns": {
        "title": "MosDNS",
        "order": 55,
        "action": {
            "type": "view",
            "path": "mosdns"
        },
        "depends": {
            "acl": [ "luci-app-mosdns" ],
            "uci": { "mosdns": true }
        }
    }
}
EOF

echo "✅ MosDNS 相关配置已创建"

# 开始构建
echo "$(date) - 开始构建镜像..."
if make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"; then
    echo "$(date) - 构建成功!"
else
    echo "$(date) - ❌ 构建失败!"
    exit 1
fi
