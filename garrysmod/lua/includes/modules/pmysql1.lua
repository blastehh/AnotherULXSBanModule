local tostring 			= tostring;
local pairs 			= pairs;
local ipairs 			= ipairs;
local string 			= string;
local unpack 			= unpack;
local SysTime 			= SysTime;

require( 'tmysql4' );

pmysql1                	= { };

local db_cache        	= { };
local query_cache     	= { };
local sync_timeout    	= 0.3;
local logging_enabled 	= true;
local log_file        	= 'pmysql_log.txt';
local max_errors		= 10;

local db_mt           	= { };
db_mt.__index         	= db_mt;

function pmysql1.print( ... )
  return MsgC( Color( 225, 0, 0 ), '[MYSQL] ', Color( 255, 255, 255 ), ... .. '\n' );
end

function pmysql1.log( str )
  pmysql1.print( str );
  if not logging_enabled then return end
  file.Append( log_file, os.date( '[%X - %d/%m/%Y] ', os.time() ) .. str .. '\n' );
end

function pmysql1.connect( hostname, username, password, database, port, optional_unix_socket_path )
	local obj = { };
	setmetatable( obj, db_mt );
  
	obj.hash = debug.getinfo(2).short_src

	if db_cache[ obj.hash ] then
		pmysql1.log( 'Recreating database connection : '.. username .. ':' .. database .. '@' .. hostname .. ':' .. port );
		db_cache[ obj.hash ]._db:Disconnect( )
		db_cache[ obj.hash ] = nil
	end

	obj._db, obj.err   = tmysql.initialize( hostname, username, password, database, port, optional_unix_socket_path );
	obj.hostname       = hostname;
	obj.username       = username;
	obj.password       = password;
	obj.database       = database;
	obj.port           = port;

	if obj._db then 
		pmysql1.log( 'Connected '.. username .. ':' .. database .. '@' .. hostname .. ':' .. port .. ' successfully.' );
	elseif obj.err then
		pmysql1.log( 'Connection ' .. username .. ':' .. database .. '@' .. hostname .. ':' .. port .. ' failed. ERROR: ' .. obj.err );
		return
	end

	db_cache[ obj.hash ] = obj;
	--obj._db:Query("SET NAMES UTF8MB4", function(results) end)
	return obj;
end
pmysql1.newdb = pmysql1.connect;

function pmysql1.getTable( )
  return db_cache;
end

function pmysql1.pollAll( )
  for _, db in pairs( pmysql1.getTable() ) do
    db:poll( );
  end
end

function pmysql1.setTimeOut( time )
  sync_timeout = time;
end

function pmysql1.setMaxErrors( num )
  max_errors = num;
end

function pmysql1.enableLog( bool )
  logging_enabled = bool;
end

function db_mt:escape( str )
  return self._db:Escape( tostring( str ) );
end

function db_mt:poll( )
  return self._db:Poll( );
end

function db_mt:setCharset( charset )
  return self._db:SetCharset( charset );
end

function db_mt:disconnect( )
  self._db:Disconnect( );
  db_cache[ self ] = nil;
end

function db_mt:query( sqlstr, cback, ... )
	local args = {...}

	return self._db:Query( sqlstr, function( results )
		for i=1, #results do
			if results[i].error then
				pmysql1.log( self.database .. ':' .. self.port .. ' - ' .. results[i].error );
				if ( query_cache[ sqlstr ] == nil ) then
					query_cache[ sqlstr ] = { obj = self, cback = cback, args = args };
				elseif ( max_errors ~= nil ) and ( query_cache[ sqlstr ] ~= nil ) and ( query_cache[ sqlstr ].errcount >= max_errors ) then
					pmysql1.log( 'ERROR: Query timeout - ' .. sqlstr );
					query_cache[ sqlstr ] = nil;
				elseif ( query_cache[ sqlstr ] ~= nil ) then
					query_cache[ sqlstr ].retry = true;
				end
			else
				if cback then cback( results[i].data, unpack(args) ); end
			end
		end
	end);
end

function db_mt:query_ex( sqlstr, options, cback, ... )
	local args = {...}
	if options ~= nil then
		for k, v in ipairs( options ) do
			options[ k ] = self:escape( v );
		end

		sqlstr = sqlstr:gsub( '%%','%%%%' ):gsub( '?', '%%s' );
		sqlstr = string.format( sqlstr, unpack( options ) );
	end
	return self:query( sqlstr, cback, unpack(args) );
end

function db_mt:query_sync( sqlstr, options, timeout ) 
  local _data;
  local done = false;
  local time = SysTime() + ( timeout and timeout or sync_timeout );
  self:query_ex( sqlstr, options, function( data )
    _data = data;
    done = true;
    time = 0;
  end );

  while ( not done ) and ( time > SysTime() ) do
    self:poll( );
  end

  return _data;
end

hook.Add('Tick', 'pmysql1.Poll', function()
  for k, v in pairs( query_cache ) do
  	if ( v.retry ~= false ) then
	    v.errcount = ( v.errcount ~= nil ) and ( v.errcount + 1 ) or 2;
	    v.retry = false;
	    v.obj:query( k, v.cback, unpack(v.args));
	end
  end
end );