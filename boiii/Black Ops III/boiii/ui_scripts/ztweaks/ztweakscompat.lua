-- Receive ZTweaks' gameplay-to-Lua compatibility packets without claiming
-- clientuimodel bits. The Compatibility page requests one paced snapshot,
-- whose row-zero packet is the match epoch; later packets contain changed rows only.
local Z = CoD.ZTweaksSettings
local R = CoD.ZTweaksCompat or {}
CoD.ZTweaksCompat = R
R.rows = R.rows or {}
R.epoch = R.epoch or 0
R.revision = R.revision or 0
if R.transportVersion ~= "scriptNotify4" then
    -- T7x can retain this Lua table while switching mod fastfiles. An old
    -- clientfield epoch must not make new notification rows appear current.
    R.transportVersion = "scriptNotify4"
    R.epoch = 0
    R.rows = {}
    R.revision = R.revision + 1
end
R.states = { [1] = "inherit", [2] = "active", [3] = "degraded", [4] = "unavailable", [5] = "conflict" }
R.reasons = {
    [1] = "activated the stock main-power finalizer without marking temporary-generator/web/defend objectives complete",
    [2] = "completed both stock water-wheel switches; Shangri-La's wait_for_power owns global activation",
    [3] = "composed before Revelations' per-player damage pipeline",
    [4] = "composed before the map's player-damage pipeline",
    [5] = "composed with a late map callback",
    [6] = "composed with late map and perk health owners",
    [7] = "composed with late map drop thresholds",
    [8] = "composed with late map round caps",
    [9] = "composed with the map's live bleed-out duration",
    [10] = "composed with the map's spawn movement scale",
    [11] = "custom/counter/quest blocker owners were preserved; no ordinary blocker was safe to claim",
    [12] = "first-round spawning began before the tweak could be applied",
    [13] = "generic inventory restoration would duplicate map quest weapons",
    [14] = "ignored an active duplicate at the pickup boundary",
    [15] = "independent safe box firearm selected for each player",
    [16] = "map and perk revive-time callbacks are composed before scaling",
    [17] = "map callback returned no spawn cadence",
    [18] = "map did not expose the standard round zombie total",
    [19] = "map does not enable standard score-threshold power-up drops",
    [20] = "map exposes no authoritative starting-weapon replacement seam",
    [21] = "map exposes no base player-health variable",
    [22] = "map exposes no composable player-damage override",
    [23] = "map exposes no initialized ordinary traversal blockers",
    [24] = "map exposes no initialized published perk/door power zones",
    [25] = "map exposes no initialized stock global-power consumers",
    [26] = "map exposes no registered perk list",
    [27] = "map exposes no registered weapon pool",
    [28] = "map exposes no safely owned timed effect storage",
    [29] = "map exposes no standard between-round delay callback",
    [30] = "map exposes no standard game-start delay",
    [31] = "map exposes no standard zombie spawn cadence callback",
    [32] = "map exposes no standard zombie-health curve",
    [33] = "map exposes no standard zombie-speed curve",
    [34] = "map has not published a finalized stock GobbleGum registry",
    [35] = "map has not published a perk-limit capability",
    [36] = "map has not published a registered timed power-up capability",
    [37] = "map has not published a standard Mystery Box",
    [38] = "map has not published a standard Mystery Box registry",
    [39] = "map has not published a standard power-up drop capability",
    [40] = "map has not published a standard power-up timeout capability",
    [41] = "map has not published an actor-damage callback",
    [42] = "map registered no activation-limited GobbleGums",
    [43] = "map registered no compatible carried weapons",
    [44] = "map registered no perks",
    [45] = "map registered no round-limited GobbleGums",
    [46] = "map registered no time-limited GobbleGums",
    [47] = "map starts with power already enabled",
    [48] = "map-composed candidates are preserved, while stock safety and ownership exclusions remain",
    [49] = "map-owned Insta-Kill override preserved",
    [50] = "map-owned or multi-FX timed lifecycle preserved",
    [51] = "map's published power consumers rejected activation",
    [52] = "map's starting loadout already fills every primary slot",
    [53] = "map's stock always-on power path completed",
    [54] = "map's stock always-on power path did not initialize",
    [55] = "map's stock global-power consumers rejected activation",
    [56] = "no second registered weapon matches the selected class",
    [57] = "opened every initialized ordinary door, linked barrier, debris group and Moon buy airlock",
    [58] = "opened initialized ordinary traversal blockers; custom, counter, cycling-airlock and quest owners were preserved",
    [59] = "ordinary enemy hits compose outside the map's actor-damage pipeline",
    [60] = "Origins did not publish all six generator consumer zones",
    [61] = "Origins exposes no initialized generator-consumer registry",
    [62] = "pickup-bound stock lifecycle owner",
    [63] = "pickup-owned fixed effects; timer-owned remaining effects",
    [64] = "player already owns every registered perk",
    [65] = "powered all four stock grids and their portals/Pack-a-Punch; ritual count and completion remain map-owned",
    [66] = "powered all six generator consumers; capture count and Pack-a-Punch progression remain map-owned",
    [67] = "powered all six stock traversal stairs and published perk/door transformers; quest outputs 20/21/23 remain map-owned",
    [68] = "powered published perk/door transformers; other Beast and quest interactions remain map-owned",
    [69] = "powered the map's published perk/door consumer zones",
    [70] = "powered the stock global consumers and Verruckt trap controls",
    [71] = "powered the stock global consumers, Pack-a-Punch and Giant traversal links",
    [72] = "Revelations exposes no initialized corruption-grid consumers",
    [73] = "Revelations' stock power consumers rejected activation",
    [74] = "scaled the stock baseline before map special-round thresholds",
    [75] = "selected equipment is not registered by this map",
    [76] = "selected grenade is not registered by this map",
    [77] = "selected weapon is not registered by this map",
    [78] = "Shadows exposes no complete six-stair/perk/door consumer registry",
    [79] = "Shadows exposes no initialized perk/door power zones",
    [80] = "Shadows' stock power consumers rejected activation",
    [81] = "Shadows' stock stair/perk/door consumers rejected activation",
    [82] = "Shangri-La exposes no initialized two-switch power route",
    [83] = "Shangri-La's stock two-switch power route did not complete",
    [84] = "standard Mystery Boxes disabled",
    [85] = "standard Mystery Boxes disabled; scripted quest rewards remain map-owned",
    [86] = "standard purchases and ZTweaks grants are blocked; scripted quest grants remain map-owned",
    [87] = "stock earned score is scaled; direct map score restoration remains map-owned",
    [88] = "stock exposes completion notifications but no safe per-player pre-use veto",
    [89] = "stock ordinary blocker routes did not publish completion",
    [90] = "stock purchase-triggered relocation disabled; explicit map/quest moves remain map-owned",
    [91] = "stock removes perks inside its private last-stand pipeline",
    [92] = "stock weapon grant rejected the registered Pack-a-Punch upgrade",
    [93] = "stock weapon grant rejected the selected firearm",
    [94] = "the map does not publish a safe starting-zone exit set",
    [95] = "the map exposes no standard bleed-out duration",
    [96] = "the map exposes no universal safe Pack-a-Punch disable callback",
    [97] = "the registered weapon pool cannot guarantee quest-safe replacement",
    [98] = "the selected starting weapon has no registered Pack-a-Punch upgrade",
    [99] = "unknown weapon class",
    [100] = "weapon assets still own the absolute engine ammo ceiling",
    [101] = "Zetsubou exposes no initialized main-power consumer",
    [102] = "Zetsubou's stock main-power consumer rejected activation",
    [103] = "custom or changed perk purchases remain map-owned",
    [104] = "map owns its perk purchase hints or prices",
    [105] = "map has no standard perk machines",
    [106] = "map exposes no standard health-regeneration delay",
    [107] = "map exposes no standard death-point penalty",
    [108] = "map owns a nonstandard death-point penalty",
    [109] = "map owns the primary-weapon limit",
    [110] = "map replaced the primary-weapon limit",
    [111] = "one-weapon-slot challenge takes precedence",
    [127] = "The game reported a newer compatibility reason; see the ZTweaks runtime log."
}
R.Read = function ( name )
    if R.epoch == 0 then
        -- ReportGet calls this only while rendering the Compatibility page.
        -- Ordinary map loading (including a disabled ZBundle component)
        -- must not send even readiness requests over the network.
        if R.StartSnapshot ~= nil then R.StartSnapshot() end
        return "not_reported", ""
    end
    local row = R.rows[name]
    if row == nil then return "not_reported", "" end
    return row.state, row.reason
