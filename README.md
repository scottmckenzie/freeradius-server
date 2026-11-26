# FreeRADIUS ARM64 image

Multi-arch (linux/amd64, linux/arm64) FreeRADIUS 3.2.x image built from
the upstream release tag, published to
`ghcr.io/scottmckenzie/freeradius-server`.

Reference: https://github.com/FreeRADIUS/freeradius-server/tree/v3.2.x/scripts/docker

## Differences from the stock configuration

- `inner-tunnel` is disabled.
- The `rewrite_called_station_id` policy is enabled in the `default`
  site, creating `Called-Station-MAC` and `Called-Station-SSID`.
- `radiusd` drops privileges to `radius:radius` after startup.
- The server log goes to stdout (`podman logs` / `docker logs`) instead
  of `radius.log`, via `-l stdout` in the entrypoint. This overrides a
  mounted `radiusd.conf`. Accounting `detail` and `linelog` output still
  go to files.
- `auth = yes`: each login accept/reject is logged.

## Mounting configuration

`radiusd` loads modules after dropping privileges, so every mounted
config file must be readable by the `radius` user (mode `0644`, or
group-readable by the `radius` group). On startup the entrypoint sets
`clients.conf`, `radiusd.conf` and `mods-config/files/authorize` to
group `radius`, mode `0640`. It warns instead of failing when it can't,
for example on a read-only mount, and warns if `radius` cannot read the
file.

## Upgrading FreeRADIUS

Change `VERSION` in `.github/workflows/ci.yml`. It maps
to the upstream tag, e.g. `3.2.10` becomes `release_3_2_10`. Every
branch builds the image; only pushes to `main` publish it.
