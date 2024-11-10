# syntax=docker/dockerfile:1

FROM debian:stable-slim

COPY <<EOF /app.sh
#!/usr/bin/env bash
set -Eeuo pipefail
while true; do
  [[ -f /secret ]] && echo "Secret file contains: $(cat /secret)" || echo "Secret file does not exist!";
  sleep 30;
done
EOF

RUN chmod +x /app.sh

CMD ["/app.sh"]
