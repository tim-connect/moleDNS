#!/bin/bash
set -Eeuo pipefail

#
#	gratuitous comments abound, happy learning
#
#

# functions----------------------------------------------------------

log_prefix() {
	local tag="$1"
	local color="$2"
	awk -v t="$tag" -v c="$color" '{printf "\033[%sm[%s]\033[0m %s\n", c, t, $0}' # line by line, -variables set, \033[ = escape sequence %sm = color code
}

log_date() {
	date +"%b %d %H:%M:%S.%3N"
}

check_hidden_dns() {
	local ip
	ip=$(dig @127.0.0.1 -p "$1" example.com +short +time=1 +tries=1 | head -n 1)
	case "$ip" in
	*.*.*.*) return 0 ;;
	*) return 1 ;;
	esac
}
wait_for_bootstrap_event() {
	local port="$1"
	local tag="$2"
	local color="$3"

	local done=0
	exec 3<>"/dev/tcp/127.0.0.1/$port"

	printf "AUTHENTICATE \"%s\"\r\nSETEVENTS STATUS_CLIENT STATUS_SERVER\r\n" "$TOR_PASSWORD" >&3
	while read -r line <&3; do
		#echo "$(date) [DEBUG] $line" | log_prefix "$tag" "$color"

		case "$line" in
		*"CIRCUIT_ESTABLISHED"*)
			echo "$(log_date) [INFO] Bootstrap complete" | log_prefix "$tag" "$color"
			done=1
			break
			;;
		*"514"* | *"551"*)
			echo "$(log_date) [ERROR] Auth failed" | log_prefix "$tag" "$color"
			kill 0
			return 1
			;;
		esac
	done
	while [ "$done" -eq 0 ]; do
		sleep 0.1
	done
}

run() {
	local tag="$1"
	local color="$2"
	shift 2 # drop the local $1 and $2 so we can pass the whole command with $@

	echo "$(log_date) [DEBUG] Running command: $*" | log_prefix "$tag" "$color"

	# line buffered stdout and stderr for the program we are running, sent to temp fds that input to the log_prefix function, forked to bg
	stdbuf -oL -eL "$@" > >(log_prefix "$tag" "$color") 2> >(log_prefix "$tag" "$color" >&2) &
	PID=$!
}

# --- setup ----------------------------------------------------------------

trap 'exit 0' INT TERM

PID=
TOR_STYLE="46"
SERVICE_STYLE="45"
DNSMASQ_STYLE="44"
ONION_STYLE="42"
CLEARNET_STYLE="41"
TOR_PASSWORD=$(head -c 32 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 13)
TOR_PASSWORD_HASH=$(tor --quiet --hash-password "$TOR_PASSWORD" | tail -n 1)
DNSMASQ_SERVERS_CONF=/dnsmasq-servers.conf
HIDDEN_PORT=5353 # as defined in our dns-crypt proxy toml files
CLEARNET_PORT=5354

ip addr add 127.0.0.2/32 dev lo # add a second loopback device so we can listen on 443 there as well, we want DoH for both
# we need this so the certificate presented must match the domain name, so we bind it in /etc/hosts
# we query one.one.one.one, get a public key that matches the domain name, but we have actually piped through
# socat, which can just refer to the IP (or onion address) directly since its tunneling straight to it (via SOCKS).

# --- tor instances --------------------------------------------------------

run tor "$TOR_STYLE" tor \
	--SocksPort 0.0.0.0:9050 \
	--ControlPort 127.0.0.1:9060 \
	--HashedControlPassword "$TOR_PASSWORD_HASH" \
	--DataDirectory /tmp/tor \
	--User toruser

sleep 2
wait_for_bootstrap_event 9060 tor "$TOR_STYLE"

# --- socat bridges --------------------------------------------------------

# fork to a separate process for each connection
# listen on 127.0.0.1:443, reuseaddr lets you bind to the port even if its not cleaned up
# connect to a socks proxy on 127.0.0.1, connecting to 1.1.1.1:443

run onion "$ONION_STYLE" socat \
	TCP4-LISTEN:443,bind=127.0.0.1,reuseaddr,fork \
	SOCKS5:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:443,socksport=9050

sleep 2

run clearnet "$CLEARNET_STYLE" socat \
	TCP4-LISTEN:443,bind=127.0.0.2,reuseaddr,fork \
	SOCKS5:127.0.0.1:1.1.1.1:443,socksport=9050

sleep 2

# --- dnscrypt-proxy -------------------------------------------------------

run clearnet "$CLEARNET_STYLE" dnscrypt-proxy -config dnscrypt-proxy.toml
run onion "$ONION_STYLE" dnscrypt-proxy -config dnscrypt-proxy-hidden.toml

# --- failover controller
#echo "$(log_date) [DEBUG] Using the following DNS servers for dnsmasq: $(cat $DNSMASQ_SERVERS_CONF)..."
run dnsmasq $DNSMASQ_STYLE dnsmasq -k -2 -R --servers-file="$DNSMASQ_SERVERS_CONF" --strict-order --interface=* --log-facility=- --no-resolv
DNSMASQ_PID=$PID

(
	echo "$(log_date) [INFO] Waiting a few seconds for services to spin up..." | log_prefix moleDNS $SERVICE_STYLE

	sleep 4
	NEW_CONF=$(printf "server=/#/127.0.0.1#%s\nserver=/#/127.0.0.1#%s\n" "$HIDDEN_PORT" "$CLEARNET_PORT")
	LAST_CONF=$NEW_CONF

	while true; do
		if check_hidden_dns "$HIDDEN_PORT"; then
			NEW_CONF=$(printf "server=/#/127.0.0.1#%s\nserver=/#/127.0.0.1#%s\n" "$HIDDEN_PORT" "$CLEARNET_PORT")
			if [ "$NEW_CONF" != "$LAST_CONF" ]; then
				echo "$(log_date) [INFO] Hidden resolver circuit is working..." | log_prefix dnsmasq $ONION_STYLE
			fi
		else
			NEW_CONF=$(printf "server=/#/127.0.0.1#%s\nserver=/#/127.0.0.1#%s\n" "$CLEARNET_PORT" "$HIDDEN_PORT")
			if [ "$NEW_CONF" != "$LAST_CONF" ]; then
				echo "$(log_date) [WARN] Hidden resolver circuit is not working, falling back to clearnet tunnel" | log_prefix dnsmasq $CLEARNET_STYLE
			fi
		fi

		if [ "$NEW_CONF" != "$LAST_CONF" ]; then
			echo "$(log_date) [INFO] Updating dnsmasq upstreams" | log_prefix dnsmasq $DNSMASQ_STYLE
			printf "%s" "$NEW_CONF" >"$DNSMASQ_SERVERS_CONF"
			kill -HUP "$DNSMASQ_PID"
			LAST_CONF="$NEW_CONF"
		fi
		sleep 30
	done
) &

sleep 8
echo "$(log_date) [INFO] Firewalling container DNS..." | log_prefix moleDNS $SERVICE_STYLE
# Force all DNS → local dnsmasq (port 53), preventing redirect loops by skipping loopback traffic in NAT:
iptables -t nat -A OUTPUT -o lo -j RETURN
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 53
# Block any DNS that tries to escape (non-loopback)
iptables -A OUTPUT ! -o lo -p udp --dport 53 -j REJECT
iptables -A OUTPUT ! -o lo -p tcp --dport 53 -j REJECT
echo "$(log_date) [INFO] Startup successful." | log_prefix moleDNS "5;$SERVICE_STYLE"
wait
