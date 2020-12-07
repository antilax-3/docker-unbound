[logo]: https://ci.nerv.com.au/userContent/antilax-3.png "AntilaX-3"
[![alt text][logo]](https://github.com/AntilaX-3/)

# AntilaX-3/unbound
[![](https://images.microbadger.com/badges/version/antilax3/unbound.svg)](https://microbadger.com/images/antilax3/unbound "Get your own version badge on microbadger.com") [![](https://images.microbadger.com/badges/image/antilax3/unbound.svg)](https://microbadger.com/images/antilax3/unbound "Get your own image badge on microbadger.com") [![Docker Pulls](https://img.shields.io/docker/pulls/antilax3/unbound.svg)](https://hub.docker.com/r/antilax3/unbound/) [![Docker Stars](https://img.shields.io/docker/stars/antilax3/unbound.svg)](https://hub.docker.com/r/antilax3/unbound/)

[Unbound](https://www.nlnetlabs.nl/projects/unbound/about/) is a validating, recursive, caching DNS resolver. 
## Usage
```
docker create --name=unbound \
-v <path to config>:/config \
-p 53:53 \
-p 53:53/udp \
antilax3/unbound
```
## Parameters
The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side. For example with a volume -v external:internal - what this shows is the volume mapping from internal to external of the container. So -v /mnt/app/config:/config would map /config from inside the container to be accessible from /mnt/app/config on the host's filesystem.

- `-v /config` - local path for Unbound config file
- `-p 53` - TCP port for Unbound
- `-p 53/udp` - UDP port for Unbound
- `-e PUID` - for UserID, see below for explanation
- `-e PGID` - for GroupID, see below for explanation
- `-e TZ` - for setting timezone information, eg Australia/Melbourne

It is based on alpine linux with s6 overlay, for shell access whilst the container is running do `docker exec -it unbound /bin/bash`.

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

## Version
- **07/12/20:** Install edge version of musl
- **03/11/20:** Drop permissions through Unbound, fix logging and remove libcap requirement
- **03/11/20:** Initial Release