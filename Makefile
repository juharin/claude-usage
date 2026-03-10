APP_NAME = ClaudeUsage
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
SOURCES = $(wildcard Sources/*.swift)

.PHONY: build clean run install

build: $(APP_BUNDLE)

$(APP_BUNDLE): $(SOURCES) Info.plist
	@mkdir -p $(BUILD_DIR)
	xcrun swiftc \
		-O \
		-framework SwiftUI \
		-framework AppKit \
		-framework Security \
		-target arm64-apple-macos14.0 \
		-o $(BUILD_DIR)/$(APP_NAME) \
		$(SOURCES)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: build
	@open $(APP_BUNDLE)

install: build
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR)
