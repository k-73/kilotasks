PLUGIN := org.kilo.plasma.kilotasks
PKG    := package
BUILD  := build

.PHONY: all plugin install-plugin install upgrade uninstall reload test lint clean

all: plugin install-plugin upgrade reload

plugin:
	@mkdir -p $(BUILD)
	@cd $(BUILD) && cmake -DCMAKE_BUILD_TYPE=Release .. >/dev/null && $(MAKE) -j

install-plugin: plugin
	@cd $(BUILD) && sudo $(MAKE) install

install:
	kpackagetool5 --type Plasma/Applet --install $(PKG) || \
	kpackagetool5 --type Plasma/Applet --upgrade $(PKG)

upgrade:
	kpackagetool5 --type Plasma/Applet --upgrade $(PKG)

uninstall:
	kpackagetool5 --type Plasma/Applet --remove $(PLUGIN)

reload:
	kquitapp5 plasmashell || true
	sleep 1
	nohup kstart5 plasmashell >/dev/null 2>&1 & disown

test:
	plasmoidviewer -a $(PKG) -f horizontal

lint:
	@find $(PKG) -name '*.qml' -print0 | xargs -0 -n1 qmllint || true

clean:
	rm -rf $(BUILD)
