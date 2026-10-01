<p align="center">
  <a href="https://github.com/AntilaX-3/"><img src="https://avatars.githubusercontent.com/u/35715409" width="150" title="AntilaX-3"></a>
</p>

<p align="center">
  <a href="https://buildkite.com/antilax-3/unbound"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fbuildkite%2F06df4de431ba3e21fa262198711fb5800dfd0d9c5a3e9b55c3%2Fmaster.json&query=%24.message&label=build&logo=buildkite&logoColor=%2314cc80&mode=dark&size=sm&variant=outline"><img alt="Build" src="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fbuildkite%2F06df4de431ba3e21fa262198711fb5800dfd0d9c5a3e9b55c3%2Fmaster.json&query=%24.message&label=build&logo=buildkite&logoColor=%2314cc80&mode=light&size=sm&variant=outline"></picture></a>
  <a href="https://hub.docker.com/r/antilax3/unbound/tags"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fimage-size%2Fantilax3%2Funbound%2Flatest.json&query=%24.message&label=image%20size&logo=docker&logoColor=%232496ed&mode=dark&size=sm&variant=outline"><img alt="Docker Size" src="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fimage-size%2Fantilax3%2Funbound%2Flatest.json&query=%24.message&label=image%20size&logo=docker&logoColor=%232496ed&mode=light&size=sm&variant=outline"></picture></a>
  <a href="https://hub.docker.com/r/antilax3/unbound"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fpulls%2Fantilax3%2Funbound.json&query=%24.message&label=pulls&logo=docker&logoColor=%232496ed&mode=dark&size=sm&variant=outline"><img alt="Docker Pulls" src="https://shieldcn.dev/badge/dynamic/json.svg?url=https%3A%2F%2Fimg.shields.io%2Fdocker%2Fpulls%2Fantilax3%2Funbound.json&query=%24.message&label=pulls&logo=docker&logoColor=%232496ed&mode=light&size=sm&variant=outline"></picture></a>
</p>

# AntilaX-3/unbound

[Unbound](https://www.nlnetlabs.nl/projects/unbound/about/) is a validating, recursive, caching DNS resolver. 
## Usage
```
docker create --name=unbound \
-v <path to config>:/config \
-p 53:53 \
-p 53:53/udp \
antilax3/unbound
```
## Tags

Two variants are built from the one Dockerfile, for `linux/amd64` and `linux/arm64`.

| Variant | Base | Tags |
| --- | --- | --- |
| wolfi | [antilax3/wolfi](https://hub.docker.com/r/antilax3/wolfi) | `latest`, `1`, `1.26`, `1.26.1` |
| alpine | [antilax3/alpine](https://hub.docker.com/r/antilax3/alpine) | `alpine`, `1-alpine`, `1.26-alpine`, `1.26.1-alpine` |

Wolfi is the default. Both variants compile the same unbound release from the signed NLnet Labs tarball, with the same features, so the choice between them is only the base and its libc.

## Parameters
The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side. For example with a volume -v external:internal - what this shows is the volume mapping from internal to external of the container. So -v /mnt/app/config:/config would map /config from inside the container to be accessible from /mnt/app/config on the host's filesystem.

- `-v /config` - local path for Unbound config file
- `-p 53` - TCP port for Unbound
- `-p 53/udp` - UDP port for Unbound
- `-e PUID` - for UserID, see below for explanation
- `-e PGID` - for GroupID, see below for explanation
- `-e TZ` - for setting timezone information, eg Australia/Melbourne

It is based on wolfi, or alpine linux for the `alpine` tags, with s6 overlay, for shell access whilst the container is running do `docker exec -it unbound /bin/bash`.

## User / Group Identifiers
Sometimes when using data volumes (-v flags) permissions issues can arise between the host OS and the container. We avoid this issue by allowing you to specify the user `PUID` and group `PGID`. Ensure the data volume directory on the host is owned by the same user you specify and it will "just work".

In this instance `PUID=1001` and `PGID=1001`. To find yours use `id user` as below:
`$ id <dockeruser>`
    `uid=1001(dockeruser) gid=1001(dockergroup) groups=1001(dockergroup)`
    
## Volumes

The container uses a single volume mounted at `/config`. This volume stores the configuration file `unbound.conf`.

    config
    |-- unbound.conf

## Configuration

The unbound.conf is copied to the /config volume when first run.

[Unbound documentation](https://nlnetlabs.nl/documentation/unbound/unbound.conf/) details each option and its expected value(s).

## Development

Linting runs locally through [lefthook](https://github.com/evilmartians/lefthook). Install the hooks once per clone:

```bash
lefthook install
```

`pre-commit` runs [editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker), [hadolint](https://github.com/hadolint/hadolint), `jq`, [shellcheck](https://github.com/koalaman/shellcheck), [typos](https://github.com/crate-ci/typos) and [yamllint](https://github.com/adrienverge/yamllint) over the staged files, and `commit-msg` enforces [Conventional Commits](https://www.conventionalcommits.org). Run everything on demand with:

```bash
lefthook run pre-commit --all-files
```

### Bumping unbound

`UNBOUND_VERSION` is managed by renovate, which resolves it through the [NLnet Labs GitHub releases](https://github.com/NLnetLabs/unbound/releases). Release candidates are only tagged there, never released, so renovate proposes final releases alone. The Dockerfile downloads the matching tarball from [nlnetlabs.nl](https://nlnetlabs.nl/downloads/unbound/) and verifies its signature, and the image tags follow the unbound release.

## Version
- **29/09/26:** Build on wolfi by default and publish alpine under its own tags, for amd64 and arm64
- **29/09/26:** Build unbound 1.26.1 from the signed NLnet Labs release rather than the alpine package
- **29/09/26:** Keep the DNSSEC trust anchor in /config, where unbound can update it
- **04/07/25:** Updated to use alpine 3.22 image and s6 v3 service structure
- **12/08/21:** Fix root.hints and trusted-key.key
- **12/06/21:** Drop edge version of applications
- **07/12/20:** Install edge version of musl
- **03/11/20:** Drop permissions through Unbound, fix logging and remove libcap requirement
- **03/11/20:** Initial Release
