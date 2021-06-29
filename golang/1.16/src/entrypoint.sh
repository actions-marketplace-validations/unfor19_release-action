#!/bin/bash
source /code/bargs.sh "$@"

set -e
set -o pipefail

### Functions
error_msg(){
  local msg="$1"
  local code="${2:-"1"}"
  echo -e "[ERROR] $(date) :: [CODE=$code] $msg"
  exit "$code"
}


log_msg(){
  local msg="$1"
  echo -e "[LOG] $(date) :: $msg"
}

log_msg "Running as $(whoami)"
_SRC_DIR="${SRC_DIR:-""}"

if [[ $ACTION = "build" && -f build.sh ]]; then
    log_msg "Found build.sh file"
    log_msg "Checking cache dir"
    if [[ -d "${GITHUB_WORKSPACE}/.cache-modules" ]]; then
        log_msg "Using ${GITHUB_WORKSPACE}/.cache-modules"
        mkdir -p /go/pkg/mod
        ls -lh "${GITHUB_WORKSPACE}/.cache-modules"
        cp -r "${GITHUB_WORKSPACE}/.cache-modules"/* /go/pkg/mod/
    fi
    if [[ -d "${GITHUB_WORKSPACE}.cache-go-build/" ]]; then
        log_msg "Cache go-build exists!"
        mkdir -p ~/.cache/go-build
        mv "${GITHUB_WORKSPACE}.cache-go-build/"* ~/.cache/go-build/
    fi
    log_msg "Executing build.sh script"
    bash ./build.sh
    log_msg "Finished building app"
    ls -lh
    log_msg "Caching build and modules..."
    mkdir -p "${GITHUB_WORKSPACE}.cache-go-build/"
    mv ~/.cache/go-build/* "${GITHUB_WORKSPACE}.cache-go-build/"
    log_msg "Setting ownership of .cache-go-build to current user ..."
    chown -R 1001:121 "${GITHUB_WORKSPACE}.cache-go-build"
    log_msg "Setting ownership of ${GITHUB_WORKSPACE}/.cache-modules to current user ..."
    chown -R 1001:121 "${GITHUB_WORKSPACE}/.cache-modules"
    ls -lah
elif [[ $ACTION = "test" ]]; then
    [[ "$_SRC_DIR" ]] && cd "$_SRC_DIR"
    go test -v
elif [[ $ACTION = "dependencies" ]]; then
    log_msg "Getting dependencies ..."
    [[ "$_SRC_DIR" ]] && cd "$_SRC_DIR"
    go mod download # -json
    mkdir -p "${GITHUB_WORKSPACE}/.cache-modules"
    mv /go/pkg/mod/* "${GITHUB_WORKSPACE}/.cache-modules/"
    chown -R 1001:121 "${GITHUB_WORKSPACE}/.cache-modules"
    ls -lh "${GITHUB_WORKSPACE}/.cache-modules"
else
    error_msg "Unknown action"
fi

log_msg "Successfully completed $ACTION step"