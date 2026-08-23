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
RUN mix assets.deploy
RUN mix release

FROM base AS app
# imagemagick required at runtime for image resize/metadata stripping
RUN apk add --no-cache ncurses-libs libstdc++ imagemagick

WORKDIR /app

RUN chown nobody:nobody /app
USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/konevo ./

ENV HOME=/app
ENV PHX_SERVER=true

CMD ["sh", "-c", "bin/konevo eval \"Konevo.Release.migrate_and_seed()\" && exec bin/konevo start"]
