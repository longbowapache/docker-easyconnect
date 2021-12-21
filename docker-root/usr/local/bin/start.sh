#!/bin/bash
BASE_CONF_DIR=/config
[ -n "$CHECK_SYSTEM_ONLY" ] && detect-tun.sh
detect-iptables.sh
. "$(which detect-route.sh)"
[ -n "$CHECK_SYSTEM_ONLY" ] && exit

# 在虚拟网络设备 tun0 打开时运行 proxy 代理服务器
[ -n "$NODANTED" ] || (while true
do
sleep 5
[ -d /sys/class/net/tun0 ] && {
	chmod a+w /tmp
	open_port 1080
	su daemon -s /usr/sbin/danted
	close_port 1080
}
done
)&
open_port 8888
tinyproxy -c /etc/tinyproxy.conf

interface_name="eth0"

# 如果是 podman 容器，interface 名称为 tap0 而不是 eth0
if [[ -n "$container" && "$container" == "podman" ]]; then
	sed --in-place=.bak 's/eth0/tap0/g' /etc/danted.conf
	interface_name="tap0"
fi

iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

# 拒绝 tun0 侧主动请求的连接.
iptables -I INPUT -p tcp -j DROP
iptables -I INPUT -i $interface_name -p tcp -j ACCEPT
iptables -I INPUT -i lo -p tcp -j ACCEPT
iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 删除深信服可能生成的一条 iptables 规则，防止其丢弃传出到宿主机的连接
# 感谢 @stingshen https://github.com/Hagb/docker-easyconnect/issues/6
( while true; do sleep 5 ; iptables -D SANGFOR_VIRTUAL -j DROP 2>/dev/null ; done )&

if [ -n "$_EC_CLI" ]; then
	ln -s /usr/share/sangfor/EasyConnect/resources/{conf_${EC_VER},conf}
	exec start-sangfor.sh
fi

[ -n "$EXIT" ] && MAX_RETRY=0

# 登录信息持久化处理
## 持久化配置文件夹 感谢 @hexid26 https://github.com/Hagb/docker-easyconnect/issues/21
[ -d ${BASE_CONF_DIR}/conf ] || cp -a /usr/share/sangfor/EasyConnect/resources/conf_backup ${BASE_CONF_DIR}/conf
[ -e ${BASE_CONF_DIR}/easy_connect.json ] && mv ${BASE_CONF_DIR}/easy_connect.json ${BASE_CONF_DIR}/conf/easy_connect.json # 向下兼容
## 默认使用英语：感谢 @forest0 https://github.com/Hagb/docker-easyconnect/issues/2#issuecomment-658205504
[ -e ${BASE_CONF_DIR}/conf/easy_connect.json ] || echo '{"language": "en_US"}' > ${BASE_CONF_DIR}/conf/easy_connect.json

export DISPLAY

if [ "$TYPE" != "X11" -a "$TYPE" != "x11" ]
then
	# container 再次运行时清除 /tmp 中的锁，使 container 能够反复使用。
	# 感谢 @skychan https://github.com/Hagb/docker-easyconnect/issues/4#issuecomment-660842149
	rm -rf /tmp
	mkdir /tmp

	# $PASSWORD 不为空时，更新 vnc 密码
	[ -e ${BASE_CONF_DIR}/.vnc/passwd ] || (mkdir -p ${BASE_CONF_DIR}/.vnc && (echo password | tigervncpasswd -f > ${BASE_CONF_DIR}/.vnc/passwd))
	[ -n "$PASSWORD" ] && printf %s "$PASSWORD" | tigervncpasswd -f > ${BASE_CONF_DIR}/.vnc/passwd

	open_port 5901
	tigervncserver :1 -geometry 800x600 -localhost no -passwd ${BASE_CONF_DIR}/.vnc/passwd -xstartup flwm
	DISPLAY=:1

	# 将 easyconnect 的密码放入粘贴板中，应对密码复杂且无法保存的情况 (eg: 需要短信验证登录)
	# 感谢 @yakumioto https://github.com/Hagb/docker-easyconnect/pull/8
	echo "$ECPASSWORD" | DISPLAY=:1 xclip -selection c
fi

exec start-sangfor.sh
