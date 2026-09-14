ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VERSION ?=

.PHONY: help package release test clean

help:
	@echo "Arkeys Make targets"
	@echo "  make package VERSION=[x.y.z] archive a Release zip into dist/"
	@echo "  make release                 prepare release notes and create a commit"
	@echo "  make test                    build the app and run Swift package tests"
	@echo "  make clean                   remove local build caches and dist/"
	@echo "  make help                    show this help"

package:
	@"$(ROOT)/Scripts/package.sh" $(VERSION)

release:
	@"$(ROOT)/Scripts/release.sh"

test:
	@"$(ROOT)/Scripts/test.sh"

clean:
	@"$(ROOT)/Scripts/clean.sh" --yes
