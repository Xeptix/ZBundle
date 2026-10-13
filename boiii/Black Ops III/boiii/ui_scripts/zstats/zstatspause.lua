-- Add ZStats Settings to BO3's active Zombies pause-menu data source.
-- T7x may replace the data source after core_mod loads, so the wrapper watcher
-- remains active and idempotently wraps each replacement object.

local P = {}
local Z = CoD.ZStatsSettings
local B = CoD.ZBundleSettings
local NewElementTimer = LUI ~= nil and LUI.UITimer ~= nil and LUI.UITimer.newElementTimer or nil
pcall( require, "ui.uieditor.widgets.StartMenu.StartMenu_GameOptions_ZM" )

-- BO3's stock Zombies pause widget exposes a five-row viewport. Standalone
-- ZStats can add both its client HUD action and Settings below those rows, so
-- grow the list while ZStats owns the shared rows. A complete ZBundle claims
-- the owners first and its loader/renderer remains responsible for the same
-- expansion there.
P.ExpandOwnedList = function ()
	local widget = CoD.StartMenu_GameOptions_ZM
	if widget == nil or type( widget.new ) ~= "function" or widget.zstatsOwnedListWrapped then return false end
	local originalNew = widget.new
	widget.new = function ( menu, controller )
		local panel = originalNew( menu, controller )
		if panel ~= nil and panel.buttonList ~= nil and ( Z.DrawsActionRows() or Z.DrawsSettingsRow() ) then
			local actionCount = 0
			if Z.DrawsActionRows() and type( B.GetActions ) == "function" then
				local ok, actions = pcall( B.GetActions, controller )
				if ok and type( actions ) == "table" then actionCount = #actions end
			end
			local settingsCount = Z.DrawsSettingsRow() and 1 or 0
			local count = math.min( 11, math.max( 5, 5 + actionCount + settingsCount ) )
			panel.buttonList:setTopBottom( true, false, 4.91, 4.91 + count * 33.6 )
			panel.buttonList:setVerticalCount( count )
		end
		return panel
	end
	widget.zstatsOwnedListWrapped = true
	return true
end

P.IsSettings = function ( value )
	return value == "ZSTATS SETTINGS" or value == "ZBUNDLE SETTINGS"
		or value == Engine.Localize( "ZSTATS SETTINGS" ) or value == Engine.Localize( "ZBUNDLE SETTINGS" )
end

P.AmHost = function ( controller )
	return B.HostStatus( controller ) == "HOST"
end

P.Press = function ( id )
	return function ( self, element, controller, param, menu )
		local action = B.ActionById[id]
		if action == nil or type( action.action ) ~= "function" or not B.ActionEnabled( action, controller ) then return end
		if action.authority ~= "player" and not P.AmHost( controller ) then return end
		pcall( action.action, controller, action, menu, element, self )
	end
end

P.Install = function ()
	local source = DataSources ~= nil and DataSources.StartMenuGameOptions or nil
	if source == nil or source.prepare == nil or source.prepare == source.zstatsPrepareWrapper then
		return false
	end

	local prepare = source.prepare
	local wrapper = function ( controller, list, filter )
		prepare( controller, list, filter )
		pcall( function ()
			if list == nil or not CoD.isZombie then
				return
			end

			local name = list.customDataSourceHelper
			local items = name ~= nil and list[name] or nil
			if items == nil then return end

			local settingsAt = #items + 1
			local hasSettings = false
			local actionIds = {}
			for index, item in ipairs( items ) do
				if item ~= nil and item.zstatsActionId ~= nil then
					actionIds[item.zstatsActionId] = true
				end
				local display = item ~= nil and item.model ~= nil and Engine.GetModel( item.model, "displayText" ) or nil
				local value = display ~= nil and Engine.GetModelValue( display ) or nil
				local existingAction = item ~= nil and item.zstatsActionId ~= nil and B.ActionById[item.zstatsActionId] or nil
				if display ~= nil and existingAction ~= nil then
					Engine.SetModelValue( display, B.ActionLabel( existingAction, controller ) )
					if existingAction.id == "zstats_toggle_hud" then
						local actionModel = Engine.GetModel( item.model, "action" )
						if actionModel ~= nil then Engine.SetModelValue( actionModel, P.Press( existingAction.id ) ) end
					end
				end
				if P.IsSettings( value ) then
					hasSettings = true
					Engine.SetModelValue( display, Z.EntryLabel() )
					if settingsAt == #items + 1 then settingsAt = index end
				end
				if value == "TOGGLE ZSTATS HUD" or value == Engine.Localize( "TOGGLE ZSTATS HUD" ) then
					actionIds.zstats_toggle_hud = true
					-- A complete ZBundle normally lets ZPause draw the shared action
					-- rows. Upgrade that existing row to ZStats' menu-aware handler so
					-- the stock StartMenu_Main instance can be closed correctly.
					local actionModel = item ~= nil and item.model ~= nil and Engine.GetModel( item.model, "action" ) or nil
					if actionModel ~= nil then
						Engine.SetModelValue( actionModel, P.Press( "zstats_toggle_hud" ) )
						item.zstatsActionId = "zstats_toggle_hud"
					end
				end
			end
			local root = ListHelper_GetListHelperModel( list, true )
			if root == nil then return end

			if Z.DrawsActionRows() then
				for _, entry in ipairs( B.GetActions( controller ) ) do
					if not actionIds[entry.id] then
						local action = Engine.CreateModel( root, "zstatsAction_" .. entry.id )
						Engine.SetModelValue( Engine.CreateModel( action, "displayText" ), B.ActionLabel( entry, controller ) )
						Engine.SetModelValue( Engine.CreateModel( action, "action" ), P.Press( entry.id ) )
						table.insert( items, settingsAt, {
							model = action, properties = {}, zstatsSharedRow = true, zstatsActionId = entry.id
						} )
						settingsAt = settingsAt + 1
					end
				end
			end

			if not hasSettings and Z.DrawsSettingsRow() then
				local settings = Engine.CreateModel( root, "zstatsSettings" )
				Engine.SetModelValue( Engine.CreateModel( settings, "displayText" ), Z.EntryLabel() )
				Engine.SetModelValue( Engine.CreateModel( settings, "action" ), Z.OpenFromPause )
				table.insert( items, settingsAt, { model = settings, properties = {}, zstatsSharedRow = true } )
			end
		end )
	end
	source.zstatsWrapped = true
	source.zstatsPrepareWrapper = wrapper
	source.prepare = wrapper
	return true
end

P.Watch = function ( parent )
	P.ExpandOwnedList()
	P.Install()
	local timerOk, timer = pcall( NewElementTimer, 500, true, function ()
		P.Watch( parent )
	end )
	if timerOk and timer ~= nil then
		pcall( function () parent:addElement( timer ) end )
	end
end

if LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil and not CoD.ZStatsPauseWatchStarted then
	CoD.ZStatsPauseWatchStarted = true
	P.Watch( LUI.roots.UIRootFull )
end
