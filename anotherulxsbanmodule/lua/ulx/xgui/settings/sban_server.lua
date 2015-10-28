------------------------Votekick/Voteban-------------------------
local plist = xlib.makelistlayout{ w=275, h=322, parent=xgui.null }
plist:Add( xlib.makelabel{ label="nVoteSban Settings" } )
plist:Add( xlib.makelabel{ label="Ratio of votes needed to accept votesban" } )
plist:Add( xlib.makeslider{ label="<--->", min=0, max=1, decimal=2, repconvar="ulx_votesbanSuccessratio" } )
plist:Add( xlib.makelabel{ label="Minimum votes required for a successful votesban" } )
plist:Add( xlib.makeslider{ label="<--->", min=0, max=10, repconvar="ulx_votesbanMinvotes" } )
xgui.addSubModule( "ULX SBan Voting", plist, nil, "server" )