-- ZShare's rows in Black Ops III's own pause menu, during a match.
--
-- The settings row is the second way into the page zsharesettings.lua
-- builds, and nothing else: both entry points call Z.CreateMenu(), so the
-- rows, the saving and the footer are the same in the lobby and in a match by
-- construction. Above it come the shared actions, which are presses rather
-- than settings. ZShare registers none of its own -- everything it does is a
-- prompt in the world -- but the list is still drawn from here, because in a
-- bundle whichever mod loaded first is the one whose copy renders, and ZShare
-- has to be able to draw ZPause's PAUSE GAME row as readily as its own entry.
--
-- Two halves. LUI.createMenu.ZShareInGameSettings is the page itself, which
-- is defined wherever this file is read -- the frontend included. It is not
-- guarded on the map: T7x can keep a module across the step into a match, so
-- a page defined only in a match would be one the frontend had already
-- decided not to have.
--
-- The other half puts a ZSHARE SETTINGS row in the pause menu's own list,
-- between RESUME GAME and the ones that end the game. The list is built by
-- DataSources.StartMenuGameOptions, and the wrap is put back from a timer
-- rather than once: the data source can be replaced after this file is read,
-- and a wrap on the object that has gone is a wrap on nothing. Wrapping is
-- idempotent -- a source already carrying ours is left alone -- so a pass
-- that finds nothing new costs a table lookup.
--
-- Host only, zombies only, the same as the lobby button: everybody's game
-- reads its own settings, but only the host's are the ones the pause runs on.

local Z = CoD.ZShareSettings
local B = CoD.ZBundleSettings
local P = {}

LUI.createMenu.ZShareInGameSettings = function ( controller )
	Z.Startup( controller )
	return Z.CreateMenu( controller, "ZShareInGameSettings" )
end

-- Whether a row in the list is one of ours, so a second pass over a list
-- that kept them does not add them again. The mark is the reliable half;
-- the text is the fallback, for a row put there by a build that had none.
P.IsOurs = function ( item, value )
	-- Any Z mod's mark, not only ZShare's: in a bundle the rows may have
	-- been put there by whichever copy of this claimed the ownership flags,
	-- and a row added twice is the thing this is here to stop.
	if item ~= nil and (item.zshareRow == true or item.zbundleRow == true
			or item.zpauseRow == true or item.ztweaksRow == true) then
		return true
	end
	if value == nil then
		return false
	end
	if value == Z.Title() or value == "ZSHARE SETTINGS" or value == "ZBUNDLE SETTINGS" then
		return true
	end
	local ok, text = pcall( Engine.Localize, value )
	return ok and text == Z.Title()
end

-- Whether this player is the host, for a host's action. The shared answer
-- where there is one, failing closed on UNKNOWN; this page's own host test
-- where a registry this old has none.
P.AmHost = function ( controller )
	if B.HostStatus ~= nil then
		local ok, status = pcall( B.HostStatus, controller )
		return ok and status == "HOST"
	end
	if Z == nil or type( Z.IsHost ) ~= "function" then
		return false
	end
	local ok, host = pcall( Z.IsHost, controller )
	return ok and host == true
end

