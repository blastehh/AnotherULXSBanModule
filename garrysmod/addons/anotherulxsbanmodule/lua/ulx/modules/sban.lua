--[[
--		Another ULX Source Bans Module 3.10
--
--		CREDITS:
--		This sban module was based on a very old version of ULX Source Bans Module by FunDK http://facepunch.com/showthread.php?t=1311847
--		It has been re-written a few times, but still has some bits of old stuff from the original.
-- 		The family sharing code is from McSimp on facepunch http://facepunch.com/showthread.php?t=1341204&p=43469693&viewfull=1#post43469693
--		The XGUI part of this module is the default ulx bans page modified to work with sbans. https://github.com/Nayruden/Ulysses/tree/master/ulx
--
--		INSTRUCTIONS:
--		This module requires tmysql4! Get it here https://facepunch.com/showthread.php?t=1442438
--		Edit the config section below to your liking, make sure you add ulx_sban_serverid to your server.cfg
--		You can find the correct number to use from the sourcebans website, if you only have one server, it will usually be 1
--		There will be an additional permission you can assign in ulx called xgui_manageunbans, this will let your admins see the sourcebans tab.
--		The tab will currently only show ACTIVE bans.
--
--		Config files will be created after the first run at garrysmod/data/sban
--		Config settings in this file will be ignored once the config files have been created after the first run.
--]]

-- Config section
-- Add ulx_sban_serverid to your server.cfg

local SBAN_PREFIX			= "sb_"					--Prefix don't change if you don't know what you are doing
local SBAN_WEBSITE			= "sourceban.domain.com"	--Source Bans Website

local SBANDATABASE_HOSTNAME	= "localhost"			-- Database IP/Host
local SBANDATABASE_HOSTPORT	= 3306					--Database Port (Default mysql port 3306)
local SBANDATABASE_DATABASE	= "sourceban"			--Database Database/Schema
local SBANDATABASE_USERNAME	= "user"			--Database Username
local SBANDATABASE_PASSWORD	= "pass"	--Database Password

local APIKey				= "1234567890" -- See http://steamcommunity.com/dev/apikey
local removeFromGroup		= true			-- Remove users from server groups if they don't exist in the sourcebans database
local checkSharing			= true			-- Check if players are borrowing the game, !!!! THIS REQUIRES AN API KEY !!!!!
local checkIP				= false			-- Check ban database using IP.
local banLender				= true			-- Ban the lender of the game as well if the player gets banned?
local announceBanCount		= true			-- Announce to admins if players have bans on record.
local announceLender		= true			-- Announce to admins if players are borrowing gmod.
local banRetrieveLimit		= 150			-- Amount of bans to retrieve in XGUI.
local banListRefreshTime	= 119			-- Seconds between refreshing the banlist in XGUI, in case the bans change from outside of the server.
local tttKarmaBan			= false			-- Enable support for TTT karma bans.
ulxBanOverride				= false			-- Override the default ulx ban to use sban.

-- Table of groups who will get sharing/ban count notifications when players join.
-- Follow the format below to add more groups, make sure to add a comma if it isn't the last entry.
local adminTable = {
	["superadmin"] = true,
	["admin"] = true,
}


-- This table excludes named groups from being removed, even if the option is turned on.
-- Format is the same as the admin table above.
local excludedGroups = {
	["vip"] = true,
}
if !file.Exists("sban", "DATA") then
	file.CreateDir("sban")
end
local configTable
if !file.Exists("sban/config.txt", "DATA") then
	configTable = {}
	configTable.SBAN_PREFIX = SBAN_PREFIX
	configTable.SBAN_WEBSITE = SBAN_WEBSITE
	configTable.SBANDATABASE_HOSTNAME = SBANDATABASE_HOSTNAME
	configTable.SBANDATABASE_HOSTPORT = SBANDATABASE_HOSTPORT
	configTable.SBANDATABASE_DATABASE = SBANDATABASE_DATABASE
	configTable.SBANDATABASE_USERNAME = SBANDATABASE_USERNAME
	configTable.SBANDATABASE_PASSWORD = SBANDATABASE_PASSWORD
	configTable.APIKey = APIKey
	configTable.removeFromGroup = removeFromGroup and "yes" or "no"
	configTable.checkSharing = checkSharing and "yes" or "no"
	configTable.checkIP = checkIP and "yes" or "no"
	configTable.banLender = banLender and "yes" or "no"
	configTable.announceBanCount = announceBanCount and "yes" or "no"
	configTable.announceLender = announceLender and "yes" or "no"
	configTable.banRetrieveLimit = banRetrieveLimit
	configTable.banListRefreshTime = banListRefreshTime
	configTable.tttKarmaBan = tttKarmaBan and "yes" or "no"
	configTable.ulxBanOverride = ulxBanOverride and "yes" or "no"
	file.Write("sban/config.txt", util.TableToKeyValues(configTable))
