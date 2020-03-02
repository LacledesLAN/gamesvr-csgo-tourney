# escape=`
FROM lacledeslan/gamesvr-csgo-tourney

ARG BUILDNODE="unspecified"
ARG SOURCE_COMMIT

LABEL maintainer="Laclede's LAN <contact @lacledeslan.com>" `
      com.lacledeslan.build-node=$BUILDNODE `
      org.label-schema.schema-version="1.0" `
      org.label-schema.url="https://github.com/LacledesLAN/README.1ST" `
      org.label-schema.vcs-ref=$SOURCE_COMMIT `
      org.label-schema.vendor="Laclede's LAN" `
      org.label-schema.description="LL Counter-Strike GO Tourney Get5 Server" `
      org.label-schema.vcs-url="https://github.com/LacledesLAN/gamesvr-csgo-tourney"

# `RUN true` lines are work around for https://github.com/moby/moby/issues/36573

# Copy in linux/metamod
COPY --chown=CSGOTourney:root ./dist/linux/metamod/addons/ /app/csgo/addons/
RUN true

# Copy in os-agnostic metamod vdf
COPY --chown=CSGOTourney:root ./dist/metamod/addons/ /app/csgo/addons/
RUN true

# Copy in linux/sourcemod
COPY --chown=CSGOTourney:root ./dist/linux/sourcemod/ /app/csgo/
RUN true

# Copy in os-agnostic global LL sourcemod configs
COPY --chown=CSGOTourney:root ./dist/sourcemod-ll-configs/ /app/csgo/
RUN true

# Copy in os-agnostic get5 sourcemod plugin
COPY --chown=CSGOTourney:root ./dist/get5/ /app/csgo/
RUN true

# Copy in os-agnostic get5 LL configs
COPY --chown=CSGOTourney:root ./dist/get5-ll-configs/ /app/csgo/
RUN true

# Copy in tests
COPY --chown=CSGOTourney:root /dist/linux/ll-tests/gamesvr-csgo-tourney-get5.sh /app/ll-tests/gamesvr-csgo-tourney-get5.sh
RUN true

# UPDATE USERNAME & ensure permissions
RUN usermod -l CSGOTourneyGet5 CSGOTourney &&`
    chmod +x /app/ll-tests/*gamesvr-csgo-tourney-get5.sh

USER CSGOTourneyGet5
