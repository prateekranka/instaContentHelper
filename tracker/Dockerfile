FROM node:24-bookworm-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
COPY public ./public
COPY seed.json ./seed.json
COPY initial-state.json ./initial-state.json
ENV TRACKER_DB=/data/tracker.sqlite PORT=3000
EXPOSE 3000
CMD ["node", "src/server.ts"]
