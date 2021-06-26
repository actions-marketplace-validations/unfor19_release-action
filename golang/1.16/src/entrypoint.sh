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
    bash ./build.sh
    echo "$GOPATH"
    ls -lh "${GOPATH}/pkg/mod/cache/download/github.com/"
    log_msg "Executing app"
    ./golang/app
elif [[ $ACTION = "test" ]]; then
    cd ./golang || exit 1
    go test -v
elif [[ $ACTION = "dependencies" ]]; then
    cd ./golang || exit 1
    go mod download -json
else
    error_msg "Unknown action"
fi
