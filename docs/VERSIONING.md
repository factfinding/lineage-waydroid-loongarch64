# Versioning

The integration uses semantic version tags in the form `vMAJOR.MINOR.PATCH`.

- The same integration tag is placed on the exact commits of the public Android, LineageOS, Waydroid-device and Chromium source forks used by that snapshot.
- The `lineage-waydroid-loongarch64` tag is the entry point. Its `projects.tsv` records every project commit and source-tree hash.
- Checking out an integration tag and running `install-local-manifests.sh` pins published forks to the matching tag. Running the script from an untagged development commit continues to use the development branches.
- Deployable image releases use `vMAJOR.MINOR.PATCH-lineage-23.2` in `waydroid-loongarch64-builds` and refer back to the corresponding source tag.
- Independently packaged host components retain upstream-derived component tags, such as `loongarch64-1.6.3-rel2` for Waydroid and `lxc-7.0.0-1-loongarch64` for AOSC LXC.
- Release-specific external and host component revisions are recorded under `releases/<version>/components.tsv`.

`v0.2.2` is the first coordinated public source tag. Earlier image releases predate this source-versioning policy.
