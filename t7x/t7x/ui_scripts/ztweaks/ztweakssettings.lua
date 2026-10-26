-- ZTweaks lobby settings for Black Ops III.
-- Rows come from src/settings.json through tools/generate_settings.py.

-- A selected ZBundle fastfile and an Omni loose route can both ask Lua to
-- load this owner under different module names.  Treat the already-installed
-- runtime as authoritative so the second route cannot reset tables, hooks, or
-- menu state underneath the first one.
if CoD.ZTweaksSettings ~= nil and CoD.ZTweaksSettings.RuntimeLoaded == true then
	return
end

require( "ztweakssettingsdata" )
require( "ztweakslocalization" )
local L = CoD.ZTweaksLocalization
L.Notices.Install( "t7" )
require( "ui.uieditor.widgets.Scrollbars.verticalScrollbar" )

local Z = CoD.ZTweaksSettings
Z.saved = {}
Z.dirty = false
Z.loaded = false
Z.pending = {}
Z.PersistenceDiagnostics = { status = "read_pending" }
Z.ByKey = {}
Z.AllRows = {}
Z.StorageRows = {}
Z.RowsByStorageSlot = {}
for _, page in ipairs( Z.Pages ) do
	for _, row in ipairs( page.rows ) do
		Z.ByKey[row.key] = row
		table.insert( Z.AllRows, row )
		Z.RowsByStorageSlot[row.storageSlot] = Z.RowsByStorageSlot[row.storageSlot] or {}
		table.insert( Z.RowsByStorageSlot[row.storageSlot], row )
		-- ZT2 was positional and predates packed slots. Preserve exactly one
		-- legacy row per original slot while importing that old record.
		if row.storageSlot <= 33 and (Z.StorageRows[row.storageSlot] == nil or row.storageLegacyIndex == true) then
			Z.StorageRows[row.storageSlot] = row
		end
	end
end

-- Hidden bundle-component state. Slot 37 already packs the four-value
-- Starting Weapon Upgraded choice (factor 1, radix 4) and one challenge bit
-- (factor 4, radix 2); factor 8 is the next non-overlapping bit. Keep this out
-- of Z.Pages so it appears only on the bundle-owned MODS category.
Z.EnabledStorageRow = {
	dvar = "zt_enabled", key = "zen", keys = { "on", "of" },
	default = "1", values = { "1", "0" }, labels = { "ON", "OFF" },
	storageSlot = 37, storageFactor = 8, storageRadix = 2
}
Z.ByKey[Z.EnabledStorageRow.key] = Z.EnabledStorageRow
table.insert( Z.AllRows, Z.EnabledStorageRow )
Z.RowsByStorageSlot[37] = Z.RowsByStorageSlot[37] or {}
table.insert( Z.RowsByStorageSlot[37], Z.EnabledStorageRow )

-- Shared lobby registry for the eventual merged ZBundle settings screen.
-- Components may register tabs before or after ZTweaks loads; duplicate ids
-- replace their earlier definition so loose development modules can coexist.
CoD.ZBundleSettings = CoD.ZBundleSettings or {}
local B = CoD.ZBundleSettings

-- This module is linked through core_mod, so the shared artwork is present.
-- Loose ui_scripts owners must leave this false and use the panel fallback.
B.BackgroundImageAvailable = false
B.Tabs = B.Tabs or {}
B.TabById = B.TabById or {}
B.Components = B.Components or {}
B.ComponentById = B.ComponentById or {}
B.Actions = B.Actions or {}
B.ActionById = B.ActionById or {}
B.Localizers = B.Localizers or {}
Z.OwnerWords = function ( english, row, tab )
	if english == nil then return "" end
	english = tostring( english )
	local owner = type( row ) == "table" and ( row.sourceOwner or row.localizationOwner ) or nil
	owner = owner or ( type( tab ) == "table" and tab.owner or nil )
	local provider = owner ~= nil and B.Localizers[owner] or nil
	if type( provider ) == "table" then provider = provider.text end
	if type( provider ) == "function" then
		local ok, result = pcall( provider, english, { row = row, tab = tab, owner = owner } )
		if ok and type( result ) == "string" and result ~= english then return result end
	end
	if owner == "ztweaks" or ( L.ShellKeys or {} )[english] == true then return L.Text( english ) end
	return english
end
-- The two published spellings have opposite tuple order. Repair a missing
-- alias by capability, even when another registry already advertises v5.
if B.RowOverride == nil and type( B.RowForced ) == "function" then
	B.RowOverride = function ( row, tab, controller )
		local locked, value = B.RowForced( row, tab, controller )
		return value, locked
	end
end
-- Read-only is a behavior contract, not just a details-panel label.  Keep one
-- shared predicate so whichever Z mod wins the renderer load race cannot turn
-- compatibility/CHANGED rows back into ordinary DEFAULT/value selectors.
if ( tonumber( B.RowWritableVersion ) or 0 ) < 3 then
	B.RowEnabled = function ( row, tab, controller )
		if type( row ) ~= "table" then return false end
		local enabled = row.enabled
		if type( enabled ) == "function" then
			local ok, result = pcall( enabled, controller or Engine.GetPrimaryController(), row, tab )
			if not ok then return false end
			enabled = result == true or result == 1 or result == "1"
		end
		return enabled ~= false and enabled ~= 0 and enabled ~= "0"
	end
	B.RowOverride = function ( row, tab, controller )
		if type( row ) ~= "table" then return nil, false end
		local value = row.forcedValue
		if type( value ) == "function" then
			local ok, result = pcall( value, controller or Engine.GetPrimaryController(), row, tab )
			if not ok then return nil, true end
			value = result
		end
		if value == nil then return nil, false end
		if value == true then value = "1" elseif value == false then value = "0" end
		if type( value ) ~= "string" and type( value ) ~= "number" then return nil, true end
		return tostring( value ), true
	end
	B.RowUnavailable = function ( row, tab, controller )
		local _, locked = B.RowOverride( row, tab, controller )
		return locked or not B.RowEnabled( row, tab, controller )
	end
	B.RowReason = function ( row, tab, controller )
		local value, locked = B.RowOverride( row, tab, controller )
		if locked then
			local reason = row.overrideReason
			if type( reason ) == "function" then
				local ok, result = pcall( reason, controller or Engine.GetPrimaryController(), row, tab )
				reason = ok and result or nil
			end
			if reason ~= nil and reason ~= false then return tostring( reason ) end
			-- Keep shared registry output owner-neutral. The renderer composes and
			-- translates the fallback with the row owner's value at the draw site.
			return nil
		end
		if not B.RowEnabled( row, tab, controller ) then return row.disabledReason or row.hint or "" end
		return row.hint or ""
	end
	B.RowWritable = function ( row, tab, controller )
		if type( row ) ~= "table" then return false end
		if row.kind == "button" then return false end
		if row.boundary == "READ ONLY" or row.ztReadOnly == true
			or row.readOnly == true or row.writable == false or row.editable == false then
			return false
		end
		if tab ~= nil and ( tab.role == "report" or tab.role == "changed" ) then return false end
		return not B.RowUnavailable( row, tab, controller ) and #( row.values or {} ) > 0
	end
	B.RowWritableVersion = 3
end

Z.RowReasonWords = function ( row, tab, controller )
	local value, locked = B.RowOverride( row, tab, controller )
	local reason = B.RowReason( row, tab, controller )
	if locked and ( reason == nil or reason == "" ) then
		if value == nil then return L.Text( "Override unavailable" ) end
		return L.Format( "Locked to {value}", { value = Z.OwnerWords( Z.ValueLabel( row, value ), row, tab ) } )
	end
	return Z.OwnerWords( reason or "", row, tab )
end
-- Authority is an edit privilege, not a gameplay scope or forced value.
if ( tonumber( B.RowWritableVersion ) or 0 ) < 5 then
	local priorEnabled, priorUnavailable, priorReason, priorWritable = B.RowEnabled, B.RowUnavailable, B.RowReason, B.RowWritable
	B.HostStatus = function ( controller )
		controller = controller or Engine.GetPrimaryController()
		local lobby = Enum.LobbyType.LOBBY_TYPE_PRIVATE
		local okGame, gameActive = pcall( Engine.IsLobbyActive, Enum.LobbyType.LOBBY_TYPE_GAME )
		local okInGame, inGame = pcall( Engine.IsInGame )
		if not ( okInGame and ( inGame == true or inGame == 1 ) ) and
			( not okGame or ( gameActive ~= true and gameActive ~= false and gameActive ~= 0 and gameActive ~= 1 ) ) then return "UNKNOWN" end
		if okGame and ( gameActive == true or gameActive == 1 ) or okInGame and ( inGame == true or inGame == 1 ) then lobby = Enum.LobbyType.LOBBY_TYPE_GAME end
		local ok, modelValue = pcall( function ()
			local root = DataSources.LobbyRoot.getModel( controller )
			local name = lobby == Enum.LobbyType.LOBBY_TYPE_GAME and "gameClient.isHost" or "privateClient.isHost"
			local model = Engine.GetModel( root, name )
			if model ~= nil then return Engine.GetModelValue( model ) end
		end )
		if ok and modelValue ~= nil then
			if modelValue == true or modelValue == 1 or modelValue == "1" then return "HOST" end
			if modelValue == false or modelValue == 0 or modelValue == "0" then return "CLIENT" end
		end
		local directOk, direct = pcall( Engine.IsLobbyHost, lobby )
		if directOk then
			if direct == true or direct == 1 then return "HOST" end
			if direct == false or direct == 0 then return "CLIENT" end
		end
		return "UNKNOWN"
	end
	B.RowAuthority = function ( row, tab )
		if tab ~= nil and tab.role == "report" then return "player" end
		local authority = row ~= nil and row.authority or nil
		if authority == nil and tab ~= nil then authority = tab.authority end
		return authority == "player" and "player" or "host"
	end
	B.RowHostLocked = function ( row, tab, controller )
		return row ~= nil and B.RowAuthority( row, tab ) == "host" and B.HostStatus( controller ) ~= "HOST"
	end
	B.RowHostValue = function ( row, tab, controller )
		return B.RowHostLocked( row, tab, controller ) and "HOST VALUE UNAVAILABLE" or nil
	end
	B.RowEnabled = function ( row, tab, controller )
		return not B.RowHostLocked( row, tab, controller ) and priorEnabled( row, tab, controller )
	end
	B.RowUnavailable = function ( row, tab, controller )
		return B.RowHostLocked( row, tab, controller ) or priorUnavailable( row, tab, controller )
	end
	B.RowReason = function ( row, tab, controller )
		if B.RowHostLocked( row, tab, controller ) then
			return B.HostStatus( controller ) == "UNKNOWN" and "Host status unknown; this host-controlled setting is locked." or "Only the host can change this setting. The host's current value is unavailable here."
		end
		return priorReason( row, tab, controller )
	end
	B.RowWritable = function ( row, tab, controller )
		return not B.RowHostLocked( row, tab, controller ) and priorWritable( row, tab, controller )
	end
	-- Local host-owned mod toggles must not hide a client's personal settings.
	B.TabEnabled = function ( tab, controller )
		if tab == nil then return false end
		if tab.role == "mods" then return true end
		local component = B.ComponentById[tab.owner]
		if B.HostStatus( controller ) == "HOST" and component ~= nil and not B.ComponentEnabled( component, controller ) then return false end
		if type( tab.enabled ) ~= "function" then return tab.enabled ~= false end
		local ok, value = pcall( tab.enabled, controller, tab )
		return ok and value ~= false
	end
	B.RowWritableVersion = 5
end
B.RowForced = B.RowForced or function ( row, tab, controller )
	local value, locked = B.RowOverride( row, tab, controller )
	return locked, value
end
B.RegisterComponent = B.RegisterComponent or function ( component )
	if type( component ) ~= "table" or type( component.id ) ~= "string" or component.id == "" then return end
	local existing = B.ComponentById[component.id]
	if existing ~= nil then
		for key, value in pairs( component ) do existing[key] = value end
		return existing
	end
	B.ComponentById[component.id] = component
	table.insert( B.Components, component )
	return component
end
B.GetComponents = B.GetComponents or function ()
	local result = {}
	for _, component in ipairs( B.Components ) do table.insert( result, component ) end
	table.sort( result, function ( left, right )
		local leftOrder = tonumber( left.order ) or 1000
		local rightOrder = tonumber( right.order ) or 1000
		if leftOrder ~= rightOrder then return leftOrder < rightOrder end
		return tostring( left.label or left.id ) < tostring( right.label or right.id )
	end )
	return result
end
B.ComponentVersions = B.ComponentVersions or {}
B.ComponentVersion = B.ComponentVersion or function ( component, controller )
	if component == nil then return nil end
	local value = component.version or component.getVersion or B.ComponentVersions[component.id]
	if type( value ) == "function" then
		local ok, result = pcall( value, controller, component )
		value = ok and result or nil
	end
	if value == nil or value == "" then
		local legacy = {
			ztweaks = CoD.ZTweaksSettings,
			zpause = CoD.ZPauseSettings,
			zshare = CoD.ZShareSettings,
			zstats = CoD.ZStatsSettings
		}
		local settings = legacy[string.lower( tostring( component.id or "" ) )]
		if settings ~= nil then value = settings.Version or settings.version end
	end
	if value == nil or value == "" then return nil end
	return string.gsub( tostring( value ), "^%s*[vV]", "" )
end
B.ComponentVersionsText = B.ComponentVersionsText or function ( controller )
	local labels = {}
	for _, component in ipairs( B.GetComponents() ) do
		local label = string.upper( tostring( component.label or component.id or "MOD" ) )
		local version = B.ComponentVersion( component, controller ) or "?"
		table.insert( labels, label .. " v" .. version )
	end
	return table.concat( labels, " / " )
end
B.ComponentEnabled = B.ComponentEnabled or function ( component, controller )
	if component == nil or type( component.getEnabled ) ~= "function" then return true end
	local ok, value = pcall( component.getEnabled, controller, component )
	if not ok then return true end
	return value ~= false and value ~= 0 and value ~= "0"
end
B.SetComponentEnabled = B.SetComponentEnabled or function ( component, controller, enabled )
	if component == nil or type( component.setEnabled ) ~= "function" then return false end
	local ok = pcall( component.setEnabled, controller, enabled, component )
	return ok
end

-- A packaged mod and loose T7x ui_scripts share this registry but may load in
-- either order. Upgrade whichever registry implementation arrived first with
-- an authoritative live-menu state. Component callbacks still own persistence
-- and next-match behavior; the cache makes the requested state visible to the
-- open menu before a later dvar/storage read catches up.
B.ComponentEnabledOverrides = B.ComponentEnabledOverrides or {}
if ( tonumber( B.LiveComponentToggleVersion ) or 0 ) < 1 then
	local inheritedComponentEnabled = B.ComponentEnabled
	local inheritedSetComponentEnabled = B.SetComponentEnabled
	B.ComponentEnabled = function ( component, controller )
		if component ~= nil and component.id ~= nil and B.ComponentEnabledOverrides[component.id] ~= nil then
			return B.ComponentEnabledOverrides[component.id]
		end
		return inheritedComponentEnabled( component, controller )
	end
	B.SetComponentEnabled = function ( component, controller, enabled )
		local ok, accepted = inheritedSetComponentEnabled( component, controller, enabled )
		if ok == false or accepted == false then return false end
		if component ~= nil and component.id ~= nil then B.ComponentEnabledOverrides[component.id] = enabled == true end
		return true
	end
	B.LiveComponentToggleVersion = 1
end
B.RegisterTab = B.RegisterTab or function ( tab )
	if type( tab ) ~= "table" or type( tab.id ) ~= "string" or tab.id == "" then return end
	local existing = B.TabById[tab.id]
	if existing ~= nil then
		for key in pairs( existing ) do existing[key] = nil end
		for key, value in pairs( tab ) do existing[key] = value end
		return
	end
	B.TabById[tab.id] = tab
	table.insert( B.Tabs, tab )
	if tab.owner ~= nil and tab.owner ~= "zbundle" and B.ComponentById[tab.owner] == nil then
		B.RegisterComponent( { id = tab.owner, label = tab.ownerLabel or tab.owner, order = tab.ownerOrder or tab.order } )
	end
end
B.IsBundle = B.IsBundle or function ()
	return #B.GetComponents() > 1
end
B.RegisterAction = B.RegisterAction or function ( action )
	if type( action ) ~= "table" or type( action.id ) ~= "string" or action.id == "" then return end
	local existing = B.ActionById[action.id]
	if existing ~= nil then
		for key in pairs( existing ) do existing[key] = nil end
		for key, value in pairs( action ) do existing[key] = value end
		return
	end
	B.ActionById[action.id] = action
	table.insert( B.Actions, action )
end
B.GetActions = B.GetActions or function ( controller )
	local result = {}
	for _, action in ipairs( B.Actions ) do
		local shown = true
		if type( action.visible ) == "function" then
			local ok, value = pcall( action.visible, controller, action )
			shown = ok and value ~= false
		end
		if shown and B.ComponentEnabled( B.ComponentById[action.owner], controller ) then table.insert( result, action ) end
	end
	table.sort( result, function ( left, right )
		local leftOrder = tonumber( left.order ) or 1000
		local rightOrder = tonumber( right.order ) or 1000
		if leftOrder ~= rightOrder then return leftOrder < rightOrder end
		return tostring( left.id ) < tostring( right.id )
	end )
	return result
end
B.ActionLabel = B.ActionLabel or function ( action, controller )
	local label = action ~= nil and action.label or nil
	if type( label ) == "function" then
		local ok, value = pcall( label, controller, action )
		label = ok and value or nil
	end
	return tostring( label or ( action ~= nil and action.id ) or "" )
end
Z.ActionWords = function ( action, controller )
	local english = B.ActionLabel( action, controller )
	if type( action ) ~= "table" then return english end
	return Z.OwnerWords( english, action, { owner = action.owner } )
end
B.ActionEnabled = B.ActionEnabled or function ( action, controller )
	if action == nil or type( action.enabled ) ~= "function" then return true end
	local ok, value = pcall( action.enabled, controller, action )
	if not ok then return true end
	return value ~= false
end
B.SettingsRowOwner = B.SettingsRowOwner or "ztweaks"
B.ActionRowsOwner = B.ActionRowsOwner or "ztweaks"
Z.DrawsSettingsRow = function () return B.SettingsRowOwner == "ztweaks" end
Z.DrawsActionRows = function () return B.ActionRowsOwner == "ztweaks" end
B.TabVisible = B.TabVisible or function ( tab, controller )
	if tab == nil then return false end
	if type( tab.visible ) ~= "function" then return tab.visible ~= false end
	local ok, value = pcall( tab.visible, controller, tab )
	return ok and value ~= false
