--------------------------------------------------------------------------------
-- luatexts/lua.lua: plain Lua implementation of luatexts
--------------------------------------------------------------------------------
-- Copyright (c) 2011-2013, luatexts authors
-- See license in the file named COPYRIGHT
--------------------------------------------------------------------------------

local assert, error, pairs, select, type
    = assert, error, pairs, select, type

local table_concat
    = table.concat

--------------------------------------------------------------------------------

local bit = require 'bit'

local bit_band, bit_bor, bit_lshift, bit_rshift
    = bit.band, bit.bor, bit.lshift, bit.rshift

--------------------------------------------------------------------------------

local save, save_cat
do
  local handlers = { }

  local handle_value = function(cat, v, visited, buf)
    local handler = handlers[type(v)]
    if handler == nil then
      return nil, "can't save `" .. type(v) .. "'"
    end
    return handler(cat, v, { }, buf)
  end

  handlers["nil"] = function(cat, v, visited, buf)
    return cat "-" "\n"
  end

  handlers["boolean"] = function(cat, v, visited, buf)
    return cat (v and "1" or "0") "\n"
  end

  handlers["number"] = function(cat, v, visited, buf)
    return cat "N" "\n" (("%.54g"):format(v)) "\n"
  end

  handlers["string"] = function(cat, v, visited, buf)
    return cat "S" "\n" (#v) "\n" (v) "\n"
  end

  handlers["table"] = function(cat, t, visited, buf)
    if visited[t] then
      -- TODO: This should be `return nil, err`, not `error()`!
      error("circular table reference detected")
    end
    visited[t] = true

    if buf then
      cat "T" "\n"

      local array_size = #t
      cat (array_size) "\n"

      local hash_size_pos = #buf + 1
      cat ("?") "\n"

      for i = 1, array_size do
        handle_value(cat, t[i], visited, buf)
      end

      local hash_size = 0
      for k, v in pairs(t) do
        if
          type(k) ~= "number" or
          k > array_size or k < 1 or -- integer key in hash part of the table
          k % 1 ~= 0 -- non-integer key
        then
          hash_size = hash_size + 1
          -- TODO: return nil, err on failure instead of asserting
          assert(handle_value(cat, k, visited, buf))
          assert(handle_value(cat, v, visited, buf))
        end
      end

      buf[hash_size_pos] = hash_size
    else -- Streaming mode
      cat "t" "\n"

      for k, v in pairs(t) do
        assert(handle_value(cat, k, visited, buf))
        assert(handle_value(cat, v, visited, buf))
      end

      handle_value(cat, nil, visited, buf)
    end

    visited[t] = nil

    return cat
  end

  local impl = function(buf, cat, ...)
    local nargs = select("#", ...)

    cat (nargs) "\n"

    for i = 1, nargs do
      handle_value(cat, select(i, ...), { }, buf)
    end

    return cat
  end

  save_cat = function(cat, ...)
    return impl(nil, cat, ...)
  end

  save = function(...)
    local buf = { }
    local function cat(s) buf[#buf + 1] = s; return cat end

    impl(buf, cat, ...)

    return table_concat(buf)
  end
end

--------------------------------------------------------------------------------

local load, load_from_buffer
do
  local make_read_buf
  do
    local read = function(self, bytes)
      local off = self.next_ + bytes - 1

      if off > #self.str_ then
        self:fail("load failed: read: not enough data in buffer")
        return nil
      end

      local result = self.str_:sub(self.next_, off)

      self.next_ = off + 1

      return result
    end

    local readpattern = function(self, pattern)
      if self.next_ > #self.str_ then
        self:fail("load failed: readpattern: not enough data in buffer")
        return nil
      end

      local start, off, result = self.str_:find(pattern, self.next_)
      if not result then
        self:fail("load failed: readpattern: not found")
        return nil
      end

      if start ~= self.next_ then
        self:fail("load failed: readpattern: garbage before pattern")
        return nil
      end

      self.next_ = off + 1

      return result
    end

    local good = function(self)
      return not self.failed_
    end

    local fail = function(self, msg)
      self.failed_ = msg -- overriding old error
    end

    local result = function(self)
      if self:good() then
        return true
      end

      return nil, self.failed_
    end

    make_read_buf = function(str)

      return
      {
        read = read;
        readpattern = readpattern;
        --
        good = good;
        fail = fail;
        result = result;
        --
        str_ = str;
        next_ = 1;
        failed_ = false;
      }
    end

  end

  local invariant = function(v)
    return function()
      return v
    end
  end

  local number = function(base)
    return function(buf)
      local v = buf:readpattern("(.-)\r?\n")
      if not buf:good() then
        return nil
      end
      v = tonumber(v, base)
      if not v then
        buf:fail("load failed: not a number")
      end
      return v
    end
  end

  local uint_patterns =
  {
    [10] = "([0-9]-)\r?\n";
    [16] = "([0-9a-fA-F]-)\r?\n";
    [36] = "([0-9a-zA-Z]-)\r?\n";
  }

  local uint = function(base)
    local pattern = assert(uint_patterns[base])

    return function(buf)
      local v = buf:readpattern(pattern)
      if not buf:good() then
        return nil
      end
      v = tonumber(v, base)
      if not v then -- Should not happen
        buf:fail("load failed: not a number")
        return nil
      end
      if v ~= v then
        buf:fail("load failed: uint is nan")
        return nil
      end
      if v < 0 then
        buf:fail("load failed: negative uint")
        return nil
      end
      if v > 4294967295 then
        buf:fail("load failed: uint is too huge")
        return nil
      end
      if v % 1 ~= 0 then
        buf:fail("load failed: fractional uint")
        return nil
      end

      return v
    end
  end

  local read_uint10 = uint(10)

  local read_utf8
  do
    -- Based on MIT-licensed Flexible and Economical UTF-8 Decoder
    -- by Bjoern Hoehrmann <bjoern@hoehrmann.de>
    -- http://bjoern.hoehrmann.de/utf-8/decoder/dfa/

    local UTF8_ACCEPT = 0
    local UTF8_REJECT = 1

    local utf8d =
    {
      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, -- 00..1f
      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, -- 20..3f
      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, -- 40..5f
      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, -- 60..7f
      1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, -- 80..9f
      7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, -- a0..bf
      8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, -- c0..df
      0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, -- e0..ef
      0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, -- f0..ff
      0x0,0x1,0x2,0x3,0x5,0x8,0x7,0x1,0x1,0x1,0x4,0x6,0x1,0x1,0x1,0x1, -- s0..s0
      1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,0,1,1,1,1,1,1, -- s1..s2
      1,2,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1, -- s3..s4
      1,2,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,3,1,1,1,1,1,1, -- s5..s6
      1,3,1,1,1,1,1,3,1,3,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1, -- s7..s8
    }

    -- Note: Keeping code as close to the C original as possible.
    --       Thus the magic numbers without constants.
    local decode = function(state, codep, byte)
      local byte_type = utf8d[byte + 1]

      codep = (state ~= UTF8_ACCEPT)
        and
        (
          bit_bor(
              bit_band(byte, 0x3f),
              bit_lshift(codep, 6)
            )
        )
        or
        (
          bit_band(
              bit_rshift(0xff, byte_type),
              byte
            )
        )

      return utf8d[256 + state * 16 + byte_type + 1], codep
    end

    read_utf8 = function(buf)
      local length = read_uint10(buf)
      if not buf:good() then
        return nil
      end

      local result
      if length == 0 then
        result = ""
      else
        result = { }

        local codepoint = 0
        local state = UTF8_ACCEPT
        while length > 0 do
          local char = buf:read(1)
          if not buf:good() then
            return nil
          end

          result[#result + 1] = char

          state, codepoint = decode(state, codepoint, char:byte())
          if state == UTF8_ACCEPT then
            length = length - 1
          elseif state == UTF8_REJECT then
            buf:fail("load failed: invalid utf-8 data")
            return nil
          end
        end

        result = table_concat(result)
      end

      -- Eat EOL after data
      buf:readpattern("()\r?\n")
      if not buf:good() then
        return nil
      end

      return result
    end
  end

  local unsupported = function(buf)
    buf:fail("load failed: unsupported value type")
  end

  local read_value

  local value_readers =
  {
    ['-'] = invariant(nil);
    ['0'] = invariant(false);
    ['1'] = invariant(true);
    ['N'] = number(10);
    ['U'] = read_uint10;
    ['H'] = uint(16);
    ['Z'] = uint(36);

    ['S'] = function(buf)
      local length = read_uint10(buf)
      if not buf:good() then
        return nil
      end

      local v = buf:read(length)
      if not buf:good() then
        return nil
      end

      -- Eat EOL after data
      local empty = buf:readpattern("()\r?\n")
      if not buf:good() then
        return nil
      end

      return v
    end;

    ['8'] = read_utf8;

    ['T'] = function(buf)
      local array_size = read_uint10(buf)
      if not buf:good() then
        return
      end

      local hash_size = read_uint10(buf)
      if not buf:good() then
        return
      end

      local r = { }

      for i = 1, array_size do
        if not buf:good() then
          return
        end

        r[i] = read_value(buf)
      end

      for i = 1, hash_size do
        if not buf:good() then
          return
        end

        local k = read_value(buf)
        if buf:good() then
          if k == nil then
            buf:fail("load failed: table key is nil")
          else
            r[k] = read_value(buf)
          end
        end
      end

      return r
    end;

    ['t'] = function(buf)
      local r = { }

      while buf:good() do
        local k = read_value(buf)
        if buf:good() then
          if k == nil then
            break -- end of table
          else
            r[k] = read_value(buf)
          end
        end
      end

      return r
    end;
  }

  read_value = function(buf)
    local value_type = buf:readpattern("(.)\r?\n")
    if not buf:good() then
      return
    end

    local reader = value_readers[value_type]
    if not reader then
      buf:fail("load failed: unknown value type")
      return
    end

    return reader(buf)
  end

  -- TODO: Cover this with separate tests.
  --       Most importantly, test that readpattern's pattern
  --       always ends with '\n'
  load_from_buffer = function(buf)
    local n = read_uint10(buf)
    if not buf:good() then
      return buf:result()
    end

    -- TODO: Use recursion instead?
    local r = { }
    for i = 1, n do
      r[i] = read_value(buf)

      if not buf:good() then
        return buf:result()
      end
    end

    return true, unpack(r, 1, n)
  end

  load = function(str)
    if type(str) ~= "string" then -- TODO: Support io.file?
      -- Imitating C API to simplify tests
      error(
          "bad argument #1 to 'load' (string expected)"
        )
    end

    return load_from_buffer(
        make_read_buf(str)
      )
  end
end

--------------------------------------------------------------------------------

return
{
  _VERSION = "luatexts-lua 0.1.5";
  _COPYRIGHT = "Copyright (C) 2011-2013, luatexts authors";
  _DESCRIPTION = "Trivial Lua human-readable binary-safe serialization library";
  --
  save = save;
  save_cat = save_cat;
  load = load;
  load_from_buffer = load_from_buffer;
}
