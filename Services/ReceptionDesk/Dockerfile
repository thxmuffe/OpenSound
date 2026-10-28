FROM elixir:1.19.5-otp-28 AS build
ENV MIX_ENV=prod
WORKDIR /app/Services/ReceptionDesk
RUN mix local.hex --force && mix local.rebar --force
COPY Services/ReceptionDesk/mix.exs Services/ReceptionDesk/mix.lock ./
COPY Services/ReceptionDesk/config ./config
RUN mix deps.get --only prod && mix deps.compile
COPY Services/ReceptionDesk/lib ./lib
COPY Services/ReceptionDesk/relay_src ./relay_src
RUN mix compile --warnings-as-errors && mix release --path /release
RUN mkdir -p /release/licenses && for dep in /app/builds/intermediates/ReceptionDeskDeps/*; do \
    for file in "$dep"/LICENSE*; do if [ -f "$file" ]; then \
    cp "$file" "/release/licenses/$(basename "$dep")-$(basename "$file")"; fi; done; done

FROM elixir:1.19.5-otp-28
WORKDIR /app
COPY --from=build --chown=1000:1000 /release ./
USER 1000:1000
ENV HOME=/app PARVI_BROKER_BIND=0.0.0.0 PORT=10000 RELEASE_DISTRIBUTION=none
EXPOSE 10000
CMD ["/app/bin/reception_desk", "start"]
