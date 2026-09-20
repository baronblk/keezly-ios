fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios tests

```sh
[bundle exec] fastlane ios tests
```

Full unit and integration tests: rules engine plus app-level tests on a simulator

### ios ui_tests

```sh
[bundle exec] fastlane ios ui_tests
```

XCUITests on an iPhone and an iPad simulator

### ios asc_check

```sh
[bundle exec] fastlane ios asc_check
```

Verify App Store Connect credentials and whether the app record exists

### ios device_smoke

```sh
[bundle exec] fastlane ios device_smoke
```

Build, install and launch on whichever physical device is available

### ios device_iphone

```sh
[bundle exec] fastlane ios device_iphone
```

The physical iPhone gate

### ios device_ipad

```sh
[bundle exec] fastlane ios device_ipad
```

The physical iPad gate

### ios device_gate

```sh
[bundle exec] fastlane ios device_gate
```

Both physical device gates

### ios lint

```sh
[bundle exec] fastlane ios lint
```

Static checks: SwiftLint and SwiftFormat

### ios qa

```sh
[bundle exec] fastlane ios qa
```

The whole local quality gate

### ios release_check

```sh
[bundle exec] fastlane ios release_check
```

Release-candidate gate — reports every sub-gate separately, never merged

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
