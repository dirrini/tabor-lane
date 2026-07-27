FROM ortussolutions/commandbox:lucee6

WORKDIR /app

COPY box.json server.json ./
RUN box install --production

COPY src ./src

ENV APP_DIR=/app \
    PORT=8080 \
    BOX_SERVER_OPENBROWSER=false \
    BOX_SERVER_PROFILE=production

EXPOSE 8080

HEALTHCHECK --interval=20s --timeout=5s --start-period=60s --retries=5 \
  CMD curl --fail --silent http://127.0.0.1:8080/health/ready || exit 1

