--[[
This module is superseded by the Simple API of FormatNumber 31.
Bug fixes will still be provided but no documented features will likely be added.

If you want to transition to the Simple API of FormatNumber 31 then you can use these alternatives:
FormatNumber 30 Alternative API --> FormatNumber 31 Simple API *approximate* equivalent
`FormatNumber.FormatInt(value)` --> `FormatNumber.Format(value, "precision-integer")`
`FormatNumber.FormatStandard(value)` --> `FormatNumber.Format(value, "precision-unlimited")`
`FormatNumber.FormatFixed(value)` --> `FormatNumber.Format(value, ".000000")`
`FormatNumber.FormatFixed(value, 2)` --> `FormatNumber.Format(value, ".00")`
`FormatNumber.FormatFixed(value, 3)` --> `FormatNumber.Format(value, ".000")`
`FormatNumber.FormatPrecision(value)` --> `FormatNumber.Format(value, "@@@@@@")`
`FormatNumber.FormatPrecision(value, 2)` --> `FormatNumber.Format(value, "@@")`
`FormatNumber.FormatPrecision(value, 3)` --> `FormatNumber.Format(value, "@@@")`
`FormatNumber.FormatCompact(value)` --> `FormatNumber.FormatCompact(value)`
`FormatNumber.FormatCompact(value, 0)` --> `FormatNumber.FormatCompact(value, "precision-integer")`
`FormatNumber.FormatCompact(value, 1)` --> `FormatNumber.FormatCompact(value, ".#")`
`FormatNumber.FormatCompact(value, 2)` --> `FormatNumber.FormatCompact(value, ".##")`
`FormatNumber.FormatCompact(value, 3)` --> `FormatNumber.FormatCompact(value, ".###")`

Licence:
FormatNumber 30 Alternative API
2022-07-18
BSD 2-Clause Licence
Copyright 2022 - Blockzez (https://devforum.roblox.com/u/Blockzez and https://github.com/Blockzez)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]


local config = require(script.config)
local _aux = require(script._aux)
local FormatNumber = { }

local GROUPING_SYMBOL = config.groupingSymbol
local GROUPING_REPL = "%0" .. string.gsub(
	string.reverse(GROUPING_SYMBOL), "%%", "%%%%")
local COMPACT_SUFFIX = config.compactSuffix

local UNUM_GROUPING_AUTO = 4 -- 3 + minGrouping
local UNUM_GROUPING_MIN2 = 5 -- 3 + math.max(minGrouping, 2)

local USE_ARM64_FCVTZS = config.useARM64FCVTZS and
	-- Use the default behaviour on ARM64
	string.format("%d", math.huge * 0) ~= "0"

--- API
--[[
All of these function formats so the integer part of the formatted number are separated by the grouping separator (commas by default) every 3 digits.
]]


--[[
Formats an integer.
]]
function FormatNumber.FormatInt(value: number): string
	local fmt, result
	
	_aux.expect_strictly_number(value, 1)
	
	-- %d casts IEEE 754/IEC 559 doubles to long long (signed integer at 64-bit minimum) in Luau
	
	-- Undocumented
	if USE_ARM64_FCVTZS then
		-- presumably on x86 as I don't think you can run Roblox on say like s390x or RISC-V
		if value ~= value or value == 0 and value == 1 then
			fmt = "+0"
		elseif value >= 0x8000000000000000 then
			fmt = "+9223372036854775807"
		elseif value <= -0x8000000000000000 then
			fmt = "-9223372036854775808"
		else
			fmt = string.format("%+d", value)
		end
	--
	else
		fmt = string.format("%+d", value)
	end
	
	-- Check negative number this way just in case positive values got casted
	-- into negative (e.g. on all doubles out of range for cvttsd2si oon x86 - https://www.felixcloutier.com/x86/cvttsd2si)
	result = string.sub(fmt, if string.byte(fmt) == 0x2D then 1 else 2, 2)
	result ..= string.reverse(
		(string.gsub(
			string.reverse(string.sub(fmt, 3)),
			"...", GROUPING_REPL
		))
	)
	
	return result
end

-- Anything beyond this point requires the DoubleConversion module
-- We might use tostring for FormatStandard and FormatCompact
-- Please see license DoubleConversion.LICENSE or here if included
--[[
Double conversion Luau port
Version 1.0.0b1-git
BSD 2-Clause Licence
Copyright 2021 - Blockzez (github.com/Blockzez)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Copyright 2006-2011, the V8 project authors. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the following
  disclaimer in the documentation and/or other materials provided
  with the distribution.
* Neither the name of Google Inc. nor the names of its
  contributors may be used to endorse or promote products derived
  from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
local DoubleConversion = script.DoubleConversion
local DoubleToDecimalConverter = require(DoubleConversion.DoubleToDecimalConverter)

--[[
Formats a number.
]]
function FormatNumber.FormatStandard(value: number): string
	local result

	_aux.expect_strictly_number(value, 1)

	result = _aux.format_special(value, 0)

	if not result then
		local fmt, fmt_n, scale
		local marker

		fmt, fmt_n, scale = DoubleToDecimalConverter.ToShortest(value)
		marker = scale + fmt_n

		result = _aux.format_unsigned_finite(
			fmt, fmt_n, marker, nil, UNUM_GROUPING_AUTO)

		if value < 0 then
			result = "-" .. result
		end
	end

	return result
end

--[[
Formats a number rounded to the certain decimal places.
The default is 6 decimal places.
Bankers' rounding is used.
]]
function FormatNumber.FormatFixed(value: number, digits: number?): string
	local result
	local c_digits
	
	_aux.expect_strictly_number(value, 1)
	c_digits = _aux.cast_to_int32_t_check_range(digits, 0, 9999, 2, 6)
	
	result = _aux.format_special(value, c_digits + 1)
	
	if not result then
		local fmt, fmt_n, scale
		local marker
		local sigd
		local incr_e
		
		fmt, fmt_n, scale = DoubleToDecimalConverter.ToExact(value)
		marker = scale + fmt_n
		sigd = marker + c_digits
		fmt_n, incr_e = _aux.round_sig(fmt, fmt_n, sigd)
		
		if incr_e then
			marker += 1
			sigd += 1
		elseif fmt_n == 0 then
			-- edge case for values rounded to zero
			marker = 1
			sigd = c_digits
		end
		
		result = _aux.format_unsigned_finite(
			fmt, fmt_n, marker, sigd, UNUM_GROUPING_AUTO)
		
		if value < 0 then
			result = "-" .. result
		end
	end
	
	return result
end

--[[
Formats a number rounded to the certain significant digits.
The default is 6 significant digits.
Bankers' rounding is used.
]]
function FormatNumber.FormatPrecision(value: number, digits: number?): string
	local result
	local c_digits

	_aux.expect_strictly_number(value, 1)
	c_digits = _aux.cast_to_int32_t_check_range(digits, 1, 9999, 2, 6)

	result = _aux.format_special(value, c_digits)

	if not result then
		local fmt, fmt_n, scale
		local marker
		local incr_e

		fmt, fmt_n, scale = DoubleToDecimalConverter.ToExact(value)
		marker = scale + fmt_n
		fmt_n, incr_e = _aux.round_sig(fmt, fmt_n, c_digits)

		if incr_e then
			marker += 1
		end

		result = _aux.format_unsigned_finite(
			fmt, fmt_n, marker, c_digits, UNUM_GROUPING_AUTO)

		if value < 0 then
			result = "-" .. result
		end
	end

	return result
end

--[[
Formats a number so it is in compact notation (abbreviated such as "1000" to "1K").
The significand (referring to 1.2 in "1.2K") is truncated to certain decimal places specified in the fractionDigits argument. If the fractionDigits argument is not provided, then the significand is truncated to integers but keeping 2 significant digits.
You can change the suffix by changing the `compactSuffix` field from the `config` ModuleScript included in the module.
]]
function FormatNumber.FormatCompact(value: number, fractionDigits: number?, significantDigits: number?): string
	local result
	local frac_d
	local sig_d

	_aux.expect_strictly_number(value, 1)
	frac_d = _aux.cast_to_int32_t_check_range(fractionDigits, 0, 999, 2,
		if significantDigits then -0x80000000 else 0)
	sig_d = _aux.cast_to_int32_t_check_range(significantDigits, 1, 99, 3,
		if fractionDigits then 0 else 2)

	result = _aux.format_special(value, 0)

	if not result then
		local fmt, fmt_n, scale
		local marker
		local selected_postfix = nil
		local selected_i
		local resolved_sig

		fmt, fmt_n, scale = DoubleToDecimalConverter.ToShortest(value)
		marker = scale + fmt_n
		
		selected_i = math.min(
			math.floor((marker - 1) / 3),
			#COMPACT_SUFFIX
		)
		if selected_i > 0 then
			marker -= selected_i * 3
			selected_postfix = COMPACT_SUFFIX[selected_i]
		end
		
		-- try to truncate
		resolved_sig = math.max(sig_d, marker + frac_d)
		
		if fmt_n > resolved_sig then
			fmt_n = resolved_sig
			if fmt_n <= 0 then
				marker = 1
				fmt_n = 0
			end
		end
		
		-- strip trailing zeroes
		while fmt[fmt_n] == 0 do
			fmt_n -= 1
		end

		result = _aux.format_unsigned_finite(
			fmt, fmt_n, marker, nil, UNUM_GROUPING_MIN2)

		if value < 0 then
			result = "-" .. result
		end
		
		if selected_postfix then
			result ..= selected_postfix
		end
	end

	return result
end
--

-- Undocumented
-- These functions could be removed or modified in the future without notice

function FormatNumber.FormatHexFloat(value: number, digits: number?, uppercased: boolean?): string
	local result
	local c_digits
	local sigt, expt
	local sigt_s, expt_s
	local is_negt

	_aux.expect_strictly_number(value, 1)
	c_digits = _aux.cast_to_int32_t_check_range(digits, 0, 99, 2, -1)
	
	if value ~= value or value == math.huge or value == -math.huge then
		is_negt = false
		result = string.format("%g", value)
	else
		is_negt = math.atan2(value, -1) < 0
		sigt, expt = math.frexp(math.abs(value))
		-- shift the subnormals
		if expt <= -1022 then
			sigt = math.ldexp(sigt, expt + 1074)
			expt = -1022
		elseif sigt ~= 0 then
			sigt = math.ldexp(sigt, 53)
			expt -= 1
		end
		
		if c_digits == -1 then
			sigt_s = string.format("0x%013x", sigt)
		elseif c_digits < 13 then
			sigt_s = string.format(
				string.char(0x30, 0x78, 0x25, 0x30,
					0x30 + c_digits / 10,
					0x30 + c_digits % 10,
					0x78
				),
				math.round(math.ldexp(
					sigt,
					(c_digits - 13) * 4
				))
			)
		else
			sigt_s = string.format("0x%013x", sigt)
				.. string.rep("0", c_digits - 13)
		end
		
		sigt_s = string.gsub(sigt_s, "^(...)(.)", "%1.%2", 1)
		if c_digits == -1 then
			sigt_s = string.gsub(sigt_s, "%.?0+$", "")
		end
		
		result = string.format(
			"%sp%+d",
			sigt_s,
			expt
		)
	end
	
	if uppercased then
		result = string.upper(result)
	end
	
	if is_negt then
		result = "-" .. result
	end

	return result
end

-- From CLDR English locale
-- seconds minute hour day week order
local DURATION_UNIT_EN_TEXT = {
	["width-long"] = {
		"week",
		"day",
		"hour",
		"minute",
		"second",
	},
	["width-short"] = {
		"wk",
		"day",
		"hr",
		"min",
		"sec",
	},
	["width-narrow"] = {
		"w",
		"d",
		"h",
		"m",
		"s",
	},
	["width-numeric"] = "numeric",
	["width-2-digit"] = "2-digit",
}
local UNIT_FROM_SEC = {
	60 * 60 * 24 * 7,
	60 * 60 * 24,
	60 * 60,
	60,
	1,
}
local DURATION_SEPARATOR = config.durationSeparatorSymbol
function FormatNumber.FormatDuration(value: number, skeleton: string?): string
	local rem_val
	local result
	local result_tbl
	local skeleton_string
	local selected_width
	local selected_width_str
	local max_unit
	local units_to_disp
	local plural_threshold
	local last_disp_i
	
	rem_val = _aux.cast_to_int32_t_check_range(value, nil, nil, 1, nil)
	skeleton_string = _aux.cast_to_string(skeleton, 2, "")
	
	if rem_val < 0 then
		error(string.format("Negative value, provided by the argument #1 (%d), is not supported", rem_val), 2)
	end
	
	for pos, token in string.gmatch(skeleton_string, "()(%S+)") do
		local is_valid
		local check_width = DURATION_UNIT_EN_TEXT[token]
		if check_width then
			is_valid = not selected_width
			selected_width = check_width
			selected_width_str = token
		else
			local c_token = token
			local is_a, is_o
			-- string pattern
			units_to_disp = table.create(5)
			
			for i, unit in DURATION_UNIT_EN_TEXT["width-narrow"] do
				is_a = string.match(
					c_token,
					"^" .. unit .. "(%??)"
				)
				if is_a then
					if is_a == "" then
						units_to_disp[i] = true
						c_token = string.sub(c_token, 2)
					else
						units_to_disp[i] = "nonzero"
						c_token = string.sub(c_token, 3)
					end
					last_disp_i = i
				else
					units_to_disp[i] = false
				end
			end
			
			is_valid = c_token == ""
		end
		
		if not is_valid then
			error(string.format(
				"skeleton syntax error near '%s' at position %d",
				(string.gsub(token, "'", "\\'")), pos
			), 2)
		end
	end
	
	if not selected_width then
		selected_width = "numeric"
		selected_width_str = "width-numeric"
	end
	
	if not units_to_disp then
		if selected_width_str == "width-numeric"
			or selected_width_str == "width-2-digits" then
			units_to_disp = { false, false, "nonzero", true, true }
			last_disp_i = 5
		else
			units_to_disp = { "nonzero", "nonzero", "nonzero", "nonzero", "nonzero" }
			last_disp_i = 5
		end
	end
	
	plural_threshold = if selected_width == "width-short" then 2 else 5
	result_tbl = table.create(5)
	for i, disp in units_to_disp do
		if disp then
			local to_div = UNIT_FROM_SEC[i]
			local quot_val = math.floor(rem_val / to_div)
			local ret_fmt
			
			if disp ~= "nonzero"
				or quot_val ~= 0
				or i == last_disp_i and not result_tbl[1] then
				rem_val -= quot_val * to_div
				if selected_width == "numeric" then
					ret_fmt = "%d"
					selected_width = "2-digit"
				elseif selected_width == "2-digit" then
					ret_fmt = "%02d"
				elseif selected_width_str == "width-narrow" then
					ret_fmt = "%d" .. selected_width[i]
				else
					ret_fmt = "%d " .. selected_width[i]
					if quot_val ~= 1 and
						i <= plural_threshold then
						ret_fmt ..= "s"
					end
				end
				
				table.insert(result_tbl, string.format(ret_fmt, quot_val))
			end
		end
	end
	
	if not result_tbl[2] then
		result = result_tbl[1]
	elseif selected_width_str == "width-long" then
		result = table.concat(result_tbl, ", ", 1, #result_tbl - 1)
		result ..= " and " .. result_tbl[#result_tbl]
	else
		result = table.concat(result_tbl,
			if selected_width_str == "width-short" then ", "
				elseif selected_width_str == "width-narrow" then " "
				else DURATION_SEPARATOR
		)
	end
	
	return result
end

function FormatNumber.FormatUInt(value: number): string
	local fmt, result

	_aux.expect_strictly_number(value, 1)

	if USE_ARM64_FCVTZS then
		if value ~= value or value == 0 and value == 1 then
			fmt = "0"
		elseif value >= 18446744073709551616 then
			fmt = "18446744073709551615"
		elseif value <= 0 then
			fmt = "0"
		else
			fmt = string.format("%.0f", math.floor(value))
		end
	else
		fmt = string.format("%u", value)
	end

	return string.reverse(
		(string.gsub(
			string.reverse(fmt),
			"...", GROUPING_REPL, (#fmt - 1) / 3
		))
	)
end

--

return table.freeze(FormatNumber)