local unbans = unbans or {}

function unbans.init()
	ULib.ucl.registerAccess( "xgui_manageunbans", "superadmin", "Allows addition, removal, and viewing of SourceBans in XGUI.", "XGUI" )

	xgui.addDataType( "unbans", function() return { count=table.Count( SBanTable ) } end, "xgui_manageunbans", 30, 20 )

	--Chat commands
	local function xgui_banWindowChat( ply, func, args, doFreeze )
		if doFreeze ~= true then doFreeze = false end
		if args[1] and args[1] ~= "" then
			local target = ULib.getUser( args[1] )
			if target then
				ULib.clientRPC( ply, "xgui.ShowSBanWindow", target, target:SteamID(), doFreeze )
			end
		else
			ULib.clientRPC( ply, "xgui.ShowSBanWindow" )
		end
	end
	ULib.addSayCommand(	"!xsban", xgui_banWindowChat, "ulx sban" )

	local function xgui_banWindowChatFreeze( ply, func, args )
		xgui_banWindowChat( ply, func, args, true )
	end
	ULib.addSayCommand(	"!fsban", xgui_banWindowChatFreeze, "ulx sban" )

	--XGUI commands
	function unbans.updateBan( ply, args )
		local access, accessTag = ULib.ucl.query( ply, "ulx sban" )
		if not access then
			ULib.tsayError( ply, "Error editing ban: You must have access to ulx sban, " .. ply:Nick() .. "!", true )
			return
		end
		
		local steamID = args[1]
		local bantime = tonumber( args[2] )
		local reason = args[3]
		local name = args[4]
		
		if SBanTable[steamID] and SBanTable[steamID].adminid != ply.sb_aid and !ULib.ucl.query( ply, "ulx editsbanall" ) then
			ULib.tsayError( ply, "Error: You do not have permission to edit another admin's ban.", true )
			return
		end

		-- Check restrictions
		local cmd = ULib.cmds.translatedCmds[ "ulx sban" ]
		local accessPieces = {}
		if accessTag then
			accessPieces = ULib.splitArgs( accessTag, "<", ">" )
		end

		-- Ban length
		local argInfo = cmd.args[3]
		local success, err = argInfo.type:parseAndValidate( ply, bantime, argInfo, accessPieces[2] )
		if not success then
			ULib.tsayError( ply, "Error editing ban: " .. err, true )
			return
		end

		-- Reason
		local argInfo = cmd.args[4]
		local success, err = argInfo.type:parseAndValidate( ply, reason, argInfo, accessPieces[3] )
		if not success then
			ULib.tsayError( ply, "Error editing ban: You did not specify a valid reason, " .. ply:Nick() .. "!", true )
			return
		end


		if not SBanTable[steamID] then
			SBAN_doban("", steamID, name, bantime*60, reason, ply)
			
			local banStr = "for #i minute(s)"
			if bantime == 0 then banStr = "permanently" end
			local str = "#A banned steamid #s "
			if name then
				steamID = steamID .. "(" .. name .. ") "
			end
			str = str .. banStr
			if reason and reason ~= "" then str = str .. " (#4s)" end
			ulx.fancyLogAdmin( ply, str, steamID, bantime ~= 0 and bantime or reason, reason )
			return
		end

		if name == "" then
			name = nil
			SBanTable[steamID].name = nil
		end

		if bantime ~= 0 then
			if (SBanTable[steamID].time + bantime*60) <= os.time() then --New ban time makes the ban expired				
				ulx.unsban( ply, steamID, "Expired" )
				return
			end
			--bantime = bantime - (os.time() - SBanTable[steamID].time)/60
		end
		SBAN_updateban( steamID, ply, bantime*60, reason, name)
	end
	xgui.addCmd( "updatesBan", unbans.updateBan )

	--Misc functions
	function unbans.processBans(wait)
		unbans.clearSortCache()
		if wait then
			timer.Simple(1, function() 
				xgui.sendDataTable( {}, "unbans" )	--Only sends the ban count, and triggers the client to clear their cache.
			end)
		else
			xgui.sendDataTable( {}, "unbans" )
		end
	end

	function unbans.clearSortCache()
		xgui.bansbyid = {}
		xgui.bansbyname = {}
		xgui.bansbyadmin = {}
		xgui.bansbyreason = {}
		xgui.bansbydate = {}
		xgui.bansbyunban = {}
		xgui.bansbybanlength = {}
		SBAN_RetrieveBans()
		
	end

	function unbans.getSortTable( sortType, ply )
		-- Retrieve the sorted table of bans. If type hasn't been sorted, then sort and cache.
		if sortType == 1 then
			-- Bans by Name
			if next( xgui.bansbyname ) == nil then
				for k, v in pairs( SBanTable ) do
					table.insert( xgui.bansbyname, { k, v.name and string.upper( v.name ) or nil } )
				end
				table.sort( xgui.bansbyname, function( a, b ) return (a[2] or "\255" .. a[1]) < (b[2] or "\255" .. b[1]) end )
			end
			return xgui.bansbyname

		elseif sortType == 2 then
			-- Bans by SteamID
			if next( xgui.bansbyid ) == nil then
				for k, v in pairs( SBanTable ) do
					table.insert( xgui.bansbyid, { k } )
				end
				table.sort( xgui.bansbyid, function( a, b ) return a[1] < b[1] end )
			end
			return xgui.bansbyid

		elseif sortType == 3 then
			-- Bans by Admin
			if next( xgui.bansbyadmin ) == nil then
				for k, v in pairs( SBanTable ) do
					table.insert( xgui.bansbyadmin, { k, v.admin or "" } )
				end
				table.sort( xgui.bansbyadmin, function( a, b ) return a[2] < b[2] end )
			end
			return xgui.bansbyadmin

		elseif sortType == 4 then
			-- Bans by Reason
			if next( xgui.bansbyreason ) == nil then
				for k, v in pairs( SBanTable ) do
					table.insert( xgui.bansbyreason, { k, v.reason or "" } )
				end
				table.sort( xgui.bansbyreason, function( a, b ) return a[2] < b[2] end )
			end
			return xgui.bansbyreason

		elseif sortType == 5 then
			-- Bans by Unban Date
			if next( xgui.bansbyunban ) == nil then
				for k, v in pairs( SBanTable ) do
					table.insert( xgui.bansbyunban, { k, v.unban or 0 } )
				end
				table.sort( xgui.bansbyunban, function( a, b ) return a[2] < b[2] end )
			end
			return xgui.bansbyunban

		elseif sortType == 6 then
			-- Bans by Ban Length
			if next( xgui.bansbybanlength ) == nil then
				for k, v in pairs( SBanTable ) do
					table.insert( xgui.bansbybanlength, { k, (tonumber(v.unban) ~= 0) and (v.unban - v.time) or nil } )
				end
				table.sort( xgui.bansbybanlength, function( a, b ) return (a[2] or math.huge) < (b[2] or math.huge) end )
			end
			return xgui.bansbybanlength

		else
			if next( xgui.bansbydate ) == nil then
				for k, v in pairs( SBanTable ) do
					table.insert( xgui.bansbydate, { k, v.time or 0 } )
				end
				table.sort( xgui.bansbydate, function( a, b ) return tonumber( a[2] ) > tonumber( b[2] ) end )
			end
			return xgui.bansbydate
		end
	end

	function unbans.sendBansToUser( ply, args )
		if not ply then return end
		if !ULib.ucl.query( ply, "ulx unsbanall" ) and !ULib.ucl.query( ply, "ulx editsbanall" ) and !ULib.ucl.query( ply, "ulx sban" ) and !ULib.ucl.query( ply, "ulx sbanid" ) and !ULib.ucl.query( ply, "ulx unsban" ) then return end
		--local perfTimer = os.clock() --Debug

		-- Default params
		sortType = tonumber( args[1] ) or 0
		filterString = args[2] and args[2] ~= "" and string.lower( args[2] ) or nil
		filterPermaBan = args[3] and tonumber( args[3] ) or 0
		filterIncomplete = args[4] and tonumber( args[4] ) or 0
		page = tonumber( args[5] ) or 1
		ascending = tonumber( args[6] ) == 1 or false

		-- Get cached sort table to use to reference the real data.
		sortTable = unbans.getSortTable( sortType, ply )

		local bansToSend = {}

		-- Handle ascending or descending
		local startValue = ascending and #sortTable or 1
		local endValue = ascending and 1 or #sortTable
		local firstEntry = (page - 1) * 17
		local currentEntry = 0

		local noFilter = ( filterPermaBan == 0 and filterIncomplete == 0 and filterString == nil )

		for i = startValue, endValue, ascending and -1 or 1 do
			local steamID = sortTable[i][1]
			local bandata = SBanTable[steamID]
			if !bandata then continue end
			-- Handle filters. This is confusing, but essentially 0 means skip check, 1 means restrict if condition IS true, 2+ means restrict if condition IS NOT true. 
			if not ( filterPermaBan > 0 and ( ( tonumber( bandata.unban ) == 0 ) == ( filterPermaBan == 1 ) ) ) then
				if not ( filterIncomplete > 0 and ( ( bandata.time == nil ) == ( filterIncomplete == 1 ) ) ) then

					-- Handle string filter
					if not ( filterString and
						not ( steamID and string.find( string.lower( steamID ), filterString ) or
							bandata.name and string.find( string.lower( bandata.name ), filterString ) or
							bandata.reason and string.find( string.lower( bandata.reason ), filterString ) or
							bandata.admin and string.find( string.lower( bandata.admin ), filterString ) or
							bandata.modified_admin and string.find( string.lower( bandata.modified_admin ), filterString ) )) then

						--We found a valid one! .. Now for the pagination.
						if #bansToSend < 17 and currentEntry >= firstEntry then
							table.insert( bansToSend, bandata )
							bansToSend[#bansToSend].steamID = steamID
							if noFilter and #bansToSend >= 17 then break end	-- If there is a filter, then don't stop the loop so we can get a "result" count.
						end
						currentEntry = currentEntry + 1
					end
				end
			end
		end
		if not noFilter then bansToSend.count = currentEntry end

		--print( "XGUI: Ban request took " .. os.clock() - perfTimer ) --Debug

		-- Send bans to client via custom handling.
		xgui.sendDataEvent( ply, 7, "unbans", bansToSend )
	end
	xgui.addCmd( "getsbans", unbans.sendBansToUser )
--[[
	--Hijack the addBan function to update XGUI's ban info.
	local banfunc = ULib.addBan
	ULib.addBan = function( steamid, time, reason, name, admin )
		banfunc( steamid, time, reason, name, admin )
		unbans.processBans()
	end

	--Hijack the unBan function to update XGUI's ban info.
	local unbanfunc = ULib.unban
	ULib.unban = function( steamid, admin )
		unbanfunc( steamid, admin )
		unbans.processBans()
		if timer.Exists( "xgui_unban" .. steamid ) then
			timer.Destroy( "xgui_unban" .. steamid )
		end
	end
--]]
	ulx.addToHelpManually( "Menus", "xgui fsban", "<player> - Opens the add ban window, freezes the specified player, and fills out the Name/SteamID automatically. (say: !fsban)" )
	ulx.addToHelpManually( "Menus", "xgui xsban", "<player> - Opens the add ban window and fills out Name/SteamID automatically if a player was specified. (say: !xsban)" )
end

function unbans.postinit()
	unbans.processBans()
end

function XGUIRefreshBans()
	unbans.processBans(true)
end

xgui.addSVModule( "unbans", unbans.init, unbans.postinit )