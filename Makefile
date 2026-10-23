.PHONY: all build install uninstall test clean

all: build

build:
	@./Scripts/build.sh

install: build
	@./Scripts/install.sh

uninstall:
	@./Scripts/uninstall.sh

reinstall:
	@./Scripts/reinstall.sh

test: build
	@./Scripts/run_tests.sh

clean:
	rm -rf build
	rm -rf /tmp/upackx_test*

