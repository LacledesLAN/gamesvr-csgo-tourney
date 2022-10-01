#!/bin/bash
set -e

echo -e '\n\033[1m[Build tourney:base]\033[0m'
docker build . -f linux.base.Dockerfile --rm -t lacledeslan/gamesvr-csgo-tourney:base --pull --build-arg BUILDNODE="$(cat /proc/sys/kernel/hostname)";
docker run -it --rm lacledeslan/gamesvr-csgo-tourney:base ./ll-tests/gamesvr-csgo-tourney-base.sh;
docker push lacledeslan/gamesvr-csgo-tourney:base

echo -e '\n\033[1m[Build tourney:base-overtime]\033[0m'
docker build . -f linux.base.Dockerfile --rm -t lacledeslan/gamesvr-csgo-tourney:base-overtime --pull --build-arg BUILDNODE="$(cat /proc/sys/kernel/hostname)";
docker push lacledeslan/gamesvr-csgo-tourney:base-overtime

echo -e '\n\033[1m[Build tourney:get5]\033[0m'
docker build . -f linux.get5.Dockerfile --rm -t lacledeslan/gamesvr-csgo-tourney:get5 --build-arg BUILDNODE="$(cat /proc/sys/kernel/hostname)";
docker run -it --rm lacledeslan/gamesvr-csgo-tourney:get5 ./ll-tests/gamesvr-csgo-tourney-get5.sh;
docker push lacledeslan/gamesvr-csgo-tourney:get5

##
## TODO: Warmod [BFG]
##

echo -e '\n\033[1m[Build tourney:latest]\033[0m'
docker tag lacledeslan/gamesvr-csgo-tourney:get5 lacledeslan/gamesvr-csgo-tourney:latest
docker push lacledeslan/gamesvr-csgo-tourney:latest

echo -e '\n\033[1m[Build tourney:hasty]\033[0m'
docker build . -f linux.latest-hasty.Dockerfile --rm -t lacledeslan/gamesvr-csgo-tourney:latest-hasty --build-arg BUILDNODE="$(cat /proc/sys/kernel/hostname)";
docker push lacledeslan/gamesvr-csgo-tourney:latest-hasty
