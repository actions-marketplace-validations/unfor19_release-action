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

version_validation(){
  local release_version="$1"
  if [[ $release_version =~ ^[0-9]+(\.[0-9]*)*(\.[0-9]+(a|b|rc)|(\.post)|(\.dev))*[0-9]+$ ]]; then
    log_msg "Passed - Release version is valid - $release_version"
  else
    error_msg "Failed - Release version is invalid - $release_version"
  fi
}


bump_version(){
  # SemVer Regex: ^[0-9]+(\.[0-9]*)*(\.[0-9]+(a|b|rc)|(\.post)|(\.dev))*[0-9]+$
  local version="$1"
  local delimiter="."
  local version_last_block=""
  local version_last_block_bumped=""
  local version_last_block_numbers=""
  local version_last_block_alpha=""
  local version_last_block_pre=""
  local bumped_version=""
  version_last_block="$(echo "$version" | rev | cut -d${delimiter} -f1 | rev)"
  if  [[ "$version_last_block" =~ ^[0-9]+[a-zA-Z]+[0-9]+$ ]]; then
    # Number and string and number
    version_last_block_pre=$(echo "$version_last_block" | sed 's~[A-Za-z]~ ~g' | cut -d' ' -f1)
    version_last_block_alpha="${version_last_block//[0-9]/}"
    version_last_block_numbers=$(echo "$version_last_block" | sed 's~[A-Za-z]~ ~g' | rev | cut -d' ' -f1 | rev)
    version_last_block_bumped="$((version_last_block_numbers+1))"
  elif [[ "$version_last_block" =~ ^[0-9]+$ ]]; then
    # Number only
    version_last_block_bumped="$((version_last_block+1))"
  else
    error_msg "Unknown pattern"
  fi

  bumped_version="${version%.*}.${version_last_block_pre}${version_last_block_alpha}${version_last_block_bumped}"

  if [[ "$bumped_version" =~ ${version} ]]; then
    error_msg "Version did not bump - ${bumped_version}"
  fi

  echo "$bumped_version"
}


gh_upload_asset(){
  local asset_type="${1:-""}"
  local asset_data="${2:-""}"
  local name_suffix="${3:-""}"
  local content_type=""
  local target_url=""
  local asset_name=""
  local target_delete_asset_url=""
  declare -a data_flag
  log_msg "Asset type: ${asset_type}"
  if [[ "$asset_type" = "txt" ]]; then
    asset_name="${_RELEASE_ARTIFACT_NAME}_${name_suffix}"
    content_type="text/plain"
    data_flag=("--data" " ")
  elif [[ "$asset_type" = "binary" ]]; then
    asset_name="${_RELEASE_ARTIFACT_NAME}"
    content_type="application/octet-stream"
    data_flag=("--data-binary" "@")
  fi

  target_delete_asset_url="$(echo "$_RELEASE_ASSETS" | jq -rc '.[] | select(.name=="'"${asset_name}"'") | .url')"  

  log_msg "Asset name: ${asset_name}"
  log_msg "Checking if asset already exists ..."
  if [[ -n "$target_delete_asset_url" ]] ; then
    log_msg "Deleting asset - ${target_delete_asset_url}"
    curl \
      --fail \
      --connect-timeout "$_CONNECT_TIMEOUT" \
      --retry-all-errors \
      --retry "$_CONNECT_RETRY" \
      --retry-delay "$_RETRY_DELAY" \
      -X "DELETE" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer ${_GH_TOKEN}" \
      "$target_delete_asset_url" | jq
  fi

  log_msg "Asset will be created with POST"
  target_url="${_UPLOAD_URL}?name=${asset_name}"
  log_msg "Target URL for upload: $target_url"
  log_msg "-X POST ${data_flag[*]}${asset_data} -H Content-Type: ${content_type} -H Authorization: Bearer HIDDEN"
  curl \
    --fail \
    --connect-timeout "$_CONNECT_TIMEOUT" \
    --retry-all-errors \
    --retry "$_CONNECT_RETRY" \
    --retry-delay "$_RETRY_DELAY" \
    -X "POST" ${data_flag[*]}"${asset_data}" \
    -H "Content-Type: ${content_type}" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer ${_GH_TOKEN}" \
    "$target_url" | jq
}


