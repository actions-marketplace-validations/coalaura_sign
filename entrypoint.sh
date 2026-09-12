#!/usr/bin/env bash

set -euo pipefail

error() {
    echo "::error::$1"
    exit 1
}

resolve_file() {
    local path="$1"

    if [[ "$path" != /* ]]; then
        path="$GITHUB_WORKSPACE/$path"
    fi

    if [[ ! -f "$path" ]]; then
        return 1
    fi

    realpath "$path"
}

if [[ ! "$INPUT_BUILDER_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    error "invalid builder version: $INPUT_BUILDER_VERSION"
fi

if [[ -n "$INPUT_KEY" && -n "$INPUT_KEY_FILE" ]]; then
    error "key and key-file cannot be used together"
fi

if [[ -z "$INPUT_KEY" && -z "$INPUT_KEY_FILE" ]]; then
    error "either key or key-file is required"
fi

binary_path="$(resolve_file "$INPUT_PATH")" || error "binary not found: $INPUT_PATH"
workspace_path="$(realpath "$GITHUB_WORKSPACE")"

case "$binary_path" in
    "$workspace_path"/*)
        ;;
    *)
        error "binary must be inside GITHUB_WORKSPACE"
        ;;
esac

temporary_directory="$(mktemp -d "$RUNNER_TEMP/coalaura-sign.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

key_path="$temporary_directory/key"

if [[ -n "$INPUT_KEY" ]]; then
    if ! printf '%s' "$INPUT_KEY" | base64 --decode > "$key_path"; then
        error "key is not valid base64"
    fi
else
    source_key="$(resolve_file "$INPUT_KEY_FILE")" || error "key file not found: $INPUT_KEY_FILE"
    cp "$source_key" "$key_path"
fi

chmod 600 "$key_path"

image="coalaura/builder:$INPUT_BUILDER_VERSION"

arguments=(
    sign
    "$binary_path"
    --sign
    /tmp/coalaura-sign/key
)

chain_index=0

while IFS= read -r chain; do
    chain="${chain%$'\r'}"

    if [[ -z "$chain" ]]; then
        continue
    fi

    if [[ "$chain" == https://* ]]; then
        arguments+=(--sign-chain "$chain")

        continue
    fi

    if [[ "$chain" == http://* ]]; then
        error "certificate chain URLs must use HTTPS: $chain"
    fi

    chain_path="$(resolve_file "$chain")" || error "certificate chain file not found: $chain"
    chain_name="chain-$chain_index"

    cp "$chain_path" "$temporary_directory/$chain_name"

    arguments+=(--sign-chain "/tmp/coalaura-sign/$chain_name")

    chain_index=$((chain_index + 1))
done <<< "$INPUT_CHAIN"

if [[ -n "$INPUT_PASSPHRASE" ]]; then
    arguments+=(--passphrase "$INPUT_PASSPHRASE")
fi

docker run \
    --rm \
    --user "$(id -u):$(id -g)" \
    --volume "$GITHUB_WORKSPACE:$GITHUB_WORKSPACE" \
    --volume "$temporary_directory:/tmp/coalaura-sign:ro" \
    --workdir "$GITHUB_WORKSPACE" \
    "$image" \
    "${arguments[@]}"

{
    echo "path=$binary_path"
    echo "filename=$(basename "$binary_path")"
    echo "image=$image"
} >> "$GITHUB_OUTPUT"
