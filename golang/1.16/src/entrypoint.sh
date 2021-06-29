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


if [[ $ACTION = "build" && -f build.sh ]]; then
    log_msg "Found build.sh file"
    log_msg "Checking cache dir"
    if [[ -d "${GITHUB_WORKSPACE}/.cache-modules" ]]; then
        mkdir -p /go/pkg/mod
        ls -lh "${GITHUB_WORKSPACE}/.cache-modules"
        mv "${GITHUB_WORKSPACE}/.cache-modules/"* /go/pkg/mod/
    fi
    if [[ -d "${GITHUB_WORKSPACE}/.cache-go-build" ]]; then
        log_msg "Cache go-build exists!"
        mkdir -p ~/.cache/go-build
        mv "${GITHUB_WORKSPACE}/.cache-go-build/"* ~/.cache/go-build/
    fi
    log_msg "Executing build.sh script"
    bash ./build.sh
    ls -lh
    log_msg "Caching build and modules..."
    mv -v ~/.cache/go-build "${GITHUB_WORKSPACE}/.cache-go-build"
    # ls -lh "${GITHUB_WORKSPACE}/.cache-go-build"
    mv -v /go/pkg/mod "${GITHUB_WORKSPACE}/.cache-modules"
    # ls -lh "${GITHUB_WORKSPACE}/.cache-modules"
elif [[ $ACTION = "test" ]]; then
    cd ./golang || exit 1
    go test -v
elif [[ $ACTION = "dependencies" ]]; then
    log_msg "Getting dependencies ..."
    go mod download # -json
    mv /go/pkg/mod "${GITHUB_WORKSPACE}/.cache-modules"
else
    error_msg "Unknown action"
fi
