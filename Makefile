# Thin wrapper around src/bin/nns; all logic lives there.
NNS     := src/bin/nns
TARGETS := pdf new list clean doctor install book help all

.DEFAULT_GOAL := help
.PHONY: $(TARGETS)

# Positional-argument trick: in `make pdf name-of-song` (or `make new ...`),
# every goal after the command is a song name. Those goals are swallowed by a
# no-op catch-all rule at the bottom of this file.
CMD := $(firstword $(MAKECMDGOALS))
ifneq ($(filter $(CMD),pdf new),)
  ARGS  := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  CLASH := $(filter $(TARGETS),$(ARGS))
  ifneq ($(CLASH),)
    $(error song name '$(firstword $(CLASH))' collides with a make target; choose another name)
  endif
endif
SONGS := $(strip $(ARGS) $(SONG))
FLAGS := $(if $(LETTERS),--letters)

help:
	@$(NNS) help

all: pdf

pdf:
	@$(NNS) build $(FLAGS) $(if $(SONGS),$(SONGS),--all)

new:
	@$(if $(SONGS),$(NNS) new $(SONGS),echo "usage: make new <song>" >&2; exit 2)

list:
	@$(NNS) list

book:
	@$(NNS) book

clean:
	@$(NNS) clean

doctor:
	@$(NNS) doctor

install:
	@$(NNS) install

build/%.pdf: songs/%.tex src/tex/nnschart.cls src/lua/nns.lua
	@$(NNS) build $*

ifneq ($(ARGS),)
%:
	@:
endif
