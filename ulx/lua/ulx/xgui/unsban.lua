xgui.prepareDataType( "unbans" )

local xunbans = xlib.makepanel{ parent=xgui.null }

xunbans.banlist = xlib.makelistview{ x=5, y=30, w=572, h=310, multiselect=false, parent=xunbans }
	xunbans.banlist:AddColumn( "Name/SteamID" )
	xunbans.banlist:AddColumn( "Banned By" )
	xunbans.banlist:AddColumn( "Unban Date" )
	xunbans.banlist:AddColumn( "Reason" )
xunbans.banlist.DoDoubleClick = function( self, LineID, line )
	xunbans.ShowBanDetailsWindow( xgui.data.unbans.cache[LineID] )
end
xunbans.banlist.OnRowRightClick = function( self, LineID, line )
	local menu = DermaMenu()
	menu:SetSkin(xgui.settings.skin)
	menu:AddOption( "Details...", function() xunbans.ShowBanDetailsWindow( xgui.data.unbans.cache[LineID] ) end )
	menu:AddOption( "Edit Ban...", function() xgui.ShowSBanWindow( nil, line:GetValue( 5 ), nil, true, xgui.data.unbans.cache[LineID] ) end )
	menu:AddOption( "Unban...", function() xunbans.RemoveBan( line:GetValue( 5 ), xgui.data.unbans.cache[LineID] ) end )
	menu:Open()
end
-- Change the column sorting method to hook into our own custom sort stuff.
xunbans.banlist.SortByColumn = function( self, ColumnID, Desc )
	local index =	ColumnID == 1 and 2 or	-- Sort by Name
					ColumnID == 2 and 4 or	-- Sort by Admin
					ColumnID == 3 and 6 or	-- Sort by Unban Date
					ColumnID == 4 and 5 or	-- Sort by Reason
									  1		-- Otherwise sort by Date
	xunbans.sortbox:ChooseOptionID( index )
end

local searchFilter = ""
xunbans.searchbox = xlib.maketextbox{ x=5, y=6, w=175, text="Search...", selectall=true, parent=xunbans }
local txtCol = xunbans.searchbox:GetTextColor()
xunbans.searchbox:SetTextColor( Color( txtCol.r, txtCol.g, txtCol.b, 196 ) ) -- Set initial color
xunbans.searchbox.OnChange = function( pnl )
	if pnl:GetText() == "" then
		pnl:SetText( "Search..." )
		pnl:SelectAll()
		pnl:SetTextColor( Color( txtCol.r, txtCol.g, txtCol.b, 196 ) )
	else
		pnl:SetTextColor( Color( txtCol.r, txtCol.g, txtCol.b, 255 ) )
	end
end
xunbans.searchbox.OnLoseFocus = function( pnl )
	if pnl:GetText() == "Search..." then
		searchFilter = ""
	else
		searchFilter = pnl:GetText()
	end
	xunbans.setPage( 1 )
	xunbans.retrieveBans()
	hook.Call( "OnTextEntryLoseFocus", nil, pnl )
end

local sortMode = 0
local sortAsc = false
xunbans.sortbox = xlib.makecombobox{ x=185, y=6, w=150, text="Sort: Date (Desc.)", choices={ "Date", "Name", "Steam ID", "Admin", "Reason", "Unban Date", "Ban Length" }, parent=xunbans }
function xunbans.sortbox:OnSelect( i, v )
	if i-1 == sortMode then
		sortAsc = not sortAsc
	else
		sortMode = i-1
		sortAsc = false
	end
	self:SetValue( "Sort: " .. v .. (sortAsc and " (Asc.)" or " (Desc.)") )
	xunbans.setPage( 1 )
	xunbans.retrieveBans()
end

local hidePerma = 0
xlib.makebutton{ x=355, y=6, w=95, label="Permabans: Show", parent=xunbans }.DoClick = function( self )
	hidePerma = hidePerma + 1
	if hidePerma == 1 then
		self:SetText( "Permabans: Hide" )
	elseif hidePerma == 2 then
		self:SetText( "Permabans: Only" )
	elseif hidePerma == 3 then
		hidePerma = 0
		self:SetText( "Permabans: Show" )
	end
	xunbans.setPage( 1 )
	xunbans.retrieveBans()
end

