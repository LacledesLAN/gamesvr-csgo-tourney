#!/bin/bash
set -e

echo -e '\n\033[1m[Build tourney:base]\033[0m'
docker build . -f linux.base.Dockerfile --rm -t lacledeslan/gamesvr-csgo-tourney:base --pull --build-arg BUILDNODE=$(cat /proc/sys/kernel/hostname);
docker run -it --rm lacledeslan/gamesvr-csgo-tourney:base ./ll-tests/gamesvr-csgo-tourney-base.sh;
docker push lacledeslan/gamesvr-csgo-tourney:base

#
# TODO: Overtime
#

echo -e '\n\033[1m[Build tourney:base-get5]\033[0m'
docker build . -f linux.base-get5.Dockerfile --rm -t lacledeslan/gamesvr-csgo-tourney:base-get5 --build-arg BUILDNODE=$(cat /proc/sys/kernel/hostname);
docker run -it --rm lacledeslan/gamesvr-csgo-tourney:base-get5 ./ll-tests/gamesvr-csgo-tourney-base-get5.sh;
docker push lacledeslan/gamesvr-csgo-tourney:base-get5

echo -e '\n\033[1m[Build tourney:latest]\033[0m'
docker tag lacledeslan/gamesvr-csgo-tourney:base-get5 lacledeslan/gamesvr-csgo-tourney:latest
docker push lacledeslan/gamesvr-csgo-tourney:latest

echo -e '\n\033[1m[Build tourney:hasty]\033[0m'
docker build . -f linux.hasty.Dockerfile --rm -t lacledeslan/gamesvr-csgo-tourney:hasty --build-arg BUILDNODE=$(cat /proc/sys/kernel/hostname);
#docker run -it --rm lacledeslan/gamesvr-csgo-tourney:hasty ./ll-tests/gamesvr-csgo-tourney-hasty.sh;
docker push lacledeslan/gamesvr-csgo-tourney:hasty