end
B.TabEnabled = B.TabEnabled or function ( tab, controller )
	if tab == nil then return false end
	if tab.role == "mods" then return true end
	local component = B.ComponentById[tab.owner]
	if component ~= nil and not B.ComponentEnabled( component, controller ) then return false end
	if type( tab.enabled ) ~= "function" then return tab.enabled ~= false end
	local ok, value = pcall( tab.enabled, controller, tab )
	return ok and value ~= false
end

-- Disabled components retain their registered categories so the bundle's
-- shape remains discoverable. The cells are grey and non-interactive until
-- MODS enables their owner again. Upgrade an older load-order winner too.
if ( tonumber( B.DisabledTabVisibilityVersion ) or 0 ) < 1 then
	B.GetTabs = function ( controller )
		local result = {}
		for _, tab in ipairs( B.Tabs ) do
			if B.TabVisible( tab, controller ) then table.insert( result, tab ) end
		end
		if B.IsBundle() and B.ModsTab ~= nil and B.TabVisible( B.ModsTab, controller ) then table.insert( result, B.ModsTab ) end
		table.sort( result, function ( left, right )
			if left.role == "mods" or right.role == "changed" then return true end
			if right.role == "mods" or left.role == "changed" then return false end
			local leftComponent = B.ComponentById[left.owner]
			local rightComponent = B.ComponentById[right.owner]
			local leftOwnerOrder = tonumber( leftComponent and leftComponent.order ) or 1000
			local rightOwnerOrder = tonumber( rightComponent and rightComponent.order ) or 1000
			if leftOwnerOrder ~= rightOwnerOrder then return leftOwnerOrder < rightOwnerOrder end
			local leftOrder = tonumber( left.order ) or 1000
			local rightOrder = tonumber( right.order ) or 1000
			if leftOrder ~= rightOrder then return leftOrder < rightOrder end
			return tostring( left.label or left.id ) < tostring( right.label or right.id )
		end )
		return result
	end
	B.DisabledTabVisibilityVersion = 1
end

B.RegisterComponent( {
	id = "ztweaks", label = "ZTweaks", version = Z.Version, order = 0,
	description = "Gameplay rules, loadouts, pacing, world, and challenge settings.", boundary = "NEXT MATCH",
	getEnabled = function () local value = Z.Get( "zt_enabled" ); return value == "" or value ~= "0" end,
	setEnabled = function ( controller, enabled )
		local value = enabled and "1" or "0"
		Z.TabSet( controller, "zt_enabled", value, Z.EnabledStorageRow )
		Z.Flush( controller )
	end
} )

-- Every component must own its writes even when another Z mod supplies the
-- visible shared renderer.  Without these callbacks a ZShare/ZPause-owned
-- ZBundle page falls back to changing the live dvar only: the value is not
-- reflected in ZTweaks' numeric save record, and a generic reset may try to
-- write an empty string into an already registered numeric dvar.  Accept both
-- registry get signatures used by released shells while keeping persistence
-- and semantic-default handling here, under ZTweaks' ownership.
Z.TabGet = function ( controller, dvar, row )
	if type( dvar ) == "table" and row == nil then dvar = controller end
	return Z.Get( dvar )
end

Z.TabSet = function ( controller, dvar, value, row )
	if value == "" and row ~= nil and row.default ~= nil then value = tostring( row.default ) end
	Z.Set( controller, dvar, value )
	local clear = row ~= nil and Z.IsDefault( value, row )
	if clear then Z.saved[dvar] = nil else Z.saved[dvar] = value end
	if not Z.loaded then Z.pending[dvar] = { clear = clear, value = value } end
	Z.dirty = true
end

Z.TabFlush = function ( controller )
	Z.Flush( controller )
end

Z.TabReset = function ( controller )
	for _, page in ipairs( Z.Pages or {} ) do
		for _, row in ipairs( page.rows or {} ) do
			if B.RowWritable( row, nil, controller ) and row.dvar ~= nil and row.dvar ~= "" then
				Z.TabSet( controller, row.dvar, tostring( row.default or "" ), row )
			end
		end
	end
	Z.Flush( controller )
end

for index, page in ipairs( Z.Pages ) do
	B.RegisterTab( {
		id = "ztweaks_" .. page.id,
		label = page.title,
		hint = page.hint,
		owner = "ztweaks",
		ownerLabel = "ZTweaks",
		order = index,
		rows = page.rows,
		get = Z.TabGet,
		set = Z.TabSet,
		flush = Z.TabFlush,
		reset = Z.TabReset
	} )
end

Z.ReportNames = {
	"auto_restart", "starting_round", "starting_points", "game_start_delay", "headshots_only",
	"perk_limit", "player_health", "player_speed", "random_starting_perks", "start_all_perks",
	"point_gain", "weapon_damage", "melee_damage", "no_explosive_self_damage", "fall_damage",
	"down_limit", "revive_time", "bleedout_time", "spawn_protection", "lose_perks_on_down", "keep_weapons_bleedout",
	"starting_weapon", "secondary_starting_weapon", "starting_weapon_upgraded", "starting_weapon_aat", "starting_ammo", "reserve_ammo",
	"starting_grenade", "max_grenades", "starting_equipment", "max_equipment",
	"zombie_health", "zombie_damage", "zombie_speed", "zombies_per_round", "round_delay", "zombie_spawn_rate",
	"start_power_on", "start_doors_open", "powerup_ground_time", "powerup_effect_time",
	"powerup_drop_rate", "powerup_max_per_round", "powerup_stacking", "box_quality", "box_lock", "box_price_multiplier", "fire_sale_box_price", "teddy_chance",
	"gobblegum_uses", "gobblegum_time", "gobblegum_rounds",
	"challenge_no_perks", "challenge_no_pap", "challenge_no_box", "challenge_wall_only",
	"challenge_starting_room", "challenge_one_box", "challenge_gun_game", "challenge_random_loadout", "challenge_random_rules", "box_no_repeat", "health_regen_delay", "round_bonus", "max_ammo_reload", "death_points_retained", "challenge_one_weapon_slot", "powerup_drop_filters", "disable_stock_aat", "wunderfizz_price_multiplier", "challenge_rising_damage", "pap_damage_multiplier", "fast_barrier_rebuild", "knife_lunge"
}

-- The gameplay HUD listener owns the clientuimodel report cache. Lobby pages
-- can read the last match's report; a new match epoch clears stale rows.
Z.ReportRead = function ( name )
	local report = CoD.ZTweaksCompat
	if report ~= nil and type( report.Read ) == "function" then
		return report.Read( name )
	end
	return "not_reported", ""
end

Z.ReportHint = function ( state, reason )
	if reason ~= "" then return reason end
	if state == "inherit" then return "GAME DEFAULT preserves this map's own behavior." end
	if state == "active" then return "ZTweaks applied this setting." end
	if state == "not_reported" then return "No gameplay compatibility report was received." end
	return "The gameplay compatibility report gave no further detail."
end

Z.ReportGet = function ( controller, dvar, row )
	-- Shared ZBundle renderers call get(dvar, row); the ZTweaks renderer
	-- historically calls get(controller, dvar, row). Support both shapes.
	if type( dvar ) == "table" and row == nil then row = dvar end
	if row ~= nil and row.ztReportName ~= nil then
		local state = Z.ReportRead( row.ztReportName )
		if state ~= "not_reported" then return state end
	end
	if row ~= nil and row.ztReportSnapshot ~= nil and row.ztReportSnapshot ~= "" then
		return tostring( row.ztReportSnapshot )
	end
	return "not_reported"
end

B.RegisterTab( {
	id = "ztweaks_report", label = "COMPATIBILITY", hint = "Applied, degraded, unavailable, and inherited tweak status.",
	owner = "ztweaks", ownerLabel = "ZTweaks", order = 90, role = "report",
	rows = function ()
		local rows = {}
		for _, name in ipairs( Z.ReportNames ) do
			local state, reason = Z.ReportRead( name )
			table.insert( rows, {
				dvar = "zt_ui_status_" .. name, key = "report_" .. name,
				label = L.ReportLabels[name] or string.upper( string.gsub( name, "_", " " ) ), hint = Z.ReportHint( state, reason ),
				default = state, boundary = "READ ONLY", scope = "HOST / SHARED", kind = "choice",
				values = { state }, labels = { string.upper( string.gsub( state, "_", " " ) ) },
				ztReadOnly = true, readOnly = true, writable = false, editable = false,
				ztReportSnapshot = state, ztReportName = name
			} )
		end
		return rows
	end,
	get = Z.ReportGet,
	set = function () end
} )
B.RegisterTab( {
	id = "zbundle_changed", label = "CHANGED", hint = "Settings changed from their semantic defaults across every registered mod.",
	owner = "zbundle", ownerLabel = "ZBundle", order = 1000000, role = "changed",
	rows = function ()
		local rows = {}
		for _, tab in ipairs( B.Tabs ) do
			if tab.role ~= "report" and tab.role ~= "changed" and tab.role ~= "mods" then
				for _, row in ipairs( Z.TabRows( tab ) ) do
					if row.kind ~= "button" and not B.RowHostLocked( row, tab ) then
					local current = Z.RowGet( row, tab )
					if not Z.IsDefault( current, row ) then
						local copy = {}
						for key, value in pairs( row ) do copy[key] = value end
						local currentLabel = string.upper( tostring( current ) )
						for index, value in ipairs( row.values or {} ) do
							if Z.Same( current, value ) then currentLabel = row.labels[index] or currentLabel; break end
						end
						local sourceOwner = row.sourceOwner or row.localizationOwner or tab.owner
						copy.label = L.Format( "{owner} - {setting}", { owner = string.upper( tostring( tab.ownerLabel or tab.owner or "MOD" ) ), setting = Z.OwnerWords( row.label, row, tab ) } )
						copy.hint = L.Format( "{hint}  Current value from {owner}.", { hint = Z.OwnerWords( row.hint, row, tab ), owner = tostring( tab.ownerLabel or tab.owner or "MOD" ) } )
						copy.sourceOwner = sourceOwner
						copy.localizationOwner = sourceOwner
						copy.labelKey, copy.hintKey, copy.choiceKeys = nil, nil, nil
						copy.boundaryKey, copy.scopeKey = nil, nil
						copy.key, copy.keys, copy.storageSlot = nil, nil, nil
						copy.storageFactor, copy.storageRadix, copy.storageLegacyIndex = nil, nil, nil
						copy.boundary = "READ ONLY"
						copy.default = current
						copy.values = { current }
						copy.labels = { currentLabel }
						copy.ztReadOnly = true
						copy.readOnly = true
						copy.writable = false
						copy.editable = false
						table.insert( rows, copy )
					end
					end
				end
			end
		end
		return rows
	end
} )

B.ModsTab = B.ModsTab or {
	id = "zbundle_mods", label = "MODS", hint = "Enable or disable each installed ZBundle component.",
	owner = "zbundle", ownerLabel = "ZBundle", order = -1000000, role = "mods",
	rows = function ()
		local rows = {}
		for _, component in ipairs( B.GetComponents() ) do
			table.insert( rows, {
				dvar = "zbundle_component_" .. component.id, key = "bundle_component_" .. component.id,
				label = string.upper( tostring( component.label or component.id ) ), hint = component.description or "Enable or disable this ZBundle component.",
				boundary = component.boundary or "NEXT MATCH", scope = "HOST / SHARED", kind = "choice", default = "1",
				values = { "0", "1" }, labels = { "OFF", "ON" }, ztComponent = component,
				ztReadOnly = type( component.setEnabled ) ~= "function"
			} )
		end
		return rows
	end,
	get = function ( dvar, row ) return B.ComponentEnabled( row.ztComponent, Engine.GetPrimaryController() ) and "1" or "0" end,
	set = function ( controller, dvar, value, row ) B.SetComponentEnabled( row.ztComponent, controller, value ~= "0" ) end
}

Z.Same = function ( a, b )
	local na = tonumber( a )
	local nb = tonumber( b )
	if na ~= nil and nb ~= nil then
		return na == nb
	end
	return a == b
end

Z.IsDefault = function ( current, row )
	return current == "" or Z.Same( current, row.default )
end

-- Menu-local cursor intent keeps a just-picked value selected even when the
-- owner normalizes that value to the row's semantic default.  It is cleared
-- on open/reset, so a fresh screen still truthfully starts on DEFAULT.
Z.Picked = Z.Picked or {}

Z.PickedKey = function ( row, tab )
	return tostring( tab ~= nil and tab.owner or "" ) .. "|" .. tostring( row.dvar or row.key or "" )
end

Z.SetPicked = function ( row, tab, value, observed )
	if row == nil then return end
	Z.Picked[Z.PickedKey( row, tab )] = { value = value, observed = observed }
end

Z.ClearPicked = function ()
	Z.Picked = {}
end

Z.ShowsDefault = function ( current, row, tab )
	local key = Z.PickedKey( row, tab )
	local picked = Z.Picked[key]
	if picked ~= nil and not ( Z.Same( current, picked.observed ) or Z.Same( current, picked.value ) ) then
		Z.Picked[key] = nil
		picked = nil
	end
	if not Z.IsDefault( current, row ) then return false end
	if picked == nil then return true end
	return picked.value == nil or picked.value == ""
end

Z.SemanticDefault = function ( row )
	if row == nil or row.default == nil then return "" end
	return tostring( row.default )
end

-- Display the effective value, not the empty persistence sentinel.
Z.ValueLabel = function ( row, current )
	if current == nil or current == "" then current = row.default end
	for index, value in ipairs( row.values or {} ) do
		if Z.Same( current, value ) then return ( row.labels or {} )[index] or tostring( value ) end
	end
	return string.upper( tostring( current or "UNAVAILABLE" ) )
end

Z.ButtonAvailable = function ( row, tab, controller )
	return not B.RowUnavailable( row, tab, controller ) and row.readOnly ~= true
		and row.ztReadOnly ~= true and row.writable ~= false and row.editable ~= false
		and row.boundary ~= "READ ONLY"
end