else
	configTable = util.KeyValuesToTable(file.Read("sban/config.txt", "DATA"))

	SBAN_PREFIX = configTable.sban_prefix
	SBAN_WEBSITE = configTable.sban_website
	SBANDATABASE_HOSTNAME = configTable.sbandatabase_hostname
	SBANDATABASE_HOSTPORT = tonumber(configTable.sbandatabase_hostport)
	SBANDATABASE_DATABASE = configTable.sbandatabase_database
	SBANDATABASE_USERNAME = configTable.sbandatabase_username
	SBANDATABASE_PASSWORD = configTable.sbandatabase_password
	APIKey = configTable.apikey
	removeFromGroup = configTable.removefromgroup == "yes"
	checkSharing = configTable.checksharing == "yes"
	banLender = configTable.banlender == "yes"
	announceBanCount = configTable.announcebancount == "yes"
	announceLender = configTable.announcelender == "yes"
	banRetrieveLimit = tonumber(configTable.banretrievelimit)
	banListRefreshTime = tonumber(configTable.banlistrefreshtime)
	tttKarmaBan = configTable.tttkarmaban == "yes"
	ulxBanOverride = configTable.ulxbanoverride == "yes"
end

if !file.Exists("sban/admingroups.txt", "DATA") then
	file.Write("sban/admingroups.txt", util.TableToJSON(adminTable))
else
	adminTable = util.JSONToTable( file.Read("sban/admingroups.txt", "DATA"))
end

if !file.Exists("sban/excludedgroups.txt", "DATA") then
	file.Write("sban/excludedgroups.txt", util.TableToJSON(excludedGroups))
else
	excludedGroups = util.JSONToTable( file.Read("sban/excludedgroups.txt", "DATA"))
end

require("pmysql1")
-- Don't touch these
local database_sban = pmysql1.connect( SBANDATABASE_HOSTNAME, SBANDATABASE_USERNAME, SBANDATABASE_PASSWORD, SBANDATABASE_DATABASE, SBANDATABASE_HOSTPORT )
CreateConVar("ulx_sban_serverid", "-1", FCVAR_NONE, "Sets the SBAN ServerID for the Source Bans ULX module")
local apiErrorCount = 0
local apiLastCheck = 0
SBanTable = SBanTable or {}
local ipCache = {}

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

-- ############### Main Database Query Function ################
-- #############################################################
local function SBAN_SQL_Query_Callback(results, qTab)
	qTab.cb(results, qTab)
end

local function SBAN_SQL_Query(sql, qTab)
	local qTab = qTab or {}
	qTab.query = sql
	if qTab.wait then
		return function(sql)
			local results = database_sban:query_sync(sql)
			return results[1].data
		end
	elseif qTab.cb then
		database_sban:query(sql, SBAN_SQL_Query_Callback, qTab)
		
	else
		database_sban:query(sql)
	end
end

-- ############### Local Helper functions ###############
-- ######################################################

local function RemoveAdmin(ply)
	if(ULib.ucl.getUserRegisteredID(ply) != nil) and removeFromGroup and !excludedGroups[ply:GetUserGroup()] then
		ulx.removeuserid(ply, ply:SteamID())
	end
end

local function DoKick(ply, reason)
	--if !IsValid(ply) then return end
	local steamID
	if type(ply) == "string" then
		steamID = ply
	elseif IsValid(ply) and ply:IsPlayer() then
		steamID = ply:SteamID()
	else
		return
	end
	
	if(reason == nil) then
		game.KickID( steamID, "You have been banned from this server, please visit "..SBAN_WEBSITE)
	else
		game.KickID( steamID, "You have been banned from this server ("..reason.."), please visit "..SBAN_WEBSITE)
	end
