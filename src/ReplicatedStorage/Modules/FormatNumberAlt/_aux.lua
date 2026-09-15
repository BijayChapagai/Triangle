--!strict
local config = require(script.Parent.config)
local _aux = { }

local GROUPING_SYMBOL = config.groupingSymbol
local GROUPING_REPL = string.gsub(GROUPING_SYMBOL, "%%", "%%%%") .. "%0"
local DECIMAL_SYMBOL = config.decimalSymbol
local INFINITY_SYMBOL = config.infinitySymbol
local QUIET_NAN_SYMBOL = config.quietNaNSymbol
local SIGNALING_NAN_SYMBOL = config.signalingNaNSymbol
local SHOW_NAN_PAYLOAD = config.showNaNPayload
local SUBNORMALS_AS_ZERO = config.subnormalsAsZero

function _aux.round_sig(fmt: { number }, fmt_n: number, sig: number): (number, boolean)
	local incr_e = false

	if sig <= 0 then
		fmt_n = 0
	elseif fmt_n > sig then
		local incr = fmt[sig + 1] > 5 or
			fmt[sig + 1] == 5 and (fmt_n > sig + 1
				or fmt[sig] % 2 == 1)

		fmt_n = sig

		if incr then
			while fmt[fmt_n] == 9 and fmt_n > 0 do
				fmt_n -= 1
			end

			if fmt_n == 0 then
				fmt[1] = 1
				fmt_n = 1
				incr_e = true
			else
				fmt[fmt_n] += 1
			end
		end
	end
	
	-- strip trailing zeroes
	while fmt[fmt_n] == 0 do
		fmt_n -= 1
	end

	return fmt_n, incr_e
end

local function internal_get_digits(fmt: { number }, fmt_n: number, i: number, j: number): string
	local leftz, strd, rightz, rightzn

	if i <= 0 then
		leftz = string.rep("0", -i + 1)
		i = 1
	else
		leftz = ""
	end

	rightzn = j - math.max(fmt_n, i - 1)
	if rightzn <= 0 then
		rightz = ""
	else
		j = fmt_n
		rightz = string.rep("0", rightzn)
	end

	if i > fmt_n then
		strd = ""
	else
		strd = string.char(table.unpack(fmt, i, j))
	end

	return leftz .. strd .. rightz
end

function _aux.format_unsigned_finite(
	fmt: { number }, fmt_n: number, marker: number,
	req_digits: number?, min_grouping: number): string
	local intg, frac

	for i = 1, fmt_n do
		fmt[i] += 0x30
	end

	frac = internal_get_digits(fmt, fmt_n, marker + 1, req_digits or fmt_n)

	if marker <= 0 then
		intg = "0"
	elseif marker >= min_grouping then
		local intg_l, ld, intg_group
		
		ld = (marker - 1) % 3 + 1
		intg_l = internal_get_digits(fmt, fmt_n, 1, ld)
		intg_group = internal_get_digits(fmt, fmt_n, ld + 1, marker)
		
		intg_group = string.gsub(intg_group, "...", GROUPING_REPL)
		
		intg = intg_l .. intg_group
	else
		intg = internal_get_digits(fmt, fmt_n, 1, marker)
	end

	if frac == "" then
		return intg
	end

	return intg .. DECIMAL_SYMBOL .. frac
end

function _aux.format_special(value: number, req_digits: number): string?
	-- Check for infinite, NaN, and zero values
	local result = nil
	local is_huge = value == math.huge
	local is_n_huge = value == -math.huge

	-- is_huge and is_n_huge is there just in case the ffinite-math-only flag is on
	-- for x86 processors (which is pretty unlikely in Roblox)
	if value ~= value or is_huge and is_n_huge then
		-- NaN
		local sigt0, sigt1, sigt2, sigt3, sigt4, sigt5, sigt6, sign =
			string.byte(string.pack("<d", value), 1, 8)
		-- The inverse might happen on some CPUs but on Roblox this is unlikely
		if bit32.band(sigt6, 0x08) == 0 then
			result = SIGNALING_NAN_SYMBOL
		else
			result = QUIET_NAN_SYMBOL
		end
		if sign > 0x7F then
			result = "-" .. result
		end
		
		if SHOW_NAN_PAYLOAD then
			result ..= string.format(
				" 0x%01X%02X%02X%02X%02X%02X%02X",
				bit32.band(sigt6, 0x0F),
				sigt5, sigt4, sigt3, sigt2, sigt1, sigt0
			)
		end
	elseif is_huge then
		-- +Infinity
		result = INFINITY_SYMBOL
	elseif is_n_huge then
		-- -Infinity
		result = "-" .. INFINITY_SYMBOL
	elseif value == 0 or SUBNORMALS_AS_ZERO and value * 1 == 0 then
		-- +0 and -0
		result = if math.atan2(value, -1) < 0 then "-0" else "0"
		if req_digits > 1 then
			result ..= DECIMAL_SYMBOL
				.. string.rep("0", req_digits - 1)
		end
	end

	return result
end

local function arg_error_msg(value, type_expected, arg_n): string
	local msg
	if value == nil then
		msg = string.format(
			"Expected %s in argument #%d, got nil or is missing",
			type_expected, arg_n
		)
	else
		msg = string.format(
			"Expected %s in argument #%d, got %s",
			type_expected, arg_n, typeof(value)
		)
	end
	
	return msg
end

function _aux.expect_strictly_number(value: number, arg_n)
	if type(value) == "string" and tostring(value) then
		error(string.format(
			"Argument #%d won't be implicitly casted to number, please use explicit casting",
			arg_n
		), 3)
	elseif type(value) ~= "number" then
		error(arg_error_msg(value, "number", arg_n), 3)
	end
end

function _aux.cast_to_string(value: string?, arg_n, default: string?): string
	if value == nil and default then
		return default
	end
	
	if type(value) == "number" then
		return value .. ""
	elseif type(value) ~= "string" then
		error(arg_error_msg(value, "string", arg_n), 3)
	end

	return value :: string
end

function _aux.cast_to_int32_t_check_range(value, min: number?, max: number?, arg_n, default: number?): number
	if value == nil and default then
		return default
	end
	
	-- try to cast to number
	local c_value = tonumber(value) :: number
	local call_native = false
	
	if not c_value then
		error(arg_error_msg(value, "number", arg_n), 3)
	end
	
	-- then cast to int32_t
	if c_value <= -1 then
		if c_value <= -0x80000001 then
			-- NaN on -ffinite-math-only flag on x86
			call_native = true
		else
			c_value = math.ceil(c_value)
		end
	elseif c_value >= 1 then
		if c_value >= 0x80000000 then
			call_native = true
		else
			c_value = math.floor(c_value)
		end
	elseif c_value == c_value then
		-- values that will be truncated to zero
		c_value = 0
	else
		-- NaN
		call_native = true
	end
	
	if call_native then
		-- Use platform dependant double to int32_t conversion
		-- cvttsd2si might be one the instruction called (on x86)
		c_value = UDim.new(nil, c_value).Offset
	end
	
	if min and max and (c_value < min or c_value > max) then
		error(string.format(
			"Expected value in range (%d..%d) in argument #%d, got %d",
			min, max, arg_n, c_value
		), 3)
	end
	
	return c_value
end

return table.freeze(_aux)