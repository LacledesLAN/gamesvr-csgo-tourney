# Working with `/dist`

| Directory        | Contents                                 | Version notes                              | Image Mount Location |
| ---------------- | ---------------------------------------- | ------------------------------------------ | -------------------- |
| /content         | Content for specific Docker images.      |                                            |                      |
|   ├─/base        | LL tournament configs.                   |                                            | /app                 |
|   └─/get5        | LL configs for the `get5` SM plugin.     |                                            | /app                 |
| /metamod/linux   | Linux version of `Metamod:Source`.       | version 1.11 - build 1148 as of 2022/09/30 | /app/csgo            |
| /sourcemod       | SourceMod and related content.           |                                            |                      |
|   ├─/get5        | `get5` SourceMod plugin.                 | version 0.10.3 - e9451ba as of 2022/09/30  | /app/csgo            |
|   ├─/linux       | Linux version of `SourceMod`.            | version 1.11 - build 6911 as of 2022/09/30 | /app/csgo            |
|   ├─/ll          | Common LL SourceMod plugins and configs. |                                            | /app/csgo            |
|   └─/warmod      | `WarMod [BFG] SourceMod` plugin.         | version 22.09.26.1915                      | /app/csgo            |

## Updating Third-Party Content

This repo includes mechanisms to prevent unwanted content from propagating. This allows us to update third-party content by simply
downloading and extract it into the correct destination directories.

* `/.dockerignore` will prevent unwanted content from making into the Docker images.
* `./dist/.gitignore` will prevent unwanted content from making into into the git repo upon commits.
* Test scripts include checks to ensure unwanted SourceMod plugins don't slip through and aren't being loaded.

### Updating `Metamod:Source` (Linux)

1. Delete *dist/metamod/linux* (`rm -rf ./dist/metamod/linux/*`).
2. Download latest stable build of `Metamod:Source` for Linux.
3. Extract the *addons* directory into *./dist/metamod/linux*.

### Updating `SourceMod` (Linux)

1. Delete *dist/sourcemod/linux* (`rm -rf ./dist/sourcemod/linux/*`).
2. Download latest stable build of `SourceMod.` for Linux.
3. Extract the contents into *./dist/metamod/linux*.

### Updating `get5` plugin for `SourceMod`

1. Delete *dist/sourcemod/get5/* (`rm -rf ./dist/sourcemod/get5/*`)
2. Download the latest stable build of `get5` for SourceMod from
  [https://github.com/splewis/get5/releases/latest](https://github.com/splewis/get5/releases/latest).
3. Extract the contents into *./dist/sourcemod/get5/*.

### Updating `WarMod [BFG] SourceMod` plugin for `SourceMod`

* Replace the `warmod.smx` in *dist/sourcemod/warmod/addons/plugins*.
