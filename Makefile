TEST_DIR=lua/frecency/tests/
MINIMAL_LUA=${TEST_DIR}minimal.lua
NVIM:=nvim

.PHONY: test
test:
	$(NVIM) --headless --clean -u ${MINIMAL_LUA} -c "PlenaryBustedDirectory ${TEST_DIR} {minimal_init = '${MINIMAL_LUA}'}"
