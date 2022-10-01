# escape=`

FROM lacledeslan/gamesvr-csgo:latest

HEALTHCHECK NONE

ARG BUILDNODE="unspecified"
ARG SOURCE_COMMIT

ENV LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8

LABEL maintainer="Laclede's LAN <contact @lacledeslan.com>" `
      com.lacledeslan.build-node=$BUILDNODE `
      org.label-schema.schema-version="1.0" `
      org.label-schema.url="https://github.com/LacledesLAN/README.1ST" `
      org.label-schema.vcs-ref=$SOURCE_COMMIT `
      org.label-schema.vendor="Laclede's LAN" `
      org.label-schema.description="LL Counter-Strike GO Tournament Server" `
      org.label-schema.vcs-url="https://github.com/LacledesLAN/gamesvr-csgo-tourney"

# LL content for `base`
COPY --chown=CSGO:root ./dist/content/base /app

# UPDATE USERNAME & ensure permissions
RUN usermod -l CSGOTourneyBase CSGO &&`
    chmod +x /app/ll-tests/*.sh &&`
    mkdir -p /app/csgo/logs &&`
    chmod 774 /app/csgo/logs

USER CSGOTourney

WORKDIR /app/

CMD ["/bin/bash"]

ONBUILD USER root