end
R.AcceptPacket = function ( raw, bank )
    if raw == nil then return end
    local packet = tonumber( raw ) or 0
    if packet < 0 then packet = packet + 65536 end
    if packet == 0 then
        if bank == 1 then return end
        if R.epoch ~= 0 then
            R.epoch = 0
            R.rows = {}
            R.revision = R.revision + 1
        end
        return
    end
    local localIndex = math.floor( packet / 1024 )
    if localIndex == 0 then
        if bank == 1 then return end
        R.awaitingSnapshot = false
        if packet ~= R.epoch then
            R.epoch = packet
            R.rows = {}
            R.revision = R.revision + 1
        end
        return
    end
    if R.epoch == 0 then return end
    local stateCode = math.floor( packet / 128 ) % 8
    local reasonCode = packet % 128
    local index = localIndex + (bank == 1 and 63 or 0)
    local name = Z.ReportNames[index]
    local state = R.states[stateCode]
    if name == nil or state == nil then return end
    local reason = R.reasons[reasonCode] or ""
    local previous = R.rows[name]
    if previous == nil or previous.state ~= state or previous.reason ~= reason then
        R.rows[name] = { state = state, reason = reason }
        R.revision = R.revision + 1
    end
end

R.OnScriptNotify = function ( model )
    local event = Engine.GetModelValue( model )
    if event ~= "ztCompatPacket" and event ~= "ztCompatPacket2" then return end
    local data = CoD.GetScriptNotifyData( model )
    if data == nil then return end
    R.AcceptPacket( data[1], event == "ztCompatPacket2" and 1 or 0 )
