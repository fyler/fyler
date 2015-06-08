include version.mk
ERLANG_ROOT := $(shell erl -eval 'io:format("~s", [code:root_dir()])' -s init stop -noshell)
APPNAME = fyler
APPDIR=$(ERLANG_ROOT)/lib/$(APPNAME)-$(VERSION)
ERL_LIBS:=apps:deps


ERL=erl +A 4 +K true
ifeq (,$(wildcard ./rebar))
	REBAR := $(shell which rebar)
else
	REBAR := ./rebar
endif

ifndef PKG_CONFIG_PATH
	export PKG_CONFIG_PATH = /usr/local/ffmpeg_build/lib/pkgconfig/
endif

all: deps update_deps compile

update:
	git pull

deps:
	@$(REBAR) get-deps

update_deps:
	@$(REBAR) update-deps

compile:
	@$(REBAR) compile

release: clean compile
	@$(REBAR) generate force=1

soft-release:
	@$(REBAR) generate force=1

test-core:
	@$(REBAR) skip_deps=true eunit apps=fyler suites=fyler_server,fyler_uploader,aws_cli,fyler_utils,fyler_queue

test-docs:
	@$(REBAR) skip_deps=true eunit suites=docs_conversions_tests

test-video:
	@$(REBAR) skip_deps=true eunit suites=video_conversions_tests

clean:
	@$(REBAR) clean

clean-hard:
	rm -rf deps/
	@$(REBAR) clean
	
db_setup:
	scripts/setup_db.erl

handlers:
	scripts/gen_handlers_list.erl

run-server:
	ERL_LIBS=apps:deps erl -args_file files/vm.args.sample -sasl errlog_type error -boot  start_sasl -s $(APPNAME) -embedded -config files/app.config  -fyler role server

run-pool:
	ERL_LIBS=apps:deps erl -args_file files/vm.args.pool.sample -sasl errlog_type error -boot start_sasl -s $(APPNAME) -embedded -config files/app.pool.config  -fyler role pool

run-pool-video:
	ERL_LIBS=apps:deps erl -args_file files/vm.args.video.sample -sasl errlog_type error -boot start_sasl -s $(APPNAME) -embedded -config files/app.video.config  -fyler role pool

clean-tmp:
	cd tmp && ls | xargs rm && cd ..

version:
	echo "VERSION=$(VER)" > version.mk
	git add version.mk
	git commit -m "Version $(VER)"
	git tag -a v$(VER) -m "version $(VER)"
