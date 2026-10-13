-- Restore the host lifecycle rows if the active BO3 start-menu data source
-- omitted them. T7x can expose a transient Resume-only source while loose
-- ui_scripts and a selected fastfile are being combined; a bundle must not
-- turn that transient shape into a permanent menu without END GAME.
-- This wraps the completed stock list instead of replacing the data source, so
-- stock and other mods keep every option they contributed. Keep polling from
-- the frontend as well: T7x can cache this module across map transitions.

local R = {}
local Z = CoD.ZTweaksSettings
local B = CoD.ZBundleSettings
local L = CoD.ZTweaksLocalization
local NewElementTimer = LUI ~= nil and LUI.UITimer ~= nil and LUI.UITimer.newElementTimer or nil
pcall( require, "ui.uieditor.widgets.StartMenu.StartMenu_GameOptions_ZM" )

-- The stock Zombies game-options widget exposes only five 33.6-unit rows.
-- With Resume/Restart/End/Quit first, a complete bundle's actions and settings
-- are present in the datasource but hidden below that uncued viewport. Grow
-- only the bundled widget; its rank panel begins at y=451, so up to eleven
-- rows fit without covering the stock bottom content.
R.ExpandBundleList = function ()
	local widget = CoD.StartMenu_GameOptions_ZM
	if widget == nil or type( widget.new ) ~= "function" or widget.ztweaksBundleListWrapped then return false end
	local originalNew = widget.new
	widget.new = function ( menu, controller )
		local panel = originalNew( menu, controller )
		if panel ~= nil and panel.buttonList ~= nil and B ~= nil and type( B.IsBundle ) == "function" and B.IsBundle() then
			local actionCount = 0
			if type( B.GetActions ) == "function" then
				local ok, actions = pcall( B.GetActions, controller )
				if ok and type( actions ) == "table" then
					local isHost = B.HostStatus( controller ) == "HOST"
					for _, entry in ipairs( actions ) do
						if isHost or entry.authority == "player" then actionCount = actionCount + 1 end
					end
				end
			end
			local count = math.min( 11, math.max( 7, 5 + actionCount ) )
			panel.buttonList:setTopBottom( true, false, 4.91, 4.91 + count * 33.6 )
			panel.buttonList:setVerticalCount( count )
		end
		return panel
	end
	widget.ztweaksBundleListWrapped = true
	return true
end

R.IsRestart = function ( value )
	return value == "MENU_RESTART_LEVEL_CAPS" or value == Engine.Localize( "MENU_RESTART_LEVEL_CAPS" )
end

R.IsEndGame = function ( value )
	return value == "MENU_END_GAME_CAPS" or value == "MENU_QUIT_GAME_CAPS"
		or value == Engine.Localize( "MENU_END_GAME_CAPS" )
		or value == Engine.Localize( "MENU_QUIT_GAME_CAPS" )
end

R.IsSettings = function ( value )
	-- Recognize our entry by every catalog spelling, including a cached label
	-- from a previous language. Do not add duplicate settings rows on refresh.
	if L ~= nil then
		for _, catalog in pairs( L.Catalogs ) do
			if value ~= nil and ( value == catalog["ZTWEAKS SETTINGS"] or value == catalog["ZBUNDLE SETTINGS"] ) then return true end
		end
	end
	return value == "ZTWEAKS SETTINGS" or value == "ZBUNDLE SETTINGS" or value == Engine.Localize( "ZTWEAKS SETTINGS" ) or value == Engine.Localize( "ZBUNDLE SETTINGS" )
end

R.PressAction = function ( id )
	return function ( self, element, controller )
		local action = B.ActionById[id]
		if action == nil or ( action.authority ~= "player" and B.HostStatus( controller ) ~= "HOST" ) then return end
		if action == nil or type( action.action ) ~= "function" or not B.ActionEnabled( action, controller ) then return end
		pcall( action.action, controller, action )
	end
end

