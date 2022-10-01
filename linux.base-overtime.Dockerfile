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
      org.label-schema.description="LL Counter-Strike GO Warmod Overtime Server" `
      org.label-schema.vcs-url="https://github.com/LacledesLAN/gamesvr-csgo-warmod-overtime"

#                          ____
#                       _.' :  `._
#                   .-.'`.  ;   .'`.-.             Begun, the overtime hacks have
#          __      / : ___\ ;  /___ ; \      __
#        ,'_ ""--.:__;".-.";: :".-.":__;.--"" _`,
#        :' `.t""--.. '<@.`;_  ',@>` ..--""j.' `;
#             `:-.._J '-.-'L__ `-- ' L_..-;'
#               "-.__ ;  .-"  "-.  : __.-"
#                   L ' /.------.\ ' J
#                    "-.   "--"   .-"
#                   __.l"-:_JL_;-";.__
RUN FILE="/app/csgo/cfg/gamemode_competitive_server.cfg" &&`
        echo "//===OVERTIME HACK" >> $FILE &&`
        echo "mp_maxrounds 7" >> $FILE &&`
        echo "mp_startmoney 10000" >> $FILE

# UPDATE USERNAME & ensure permissions
RUN usermod -l CSGOTourneyBaseOvertime CSGOTourneyBase &&`
    chmod +x /app/ll-tests/*.sh &&`
    chmod 774 /app/csgo/cfg/*.cfg

USER CSGOTourneyBaseOvertime

WORKDIR /app/

CMD ["/bin/bash"]

ONBUILD USER root