local hideIncomplete = 0
xlib.makebutton{ x=455, y=6, w=95, label="Incomplete: Show", parent=xunbans, tooltip="Filters bans that are loaded by ULib, but do not have any metadata associated with them." }.DoClick = function( self )
	hideIncomplete = hideIncomplete + 1
	if hideIncomplete == 1 then
		self:SetText( "Incomplete: Hide" )
	elseif hideIncomplete == 2 then
		self:SetText( "Incomplete: Only" )
	elseif hideIncomplete == 3 then
		hideIncomplete = 0
		self:SetText( "Incomplete: Show" )
	end
	xunbans.setPage( 1 )
	xunbans.retrieveBans()
end


local function banUserList( doFreeze )
	local menu = DermaMenu()
	menu:SetSkin(xgui.settings.skin)
	for k, v in ipairs( player.GetAll() ) do
		menu:AddOption( v:Nick(), function() xgui.ShowSBanWindow( v, v:SteamID(), doFreeze ) end )
	end
	menu:AddSpacer()
	if LocalPlayer():query("ulx sbanid") then menu:AddOption( "Ban by STEAMID...", function() xgui.ShowSBanWindow() end ) end
	menu:Open()
end

xlib.makebutton{ x=5, y=340, w=70, label="Ban...", parent=xunbans }.DoClick = function() banUserList( false ) end
xunbans.btnFreezeBan = xlib.makebutton{ x=80, y=340, w=95, label="Freeze Ban...", parent=xunbans }
xunbans.btnFreezeBan.DoClick = function() banUserList( true ) end

xunbans.infoLabel = xlib.makelabel{ x=204, y=344, label="Right-click on a ban for more options", parent=xunbans }


xunbans.resultCount = xlib.makelabel{ y=344, parent=xunbans }
function xunbans.setResultCount( count )
	local pnl = xunbans.resultCount
	pnl:SetText( count .. " results" )
	pnl:SizeToContents()

	local width = pnl:GetWide()
	local x, y = pnl:GetPos()
	pnl:SetPos( 475 - width, y )
	
	local ix, iy = xunbans.infoLabel:GetPos()
	xunbans.infoLabel:SetPos( ( 130 - width ) / 2 + 175, y )
end

local numPages = 1
local pageNumber = 1
xunbans.pgleft = xlib.makebutton{ x=480, y=340, w=20, icon="icon16/arrow_left.png", centericon=true, disabled=true, parent=xunbans }
xunbans.pgleft.DoClick = function()
	xunbans.setPage( pageNumber - 1 )
	xunbans.retrieveBans()
end
xunbans.pageSelector = xlib.makecombobox{ x=500, y=340, w=57, text="1", enableinput=true, parent=xunbans }
function xunbans.pageSelector:OnSelect( index )
	xunbans.setPage( index )
	xunbans.retrieveBans()
end
function xunbans.pageSelector.TextEntry:OnEnter()
	pg = math.Clamp( tonumber( self:GetValue() ) or 1, 1, numPages )
	xunbans.setPage( pg )
	xunbans.retrieveBans()
end
xunbans.pgright = xlib.makebutton{ x=557, y=340, w=20, icon="icon16/arrow_right.png", centericon=true, disabled=true, parent=xunbans }
xunbans.pgright.DoClick = function()
	xunbans.setPage( pageNumber + 1 )
	xunbans.retrieveBans()
end

xunbans.setPage = function( newPage )
	pageNumber = newPage
	xunbans.pgleft:SetDisabled( pageNumber <= 1 )
	xunbans.pgright:SetDisabled( pageNumber >= numPages )
	xunbans.pageSelector.TextEntry:SetText( pageNumber )
end


function xunbans.RemoveBan( ID, bandata )
	local tempstr = "<Unknown>"
	if bandata then tempstr = bandata.name or "<Unknown>" end
	Derma_Query( "Are you sure you would like to unban " .. tempstr .. " - " .. ID .. "?", "XGUI WARNING", 
		"Unban...",	function()
						Derma_StringRequest("Unban Reason?", "Please specify the unban reason.", "", function(text) 
							RunConsoleCommand( "ulx", "unsban", ID, text ) 
							xunbans.RemoveBanDetailsWindow( ID )
						end,
						function() end)
						
					end,
		"Cancel", 	function() end )
end

