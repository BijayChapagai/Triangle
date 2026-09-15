return {
	-- Symbols
	-- The default is ","
	groupingSymbol = ",",
	-- The default is "."
	decimalSymbol = ".",
	-- The default is "∞"
	infinitySymbol = "∞",
	-- The default is "NaNQ"
	quietNaNSymbol = "NaNQ",
	-- there's a small chance that signaling NaN could raise a floating point exception
	-- in this case, signaling NaNs are not supported
	-- THe default is "NaNS"
	signalingNaNSymbol = "NaNS",
	
	-- Suffixes displayed for every power of thousands
	-- The default is K, M, B, T - similar to the one provided by Unicode CLDR.
	-- You can add more or change the suffixes provided here.
	compactSuffix = {
		"K", "M", "B", "T",
	},

	-- advanced configurations --
	showNaNPayload = true,
	
	-- Will only work if the FTZ flag is on and the DAZ flag is off
	-- If the DAZ flag is on then this option will always be true even if you set it to 'false'
	-- If the FTZ flag is off (and the DAZ flag is off) then this option will always be false even if you set it to 'true'.
	-- Currently the Roblox engine has the FTZ flag on but not the DAZ flag (well perhaps except in the Server Studio)
	subnormalsAsZero = false,
	
	
	-- undocumented --
	durationSeparatorSymbol = ":",
	
	useARM64FCVTZS = false,
}