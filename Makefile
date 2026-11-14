# Override DEVELOPER_DIR if Xcode is installed elsewhere.
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
DERIVED_DATA ?= /tmp/indoorbility-derived

.PHONY: project test build uitest
project:
	python3 scripts/generate_project.py

test:
	CLANG_MODULE_CACHE_PATH=/tmp/indoorbility-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/indoorbility-module-cache xcrun swift test --scratch-path /tmp/indoorbility-swift-build --cache-path /tmp/indoorbility-package-cache --disable-sandbox

build:
	xcodebuild -project Indoorbility.xcodeproj -scheme Indoorbility -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build

# Pass a device identifier from `xcrun simctl list devices available`.
uitest:
	@test -n "$(SIMULATOR_ID)" || (echo 'Set SIMULATOR_ID to an installed iOS Simulator UUID'; exit 1)
	xcodebuild -project Indoorbility.xcodeproj -scheme Indoorbility -destination 'platform=iOS Simulator,id=$(SIMULATOR_ID)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test
