local CATEGORY_NAME = "Source Bans"

function ulx.sban( calling_ply, target_ply, minutes, reason )
	
	if target_ply:IsBot() then
		ULib.tsayError( calling_ply, "Cannot ban a bot", true )
		return
	end

	local time = "for #i minute(s)"
	if minutes == 0 then time = "permanently" end
	local str = "#A banned #T " .. time
	if reason and reason ~= "" then str = str .. " (#s)" end
	ulx.fancyLogAdmin( calling_ply, str, target_ply, minutes ~= 0 and minutes or reason, reason )
	
	ULib.queueFunctionCall( SBAN_banplayer, target_ply, minutes*60, reason, calling_ply)
end
local sban = ulx.command( CATEGORY_NAME, "ulx sban", ulx.sban, "!sban" )
sban:addParam{ type=ULib.cmds.PlayerArg }
sban:addParam{ type=ULib.cmds.NumArg, hint="minutes, 0 for perma", ULib.cmds.optional, ULib.cmds.allowTimeString, min=0 }
sban:addParam{ type=ULib.cmds.StringArg, hint="reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine, completes=ulx.common_kick_reasons }
sban:defaultAccess( ULib.ACCESS_ADMIN )
sban:help( "Bans target." )

function ulx.sbanid( calling_ply, steamid, minutes, reason )
	steamid = steamid:upper()
	if not ULib.isValidSteamID( steamid ) then
		ULib.tsayError( calling_ply, "Invalid steamid." )
		return
	end

	local name
	local plys = player.GetAll()
	for i=1, #plys do
		if plys[ i ]:SteamID() == steamid then
			name = plys[ i ]:Nick()
			break
		end
	end
	
	local time = "for #i minute(s)"
	if minutes == 0 then time = "permanently" end
	local str = "#A banned steamid #s "
	if name then
		steamid = steamid .. "(" .. name .. ") "
	end
	str = str .. time
	if reason and reason ~= "" then str = str .. " (#4s)" end
	ulx.fancyLogAdmin( calling_ply, str, steamid, minutes ~= 0 and minutes or reason, reason )
	
	if(name != nil) then
		SBAN_doban("unknown", steamid, name, minutes*60, reason, calling_ply)
	else
		SBAN_doban("unknown", steamid, "[Unknown]", minutes*60, reason, calling_ply)
	end
end
local sbanid = ulx.command( CATEGORY_NAME, "ulx sbanid", ulx.sbanid )
sbanid:addParam{ type=ULib.cmds.StringArg, hint="steamid" }
sbanid:addParam{ type=ULib.cmds.NumArg, hint="minutes, 0 for perma", ULib.cmds.optional, ULib.cmds.allowTimeString, min=0 }
sbanid:addParam{ type=ULib.cmds.StringArg, hint="reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine, completes=ulx.common_kick_reasons }
sbanid:defaultAccess( ULib.ACCESS_SUPERADMIN )
sbanid:help( "Bans steamid." )

------------------------------Unban SourceBans----------------------
function ulx.unsban( calling_ply, steamid, ureason )
	steamid = steamid:upper()
	if not ULib.isValidSteamID( steamid ) then
		ULib.tsayError( calling_ply, "Error: Invalid Steam ID!", true )
		return
	end
	if SBanTable[ steamid ] then
		if ( SBanTable[ steamid ].adminid != calling_ply.sb_aid ) and !ULib.ucl.query( calling_ply, "ulx unsbanall" )  then
			ULib.tsayError( calling_ply, "Error: You do not have permission to remove another admin's ban.", true )
			return
		end
	elseif !SBAN_canunban(steamid, calling_ply) then
		ULib.tsayError( calling_ply, "Error: You do not have permission to remove another admin's ban.", true )
		return
	end
	name = SBanTable[ steamid ] and SBanTable[ steamid ].name
	if !ureason or string.len(ureason) < 3 then
		ULib.tsayError( calling_ply, "Error: Please specify an unban reason!", true )
		return
	end
	ureason = calling_ply:Nick() .. ": "..ureason
	SBAN_unban( steamid, calling_ply, ureason )
	if name then
		ulx.fancyLogAdmin( calling_ply, "#A unbanned steamid #s", steamid .. " (" .. name .. ")" )
	else
		ulx.fancyLogAdmin( calling_ply, "#A unbanned steamid #s", steamid )
	end
end
local unsban = ulx.command( CATEGORY_NAME, "ulx unsban", ulx.unsban )
unsban:addParam{ type=ULib.cmds.StringArg, hint="Steam ID" }
unsban:addParam{ type=ULib.cmds.StringArg, hint="Unban reason", ULib.cmds.takeRestOfLine }
unsban:defaultAccess( ULib.ACCESS_ADMIN )
unsban:help( "Unbans Steam ID from SourceBans." )