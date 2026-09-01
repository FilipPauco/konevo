FROM elixir:1.19.5-alpine AS base

FROM base AS build

RUN apk add --no-cache build-base git python3 nodejs npm imagemagick

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix assets

COPY priv priv
COPY lib lib
RUN mix compile
COPY assets assets
COPY THIRD_PARTY_NOTICES.md ./
RUN mix assets.deploy
RUN mix release

FROM base AS app
# imagemagick and libwebp-tools are required for image resize/metadata stripping,
# including ImageMagick's WebP dwebp delegate.
RUN apk add --no-cache ncurses-libs libstdc++ imagemagick libwebp-tools

WORKDIR /app

RUN chown nobody:nobody /app
USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/konevo ./
COPY --from=build --chown=nobody:nobody /app/THIRD_PARTY_NOTICES.md ./

ENV HOME=/app
ENV PHX_SERVER=true

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=12 \
  CMD wget --quiet --spider http://127.0.0.1:4000/health || exit 1

CMD ["sh", "-c", "bin/konevo eval \"Konevo.Release.migrate_and_seed()\" && exec bin/konevo start"]
