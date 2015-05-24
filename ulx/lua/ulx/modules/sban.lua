--[[
--		Another ULX Source Bans Module 0.9
--
--		CREDITS:
--		This sban module was based on a very old version of ULX Source Bans Module by FunDK http://facepunch.com/showthread.php?t=1311847
--		It has been re-written a few times, but still has some bits of old stuff from the original.
-- 		The family sharing code is from McSimp on facepunch http://facepunch.com/showthread.php?t=1341204&p=43469693&viewfull=1#post43469693
--		The XGUI part of this module is the default ulx bans page modified to work with sbans. https://github.com/Nayruden/Ulysses/tree/master/ulx
--
--		INSTRUCTIONS:
--		This module requires mysqloo! Get it here http://facepunch.com/showthread.php?t=1357773
--		Edit the config section below to your liking, make sure you add ulx_sban_serverid to your server.cfg
--		You can find the correct number to use from the sourcebans website, if you only have one server, it will usually be 1
--		There will be an additional permission you can assign in ulx called xgui_manageunbans, this will let your admins see the sourcebans tab.
--		The tab will currently only show ACTIVE bans.
--]]

require ("mysqloo")

-- Config section
-- Add ulx_sban_serverid to your server.cfg

local SBAN_PREFIX			= "sb_"						--Prefix don't change if you don't know what you are doing
local SBAN_WEBSITE			= "sourceban.domain.com"	--Source Bans Website

local SBANDATABASE_HOSTNAME	= "localhost"			-- Database IP/Host
local SBANDATABASE_HOSTPORT	= 3306					--Database Port (Default mysql port 3306)
local SBANDATABASE_DATABASE	= "sourceban"			--Database Database/Schema
local SBANDATABASE_USERNAME	= "user"			--Database Username
local SBANDATABASE_PASSWORD	= "pass"	--Database Password
local database_sban = mysqloo.connect(SBANDATABASE_HOSTNAME, SBANDATABASE_USERNAME, SBANDATABASE_PASSWORD, SBANDATABASE_DATABASE, SBANDATABASE_HOSTPORT)

local APIKey				= "1234567890"	-- See http://steamcommunity.com/dev/apikey
local removeFromGroup		= true			-- Remove users from server groups if they don't exist in the sourcebans database
local checkSharing			= true			-- Check if players are borrowing the game, !!!! THIS REQUIRES AN API KEY !!!!!
local banLender				= true			-- Ban the lender of the game as well if the player gets banned?
local announceBanCount		= true			-- Announce to admins if players have bans on record.
local announceLender		= true			-- Announce to admins if players are borrowing gmod.
local banRetrieveLimit		= 150			-- Amount of bans to retrieve in XGUI.
local banListRefreshTime	= 119			-- Seconds between refreshing the banlist in XGUI, in case the bans change from outside of the server.

-- Table of groups who will get sharing/ban count notifications when players join.
-- Follow the format below to add more groups, make sure to add a comma if it isn't the last entry.
local adminTable = {
	["superadmin"] = true,
	["admin"] = true
}


-- This table excludes named groups from being removed, even if the option is turned on.
-- Format is the same as the admin table above.
local excludedGroups = {
	["vip"] = true
}

-- Don't touch these
CreateConVar("ulx_sban_serverid", "-1", FCVAR_NONE, "Sets the SBAN ServerID for the Source Bans ULX module")
local apiErrorCount = 0
local apiLastCheck = apiLastCheck or 0
local SBAN_Queue = SBAN_Queue or {}
SBanTable = SBanTable or {}

-- ServerID in server.cfg file
cvars.AddChangeCallback( "ulx_sban_serverid", function()
	if(GetConVar("ulx_sban_serverid"):GetInt() != -1) then
		SBAN_SERVERID = GetConVar("ulx_sban_serverid"):GetInt()
		print("[SBAN][Init] ServerID: "..SBAN_SERVERID)
	end
end)

hook.Add("Initialize", "CheckServerID", function()
	if !SBAN_SERVERID then
		if !GetConVar("ulx_sban_serverid"):GetInt() then
			ErrorNoHalt("[SBAN][ERROR] ulx_sban_serverid has not been set in server.cfg!\n")
		end
		SBAN_SERVERID = GetConVar("ulx_sban_serverid"):GetInt() or 1
	end
end)

database_sban.onConnected = function()
	ServerLog("[SBAN][Init] Mysql successfully connected\n")
	if SBAN_Queue then
		for k, v in pairs( SBAN_Queue ) do
			SBAN_SQL_Query( v[ 1 ], v[ 2 ]  )
		end
		SBAN_Queue = {}
	end