xunbans.openWindows = {}
function xunbans.RemoveBanDetailsWindow( ID )
	if xunbans.openWindows[ID] then
		xunbans.openWindows[ID]:Remove()
		xunbans.openWindows[ID] = nil
	end
end

function xunbans.ShowBanDetailsWindow( bandata )
	local wx, wy
	if xunbans.openWindows[bandata.steamID] then
		wx, wy = xunbans.openWindows[bandata.steamID]:GetPos()
		xunbans.openWindows[bandata.steamID]:Remove()
	end
	xunbans.openWindows[bandata.steamID] = xlib.makeframe{ label="Ban Details", x=wx, y=wy, w=285, h=315, skin=xgui.settings.skin }

	local panel = xunbans.openWindows[bandata.steamID]
	local name = xlib.makelabel{ x=50, y=30, label="Name:", parent=panel }
	xlib.makelabel{ x=90, y=30, w=190, label=( bandata.name or "<Unknown>" ), parent=panel, tooltip=bandata.name }
	xlib.makelabel{ x=36, y=50, label="SteamID:", parent=panel }
	xlib.makelabel{ x=90, y=50, label=bandata.steamID, parent=panel }
	xlib.makelabel{ x=33, y=70, label="Ban Date:", parent=panel }
	xlib.makelabel{ x=90, y=70, label=bandata.time and ( os.date( "%b %d, %Y - %I:%M:%S %p", tonumber( bandata.time ) ) ) or "<This ban has no metadata>", parent=panel }
	xlib.makelabel{ x=20, y=90, label="Unban Date:", parent=panel }
	xlib.makelabel{ x=90, y=90, label=( tonumber( bandata.unban ) == 0 and "Never" or os.date( "%b %d, %Y - %I:%M:%S %p", math.min(  tonumber( bandata.unban ), 4294967295 ) ) ), parent=panel }
	xlib.makelabel{ x=10, y=110, label="Length of Ban:", parent=panel }
	xlib.makelabel{ x=90, y=110, label=( tonumber( bandata.unban ) == 0 and "Permanent" or xgui.ConvertTime( tonumber( bandata.unban ) - bandata.time ) ), parent=panel }
	xlib.makelabel{ x=33, y=130, label="Time Left:", parent=panel }
	local timeleft = xlib.makelabel{ x=90, y=130, label=( tonumber( bandata.unban ) == 0 and "N/A" or xgui.ConvertTime( tonumber( bandata.unban ) - os.time() ) ), parent=panel }
	xlib.makelabel{ x=26, y=150, label="Banned By:", parent=panel }
	if bandata.admin then xlib.makelabel{ x=90, y=150, label=string.gsub( bandata.admin, "%(STEAM_%w:%w:%w*%)", "" ), parent=panel } end
	if bandata.admin then xlib.makelabel{ x=90, y=165, label=string.match( bandata.admin, "%(STEAM_%w:%w:%w*%)" ), parent=panel } end
	xlib.makelabel{ x=44, y=185, label="Server:", parent=panel }
	xlib.makelabel{ x=90, y=185, label=bandata.sid, parent=panel }
	xlib.makelabel{ x=41, y=205, label="Reason:", parent=panel }
	xlib.makelabel{ x=90, y=205, w=190, label=bandata.reason, parent=panel, tooltip=bandata.reason ~= "" and bandata.reason or nil }
	xlib.makelabel{ x=13, y=225, label="Last Updated:", parent=panel }
	xlib.makelabel{ x=90, y=225, label=( ( bandata.modified_time == nil ) and "Never" or os.date( "%b %d, %Y - %I:%M:%S %p", tonumber( bandata.modified_time ) ) ), parent=panel }
	xlib.makelabel{ x=21, y=245, label="Updated by:", parent=panel }
	if bandata.modified_admin then xlib.makelabel{ x=90, y=245, label=string.gsub( bandata.modified_admin, "%(STEAM_%w:%w:%w*%)", "" ), parent=panel } end
	if bandata.modified_admin then xlib.makelabel{ x=90, y=260, label=string.match( bandata.modified_admin, "%(STEAM_%w:%w:%w*%)" ), parent=panel } end

	panel.data = bandata	-- Store data on panel for future reference.
	xlib.makebutton{ x=5, y=285, w=89, label="Edit Ban...", parent=panel }.DoClick = function()
		xgui.ShowSBanWindow( nil, panel.data.steamID, nil, true, panel.data )
	end

	xlib.makebutton{ x=99, y=285, w=89, label="Unban", parent=panel }.DoClick = function()
		xunbans.RemoveBan( panel.data.steamID, panel.data )
	end

	xlib.makebutton{ x=192, y=285, w=88, label="Close", parent=panel }.DoClick = function()
		xunbans.RemoveBanDetailsWindow( panel.data.steamID )
	end

	panel.btnClose.DoClick = function ( button )
		xunbans.RemoveBanDetailsWindow( panel.data.steamID )
	end

	if timeleft:GetValue() ~= "N/A" then
		function panel.OnTimer()
			if panel:IsVisible() then
				local bantime = tonumber( panel.data.unban ) - os.time()
				if bantime <= 0 then
					xunbans.RemoveBanDetailsWindow( panel.data.steamID )
					return
				else
					timeleft:SetText( xgui.ConvertTime( bantime ) )
				end
				timeleft:SizeToContents()
				timer.Simple( 1, panel.OnTimer )
			end
		end
		panel.OnTimer()
	end