-- Every row kind participates, including buttons: an absent baseline made
-- older bundle MODS pages rebuild on every poll. Pure reads, never actions.
Z.AvailabilitySnapshot = function ( menu, controller )
	local parts = {}
	for _, row in ipairs( Z.TabRows( menu.ztActiveTab ) ) do
		local tab = row.ztSourceTab or menu.ztActiveTab
		local value, locked = B.RowOverride( row, tab, controller )
		local current = Z.RowGet( row, tab, controller )
		for _, part in ipairs( { tostring( row.dvar ), tostring( B.RowEnabled( row, tab, controller ) ),
			tostring( B.RowWritable( row, tab, controller ) ), tostring( locked ), tostring( value ),
			tostring( current ), tostring( B.RowReason( row, tab, controller ) ) } ) do
			parts[#parts + 1] = tostring( #part ) .. ":" .. part
		end
	end
	return table.concat( parts, "|" )
end

Z.Get = function ( dvar )
	local ok, value = pcall( Engine.DvarString, nil, dvar )
	if ok and type( value ) == "string" then
		return value
	end
	return ""
end

Z.Set = function ( controller, dvar, value )
	pcall( Engine.SetDvar, dvar, value )
	if Z.Get( dvar ) ~= value then
		Engine.Exec( controller, "set " .. dvar .. " \"" .. value .. "\"" )
	end
end

-- BO3 does not archive mod dvars. Persist each setting in its own numeric
-- loadout field. ZPause uses customClassName in this same mod save whenever
-- its loose UI is stacked with ZTweaks, so ZTweaks must never write those
-- names or the two menus erase one another's records.
Z.STORAGE = Enum.StorageFileType.STORAGE_ZM_LOADOUTS_OFFLINE
-- 100/101 are the original numeric layout. 102/103 move two 1.2 rows away
-- from the bundle enable bit; old records are decoded before the new write.
Z.NUMERIC_FORMAT = 102
Z.PREVIOUS_NUMERIC_FORMAT = 100
Z.LEGACY_POSITIONAL_FORMAT = "ZT2"
Z.LEGACY_FORMAT = "ZT1"
Z.LEGACY_ENTRY = 5
Z.VALUE_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
Z.ENDGAME_MARKER = "EG1!!"

Z.LoadoutRoot = function ( controller )
	local root = nil
	pcall( function ()
		root = Engine.StorageGetBuffer( controller, Z.STORAGE ).cacLoadouts
	end )
	return root
end

Z.MetaField = function ( controller )
	local root = Z.LoadoutRoot( controller )
	if root == nil then return nil end
	local field = nil
	pcall( function () field = root.customclass[0].primaryattachment5 end )
	return field
end

Z.ValueField = function ( controller, row )
	local root = Z.LoadoutRoot( controller )
	if root == nil or row.storageSlot == nil then return nil end
	local field = nil
	pcall( function ()
		if row.storageSlot <= 10 then
			field = root.customclass[row.storageSlot - 1].primaryattachment6
		elseif row.storageSlot <= 20 then
			field = root.customclass[row.storageSlot - 11].primaryattachment4
		elseif row.storageSlot <= 30 then
			field = root.customclass[row.storageSlot - 21].primaryattachment3
		elseif row.storageSlot <= 40 then
			field = root.customclass[row.storageSlot - 31].primaryattachment7
		else
			field = root.customclass[row.storageSlot - 41].primaryattachment8
		end
	end )
	return field
end

Z.ReadMeta = function ( controller )
	local field = Z.MetaField( controller )
	if field == nil then return nil end
	local ok, raw = pcall( field.get, field )
	if not ok then return nil end
	local value = tonumber( raw )
	if value == nil or value ~= math.floor( value ) then return nil end
	return value
end

-- Read the former class-name record only for one-time ZT1/ZT2 migration.
-- This function is deliberately read-only so a stacked ZPause record survives.
Z.ReadLegacyText = function ( controller )
	local ok, text = pcall( function ()
		local text = ""
		local names = Z.LoadoutRoot( controller ).customClassName
		if names == nil then return nil end
		for index = 0, 31 do
			local field = names[index]
			if field == nil then return nil end
			local part = field:get()
			if type( part ) ~= "string" then return nil end
			if part == "" then return text end
			text = text .. part
		end
		return text
	end )
	if not ok then return nil end
	return text
end

Z.Read = function ( controller )
	local saved = {}
	local meta = Z.ReadMeta( controller )
	if meta == nil then return nil, false, "read_unavailable" end
	local previousFormat = meta == Z.PREVIOUS_NUMERIC_FORMAT or meta == Z.PREVIOUS_NUMERIC_FORMAT + 1
	if previousFormat or meta == Z.NUMERIC_FORMAT or meta == Z.NUMERIC_FORMAT + 1 then
		local slots = {}
		for slot, rows in pairs( Z.RowsByStorageSlot ) do
			local field = Z.ValueField( controller, rows[1] )
			if field == nil then return nil, false, "read_unavailable" end
			local ok, raw = pcall( field.get, field )
			if not ok then return nil, false, "read_unavailable" end
			local stored = tonumber( raw )
			-- Snapshot.24 could combine the old death-points digit with the
			-- bundle enable bit in slot 37. Its out-of-range mock value can be
			-- read for migration; the new format never permits it.
			local limit = previousFormat and slot == 37 and 39 or 31
			if stored == nil or stored ~= math.floor( stored ) or stored < 0 or stored > limit then
				return nil, false, "invalid_record"
			end
			local packedMax = 0
			for _, row in ipairs( rows ) do
				if row.storageFactor ~= nil and row.storageRadix ~= nil then
					packedMax = packedMax + (row.storageRadix - 1) * row.storageFactor
				end
			end
			if previousFormat and slot == 37 then packedMax = 39 end
			if previousFormat and slot == 41 then packedMax = 15 end
			if previousFormat and slot == 49 then packedMax = 13 end
			if packedMax > 0 and stored > packedMax then return nil, false, "invalid_record" end
			slots[slot] = stored
		end
		for _, row in ipairs( Z.AllRows ) do
			local valueIndex = 0
			local stored = slots[row.storageSlot]
			local factor = row.storageFactor
			-- The previous record put Box No Repeat in slot 41's high bit.
			-- Death Points Retained shared slot 37's enable bit, so its value
			-- cannot be recovered unambiguously and is reset to GAME DEFAULT.
			if previousFormat and row.dvar == "zt_box_no_repeat" then
				stored, factor = slots[41], 8
			elseif previousFormat and row.dvar == "zt_death_points_retained" then
				stored = 0
			end
			if row.storageFactor ~= nil and row.storageRadix ~= nil then
				valueIndex = math.floor( stored / factor ) % row.storageRadix
				if row.storageLegacyIndex ~= true then valueIndex = valueIndex + 1 end
			else
				valueIndex = stored
			end
			if valueIndex > 0 and row.values[valueIndex] == nil then
				return nil, false, "invalid_record"
			end
			if valueIndex > 0 and row.values[valueIndex] ~= nil and not Z.IsDefault( row.values[valueIndex], row ) then
				saved[row.dvar] = row.values[valueIndex]
			end
		end
		return saved, previousFormat
	end
	-- A newer owner may have written a format we cannot decode. Do not turn it
	-- into an empty current-format record merely because a setting was edited.
	if meta ~= 0 then return nil, false, "unknown_format" end

	local text = Z.ReadLegacyText( controller )
	if text == nil then return nil, false, "read_unavailable" end
	if string.sub( text, 1, string.len( Z.LEGACY_POSITIONAL_FORMAT ) ) == Z.LEGACY_POSITIONAL_FORMAT then
		local first = string.len( Z.LEGACY_POSITIONAL_FORMAT ) + 1
		for rowIndex, row in ipairs( Z.StorageRows ) do
			local code = string.sub( text, first + rowIndex - 1, first + rowIndex - 1 )
			local encoded = code ~= "" and string.find( Z.VALUE_CHARS, code, 1, true ) or nil
			local valueIndex = encoded ~= nil and encoded - 1 or 0
			if valueIndex > 0 and row.values[valueIndex] ~= nil and not Z.IsDefault( row.values[valueIndex], row ) then
				saved[row.dvar] = row.values[valueIndex]
			end
		end
		return saved, true
	end
	if string.sub( text, 1, string.len( Z.LEGACY_FORMAT ) ) ~= Z.LEGACY_FORMAT then
		return saved, false
	end
	for at = string.len( Z.LEGACY_FORMAT ) + 1, string.len( text ) - Z.LEGACY_ENTRY + 1, Z.LEGACY_ENTRY do
		local row = Z.ByKey[string.sub( text, at, at + 2 )]
		if row ~= nil then
			local valueKey = string.sub( text, at + 3, at + 4 )
			for index, key in ipairs( row.keys ) do
				if key == valueKey then
					saved[row.dvar] = row.values[index]
				end
			end
		end
	end
	return saved, true
end

Z.Write = function ( controller )
	-- A late or foreign format must remain untouched even if this VM had
	-- completed its initial read before the marker changed.
	local format = Z.ReadMeta( controller )
	if format == nil then return false, "read_unavailable" end
	if format ~= 0 and format ~= Z.PREVIOUS_NUMERIC_FORMAT and format ~= Z.PREVIOUS_NUMERIC_FORMAT + 1 and
	   format ~= Z.NUMERIC_FORMAT and format ~= Z.NUMERIC_FORMAT + 1 then
		return false, "unknown_format"
	end
	for slot, rows in pairs( Z.RowsByStorageSlot ) do
		local field = Z.ValueField( controller, rows[1] )
		if field == nil then return false, "write_unavailable" end
		local stored = 0
		for _, row in ipairs( rows ) do
			local value = Z.saved[row.dvar]
			local valueIndex = 0
			if value ~= nil then
				for index, known in ipairs( row.values ) do
					if Z.Same( known, value ) then
						valueIndex = index
						break
					end
				end
				if valueIndex == 0 then return false, "invalid_value" end
			end
			if row.storageFactor ~= nil and row.storageRadix ~= nil then
				local digit = 0
				if valueIndex > 0 then
					digit = row.storageLegacyIndex == true and valueIndex or valueIndex - 1
				end
				if digit >= row.storageRadix then return false, "invalid_value" end
				stored = stored + digit * row.storageFactor
			else
				stored = valueIndex
			end
		end
		if stored < 0 or stored > 31 then return false, "capacity_exhausted" end
		if not pcall( field.set, field, stored ) then return false, "write_rejected" end
		local verified = nil
		pcall( function () verified = tonumber( field:get() ) end )
		if verified ~= stored then return false, "verify_mismatch" end
	end
	local meta = Z.MetaField( controller )
	if meta == nil then return false, "write_unavailable" end
	local metaValue = Z.NUMERIC_FORMAT
	if Z.endGameQueued == true then metaValue = metaValue + 1 end
	if not pcall( meta.set, meta, metaValue ) then return false, "write_rejected" end
	local verifiedMeta = nil
	pcall( function () verifiedMeta = tonumber( meta:get() ) end )
	if verifiedMeta ~= metaValue then return false, "verify_mismatch" end
	-- Some clients return nil on success; only an explicit false is a rejection.
	local accepted = Engine.StorageWrite( controller, Z.STORAGE )
	if accepted == false then return false, "write_rejected" end
	return true
end

Z.StorageReady = function ( controller )
	local ok, ready = pcall( Engine.StorageIsFileReady, controller, Z.STORAGE )
	return ok and ready == true
end

Z.LoadAndMerge = function ( controller )
	if Z.loaded then return true end
	if not Z.StorageReady( controller ) then
		Z.PersistenceDiagnostics.status = "read_pending"
		return false
	end
	if Z.MetaField( controller ) == nil then
		Z.PersistenceDiagnostics.status = "read_unavailable"
		return false
	end
	for _, rows in pairs( Z.RowsByStorageSlot ) do
		if rows[1] ~= nil and Z.ValueField( controller, rows[1] ) == nil then
			Z.PersistenceDiagnostics.status = "read_unavailable"
			return false
		end
	end
	local saved, migrated, reason = Z.Read( controller )
	if saved == nil then
		Z.PersistenceDiagnostics.status = reason or "read_unavailable"
		return false
	end
	local pendingEndGame = Z.endGameQueued == true or Z.EndGamePending()
	for dvar, pending in pairs( Z.pending ) do
		if pending.clear then saved[dvar] = nil else saved[dvar] = pending.value end
	end
	Z.saved = saved
	Z.pending = {}
	Z.loaded = true
	local marker = Z.ReadMeta( controller )
	Z.endGameQueued = pendingEndGame or marker == Z.NUMERIC_FORMAT + 1 or marker == Z.PREVIOUS_NUMERIC_FORMAT + 1
	Z.PersistenceDiagnostics.status = "restored"
	if migrated then Z.dirty = true end
	return true
end

Z.Flush = function ( controller )
	if not Z.dirty then return true end
	if not Z.LoadAndMerge( controller ) then return false end
	local ok, wrote, reason = pcall( Z.Write, controller )
	if ok and wrote == true then
		Z.dirty = false
		Z.PersistenceDiagnostics.status = "committed"
		return true
	end
	-- Storage can disappear while transitioning between frontend and match.
	-- Keep the transaction dirty so the root keeper can retry it later.
	Z.dirty = true
	Z.PersistenceDiagnostics.status = reason or "write_rejected"
	return false
end

Z.Startup = function ( controller )
	if not Z.LoadAndMerge( controller ) then return false end
	if Z.Get( "zt_lobby_restored" ) ~= "1" then
		-- Absence from the packed record is the semantic DEFAULT.  Re-establish
		-- every owned live dvar, not only the stored exceptions: a script/mod VM
		-- handoff or a prior build can otherwise leave an old non-default live
		-- value behind after Reset All correctly removed its persisted record.
		for _, row in ipairs( Z.AllRows ) do
			local value = Z.saved[row.dvar]
			if value == nil then value = tostring( row.default or "" ) end
			Z.Set( controller, row.dvar, value )
		end
		Z.Set( controller, "zt_lobby_restored", "1" )
	end
	if Z.dirty then Z.Flush( controller ) end
	return true
end

-- Gameplay and frontend run in separate Lua VMs.  The offline-loadout record
-- is the durable handoff, but BO3 can make that storage unavailable during
-- the results transition.  Mirror the one-bit queue in a session dvar so the
-- frontend can still consume it after the gameplay VM has been destroyed.
Z.EndGamePending = function ()
	return Z.Get( "zt_t7_endgame_pending" ) == "1"
end

Z.SetEndGamePending = function ( controller, pending )
	Z.Set( controller, "zt_t7_endgame_pending", pending and "1" or "0" )
end

Z.PersistEndGameMarker = function ( controller )
	Z.dirty = true
	return Z.Flush( controller )
end

Z.TryEndGameAction = function ()
	if Z.autoRestartLaunching == true then return end
	local controller = Engine.GetPrimaryController()
	if Z.endGameQueued ~= true and Z.EndGamePending() then
		Z.endGameQueued = true
		Z.endGameMapPrepared = false
	end
	if Z.endGameQueued ~= true then return end
	if Engine.GetCurrentMap() ~= "core_frontend" or controller == nil or controller < 0 then
		Z.autoRestartReadyTicks = 0
		return
	end
	-- zt_lobby_restored describes live dvars, not this Lua VM's in-memory
	-- storage state.  A recreated frontend VM can inherit that dvar while
	-- Z.saved is still empty; never write/consume an end-game transaction until
	-- this VM has loaded and merged the component record.
	if not Z.loaded then
		local ok, ready = pcall( Engine.StorageIsFileReady, controller, Z.STORAGE )
		if not ok or ready ~= true then return end
		Z.Startup( controller )
		-- LoadAndMerge restores the durable marker and may legitimately read no
		-- marker when the gameplay write was refused.  Re-import the session relay
		-- after that load so the fallback cannot be overwritten by stale storage.
		if Z.EndGamePending() then Z.endGameQueued = true end
		if Z.endGameQueued ~= true then return end
	end
	local restart = Z.Get( "zt_auto_restart" ) == "1"
	local mapMode = Z.Get( "zt_next_map" )
	local randomMap = mapMode == "stock" or mapMode == "custom" or mapMode == "all"
	if not restart and not randomMap then
		Z.endGameQueued = false
		Z.SetEndGamePending( controller, false )
		Z.PersistEndGameMarker( controller )
		return
	end
	local lobbyType = Enum.LobbyType.LOBBY_TYPE_PRIVATE
	local gameOk, gameActive = pcall( Engine.IsLobbyActive, Enum.LobbyType.LOBBY_TYPE_GAME )
	if gameOk and gameActive then lobbyType = Enum.LobbyType.LOBBY_TYPE_GAME end
	local activeOk, active = pcall( Engine.IsLobbyActive, lobbyType )
	local hostOk, host = pcall( Engine.IsLobbyHost, lobbyType )
	if not activeOk or not active or not hostOk or not host then
		Z.autoRestartReadyTicks = 0
		return
	end
	if randomMap and Z.endGameMapPrepared ~= true then
		Z.endGameMapPrepared = true
		local changed = Z.SelectRandomMap( controller, mapMode )
		if not restart then
			Z.endGameQueued = false
			Z.SetEndGamePending( controller, false )
			Z.PersistEndGameMarker( controller )
			return
		end
		if changed then
			-- Give the stock lobby model time to propagate the new selection to
			-- every local/client view before asking LobbyVM to launch it.
			Z.autoRestartReadyTicks = 0
			return
		end
	end
	if not restart then return end
	Z.autoRestartReadyTicks = (Z.autoRestartReadyTicks or 0) + 1
	if Z.autoRestartReadyTicks < 4 then return end
	Z.autoRestartLaunching = true
	Z.endGameQueued = false
	Z.SetEndGamePending( controller, false )
	if not Z.PersistEndGameMarker( controller ) then
		-- Otherwise a refused clear can relaunch the level on the next VM.
		Z.autoRestartLaunching = false
		Z.endGameQueued = true
		Z.SetEndGamePending( controller, true )
		return
	end
	pcall( Engine.SetDvar, "skipto", "" )
	pcall( Engine.SetDvar, "sv_saveGameSkipto", "" )
	local ok = pcall( Engine.LobbyVM_CallFunc, "LaunchGame", {
		controller = controller,
		lobbyType = Enum.LobbyType.LOBBY_TYPE_GAME
	} )
	if not ok then
		Z.autoRestartLaunching = false
		Z.autoRestartReadyTicks = 0
		Z.endGameQueued = true
		Z.SetEndGamePending( controller, true )
		Z.PersistEndGameMarker( controller )
	end
end

Z.RandomMapCandidates = function ( controller, mode )
	local maps = {}
	local seen = {}
	local add = function ( id )
		if type( id ) == "string" and id ~= "" and seen[id] ~= true then
			seen[id] = true
			table.insert( maps, id )
		end
	end
	if mode == "stock" or mode == "all" then
		if type( CoD.mapsTable ) == "table" then
			for id, info in pairs( CoD.mapsTable ) do
				if type( info ) == "table" and info.session_mode == Enum.eModes.MODE_ZOMBIES and info.dlc_pack ~= -1 then
					local ok, valid = pcall( Engine.IsMapValid, id )
					if ok and valid then add( id ) end
				end
			end
		end
	end
	if mode == "custom" or mode == "all" then
		pcall( function ()
			if Mods_Enabled() and Engine.Mods_Lists_GetInfoEntriesCount ~= nil and Engine.Mods_Lists_GetInfoEntries ~= nil then
				local count = Engine.Mods_Lists_GetInfoEntriesCount( LuaEnums.USERMAP_BASE_PATH )
				local entries = Engine.Mods_Lists_GetInfoEntries( LuaEnums.USERMAP_BASE_PATH, 0, count )
				if type( entries ) == "table" then
					for _, info in pairs( entries ) do
						if type( info ) == "table" and string.sub( info.internalName or "", 1, 3 ) == "zm_" then
							add( info.ugcName )
						end
					end
				end
			end
		end )
	end
	return maps
end

Z.SelectRandomMap = function ( controller, mode )
	local maps = Z.RandomMapCandidates( controller, mode )
	if #maps == 0 then return false end
	local current = Z.Get( "ui_mapname" )
	local selected = nil
	pcall( function ()
		selected = Engine.GetModelValue( Engine.GetModel( Engine.GetGlobalModel(), "lobbyRoot.selectedMapId" ) )
	end )
	local alternatives = {}
	for _, id in ipairs( maps ) do
		if #maps == 1 or id ~= current and id ~= selected then
			table.insert( alternatives, id )
		end
	end
	if #alternatives == 0 then alternatives = maps end
	local chosen = alternatives[math.random( 1, #alternatives )]
	local ok = false
	if type( SetMap ) == "function" then
		ok = pcall( SetMap, controller, chosen, false )
	else
		ok = pcall( function ()
			Engine.GameLobbySetMap( chosen )
			Engine.SetModelValue( Engine.CreateModel( Engine.GetGlobalModel(), "lobbyRoot.selectedMapId" ), chosen )
		end )
	end
	return ok
end

Z.OnScriptNotify = function ( controller, model )
	if Engine.GetModelValue( model ) ~= "force_scoreboard" then return end
	local data = CoD.GetScriptNotifyData( model )
	if data == nil or tonumber( data[1] ) ~= 1 then return end
	local mapMode = Z.Get( "zt_next_map" )
	local wantsMap = mapMode == "stock" or mapMode == "custom" or mapMode == "all"
	if Z.Get( "zt_auto_restart" ) ~= "1" and not wantsMap then return end
	local ok, host = pcall( Engine.IsLobbyHost, Enum.LobbyType.LOBBY_TYPE_GAME )
	if not ok or not host or Z.endGameQueued == true then return end
	-- The gameplay Lua VM can load this module afresh. Populate Z.saved before
	-- appending the marker so the write preserves every configured option.
	-- Set the session relay first: even if offline-loadout storage is transiently
	-- unavailable, the frontend VM will still observe the queued action.
	Z.SetEndGamePending( controller, true )
	Z.Startup( controller )
	Z.endGameQueued = true
	Z.endGameMapPrepared = false
	Z.dirty = true
	Z.Flush( controller )
end

-- Opt-in frontend-to-match visibility probe. This is deliberately only a
-- host-process snapshot of an existing saved field, not a per-player relay.
-- It must never be used to assign a remote client's character.
Z.UpdateCharacterProbeFrontendSnapshot = function ( controller )
	if Z.Get( "zt_character_probe" ) ~= "1" or Engine.GetCurrentMap() ~= "core_frontend" then return end
	local snapshot = "UNAVAILABLE"
	if Z.StorageReady( controller ) then
		local marker = Z.ReadMeta( controller )
		if marker == Z.NUMERIC_FORMAT or marker == Z.NUMERIC_FORMAT + 1 or
		   marker == Z.PREVIOUS_NUMERIC_FORMAT or marker == Z.PREVIOUS_NUMERIC_FORMAT + 1 then
			local field = Z.ValueField( controller, { storageSlot = 2 } )
			if field ~= nil then
				local ok, raw = pcall( field.get, field )
				local value = ok and tonumber( raw ) or nil
				if value ~= nil and value == math.floor( value ) and value >= 0 and value <= 31 then
					snapshot = tostring( marker ) .. ":" .. tostring( value )
				end
			end
		end
	end
	if Z.Get( "zt_char_probe_frontend_slot2" ) ~= snapshot then
		Z.Set( controller, "zt_char_probe_frontend_slot2", snapshot )
	end
end

-- Character transport probe: answer from this controller's offline Zombies
-- storage, never from a host dvar. This deliberately sends no cast request;
-- GSC only compares response time with stock character assignment.
Z.MarkCharacterProbeStage = function ( controller, stage )
	if Z.Get( "zt_character_probe" ) ~= "1" then return end
	local run = Z.Get( "zt_char_probe_run" )
	if run == "" then return end
	local current = Z.Get( "zt_char_probe_lua_stage" )
	if (stage == "HUD" or stage == "LOADING") and string.sub( current, 1, #run + 1 ) == run .. ":" then return end
	Z.Set( controller, "zt_char_probe_lua_stage", run .. ":" .. stage )
end

Z.CharacterProbeMovieState = function ()
	local ok, playing = pcall( Engine.IsCinematicPlaying )
	if not ok then return "UNKNOWN" end
	if playing == true or playing == 1 then return "PLAYING" end
	if playing == false or playing == 0 then return "IDLE" end
	return "UNKNOWN"
end

Z.SampleCharacterProbeMovie = function ( controller, phase )
	local run = Z.Get( "zt_char_probe_run" )
	local state = Z.CharacterProbeMovieState()
	if Z.Get( "zt_character_probe" ) ~= "1" or run == "" then return state end
	if Z.characterProbeMovieRun ~= run then
		Z.characterProbeMovieRun = run
		Z.characterProbeMovieState = nil
		Z.characterProbeMovieTransitions = 0
	end
	if Z.characterProbeMovieState ~= state then
		Z.characterProbeMovieState = state
		Z.characterProbeMovieTransitions = Z.characterProbeMovieTransitions + 1
		Z.Set( controller, "zt_char_probe_movie_stage", run .. ":" .. tostring( Z.characterProbeMovieTransitions ) .. ":" .. state .. ":" .. phase )
	end
	return state
end

Z.SendCharacterProbe = function ( controller, source )
	local run = Z.Get( "zt_char_probe_run" )
	if run == "" then return end
	-- The loading poll and multiple UI subscribers may all be live. Exactly
	-- one ordinary response attempt per match avoids a reliable-command burst.
	-- The opt-in cast-delay test permits exactly one separate idle-cinematic
	-- retry while the server is still holding that first cast.
	local idleRetry = source == "DEFER_IDLE"
	if idleRetry then
		if Z.Get( "zt_character_delay_probe" ) ~= "1" or Z.characterProbeIdleRetryRun == run then return end
		Z.characterProbeIdleRetryRun = run
	else
		if Z.characterProbeReplyRun == run then return end
		Z.characterProbeReplyRun = run
	end
	local movieEvent
	if source == "LOADING_POLL" then
		Z.MarkCharacterProbeStage( controller, "POLL" )
		movieEvent = Z.SampleCharacterProbeMovie( controller, "POLL" )
	else
		Z.MarkCharacterProbeStage( controller, "EVENT" )
		movieEvent = Z.SampleCharacterProbeMovie( controller, "EVENT" )
	end
	local raw = -99
	if Z.StorageReady( controller ) then
		local field = Z.ValueField( controller, { storageSlot = 2 } )
		if field ~= nil then
			local ok, value = pcall( field.get, field )
			if ok and tonumber( value ) ~= nil then raw = tonumber( value ) end
		end
	end
	-- T7x gameplay delivers this response through the stock StartMenu_Main
	-- channel. An arbitrary probe menu name can return success in Lua without
	-- reaching the player's GSC menuresponse watcher. The payload tag, not the
	-- forwarded menu name, identifies this probe on the server.
	local movieSend = Z.SampleCharacterProbeMovie( controller, "SEND" )
	local payload = "zt_char_probe|" .. run .. "|" .. tostring( raw ) .. "|" .. movieEvent .. "|" .. movieSend .. "|" .. tostring( source or "HUD" )
	local ok, accepted = pcall( Engine.SendMenuResponse, controller, "StartMenu_Main", payload )
	if source == "LOADING_POLL" then Z.Set( controller, "zt_char_probe_poll_sent", run ) end
	local sent = ok and accepted ~= false
	Z.MarkCharacterProbeStage( controller, sent and (idleRetry and "IDLE_SENT" or "SENT") or (idleRetry and "IDLE_FAILED" or "SEND_FAILED") )
end

Z.TryCharacterProbeIdleRetry = function ( controller, movieState )
	if Z.Get( "zt_character_probe" ) ~= "1" or Z.Get( "zt_character_delay_probe" ) ~= "1" then return end
	local run = Z.Get( "zt_char_probe_run" )
	if run == "" or Z.characterProbeIdleRetryRun == run
		or Z.Get( "zt_char_probe_defer_state" ) ~= run .. ":ACTIVE"
		or movieState ~= "IDLE" then return end
	-- A process-global dvar is not a remote-client transport. This diagnostic
	-- retry is strictly for the local solo host, just like the loading push.
	local hostOk, host = pcall( Engine.IsLobbyHost, Enum.LobbyType.LOBBY_TYPE_GAME )
	local countOk, count = pcall( Engine.GetLobbyClientCount, Enum.LobbyType.LOBBY_TYPE_GAME )
	if not hostOk or not host or not countOk or type( count ) ~= "number" or count > 1 then return end
	if Z.characterProbeReplyRun == run then
		Z.SendCharacterProbe( controller, "DEFER_IDLE" )
	else
		-- The first attempt may not have fired before this cast. Use the same
		-- one-shot path, then mark the idle opportunity consumed.
		Z.SendCharacterProbe( controller, "HUD_IDLE" )
		Z.characterProbeIdleRetryRun = run
	end
end

Z.OnCharacterProbe = function ( controller, model, source )
	if Engine.GetModelValue( model ) ~= "ztCharProbe" then return end
	Z.SendCharacterProbe( controller, source )
end

-- The co-op transport probe reads this controller's own offline record.
-- It does not infer a remote player's value from a process-wide host dvar,
-- and it never changes gameplay character state. The server's numeric
-- packet carries a bounded request token and roster code, not a string.
Z.OnCharacterCoopProbe = function ( controller, model )
	if Engine.GetModelValue( model ) ~= "ztCharCoopPreference" then return end
	local data = CoD.GetScriptNotifyData( model )
	local packet = data ~= nil and tonumber( data[1] ) or nil
	if packet == nil or packet ~= math.floor( packet ) then return end
	local token = math.floor( packet / 8 )
	local roster = packet % 8
	if token < 1 or token > 1023 then return end
	local dvar = ( {
		[1] = "scr_zt_char_victis", [2] = "scr_zt_char_mob",
		[3] = "scr_zt_char_origins", [4] = "scr_zt_char_soe",
		[5] = "scr_zt_char_primis", [6] = "scr_zt_char_ultimis"
	} )[roster]
	if dvar == nil then return end
	-- A new host or process can reuse a token after a map restart. Let the
	-- server-side one-shot listener discard duplicate replies instead of
	-- retaining a cross-match Lua dedupe table.
	local value = "UNAVAILABLE"
	if controller == Engine.GetPrimaryController() and Z.LoadAndMerge( controller ) then
		-- Use the component-owned transaction, including unflushed changes.
		-- A raw profile reread can discard a preference edited just before launch.
		value = tostring( Z.saved[dvar] or "-1" )
	elseif controller ~= Engine.GetPrimaryController() and Z.StorageReady( controller ) then
		-- The shell transaction belongs to the primary controller. Never send
		-- that player's preference on behalf of a second local profile.
		local saved = Z.Read( controller )
		if saved ~= nil then value = tostring( saved[dvar] or "-1" ) end
	end
	if value ~= "-1" and value ~= "0" and value ~= "1" and value ~= "2" and value ~= "3" then
		value = "UNAVAILABLE"
	end
	pcall( Engine.SendMenuResponse, controller, "StartMenu_Main", "zt_char_coop|" .. tostring( token ) .. "|" .. value )
end

-- Loading.lua creates its menu with CoD.Menu.NewFromState before the Zombies
-- gameplay HUD exists. Keep this opt-in listener on that exact menu instance;
-- it neither replaces stock loading.lua nor sends an extra server request.
Z.ListenLoadingCharacterProbe = function ( element )
	if element == nil or element.ztLoadingCharacterProbeListening == true
		or Z.Get( "zt_character_probe" ) ~= "1" then return end
	local controller = Engine.GetPrimaryController()
	if controller == nil or controller < 0 then return end
	element.ztLoadingCharacterProbeListening = true
	element:subscribeToGlobalModel( controller, "PerController", "scriptNotify", function ( model )
		Z.OnCharacterProbe( controller, model, "LOADING" )
	end )
	Z.MarkCharacterProbeStage( controller, "LOADING" )
	Z.SampleCharacterProbeMovie( controller, "LOAD" )
	-- The loading menu can precede the server's per-match run dvar. Poll only
	-- locally until it appears, including during the intro, then leave a
	-- single readiness marker for the existing one-shot GSC notify loop.
	local samples = 0
	local timer
	timer = LUI.UITimer.newElementTimer( 100, false, function ()
		samples = samples + 1
		Z.MarkCharacterProbeStage( controller, "LOADING" )
		local movieState = Z.SampleCharacterProbeMovie( controller, "LOAD_TICK" )
		Z.TryCharacterProbeIdleRetry( controller, movieState )
		local run = Z.Get( "zt_char_probe_run" )
		if run ~= "" and Z.Get( "zt_char_probe_poll_ready" ) == run
			and Z.characterProbeReplyRun ~= run then
			local hostOk, host = pcall( Engine.IsLobbyHost, Enum.LobbyType.LOBBY_TYPE_GAME )
			local countOk, count = pcall( Engine.GetLobbyClientCount, Enum.LobbyType.LOBBY_TYPE_GAME )
			if hostOk and host and countOk and count <= 1 then
				Z.SendCharacterProbe( controller, "LOADING_POLL" )
			end
		end
		local deferState = Z.Get( "zt_char_probe_defer_state" )
		local delayMode = Z.Get( "zt_character_delay_probe" ) == "1"
		if samples >= 1200 or (not delayMode and Z.characterProbeReplyRun == run)
			or (delayMode and (Z.characterProbeIdleRetryRun == run or deferState == run .. ":DONE")) then
			timer:close()
		end
	end )
	element:addElement( timer )
end

Z.ListenCharacterProbe = function ( element, controller )
	if element == nil or element.ztCharacterProbeListening == true then return end
	controller = controller or Engine.GetPrimaryController()
	if controller == nil or controller < 0 then return end
	element.ztCharacterProbeListening = true
	element:subscribeToGlobalModel( controller, "PerController", "scriptNotify", function ( model )
		Z.OnCharacterProbe( controller, model )
		Z.OnCharacterCoopProbe( controller, model )
	end )
	Z.MarkCharacterProbeStage( controller, "HUD" )
	Z.SampleCharacterProbeMovie( controller, "HUD" )
	-- A sampled state change remains visible in the GSC cast/reply markers.
	-- Keep this diagnostic timer bounded even if the solo intro is watched in
	-- full; no gameplay state or clientfield is changed.
	if Z.Get( "zt_character_probe" ) == "1" then
		local movieSamples = 0
		local movieTimer
		movieTimer = LUI.UITimer.newElementTimer( 500, false, function ()
			movieSamples = movieSamples + 1
			local movieState = Z.SampleCharacterProbeMovie( controller, "TICK" )
			Z.TryCharacterProbeIdleRetry( controller, movieState )
			if movieSamples >= 300 then movieTimer:close() end
		end )
		element:addElement( movieTimer )
	end
	-- The GSC probe clears its run marker during map setup. A HUD created
	-- before that reset must keep identifying itself through the startup
	-- window, including after Auto Restart, without sending extra requests.
	if Z.Get( "zt_character_probe" ) == "1" then
		local samples = 0
		local function markHud()
			samples = samples + 1
			Z.MarkCharacterProbeStage( controller, "HUD" )
			if samples < 16 then
				element:addElement( LUI.UITimer.newElementTimer( 500, true, markHud ) )
			end
		end
		markHud()
	end
end

Z.ListenEndGameAction = function ( element, controller )
	if element == nil or element.ztEndGameListening == true then return end
	controller = controller or Engine.GetPrimaryController()
	if controller == nil or controller < 0 then return end
	element.ztEndGameListening = true
	element:subscribeToGlobalModel( controller, "PerController", "scriptNotify", function ( model )
		Z.OnScriptNotify( controller, model )
	end )
end

Z.WatchEndGameAction = function ( parent )
	if parent == nil or Z.endGameWatchRoot == parent then return end
	Z.endGameWatchRoot = parent
	local poll
	poll = function ()
		if Z.endGameWatchRoot ~= parent then return end
		local controller = Engine.GetPrimaryController()
		if controller ~= nil and controller >= 0 then
			if Z.dirty then pcall( Z.Flush, controller ) end
			Z.UpdateCharacterProbeFrontendSnapshot( controller )
		end
		pcall( Z.TryEndGameAction )
		local ok, timer = pcall( LUI.UITimer.newElementTimer, 500, true, poll )
		if ok and timer ~= nil then pcall( function () parent:addElement( timer ) end ) end
	end
	poll()
end

Z.Wait = function ( parent, tries )
	parent:addElement( LUI.UITimer.newElementTimer( 1000, true, function ()
		Z.Hook()
		local controller = Engine.GetPrimaryController()
		if controller ~= nil and controller >= 0 then
			local ok, ready = pcall( Engine.StorageIsFileReady, controller, Z.STORAGE )
			if ok and ready == true or tries >= 60 then
				Z.Startup( controller )
				return
			end
			tries = tries + 1
		end
		Z.Wait( parent, tries )
	end ) )
end

Z.IsHost = function ( controller )
	return B.HostStatus( controller ) == "HOST"
end

Z.AddButton = function ( buttons )
	if not Z.DrawsSettingsRow() then return end
	local at = #buttons + 1
	for index, button in ipairs( buttons ) do
		if button.optionDisplay == "MENU_BUBBLEGUM_BUFFS_CAPS" then
			at = index
			break
		end
	end
	if at > 1 then
		buttons[at - 1].isLastButtonInGroup = true
	end
	table.insert( buttons, at, {
		optionDisplay = Z.EntryLabel(),
		action = Z.OpenFromLobby,
		customId = "btnZTweaksSettings",
		isLargeButton = true,
		isLastButtonInGroup = true,
		disabled = false,
		selected = false,
		warning = false
	} )
end

Z.Hook = function ()
	if Z.hooked or CoD.LobbyMenus == nil or CoD.LobbyMenus.AddButtonsForTarget == nil or LobbyData == nil or LobbyData.UITargets == nil then
		return
	end
	Z.hooked = true
	Z.Lobbies = {}
	for _, name in ipairs( { "UI_ZMLOBBYONLINE", "UI_ZMLOBBYONLINECUSTOMGAME", "UI_ZMLOBBYLANGAME" } ) do
		local target = LobbyData.UITargets[name]
		if target ~= nil then
			Z.Lobbies[target.id] = true
		end
	end
	local addButtonsForTarget = CoD.LobbyMenus.AddButtonsForTarget
	CoD.LobbyMenus.AddButtonsForTarget = function ( controller, id )
		if LUI.roots ~= nil then Z.WatchEndGameAction( LUI.roots.UIRootFull ) end
		local buttons = addButtonsForTarget( controller, id )
		if Z.Lobbies[id] then Z.AddButton( buttons ) end
		return buttons
	end
end

Z.OpenFromLobby = function ( self, element, controller, param, menu )
	if B.HostStatus( controller ) == "HOST" then
		pcall( function ()
			CoD.LobbyBase.SetLeaderActivity( controller, CoD.LobbyBase.LeaderActivity.EDITING_GAME_RULES )
		end )
	end
	local opened = OpenOverlay( menu, "ZTweaksSettings", controller )
	if opened ~= nil then
		LUI.OverrideFunction_CallOriginalFirst( opened, "close", function ()
			if B.HostStatus( controller ) == "HOST" then pcall( function () CoD.LobbyBase.ResetLeaderActivity( controller ) end ) end
		end )
	end
end

Z.OpenCharacterPreferencesFromLobby = function ( self, element, controller, param, menu )
	OpenOverlay( menu, "ZTweaksCharacterPreferences", controller )
end

Z.OpenFromPause = function ( self, element, controller )
	Z.Startup( controller )
	local menu = self
	while menu ~= nil and menu.openMenu == nil do
		menu = menu:getParent()
	end
	if menu ~= nil then
		OpenPopup( menu, "ZTweaksInGameSettings", controller )
	end
end

Z.RowGet = function ( row, tab, controller )
	if row ~= nil and row.kind == "button" then return "" end
	tab = row.ztSourceTab or tab
	controller = controller or Engine.GetPrimaryController()
	local forced, locked = B.RowOverride( row, tab, controller )
	if locked and forced ~= nil then return forced end
	if tab ~= nil and type( tab.get ) == "function" then
		-- External ZBundle tabs use get(dvar, row). Only our own tabs retain
		-- the legacy get(controller, dvar, row) callback shape.
		local ok, value
		if tab.owner == "ztweaks" then
			ok, value = pcall( tab.get, controller, row.dvar, row )
		else
			ok, value = pcall( tab.get, row.dvar, row )
		end
		if ok and value ~= nil then return tostring( value ) end
	end
	return Z.Get( row.dvar )
end

-- Shared-menu conformance: action rows are inert values in every distribution.
Z.NativeButtonRowSeam = 1

Z.Chosen = function ( self, element, controller, param, menu )
	local row = param.row or param
	local tab = param.tab
	if not B.RowWritable( row, tab, controller ) then return end
	UpdateInfoModels( element )
	local picked = element.default == true and "" or element.value
	local current = Z.RowGet( row, tab, controller )
	Z.SetPicked( row, tab, picked, current )
	if element.default == true then
		if Z.IsDefault( current, row ) then return end
	elseif Z.Same( current, element.value ) then
		return
	end
	if tab ~= nil and type( tab.set ) == "function" then
		tab.set( controller, row.dvar, element.value, row )
		Z.SetPicked( row, tab, picked, Z.RowGet( row, tab, controller ) )
		-- The CHANGED category's enabled model is part of the tab datasource.
		-- Refresh after every real write so the final category becomes reachable
		-- immediately instead of retaining the disabled state captured at open.
		if type( Z.QueueRegistryRefresh ) == "function" then Z.QueueRegistryRefresh( menu, controller, tab.id ) end
		return
	end
	Z.TabSet( controller, row.dvar, element.value, row )
	Z.SetPicked( row, tab, picked, Z.RowGet( row, tab, controller ) )
	if type( Z.QueueRegistryRefresh ) == "function" then Z.QueueRegistryRefresh( menu, controller, tab ~= nil and tab.id or nil ) end
end

Z.Row = function ( row, source, tab, controller )
	controller = controller or Engine.GetPrimaryController()
	tab = row.ztSourceTab or tab
	if row.kind == "button" then
		local hostLocked = B.RowHostLocked( row, tab, controller )
		local available = Z.ButtonAvailable( row, tab, controller )
		DataSources[source] = DataSourceHelpers.ListSetup( source, function ( who )
			who = who or controller
			return { {
			models = { text = Z.OwnerWords( B.RowHostLocked( row, tab, who ) and "HOST CONTROLLED" or ( Z.ButtonAvailable( row, tab, who ) and "ACTIVATE" or "UNAVAILABLE" ), row, tab ), ztOptionLocked = true },
			properties = { title = row.dvar or "", desc = Z.OwnerWords( row.hint or "", row, tab ), selectIndex = true,
				loopEdges = false, showChangeIndicator = function () return false end }
		} } end, nil, nil, nil )
		return { models = { name = Z.OwnerWords( row.label or "ACTION", row, tab ), desc = Z.RowReasonWords( row, tab, controller ),
			ztButtonRow = true, ztRowState = available and "NORMAL" or "DISABLED",
			ztDefaultCaption = "TYPE", ztBoundaryCaption = "STATUS", defaultText = "BUTTON",
			boundaryText = hostLocked and "HOST CONTROLLED" or ( available and "READY" or "DISABLED" ),
			scopeText = row.scope or "LOCAL", optionsDatasource = source }, properties = {} }
	end
	local defaultLabel = row.default
	for index, value in ipairs( row.values ) do
		if Z.Same( value, row.default ) then
			defaultLabel = row.labels[index]
			break
		end
	end
	local forced, locked = B.RowOverride( row, tab, controller )
	local unavailable = B.RowUnavailable( row, tab, controller )
	local hostLocked = B.RowHostLocked( row, tab, controller )
	local state = hostLocked and "HOST CONTROLLED" or ( locked and "OVERRIDDEN" or ( unavailable and "DISABLED" or "NORMAL" ) )
	local current = Z.RowGet( row, tab, controller )
	local currentLabel = locked and forced == nil and "UNAVAILABLE" or Z.ValueLabel( row, current )
	-- LUIGridLayout consumes selectIndex while preparing a list. Returning the
	-- same table again therefore loses the selected value when the outer list
	-- recycles a row during scrolling and used to snap that row to DEFAULT.
	-- Always build fresh option models from the live dvar for every request.
	local buildOptions = function ( optionController )
		local controller = optionController or controller
		local current = Z.RowGet( row, tab, controller )
		if not B.RowWritable( row, tab, controller ) then
			local forced, locked = B.RowOverride( row, tab, controller )
			local readLabel = B.RowHostValue( row, tab, controller )
			if readLabel == nil then
				readLabel = locked and forced == nil and "UNAVAILABLE" or Z.ValueLabel( row, current )
				readLabel = Z.OwnerWords( readLabel, row, tab )
				if locked then readLabel = L.Format( "LOCKED: {value}", { value = readLabel } )
				elseif not B.RowEnabled( row, tab, controller ) then readLabel = L.Format( "DISABLED: {value}", { value = readLabel } ) end
			else
				readLabel = Z.OwnerWords( readLabel, row, tab )
			end
			return { {
				models = { text = readLabel, ztOptionLocked = true },
				properties = { title = row.dvar, desc = L.Format( "[{boundary}] {hint}", { boundary = Z.OwnerWords( locked and "OVERRIDDEN" or ( B.RowEnabled( row, tab, controller ) and "READ ONLY" or "DISABLED" ), row, tab ), hint = Z.RowReasonWords( row, tab, controller ) } ), value = current, selectIndex = true, loopEdges = false, action = function () end }
			} }
		end
		local atDefault = Z.ShowsDefault( current, row, tab )
		local listed = atDefault
		for _, value in ipairs( row.values ) do
			if Z.Same( current, value ) then listed = true end
		end
		local options = {}
		local add = function ( label, value, isDefault, selected )
			table.insert( options, {
				models = { text = Z.OwnerWords( label, row, tab ) },
				properties = {
					title = row.dvar,
					desc = L.Format( "[{boundary}] {hint}", { boundary = Z.OwnerWords( row.boundary, row, tab ), hint = Z.OwnerWords( row.hint, row, tab ) } ),
					value = value,
					default = isDefault,
					actionParam = { row = row, tab = tab },
					action = B.RowWritable( row, tab, controller ) and Z.Chosen or nil,
					selectIndex = selected,
					loopEdges = true,
					showChangeIndicator = function ( item ) return item.default ~= true end
				}
			} )
		end
		if tab ~= nil and tab.role == "mods" then
			-- A component is either enabled or disabled. Keep ON as the
			-- semantic default for reset/change indicators, but show its
			-- actual state instead of a synthetic DEFAULT choice.
			add( "ON", "1", true, Z.Same( current, "1" ) )
			add( "OFF", "0", false, Z.Same( current, "0" ) )
			options[1].properties.first = true
			options[#options].properties.last = true
			return options
		end
		add( "DEFAULT", "", true, atDefault )
		for index, value in ipairs( row.values ) do
			-- Keep the explicit RANDOM choice after the standard DEFAULT entry.
			-- tab already resolves a CHANGED row back to its owning source tab.
			if ( tab ~= nil and tab.id == "ztweaks_characters" ) or not Z.Same( value, row.default ) then
				if not listed and row.kind == "number" and tonumber( current ) ~= nil and tonumber( current ) < tonumber( value ) then
					add( current, current, false, true )
					listed = true
				end
				add( row.labels[index], value, false, not atDefault and Z.Same( current, value ) )
			end
		end
		if not listed then add( string.upper( current ), current, false, true ) end
		options[1].properties.first = true
		options[#options].properties.last = true
		return options
	end
	DataSources[source] = DataSourceHelpers.ListSetup( source, buildOptions, nil, nil, nil )
	return {
		models = {
			name = Z.OwnerWords( row.label or row.dvar, row, tab ),
			desc = state == "NORMAL" and Z.RowReasonWords( row, tab, controller ) or L.Format( "{state}: {reason}", { state = Z.OwnerWords( state, row, tab ), reason = Z.RowReasonWords( row, tab, controller ) } ),
			disabled = false,
			ztUnavailable = unavailable,
			ztRowState = state,
			ztDefaultCaption = hostLocked and "HOST VALUE" or ( state == "OVERRIDDEN" and "FORCED" or ( state == "DISABLED" and "CURRENT" or "DEFAULT" ) ),
			ztBoundaryCaption = state == "NORMAL" and "APPLIES" or "STATUS",
			defaultText = Z.OwnerWords( hostLocked and "UNAVAILABLE" or ( state == "NORMAL" and defaultLabel or currentLabel ), row, tab ),
			boundaryText = Z.OwnerWords( state == "NORMAL" and row.boundary or state, row, tab ),
			scopeText = Z.OwnerWords( row.scope or "HOST / SHARED", row, tab ),
			optionsDatasource = source
		},
		properties = {}
	}
end

Z.ActivateFocusedButton = function ( menu, controller, control )
	if menu == nil or menu.Options == nil then return false end
	local index
	if control ~= nil then
		local item = control
		while item ~= nil and item ~= menu.Options do
			local parent = type( item.getParent ) == "function" and item:getParent() or nil
			if parent == menu.Options then
				index = item.gridInfoTable ~= nil and item.gridInfoTable.zeroBasedIndex or nil
				break
			end
			item = parent
		end
		-- A stale/detached click must never fall back to a different focused row.
		if index == nil then return false end
	else
		local active = menu.Options.activeWidget
		index = active ~= nil and active.gridInfoTable ~= nil
			and active.gridInfoTable.zeroBasedIndex or menu.Options.savedActiveIndex or 0
	end
	local row = ( menu.ztRows or {} )[index + 1]
	if row == nil or row.kind ~= "button" then return false end
	local tab = row.ztSourceTab or menu.ztActiveTab
	if Z.ButtonAvailable( row, tab, controller ) and type( row.action ) == "function" then
		row.action( controller, menu, row, tab )
	end
	return true
end

Z.Rows = function ()
	return Z.AllRows
end

Z.TabRows = function ( tab )
	if tab == nil then return {} end
	if type( tab.rows ) == "function" then
		local ok, rows = pcall( tab.rows )
		if ok and type( rows ) == "table" then return rows end
		return {}
	end
	return type( tab.rows ) == "table" and tab.rows or {}
end

Z.TabEnabled = function ( tab, controller )
	if not B.TabEnabled( tab, controller ) then return false end
	if tab ~= nil and tab.role == "changed" then return #Z.TabRows( tab ) > 0 end
	return true
end

Z.FindTab = function ( tabs, id )
	for _, tab in ipairs( tabs or {} ) do
		if tab.id == id then return tab end
	end
	return nil
end

Z.FindTabIndex = function ( tabs, id )
	for index, tab in ipairs( tabs or {} ) do
		if tab.id == id then return index end
	end
	return 1
end

Z.AdjacentTabIndex = function ( tabs, id, direction, controller )
	local count = #( tabs or {} )
	if count < 2 then return nil end
	local index = Z.FindTabIndex( tabs, id )
	for _ = 1, count - 1 do
		index = index + direction
		if index < 1 then index = count elseif index > count then index = 1 end
		if Z.TabEnabled( tabs[index], controller ) then return index end
	end
	return nil
end

Z.UpdateTabNavigation = function ( menu, id, controller )
	if menu == nil or menu.ztTabs == nil then return end
	local count = #menu.ztTabs
	local index = Z.FindTabIndex( menu.ztTabs, id )
	local previousIndex = Z.AdjacentTabIndex( menu.ztTabs, id, -1, controller )
	local nextIndex = Z.AdjacentTabIndex( menu.ztTabs, id, 1, controller )
	local hasPrevious = previousIndex ~= nil
	local hasNext = nextIndex ~= nil
	if menu.TabLeft ~= nil then menu.TabLeft:setAlpha( hasPrevious and 1 or 0.22 ) end
	if menu.TabRight ~= nil then menu.TabRight:setAlpha( hasNext and 1 or 0.22 ) end
	if menu.TabPrevious ~= nil then
		menu.TabPrevious:setText( hasPrevious and L.Format( "<  PREV: {tab}", { tab = Z.OwnerWords( menu.ztTabs[previousIndex].label or menu.ztTabs[previousIndex].id, nil, menu.ztTabs[previousIndex] ) } ) or "" )
	end
	if menu.TabNext ~= nil then
		menu.TabNext:setText( hasNext and L.Format( "NEXT: {tab}  >", { tab = Z.OwnerWords( menu.ztTabs[nextIndex].label or menu.ztTabs[nextIndex].id, nil, menu.ztTabs[nextIndex] ) } ) or "" )
	end
	if menu.TabPosition ~= nil then
		menu.TabPosition:setText( L.Text( L.Format( "CATEGORY {current} / {total}", { current = index, total = count } ) ) )
	end
end

Z.BuildTabsDataSource = function ( name, tabs, selectedId, controller )
	DataSources[name] = DataSourceHelpers.ListSetup( name, function ()
		local result = {}
		for _, tab in ipairs( tabs ) do
			table.insert( result, {
				models = {
					tabName = Z.OwnerWords( tab.label or tab.id, nil, tab ),
					tabId = tab.id,
					tabHint = Z.OwnerWords( tab.hint or "", nil, tab ),
					tabOwner = tab.owner or "",
					disabled = not Z.TabEnabled( tab, controller )
				},
				properties = { selectIndex = tab.id == selectedId }
			} )
		end
		return result
	end, nil, nil, nil )
end

Z.BuildDataSource = function ( name, rows, tab )
	DataSources[name] = DataSourceHelpers.ListSetup( name, function ( controller )
		local result = {}
		for index, row in ipairs( rows ) do
			table.insert( result, Z.Row( row, name .. "_" .. index, row.ztSourceTab or tab, controller ) )
		end
		return result
	end, nil, nil, nil )
end

Z.SyncScrollbar = function ( menu )
	if menu == nil or menu.Options == nil then return end
	-- T7x keeps datasource models alive across menu/module reloads. Keep the
	-- native scrollbar's private geometry in lockstep with the active tab so a
	-- formerly larger list cannot leave a misleading thumb behind. The stock
	-- widget caches its 500-unit constructor height before this 441-unit list is
	-- laid out, so derive the usable track from the live list every time too.
	menu.Options.vCount = 7
	menu.Options.requestedRowCount = #menu.ztRows
	if menu.Options.verticalScrollbar ~= nil then
		local _, listHeight = menu.Options:getLocalSize()
		if listHeight ~= nil and listHeight > 24 then
			menu.Options.verticalScrollbar.sliderTop = 12
			menu.Options.verticalScrollbar.sliderHeight = listHeight - 24
		end
	end
	menu.Options:updateScrollbars()
end

Z.ActivateTab = function ( menu, controller, id, force )
	if menu == nil or menu.Options == nil or id == nil or ( id == menu.ztActiveTabId and not force ) then return end
	local tab = Z.FindTab( menu.ztTabs, id )
	if tab == nil or not Z.TabEnabled( tab, controller ) then return end
	if menu.ztActiveTabId ~= nil then
		menu.ztTabPositions[menu.ztActiveTabId] = menu.Options.savedActiveIndex or 0
	end
	menu.ztActiveTabId = id
	menu.ztActiveTab = tab
	menu.ztChangedOnly = false
	menu.ztRows = Z.TabRows( tab )
	menu.ztAvailability = Z.AvailabilitySnapshot( menu, controller )
	if menu.Title ~= nil then menu.Title:setText( L.Text( menu.ztCharacterOnly and "CHARACTER PREFERENCES" or Z.MenuTitle( menu.ztTabs, tab ) ) ) end
	menu.Subtitle:setText( Z.OwnerWords( tab.hint or "", nil, tab ) )
	menu.ztDataSource = menu.ztDataSources[id]
	Z.BuildDataSource( menu.ztDataSource, menu.ztRows, tab )
	menu.Options.savedActiveIndex = menu.ztTabPositions[id] or 0
	menu.Options:setDataSource( menu.ztDataSource )
	Z.SyncScrollbar( menu )
	Z.UpdateTabNavigation( menu, id, controller )
end

Z.CaptureView = function ( menu )
	local list = menu ~= nil and menu.Options or nil
	if list == nil then return nil end
	local active = list.activeWidget
	local index = active ~= nil and active.gridInfoTable ~= nil
		and active.gridInfoTable.zeroBasedIndex or list.savedActiveIndex or 0
	local row = ( menu.ztRows or {} )[index + 1]
	return { tabId = menu.ztActiveTabId, index = index,
		rowKey = row ~= nil and tostring( row.dvar or "" ) or "",
		first = list.currentStartRow or 1 }
end

Z.RestoreView = function ( menu, snapshot )
	if snapshot == nil or menu.ztActiveTabId ~= snapshot.tabId or menu.Options == nil then return end
	local list, rows = menu.Options, menu.ztRows or {}
	if #rows == 0 then return end
	local index = math.min( snapshot.index, #rows - 1 )
	if snapshot.rowKey ~= "" then
		for candidate, row in ipairs( rows ) do
			if tostring( row.dvar or "" ) == snapshot.rowKey then index = candidate - 1; break end
		end
	end
	index = math.max( 0, index )
	local count = math.max( 1, list.vCount or 1 )
	local first = math.max( 1, math.min( snapshot.first, math.max( 1, #rows - count + 1 ) ) )
	first = math.min( first, index + 1 )
	first = math.max( first, index - count + 2 )
	if type( list.updateCurrentPosition ) == "function" then
		list:updateCurrentPosition( first, list.currentStartColumn or 1 )
		list:updateLayout( 0 )
	end
	list:setActiveIndex( index + 1, 1, 0, true )
	if type( list.updateScrollbars ) == "function" then list:updateScrollbars() end
end

Z.TabWindowStart = function ( count, visible, active, previous )
	visible = math.max( 1, math.min( visible or 6, count ) )
	local first = math.min( math.max( 1, previous or 1 ), math.max( 1, count - visible + 1 ) )
	if active < first then first = active end
	if active > first + visible - 1 then first = active - visible + 1 end
	return first
end

Z.RestoreTabWindow = function ( grid, count, active, previous )
	local first = Z.TabWindowStart( count, grid.hCount or 6, active, previous )
	if grid.currentStartColumn ~= first then
		grid:updateCurrentPosition( 1, first )
		grid:updateLayout( 0 )
	end
	return first
end

Z.RefreshRegistry = function ( menu, controller, preferredId )
	if menu == nil or menu.Options == nil then return end
	local snapshot = Z.CaptureView( menu )
	local grid = menu.Tabs and menu.Tabs.grid
	local previousTabFirst = grid and grid.currentStartColumn or 1
	if menu.ComponentVersions ~= nil then menu.ComponentVersions:setText( L.Text( B.ComponentVersionsText( controller ) ) ) end
	local tabs = menu.ztCharacterOnly and { B.TabById.ztweaks_characters } or B.GetTabs( controller )
	local active = Z.FindTab( tabs, preferredId )
	if active ~= nil and not Z.TabEnabled( active, controller ) then active = nil end
	if active == nil then
		for _, tab in ipairs( tabs ) do if Z.TabEnabled( tab, controller ) then active = tab; break end end
	end
	if active == nil then return end
	menu.ztTabs = tabs
	for _, tab in ipairs( tabs ) do
		local source = menu.ztMenuName .. "Rows_" .. tab.id
		menu.ztDataSources[tab.id] = source
		Z.BuildDataSource( source, Z.TabRows( tab ), tab )
	end
	-- BO3 caches a GridLayout's item inventory by data-source name. Give each
	-- Give every registry rebuild a fresh identity so component enable changes
	-- immediately refresh disabled models instead of waiting for a reopen.
	menu.ztRegistryRevision = ( menu.ztRegistryRevision or 0 ) + 1
	menu.ztTabsDataSource = menu.ztMenuName .. "TabsLive_" .. tostring( menu.ztRegistryRevision )
	Z.BuildTabsDataSource( menu.ztTabsDataSource, tabs, active.id, controller )
	menu.Tabs.grid:setDataSource( menu.ztTabsDataSource )
	if grid.updateDataSource ~= nil then grid:updateDataSource() end
	Z.RestoreTabWindow( grid, #tabs, Z.FindTabIndex( tabs, active.id ), previousTabFirst )
	Z.ActivateTab( menu, controller, active.id, true )
	Z.RestoreView( menu, snapshot )
end

Z.QueueRegistryRefresh = function ( menu, controller, preferredId )
	if menu == nil then return end
	menu.ztPendingRegistryController = controller
	menu.ztPendingRegistryTabId = preferredId
	if menu.ztRegistryRefreshQueued == true then return end
	menu.ztRegistryRefreshQueued = true
	local refresh = function ()
		menu.ztRegistryRefreshQueued = nil
		local pendingController = menu.ztPendingRegistryController or controller
		local pendingTabId = menu.ztPendingRegistryTabId or preferredId
		menu.ztPendingRegistryController = nil
		menu.ztPendingRegistryTabId = nil
		Z.RefreshRegistry( menu, pendingController, pendingTabId )
	end
	-- Let the confirmation popup finish closing before rebuilding its parent.
	-- Rebuilding on the same UI tick can invalidate a bundle owner's rows while
	-- the overlay is still walking them.
	local ok, timer = pcall( LUI.UITimer.newElementTimer, 50, true, refresh )
	if ok and timer ~= nil then menu:addElement( timer ) else refresh() end
end

Z.NavigateTabDirection = function ( menu, controller, direction )
	if menu == nil or menu.Tabs == nil or menu.Tabs.grid == nil then return false end
	local target = Z.AdjacentTabIndex( menu.ztTabs, menu.ztActiveTabId, direction, controller )
	if target == nil then return false end
	local targetId = menu.ztTabs[target].id
	-- Rebuild under a fresh datasource identity and select the destination.
	-- Besides making both edges circular, this refreshes the dynamic CHANGED
	-- disabled state before GridLayout can skip its formerly-disabled model and
	-- guarantees that an off-screen selected category is scrolled into view.
	Z.RefreshRegistry( menu, controller, targetId )
	return true
end

Z.StopTabHold = function ( menu )
	if menu == nil then return end
	menu.ztTabHoldSource = nil
	menu.ztTabHoldDirection = nil
	menu.ztTabHoldEpoch = ( menu.ztTabHoldEpoch or 0 ) + 1
	if menu.ztTabHoldTimer ~= nil then
		pcall( menu.ztTabHoldTimer.close, menu.ztTabHoldTimer )
		menu.ztTabHoldTimer = nil
	end
end

Z.TabHoldBlocked = function ( menu )
	return menu == nil or menu.occludedBy ~= nil
end

Z.TabHoldSchedule = function ( menu, epoch, delay, controller, direction )
	local ok, timer = pcall( LUI.UITimer.newElementTimer, delay, true, function ()
		menu.ztTabHoldTimer = nil
		if menu.ztTabHoldEpoch ~= epoch or menu.ztTabHoldSource == nil then return end
		if Z.TabHoldBlocked( menu ) or not Z.NavigateTabDirection( menu, controller, direction ) then
			Z.StopTabHold( menu )
			return
		end
		if menu.ztTabHoldEpoch == epoch then Z.TabHoldSchedule( menu, epoch, 225, controller, direction ) end
	end )
	if ok and timer ~= nil then
		menu.ztTabHoldTimer = timer
		menu:addElement( timer )
	else
		Z.StopTabHold( menu )
	end
end

Z.StartTabHold = function ( menu, controller, direction, source )
	if menu == nil or Z.TabHoldBlocked( menu ) then return end
	if menu.ztTabHoldSource == source and menu.ztTabHoldDirection == direction then return end
	Z.StopTabHold( menu )
	menu.ztTabHoldSource = source
	menu.ztTabHoldDirection = direction
	local epoch = menu.ztTabHoldEpoch
	if not Z.NavigateTabDirection( menu, controller, direction ) or menu.ztTabHoldEpoch ~= epoch
		or Z.TabHoldBlocked( menu ) then
		Z.StopTabHold( menu )
		return
	end
	Z.TabHoldSchedule( menu, epoch, 350, controller, direction )
end

-- Merge raw and model edges. A raw release is authoritative; a zero written
-- by stock as a model acknowledgement is not a physical release while raw is
-- still down.
Z.TabHoldEdge = function ( menu, controller, source, direction, route, down )
	if menu == nil or type( down ) ~= "boolean" then return end
	menu.ztTabEdges = menu.ztTabEdges or {}
	local state = menu.ztTabEdges[source]
	if state == nil then state = {}; menu.ztTabEdges[source] = state end
	if state[route] == down then return end
	state[route] = down
	if route == "raw" then state.rawSeen = down end
	if not down and ( route == "raw" or not state.rawSeen ) then
		state.pressed = false
		if menu.ztTabHoldSource == source then Z.StopTabHold( menu ) end
	elseif down and not state.pressed then
		state.pressed = true
		Z.StartTabHold( menu, controller, direction, source )
	end
end

Z.TabHoldSources = { Q = -1, E = 1, LB = -1, RB = 1 }

Z.TabHoldModel = function ( menu, controller, source, model )
	local usable = Engine.IsControllerBeingUsed( controller ) or menu.unusedControllerAllowed
	local down = false
	if usable then
		local ok, got = pcall( function ()
			return CoD.BitUtility.IsBitwiseAndNonZero( Engine.GetModelValue( model ), Enum.LUIButtonFlags.FLAG_DOWN )
		end )
		down = ok and got == true
	end
	Z.TabHoldEdge( menu, controller, source, Z.TabHoldSources[source], "model", down )
end

Z.InstallHeldShortcutBitGuard = function ()
	if CoD.Menu == nil or type( CoD.Menu.HandleButtonPress ) ~= "function"
		or Z.HeldShortcutHandler == CoD.Menu.HandleButtonPress then return end
	local inherited = CoD.Menu.HandleButtonPress
	local wrapped = function ( menu, controller, button, model, ... )
		local models = menu ~= nil and menu.ztHeldShortcutModels or nil
		local source = models ~= nil and models[model] or nil
		if source == nil then return inherited( menu, controller, button, model, ... ) end
		Z.TabHoldModel( menu, controller, source, model )
	end
	Z.HeldShortcutHandler = wrapped
	CoD.Menu.HandleButtonPress = wrapped
end

Z.AttachMouseTabHold = function ( menu, button, controller, direction )
	local source = direction < 0 and "mouse_left" or "mouse_right"
	button:registerEventHandler( "leftmousedown", function ( element, event )
		element.ztMouseTabPress = true
		Z.StartTabHold( menu, event.controller or controller, direction, source )
		return true
	end )
	button:registerEventHandler( "leftmouseup", function ()
		if menu.ztTabHoldSource == source then Z.StopTabHold( menu ) end
		return true
	end )
	button:registerEventHandler( "mouseleave", function ()
		if menu.ztTabHoldSource == source then Z.StopTabHold( menu ) end
	end )
end

Z.AttachTabHoldInputs = function ( menu, controller )
	if menu == nil then return end
	if menu.Tabs ~= nil then menu.Tabs.m_disableNavigation = true end
	menu.ztHeldShortcutModels = {}
	local root = Engine.GetModelForController( controller )
	for source, path in pairs( {
		Q = "KeyPressBits.Q", E = "KeyPressBits.E",
		LB = "ButtonBits." .. Enum.LUIButton.LUI_KEY_LB,
		RB = "ButtonBits." .. Enum.LUIButton.LUI_KEY_RB
	} ) do
		local ok, model = pcall( Engine.GetModel, root, path )
		if ok and model ~= nil then
			menu.ztHeldShortcutModels[model] = source
			menu:subscribeToModel( model, function ( changed ) Z.TabHoldModel( menu, controller, source, changed ) end, false )
		end
	end
	local previous = menu.m_eventHandlers ~= nil and menu.m_eventHandlers.gamepad_button or nil
	menu:registerEventHandler( "gamepad_button", function ( element, event )
		local source = nil
		local button = event.button
		if button == "shoulderl" or button == "left_shoulder" or button == Enum.LUIButton.LUI_KEY_LB then source = "LB"
		elseif button == "shoulderr" or button == "right_shoulder" or button == Enum.LUIButton.LUI_KEY_RB then source = "RB"
		elseif button == "key_shortcut" and type( event.key ) == "string" then
			local key = string.upper( event.key )
			if key == "Q" or key == "E" then source = key end
		end
		if source ~= nil then
			Z.TabHoldEdge( element, event.controller or controller, source, Z.TabHoldSources[source], "raw", event.down )
			return true
		end
		if previous ~= nil then return previous( element, event ) end
	end )
end

Z.ResetRow = function ( controller, tab, row )
	if row == nil or not B.RowWritable( row, tab, controller ) or row.dvar == nil or row.dvar == "" then return false end
	local value = Z.SemanticDefault( row )
	if tab ~= nil and tab.owner ~= "ztweaks" and type( tab.set ) == "function" then
		local ok = pcall( tab.set, controller, row.dvar, value, row )
		return ok
	end
	if tab == nil or tab.owner == "ztweaks" then
		-- TabSet writes the semantic default to the live dvar, removes its packed
		-- storage value, and records a pending clear if storage is unavailable.
		Z.TabSet( controller, row.dvar, value, row )
		return true
	end
	return false
end

Z.ResetAll = function ( controller, menu )
	Z.ClearPicked()
	local preferredId = menu ~= nil and menu.ztActiveTabId or nil
	local flushedOwners = {}
	local resetOwners = {}
	local disabledOwners = {}
	local seenRows = {}
	local tabs = {}
	for _, tab in ipairs( B.Tabs or {} ) do table.insert( tabs, tab ) end
	if menu ~= nil and menu.ztCharacterOnly then tabs = menu.ztTabs end
	for _, tab in ipairs( tabs ) do
		if tab.role == nil then
			local owner = tostring( tab.owner or tab.id or "unknown" )
			-- Never pair row setters with an opaque reset from another tab.
			if tab.owner == "ztweaks" or type( tab.set ) == "function" then disabledOwners[owner] = true end
			for _, row in ipairs( Z.TabRows( tab ) ) do
				if not B.RowWritable( row, tab, controller ) then disabledOwners[owner] = true end
			end
		end
	end
	for _, tab in ipairs( tabs ) do
		if tab.role == nil then
			local owner = tostring( tab.owner or tab.id or "unknown" )
			local usedSetter = false
			for _, row in ipairs( Z.TabRows( tab ) ) do
				local key = owner .. "\0" .. tostring( row.dvar or "")
				if not seenRows[key] then
					seenRows[key] = true
					usedSetter = Z.ResetRow( controller, tab, row ) or usedSetter
				end
			end
			-- Legacy external components may expose an owner-wide reset but no
			-- row setter. Invoke that callback once per owner as a compatibility
			-- fallback; current components should expose set + flush.
			if B.HostStatus( controller ) == "HOST" and not usedSetter and not disabledOwners[owner] and type( tab.set ) ~= "function" and type( tab.reset ) == "function" and not resetOwners[owner] then
				pcall( tab.reset, controller, menu, tab )
				resetOwners[owner] = true
			end
			if type( tab.flush ) == "function" and not flushedOwners[owner] then
				pcall( tab.flush, controller, tab )
				flushedOwners[owner] = true
			end
		end
	end
	if Z.dirty then Z.Flush( controller ) end
	return preferredId
end

Z.ResetActiveOwner = function ( controller, menu )
	Z.ClearPicked()
	Z.ResetAll( controller, menu )
end

Z.ResetActiveTab = function ( controller, menu )
	Z.ClearPicked()
	local tab = menu ~= nil and menu.ztActiveTab or nil
	if tab == nil or tab.role ~= nil then return end
	local usedSetter = false
	local hasDisabledRow = false
	for _, row in ipairs( Z.TabRows( tab ) ) do
		if not B.RowWritable( row, tab, controller ) then hasDisabledRow = true end
		usedSetter = Z.ResetRow( controller, tab, row ) or usedSetter
	end
	-- Older registry providers may expose only an owner-wide reset callback.
	-- Match Reset All's compatibility fallback instead of silently doing
	-- nothing when their rows do not provide a setter.
	-- A legacy reset may also clear host settings absent from this tab.
	if B.HostStatus( controller ) == "HOST" and not usedSetter and not hasDisabledRow and type( tab.set ) ~= "function" and type( tab.reset ) == "function" then
		pcall( tab.reset, controller, menu, tab )
	end
	if type( tab.flush ) == "function" then pcall( tab.flush, controller, tab ) end
	if Z.dirty then Z.Flush( controller ) end
	return tab.id
end

Z.RandomizeActiveTab = function ( controller, menu )
	local tab = menu ~= nil and menu.ztActiveTab or nil
	if tab == nil or tab.role ~= nil then return end
	for _, row in ipairs( Z.TabRows( tab ) ) do
		if B.RowWritable( row, tab, controller ) and row.dvar ~= nil and row.dvar ~= "" then
			local choices = { Z.SemanticDefault( row ) }
			for _, value in ipairs( row.values or {} ) do
				if not Z.Same( value, row.default ) then table.insert( choices, value ) end
			end
			local value = choices[math.random( #choices )]
			if tab.owner == "ztweaks" then Z.TabSet( controller, row.dvar, value, row )
			elseif type( tab.set ) == "function" then pcall( tab.set, controller, row.dvar, value, row ) end
		end
	end
	-- The registry owner, not the visible renderer, owns persistence. External
	-- tabs therefore need their own commit callback just like Reset Tab does.
	if type( tab.flush ) == "function" then pcall( tab.flush, controller, tab ) end
	if Z.dirty then Z.Flush( controller ) end
	return tab.id
end

Z.AskRandomizeTab = function ( controller, settingsMenu )
	local overlayName = "ZTweaksSettingsRandomizeTab"
	CoD.OverlayUtility.AddSystemOverlay( overlayName, {
		menuName = "SystemOverlay_Compact", title = L.Text( "RANDOMIZE THIS TAB" ),
		description = L.Text( "Choose random values for every setting on this tab? GAME DEFAULT may be selected." ),
		categoryType = CoD.OverlayUtility.OverlayTypes.Alert,
		listDatasource = function ()
			DataSources.ZTweaksSettingsRandomizeTab_List = DataSourceHelpers.ListSetup( "ZTweaksSettingsRandomizeTab_List", function () return {
				{ models = { displayText = Engine.Localize( "MENU_NO" ) }, properties = { action = function ( self, element, c, param, menu ) GoBack( menu, c ) end } },
				{ models = { displayText = Engine.Localize( "MENU_YES" ) }, properties = { action = function ( self, element, c, param, menu )
					local preferredId = Z.RandomizeActiveTab( c, settingsMenu )
					GoBack( menu, c )
					-- Rebuild from fresh owner values after the overlay starts closing.
					-- Updating an occluded GridLayout can leave recycled selectors and
					-- the aggregate CHANGED tab showing their pre-action snapshot.
					Z.QueueRegistryRefresh( settingsMenu, c, preferredId )
				end } }
			} end, true, nil )
			return "ZTweaksSettingsRandomizeTab_List"
		end
	} )
	CoD.OverlayUtility.CreateOverlay( controller, settingsMenu, overlayName )
end

Z.ToggleChangedFilter = function ( controller, menu )
	local tab = menu ~= nil and menu.ztActiveTab or nil
	if tab == nil or tab.role ~= nil then return end
	menu.ztChangedOnly = not menu.ztChangedOnly
	local rows = Z.TabRows( tab )
	if menu.ztChangedOnly then
		local filtered = {}
		for _, row in ipairs( rows ) do
			if row.kind ~= "button" and not Z.IsDefault( Z.RowGet( row, tab, controller ), row ) then table.insert( filtered, row ) end
		end
		rows = filtered
	end
	menu.ztRows = rows
	-- GridLayout caches its item inventory by datasource name. Reusing the
	-- active source can leave the old row count visible after toggling this
	-- filter, so publish the filtered view under a fresh identity.
	menu.ztRowRevision = ( menu.ztRowRevision or 0 ) + 1
	menu.ztDataSource = menu.ztMenuName .. "RowsFilter_" .. tostring( tab.id ) .. "_" .. tostring( menu.ztRowRevision )
	menu.ztDataSources[tab.id] = menu.ztDataSource
	Z.BuildDataSource( menu.ztDataSource, rows, tab )
	menu.Options.savedActiveIndex = 0
	menu.Options:setDataSource( menu.ztDataSource )
	menu.Subtitle:setText( menu.ztChangedOnly and L.Format( "{hint}  FILTER: CHANGED", { hint = Z.OwnerWords( tab.hint, nil, tab ) } ) or Z.OwnerWords( tab.hint, nil, tab ) )
	Z.SyncScrollbar( menu )
end

Z.AskResetTab = function ( controller, settingsMenu )
	local overlayName = "ZTweaksSettingsResetTab"
	CoD.OverlayUtility.AddSystemOverlay( overlayName, {
		menuName = "SystemOverlay_Compact", title = L.Text( "RESET THIS TAB" ),
		description = L.Text( "Put every setting on this tab back to its default?" ),
		categoryType = CoD.OverlayUtility.OverlayTypes.Alert,
		listDatasource = function ()
			DataSources.ZTweaksSettingsResetTab_List = DataSourceHelpers.ListSetup( "ZTweaksSettingsResetTab_List", function () return {
				{ models = { displayText = Engine.Localize( "MENU_NO" ) }, properties = { action = function ( self, element, c, param, menu ) GoBack( menu, c ) end } },
				{ models = { displayText = Engine.Localize( "MENU_YES" ) }, properties = { action = function ( self, element, c, param, menu )
					local preferredId = Z.ResetActiveTab( c, settingsMenu )
					GoBack( menu, c )
					Z.QueueRegistryRefresh( settingsMenu, c, preferredId )
				end } }
			} end, true, nil )
			return "ZTweaksSettingsResetTab_List"
		end
	} )
	CoD.OverlayUtility.CreateOverlay( controller, settingsMenu, overlayName )
end

-- Use the game's normal destructive-action confirmation, with NO selected
-- first. Both the lobby and in-game pages call this shared implementation.
Z.AskReset = function ( controller, settingsMenu )
	local overlayName = "ZTweaksSettingsReset"
	CoD.OverlayUtility.AddSystemOverlay( overlayName, {
		menuName = "SystemOverlay_Compact",
		title = L.Text( "RESET TO DEFAULTS" ),
		description = L.Text( B.IsBundle() and "Put every registered mod setting back to its default?" or "Put every ZTweaks setting back to its default?" ),
		categoryType = CoD.OverlayUtility.OverlayTypes.Alert,
		listDatasource = function ()
			DataSources.ZTweaksSettingsReset_List = DataSourceHelpers.ListSetup( "ZTweaksSettingsReset_List", function ()
				return {
					{
						models = { displayText = Engine.Localize( "MENU_NO" ) },
						properties = {
							action = function ( self, element, choiceController, param, menu )
								GoBack( menu, choiceController )
							end
						}
					},
					{
						models = { displayText = Engine.Localize( "MENU_YES" ) },
						properties = {
							action = function ( self, element, choiceController, param, menu )
								local preferredId = settingsMenu ~= nil and settingsMenu.ztActiveTabId or nil
								Z.ResetActiveOwner( choiceController, settingsMenu )
								GoBack( menu, choiceController )
								-- One rebuild after every component owner has committed avoids
								-- stale CHANGED rows and avoids invalidating another owner's
								-- datasource while the confirmation overlay is still walking it.
								Z.QueueRegistryRefresh( settingsMenu, choiceController, preferredId )
							end
						}
					}
				}
			end, true, nil )
			return "ZTweaksSettingsReset_List"
		end
	} )
	CoD.OverlayUtility.CreateOverlay( controller, settingsMenu, overlayName )
end

Z.Back = function ( menu, controller )
	Z.StopTabHold( menu )
	for _, tab in ipairs( menu.ztCharacterOnly and menu.ztTabs or B.GetTabs() ) do
		if type( tab.flush ) == "function" then pcall( tab.flush, controller, tab ) end
	end
	GoBack( menu, controller )
	ClearSavedState( menu, controller )
end

Z.BundleVersion = function ()
	local value = B.BundleVersion or CoD.ZBundleVersion
	if type( value ) == "function" then
		local ok, result = pcall( value )
		value = ok and result or nil
	end
	if value == nil or value == "" then
		local dvar = Z.Get( "zbundle_version" )
		if dvar ~= "" then value = dvar end
	end
	return value
end

Z.EntryLabel = function ()
	return L.Text( B.IsBundle() and "ZBUNDLE SETTINGS" or "ZTWEAKS SETTINGS" )
end

Z.MenuTitle = function ( tabs, tab )
	if not B.IsBundle() then return L.Text( "ZTWEAKS SETTINGS" ) end
	local suffix = tab ~= nil and ( tab.owner == "zbundle" and tab.label or tab.ownerLabel or tab.owner ) or nil
	return suffix ~= nil and L.Format( "ZBUNDLE SETTINGS - {owner}", { owner = L.Text( string.upper( tostring( suffix ) ) ) } ) or L.Text( "ZBUNDLE SETTINGS" )
end

-- Lobby and pause use this same page so labels, scrolling, persistence and
-- footer actions cannot drift apart as the settings catalog grows.
Z.CreateMenu = function ( controller, menuName, characterOnly )
	Z.ClearPicked()
	require( "ui.uieditor.widgets.StartMenu.StartMenu_Options_Slider_Small" )
	require( "ui.uieditor.widgets.StartMenu.StartMenu_Options_Slider_Control_Item_Small" )
	require( "ui.uieditor.widgets.Lobby.Common.List1ButtonLarge_PH" )
	require( "ui.uieditor.widgets.TabbedWidgets.basicTabList" )
	require( "ui.uieditor.widgets.TabbedWidgets.paintshopTabWidget" )
	require( "ui.uieditor.widgets.BumperButtonWithKeyMouse" )
	Z.InstallHeldShortcutBitGuard()
	-- In-game offline-loadout storage can be unavailable when the pause menu
	-- first opens. Keep retrying pending reset/change transactions from the
	-- durable UI root even after this overlay closes.
	if LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil then
		Z.WatchEndGameAction( LUI.roots.UIRootFull )
	end

	-- The stock slider makes its arrows clickable but leaves the value text
	-- inert. TextBox belongs to each inner control item, not the outer slider.
	-- Give our inner item a center-click target that advances right; loopEdges
	-- on our option rows brings the last value back to DEFAULT.
	if CoD.ZTweaks_Options_Slider_Control_Item_Small == nil then
		CoD.ZTweaks_Options_Slider_Control_Item_Small = InheritFrom( CoD.StartMenu_Options_Slider_Control_Item_Small )
		CoD.ZTweaks_Options_Slider_Control_Item_Small.new = function ( owner, ownerController )
			local widget = CoD.StartMenu_Options_Slider_Control_Item_Small.new( owner, ownerController )
			widget:setClass( CoD.ZTweaks_Options_Slider_Control_Item_Small )
			widget:setLeftRight( true, false, 0, 215 )
			for _, arrow in ipairs( { widget.left, widget.right } ) do
				for _, part in ipairs( { arrow, arrow.arrow } ) do
					local inheritedAlpha = part.setAlpha
					part.setAlpha = function ( element, alpha, ... )
						return inheritedAlpha( element, widget.ztOptionLocked and 0 or alpha, ... )
					end
				end
			end
			local inheritedState = widget.setState
			widget.setState = function ( element, state, ... )
				if element.ztOptionLocked then state = "ArrowsHidden" end
				return inheritedState( element, state, ... )
			end
			local applyLock = function ( locked )
				if widget.ztOptionLocked == locked then return end
				widget.ztOptionLocked = locked
				widget:setState( locked and "ArrowsHidden" or "DefaultState" )
				widget.left:setAlpha( locked and 0 or 1 )
				widget.left.arrow:setAlpha( locked and 0 or 1 )
				widget.right:setAlpha( locked and 0 or 1 )
				widget.right.arrow:setAlpha( locked and 0 or 1 )
				widget.left:setHandleMouse( not locked )
				widget.right:setHandleMouse( not locked )
			end
			widget:linkToElementModel( widget, "ztOptionLocked", true, function ( model )
				local value = Engine.GetModelValue( model )
				applyLock( value == true or value == 1 or value == "1" or value == "true" )
			end )
			widget:linkToElementModel( widget, "text", true, function ( textModel )
				local model = widget:getModel( ownerController, "ztOptionLocked" )
				local value = model ~= nil and Engine.GetModelValue( model ) or nil
				local text = tostring( Engine.GetModelValue( textModel ) or "" )
				applyLock( value == true or value == 1 or value == "1" or value == "true"
					or string.find( text, "^DISABLED: " ) ~= nil or string.find( text, "^LOCKED: " ) ~= nil )
			end )
			widget.TextBox:setHandleMouse( true )
			widget.TextBox:registerEventHandler( "button_action", function ()
				if Z.ActivateFocusedButton( owner, ownerController, widget ) then return true end
				SendButtonPressToMenuEx( owner, ownerController, Enum.LUIButton.LUI_KEY_RIGHT )
				return true
			end )
			return widget
		end
	end
	if CoD.ZTweaks_Options_Slider_Small == nil then
		CoD.ZTweaks_Options_Slider_Small = InheritFrom( CoD.StartMenu_Options_Slider_Small )
		CoD.ZTweaks_Options_Slider_Small.new = function ( owner, ownerController )
			local widget = CoD.StartMenu_Options_Slider_Small.new( owner, ownerController )
			widget:setClass( CoD.ZTweaks_Options_Slider_Small )
			-- Reserve the final 20 units of the 520-unit list for its scrollbar.
			-- The remaining row is divided into equal label/value halves, and the
			-- inner value control is widened so its arrows reach both edges.
			widget:setLeftRight( true, false, 0, 500 )
			widget.StartMenuframenoBG0:setLeftRight( true, true, 0, -254 )
			widget.StartMenuframenoBG1:setLeftRight( true, true, 254, -1 )
			widget.Title:setLeftRight( true, false, 20, 230 )
			widget.Slider:setLeftRight( true, false, 270, 485 )
			widget.altText:setLeftRight( true, false, 254, 499 )
			widget.FocusBarB:setLeftRight( true, true, 254, -2 )
			widget.FocusBarT:setLeftRight( true, true, 254, -2 )
			widget.Slider:setWidgetType( CoD.ZTweaks_Options_Slider_Control_Item_Small )
			-- Bundle-owned pages prefix rows with the component name. Keep those
			-- labels on one line without changing the fixed row height or the list's
			-- scrollbar math. This subscription also restores the stock size when a
			-- recycled widget is assigned a shorter row.
			widget.Title:linkToElementModel( widget, "name", true, function ( model )
				local value = Engine.GetModelValue( model )
				local localizedName = value ~= nil and Engine.Localize( value ) or ""
				local halfHeight = L.Length( localizedName ) > 27 and 8.5 or 11
				widget.Title:setTopBottom( false, false, -halfHeight, halfHeight )
			end )
			-- Keep focus and hover, but style disabled/forced rows after every
			-- stock clip transition (which otherwise restores normal opacity).
			local applyState = function ()
				local state = widget.ztRowState
				widget:setAlpha( state == "DISABLED" and 0.52 or ( state == "OVERRIDDEN" and 0.72 or 1 ) )
				if state == "DISABLED" then widget.Title:setRGB( 0.68, 0.68, 0.68 )
				elseif state == "OVERRIDDEN" then widget.Title:setRGB( 1, 0.7, 0.4 )
				else widget.Title:setRGB( 1, 1, 1 ) end
			end
			widget:linkToElementModel( widget, "ztRowState", true, function ( model )
				widget.ztRowState = Engine.GetModelValue( model )
				applyState()
			end )
			LUI.OverrideFunction_CallOriginalSecond( widget, "setState", applyState )
			return widget
		end
	end
	if CoD.ZTweaks_TabWidget == nil then
		CoD.ZTweaks_TabWidget = InheritFrom( CoD.paintshopTabWidget )
		CoD.ZTweaks_TabWidget.new = function ( owner, ownerController )
			local widget = CoD.paintshopTabWidget.new( owner, ownerController )
			widget:setClass( CoD.ZTweaks_TabWidget )
			-- Six cells plus the five native two-unit gaps exactly fill the
			-- 1010-unit viewport. Do not center with firstElementXOffset: BO3's
			-- GridLayout then treats the incoming seventh item as partly visible
			-- and can advance the selection without scrolling that item on-screen.
			widget.getWidthInList = function () return 500 / 3 end
			return widget
		end
	end

	local tabs = characterOnly and { B.TabById.ztweaks_characters } or B.GetTabs( controller )
	local activeTab = nil
	for _, tab in ipairs( tabs ) do if Z.TabEnabled( tab, controller ) then activeTab = tab; break end end
	if activeTab == nil then return nil end
	local rows = Z.TabRows( activeTab )
	local rowSources = {}
	for _, tab in ipairs( tabs ) do
		local tabSource = menuName .. "Rows_" .. tab.id
		rowSources[tab.id] = tabSource
		Z.BuildDataSource( tabSource, Z.TabRows( tab ), tab )
	end
	local source = rowSources[activeTab.id]
	local tabSource = menuName .. "Tabs"
	Z.BuildTabsDataSource( tabSource, tabs, activeTab.id, controller )

	local self = CoD.Menu.NewForUIEditor( menuName )
	self.disablePopupOpenCloseAnim = true
	self.soundSet = "ChooseDecal"
	self:setOwner( controller )
	self:setLeftRight( true, true, 0, 0 )
	self:setTopBottom( true, true, 0, 0 )
	self:playSound( "menu_open", controller )
	self.buttonModel = Engine.CreateModel( Engine.GetModelForController( controller ), menuName .. ".buttonPrompts" )
	self.anyChildUsesUpdateState = true
	self.ztDataSource = source
	self.ztDataSources = rowSources
	self.ztRows = rows
	self.ztTabs = tabs
	self.ztActiveTab = activeTab
	self.ztAvailability = Z.AvailabilitySnapshot( self, controller )
	self.ztActiveTabId = activeTab.id
	self.ztTabPositions = {}
	self.ztMenuName = menuName
	self.ztCharacterOnly = characterOnly == true
	self.ztTabsDataSource = tabSource

	local background = LUI.UIImage.new()
	background:setLeftRight( true, true, 0, 0 )
	background:setTopBottom( true, true, 0, 0 )
	local hasBackgroundImage = B.BackgroundImageAvailable == true
	if hasBackgroundImage then
		background:setImage( RegisterImage( "zmods_menu_background_image" ) )
	else
		background:setRGB( 0, 0, 0 )
		background:setAlpha( 0.5 )
	end
	self:addElement( background )
	self.Background = background

	local shade = LUI.UIImage.new()
	shade:setLeftRight( true, true, 0, 0 )
	shade:setTopBottom( true, true, 0, 0 )
	shade:setRGB( 0, 0, 0 )
	shade:setAlpha( hasBackgroundImage and 0.34 or 0 )
	self:addElement( shade )
	self.Shade = shade

	local title = LUI.UIText.new()
	title:setLeftRight( true, false, 90, 720 )
	title:setTopBottom( true, false, 48, 98 )
	title:setText( L.Text( characterOnly and "CHARACTER PREFERENCES" or Z.MenuTitle( tabs, activeTab ) ) )
	title:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	title:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	title:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_MIDDLE )
	self:addElement( title )
	self.Title = title

	local ComponentVersions = LUI.UIText.new()
	ComponentVersions:setLeftRight( true, false, 90, 1190 )
	ComponentVersions:setTopBottom( true, false, 25, 42 )
	ComponentVersions:setText( L.Text( B.ComponentVersionsText( controller ) ) )
	ComponentVersions:setRGB( 0.72, 0.72, 0.72 )
	ComponentVersions:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	ComponentVersions:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	self:addElement( ComponentVersions )
	self.ComponentVersions = ComponentVersions

	local HostStatus = LUI.UIText.new()
	HostStatus:setLeftRight( true, false, 950, 1190 )
	HostStatus:setTopBottom( true, false, 48, 72 )
	HostStatus:setText( L.Text( B.HostStatus( controller ) ) )
	HostStatus:setRGB( 1, 0.55, 0.18 )
	HostStatus:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	HostStatus:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_RIGHT )
	self:addElement( HostStatus )
	self.HostStatus = HostStatus
	self.ztHostState = B.HostStatus( controller )

	local Subtitle = LUI.UIText.new()
	Subtitle:setLeftRight( true, false, 92, 1190 )
	Subtitle:setTopBottom( true, false, 97, 121 )
	Subtitle:setText( Z.OwnerWords( activeTab.hint or "", nil, activeTab ) )
	Subtitle:setRGB( 1, 0.55, 0.18 )
	Subtitle:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	Subtitle:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	Subtitle:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_MIDDLE )
	self:addElement( Subtitle )
	self.Subtitle = Subtitle

	local TabLeft = CoD.BumperButtonWithKeyMouse.new( self, controller )
	TabLeft:setLeftRight( true, false, 90, 135 )
	TabLeft:setTopBottom( true, false, 134, 164 )
	TabLeft:registerEventHandler( "button_action", function ( element )
		if element.ztMouseTabPress then element.ztMouseTabPress = nil; return true end
		SendButtonPressToMenuEx( self, controller, Enum.LUIButton.LUI_KEY_LB )
		return true
	end )
	self:addElement( TabLeft )
	self.TabLeft = TabLeft
	Z.AttachMouseTabHold( self, TabLeft, controller, -1 )

	local Tabs = CoD.basicTabList.new( self, controller )
	Tabs:setLeftRight( true, false, 135, 1145 )
	Tabs:setTopBottom( true, false, 129, 169 )
	Tabs.grid:setDataSource( tabSource )
	Tabs.grid:setWidgetType( CoD.ZTweaks_TabWidget )
	Tabs.grid:setLeftRight( true, true, 0, 0 )
	-- basicTabList parents its tab widgets under itemStencil. Stenciling the
	-- outer list or GridLayout does not clip those children; enable the private
	-- stencil itself and retain the stock six-column scrolling viewport.
	Tabs.grid.itemStencil:setUseStencil( true )
	Tabs.grid.usingStencil = true
	Tabs.grid:setHorizontalCount( 6 )
	self:addElement( Tabs )
	self.Tabs = Tabs

	local TabRight = CoD.BumperButtonWithKeyMouse.new( self, controller )
	TabRight:setLeftRight( true, false, 1145, 1190 )
	TabRight:setTopBottom( true, false, 134, 164 )
	TabRight.KeyMouseImage:setImage( RegisterImage( "uie_bumperright" ) )
	TabRight:subscribeToGlobalModel( controller, "Controller", "right_shoulder_button_image", function ( model )
		local image = Engine.GetModelValue( model )
		if image then TabRight.ControllerImage:setImage( RegisterImage( image ) ) end
	end )
	TabRight:registerEventHandler( "button_action", function ( element )
		if element.ztMouseTabPress then element.ztMouseTabPress = nil; return true end
		SendButtonPressToMenuEx( self, controller, Enum.LUIButton.LUI_KEY_RB )
		return true
	end )
	self:addElement( TabRight )
	self.TabRight = TabRight
	Z.AttachMouseTabHold( self, TabRight, controller, 1 )

	local TabPrevious = LUI.UIText.new()
	TabPrevious:setLeftRight( true, false, 135, 450 )
	TabPrevious:setTopBottom( true, false, 171, 189 )
	TabPrevious:setRGB( 1, 0.55, 0.18 )
	TabPrevious:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	TabPrevious:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	TabPrevious:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_MIDDLE )
	self:addElement( TabPrevious )
	self.TabPrevious = TabPrevious

	local TabPosition = LUI.UIText.new()
	TabPosition:setLeftRight( true, false, 540, 740 )
	TabPosition:setTopBottom( true, false, 171, 189 )
	TabPosition:setRGB( 0.72, 0.72, 0.72 )
	TabPosition:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	TabPosition:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_CENTER )
	TabPosition:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_MIDDLE )
	self:addElement( TabPosition )
	self.TabPosition = TabPosition

	local TabNext = LUI.UIText.new()
	TabNext:setLeftRight( true, false, 830, 1145 )
	TabNext:setTopBottom( true, false, 171, 189 )
	TabNext:setRGB( 1, 0.55, 0.18 )
	TabNext:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	TabNext:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_RIGHT )
	TabNext:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_MIDDLE )
	self:addElement( TabNext )
	self.TabNext = TabNext
	Z.UpdateTabNavigation( self, activeTab.id, controller )

	local Options = LUI.UIList.new( self, controller, 8, 0, nil, false, false, 0, 0, false, false )
	Options:makeFocusable()
	Options:setLeftRight( true, false, 90, 610 )
	Options:setTopBottom( true, false, 200, 641 )
	Options:setWidgetType( CoD.ZTweaks_Options_Slider_Small )
	Options:setVerticalCount( 7 )
	Options:setSpacing( 8 )
	Options:setDataSource( source )
	Options:setVerticalScrollbar( CoD.verticalScrollbar )
	self:addElement( Options )
	self.Options = Options
	Options.id = "Options"

	-- Shared lobby/in-game context panel. Linking it to the list's selected
	-- element keeps controller focus, keyboard navigation, and mouse hover in
	-- sync without maintaining a second selection state.
	local DetailsPanel = LUI.UIImage.new()
	DetailsPanel:setLeftRight( true, false, 640, 1190 )
	DetailsPanel:setTopBottom( true, false, 200, 545 )
	DetailsPanel:setRGB( 0.015, 0.02, 0.025 )
	DetailsPanel:setAlpha( 0.78 )
	self:addElement( DetailsPanel )
	self.DetailsPanel = DetailsPanel

	local DetailsAccent = LUI.UIImage.new()
	DetailsAccent:setLeftRight( true, false, 640, 1190 )
	DetailsAccent:setTopBottom( true, false, 200, 204 )
	DetailsAccent:setRGB( 1, 0.35, 0.06 )
	self:addElement( DetailsAccent )
	self.DetailsAccent = DetailsAccent

	local DetailsTitle = LUI.UIText.new()
	DetailsTitle:setLeftRight( true, false, 670, 1160 )
	DetailsTitle:setTopBottom( true, false, 225, 259 )
	DetailsTitle:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	DetailsTitle:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	DetailsTitle:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_TOP )
	self:addElement( DetailsTitle )
	self.DetailsTitle = DetailsTitle

	local DescriptionLabel = LUI.UIText.new()
	DescriptionLabel:setLeftRight( true, false, 670, 1160 )
	DescriptionLabel:setTopBottom( true, false, 277, 297 )
	DescriptionLabel:setText( L.Text( "DESCRIPTION" ) )
	DescriptionLabel:setRGB( 1, 0.55, 0.18 )
	DescriptionLabel:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	DescriptionLabel:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	DescriptionLabel:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_TOP )
	self:addElement( DescriptionLabel )
	self.DescriptionLabel = DescriptionLabel

	local DetailsDescription = LUI.UIText.new()
	DetailsDescription:setLeftRight( true, false, 670, 1160 )
	DetailsDescription:setTopBottom( true, false, 303, 325 )
	DetailsDescription:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	DetailsDescription:setLineSpacing( -1 )
	DetailsDescription:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	DetailsDescription:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_TOP )
	self:addElement( DetailsDescription )
	self.DetailsDescription = DetailsDescription

	local DefaultLabel = LUI.UIText.new()
	DefaultLabel:setLeftRight( true, false, 670, 800 )
	DefaultLabel:setTopBottom( true, false, 447, 469 )
	DefaultLabel:setText( L.Text( "DEFAULT" ) )
	DefaultLabel:setRGB( 1, 0.55, 0.18 )
	DefaultLabel:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	DefaultLabel:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	self:addElement( DefaultLabel )
	self.DefaultLabel = DefaultLabel

	local DetailsDefault = LUI.UIText.new()
	DetailsDefault:setLeftRight( true, false, 810, 1160 )
	DetailsDefault:setTopBottom( true, false, 447, 469 )
	DetailsDefault:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	DetailsDefault:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	self:addElement( DetailsDefault )
	self.DetailsDefault = DetailsDefault

	local AppliesLabel = LUI.UIText.new()
	AppliesLabel:setLeftRight( true, false, 670, 800 )
	AppliesLabel:setTopBottom( true, false, 485, 507 )
	AppliesLabel:setText( L.Text( "APPLIES" ) )
	AppliesLabel:setRGB( 1, 0.55, 0.18 )
	AppliesLabel:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	AppliesLabel:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	self:addElement( AppliesLabel )
	self.AppliesLabel = AppliesLabel

	local DetailsBoundary = LUI.UIText.new()
	DetailsBoundary:setLeftRight( true, false, 810, 1160 )
	DetailsBoundary:setTopBottom( true, false, 485, 507 )
	DetailsBoundary:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	DetailsBoundary:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	self:addElement( DetailsBoundary )
	self.DetailsBoundary = DetailsBoundary

	local ScopeLabel = LUI.UIText.new()
	ScopeLabel:setLeftRight( true, false, 670, 800 )
	ScopeLabel:setTopBottom( true, false, 519, 541 )
	ScopeLabel:setText( L.Text( "SCOPE" ) )
	ScopeLabel:setRGB( 1, 0.55, 0.18 )
	ScopeLabel:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	ScopeLabel:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	self:addElement( ScopeLabel )
	self.ScopeLabel = ScopeLabel

	local DetailsScope = LUI.UIText.new()
	DetailsScope:setLeftRight( true, false, 810, 1160 )
	DetailsScope:setTopBottom( true, false, 519, 541 )
	DetailsScope:setTTF( "fonts/RefrigeratorDeluxe-Regular.ttf" )
	DetailsScope:setAlignment( Enum.LUIAlignment.LUI_ALIGNMENT_LEFT )
	self:addElement( DetailsScope )
	self.DetailsScope = DetailsScope

	DetailsTitle:linkToElementModel( Options, "name", true, function ( model )
		local value = Engine.GetModelValue( model )
		if value then DetailsTitle:setText( L.Text( value ) ) end
	end )
	DetailsDescription:linkToElementModel( Options, "desc", true, function ( model )
		local value = Engine.GetModelValue( model )
		if value then DetailsDescription:setText( L.Text( value ) ) end
	end )
	DetailsDefault:linkToElementModel( Options, "defaultText", true, function ( model )
		local value = Engine.GetModelValue( model )
		if value then DetailsDefault:setText( L.Text( value ) ) end
	end )
	DefaultLabel:linkToElementModel( Options, "ztDefaultCaption", true, function ( model )
		DefaultLabel:setText( L.Text( Engine.GetModelValue( model ) or "DEFAULT" ) )
	end )
	AppliesLabel:linkToElementModel( Options, "ztBoundaryCaption", true, function ( model )
		AppliesLabel:setText( L.Text( Engine.GetModelValue( model ) or "APPLIES" ) )
	end )
	DetailsBoundary:linkToElementModel( Options, "boundaryText", true, function ( model )
		local value = Engine.GetModelValue( model )
		if value then DetailsBoundary:setText( L.Text( value ) ) end
	end )
	DetailsScope:linkToElementModel( Options, "scopeText", true, function ( model )
		local value = Engine.GetModelValue( model )
		if value then DetailsScope:setText( L.Text( value ) ) end
	end )
	Subtitle:linkToElementModel( Tabs.grid, "tabId", true, function ( model )
		local value = Engine.GetModelValue( model )
		if value then Z.ActivateTab( self, controller, value ) end
	end )

	local Back = CoD.List1ButtonLarge_PH.new( self, controller )
	Back:setLeftRight( true, false, 90, 185 )
	Back:setTopBottom( true, false, 654, 686 )
	Back.btnDisplayText:setText( L.Text( "BACK" ) )
	Back.btnDisplayTextStroke:setText( L.Text( "BACK" ) )
	self:addElement( Back )
	self.Back = Back
	Back.id = "Back"

	local Reset = CoD.List1ButtonLarge_PH.new( self, controller )
	Reset:setLeftRight( true, false, 195, 335 )
	Reset:setTopBottom( true, false, 654, 686 )
	Reset.btnDisplayText:setText( L.Text( "RESET TAB" ) )
	Reset.btnDisplayTextStroke:setText( L.Text( "RESET TAB" ) )
	self:addElement( Reset )
	self.Reset = Reset
	Reset.id = "Reset"

	local Randomize = CoD.List1ButtonLarge_PH.new( self, controller )
	Randomize:setLeftRight( true, false, 345, 475 )
	Randomize:setTopBottom( true, false, 654, 686 )
	Randomize.btnDisplayText:setText( L.Text( "RANDOMIZE" ) )
	Randomize.btnDisplayTextStroke:setText( L.Text( "RANDOMIZE" ) )
	self:addElement( Randomize )
	self.Randomize = Randomize
	Randomize.id = "Randomize"

	local ResetAll = CoD.List1ButtonLarge_PH.new( self, controller )
	ResetAll:setLeftRight( true, false, 485, 610 )
	ResetAll:setTopBottom( true, false, 654, 686 )
	ResetAll.btnDisplayText:setText( L.Text( "RESET ALL" ) )
	ResetAll.btnDisplayTextStroke:setText( L.Text( "RESET ALL" ) )
	self:addElement( ResetAll )
	self.ResetAll = ResetAll
	ResetAll.id = "ResetAll"

	Options.navigation = { down = Back }
	Back.navigation = { up = Options, right = Reset }
	Reset.navigation = { up = Options, left = Back, right = Randomize }
	Randomize.navigation = { up = Options, left = Reset, right = ResetAll }
	ResetAll.navigation = { up = Options, left = Randomize }
	CoD.Menu.AddNavigationHandler( self, self, controller )
	self:AddButtonCallbackFunction( self, controller, Enum.LUIButton.LUI_KEY_XBA_PSCROSS, "ENTER", function ()
		return Z.ActivateFocusedButton( self, controller )
	end, function ( element, menu )
		if Z.ActivateFocusedButton == nil then return false end
		CoD.Menu.SetButtonLabel( menu, Enum.LUIButton.LUI_KEY_XBA_PSCROSS, "MENU_SELECT" )
		return true
	end, false )
	local bindFooter = function ( button, action )
		button:registerEventHandler( "gain_focus", function ( element, event )
			local result = nil
			if element.gainFocus then
				result = element:gainFocus( event )
			elseif element.super.gainFocus then
				result = element.super:gainFocus( event )
			end
			CoD.Menu.UpdateButtonShownState( element, self, controller, Enum.LUIButton.LUI_KEY_XBA_PSCROSS )
			return result
		end )
		button:registerEventHandler( "lose_focus", function ( element, event )
			if element.loseFocus then
				return element:loseFocus( event )
			elseif element.super.loseFocus then
				return element.super:loseFocus( event )
			end
		end )
		self:AddButtonCallbackFunction( button, controller, Enum.LUIButton.LUI_KEY_XBA_PSCROSS, "ENTER", function ()
			action()
			return true
		end, function ( element, menu )
			CoD.Menu.SetButtonLabel( menu, Enum.LUIButton.LUI_KEY_XBA_PSCROSS, "MENU_SELECT" )
			return true
		end, false )
	end
	bindFooter( Reset, function () Z.AskResetTab( controller, self ) end )
	bindFooter( Randomize, function () Z.AskRandomizeTab( controller, self ) end )
	bindFooter( ResetAll, function () Z.AskReset( controller, self ) end )
	bindFooter( Back, function () Z.Back( self, controller ) end )
	self:AddButtonCallbackFunction( self, controller, Enum.LUIButton.LUI_KEY_XBB_PSCIRCLE, nil, function ()
		Z.Back( self, controller )
		return true
	end, function ( element, menu )
		CoD.Menu.SetButtonLabel( menu, Enum.LUIButton.LUI_KEY_XBB_PSCIRCLE, "MENU_BACK" )
		return true
	end, false )
	self:AddButtonCallbackFunction( self, controller, Enum.LUIButton.LUI_KEY_XBX_PSSQUARE, "R", function ()
		Z.AskReset( controller, self )
		return true
	end, function ( element, menu )
		CoD.Menu.SetButtonLabel( menu, Enum.LUIButton.LUI_KEY_XBX_PSSQUARE, L.Text( "RESET TO DEFAULTS" ) )
		return true
	end, false )
	self:AddButtonCallbackFunction( self, controller, Enum.LUIButton.LUI_KEY_XBY_PSTRIANGLE, "F", function ()
		Z.ToggleChangedFilter( controller, self )
		return true
	end, function ( element, menu )
		CoD.Menu.SetButtonLabel( menu, Enum.LUIButton.LUI_KEY_XBY_PSTRIANGLE, L.Text( "FILTER CHANGED" ) )
		return true
	end, false )
	self:AddButtonCallbackFunction( self, controller, Enum.LUIButton.LUI_KEY_LB, "Q", function ()
		return true
	end, AlwaysFalse, false )
	self:AddButtonCallbackFunction( self, controller, Enum.LUIButton.LUI_KEY_RB, "E", function ()
		return true
	end, AlwaysFalse, false )
	Z.AttachTabHoldInputs( self, controller )

	self:processEvent( { name = "menu_loaded", controller = controller } )
	self:processEvent( { name = "update_state", menu = self } )
	Z.SyncScrollbar( self )
	if not self:restoreState() then
		Options:processEvent( { name = "gain_focus", controller = controller } )
	end
	LUI.OverrideFunction_CallOriginalSecond( self, "close", function ( element )
		Z.Flush( controller )
		for _, tab in ipairs( element.ztCharacterOnly and element.ztTabs or B.GetTabs() ) do
			if type( tab.flush ) == "function" then pcall( tab.flush, controller, tab ) end
		end
		element.Options:close()
		element.Back:close()
		element.Reset:close()
		element.Randomize:close()
		element.ResetAll:close()
		element.TabRight:close()
		element.TabNext:close()
		element.TabPosition:close()
		element.TabPrevious:close()
		element.Tabs:close()
		element.TabLeft:close()
			element.ComponentVersions:close()
			element.HostStatus:close()
		element.Title:close()
		element.Subtitle:close()
		element.DetailsBoundary:close()
		element.DetailsScope:close()
		element.ScopeLabel:close()
		element.AppliesLabel:close()
		element.DetailsDefault:close()
		element.DefaultLabel:close()
		element.DetailsDescription:close()
		element.DescriptionLabel:close()
		element.DetailsTitle:close()
		element.DetailsAccent:close()
		element.DetailsPanel:close()
		element.Shade:close()
		element.Background:close()
		Engine.UnsubscribeAndFreeModel( Engine.GetModel( Engine.GetModelForController( controller ), menuName .. ".buttonPrompts" ) )
	end )
	local pollReport
	pollReport = function ()
		local status = B.HostStatus( controller )
		local availability = Z.AvailabilitySnapshot( self, controller )
		if self.occludedBy == nil and not self.m_inputDisabled
			and ( status ~= self.ztHostState or availability ~= self.ztAvailability ) then
			self.ztHostState = status
			self.HostStatus:setText( L.Text( status ) )
			Z.RefreshRegistry( self, controller, self.ztActiveTabId )
		end
		local report = CoD.ZTweaksCompat
		if self.ztActiveTabId == "ztweaks_report" and report ~= nil
			and self.ztReportRevision ~= report.revision then
			self.ztReportRevision = report.revision
			Z.RefreshRegistry( self, controller, "ztweaks_report" )
		end
		local ok, timer = pcall( LUI.UITimer.newElementTimer, 1000, true, pollReport )
		if ok and timer ~= nil then self:addElement( timer ) end
	end
	pollReport()
	return self
end

LUI.createMenu.ZTweaksSettings = function ( controller )
	return Z.CreateMenu( controller, "ZTweaksSettings" )
end

LUI.createMenu.ZTweaksCharacterPreferences = function ( controller )
	return Z.CreateMenu( controller, "ZTweaksCharacterPreferences", true )
end

if Engine.GetCurrentMap() == "core_frontend" then
	Z.Hook()
	if LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil then
		Z.WatchEndGameAction( LUI.roots.UIRootFull )
		Z.Wait( LUI.roots.UIRootFull, 0 )
	end
end

if LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil then
	Z.ListenCharacterProbe( LUI.roots.UIRootFull )
end

-- Stock ui_mp/t6/hud.lua requires Loading.lua before CoDUtilityRequire and
-- constructs the Loading menu later. Wrap only that constructor result so
-- other mods and the original loading/cinematic code retain full ownership.
if Z.loadingProbeHookVersion ~= "loadingProbe1" and type( CoD.Menu.NewFromState ) == "function" then
	Z.loadingProbeHookVersion = "loadingProbe1"
	local previous = CoD.Menu.NewFromState
	CoD.Menu.NewFromState = function ( name, ... )
		local menu = previous( name, ... )
		if name == "Loading" then Z.ListenLoadingCharacterProbe( menu ) end
		return menu
	end
end

-- The stock HUD require-list rawfile can lose an asset-priority race on T7x.
-- Register the gameplay hook from this module too: the settings loader is
-- required by the bundle menu, and per-menu guards make either load order safe.
-- Do not require gameplay-only compatibility Lua in the frontend: zm_mod is
-- not guaranteed to be loaded there yet.
if Z.settingsHudProbeHookVersion ~= "settingsProbe1" then
	Z.settingsHudProbeHookVersion = "settingsProbe1"
	local previous = CoD.Menu.NewForUIEditor
	CoD.Menu.NewForUIEditor = function ( name )
		local menu = previous( name )
		if name == "T7Hud_ZM" or string.sub( name or "", 1, 8 ) == "T7Hud_zm" then
			local controller = Engine.GetPrimaryController()
			Z.ListenCharacterProbe( menu, controller )
			Z.ListenEndGameAction( menu, controller )
			pcall( require, "ztweakscompat" )
			if CoD.ZTweaksCompat ~= nil and type( CoD.ZTweaksCompat.Listen ) == "function" then
				CoD.ZTweaksCompat.Listen( menu, controller )
			end
		end
		return menu
	end
end

-- Set this only after the complete settings runtime has installed.  The loose
-- __init__ route uses it to skip its remaining modules when ZBundle already
-- supplied the same owner through the fastfile (and vice versa).
Z.RuntimeLoaded = true
