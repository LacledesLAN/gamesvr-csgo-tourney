# Laclede's LAN CSGO Tournament Server in Docker

![thumb-csgo-tourney](https://raw.githubusercontent.com/LacledesLAN/gamesvr-csgo-tourney/master/.misc/thumb-csgo-tourney.png "thumb-csgo-tourney")

This repository is maintained by [Laclede's LAN](https://lacledeslan.com). Its contents are heavily tailored and tweaked for use at our
charity LAN-Parties. For third-parties we recommend using this repo only as a reference example and then building your own using
[gamesvr-csgo](https://github.com/LacledesLAN/gamesvr-csgo) as the base image for your customized server.

## Table of Content

* [Third-Party Content](#third-party-content)
* [gamesvr-csgo-tourney:latest](#gamesvr-csgo-tourney:latest)
  * [gamesvr-csgo-tourney:hasty](#gamesvr-csgo-tourney:hasty)
  * [gamesvr-csgo-tourney:overtime](#gamesvr-csgo-tourney:overtime)
* [gamesvr-csgo-tourney:get5](#gamesvr-csgo-tourney:get5)
* [Useful Commands](#useful-commands)

## Tags

| Tag             | Description                                                             | Purpose    |
| --------------- | ----------------------------------------------------------------------- | ---------- |
| `latest`        | Alias for the default LL tournament server, currently `base-get5`.      | PRODUCTION |
| `hasty`         | Built from `latest`, configurations tweak for shorter play and testing. | TESTING    |
| `base`          | LL tournament rules.                                                    | n/a        |
| `base-overtime` | LL tournament rules, but the server starts in overtime mode.            | TESTING    |
| `get5`          | Built from `base`, but includes metamod, sourcemod, and get5.           | PRODUCTION |

## Third Party Content

This repo includes content from other projects, including [Metamod:Source](https://www.sourcemm.net/),
[SourceMod](https://www.sourcemod.net/), and [SourceMod get5 plugin](https://github.com/splewis/get5). For details see
`[./dist/README.md](./dist/README.md)`.

## Linux

## `gamesvr-csgo-tourney:latest`

The default tag `latest` contains just the LL server configs along with a simple test script. It is built from
`lacledeslan/gamesvr-csgo:latest`

### Download

```shell
docker pull lacledeslan/gamesvr-csgo-tourney;
```

### Run Self-Tests

The image includes a test script that can be used to verify its contents. No changes or pull-requests will be accepted to this repository if
any tests fail.

```shell
docker run --rm lacledeslan/gamesvr-csgo-tourney ./ll-tests/gamesvr-csgo-tourney.sh;
```

### `gamesvr-csgo-tourney:hasty`

Tag `hasty` is derived from `latest` but makes tweaks that drastically shorten game time. It is useful for testing changes without having to
play complete rounds.

### `gamesvr-csgo-tourney:overtime`

Tag `over` is derived from `latest` but the configuration starts the game with overtime settings.

## `gamesvr-csgo-tourney:get5`

Tag `get5` is derived from `latest` but includes the MetaMod plugin [get5](https://github.com/splewis/get5) and its prerequisites
[Metamod:Source](https://www.sourcemm.net/) and [SourceMod](https://www.sourcemod.net/).

```shell
docker pull lacledeslan/gamesvr-csgo-tourney:get5;
```

### Run Self-Tests

The image includes a test script that can be used to verify its contents. No changes or pull-requests will be accepted to this repository if
any tests fail.

```shell
docker run --rm lacledeslan/gamesvr-csgo-tourney:get5 ./ll-tests/gamesvr-csgo-tourney-get5.sh;
```

## Useful Commands

### Extract Log Files

```shell
docker ps -a | grep lacledeslan/gamesvr-csgo-tourney | awk '{ print $14 }' | while read containerName; do
    echo Extracting for $containerName
    docker cp $containerName:/app/csgo/logs ~/$containerName/
    rm -f ~/$containerName/*.txt
    docker cp $containerName:/app/csgo/addons/sourcemod/logs ~/$containerName/sourcemod/
    rm -f ~/$containerName/sourcemod/accelerator.log
    rm -f ~/$containerName/sourcemod/*.txt
done
```
