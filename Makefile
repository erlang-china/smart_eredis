REBAR    = ./rebar
APPS     = kernel stdlib sasl erts ssl tools os_mon runtime_tools crypto inets public_key mnesia syntax_tools compiler
CODE_PLT = ./eredis_dialyzer_plt

.PHONY: rel deps

all:deps compile

deps:
	@$(REBAR) get-deps

compile:
	@$(REBAR) compile

edoc:
	@$(REBAR) doc

test:
	@rm -rf .eunit
	@mkdir -p .eunit
	@$(REBAR) skip_deps=true eunit

clean:
	@$(REBAR) clean


console:
	exec erl \
	+P 100000 \
 	-pa ebin deps/*/ebin \
 	-sname smart_eredis \
    -boot start_sasl \
    -s smart_eredis

win_console:
	exec werl \
	+P 100000 \
 	-pa ebin deps/*/ebin \
 	-sname smart_eredis \
    -boot start_sasl \
    -s smart_eredis

build_plt: compile
	dialyzer --build_plt --output_plt $(CODE_PLT) --apps $(APPS) \
		ebin deps/*/ebin

check_plt: compile
	dialyzer --check_plt --plt $(CODE_PLT) --apps $(APPS) \
		ebin deps/*/ebin

dialyzer: compile
	@echo
	@echo Use "'make check_plt'" to check PLT prior to using this target.
	@echo Use "'make build_plt'" to build PLT prior to using this target.
	@echo
	@sleep 1
	dialyzer --plt $(CODE_PLT) ebin deps/*/ebin