end

database_sban.onConnectionFailed = function( db, err ) 
	ServerLog("[SBAN][Init] Mysql failed to connect\n")
	ServerLog("[SBAN][Init] Mysql Error: "..tostring(err).."\n")
end

-- ############### Main Database Query Function ################
-- #############################################################
local function SBAN_SQL_Query(sql, qTab)

	local ply = qTab.ply
	local steamid = qTab.steamid
	local callback = qTab.cb
	local aid = qTab.aid
	local wait = qTab.wait
	local result
    local query = database_sban:query(sql)

	if !query then
		ServerLog("[SBAN] Query is empty?\n")
		if ( database_sban:status() != mysqloo.DATABASE_CONNECTED ) then
			database_sban:connect()
			ErrorNoHalt("[SBAN] Empty query, retrying connection.\n")
			return
		else
			error("[SBAN] Empty query, we're already connected.\n")
		end
	end

	query.onSuccess = function(_, data)

		if !callback then 
			result = data
		else
			callback(data, qTab)
		end

	end
	
	query.onError = function(_, err, sql)
		
		ServerLog("[SBAN][ERROR] "..err.."\n")
		ServerLog("[SBAN][ERROR] "..sql.."\n")
		if ( (database_sban:status() != mysqloo.DATABASE_CONNECTED) && callback ) then
			table.insert( SBAN_Queue, { sql, qTab } )
			database_sban:connect()
			return
		else
			database_sban:connect()
			database_sban:wait()
		end
		if ( database_sban:status() != mysqloo.DATABASE_CONNECTED ) then
			ErrorNoHalt("[SBAN] Re-connection to database server failed.\n")
			return
		end
	end
	
	query:start()
	if !callback then
		if wait then query:wait() end
		return result
	end
	
end


-- Initial connect
database_sban:connect()

-- ############### Local Helper functions ###############
-- ######################################################

local function RemoveAdmin(ply)
	if(ULib.ucl.getUserRegisteredID(ply) != nil) and removeFromGroup and !excludedGroups[ply:GetUserGroup()] then
		ulx.removeuserid(ply, ply:SteamID())
	end
end

local function DoKick(ply, reason)
	if !IsValid(ply) then return end
	if(reason == nil) then
		ply:Kick("You have been banned from this server, please visit "..SBAN_WEBSITE)
	else
		ply:Kick("You have been banned from this server ("..reason.."), please visit "..SBAN_WEBSITE)
	end
end

local function ReportBlock(bid, name)
	local ostime = os.time();
	local qTab = {}
	qTab.wait = false
	local query = "INSERT INTO "..SBAN_PREFIX.."banlog (sid, time, name, bid)"
	query = query.." VALUES ("..SBAN_SERVERID..", "..ostime..", '"..database_sban:escape(name).."', "..bid..");"
	
	SBAN_SQL_Query(query, qTab)
	
end

local function StillBanned(ply, bid, reason)
	if !IsValid(ply) then return end
	ReportBlock(bid,ply:Nick())
	DoKick(ply, reason)
end

ULib.ucl.registerAccess( "ulx unsbanall", ULib.ACCESS_SUPERADMIN, "Ability to unban all sban entries", "Other" ) -- Permission for admins to unban players banned by other admins.
ULib.ucl.registerAccess( "ulx editsbanall", ULib.ACCESS_SUPERADMIN, "Ability to edit all sban entries", "Other" ) -- Permission for admins to edit bans made by other admins.

-- ############### Global Helper functions ##############
-- ######################################################

function SBAN_doban(inip, steamid, name, length, reason, callingadmin, lenderid)
	local adminid = 0
	if type(callingadmin) == "number" then
		adminid = callingadmin
	elseif callingadmin:IsPlayer() and type(callingadmin.sb_aid) == "number" then
		adminid = callingadmin.sb_aid
	end
	local ip = string.Explode(":", inip)[1]
	local qTab = {}
	qTab.wait = false
	
	local time = os.time();
	
	local query = "INSERT INTO "..SBAN_PREFIX.."bans (ip, authid, name, created, ends, length, reason, aid, sid) "
	query = query.." VALUES ('"..database_sban:escape(ip).."', '"..database_sban:escape(steamid).."', '"..database_sban:escape(name).."',"..time..", "..(time + length)..", "..length..", '"..database_sban:escape(reason).."', "..adminid..", "..SBAN_SERVERID..");"
	SBAN_SQL_Query(query, qTab)
	
	if lenderid and banLender then
		
		local query2 = "INSERT INTO "..SBAN_PREFIX.."bans (ip, authid, name, created, ends, length, reason, aid, sid) "
		query2 = query2.."VALUES ('"..database_sban:escape(ip).."', '"..database_sban:escape(lenderid).."', '"..database_sban:escape(name).."',"..time..", "..(time + length)..", "..length..", '"..database_sban:escape(reason).."', "..adminid..", "..SBAN_SERVERID..");"
		SBAN_SQL_Query(query2, qTab)
		
	end
	XGUIRefreshBans()