end

local function ReportBlock(bid, name)
	local ostime = os.time();
	local qTab = {}
	qTab.wait = false
	local query = "INSERT INTO "..database_sban:escape(SBAN_PREFIX).."banlog (sid, time, name, bid)"
	query = query.." VALUES ("..database_sban:escape(SBAN_SERVERID)..", "..database_sban:escape(ostime)..", '"..database_sban:escape(name).."', "..database_sban:escape(bid)..");"
	
	SBAN_SQL_Query(query, qTab)
end

local function StillBanned(ply, bid, reason, preSpawn)
	if (!preSpawn and !IsValid(ply)) then return end
	
	local name
	local steamID
	
	if preSpawn then
		name = ply.name
		steamID = ply.steamID
	else
		name = ply:Nick()
		steamID = ply:SteamID()
	end
	
	ReportBlock(bid, name)
	DoKick(steamID, reason)
end

ULib.ucl.registerAccess( "ulx unsbanall", ULib.ACCESS_SUPERADMIN, "Ability to unban all sban entries", "Other" ) -- Permission for admins to unban players banned by other admins.
ULib.ucl.registerAccess( "ulx editsbanall", ULib.ACCESS_SUPERADMIN, "Ability to edit all sban entries", "Other" ) -- Permission for admins to edit bans made by other admins.

-- ############### Global Helper functions ##############
-- ######################################################

function SBAN_doban(inip, steamID, name, length, reason, callingAdmin, lenderID)
	local adminID = 0
	if type(callingAdmin) == "number" then
		adminID = callingAdmin
	elseif callingAdmin:IsPlayer() and type(callingAdmin.sb_aid) == "number" then
		adminID = callingAdmin.sb_aid
	end

	local ip = database_sban:escape(string.Explode(":", inip)[1])
	steamID = database_sban:escape(steamID)
	name = database_sban:escape(name)
	length = database_sban:escape(length)
	reason = database_sban:escape(reason)
	adminID = database_sban:escape(adminID)
	local qTab = {}
	qTab.wait = false
	
	local time = os.time()
	
	local query = "INSERT INTO "..database_sban:escape(SBAN_PREFIX).."bans (ip, authid, name, created, ends, length, reason, aid, sid) "
	query = query.." VALUES ('"..ip.."', '"..steamID.."', '"..name.."',"..time..", "..(time + length)..", "..length..", '"..reason.."', "..adminID..", "..database_sban:escape(SBAN_SERVERID)..");"
	SBAN_SQL_Query(query, qTab)
	
	if lenderID and banLender then
		lenderID = database_sban:escape(lenderID)
		local query2 = "INSERT INTO "..database_sban:escape(SBAN_PREFIX).."bans (ip, authid, name, created, ends, length, reason, aid, sid) "
		query2 = query2.."VALUES ('"..ip.."', '"..lenderID.."', '"..name.."',"..time..", "..(time + length)..", "..length..", '"..reason.."', "..adminID..", "..database_sban:escape(SBAN_SERVERID)..");"
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
	local steamID = ply:SteamID()
	local name = ply:Nick()

	SBAN_doban(ip, steamID, name, length, reason, callingadmin ,lenderid)
	DoKick(steamID, reason)
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
	local query = SBAN_SQL_Query("SELECT aid FROM "..database_sban:escape(SBAN_PREFIX).."admins WHERE authid = '" ..database_sban:escape(steamid).. "'", qTab)
	return query[1].aid
end

function SBAN_unban(steamid, ply, ureason)
	local adminID = database_sban:escape(ply.sb_aid or 0)
	local qTab = {}
	qTab.wait = false
	SBAN_SQL_Query("UPDATE "..database_sban:escape(SBAN_PREFIX).."bans SET RemovedOn = "..os.time()..", RemovedBy = "..adminID..", RemoveType = 'U', ureason = '"..database_sban:escape(ureason).."' WHERE authid = '"..database_sban:escape(steamid).."' and RemoveType is null", qTab)
	XGUIRefreshBans()