end

R.Listen = function ( element, controller )
    if element == nil or element.ztCompatListening == true then return end
    if controller == nil or controller < 0 then return end
    element.ztCompatListening = true
    -- A persistent T7x Lua table can outlive a match. Do not show its stale
    -- statuses while this HUD waits for the new game's snapshot.
    R.epoch = 0
    R.rows = {}
    R.revision = R.revision + 1
    R.awaitingSnapshot = true
    R.snapshotWanted = false
    element:subscribeToGlobalModel( controller, "PerController", "scriptNotify", function ( model )
        R.OnScriptNotify( model )
    end )
    local attempts = 0
    local timer
    local request = function ()
        if not R.awaitingSnapshot or attempts >= 30 then
            if timer ~= nil then timer:close() end
            return
        end
        if not R.snapshotWanted then return end
        attempts = attempts + 1
        -- This is client -> server readiness only; the server owns the
        -- response pace and sends nothing to an unready joining player.
        pcall( Engine.SendMenuResponse, controller, "StartMenu_Main", "zt_compat_ready" )
    end
    R.StartSnapshot = function ()
        if R.snapshotWanted then return end
        local ok, map = pcall( Engine.GetCurrentMap )
        if not ok or map == nil or map == "" or map == "core_frontend" then return end
        R.snapshotWanted = true
        request()
    end
    local ok, created = pcall( LUI.UITimer.newElementTimer, 2000, false, request )
    if ok and created ~= nil then
        timer = created
        element:addElement( timer )
    end
end

if R.menuFactoryTransport ~= "scriptNotify4" then
    R.menuFactoryTransport = "scriptNotify4"
    R.menuFactoryHooked = true
    local previous = CoD.Menu.NewForUIEditor
    CoD.Menu.NewForUIEditor = function ( name )
        local menu = previous( name )
        if name ~= "T7Hud_ZM" and string.sub( name or "", 1, 8 ) ~= "T7Hud_zm" then return menu end
        local controller = Engine.GetPrimaryController()
        R.Listen( menu, controller )
        return menu
    end
end