default_build(){
  local project_root="/go/src/github.com/${GITHUB_REPOSITORY}"
  local file_extenstion=""
  local artifact_name="${_PROJECT_NAME}"
  mkdir -p "$project_root"
  rmdir "$project_root"
  ln -s "$GITHUB_WORKSPACE" "$project_root"
  cd "${project_root}/${_SRC_DIR}"
  go mod download
  file_extenstion=''

  if [[ "$GOOS" = 'windows' ]]; then
    file_extenstion='.exe'
  fi

  go build -o "${artifact_name}${file_extenstion}"
}


sync_commit_tag(){
  local tag_name="$1"
  local github_repository="$2"
  local current_sha=""
  local response=""
  local github_ref=""
  local future_sha=""
  future_sha="$(git rev-parse HEAD)"
  github_ref="refs/tags/${tag_name}"
  log_msg "Syncing release tag and current commit ..."

  log_msg "Checking if it's necessary to sync ..."
  response="$(curl \
    --fail \
    --connect-timeout "$_CONNECT_TIMEOUT" \
    --retry-all-errors \
    --retry "$_CONNECT_RETRY" \
    --retry-delay "$_RETRY_DELAY" \
    -X "GET" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: Bearer ${_GH_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${github_repository}/git/${github_ref}" | jq)"
  current_sha="$(echo "$response" | jq -cr '.object.sha')"
  if [[ "$current_sha" = "$future_sha" ]]; then
    log_msg "Tag ${tag_name} is already synced with the commit ${future_sha}"
  else
    log_msg "Replacing ${current_sha} tag ${tag_name} with ${future_sha}"
    curl \
      --fail \
      --connect-timeout "$_CONNECT_TIMEOUT" \
      --retry-all-errors \
      --retry "$_CONNECT_RETRY" \
      --retry-delay "$_RETRY_DELAY" \
      -X "PATCH" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer ${_GH_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"sha":"'"$future_sha"'","force": true}' \
      "https://api.github.com/repos/${github_repository}/git/${github_ref}" | jq
  fi
}

