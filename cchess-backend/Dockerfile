# Multi-stage build for cchess-backend.
# Stage 1: install dev deps + compile TypeScript -> JavaScript
# Stage 2: minimal production image with only runtime deps.

FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
EXPOSE 8080
# Render / Railway / Fly.io will inject FIREBASE_SERVICE_ACCOUNT_JSON env.
CMD ["node", "dist/server.js"]
