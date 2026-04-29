#!/usr/bin/env bash
set -euo pipefail

DOCKER_COMPOSE=./tests/docker-compose.test.yml

echo "🔧 Building container..."
docker compose -f "$DOCKER_COMPOSE" build

echo "🚀 Starting container..."
docker compose -f "$DOCKER_COMPOSE" up -d

echo "⏳ Waiting for healthcheck..."

# wait for container to become healthy
for i in {1..12}; do
	status=$(docker inspect --format='{{.State.Health.Status}}' moledns-test 2>/dev/null || echo "starting")
	if [ "$status" = "healthy" ]; then
		echo "✅ Container is healthy"
		break
	fi
	sleep "$i"
done

if [ "$status" != "healthy" ]; then
	echo "❌ Container failed healthcheck"
	docker logs moledns-test
	exit 1
fi

echo "🧪 Running DNS test..."
dig @127.0.0.1 -p 53053 cloudflare.com A +short

echo "🧹 Cleaning up..."
docker compose -f "$DOCKER_COMPOSE" down

echo "✅ Test passed"
