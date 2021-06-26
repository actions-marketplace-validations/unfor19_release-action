#!/bin/bash
source /code/bargs.sh "$@"

echo "$LANG_NAME"
echo "$LANG_VERSION"
echo "::set-output name=lang_name::$LANG_NAME"
echo "::set-output name=lang_version::$LANG_VERSION"