end

function xgui.ShowSBanWindow( ply, ID, doFreeze, isUpdate, bandata )
	if not LocalPlayer():query( "ulx sban" ) and not LocalPlayer():query( "ulx sbanid" ) then return end

	local xgui_banwindow = xlib.makeframe{ label=( isUpdate and "Edit Ban" or "Ban Player" ), w=285, h=180, skin=xgui.settings.skin }
	xlib.makelabel{ x=37, y=33, label="Name:", parent=xgui_banwindow }
	xlib.makelabel{ x=23, y=58, label="SteamID:", parent=xgui_banwindow }
	xlib.makelabel{ x=28, y=83, label="Reason:", parent=xgui_banwindow }
	xlib.makelabel{ x=10, y=108, label="Ban Length:", parent=xgui_banwindow }
	local reason = xlib.makecombobox{ x=75, y=80, w=200, parent=xgui_banwindow, enableinput=true, selectall=true, choices=ULib.cmds.translatedCmds["ulx sban"].args[4].completes }
	local banpanel = ULib.cmds.NumArg.x_getcontrol( ULib.cmds.translatedCmds["ulx sban"].args[3], 2 )
	banpanel:SetParent( xgui_banwindow )
	banpanel.interval:SetParent( xgui_banwindow )
	banpanel.interval:SetPos( 200, 105 )
	banpanel.val:SetParent( xgui_banwindow )
	banpanel.val:SetPos( 75, 125 )
	banpanel.val:SetWidth( 200 )

	local name
	if not isUpdate then
		name = xlib.makecombobox{ x=75, y=30, w=200, parent=xgui_banwindow, enableinput=true, selectall=true }
		for k,v in pairs( player.GetAll() ) do
			name:AddChoice( v:Nick(), v:SteamID() )
		end
		name.OnSelect = function( self, index, value, data )
			self.steamIDbox:SetText( data )
		end
	else
		name = xlib.maketextbox{ x=75, y=30, w=200, parent=xgui_banwindow, selectall=true }
		if bandata then
			name:SetText( bandata.name or "" )
			reason:SetText( bandata.reason or "" )
			if tonumber( bandata.unban ) ~= 0 then
				local btime = ( tonumber( bandata.unban ) - tonumber( bandata.time ) )
				if btime % 31536000 == 0 then
					if #banpanel.interval.Choices >= 6 then
						banpanel.interval:ChooseOptionID(6)
					else
						banpanel.interval:SetText( "Years" )
					end
					btime = btime / 31536000
				elseif btime % 604800 == 0 then
					if #banpanel.interval.Choices >= 5 then
						banpanel.interval:ChooseOptionID(5)
					else
						banpanel.interval:SetText( "Weeks" )
					end
					btime = btime / 604800
				elseif btime % 86400 == 0 then
					if #banpanel.interval.Choices >= 4 then
						banpanel.interval:ChooseOptionID(4)
					else
						banpanel.interval:SetText( "Days" )
					end
					btime = btime / 86400
				elseif btime % 3600 == 0 then
					if #banpanel.interval.Choices >= 3 then
						banpanel.interval:ChooseOptionID(3)
					else
						banpanel.interval:SetText( "Hours" )
					end
					btime = btime / 3600
				else
					btime = btime / 60
					if #banpanel.interval.Choices >= 2 then
						banpanel.interval:ChooseOptionID(2)
					else
						banpanel.interval:SetText( "Minutes" )
					end
				end
				banpanel.val:SetValue( btime )
			end
		end
	end

	local steamID = xlib.maketextbox{ x=75, y=55, w=200, selectall=true, disabled=( isUpdate or not LocalPlayer():query( "ulx sbanid" ) ), parent=xgui_banwindow }
	name.steamIDbox = steamID --Make a reference to the steamID textbox so it can change the value easily without needing a global variable

	if doFreeze and ply then
		if LocalPlayer():query( "ulx freeze" ) then
			RunConsoleCommand( "ulx", "freeze", "$" .. ULib.getUniqueIDForPlayer( ply ) )
			steamID:SetDisabled( true )
			name:SetDisabled( true )
			xgui_banwindow:ShowCloseButton( false )
		else
			doFreeze = false
		end
	end
	xlib.makebutton{ x=165, y=150, w=75, label="Cancel", parent=xgui_banwindow }.DoClick = function()
		if doFreeze and ply and ply:IsValid() then
			RunConsoleCommand( "ulx", "unfreeze", "$" .. ULib.getUniqueIDForPlayer( ply ) )
		end
		xgui_banwindow:Remove()
	end
	xlib.makebutton{ x=45, y=150, w=75, label=( isUpdate and "Update" or "Ban!" ), parent=xgui_banwindow }.DoClick = function()
		if isUpdate then
			local function performUpdate(btime)
				RunConsoleCommand( "xgui", "updatesBan", steamID:GetValue(), btime, reason:GetValue(), name:GetValue() )
				xgui_banwindow:Remove()
			end
			btime = banpanel:GetMinutes()
			if btime ~= 0 and bandata and btime * 60 + bandata.time < os.time() then
				Derma_Query( "WARNING! The new ban time you have specified will cause this ban to expire.\nThe minimum time required in order to change the ban length successfully is " 
						.. xgui.ConvertTime( os.time() - bandata.time ) .. ".\nAre you sure you wish to continue?", "XGUI WARNING",
					"Expire Ban", function()
						performUpdate(btime)
						xunbans.RemoveBanDetailsWindow( bandata.steamID )
					end,
					"Cancel", function() end )
			else
				performUpdate(btime)
			end
			return
		end

		if ULib.isValidSteamID( steamID:GetValue() ) then
			local isOnline = false
			for k, v in ipairs( player.GetAll() ) do
				if v:SteamID() == steamID:GetValue() then
					isOnline = v
					break
				end
			end
			if not isOnline then
				if name:GetValue() == "" then
					RunConsoleCommand( "ulx", "sbanid", steamID:GetValue(), banpanel:GetValue(), reason:GetValue() )
				else
					RunConsoleCommand( "xgui", "updatesBan", steamID:GetValue(), banpanel:GetMinutes(), reason:GetValue(), ( name:GetValue() ~= "" and name:GetValue() or nil ) )
				end
			else
				RunConsoleCommand( "ulx", "sban", "$" .. ULib.getUniqueIDForPlayer( isOnline ), banpanel:GetValue(), reason:GetValue() )
			end
			xgui_banwindow:Remove()
		else
			local ply = ULib.getUser( name:GetValue() )
			if ply then
				RunConsoleCommand( "ulx", "sban", "$" .. ULib.getUniqueIDForPlayer( ply ), banpanel:GetValue(), reason:GetValue() )
				xgui_banwindow:Remove()
				return
			end
			Derma_Message( "Invalid SteamID, player name, or multiple player targets found!" )
		end
	end

	if ply then name:SetText( ply:Nick() ) end
	if ID then steamID:SetText( ID ) else steamID:SetText( "STEAM_0:" ) end
