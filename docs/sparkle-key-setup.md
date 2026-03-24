# Sparkle Key Setup

This document explains how to generate, store, and configure the Sparkle EdDSA keys used by NotesBridge for direct-download updates.

## Current State

NotesBridge currently embeds this Sparkle public key in the app bundle:

`bN0AdWyNntmdvuNQNXa2pDP8peMGNfsbBcrXIBf60ys=`

That value is currently sourced by the bundle build path, exposed through:

- [/Users/petepei/Projects/Notes/scripts/notesbridge.sh](/Users/petepei/Projects/Notes/scripts/notesbridge.sh)

The GitHub Actions release workflow expects the matching private key in this repository secret:

- `SPARKLE_PRIVATE_ED_KEY`

Without that secret, the workflow cannot generate `appcast.xml`, GitHub Pages never publishes the Sparkle feed, and in-app update checks fail.

## What Was Checked

The following were checked and **no matching existing Sparkle private key was found**:

- repository files
- shell history / local config files
- current environment variables
- default Sparkle keychain entry
- Keychain item named `Private key for signing Sparkle updates`

Relevant checks:

- `./.build/artifacts/sparkle/Sparkle/bin/generate_keys -p`
  - result: `ERROR: No existing signing key found!`
- `security find-generic-password -g -s "Private key for signing Sparkle updates"`
  - result: keychain item not found

Treat the previous private key as **lost** unless it exists in an external password manager, a CI secret backup, or another developer machine.

The earlier embedded public key was:

`0Gcbr/JsQLrUXt36na4JMUNt7S9/+GIVr3fNSE8q1F4=`

## Important Consequence Of A Lost Sparkle Key

If the private key is lost, you can generate a new key pair, but **existing released builds cannot trust updates signed by the new key**.

That means:

- NotesBridge `0.2.2` to `0.2.4` cannot be repaired in-place for automatic updates
- users on those builds will need **one manual upgrade**
- once they install a build containing the new public key, future Sparkle updates can work again

## Generate A New Sparkle Key Pair

Use Sparkle's bundled tool from this repository:

```bash
./.build/artifacts/sparkle/Sparkle/bin/generate_keys --account NoteBridge
```

Recommended:

- run this on a trusted Mac
- use a stable account name such as `NoteBridge`
- allow Keychain access when prompted

The tool prints the **public key** that must be embedded into the app.

## Export The Private Key For CI

Export the matching private key from Keychain into a file:

```bash
./.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account NoteBridge \
  -x /tmp/NotesBridge.sparkle.key
```

The exported file contents are the value that should be stored in GitHub as `SPARKLE_PRIVATE_ED_KEY`.

Do not commit this file.

Recommended immediate handling:

```bash
mkdir -p ~/Secrets/NotesBridge
mv /tmp/NotesBridge.sparkle.key ~/Secrets/NotesBridge/
chmod 600 ~/Secrets/NotesBridge/NotesBridge.sparkle.key
```

Then also store it in a password manager or other secure backup.

## Update NotesBridge To Use The New Public Key

Replace the default public key in the bundle build path:

- [/Users/petepei/Projects/Notes/scripts/notesbridge.sh](/Users/petepei/Projects/Notes/scripts/notesbridge.sh)

Update this line:

```bash
SPARKLE_PUBLIC_ED_KEY="${NOTESBRIDGE_SPARKLE_PUBLIC_ED_KEY:-...}"
```

with the new public key printed by `generate_keys`.

## Configure GitHub Secret

Set the repository secret from the exported private key file:

```bash
gh secret set SPARKLE_PRIVATE_ED_KEY < ~/Secrets/NotesBridge/NotesBridge.sparkle.key
```

Confirm secrets if needed:

```bash
gh secret list
```

## Publish The First Release With The New Key

After updating the embedded public key and setting the private-key secret:

1. build and release a new NotesBridge version, for example `0.2.5`
2. run the `Release` workflow, or the local unified command:

```bash
./scripts/notesbridge.sh release --version 0.2.5
```
3. confirm the workflow completes these steps:
   - `Generate Sparkle appcast`
   - `Publish GitHub Pages content`
4. verify the feed URL returns `200`:

```bash
curl -I -L https://peizh.github.io/NoteBridge/updates/appcast.xml
```

5. verify `gh-pages` exists:

```bash
git ls-remote --heads origin gh-pages
```

## Local Smoke Test

After the first release with the new key:

1. install the new build manually
2. open NotesBridge Settings
3. use `Check for Updates`
4. confirm Sparkle can retrieve update metadata without the old error dialog

## Recommended Operational Practice

After generating the new Sparkle key:

- keep the public key in the repo
- keep the private key only in:
  - GitHub secret `SPARKLE_PRIVATE_ED_KEY`
  - a password manager / secure backup
- do not rely on Keychain-only storage as the sole copy
- document the rotation date and affected minimum manual-upgrade version in release notes
