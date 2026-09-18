# Flying Toasters — After Dark tribute (Free Pascal)
#
# macOS:   make
# Linux:   sudo apt install fpc libgtk2.0-dev   &&  make linux
# Windows: from a native FPC install:            make windows

FPC      ?= fpc
SRC      := src
BUILD    := build
APP      := $(BUILD)/FlyingToasters.app
UNITS    := -Fu$(SRC) -FU$(BUILD) -FE$(BUILD)
FLAGS    := -Mobjfpc -Scgi -O2 -Xs

.PHONY: all app run linux windows test snap clean

all: app

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/FlyingToasters: $(BUILD) $(SRC)/*.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/FlyingToasters $(SRC)/toasters.pas

$(BUILD)/toastertest: $(BUILD) $(SRC)/utoasterconfig.pas $(SRC)/utoastermodel.pas $(SRC)/utoasteraudio.pas $(SRC)/utoasterrender.pas $(SRC)/ubitmapfont.pas $(SRC)/utoasterapp.pas $(SRC)/toastertest.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/toastertest $(SRC)/toastertest.pas

$(BUILD)/toastersnap: $(BUILD) $(SRC)/utoasterconfig.pas $(SRC)/utoastermodel.pas $(SRC)/utoasterrender.pas $(SRC)/ubitmapfont.pas $(SRC)/utoasterapp.pas $(SRC)/toastersnap.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/toastersnap $(SRC)/toastersnap.pas

app: $(BUILD)/FlyingToasters
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BUILD)/FlyingToasters $(APP)/Contents/MacOS/FlyingToasters
	cp bundle/Info.plist $(APP)/Contents/Info.plist

run: app
	open $(APP)

linux: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/flyingtoasters $(SRC)/toasters.pas

windows: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/FlyingToasters.exe $(SRC)/toasters.pas

test: $(BUILD)/toastertest
	$(BUILD)/toastertest

snap: $(BUILD)/toastersnap
	$(BUILD)/toastersnap $(BUILD)

clean:
	rm -rf $(BUILD)
