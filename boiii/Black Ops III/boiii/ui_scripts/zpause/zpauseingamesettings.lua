-- ZBUNDLE_ENTRY_LOCALIZATION_V1
-- The pause-menu entry is localized natively: Z.MenuTitle draws from ZPause's
-- own catalogs in the language on screen, and the row is recognised by that same
-- title, so a bundle builder finding this marker changes nothing in this file.
-- ZPause's rows in Black Ops III's own pause menu, during a match.
--
-- Two of them. The settings row is the second way into the page
-- zpausesettings.lua builds, and nothing else: both entry points call
-- Z.CreateMenu(), so the rows, the saving and the footer are the same in
-- the lobby and in a match by construction. Above it come the shared
-- actions, of which ZPause registers one: PAUSE GAME, or UNPAUSE GAME while
-- the game is paused. Both are drawn from the shared registry rather than
-- from a list of ZPause's own, so a bundle shows one settings row and
-- everybody's actions.
--
-- Two halves. LUI.createMenu.ZPauseInGameSettings is the page itself, which
-- is defined wherever this file is read -- the frontend included. It is not
-- guarded on the map: T7x can keep a module across the step into a match, so
-- a page defined only in a match would be one the frontend had already
-- decided not to have.
--
-- The other half puts a ZPAUSE SETTINGS row in the pause menu's own list,
-- between RESUME GAME and the ones that end the game. The list is built by
-- DataSources.StartMenuGameOptions, and the wrap is put back from a timer
-- rather than once: the data source can be replaced after this file is read,
-- and a wrap on the object that has gone is a wrap on nothing. Wrapping is
-- idempotent -- a source already carrying ours is left alone -- so a pass
-- that finds nothing new costs a table lookup.
--
-- Zombies only. The settings row is everybody's: a client has their own rows
-- on the shared page, and the host's are locked one by one inside it. An
-- action is drawn for whoever its authority says it is for.

local Z = CoD.ZPauseSettings
local B = CoD.ZBundleSettings
local P = {}

LUI.createMenu.ZPauseInGameSettings = function ( controller )
	-- Both entry routes or neither: T7 has two factories and a passing check on
	-- one proves nothing about the other, so this one asks the same question.
	-- Z.Startup stays on ZPause's side of the line - it is a storage and
	-- restore keeper, which rule 4 says never moves into a renderer, so it runs
	-- whoever owns the screen.
	Z.Startup( controller )
	local elsewhere = Z.MenuEntryElsewhere( LUI.createMenu.ZPauseInGameSettings )
	if elsewhere ~= nil then
		return elsewhere( controller )
	end
	return Z.CreateMenu( controller, "ZPauseInGameSettings" )
end

-- Whether a row in the list is one of ours, so a second pass over a list
-- that kept them does not add them again. The mark is the reliable half;
-- the text is the fallback, for a row put there by a build that had none.
P.IsOurs = function ( item, value )
	if item ~= nil and item.zpauseRow == true then
		return true
	end
	if value == nil then
		return false
	end
	if value == Z.Title() or value == "ZPAUSE SETTINGS" or value == "ZBUNDLE SETTINGS"
		or value == Z.Text( "ui.bundle_title", "ZBUNDLE SETTINGS" ) then
		return true
	end
	local ok, text = pcall( Engine.Localize, value )
	return ok and text == Z.Title()
end

-- An action's own press. The action is looked up by id when it is pressed
-- rather than held in the handler: a mod may have corrected its own
-- registration since the menu was built, and what the player pressed is the
-- row as it reads now.
-- Whether this player is the host, for a host's action. The shared answer
-- where there is one, failing closed on UNKNOWN; the lobby's own where a
-- registry this old has none.
P.AmHost = function ( controller )
	if B.HostStatus ~= nil then
		local ok, status = pcall( B.HostStatus, controller )
		return ok and status == "HOST"
	end
	return CoD.ZPauseAPI ~= nil and CoD.ZPauseAPI.IsHost ~= nil and CoD.ZPauseAPI.IsHost() == true
end

P.Press = function ( id )
	return function ( self, element, controller )
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
		pcall( action.action, controller, action )
	end
end

