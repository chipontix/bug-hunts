# Every reproduction runs in Docker; the host needs Docker, bash and python3.
SHELL := bash
BUGS := $(notdir $(wildcard bugs/*))

.PHONY: verify test repeat list build clean $(BUGS)

verify:               ## build all images, run each test before and after the fix, print the table
	scripts/verify.sh

test: verify          ## alias for verify

$(BUGS):              ## one bug only, e.g. `make go-flate-preset-dict`
	scripts/verify.sh $@

repeat:               ## stability check: make repeat BUG=go-http-body-close-deadlock N=20
	scripts/repeat.sh $(BUG) $(or $(N),20)

list:                 ## list the bugs
	@printf '%s\n' $(BUGS)

build:                ## build the images without running anything
	@for b in $(BUGS); do docker build -q -t bughunts-$$b -f bugs/$$b/Dockerfile . || exit 1; done

clean:                ## remove this repo's images (bughunts-*) and nothing else
	-docker rmi $$(docker images -q 'bughunts-*' | sort -u) 2>/dev/null
