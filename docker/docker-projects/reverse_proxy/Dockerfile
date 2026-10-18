# Stock Caddy has no DNS providers. The DuckDNS plugin lets Caddy prove domain
# ownership through a TXT record (DNS-01), the only ACME challenge that works
# behind CGNAT.
FROM caddy:2.11.7-builder-alpine AS builder
RUN xcaddy build --with github.com/caddy-dns/duckdns@v0.5.0

FROM caddy:2.11.7-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
