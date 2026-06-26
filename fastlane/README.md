fastlane documentation
----

# Installation

This project currently uses the Homebrew Fastlane install because Apple's bundled
Ruby is too old for current Fastlane dependencies:

```sh
brew install fastlane
```

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build_app_store

```sh
fastlane ios build_app_store
```

Build a signed App Store Connect IPA for Velo TV

### ios upload_build

```sh
fastlane ios upload_build
```

Upload the latest exported IPA to App Store Connect

### ios release_upload

```sh
fastlane ios release_upload
```

Build and upload Velo TV to App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
