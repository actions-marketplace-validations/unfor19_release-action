#!/bin/bash
source /code/bargs.sh "$@"

echo "PWD = $PWD"
if [[ $ACTION = "build" && -f build.sh ]]; then
    echo "found build.sh file"
    bash ./build.sh
    echo "executing app"
    ./golang/app
elif [[ $ACTION = "test" ]]; then
    cd ./golang || exit 1
    go test -v
else
    echo "unknown action"
fi