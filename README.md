# Laclede's LAN CSGO Tournament Server in Docker

![thumb-csgo-tourney](https://raw.githubusercontent.com/LacledesLAN/gamesvr-csgo-tourney/master/.misc/thumb-csgo-tourney.png "thumb-csgo-tourney")

This repository is maintained by [Laclede's LAN](https://lacledeslan.com). Its contents are heavily tailored and tweaked for use at our
charity LAN-Parties. For third-parties we recommend using this repo only as a reference example and then building your own using
[gamesvr-csgo](https://github.com/LacledesLAN/gamesvr-csgo) as the base image for your customized server.

## Table of Content

* [Third-Party Content](#third-party-content)
* [Tags](#tags)
* [Useful Commands](#useful-commands)

## Tags

| Tag                             | Description                                                             | Purpose    |
| ------------------------------- | ----------------------------------------------------------------------- | ---------- |
| `base`                          | LL tournament rules.                                                    | n/a        |
| [base-overtime](#base-overtime) | LL tournament rules, but the server starts in overtime mode.            | TESTING    |
| [get5](#get5)                   | Built from `base`, but includes metamod, sourcemod, and get5.           | PRODUCTION |
| `latest`                        | Alias for the default LL tournament server, currently `base-get5`.      | PRODUCTION |
| [hasty](#hasty)                 | Built from `latest`, configurations tweak for shorter play and testing. | TESTING    |

### Build Hierarchy

```text
                                              ┌───────────────────────┐
                                              │                       │
                                              │  gamesvr-csgo:latest  │
                                              │                       │
                                              └───────────┬───────────┘
                                                          │
                                           ┌──────────────▼──────────────┐
                                           │                             │
                                           │  gamesvr-csgo-tourney:base  │
                                           │                             │
                                           └──────┬───────┬──────┬───────┘
                    ┌─────────────────────────────┘       │      └───────────────────────────┐
┌───────────────────▼──────────────────┐   ┌──────────────▼──────────────┐   ┌───────────────▼───────────────┐
│                                      │   │                             │   │                               │
│  gamesvr-csgo-tourney:base-overtime  │   │  gamesvr-csgo-tourney:get5  │   │  gamesvr-csgo-tourney:warmod  │
│                                      │   │                             │   │                               │
└──────────────────────────────────────┘   └─────────────────────────────┘   └───────────────────────────────┘

              ┌───────────────────────────────┐                  ┌──────────────────────────────┐
              │                               │                  │                              │
              │  gamesvr-csgo-tourney:latest  ├──────────────────►  gamesvr-csgo-tourney:hasty  │
              │                               │                  │                              │
              └───────────────────────────────┘                  └──────────────────────────────┘
```

## Third Party Content

This repo includes content from other projects, including [Metamod:Source](https://www.sourcemm.net/),
[SourceMod](https://www.sourcemod.net/), and [SourceMod get5 plugin](https://github.com/splewis/get5). For details see
`[./dist/README.md](./dist/README.md)`.

## Linux

### Get5

`get5` is derived from `base` but includes the MetaMod plugin [get5](https://github.com/splewis/get5) and its prerequisites
[Metamod:Source](https://www.sourcemm.net/) and [SourceMod](https://www.sourcemod.net/).

#### Download

```shell
docker pull lacledeslan/gamesvr-csgo-tourney:get5;
```

### Run Self-Tests

```shell
docker run --rm lacledeslan/gamesvr-csgo-tourney:get5 ./ll-tests/gamesvr-csgo-tourney-get5.sh;
```

### Base-Overtime

The `base-overtime` image is mod-free, containing LL tournament configs that have been tweaked to start the server in overtime mode.

#### Start Overtime Server

```shell
TODO!
```

### Hasty

The `hasty` image is built from `latest` and is meant only for testing. Its configs have been tweaked to drastically shorten game time.

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
