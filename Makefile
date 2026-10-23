.PHONY: all build install test clean

all: build

build:
	@./Scripts/build.sh

install: build
	@./Scripts/install.sh

test: build
	@./Scripts/run_tests.sh

clean:
	rm -rf build
	rm -rf /tmp/upackx_test*
