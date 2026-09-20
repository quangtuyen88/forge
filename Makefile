.PHONY: build-ios test test-ios-unit test-onboarding-e2e test-app-e2e test-journey-e2e record-app-tour

# Override with `make test-ios-unit SIMULATOR="iPhone 17 Pro"` when that device exists.
SIMULATOR ?= iPhone 17e

build-ios:
	xcodebuild -project App/Forge.xcodeproj -scheme Forge -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/forge-build-ios CODE_SIGNING_ALLOWED=NO -quiet build

test:
	swift test --package-path ForgeCore
	# `pnpm test` compiles current TypeScript itself (never stale dist).
	pnpm --dir server test
	$(MAKE) test-ios-unit

# The app-target unit suite: SwiftData, the decision trace and the coach read contracts.
# Needs a simulator, so it is its own target as well as part of `test`.
test-ios-unit:
	xcodebuild test -project App/Forge.xcodeproj -scheme Forge -destination 'platform=iOS Simulator,name=$(SIMULATOR)' -derivedDataPath /tmp/forge-build-ios CODE_SIGNING_ALLOWED=NO -quiet -only-testing:ForgeTests

test-onboarding-e2e:
	./scripts/test-onboarding-e2e.sh

test-app-e2e:
	./scripts/test-app-e2e.sh

test-journey-e2e:
	./scripts/test-journey-e2e.sh

record-app-tour:
	./scripts/record-full-app-tour.sh