end

function xgui.ConvertTime( seconds )
	--Convert number of seconds remaining to something more legible (Thanks JamminR!)
	local years = math.floor( seconds / 31536000 )
	seconds = seconds - ( years * 31536000 )
	local weeks = math.floor( seconds / 604800 )
	seconds = seconds - ( weeks * 604800 )
	local days = math.floor( seconds / 86400 )
	seconds = seconds - ( days * 86400 )
	local hours = math.floor( seconds/3600 )
	seconds = seconds - ( hours * 3600 )
	local minutes = math.floor( seconds/60 )
	seconds = seconds - ( minutes * 60 )
	local curtime = ""
	if years ~= 0 then curtime = curtime .. years .. " year" .. ( ( years > 1 ) and "s, " or ", " ) end
	if weeks ~= 0 then curtime = curtime .. weeks .. " week" .. ( ( weeks > 1 ) and "s, " or ", " ) end
	if days ~= 0 then curtime = curtime .. days .. " day" .. ( ( days > 1 ) and "s, " or ", " ) end
	curtime = curtime .. ( ( hours < 10 ) and "0" or "" ) .. hours .. ":"
	curtime = curtime .. ( ( minutes < 10 ) and "0" or "" ) .. minutes .. ":"
	return curtime .. ( ( seconds < 10 and "0" or "" ) .. seconds )
