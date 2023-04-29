# escape=`
FROM lacledeslan/gamesvr-csgo-tourney:base

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

# Linux version of `Metamod:Source`.
COPY --chown=CSGOTourneyBase:root ./dist/metamod/linux /app/csgo
RUN true

# Linux version of `SourceMod`.
COPY --chown=CSGOTourneyBase:root ./dist/sourcemod/linux /app/csgo
RUN true

# `Warmod` SourceMod plugin.
COPY --chown=CSGOTourneyBase:root ./dist/sourcemod/warmod /app/csgo
RUN true

# LL content for `Warmod`
COPY --chown=CSGOTourneyBase:root ./dist/content/warmod /app

# UPDATE USERNAME & ensure permissions
RUN usermod -l CSGOTourneyGet5 CSGOTourneyBase &&`
    chmod +x /app/ll-tests/*.sh

USER CSGOTourneyGet5

ONBUILD USER root
