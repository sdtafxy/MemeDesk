APP_NAME = MemeDesk

# 同 Scripts/build.sh：xcode-select 指向 CommandLineTools 时 SwiftUI 宏插件缺失，
# 装了完整 Xcode 就自动切过去（已显式设置 DEVELOPER_DIR 时不覆盖）。
LOCAL_DEVDIR := $(shell p=$$(xcode-select -p 2>/dev/null); \
  if [ "$$p" = "/Library/Developer/CommandLineTools" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then \
    echo /Applications/Xcode.app/Contents/Developer; fi)
ifeq ($(origin DEVELOPER_DIR),undefined)
export DEVELOPER_DIR := $(LOCAL_DEVDIR)
endif

.PHONY: build app dmg zip release open samples icon install clean

build:
	swift build -c release

app:
	./Scripts/build.sh

dmg: app
	./Scripts/make_dmg.sh

# 更新器用的 zip（+ sha256，配了私钥还会出 .ed25519）
zip: app
	./Scripts/make_zip.sh

release: app
	./Scripts/make_dmg.sh
	./Scripts/make_zip.sh

open: app
	open dist/$(APP_NAME).app

samples:
	python3 Scripts/generate_samples.py

icon:
	python3 Scripts/make_icon.py

install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R dist/$(APP_NAME).app /Applications/

clean:
	rm -rf .build dist