# TODO: Split
gh_release(){
    log_msg "Event Type: $GITHUB_EVENT_NAME"
    if [[ "$_PRE_RELEASE" = "true" || "$GITHUB_EVENT_NAME" = "push" || "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]]; then
        log_msg "Will publish as PRE-RELEASE"
        _PRE_RELEASE_FLAG="--prerelease"
    fi

    if [[ "$_OVERWRITE_RELEASE" = "true" || "$GITHUB_EVENT_NAME" = "push" || "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]]; then
        log_msg "Will overwrite existing assets if any"
        _OVERWRITE_RELEASE="true"
    fi

    EVENT_DATA=$(cat "$GITHUB_EVENT_PATH")
    if [[ "$GITHUB_EVENT_NAME" = "release" ]]; then
        ### Use this release
        _UPLOAD_URL=$(echo "$EVENT_DATA" | jq -r .release.upload_url)
        _UPLOAD_URL=${_UPLOAD_URL/\{?name,label\}/}
        RELEASE_NAME=$(echo "$EVENT_DATA" | jq -r .release.tag_name)
        _RELEASE_DETAILS="$(gh api -H 'Accept: application/vnd.github.v3.raw+json' /repos/"$GITHUB_REPOSITORY"/releases | jq '.[] | select(.name=="'"$RELEASE_NAME"'")')"
        _UPLOAD_URL="$(echo "$_RELEASE_DETAILS" | jq -rc '. | .upload_url')"
        _UPLOAD_URL="${_UPLOAD_URL/\{*/}" # Cleanup
        _RELEASE_ASSETS=$(echo "$_RELEASE_DETAILS" | jq '. | .assets')
        if [[ "$(echo "$_RELEASE_DETAILS" | jq '. | .assets')" != "[]" ]] ; then
            log_msg "Release already has artifacts, skipping upload step"
            log_msg "$(echo "$_RELEASE_ASSETS" | jq -r '.[] | .name')"
            log_msg "Successfully skipped"
            exit 0
        fi
    elif [[ "$GITHUB_EVENT_NAME" = "push" || "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]]; then
        ### Creates a new release and use it
        # Authenticate with GitHub
        gh config set prompt disabled
        if gh auth status 2>/dev/null ; then
            log_msg "Authenticated with GitHub CLI"
        else
            log_msg "Attempting to login to GitHub with the GitHub CLI and GH_TOKEN"
            echo "$_GH_TOKEN" | gh auth login --with-token
        fi

        # Bump version and create release
        log_msg "Getting latest release version ..."
        LATEST_VERSION="$(curl --fail -s -H "Authorization: Bearer ${_GH_TOKEN}" https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/latest | grep "tag_name" | cut -d ':' -f2 | cut -d '"' -f2 2>/dev/null || true)"
        if [[ -z "$LATEST_VERSION" ]]; then
            error_msg "Error getting latest release version, if this is the first release ever, create a new release in GitHub"
        fi
        log_msg "Latest Release version: ${LATEST_VERSION}"
        version_validation "${LATEST_VERSION}"
        RELEASE_NAME=$(bump_version "$LATEST_VERSION")
        log_msg "Bumped Latest Release version: ${RELEASE_NAME}"
        log_msg "Attempting to create the new release ..."
        # Create Release if does not exist - no assets yet
        if gh release create "$RELEASE_NAME" -t "$RELEASE_NAME" -R "${GITHUB_REPOSITORY}" $_PRE_RELEASE_FLAG >/dev/null ; then
            log_msg "Successfully created the release https://github.com/${GITHUB_REPOSITORY}/releases/tag/${RELEASE_NAME}"
        fi

        _RELEASE_DETAILS="$(gh api -H 'Accept: application/vnd.github.v3.raw+json' /repos/"$GITHUB_REPOSITORY"/releases | jq '.[] | select(.name=="'"$RELEASE_NAME"'")')"
        _UPLOAD_URL="$(echo "$_RELEASE_DETAILS" | jq -rc '. | .upload_url')"
        _UPLOAD_URL="${_UPLOAD_URL/\{*/}" # Cleanup
        _RELEASE_ASSETS=$(echo "$_RELEASE_DETAILS" | jq '. | .assets')
    else
        error_msg "Unhandled event type - ${GITHUB_EVENT_PATH}"
    fi

    log_msg "Target release version: ${RELEASE_NAME}"
    log_msg "Target release upload url for assets: ${_UPLOAD_URL}"

    version_validation "$RELEASE_NAME"

    sync_commit_tag "$RELEASE_NAME" "$GITHUB_REPOSITORY"

    _PUBILSH_CHECKSUM_SHA256="${PUBILSH_CHECKSUM_SHA256:-"true"}"
    _PUBILSH_CHECKSUM_MD5="${PUBILSH_CHECKSUM_MD5:-"false"}"
    NAME="${NAME:-${_PROJECT_NAME}_${RELEASE_NAME}}_${GOOS}_${GOARCH}"
    _EXTRA_FILES="${EXTRA_FILES:-""}"
    _COMPRESS="${COMPRESS:-"false"}"
    _RELEASE_ARTIFACT_NAME="${RELEASE_ARTIFACT_NAME:-"$NAME"}"
    _GO_ARTIFACT_NAME="${GO_ARTIFACT_NAME:-"$_PROJECT_NAME"}"

    if [[ "$_EXTRA_FILES" = "" ]]; then
        log_msg "EXTRA_FILES not set"
    fi
    
    FILE_LIST="${FILE_LIST} ${_EXTRA_FILES}"
    FILE_LIST=$(echo "${FILE_LIST}" | awk '{$1=$1};1')

    log_msg "Preparing final artifact ..."
    log_msg "$FILE_LIST"
    if [[ "$GOOS" = "windows" ]]; then
        if [[ "$_EXTRA_FILES" != "" || "$_COMPRESS" = "true" ]]; then
            _ARTIFACT_SUFFIX=".zip"
            _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
            _ARTIFACT_PATH="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
            zip -9r "$_ARTIFACT_PATH" ${FILE_LIST} # FILE_LIST unquoted on purpose
        else
            _ARTIFACT_SUFFIX=".exe"
            _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
            _ARTIFACT_PATH="${_GO_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
        fi
    else
        # linux or macos-darwin
        if [[ "$_EXTRA_FILES" != "" || "$_COMPRESS" = "true" ]]; then
            _ARTIFACT_SUFFIX=".tgz"
            _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
            _ARTIFACT_PATH="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
            tar cvfz "$_ARTIFACT_PATH" ${FILE_LIST} # FILE_LIST unquoted on purpose
        else
            _ARTIFACT_SUFFIX=""
            _RELEASE_ARTIFACT_NAME="${_RELEASE_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
            _ARTIFACT_PATH="${_GO_ARTIFACT_NAME}${_ARTIFACT_SUFFIX}"
        fi
    fi
    ls -lh "$_ARTIFACT_PATH"
    log_msg "Final artifact is ready - $_ARTIFACT_PATH"

    _CHECKSUM_MD5=$(md5sum "$_ARTIFACT_PATH" | cut -d ' ' -f 1)
    _CHECKSUM_SHA256=$(sha256sum "$_ARTIFACT_PATH" | cut -d ' ' -f 1)
    log_msg "md5sum - $_CHECKSUM_MD5"
    log_msg "sha256sum - $_CHECKSUM_SHA256"

    log_msg "Uploading artifact - $_ARTIFACT_PATH"
    gh_upload_asset "binary" "$_ARTIFACT_PATH"

    if [[ "$_PUBILSH_CHECKSUM_SHA256" = "true" ]]; then
        log_msg "Uploading SHA256 checksum ..."
        gh_upload_asset "txt" "$_CHECKSUM_SHA256" "sha256.txt"
    fi

    if [[ "$_PUBILSH_CHECKSUM_MD5" = "true" ]]; then
        log_msg "Uploading MD5 checksum ..."
        gh_upload_asset "txt" "$_CHECKSUM_MD5" "md5.txt"
    fi
}

restore_dependencies_cache(){
    log_msg "Checking dependencies cache dir"
    if [[ -d "${GITHUB_WORKSPACE}/.cache-modules/" ]]; then
        log_msg "Using ${GITHUB_WORKSPACE}/.cache-modules"
        mkdir -p /go/pkg/mod
        ls -lh "${GITHUB_WORKSPACE}/.cache-modules"
        cd "${GITHUB_WORKSPACE}/.cache-modules"
        tar cf - . | pv | (cd /go/pkg/mod/; tar xf -)
        cd -
    else
        log_msg "Cache dir does not exist - ${GITHUB_WORKSPACE}/.cache-modules/"
    fi
    log_msg "Finished restoring dependencies"
}

restore_build_cache(){
    log_msg "Checking build cache dir"
    if [[ -d "${GITHUB_WORKSPACE}/.cache-go-build/" ]]; then
        log_msg "Cache go-build exists!"
        mkdir -p ~/.cache/go-build
        cd "${GITHUB_WORKSPACE}/.cache-go-build"
        tar cf - . | pv | (cd ~/.cache/go-build/; tar xf -)
        cd -
    else
        log_msg "Cache dir does not exist - ${GITHUB_WORKSPACE}/.cache-go-build/"
    fi
    log_msg "Finished restoring build"
}

build_app(){
    if [[ -z "$_BUILD_SCRIPT_PATH" && "$_BUILD_SCRIPT_PATH" != "false" && -f "$_BUILD_SCRIPT_PATH" ]]; then
        log_msg "Build With: ${_BUILD_SCRIPT_PATH}"
        log_msg "Building..."
        bash "$_BUILD_SCRIPT_PATH"
    else
        log_msg "Build With: Default"
        log_msg "Building..."
        default_build
    fi
    ls -lh
    log_msg "Finished building app"
}

cache_dependencies(){
  log_msg "Caching dependencies..."
  mkdir -p "${GITHUB_WORKSPACE}/.cache-modules"
  # cp -r /go/pkg/mod/* "${GITHUB_WORKSPACE}/.cache-modules"
  mv /go/pkg/mod/* "${GITHUB_WORKSPACE}/.cache-modules"
  log_msg "Setting ownership of ${GITHUB_WORKSPACE}/.cache-modules to 1001:121 ..."
  chown -R 1001:121 "${GITHUB_WORKSPACE}/.cache-modules"
  ls -lh "${GITHUB_WORKSPACE}/.cache-modules"
  log_msg "Finished caching dependencies"
}

cache_build(){
    log_msg "Caching build..."
    mkdir -p "${GITHUB_WORKSPACE}/.cache-go-build/"
    cp -r ~/.cache/go-build/* "${GITHUB_WORKSPACE}/.cache-go-build/"
    log_msg "Setting ownership of .cache-go-build to 1001:121 ..."
    chown -R 1001:121 "${GITHUB_WORKSPACE}/.cache-go-build"
    ls -lah
    log_msg "Finished caching build"
}


_PRE_RELEASE="${PRE_RELEASE:-""}"
_PRE_RELEASE_FLAG=""
_CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-"30"}"
_CONNECT_RETRY="${_CONNECT_RETRY:-"3"}"
_RETRY_DELAY="${RETRY_DELAY:-"20"}"
_OVERWRITE_RELEASE="${OVERWRITE_RELEASE:-""}"
_GH_TOKEN="${GH_TOKEN:-""}"
_BUILD_SCRIPT_PATH="${BUILD_SCRIPT_PATH:-"false"}"

log_msg "Running as $(whoami)"
_SRC_DIR="${SRC_DIR:-""}"
_PROJECT_NAME="${PROJECT_NAME:-"$(basename "$GITHUB_REPOSITORY")"}"
log_msg "Project Name: ${_PROJECT_NAME}"
log_msg "Source Dir: ${_SRC_DIR}"
if [[ $ACTION = "build" ]]; then
    ls -lh
    restore_dependencies_cache
    restore_build_cache
    build_app
    cache_build
elif [[ $ACTION = "test" ]]; then
    [[ "$_SRC_DIR" ]] && cd "$_SRC_DIR"
    ls -lh
    log_msg "Checking cache dir"
    restore_dependencies_cache
    restore_build_cache
    unset GOOS GOARCH # Avoids errors on arm64 builds
    log_msg "Testing..."
    go test -v
    cache_build
    log_msg "Finished testing"
elif [[ $ACTION = "dependencies" ]]; then
    log_msg "Getting dependencies ..."
    ls -lh
    [[ "$_SRC_DIR" ]] && cd "$_SRC_DIR"
    ls -lh
    go mod download # -json
    log_msg "Finished downloading dependencies"
    cache_dependencies
elif [[ $ACTION = "release" ]]; then
    log_msg "Publishing release assets ..."
    [[ "$_SRC_DIR" ]] && cd "$_SRC_DIR"
    if [[ -z "$_GH_TOKEN" || "$_GH_TOKEN" = "false" ]]; then
        error_msg "Must provide GH_TOKEN (gh-token) to publish release assets"
    fi
    gh_release
else
    error_msg "Unknown action"
fi

log_msg "Successfully completed $ACTION step"