end

function SBAN_canunban(steamid, ply)
	local adminID = ply.sb_aid or 0
	
	local query = "SELECT * FROM "..database_sban:escape(SBAN_PREFIX).."bans WHERE authid = '"..database_sban:escape(steamid).."' and RemoveType is null"
	if !ULib.ucl.query( ply, "ulx unsbanall" ) then
		query = query .. " and aid = "..database_sban:escape(adminID)
	end
	local qTab = {}
	qTab.wait = true
	
	return #SBAN_SQL_Query(query, qTab) > 0
end

function SBAN_updateban(steamID, ply, bantime, reason, name)
	local updateName = "[Unknown]"
	if name and string.len(name) > 0 then
		updateName = name
	end
	
	bantime = database_sban:escape(bantime)
	updateName = database_sban:escape(updateName)
	reason = database_sban:escape(reason)
	steamID = database_sban:escape(steamID)
	
	local qTab = {}
	qTab.wait = false
	local query = "UPDATE "..database_sban:escape(SBAN_PREFIX).."bans SET ends = created + "..bantime
	query = query .. ", length = "..bantime..", name = '"..updateName.."', reason = '"..reason.."' WHERE authid = '"..steamID.."' and RemoveType is null"
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
	banRetrieveLimit = database_sban:escape(banRetrieveLimit)
	SBAN_SQL_Query("SELECT a.user as admin, b.aid, b.bid, b.sid, b.name, b.reason, b.authid, b.created, b.ends FROM " ..database_sban:escape(SBAN_PREFIX).. "bans b INNER JOIN " ..database_sban:escape(SBAN_PREFIX).. "admins a ON b.aid = a.aid WHERE b.RemoveType is null ORDER BY b.created DESC LIMIT "..banRetrieveLimit, qTab)
end
hook.Add("InitPostEntity", "LoadSbans", SBAN_RetrieveBans)

timer.Create("UpdateBanListPls", banListRefreshTime, 0, SBAN_RetrieveBans)

-- ############### Admin Check Section #############
-- #################################################

local function CheckAdmin(result, qTab, lev)
	local ply = qTab.ply
	local steamid = database_sban:escape(qTab.steamID)
	local aid = qTab.aid
	
	qTab.cb = nil
	
	if !lev then -- Initial call
	
		if #result == 1 then
			ply.sb_aid = result[1].aid
			qTab.aid = result[1].aid
			-- This should return the same Admin ID if they are specifically an admin on this server. (not in a group)

			qTab.cb = function(result, qTab) CheckAdmin(result, qTab, "checkadmingroup") end
			SBAN_SQL_Query("SELECT admin_id FROM "..database_sban:escape(SBAN_PREFIX).."admins_servers_groups WHERE admin_id="..database_sban:escape(result[1].aid).." AND srv_group_id=-1 AND server_id="..database_sban:escape(SBAN_SERVERID), qTab)
		else
			-- Remove them if they don't exist at all
			RemoveAdmin(ply)
			return
		end
		
	elseif lev == "checkadmingroup" then
	
		if #result >= 1 then --Admin has permissions for this specific server, finding admin group to add.
			qTab.cb = function(result, qTab) CheckAdmin(result, qTab, "addtogroup") end
			SBAN_SQL_Query("SELECT srv_group FROM "..database_sban:escape(SBAN_PREFIX).."admins WHERE authid = '" ..steamid.. "'", qTab)
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
			local servermatchq = string.format(qS, database_sban:escape(SBAN_PREFIX), database_sban:escape(SBAN_SERVERID), database_sban:escape(SBAN_PREFIX), database_sban:escape(aid))
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
			SBAN_SQL_Query("SELECT srv_group FROM "..database_sban:escape(SBAN_PREFIX).."admins WHERE authid = '" ..steamid.. "'", qTab)
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
	qTab.steamID = steamid
	qTab.cb = function(result, qTab) CheckAdmin(result, qTab) end

	SBAN_SQL_Query("SELECT aid FROM "..database_sban:escape(SBAN_PREFIX).."admins WHERE authid = '" ..database_sban:escape(steamid).. "'", qTab)
end

