FROM node:23-alpine AS base
ARG TARGETARCH
ARG TARGETVARIANT
WORKDIR /app
CMD ["node", "index.js"]

FROM base AS dev
RUN --mount=type=cache,target=/var/cache/apk,id=file-manager-apk-$TARGETARCH$TARGETVARIANT,sharing=locked apk --update add make g++ python3

FROM base AS prod
COPY . /app