end

function SBAN_banplayer(ply, length, reason, callingadmin)
	local lenderid = nil
	if ply.familyshared then
		lenderid = ply.lenderid
	end
	local ip = string.Explode(":",ply:IPAddress())[1]
	local steamid = ply:SteamID()
	local name = ply:Nick()

	SBAN_doban(ip, steamid, name, length, reason, callingadmin ,lenderid)
	DoKick(ply, reason)
end

function SBAN_getadmin_id(steamid)
	local found
	for k, v in pairs(player.GetAll()) do
		if v:SteamID() == steamid then
			found = v
			break
		end
	end
	
	if found.sb_aid then return found.sb_aid end
	
	local qTab = {}
	qTab.wait = true
	local query = SBAN_SQL_Query("SELECT aid FROM "..SBAN_PREFIX.."admins WHERE authid = '" ..steamid.. "'", qTab)
	return query[1].aid
end

function SBAN_unban(steamid, ply, ureason)
	local adminID = ply.sb_aid or 0
	local qTab = {}
	qTab.wait = false
	SBAN_SQL_Query("UPDATE "..SBAN_PREFIX.."bans SET RemovedOn = "..os.time()..", RemovedBy = "..adminID..", RemoveType = 'U', ureason = '"..database_sban:escape(ureason).."' WHERE authid = '"..database_sban:escape(steamid).."' and RemoveType is null", qTab)
	XGUIRefreshBans()
end

function SBAN_canunban(steamid, ply)
	local adminID = ply.sb_aid or 0
	
	local query = "SELECT * FROM "..SBAN_PREFIX.."bans WHERE authid = '"..database_sban:escape(steamid).."' and RemoveType is null"
	if !ULib.ucl.query( ply, "ulx unsbanall" ) then
		query = query .. " and aid = "..adminID
	end
	local qTab = {}
	qTab.wait = true
	
	return #SBAN_SQL_Query(query, qTab) > 0
end

function SBAN_updateban(steamid, ply, bantime, reason, name)
	local updateName = "[Unknown]"
	if name and string.len(name) > 0 then
		updateName = name
	end
	
	local qTab = {}
	qTab.wait = false
	local query = "UPDATE "..SBAN_PREFIX.."bans SET ends = created + "..bantime
	query = query .. ", length = "..bantime..", name = '"..database_sban:escape(updateName).."', reason = '"..database_sban:escape(reason).."' WHERE authid = '"..database_sban:escape(steamid).."' and RemoveType is null"
	SBAN_SQL_Query(query, qTab)
	XGUIRefreshBans()
end
-- ############### Unban UI  Section ###############
-- #################################################

local function UpdateBanList(result, qTab)
	local tempTable = {}
	for k,v in pairs(result) do
		tempTable[v.authid] = {}
		tempTable[v.authid].bid = v.bid
		tempTable[v.authid].sid = tonumber(v.sid) > 0 and v.sid or "Web"
		tempTable[v.authid].admin = v.admin
		tempTable[v.authid].adminid = v.aid
		tempTable[v.authid].name = v.name
		tempTable[v.authid].reason = v.reason
		tempTable[v.authid].steamID = v.authid
		tempTable[v.authid].time = v.created
		tempTable[v.authid].unban = v.created == v.ends and 0 or v.ends
	end
	SBanTable = tempTable
end

function SBAN_RetrieveBans()
	local qTab = {}
	qTab.cb = function(result, qTab) UpdateBanList(result, qTab) end
	if !banRetrieveLimit or type(banRetrieveLimit) != number then
		banRetrieveLimit = 150
	end
	SBAN_SQL_Query("SELECT a.user as admin, b.aid, b.bid, b.sid, b.name, b.reason, b.authid, b.created, b.ends FROM " ..SBAN_PREFIX.. "bans b INNER JOIN " ..SBAN_PREFIX.. "admins a ON b.aid = a.aid WHERE b.RemoveType is null ORDER BY b.created DESC LIMIT "..banRetrieveLimit, qTab)
