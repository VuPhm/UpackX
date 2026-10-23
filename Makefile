.PHONY: all build package release-check test install uninstall reinstall clean

all: build

build:
	@./Scripts/build.sh

package:
	@./Packaging/package.sh

release-check:
	@./Packaging/release_check.sh

test: build
	@./Scripts/run_tests.sh

install: build
	@./Scripts/install.sh

uninstall:
	@./Scripts/uninstall.sh

reinstall:
	@./Scripts/reinstall.sh

clean:
	rm -rf build dist
	rm -rf /tmp/upackx_test*
