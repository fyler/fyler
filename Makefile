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


all: deps compile

update:
	git pull

deps:
	@$(REBAR) get-deps

deps_server:
	@$(REBAR) get-deps -C rebar_server.config

deps_pool_document:
	@$(REBAR) get-deps -C rebar_pool.config

deps_pool_video:
	@$(REBAR) get-deps -C rebar_pool_video.config

update_deps_server:
	@$(REBAR) update-deps -C rebar_server.config

update_deps_pool_document:
	@$(REBAR) update-deps -C rebar_pool.config

update_deps_pool_video:
	@$(REBAR) update-deps -C rebar_pool_video.config

compile:
	@$(REBAR) compile

compile_server:
	@$(REBAR) compile -C rebar_server.config

compile_pool_document:
	@$(REBAR) compile -C rebar_pool.config

compile_pool_video:
	@$(REBAR) compile -C rebar_pool_video.config

release: clean compile
	@$(REBAR) generate force=1

soft-release: clean compile
	@$(REBAR) generate force=1

test-core:
	@$(REBAR) skip_deps=true eunit apps=fyler suites=fyler_server,fyler_uploader,aws_cli,fyler_utils,fyler_queue

test-docs:
	@$(REBAR) skip_deps=true eunit suites=docs_conversions_tests

test-video:
	@$(REBAR) skip_deps=true eunit suites=video_conversions_tests

clean:
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