end
hook.Add("InitPostEntity", "LoadSbans", SBAN_RetrieveBans)

timer.Create("UpdateBanListPls", banListRefreshTime, 0, SBAN_RetrieveBans)

-- ############### Admin Check Section #############
-- #################################################

local function CheckAdmin(result, qTab, lev)
	local ply = qTab.ply
	local steamid = qTab.steamid
	local aid = qTab.aid
	
	qTab.cb = nil
	
	if !lev then -- Initial call
	
		if #result == 1 then
			ply.sb_aid = result[1].aid
			qTab.aid = result[1].aid
			-- This should return the same Admin ID if they are specifically an admin on this server. (not in a group)

			qTab.cb = function(result, qTab) CheckAdmin(result, qTab, "checkadmingroup") end
			SBAN_SQL_Query("SELECT admin_id FROM "..SBAN_PREFIX.."admins_servers_groups WHERE admin_id="..result[1].aid.." AND srv_group_id=-1 AND server_id="..SBAN_SERVERID, qTab)
		else
			-- Remove them if they don't exist at all
			RemoveAdmin(ply)
			return
		end
		
	elseif lev == "checkadmingroup" then
	
		if #result >= 1 then --Admin has permissions for this specific server, finding admin group to add.
			qTab.cb = function(result, qTab) CheckAdmin(result, qTab, "addtogroup") end
			SBAN_SQL_Query("SELECT srv_group FROM "..SBAN_PREFIX.."admins WHERE authid = '" ..steamid.. "'", qTab)
			return
		else
			-- Admin not in this server specifically, checking server group
			qTab.cb = function(result, qTab) CheckAdmin(result, qTab, "servergroupmatch") end
			local qS = [[
			SELECT * FROM %sservers_groups sg 
			WHERE sg.server_id = %s 
			AND (
					SELECT asg.srv_group_id FROM %sadmins_servers_groups asg WHERE admin_id = %s and asg.srv_group_id = sg.group_id
					) >= 1;
			]]
			local servermatchq = string.format(qS, SBAN_PREFIX, SBAN_SERVERID, SBAN_PREFIX, aid)
			SBAN_SQL_Query(servermatchq, qTab)
			return
		end
		
	elseif lev == "addtogroup" then
	
		local group = result[1].srv_group
		if group != nil and string.len(group) > 0 then
			--check if already exists on server
			if(ULib.ucl.getUserRegisteredID(ply) == nil || ply:GetUserGroup() != group) then
				ulx.adduserid(ply, steamid, group)
			end
			return
		else
			RemoveAdmin(ply)
			return
		end
		
	elseif lev == "servergroupmatch" then
		
		if #result >= 1 then
			qTab.cb = function(result, qTab) CheckAdmin(result, qTab, "addtogroup") end
			SBAN_SQL_Query("SELECT srv_group FROM "..SBAN_PREFIX.."admins WHERE authid = '" ..steamid.. "'", qTab)
			return
		else
			RemoveAdmin(ply)
			return
		end

	end
	
end

-- Start of admin checks
local function StartAdminCheck(ply, steamid)
	local qTab = {}
	qTab.ply = ply
	qTab.steamid = steamid
	qTab.cb = function(result, qTab) CheckAdmin(result, qTab) end

	SBAN_SQL_Query("SELECT aid FROM "..SBAN_PREFIX.."admins WHERE authid = '" ..steamid.. "'", qTab)
end

-- ############### Ban Checks #####################
-- ################################################

local function DetermineBanned(result, qTab)

	local ply = qTab.ply
	local steamid = qTab.steamid
	
	if #result > 0 then
		
		for k,v in pairs(result) do
		
			if (v.length == 0) and (v.RemoveType != "U") then
				StillBanned(ply, v.bid, v.reason)
				return
			elseif (v.length != 0) and (v.ends > os.time()) and (v.RemoveType != "U") then
				StillBanned(ply, v.bid, v.reason)
				return
			end
			
		end

		ply.BanCount = #result

		local banPlural = (ply.BanCount > 1) and "bans" or "ban"
		local banText = ""
		if ply.familyshared then
			banText = string.format("%s's lender (%s) has %s %s on record.", ply:Nick(), steamid, ply.BanCount, banPlural)
		else
			banText = string.format("%s (%s) has %s %s on record.", ply:Nick(), steamid, ply.BanCount, banPlural)
		end
			
		if announceBanCount then
		
			timer.Create("BanCount"..steamid, 10, 1, function()
				if !IsValid(ply) then return end
				for k,v in pairs(player.GetAll()) do
					if adminTable[v:GetUserGroup()] then
						v:ChatPrint(banText)
					end
				end
			end)
			
		end
		
	end
	
	if ply.familyshared then return end
	StartAdminCheck(ply, steamid)
