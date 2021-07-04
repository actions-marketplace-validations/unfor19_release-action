# release-action

[![Release-Test](https://github.com/unfor19/release-action-test/actions/workflows/go-release.yml/badge.svg)](https://github.com/unfor19/release-action-test/actions/workflows/go-release.yml)

This action is tested in [unfor19/release-action-test](https://github.com/unfor19/release-action-test)

## Supported Languages

- [Golang](https://golang.org/)
- TODO: node
- TODO: python
- TODO: docker (tar.gz)
- TODO: java
- TODO: rust

## Example Workflow

This workflow can build any Golang application, tested on [golang-example](https://github.com/unfor19/release-action-test/tree/master/golang), [terraform](https://github.com/hashicorp/terraform) and [gin-tonic](https://github.com/gin-gonic/gin).

```yaml
name: Release-Test

on:
  push:
    branches:
      - master # creates a pre-release
  release:
    types:
      - released # does not include pre-release
  workflow_dispatch:
    inputs:
      branch:
        description: "Branch to set as prerelease"
        required: false
        default: "master"

jobs:
  test:
    name: Test
    runs-on: ubuntu-20.04
    steps:
      - uses: actions/checkout@master
      - name: Cache Go Build
        id: cache-go-build
        uses: actions/cache@v2
        with:
          path: |
            .cache-go-build
          key: ${{ runner.os }}-go-build-test-${{ hashFiles('**/go.sum') }}-app-v2
          restore-keys: |
            ${{ runner.os }}-go-build-test-${{ hashFiles('**/go.sum') }}-app-v2
      - name: Cache Go Modules
        id: cache-go-modules
        uses: actions/cache@v2
        with:
          path: |
            .cache-modules
          key: ${{ runner.os }}-go-modules-test-${{ hashFiles('**/go.sum') }}-app-v2
          restore-keys: |
            ${{ runner.os }}-go-modules-test-${{ hashFiles('**/go.sum') }}-app-v2
      - name: Get Dependencies
        if: steps.cache-go-modules.outputs.cache-hit != 'true'
        uses: unfor19/release-action/golang/1.16@master
        with:
          action: dependencies
          src-dir: golang
          project-name: app
      - name: Go Test
        uses: unfor19/release-action/golang/1.16@master
        with:
          action: test
          src-dir: golang
          project-name: app
      - name: Upload Test Results As Artifact
        uses: actions/upload-artifact@v2
        if: always()
        with:
          name: test_report
          path: test_report.html
  release:
    name: Release
    runs-on: ubuntu-20.04
    needs:
      - test
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
          - GOARCH: "amd64"
            GOOS: "windows"
    env:
      GOOS: ${{ matrix.GOOS }}
      GOARCH: ${{ matrix.GOARCH }}
    steps:
      - uses: actions/checkout@master
      - name: Cache Go Build
        id: cache-go-build
        uses: actions/cache@v2
        with:
          path: |
            .cache-go-build
          key: ${{ runner.os }}-go-build-${{ matrix.GOOS }}-${{ matrix.GOARCH }}-${{ hashFiles('**/go.sum') }}-app-v2
          restore-keys: |
            ${{ runner.os }}-go-build-${{ matrix.GOOS }}-${{ matrix.GOARCH }}-${{ hashFiles('**/go.sum') }}-app-v2
      - name: Cache Go Modules
        id: cache-go-modules
        uses: actions/cache@v2
        with:
          path: |
            .cache-modules
          key: ${{ runner.os }}-go-modules-${{ matrix.GOOS }}-${{ matrix.GOARCH }}-${{ hashFiles('**/go.sum') }}-app-v2
          restore-keys: |
            ${{ runner.os }}-go-modules-${{ matrix.GOOS }}-${{ matrix.GOARCH }}-${{ hashFiles('**/go.sum') }}-app-v2
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
      - name: Release
        uses: unfor19/release-action/golang/1.16@master
        with:
          action: release
          src-dir: golang
          project-name: app
          gh-token: ${{ secrets.GH_TOKEN }}
```

## Actions

Expand to see a full description and behavior of each action.

<details>

<summary>Expand/Collapse</summary>

### Dependencies

#### Input

```yaml
with:
  action: dependencies
```

#### Description

Downloads and installs dependencies. Supports using the official [cache](https://github.com/actions/cache). This step is skipped if there's a cache hit.

### Build

#### Input

```yaml
with:
  action: build
  build-script-path: ""
```

#### Description

Builds the artifacts. Supports using the official [cache](https://github.com/actions/cache). The caching mechanism decreases the build time significantly (tested in Golang).

#### Behavior

Attempts to find `build-script-path`, if the file exists it will be executed. If the file does not exist, this action will use a default build process.

An example for a build script in Golang

```bash
#!/bin/bash
cd ./golang || exit 1

if [[ "$GOOS" = "windows" ]]; then
    _EXT=".exe"
fi

go build -o "app${_EXT}"
```

#### Test

#### Input

```yaml
with:
  action: test
```

#### Description

Executes tests

#### Behavior

For Golang, this action runs `go test ./... -v`.

#### Release

#### Input

```yaml
with:
  action: release
  gh-token: ${{ secrets.GH_TOKEN }}
```

#### Description

Automatically upload release assets upon `git push` event. Also updates a newly created release by uploading assets to the release.

#### Behavior

 - On Release `released` - created a new release
    1. Checks if release has assets, if not continue
    2. Uploads build artifacts as release assets, including md5 checksum `.txt` per asset
 - On Push to `master` - pushed to main branch
    1. Checks latest published release, for example `1.0.0rc1`
    2. Saves the value of the bumped latest current release, for example `1.0.0rc2`
    3. Checks if the bumped release version exists as a pre-release, if not creates a pre-release, for example `1.0.0rc2`
    4. Checks if artifacts exist in the pre-release, if yes delete them. The deletion process runs per job, so linux-amd64 will delete its exsiting artifacts, same goes for the job darwin-amd64, and so on.
    5. Uploads artifacts as assets to the pre-release, for example `app_1.0.0rc2_linux_amd64`, `app_0.0.3rc2_linux_amd64_sha256.txt`, `app_1.0.0rc2_darwin_amd64`, `app_1.0.0rc2_darwin_amd64_sha256.txt`, etc.
    6. Syncs release tag with the current commit, so the source code files `.zip` and `.tgz` match the release's commit SHA.<br>
       **Known Caveat**: Release timestamp is not updated when pushing artifacts

</details>

## Authors

Created and maintained by [Meir Gabay](https://github.com/unfor19)


## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/unfor19/release-action/blob/master/LICENSE) file for details