R.EndGame = function ( self, element, controller )
	if B.HostStatus( controller ) ~= "HOST" then return end
	local parent = self
	while parent ~= nil and parent.openMenu == nil do
		parent = parent:getParent()
	end
	if parent == nil or CoD.OverlayUtility == nil then return end

	local name = "ZTweaksEndGameConfirm"
	CoD.OverlayUtility.AddSystemOverlay( name, {
		menuName = "SystemOverlay_Compact",
		title = Engine.Localize( "MENU_END_GAME_CAPS" ),
		description = L.Text( "End the current game?" ),
		categoryType = CoD.OverlayUtility.OverlayTypes.Alert,
		listDatasource = function ()
			DataSources[name .. "_List"] = DataSourceHelpers.ListSetup( name .. "_List", function ()
				return {
					{
						models = { displayText = Engine.Localize( "MENU_NO" ) },
						properties = { action = function ( row, button, choiceController, param, overlay )
							GoBack( overlay, choiceController )
						end }
					},
					{
						models = { displayText = Engine.Localize( "MENU_YES" ) },
						properties = { action = function ( row, button, choiceController, param, overlay )
							GoBack( overlay, choiceController )
							if B.HostStatus( choiceController ) == "HOST" then
								Engine.SendMenuResponse( choiceController, "popup_leavegame", "endround" )
							end
						end }
					}
				}
			end, true, nil )
			return name .. "_List"
		end
	} )
	CoD.OverlayUtility.CreateOverlay( controller, parent, name )
end

-- Other Z mods can own the shared renderer and put their actions/settings
-- ahead of the stock lifecycle group. Move every marked shared row behind
-- RESTART/END GAME so a future third action cannot push END GAME below the
-- native five-row T7 start-menu viewport again.
R.IsSharedRow = function ( item, value )
	return item ~= nil and ( item.ztweaksSharedRow == true or item.zpauseRow == true
		or item.zshareRow == true or item.zstatsSharedRow == true or item.zbundleRow == true )
		or R.IsSettings( value )
end

R.MoveSharedAfterLifecycle = function ( items )
	local shared = {}
	for index = #items, 1, -1 do
		local item = items[index]
		local display = item ~= nil and item.model ~= nil and Engine.GetModel( item.model, "displayText" ) or nil
		local value = display ~= nil and Engine.GetModelValue( display ) or nil
		if R.IsSharedRow( item, value ) then
			table.insert( shared, 1, table.remove( items, index ) )
		end
	end
	for _, item in ipairs( shared ) do
		table.insert( items, item )
	end
end

