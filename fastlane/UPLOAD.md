# Uploading Builds

Fastlane uploads use an App Store Connect API key. Keep the `.p8` file outside
the repository, for example in `~/.private_keys`.

Upload the current exported IPA:

```sh
APP_STORE_CONNECT_API_KEY_ID="..." \
APP_STORE_CONNECT_API_ISSUER_ID="..." \
APP_STORE_CONNECT_API_KEY_PATH="$HOME/.private_keys/AuthKey_....p8" \
fastlane ios upload_build
```

Build and upload:

```sh
APP_STORE_CONNECT_API_KEY_ID="..." \
APP_STORE_CONNECT_API_ISSUER_ID="..." \
APP_STORE_CONNECT_API_KEY_PATH="$HOME/.private_keys/AuthKey_....p8" \
fastlane ios release_upload
```

Use `VELO_IPA_PATH=/path/to/Velo.ipa` to upload a specific IPA.