-- The actions this player is drawn. A player's action is every player's;
-- any other is a host's press and is drawn for the host alone. The press
-- asks again.
P.ActionsFor = function ( controller, amHost )
	local out = {}
	for _, entry in ipairs( B.GetActions( controller ) ) do
		if entry.authority == "player" or amHost then
			out[#out + 1] = entry
		end
	end
	return out
end

-- An action's own press. The action is looked up by id when it is pressed
-- rather than held in the handler: a mod may have corrected its own
-- registration since the menu was built, and what the player pressed is the
-- row as it reads now.
-- The menu goes with it, as the third argument, the same as on Black Ops II:
-- an action that has to close the menu it was pressed from has no other way
-- to reach it.
P.Press = function ( id )
	return function ( self, element, controller, param, menu )
		local action = B.ActionById[id]
		if action == nil or type( action.action ) ~= "function" then
			return
		end
		if not B.ActionEnabled( action, controller ) then
			return
		end
		-- Authority again at the press, not only when the row was drawn: host
		-- status can change with the menu open, and a host's action is never
		-- a client's to fire.
		if action.authority ~= "player" and not P.AmHost( controller ) then
			return
		end
		pcall( action.action, controller, action, menu )
	end
end

-- Where the row goes: ahead of the first thing that ends or restarts the
-- game, which in a zombies match leaves it directly under RESUME GAME.
P.Place = function ( items )
	local at = #items + 1
	for index, item in ipairs( items ) do
		local model = item ~= nil and item.model ~= nil and Engine.GetModel( item.model, "displayText" ) or nil
		local value = model ~= nil and Engine.GetModelValue( model ) or nil
		if P.IsOurs( item, value ) then
			return nil
		end
		if at == #items + 1 and (value == "MENU_RESTART_LEVEL_CAPS" or value == "MENU_END_GAME_CAPS" or value == "MENU_QUIT_GAME_CAPS") then
			at = index
		end
	end
	return at
end

P.Install = function ()
	local source = DataSources ~= nil and DataSources.StartMenuGameOptions or nil
	if source == nil or source.prepare == nil or source.zshareWrapped then
		return
	end
	source.zshareWrapped = true

	local prepare = source.prepare
	source.prepare = function ( controller, list, filter )
		prepare( controller, list, filter )
		pcall( function ()
			-- Any zombies match: the actions go by their own authority, and a
			-- player's action is every player's whether or not they have a
			-- setting row (ZStats' HUD toggle was missing for such a client).
			if list == nil or not CoD.isZombie then
				return
			end
			local name = list.customDataSourceHelper
			local items = name ~= nil and list[name] or nil
			if items == nil then
				return
			end
			local at = P.Place( items )
			if at == nil then
				return
			end
			local root = ListHelper_GetListHelperModel( list, true )
			if root == nil then
				return
			end
			-- The actions first, so the pause sits directly under RESUME
			-- GAME where a player looking for it would reach for it.
			if Z.DrawsActionRows() then
				for _, entry in ipairs( P.ActionsFor( controller, P.AmHost( controller ) ) ) do
					local action = Engine.CreateModel( root, "zshareAction_" .. entry.id )
					Engine.SetModelValue( Engine.CreateModel( action, "displayText" ),
						Z.ActionWords( entry, controller ) )
					Engine.SetModelValue( Engine.CreateModel( action, "action" ), P.Press( entry.id ) )
					table.insert( items, at, {
						model = action,
						properties = {},
						zshareRow = true,
						zbundleRow = true
					} )
					at = at + 1
				end
			end
			-- The settings row: the host always, a client when the screen holds
			-- something of theirs, which standalone ZShare never has and a
			-- bundle can -- the row is drawn by whichever Z mod loaded first, so
			-- hiding it here hides somebody else's personal rows along with
			-- ZShare's.
			if not Z.DrawsSettingsRow() or not Z.EntryVisible( controller ) then
				return
			end
			local row = Engine.CreateModel( root, "zshareSettings" )
			Engine.SetModelValue( Engine.CreateModel( row, "displayText" ),
				Z.MenuTitle( B.GetTabs( controller ) ) )
			Engine.SetModelValue( Engine.CreateModel( row, "action" ), Z.OpenFromPause )
			table.insert( items, at, {
				model = row,
				properties = {},
				zshareRow = true,
				zbundleRow = true
			} )
		end )
	end
end

P.Install()
-- One timer, kept: it is not disposable, so it resets itself rather than
-- leaving a new element behind on every pass.
if LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil and not CoD.ZSharePauseEntryWatching then
	CoD.ZSharePauseEntryWatching = true
	LUI.roots.UIRootFull:addElement( LUI.UITimer.newElementTimer( 500, false, function ()
		P.Install()
	end ) )
end
