include version.mk
ERLANG_ROOT := $(shell erl -eval 'io:format("~s", [code:root_dir()])' -s init stop -noshell)
APPNAME = fyler
APPDIR=$(ERLANG_ROOT)/lib/$(APPNAME)-$(VERSION)
ERL_LIBS:=apps:deps


ERL=erl +A 4 +K true
REBAR := which rebar || ./rebar


all: deps compile

update:
	git pull

deps:
	@$(REBAR) get-deps

compile:
	@$(REBAR) compile

release: clean compile
	@$(REBAR) generate force=1
	chmod +x $(APPNAME)/bin/$(APPNAME)

test:
	@$(REBAR) skip_deps=true eunit

clean:
	@$(REBAR) clean

dtl:
	scripts/compile_dtl.erl

run-server:
	ERL_LIBS=apps:..:deps erl -args_file files/vm.args -sasl errlog_type error -sname fyler_server -boot  start_sasl -s $(APPNAME) -embedded -config files/app.config  -fyler role server

run-pool:
	ERL_LIBS=apps:..:deps erl -args_file files/vm.args -sasl errlog_type error -sname fyler_pool_$(id) -boot start_sasl -s $(APPNAME) -embedded -config files/app.config  -fyler role pool

clean-tmp:
	cd tmp && ls | xargs rm && cd ..

version:
	echo "VERSION=$(VER)" > version.mk
	git add version.mk
	git commit -m "Version $(VER)"
	git tag -s v$(VER) -m "version $(VER)"
