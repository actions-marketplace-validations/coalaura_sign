# sign

Sign Windows, macOS and Linux binaries in GitHub Actions with [coalaura/builder](https://github.com/coalaura/builder).

The action runs the published `coalaura/builder` image directly. It does not build a separate container image.

## Usage

```yaml
- name: Build
  id: build
  uses: coalaura/build@v1
  with:
    os: windows
    arch: amd64
    output: build/example.exe

- name: Sign
  id: sign
  uses: coalaura/sign@v1
  with:
    path: ${{ steps.build.outputs.path }}
    key: ${{ secrets.SIGNING_KEY }}
    passphrase: ${{ secrets.SIGNING_KEY_PASSPHRASE }}
    chain: |
      certs/issuing.pem
      https://example.com/root.pem

- name: Upload
  uses: actions/upload-artifact@v4
  with:
    name: example
    path: ${{ steps.sign.outputs.path }}
```

`builder` detects the binary format automatically. It supports Authenticode signatures for Windows PE binaries, thin Mach-O signatures for macOS and appended CMS/PKCS#7 signatures for Linux binaries.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `builder-version` | `v0.4.3` | Version of `coalaura/builder` to run |
| `path` | required | Binary to sign |
| `key` | | Base64-encoded PEM, PFX or P12 signing key |
| `key-file` | | Path to a PEM, PFX or P12 signing key |
| `chain` | | Certificate chain files or HTTPS URLs, one per line |
| `passphrase` | | Signing-key passphrase |

Exactly one of `key` or `key-file` must be provided.

Local key and certificate files are copied into an isolated temporary directory and mounted read-only into the Builder container. The temporary files are removed when the action finishes.

The binary itself must be inside `GITHUB_WORKSPACE`.

## Outputs

| Output | Description |
| --- | --- |
| `path` | Absolute path to the signed binary |
| `filename` | Filename of the signed binary |
| `image` | Builder Docker image used |

Signing happens in place, so `path` refers to the same file supplied to the action.

## Signing key

For CI, storing the key as a base64-encoded GitHub Actions secret is usually the most convenient option.

Linux:

```sh
base64 -w 0 certificate.pfx
```

PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.pfx"))
```

Store the result in a secret such as `SIGNING_KEY`:

```yaml
- uses: coalaura/sign@v1
  with:
    path: build/example.exe
    key: ${{ secrets.SIGNING_KEY }}
    passphrase: ${{ secrets.SIGNING_KEY_PASSPHRASE }}
```

A file already present on the runner can be used instead:

```yaml
- uses: coalaura/sign@v1
  with:
    path: build/example.exe
    key-file: certs/signing.pfx
```

## Certificate chains

`chain` accepts one local file or HTTPS URL per line:

```yaml
with:
  chain: |
    certs/issuing.pem
    https://example.com/root.pem
```

Each value is forwarded as a separate `--sign-chain` option.

## Matrix builds

`coalaura/sign` works naturally after `coalaura/build` in a matrix. Each matrix job signs its own build output:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest

    strategy:
      fail-fast: false
      matrix:
        goos: [windows, linux, darwin]
        goarch: [amd64, arm64]

    steps:
      - uses: actions/checkout@v7

      - name: Build
        id: build
        uses: coalaura/build@v1
        with:
          os: ${{ matrix.goos }}
          arch: ${{ matrix.goarch }}
          output: build/example_${{ matrix.goos }}_${{ matrix.goarch }}${{ matrix.goos == 'windows' && '.exe' || '' }}

      - name: Sign
        id: sign
        uses: coalaura/sign@v1
        with:
          path: ${{ steps.build.outputs.path }}
          key: ${{ secrets.SIGNING_KEY }}
          passphrase: ${{ secrets.SIGNING_KEY_PASSPHRASE }}
          chain: |
            ${{ secrets.SIGNING_ISSUER_URL }}
            ${{ secrets.SIGNING_ROOT_URL }}

      - uses: actions/upload-artifact@v7
        with:
          name: example_${{ matrix.goos }}_${{ matrix.goarch }}
          path: ${{ steps.sign.outputs.path }}
```

## Builder version

The action defaults to Builder `v0.4.3`, but another published version can be selected without changing the action version:

```yaml
- uses: coalaura/sign@v1
  with:
    builder-version: v0.4.4
    path: build/example.exe
    key: ${{ secrets.SIGNING_KEY }}
```

`coalaura/sign@v1` is the version of the GitHub Action interface. `builder-version` selects the version of the underlying Builder image.