-- ############### Ban Checks #####################
-- ################################################

local function DetermineBanned(result, qTab, preSpawn)
	local ply
	local steamID
	if preSpawn then
		ply = {}
		ply.name = qTab.name
		ply.steamID = qTab.steamID
	else
		ply = qTab.ply
		steamID = qTab.steamID
	end
	
	if #result > 0 then
		
		for k,v in pairs(result) do
		
			if (v.length == 0) and (v.RemoveType != "U") then
				StillBanned(ply, v.bid, v.reason, preSpawn)
				return
			elseif (v.length != 0) and (v.ends > os.time()) and (v.RemoveType != "U") then
				StillBanned(ply, v.bid, v.reason, preSpawn)
				return
			end
			
		end
		
		if preSpawn then return end

		ply.BanCount = #result

		local banPlural = (ply.BanCount > 1) and "bans" or "ban"
		local banText = ""
		if ply.familyshared then
			banText = string.format("%s's lender (%s) has %s %s on record.", ply:Nick(), steamID, ply.BanCount, banPlural)
		else
			banText = string.format("%s (%s) has %s %s on record.", ply:Nick(), steamID, ply.BanCount, banPlural)
		end
	
		if announceBanCount then
		
			timer.Create("BanCount"..steamID, 10, 1, function()
				if !IsValid(ply) then return end
				for k,v in pairs(player.GetAll()) do
					if adminTable[v:GetUserGroup()] then
						v:ChatPrint(banText)
					end
				end
			end)
			
		end
		
	end
	if preSpawn then return end
	if ply.familyshared then return end
	StartAdminCheck(ply, steamID)
end

local function StartBanCheck(ply, steamID)
	local qTab = {}
	qTab.ply = ply
	qTab.steamID = steamID
	qTab.ip = string.Explode(":", ply:IPAddress())[1]
	qTab.cb = function(result, qTab) DetermineBanned(result, qTab) end
	
	SBAN_SQL_Query("SELECT bid, authid, ends, length, reason, RemoveType FROM "..database_sban:escape(SBAN_PREFIX).."bans WHERE authid = '" ..database_sban:escape(steamID).. "'", qTab)
	
	if checkIP and not ipCache[qTab.ip] then
		SBAN_SQL_Query("SELECT bid, authid, ends, length, reason, RemoveType FROM "..database_sban:escape(SBAN_PREFIX).."bans WHERE ip = '" ..database_sban:escape(qTab.ip).. "'", qTab)
		ipCache[qTab.ip] = true
	end
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

local function SBAN_playerconnect(ply, steamID)
	StartBanCheck(ply, steamID)
	if checkSharing then CheckFamilySharing(ply) end
end

local function PW_BanCheck(sid64, ip, svPass, clPass, name)
	local qTab = {}
	qTab.name = name
	qTab.steamID = util.SteamIDFrom64(sid64)
	qTab.ip = string.Explode(":", ip)[1]
	qTab.cb = function(result, qTab) DetermineBanned(result, qTab, true) end
	
	SBAN_SQL_Query("SELECT bid, authid, ends, length, reason, RemoveType FROM "..database_sban:escape(SBAN_PREFIX).."bans WHERE authid = '" ..database_sban:escape(qTab.steamID).. "'", qTab)
	
	if checkIP then
		SBAN_SQL_Query("SELECT bid, authid, ends, length, reason, RemoveType FROM "..database_sban:escape(SBAN_PREFIX).."bans WHERE ip = '" ..database_sban:escape(qTab.ip).. "'", qTab)
		ipCache[qTab.ip] = true
	end
end

hook.Add( "PlayerAuthed", "sban_ulx", SBAN_playerconnect)
hook.Add( "CheckPassword", "sban_ulx_checkpassword", PW_BanCheck)

hook.Add("TTTKarmaLow", "KarmaSourceBan", function(ply)
	if tttKarmaBan and KARMA and KARMA.cv.enabled:GetBool() and KARMA.cv.autoban:GetBool() then
		SBAN_doban(ply:IPAddress(),ply:SteamID(), ply:Nick(), KARMA.cv.bantime:GetInt() * 60, "Karma too low", 0, ply.lenderid)
	end
end)
