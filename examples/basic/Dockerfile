FROM hexpm/elixir:1.20.4-erlang-29.0.6-debian-trixie-20261027-slim AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
WORKDIR /src/fow/examples/basic

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs package.json /src/fow/
COPY lib /src/fow/lib
COPY priv /src/fow/priv
COPY examples/basic/mix.exs examples/basic/mix.lock ./
COPY examples/basic/config/config.exs examples/basic/config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile && mix assets.setup

COPY examples/basic/lib lib
COPY examples/basic/priv priv
COPY examples/basic/assets assets
RUN mix compile && mix assets.deploy

COPY examples/basic/config/runtime.exs config/
RUN mix release

FROM debian:trixie-20261027-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libncurses6 libstdc++6 openssl \
  && rm -rf /var/lib/apt/lists/*
ENV LANG=C.UTF-8
WORKDIR /app
COPY --from=build --chown=nobody:root /src/fow/examples/basic/_build/prod/rel/fog_of_war_basic ./
USER nobody
CMD ["/app/bin/fog_of_war_basic", "start"]
