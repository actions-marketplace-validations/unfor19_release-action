# release-action

[![Release-Test](https://github.com/unfor19/release-action-test/actions/workflows/go-release.yml/badge.svg)](https://github.com/unfor19/release-action-test/actions/workflows/go-release.yml)

This action is tested in [unfor19/release-action-test](https://github.com/unfor19/release-action-test)

## Requirements

A file named `build.sh` at the root folder of the repository. If the file does not exist, this action will use a default build process.

An example for `build.sh` in Golang

```bash
#!/bin/bash
cd ./golang || exit 1

if [[ "$GOOS" = "windows" ]]; then
    _EXT=".exe"
fi

go build -o "app${_EXT}"
```

## Example Workflow

```yaml
name: Release-Test

on:
  push:
    branches:
      - master # creates a pre-release
  release:
    types:
      - released # does not include pre-release
jobs:
  release:
    name: Release
    runs-on: ubuntu-20.04
    strategy:
      matrix:
        include:
          - GOARCH: "amd64"
            GOOS: "linux"
          - GOARCH: "386"
            GOOS: "linux"
          - GOARCH: "arm64"
            GOOS: "linux"
          - GOARCH: "amd64"
            GOOS: "darwin"
          - GOARCH: "arm64"
            GOOS: "darwin"
          - GOARCH: "amd64"
            GOOS: "windows"
    env:
      GOOS: ${{ matrix.GOOS }}
      GOARCH: ${{ matrix.GOARCH }}
    steps:
      - uses: actions/checkout@master
      - name: Cache Go Build and Modules
        id: cache-go-modules
        uses: actions/cache@v2
        with:
          # Don't change the paths
          path: |
            .cache-modules
            .cache-go-build
          # CHANGE the path to go.sum
          key: ${{ runner.os }}-golang-${{ matrix.GOOS }}-${{ matrix.GOARCH }}-${{ hashFiles('golang/go.sum') }}-v1
          restore-keys: |
            ${{ runner.os }}-golang-${{ matrix.GOOS }}-${{ matrix.GOARCH }}-
      - name: Get Dependencies
        if: steps.cache-go-modules.outputs.cache-hit != 'true'
        uses: unfor19/release-action/golang/1.16@master
        with:
          action: dependencies
          src-dir: golang
          project-name: app
      - name: Go Build
        uses: unfor19/release-action/golang/1.16@master
        with:
          action: build
          src-dir: golang
          project-name: app
      - name: Go Test
        uses: unfor19/release-action/golang/1.16@master
        with:
          action: test
          src-dir: golang
          project-name: app
      - name: Release
        uses: unfor19/release-action/golang/1.16@master
        with:
          action: release
          src-dir: golang
          project-name: app
          gh-token: ${{ secrets.GH_TOKEN }}
```

## Actions

1. `dependencies` - Downloads and installs dependencies. Supports using the official [cache](https://github.com/actions/cache). This step is skipped if there's a cache hit.
2. Build - Builds the artifacts. Supports using the official [cache](https://github.com/actions/cache). The caching mechanism decreases the build time significantly (tested in Golang).
3. Test - Execute tests
4. Release
   1. On Release `released` - created a new release
      1. Checks if release has assets, if not continue
      2. Uploads build artifacts as release assets, including md5 checksum `.txt` per asset
   2. On Push to `master` - pushed to main branch
      1. Checks latest published release, for example `1.0.0rc1`
      2. Saves the value of the bumped latest current release, for example `1.0.0rc2`
      3. Checks if the bumped release version exists as a pre-release, if not creates a pre-release, for example `1.0.0rc2`
      4. Checks if artifacts exist in the pre-release, if yes delete them. The deletion process runs per job, so linux-amd64 will delete its exsiting artifacts, same goes for the job darwin-amd64, and so on.
      5. Uploads artifacts as assets to the pre-release, for example `app_1.0.0rc2_linux_amd64`, `app_0.0.3rc2_linux_amd64_sha256.txt`, `app_1.0.0rc2_darwin_amd64`, `app_1.0.0rc2_darwin_amd64_sha256.txt`, etc.
      6. Syncs release tag with the current commit, so the source code files `.zip` and `.tgz` match the release's commit SHA.<br>
         **Known Caveat**: Release timestamp is not updated when pushing artifacts

## Supported Languages

- golang
- TODO: node
- TODO: python
- TODO: docker (tar.gz)
- TODO: java
- TODO: rust

## Authors

Created and maintained by [Meir Gabay](https://github.com/unfor19)


## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/unfor19/release-action/blob/master/LICENSE) file for details