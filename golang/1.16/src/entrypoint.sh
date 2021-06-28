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
    mkdir -p /go/pkg/mod
    ln -s ./.cache-modules /go/pkg/mod
    ls -lh /go/pkg/mod/ || true
    if [[ -L "${HOME}/.cache/go-build" ]]; then
        log_msg "Cache go-build exists!"
        ln -s ./.cache-go-build ~/.cache/go-build
        ls -lh /go/pkg/mod/ || true
    fi
    log_msg "Executing build.sh script"
    bash ./build.sh
    ls -lh
    log_msg "Caching build ..."
    mv ~/.cache/go-build ./.cache-go-build/
elif [[ $ACTION = "test" ]]; then
    cd ./golang || exit 1
    go test -v
elif [[ $ACTION = "dependencies" ]]; then
    log_msg "Getting dependencies ..."
    mkdir -p /go/pkg/mod
    ln -s ./.cache-modules /go/pkg/mod
    go mod download -json
    ls -lh /go/pkg/mod || true
else
    error_msg "Unknown action"
fi