end

---Update stuff
function xunbans.bansRefreshed()
	xgui.data.unbans.cache = {} -- Clear the bans cache

	-- Retrieve bans if XGUI is open, otherwise it will be loaded later.
	if xgui.anchor:IsVisible() then
		xunbans.retrieveBans()
	end
end
xgui.hookEvent( "unbans", "process", xunbans.bansRefreshed, "sbansRefresh" )

function xunbans.banPageRecieved( data )
	xgui.data.unbans.cache = data
	xunbans.clearbans()
	xunbans.populateBans()
end
xgui.hookEvent( "unbans", "data", xunbans.banPageRecieved, "sbansGotPage" )

function xunbans.checkCache()
	if xgui.data.unbans.cache and xgui.data.unbans.count ~= 0 and table.Count(xgui.data.unbans.cache) == 0 then
		xunbans.retrieveBans()
	end
end
xgui.hookEvent( "onOpen", nil, xunbans.checkCache, "sbansCheckCache" )

function xunbans.clearbans()
	xunbans.banlist:Clear()
end

function xunbans.retrieveBans()
	RunConsoleCommand( "xgui", "getsbans",
		sortMode,			-- Sort Type
		searchFilter,		-- Filter String
		hidePerma,			-- Hide permabans?
		hideIncomplete,		-- Hide bans that don't have full ULX metadata?
		pageNumber,			-- Page number
		sortAsc and 1 or 0)	-- Ascending/Descending
end

function xunbans.populateBans()
	if xgui.data.unbans.cache == nil then return end
	local cache = xgui.data.unbans.cache
	local count = cache.count or xgui.data.unbans.count
	numPages = math.max( 1, math.ceil( count / 17 ) )

	xunbans.setResultCount( count )
	xunbans.pageSelector:SetDisabled( numPages == 1 )
	xunbans.pageSelector:Clear()
	for i=1, numPages do
		xunbans.pageSelector:AddChoice(i)
	end
	xunbans.setPage( math.Clamp( pageNumber, 1, numPages ) )

	cache.count = nil

	for _, baninfo in pairs( cache ) do
		xunbans.banlist:AddLine( baninfo.name or baninfo.steamID,
					( baninfo.admin ) and string.gsub( baninfo.admin, "%(STEAM_%w:%w:%w*%)", "" ) or "",
					(( tonumber( baninfo.unban ) ~= 0 ) and os.date( "%c", math.min( tonumber( baninfo.unban ), 4294967295 ) )) or "Never",
					baninfo.reason,
					baninfo.steamID,
					tonumber( baninfo.unban ) )
	end
end
xunbans.populateBans()

function xunbans.xban( ply, cmd, args, dofreeze )
	if args[1] and args[1] ~= "" then
		local target = ULib.getUser( args[1] )
		if target then
			xgui.ShowSBanWindow( target, target:SteamID(), dofreeze )
		end
	else
		xgui.ShowSBanWindow()
	end
end
ULib.cmds.addCommandClient( "xgui xsban", xunbans.xban )

function xunbans.fban( ply, cmd, args )
	xunbans.xban( ply, cmd, args, true )
end
ULib.cmds.addCommandClient( "xgui fsban", xunbans.fban )

function xunbans.UCLChanged()
	xunbans.btnFreezeBan:SetDisabled( not LocalPlayer():query("ulx freeze") )
end
hook.Add( "UCLChanged", "xgui_RefreshBansMenu", xunbans.UCLChanged )

xgui.addModule( "SourceBans", xunbans, "icon16/exclamation.png", "xgui_manageunbans" )
