#!/bin/bash
source /code/bargs.sh "$@"
ls -lh
echo "PWD = $PWD"
echo "$GITHUB_WORKSPACE"
echo "$LANG_NAME"
echo "$LANG_VERSION"
echo "::set-output name=lang_name::$LANG_NAME"
echo "::set-output name=lang_version::$LANG_VERSION"
if [[ -f build.sh ]]; then
    echo "found build.sh file"
    bash ./build.sh
    echo "executing app"
    ./app
else
    echo "build.sh file not found"
fi