-- Where the rows go: after everything the host's own game runs on.
--
-- They used to go above the first of them, which read well -- the pause sat
-- under RESUME GAME -- and was wrong: the list shows five rows at a time, so
-- two mods' rows pushed END GAME off the bottom of a menu that still had it.
-- Resume, Restart and End Game are the game's, they come first, and ours
-- follow. A bundle that recovers a lifecycle row late moves our rows behind
-- it again; this does not put them back in front on the next pass.
P.LIFECYCLE = {
	MENU_RESUME_GAME_CAPS = true,
	MENU_RESTART_LEVEL_CAPS = true,
	MENU_END_GAME_CAPS = true,
	MENU_QUIT_GAME_CAPS = true
}

P.Place = function ( items )
	local at = 1
	for index, item in ipairs( items ) do
		local model = item ~= nil and item.model ~= nil and Engine.GetModel( item.model, "displayText" ) or nil
		local value = model ~= nil and Engine.GetModelValue( model ) or nil
		if P.IsOurs( item, value ) then
			return nil
		end
		if value ~= nil and P.LIFECYCLE[value] then
			at = index + 1
		end
	end
	if at < 1 or at > #items + 1 then
		at = #items + 1
	end
	return at
end

-- The actions this player may press: all of them for the host, and for anybody
-- else the ones that declare authority = "player". Read from the descriptor
-- each time, so a mod that corrects its own registration is drawn as it reads now.
P.ActionsFor = function ( controller, amHost )
	local result = {}
	for _, entry in ipairs( B.GetActions( controller ) ) do
		if amHost or entry.authority == "player" then
			table.insert( result, entry )
		end
	end
	return result
end

P.Install = function ()
	local source = DataSources ~= nil and DataSources.StartMenuGameOptions or nil
	if source == nil or source.prepare == nil or source.zpauseWrapped then
		return
	end
	source.zpauseWrapped = true

	local prepare = source.prepare
	source.prepare = function ( controller, list, filter )
		prepare( controller, list, filter )
		pcall( function ()
			-- Anybody in a zombies match, not the host alone. The page is
			-- the shared shell and a client has their own rows on it; the
			-- host's are locked one by one inside it. The actions below
			-- keep their own host check.
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
			-- GAME where a player looking for it would reach for it. Each
			-- is drawn for whoever its own authority says: an action that
			-- declares authority = "player" acts on the player who presses
			-- it - ZPause's pause, which the script puts through the combo's
			-- gates, and ZStats' HUD toggle - and is every player's; any
			-- other action is a host's press and stays the host's. Whole
			-- list host-gated until 1.7, so a client saw neither.
			local amHost = P.AmHost( controller )
			if Z.DrawsActionRows() then
				for _, entry in ipairs( P.ActionsFor( controller, amHost ) ) do
					local action = Engine.CreateModel( root, "zpauseAction_" .. entry.id )
					Engine.SetModelValue( Engine.CreateModel( action, "displayText" ),
						Z.ActionWords( entry, controller ) )
					Engine.SetModelValue( Engine.CreateModel( action, "action" ), P.Press( entry.id ) )
					table.insert( items, at, {
						model = action,
						properties = {},
						zpauseRow = true
					} )
					at = at + 1
				end
			end
			if not Z.DrawsSettingsRow() then
				return
			end
			local row = Engine.CreateModel( root, "zpauseSettings" )
			Engine.SetModelValue( Engine.CreateModel( row, "displayText" ),
				Z.MenuTitle( B.GetTabs( controller ) ) )
			Engine.SetModelValue( Engine.CreateModel( row, "action" ), Z.OpenFromPause )
			table.insert( items, at, {
				model = row,
				properties = {},
				zpauseRow = true
			} )
		end )
	end
end

P.Install()
-- One timer, kept: it is not disposable, so it resets itself rather than
-- leaving a new element behind on every pass.
if LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil and not CoD.ZPausePauseEntryWatching then
	CoD.ZPausePauseEntryWatching = true
	LUI.roots.UIRootFull:addElement( LUI.UITimer.newElementTimer( 500, false, function ()
		P.Install()
		-- And the state a client's row reads, in case the root was not there
		-- when zpausesettings.lua first asked.
		if CoD.ZPauseAPI ~= nil and CoD.ZPauseAPI.WatchState ~= nil then
			CoD.ZPauseAPI.WatchState()
		end
	end ) )
end
