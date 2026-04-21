Making DNS private AND anonymous.
A DNS proxy that prioritizes Cloudflares Tor hidden resolver and automatically fails over to clearnet DoH over Tor, with health-based routing and metrics monitoring. Set up is easy and privacy is extremely strong. Designed for users who want to hide DNS activity from ISPs and resolvers, and reduce linkability between queries and identity.

Testimonials:
"I've used moleDNS for 2 years in production and have zero downtime!" - Guy who made it

## wishlist

- [ ] Support for encrypted connections to the container (DoT, DoH)
- [ ] Add nyx support
- [ ] Pass through more docker env variables for advanced configuration
- [ ] Performance optimizations

## Priorities

This mission of this project is to provide an ***easy***, out-of-the-box solution that anyone can run to have the ultimate in DNS privacy

# Why?

DNScrypt is a great way to shield your DNS queries from your ISP and other on-path entities, but it still requires you to trust the resolvers themselves. Privacy is possible, but anonymity is not.
This solution assumes resolvers cannot be trusted. In the age of big data and AI, why trust a resolver? With moleDNS the resolvers no longer see your IP. In extreme cases, advanced techniques like heuristics to reveal who you are based on your queries, or timing attacks, are still possible.

# Getting Started

1. Clone this repo, or download it.
2. Make sure you've installed Docker Desktop
3. In the project folder, run `docker compose up`, or `docker compose up -d` to run in the background
4. Your DNS server is now available at 127.0.0.1 on port 6053


# Considerations

### Performance

Latency is generally under 300ms, and does not disrupt regular services. Acceptable for most use cases, with caching mitigating most query overhead.

### hostname visible in request

Without Encrypted Client Hello (ECH), the destination hostname is still exposed via SNI during the TLS handshake, which can reduce or eliminate the privacy gains of encrypted DNS, especially against on path observers like ISPs. DNS encryption still prevents DNS level monitoring, but SNI can reveal the same hostname later in the connection.

### IP correlation
Small or self-hosted websites will have IPs that make it pretty easy to guess what site you're visiting. Larger providers will have many hostnames behind the IPs they serve, so privacy is preserved more easily when accessing sites hosted on these platforms.

## Technical Notes

### HTTPS
Tor exit nodes are not to be trusted; whoever controls one unwraps the final layer of encryption in a connection, so HTTPS must be used.
This requires the hosts file to bind hostnames for the DNS servers directly to the socat instance its targeting, this ensures when the https pipe for socat sends back the certificate that cloudflare provides it can show the same hostname that dnscrypt proxy attempted to start the connection with, since IP addresses are not possible (we connect to socat on the loopback, not 1.1.1.1).



```mermaid

flowchart TD
	CLIENTS["hosts & other containers"]
	INTERNET["Cloudflare 1.1.1.1"]
	subgraph DOCKER["Docker container"]
		NIC
		subgraph DNSMASQ
			DNSMASQ_SVC["dnsmasq service"]
			DNS_SERVERS["dnsmasq-servers.conf<br><sub>dnscrypt proxies<br>strict ordering"]
		end
		
		DNSCRYPT_ONION["dnscrypt - onion"]
		DNSCRYPT_CLEARNET["dnscrypt - clearnet"]
		
		HEALTH["Health checker"]
		
		subgraph HOSTS["/etc/hosts"]
			HOSTS_CLEARNET["one.one.one.one<br><sub>127.0.0.2"]
			HOSTS_ONION["dns4tor...ad.onion<br><sub>127.0.0.1"]
		end

		SOCAT_ONION["socat<br><sub>127.0.0.1<br><sub>onion pipe"]
		SOCAT_CLEARNET["socat<br><sub>127.0.0.2<br><sub>clearnet pipe"]
		TOR_PROXY["Tor SOCKS5 Proxy"]
	end

	subgraph TOR_NETWORK["Tor network"]
		NODES["Entry & Relay Nodes"]
		EXIT_NODE["Exit Node"]
		HIDDEN_SVCS["Cloudflare Hidden Service"]
	end

	CLIENTS --> |port 53 - unencrypted| NIC --> DNSMASQ_SVC
	
	%% ONION RESOLVER

	DNSMASQ_SVC --> |default preferred| DNSCRYPT_ONION --> |HTTPS traffic|SOCAT_ONION

	%% dnsmasq
	HEALTH -.-> |Test circuits /<br>reload after swapping|DNSMASQ_SVC
	HEALTH -.-> |set server order by health|DNS_SERVERS
	%% HOSTNAME RESOLUTION

	DNSCRYPT_ONION -.-> HOSTS_ONION
	DNSCRYPT_CLEARNET -.-> HOSTS_CLEARNET
	
	%% CLEARNET RESOLVER

	DNSMASQ_SVC --> |fallback|DNSCRYPT_CLEARNET --> |HTTPS traffic|SOCAT_CLEARNET

	%% tor

	SOCAT_ONION & SOCAT_CLEARNET ==> TOR_PROXY
	TOR_PROXY ==> | .onion & clearnet requests |NODES
	NODES ==> | .onion requests<br>DNS over HTTPS |HIDDEN_SVCS
	NODES ==> | clearnet requests |EXIT_NODE ==> |DNS over HTTPS|INTERNET
	

	linkStyle 3 stroke:orange,stroke-width:2px
	linkStyle 9 stroke:orange,stroke-width:2px
	linkStyle 10 stroke:orange,stroke-width:2px
	linkStyle 11 stroke:orange,stroke-width:2px
	linkStyle 12 stroke:orange,stroke-width:2px
	linkStyle 13 stroke:orange,stroke-width:2px
	linkStyle 14 stroke:orange,stroke-width:2px
	linkStyle 15 stroke:orange,stroke-width:2px

```
