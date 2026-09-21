FROM elixir:1.20.4-otp-29 AS build
ENV MIX_ENV=prod
WORKDIR /build
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile
COPY lib lib
COPY priv priv
RUN mix compile && mix release

# Same base as the build stage keeps native DTLS/SRTP libraries ABI-compatible.
FROM elixir:1.20.4-otp-29 AS runtime
WORKDIR /app
RUN useradd --system --uid 10001 app
COPY --from=build --chown=app /build/_build/prod/rel/webrtc_live ./
USER app
ENV PHX_SERVER=true
CMD ["bin/webrtc_live", "start"]