end

local function StartBanCheck(ply, steamid)
	local qTab = {}
	qTab.ply = ply
	qTab.steamid = steamid
	qTab.cb = function(result, qTab) DetermineBanned(result, qTab) end
	
	SBAN_SQL_Query("SELECT bid, authid, ends, length, reason, RemoveType FROM "..SBAN_PREFIX.."bans WHERE authid = '" ..steamid.. "'", qTab)
end

-- ############### Family Sharing #################
-- ################################################

local function AnnounceLender(ply,lender)
	if !IsValid(ply) or !announceLender then return end
	
	timer.Create("FSAnnounce"..ply:SteamID(),10,1, function()
		if !IsValid(ply) then return end
		for k,v in pairs(player.GetAll()) do
			if adminTable[v:GetUserGroup()] then
				v:ChatPrint(string.format("[Family Sharing] %s (%s) has been lent Garry's Mod by %s", ply:Nick(), ply:SteamID(), lender))
			end
		end
	end)
	
end

local function HandleSharedPlayer(ply, lenderSteamID)
	
	apiErrorCount = (apiErrorCount > 1) and (apiErrorCount - 1) or 0
	if !IsValid(ply) then return end

	AnnounceLender(ply,lenderSteamID)
	
	ply.familyshared = true
	ply.lenderid = lenderSteamID
    StartBanCheck(ply, lenderSteamID)
	
end

local function CheckFamilySharing(ply)
	apiLastCheck = apiLastCheck or 0
	if !IsValid(ply) or apiErrorCount > 100 then return end
	if (CurTime() - apiLastCheck <= 1) or CurTime() < 12 then
		
		local checkDelay = math.Rand(2,25)
		
		timer.Create("FSCheck_"..ply:SteamID(),checkDelay,1, function()
			if !IsValid(ply) then return end
			CheckFamilySharing(ply)
		end)
		
		return
	end
	apiLastCheck = CurTime()
    http.Fetch(
        string.format("http://api.steampowered.com/IPlayerService/IsPlayingSharedGame/v0001/?key=%s&format=json&steamid=%s&appid_playing=4000",
            APIKey,
            ply:SteamID64()
        ),
        
        function(body)
			if !IsValid(ply) then return end
            body = util.JSONToTable(body)

            if not body or not body.response or not body.response.lender_steamid then
                ErrorNoHalt(string.format("[SBAN] FamilySharing: Invalid Steam API response for %s | %s\n", ply:Nick(), ply:SteamID()))
				apiErrorCount = apiErrorCount + 2
				CheckFamilySharing(ply)
				return
            end

            local lender = body.response.lender_steamid
            if lender ~= "0" then
				if !IsValid(ply) then return end
				local lenderSteamID = util.SteamIDFrom64(lender)
				HandleSharedPlayer(ply, lenderSteamID)

            end
        end,
        
        function(code)
			if !IsValid(ply) then return end
			ErrorNoHalt(string.format("[SBAN] FamilySharing: Failed API call for %s | %s (Error: %s)\n", ply:Nick(), ply:SteamID(), code))
			apiErrorCount = apiErrorCount + 2
			CheckFamilySharing(ply)
        end
    )

end

local function SBAN_rehash( ply,cmd,args,str )
	if IsValid(ply) then return end
	for k,v in pairs(player.GetAll()) do
		StartAdminCheck(v, v:SteamID())
	end
end
concommand.Add( "sm_rehash", SBAN_rehash)
concommand.Add( "sban_rehash", SBAN_rehash)

local function SBAN_serverid_cmd( ply,cmd,args,str )
	if IsValid(ply) then return end
	print("[SBAN] ServerID: "..SBAN_SERVERID)
end
concommand.Add( "sban_serverid", SBAN_serverid_cmd)

local function SBAN_playerconnect(ply, steamid)
	StartBanCheck(ply, steamid)
	if checkSharing then CheckFamilySharing(ply) end
end
hook.Add( "PlayerAuthed", "sban_ulx", SBAN_playerconnect)