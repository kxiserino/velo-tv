# Uploading Builds

Fastlane uploads use an App Store Connect API key. Keep the `.p8` file outside
the repository, for example in `~/.private_keys`.

Create your local env file:

```sh
cp .env.example .env
```

Then fill in `.env` and load it before running Fastlane:

```sh
set -a
source .env
set +a
```

Upload the current exported IPA:

```sh
fastlane ios upload_build
```

Build and upload:

```sh
fastlane ios release_upload
```

Use `VELO_IPA_PATH=/path/to/Velo.ipa` to upload a specific IPA.