R.Install = function ()
	local source = DataSources ~= nil and DataSources.StartMenuGameOptions or nil
	if source == nil or source.prepare == nil or source.ztweaksRestartWrapped then
		return false
	end

	source.ztweaksRestartWrapped = true
	local prepare = source.prepare
	source.prepare = function ( controller, list, filter )
		prepare( controller, list, filter )

		-- The start-menu datasource can briefly contain incomplete entries while
		-- last stand, game over, or another mod is rebuilding it. Our optional
		-- buttons must fail closed instead of breaking the stock pause menu.
		pcall( function ()
			if list == nil or not CoD.isZombie then
				return
			end

			local name = list.customDataSourceHelper
			local items = name ~= nil and list[name] or nil
			if items == nil then
				return
			end
			-- Preserve every stock row at the front of the native five-row
			-- viewport.  In particular, registered Z-mod actions must not push
			-- END GAME below the fold and make it appear to be missing.
			local sharedAt = #items + 1
			local hasSettings = false
			local hasRestart = false
			local hasEndGame = false
			local actionIds = {}
			for index, item in ipairs( items ) do
				if item ~= nil and item.ztweaksActionId ~= nil then actionIds[item.ztweaksActionId] = true end
				local display = item ~= nil and item.model ~= nil and Engine.GetModel( item.model, "displayText" ) or nil
				local value = display ~= nil and Engine.GetModelValue( display ) or nil
				if R.IsSettings( value ) then
					hasSettings = true
					Engine.SetModelValue( display, CoD.ZTweaksSettings.EntryLabel() )
				end
				if R.IsRestart( value ) then
					hasRestart = true
				end
				if R.IsEndGame( value ) then
					hasEndGame = true
				end
			end

			local root = ListHelper_GetListHelperModel( list, true )
			if root == nil then
				return
			end
			local isHost = B.HostStatus( controller ) == "HOST"
			if Z.DrawsActionRows() then
				for _, entry in ipairs( B.GetActions( controller ) ) do
					if ( isHost or entry.authority == "player" ) and not actionIds[entry.id] then
						local action = Engine.CreateModel( root, "ztweaksAction_" .. entry.id )
						Engine.SetModelValue( Engine.CreateModel( action, "displayText" ), Z.ActionWords( entry, controller ) )
						Engine.SetModelValue( Engine.CreateModel( action, "action" ), R.PressAction( entry.id ) )
						table.insert( items, sharedAt, {
							model = action, properties = {}, ztweaksSharedRow = true, ztweaksActionId = entry.id
						} )
						sharedAt = sharedAt + 1
					end
				end
			end
			-- Older/loose ZPause pause wrappers still hide the shared entry from
			-- clients. Use the active bundle renderer, not a second personal menu.
			local openSettings = Z.DrawsSettingsRow() and Z.OpenFromPause or nil
			if B.SettingsRowOwner == "zbundle" and CoD.ZPauseSettings ~= nil then
				openSettings = CoD.ZPauseSettings.OpenFromPause
			end
			if not hasSettings and type( openSettings ) == "function" then
				local settings = Engine.CreateModel( root, "ztweaksSettings" )
				Engine.SetModelValue( Engine.CreateModel( settings, "displayText" ), CoD.ZTweaksSettings.EntryLabel() )
				Engine.SetModelValue( Engine.CreateModel( settings, "action" ), openSettings )
				table.insert( items, sharedAt, { model = settings, properties = {}, ztweaksSharedRow = true } )
			end

			if isHost and not hasRestart then
				local restartAt = #items + 1
				for index, item in ipairs( items ) do
					local display = item ~= nil and item.model ~= nil and Engine.GetModel( item.model, "displayText" ) or nil
					local value = display ~= nil and Engine.GetModelValue( display ) or nil
					if value == "MENU_END_GAME_CAPS" or value == "MENU_QUIT_GAME_CAPS" then
						restartAt = index
						break
					end
				end
				local restart = Engine.CreateModel( root, "ztweaksRestart" )
				Engine.SetModelValue( Engine.CreateModel( restart, "displayText" ), "MENU_RESTART_LEVEL_CAPS" )
				Engine.SetModelValue( Engine.CreateModel( restart, "action" ), function ( self, element, activeController, ... )
					if B.HostStatus( activeController ) == "HOST" then return RestartGame( self, element, activeController, ... ) end
				end )
				table.insert( items, restartAt, { model = restart, properties = {} } )
			end
			if isHost and not hasEndGame then
				local finish = Engine.CreateModel( root, "ztweaksEndGame" )
				Engine.SetModelValue( Engine.CreateModel( finish, "displayText" ), "MENU_END_GAME_CAPS" )
				Engine.SetModelValue( Engine.CreateModel( finish, "action" ), R.EndGame )
				table.insert( items, { model = finish, properties = {}, ztweaksLifecycleRow = true } )
			end
			R.MoveSharedAfterLifecycle( items )
		end )
	end
	return true
end

R.Watch = function ( parent )
	-- T7x installs its own StartMenuGameOptions datasource after core_mod has
	-- loaded. Keep watching so that replacement is wrapped too; Install's flag
	-- makes stable stock/T7 datasources a no-op between checks.
	R.ExpandBundleList()
	R.Install()
	local timerOk, timer = pcall( NewElementTimer, 500, true, function ()
		R.Watch( parent )
	end )
	if timerOk and timer ~= nil then
		pcall( function () parent:addElement( timer ) end )
	end
end

if LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil and not CoD.ZTweaksPauseWatchStarted then
	CoD.ZTweaksPauseWatchStarted = true
	R.Watch( LUI.roots.UIRootFull )
end
