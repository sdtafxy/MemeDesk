APP_NAME = MemeDesk

.PHONY: build app dmg open samples icon install clean

build:
	swift build -c release

app:
	./Scripts/build.sh

dmg: app
	./Scripts/make_dmg.sh

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
