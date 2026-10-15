// ZSTATS T6 v1.2
// Passive Zombies telemetry, live HUD, round MVP feed, and game-over awards.

// Every raw Plutonium GSC is linked independently, including each component
// inside ZBundle.  Keep ZStats' stock dependencies local to this script;
// includes in ZPause/ZShare do not make their exports visible here.
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\gametypes_zm\_hud_util;

init()
{
    if ( isdefined( level.zstats_loaded ) )
        return;

    level.zstats_loaded = 1;
    level.zstats = spawnstruct();
    level.zstats.match_start = undefined;
    level.zstats.round_start = undefined;
    level.zstats.current_round = 0;
    level.zstats.round_serial = 0;
    level.zstats.in_round = 0;
    level.zstats.round_start_seen = 0;
    level.zstats.round_end_seen = 0;
    level.zstats.pending_round_completion = 0;
    level.zstats.pending_round_number = 0;
    level.zstats.pending_round_end_time = undefined;
    level.zstats.pending_round_mvp_candidates = [];
    level.zstats.game_over_signal = 0;
    level.zstats.departed_snapshots = [];
    level.zstats.next_player_id = 1;
    level.zstats.metrics = [];
    level.zstats.metric_by_id = [];
    level.zstats.awards = [];
    level.zstats.award_by_id = [];
    level.zstats.metrics_frozen = 0;
    level.zstats.registration_open = 1;
    level.zstats.registration_started = gettime();
    level.zstats.accepting_values = 0;
    level.zstats.capabilities = spawnstruct();
    level.zstats.capabilities.score_total = 0;
    level.zstats.capabilities.zombies_left = 0;
    level.zstats.capabilities.round_events = 0;
    level.zstats.capabilities.round_timing = 0;
    level.zstats.capabilities.round_fallback = 0;
    level.zstats.capabilities.spending_events = zs_stock_spending_contract();

    zs_set_defaults();
    level.zstats.enabled = zs_cfg_int( "zstats_enabled", 1 );
    level.zstats.supported_mode = zs_mode_supported();
    zs_register_self();
    level notify( "zstats_ready" );

    // Keep the descriptor available to ZBundle, but do not install any HUD,
    // telemetry, round, or recap threads while the component is disabled.
    if ( !level.zstats.enabled )
    {
        zs_api_close_registration();
        return;
    }
    if ( !level.zstats.supported_mode )
    {
        zs_api_close_registration();
        level thread zs_unsupported_mode_notice();
        return;
    }

    level thread zs_build_watermark();
    zs_reserve_recap_time();
    level.zstats.accepting_values = 1;

    level thread zs_registration_watch();
    level thread zs_match_start_watch();
    level thread zs_player_watch();
    level thread zs_spent_points_watch();
    level thread zs_round_watch();
    level thread zs_round_end_watch();
    level thread zs_time_bomb_save_watch();
    level thread zs_time_bomb_restore_watch();
    level thread zs_end_game_signal_watch();
    level thread zs_game_over_watch();
}

zs_mark_match_started()
{
    if ( isdefined( level.zstats.match_start ) )
        return;

    level.zstats.match_start = gettime();
    if ( !isdefined( level.zstats.round_start ) )
        level.zstats.round_start = level.zstats.match_start;
}

zs_match_start_watch()
{
    while ( !isdefined( level.zstats.match_start ) )
    {
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            if ( zs_player_ready( players[i] ) )
            {
                zs_mark_match_started();
                return;
            }
        }
        wait 0.05;
    }
}

zs_mode_supported()
{
    mode = getdvar( "ui_gametype" );
    if ( isdefined( level.scr_zm_ui_gametype ) )
        mode = level.scr_zm_ui_gametype;
    return mode != "zgrief" && mode != "zmeat" && mode != "zcleansed";
}

zs_map_script()
{
    if ( isdefined( level.script ) )
        return tolower( "" + level.script );
    return tolower( getdvar( "mapname" ) );
}

zs_stock_spending_contract()
{
    script = zs_map_script();
    return script == "zm_transit" || script == "zm_transit_dr" || script == "zm_nuked" ||
        script == "zm_highrise" || script == "zm_prison" || script == "zm_buried" ||
        script == "zm_tomb";
}

zs_unsupported_mode_notice()
{
    while ( 1 )
    {
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            if ( zs_player_spawned( players[i] ) )
            {
                players[i] iprintlnbold( "^5ZStats^7 is disabled for this alternate Zombies mode" );
                return;
            }
        }
        wait 0.1;
    }
}

zs_set_defaults()
{
    set_dvar_if_unset( "zstats_enabled", "1" );
    set_dvar_if_unset( "zs_pb_scope", "career" );
    set_dvar_if_unset( "zs_pb_round_announce", "1" );
    set_dvar_if_unset( "zs_hud_enabled", "1" );
    set_dvar_if_unset( "zs_hud_position", "top_right" );
    set_dvar_if_unset( "zs_hud_scale", "100" );
    set_dvar_if_unset( "zs_hud_preset", "compact" );
    set_dvar_if_unset( "zs_scoreboard_hud_preset", "detailed" );
    set_dvar_if_unset( "zs_hud_opacity", "22" );
    set_dvar_if_unset( "zs_hud_header", "1" );
    set_dvar_if_unset( "zs_hud_time", "1" );
    set_dvar_if_unset( "zs_hud_zombies_left", "1" );
    set_dvar_if_unset( "zs_hud_ppr", "1" );
    set_dvar_if_unset( "zs_hud_kpr", "1" );
    set_dvar_if_unset( "zs_hud_round_time", "0" );
    set_dvar_if_unset( "zs_hud_score", "0" );
    set_dvar_if_unset( "zs_hud_round_kills", "0" );
    set_dvar_if_unset( "zs_hud_round_points", "0" );
    set_dvar_if_unset( "zs_hud_headshots", "0" );
    set_dvar_if_unset( "zs_hud_round_revives", "0" );
    set_dvar_if_unset( "zs_hud_round_number", "0" );
    set_dvar_if_unset( "zs_hud_personal_best", "1" );
    set_dvar_if_unset( "zs_round_report", "1" );
    set_dvar_if_unset( "zs_game_over_report", "1" );
    set_dvar_if_unset( "zs_show_lowlights", "0" );
    set_dvar_if_unset( "zs_recap_seconds", "20" );
}

zs_cfg_int( name, default_value )
{
    value = getdvar( name );
    if ( value == "" )
        return default_value;
    return int( value );
}

zs_cfg_string( name, default_value )
{
    value = getdvar( name );
    if ( value == "" )
        return default_value;
    return value;
}

zs_register_self()
{
    if ( !isdefined( level.zmods ) )
        level.zmods = [];
    if ( !isdefined( level.zmods["zstats"] ) )
        level.zmods["zstats"] = spawnstruct();

    // Version-one ZBundle descriptor. Update the existing object in place so
    // consumers never lose a reference when initialization is retried.
    mod = level.zmods["zstats"];
    mod.id = "zstats";
    mod.display_name = "ZStats";
    mod.version = zs_version();
    mod.api_version = 1;
    mod.enabled = level.zstats.enabled;
    mod.supported = level.zstats.supported_mode;
    mod.ready = 1;
    mod.registration_open = level.zstats.registration_open;
    mod.settings_manifest_version = 2;
    mod.reload_config = ::zs_api_reload_config;
    mod.get_player_snapshot = ::zs_api_get_player_snapshot;
    mod.get_match_value = ::zs_api_get_match_value;
    mod.get_round_value = ::zs_api_get_round_value;
    mod.register_metric = ::zs_api_register_metric;
    mod.add_value = ::zs_api_add_value;
    mod.register_award = ::zs_api_register_award;
    mod.close_registration = ::zs_api_close_registration;
    mod.get_capabilities = ::zs_api_get_capabilities;
}

zs_api_get_capabilities()
{
    result = spawnstruct();
    result.supported_mode = level.zstats.supported_mode;
    result.score_total = level.zstats.capabilities.score_total;
    result.zombies_left = level.zstats.capabilities.zombies_left;
    result.round_events = level.zstats.capabilities.round_events;
    result.round_timing = level.zstats.capabilities.round_timing;
    result.round_fallback = level.zstats.capabilities.round_fallback;
    result.spending_events = level.zstats.capabilities.spending_events;
    return result;
}

zs_api_close_registration()
{
    if ( !level.zstats.registration_open )
        return 1;
    level.zstats.registration_open = 0;
    level.zstats.metrics_frozen = 1;
    level.zmods["zstats"].registration_open = 0;
    level notify( "zstats_registration_closed" );
    return 1;
}

zs_registration_watch()
{
    while ( level.zstats.registration_open )
    {
        if ( isdefined( level.zstats_registration_complete ) && level.zstats_registration_complete )
        {
            zs_api_close_registration();
            return;
        }
        if ( gettime() - level.zstats.registration_started >= 1000 )
        {
            players = getplayers();
            for ( i = 0; i < players.size; i++ )
            {
                if ( zs_player_spawned( players[i] ) )
                {
                    zs_api_close_registration();
                    return;
                }
            }
        }
        wait 0.05;
    }
}

zs_api_reload_config()
{
    // Presentation settings are read directly from dvars by the HUD/recap.
    // Keeping this callable makes a shared config reload explicit and never
    // resets telemetry accumulated by the active match.
    return level.zstats.enabled;
}

zs_api_namespaced_id( owner, id )
{
    if ( !isdefined( owner ) || !isstring( owner ) || owner == "" || !isdefined( id ) || !isstring( id ) )
        return 0;
    prefix = owner + ":";
    return id.size > prefix.size && getsubstr( id, 0, prefix.size ) == prefix;
}

zs_api_stock_metric( id )
{
    return id == "kills" || id == "headshots" || id == "revives" || id == "downs" ||
        id == "doors" || id == "barriers" || id == "boards" || id == "melee_kills" ||
        id == "score" || id == "points_earned" || id == "points_spent" ||
        id == "perks_acquired" || id == "perks" || id == "round_kills" ||
        id == "round_headshots" || id == "round_revives" || id == "round_downs" ||
        id == "round_points_earned" || id == "round_points_spent" ||
        id == "match_elapsed_ms" || id == "round_elapsed_ms" || id == "current_round";
}

zs_api_metric_same( left, right )
{
    return left.owner == right.owner && left.id == right.id && left.label == right.label &&
        left.scope == right.scope && left.default_value == right.default_value &&
        left.higher_is_better == right.higher_is_better && left.hud_allowed == right.hud_allowed &&
        left.award_allowed == right.award_allowed;
}

zs_api_register_metric( owner, definition )
{
    if ( !level.zstats.enabled || !level.zstats.registration_open || level.zstats.metrics_frozen || !isdefined( definition ) ||
        !zs_api_namespaced_id( owner, definition.id ) || !isdefined( definition.label ) ||
        !isstring( definition.label ) || !isdefined( definition.scope ) ||
        ( definition.scope != "match" && definition.scope != "round" ) ||
        !zs_numeric( definition.default_value ) || !zs_numeric( definition.higher_is_better ) ||
        !zs_numeric( definition.hud_allowed ) || !zs_numeric( definition.award_allowed ) )
        return 0;

    existing = level.zstats.metric_by_id[definition.id];
    candidate = spawnstruct();
    candidate.owner = owner;
    candidate.id = definition.id;
    candidate.label = zs_display_text( definition.label, 24 );
    candidate.scope = definition.scope;
    candidate.default_value = definition.default_value;
    candidate.higher_is_better = int( definition.higher_is_better != 0 );
    candidate.hud_allowed = int( definition.hud_allowed != 0 );
    candidate.award_allowed = int( definition.award_allowed != 0 );
    if ( isdefined( existing ) )
        return zs_api_metric_same( existing, candidate );
    level.zstats.metric_by_id[candidate.id] = candidate;
    level.zstats.metrics[level.zstats.metrics.size] = candidate;
    return 1;
}

zs_api_award_same( left, right )
{
    return left.owner == right.owner && left.id == right.id && left.label == right.label &&
        left.metric_id == right.metric_id && left.lowest == right.lowest &&
        left.allow_ties == right.allow_ties && left.show_zero == right.show_zero &&
        left.lowlight == right.lowlight && left.order == right.order;
}

zs_api_register_award( owner, definition )
{
    if ( !level.zstats.enabled || !level.zstats.registration_open || !isdefined( definition ) || !zs_api_namespaced_id( owner, definition.id ) ||
        !isdefined( definition.label ) || !isstring( definition.label ) ||
        !isdefined( definition.metric_id ) || !isstring( definition.metric_id ) ||
        !zs_numeric( definition.lowest ) || !zs_numeric( definition.allow_ties ) ||
        !zs_numeric( definition.show_zero ) || !zs_numeric( definition.lowlight ) ||
        !zs_numeric( definition.order ) )
        return 0;
    metric = level.zstats.metric_by_id[definition.metric_id];
    if ( !zs_api_stock_metric( definition.metric_id ) && ( !isdefined( metric ) || !metric.award_allowed ) )
        return 0;

    candidate = spawnstruct();
    candidate.owner = owner;
    candidate.id = definition.id;
    candidate.label = zs_display_text( definition.label, 24 );
    candidate.metric_id = definition.metric_id;
    candidate.lowest = int( definition.lowest != 0 );
    candidate.allow_ties = int( definition.allow_ties != 0 );
    candidate.show_zero = int( definition.show_zero != 0 );
    candidate.lowlight = int( definition.lowlight != 0 );
    candidate.order = definition.order;
    existing = level.zstats.award_by_id[candidate.id];
    if ( isdefined( existing ) )
        return zs_api_award_same( existing, candidate );
    at = level.zstats.awards.size;
    for ( i = 0; i < level.zstats.awards.size; i++ )
    {
        if ( candidate.order < level.zstats.awards[i].order )
        {
            at = i;
            break;
        }
    }
    for ( i = level.zstats.awards.size; i > at; i-- )
        level.zstats.awards[i] = level.zstats.awards[i - 1];
    level.zstats.awards[at] = candidate;
    level.zstats.award_by_id[candidate.id] = candidate;
    return 1;
}

zs_api_add_value( player, id, delta )
{
    if ( !level.zstats.enabled || !level.zstats.accepting_values || !isdefined( player ) || !isplayer( player ) ||
        !isdefined( player.zstats ) || !isdefined( id ) || !isstring( id ) ||
        !zs_numeric( delta ) || delta != delta || delta - delta != 0 )
        return 0;
    metric = level.zstats.metric_by_id[id];
    if ( !isdefined( metric ) )
        return 0;
    if ( metric.scope == "round" )
        player.zstats.custom_round[id] += delta;
    else
        player.zstats.custom_match[id] += delta;
    return 1;
}

zs_version()
{
    // ZS_VERSION_BEGIN
    return "1.2";
    // ZS_VERSION_END
}

zs_player_watch()
{
    level endon( "end_game" );

    while ( 1 )
    {
        if ( level.zstats.registration_open )
        {
            wait 0.05;
            continue;
        }
        zs_reconcile_round_state();
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            if ( !isdefined( players[i].zstats_tracking ) && zs_player_ready( players[i] ) )
                players[i] zs_start_player();
        }
        wait 0.5;
    }
}

zs_player_spawned( player )
{
    if ( !isdefined( player ) || !isplayer( player ) )
        return 0;
    if ( isdefined( player.hasspawned ) )
        return player.hasspawned;
    return isdefined( player.sessionstate ) && player.sessionstate == "playing" && isalive( player );
}

zs_stock_round_start_time()
{
    if ( zs_numeric( level.round_start_time ) && level.round_start_time > 0 && level.round_start_time <= gettime() )
        return level.round_start_time;
    return -1;
}

zs_reconcile_round_state()
{
    if ( !zs_numeric( level.round_number ) || level.round_number < 1 )
        return;

    round_number = int( level.round_number );
    // Proven event streams own the current numbered lifecycle, but a custom
    // map may stop notifying later. Recover only when its number advances.
    if ( level.zstats.capabilities.round_events && level.zstats.round_serial > 0 && level.zstats.current_round == round_number )
        return;

    active = zs_active_zombie_count();
    queued = 0;
    if ( zs_numeric( level.zombie_total ) )
        queued = int( level.zombie_total );
    if ( active <= 0 && queued <= 0 )
    {
        if ( level.zstats.capabilities.round_fallback )
            level.zstats.in_round = 0;
        return;
    }

    if ( level.zstats.round_serial > 0 && level.zstats.current_round == round_number )
    {
        stock_round_start = zs_stock_round_start_time();
        if ( !level.zstats.capabilities.round_timing && stock_round_start >= 0 )
        {
            level.zstats.round_start = stock_round_start;
            level.zstats.capabilities.round_timing = 1;
        }
        level.zstats.in_round = 1;
        return;
    }

    if ( level.zstats.round_serial > 0 )
    {
        if ( level.zstats.pending_round_completion )
            zs_finalize_pending_round();
        else
        {
            players = getplayers();
            for ( i = 0; i < players.size; i++ )
                players[i] zs_finalize_round();
        }
    }
    level.zstats.round_serial++;
    level.zstats.current_round = round_number;
    level.zstats.capabilities.round_timing = 0;
    stock_round_start = zs_stock_round_start_time();
    if ( stock_round_start >= 0 )
    {
        level.zstats.round_start = stock_round_start;
        level.zstats.capabilities.round_timing = 1;
    }
    else
        level.zstats.round_start = gettime();
    level.zstats.in_round = 1;
    level.zstats.capabilities.round_fallback = 1;
    zs_mark_match_started();
    players = getplayers();
    for ( i = 0; i < players.size; i++ )
        players[i] zs_begin_round( round_number );
}

zs_player_ready( player )
{
    return isdefined( player ) && isplayer( player ) &&
        isdefined( player.sessionstate ) && player.sessionstate == "playing" &&
        zs_player_spawned( player ) &&
        isdefined( player.pers ) && zs_numeric( player.pers["score"] ) &&
        zs_numeric( player.pers["kills"] );
}

zs_gameplay_ready()
{
    // Player entities can become playable before stock intro ownership ends.
    // Keep live HUD allocation and text publication behind the common round
    // lifecycle flag so long cinematics cannot accumulate reliable updates.
    return isdefined( level.flag ) && isdefined( level.flag["start_zombie_round_logic"] ) && level.flag["start_zombie_round_logic"];
}

zs_pb_clamp( value, maximum )
{
    if ( !isdefined( value ) )
        return 0;
    value = int( value );
    if ( value < 0 )
        return 0;
    if ( value > maximum )
        return maximum;
    return value;
}

zs_pb_scope_career()
{
    return isdefined( self.zstats ) && isdefined( self.zstats.pb_scope ) && self.zstats.pb_scope == "career";
}

zs_pb_publish_update()
{
    self.zstats.pb_update_epoch = self.zstats.pb_update_epoch % 65534 + 1;
    record = "" + self.zstats.pb_update_epoch + "|" + self.zstats.career_best_round_kills + "|" +
        self.zstats.career_best_round_headshots + "|" + self.zstats.career_best_round_melee_kills + "|" +
        self.zstats.career_best_round_points + "|" + self.zstats.career_best_round_revives + "|" +
        self.zstats.career_best_kpr_tenths + "|" + self.zstats.career_best_ppr_tenths + "|" +
        int( self.zstats.career_fastest_round / 100 ) + "|" +
        self.zstats.career_best_match_earned + "|" + self.zstats.career_best_match_kills + "|" +
        self.zstats.career_highest_round;
    self setclientdvar( "zs_pb_update", record );
}

zs_pb_apply_record( response )
{
    tokens = strtok( response, "|" );
    if ( ( tokens.size != 14 && tokens.size != 15 ) || tokens[0] != "zstats_pb" || int( tokens[1] ) != self.zstats.pb_request_epoch )
        return 0;
    if ( tokens[2] != "career" && tokens[2] != "match" )
        return 0;
    self.zstats.pb_scope = tokens[2];
    value_offset = 0;
    self.zstats.pb_announce = 1;
    if ( tokens.size == 15 )
    {
        self.zstats.pb_announce = int( tokens[3] ) != 0;
        value_offset = 1;
    }
    incoming = [];
    incoming[1] = zs_pb_clamp( tokens[3 + value_offset], 32767 );
    incoming[2] = zs_pb_clamp( tokens[4 + value_offset], 32767 );
    incoming[3] = zs_pb_clamp( tokens[5 + value_offset], 32767 );
    incoming[4] = zs_pb_clamp( tokens[6 + value_offset], 1048575 );
    incoming[5] = zs_pb_clamp( tokens[7 + value_offset], 32767 );
    incoming[6] = zs_pb_clamp( tokens[8 + value_offset], 1048575 );
    incoming[7] = zs_pb_clamp( tokens[9 + value_offset], 1048575 );
    incoming[8] = zs_pb_clamp( tokens[10 + value_offset], 1048575 );
    incoming[9] = zs_pb_clamp( tokens[11 + value_offset], 2097151 );
    incoming[10] = zs_pb_clamp( tokens[12 + value_offset], 32767 );
    incoming[11] = zs_pb_clamp( tokens[13 + value_offset], 1023 );
    current = [];
    current[1] = self.zstats.career_best_round_kills;
    current[2] = self.zstats.career_best_round_headshots;
    current[3] = self.zstats.career_best_round_melee_kills;
    current[4] = self.zstats.career_best_round_points;
    current[5] = self.zstats.career_best_round_revives;
    current[6] = self.zstats.career_best_kpr_tenths;
    current[7] = self.zstats.career_best_ppr_tenths;
    current[8] = int( self.zstats.career_fastest_round / 100 );
    current[9] = self.zstats.career_best_match_earned;
    current[10] = self.zstats.career_best_match_kills;
    current[11] = self.zstats.career_highest_round;
    publish = 0;
    for ( i = 1; i <= 11; i++ )
    {
        keep_current = i == 8 && current[i] > 0 && ( incoming[i] <= 0 || current[i] < incoming[i] );
        if ( i != 8 ) keep_current = current[i] > incoming[i];
        if ( keep_current ) publish = 1;
        else current[i] = incoming[i];
    }
    self.zstats.career_best_round_kills = current[1];
    self.zstats.career_best_round_headshots = current[2];
    self.zstats.career_best_round_melee_kills = current[3];
    self.zstats.career_best_round_points = current[4];
    self.zstats.career_best_round_revives = current[5];
    self.zstats.career_best_kpr_tenths = current[6];
    self.zstats.career_best_ppr_tenths = current[7];
    self.zstats.career_fastest_round = current[8] * 100;
    self.zstats.career_best_match_earned = current[9];
    self.zstats.career_best_match_kills = current[10];
    self.zstats.career_highest_round = current[11];
    self.zstats.pb_loaded = 1;
    if ( publish ) self zs_pb_publish_update();
    return 1;
}

zs_pb_reset_record( response )
{
    tokens = strtok( response, "|" );
    if ( tokens.size != 11 || tokens[0] != "zstats_pb_reset" )
        return 0;
    if ( tokens[2] != "career" && tokens[2] != "match" )
        return 0;
    self.zstats.pb_scope = tokens[2];
    self.zstats.career_best_round_kills = 0;
    self.zstats.career_best_round_headshots = 0;
    self.zstats.career_best_round_melee_kills = 0;
    self.zstats.career_best_round_points = 0;
    self.zstats.career_best_round_revives = 0;
    self.zstats.career_best_kpr_tenths = 0;
    self.zstats.career_best_ppr_tenths = 0;
    self.zstats.career_fastest_round = 0;
    self.zstats.career_best_match_earned = 0;
    self.zstats.career_best_match_kills = 0;
    self.zstats.career_highest_round = 0;
    self.zstats.career_pb_new = [];
    self.zstats.career_pb_previous = [];
    self.zstats.match_pb_new = [];
    self.zstats.match_pb_previous = [];
    self.zstats.last_round_pb = [];
    self.zstats.pb_loaded = 1;
    return 1;
}

zs_pb_request_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    while ( !zs_gameplay_ready() )
        wait 0.1;
    self.zstats.pb_request_epoch = ( gettime() + self.zstats.player_id * 97 ) % 65534 + 1;
    self setclientdvar( "zs_pb_request", "" + self.zstats.pb_request_epoch );
}

zs_career_pb_update( kind, value )
{
    if ( !self zs_pb_scope_career() || !self.zstats.pb_loaded )
        return 0;
    field = "";
    maximum = 1048575;
    stored_value = value;
    if ( kind == 1 ) { field = "career_best_round_kills"; maximum = 32767; }
    else if ( kind == 2 ) { field = "career_best_round_headshots"; maximum = 32767; }
    else if ( kind == 3 ) { field = "career_best_round_melee_kills"; maximum = 32767; }
    else if ( kind == 4 ) field = "career_best_round_points";
    else if ( kind == 5 ) { field = "career_best_round_revives"; maximum = 32767; }
    else if ( kind == 6 ) field = "career_best_kpr_tenths";
    else if ( kind == 7 ) field = "career_best_ppr_tenths";
    else if ( kind == 8 )
    {
        field = "career_fastest_round";
        stored_value = int( value / 100 );
    }
    else if ( kind == 9 ) { field = "career_best_match_earned"; maximum = 2097151; }
    else if ( kind == 10 ) { field = "career_best_match_kills"; maximum = 32767; }
    else if ( kind == 11 ) { field = "career_highest_round"; maximum = 1023; }
    if ( field == "" )
        return 0;
    stored_value = zs_pb_clamp( stored_value, maximum );
    // Player telemetry lives in a struct; dynamic array indexing is not a
    // portable way to read it during a round-end PB update.
    current = self zs_round_pb_threshold( kind, 0 );
    improved = kind == 8 && stored_value > 0 && ( current <= 0 || stored_value * 100 < current );
    if ( kind != 8 ) improved = stored_value > current;
    if ( !improved )
        return 0;
    self.zstats.career_pb_previous[kind] = current;
    if ( kind == 1 ) self.zstats.career_best_round_kills = stored_value;
    else if ( kind == 2 ) self.zstats.career_best_round_headshots = stored_value;
    else if ( kind == 3 ) self.zstats.career_best_round_melee_kills = stored_value;
    else if ( kind == 4 ) self.zstats.career_best_round_points = stored_value;
    else if ( kind == 5 ) self.zstats.career_best_round_revives = stored_value;
    else if ( kind == 6 ) self.zstats.career_best_kpr_tenths = stored_value;
    else if ( kind == 7 ) self.zstats.career_best_ppr_tenths = stored_value;
    else if ( kind == 8 ) self.zstats.career_fastest_round = stored_value * 100;
    else if ( kind == 9 ) self.zstats.career_best_match_earned = stored_value;
    else if ( kind == 10 ) self.zstats.career_best_match_kills = stored_value;
    else self.zstats.career_highest_round = stored_value;
    self.zstats.career_pb_new[kind] = 1;
    self zs_pb_publish_update();
    return 1;
}

zs_round_pb_commit( kind, value, match_best )
{
    if ( self zs_pb_scope_career() )
        return self zs_career_pb_update( kind, value );
    improved = value > match_best;
    if ( improved )
    {
        self.zstats.match_pb_new[kind] = 1;
        self.zstats.match_pb_previous[kind] = match_best;
    }
    return improved;
}

zs_round_pb_threshold( kind, match_best )
{
    if ( !self zs_pb_scope_career() ) return match_best;
    if ( !self.zstats.pb_loaded ) return -1;
    if ( kind == 1 ) return self.zstats.career_best_round_kills;
    if ( kind == 2 ) return self.zstats.career_best_round_headshots;
    if ( kind == 3 ) return self.zstats.career_best_round_melee_kills;
    if ( kind == 4 ) return self.zstats.career_best_round_points;
    if ( kind == 5 ) return self.zstats.career_best_round_revives;
    if ( kind == 6 ) return self.zstats.career_best_kpr_tenths;
    if ( kind == 7 ) return self.zstats.career_best_ppr_tenths;
    if ( kind == 8 ) return self.zstats.career_fastest_round;
    if ( kind == 9 ) return self.zstats.career_best_match_earned;
    if ( kind == 10 ) return self.zstats.career_best_match_kills;
    if ( kind == 11 ) return self.zstats.career_highest_round;
    return match_best;
}

zs_pb_kind_label( kind )
{
    if ( kind == 1 ) return "KILLS";
    if ( kind == 2 ) return "HEADSHOTS";
    if ( kind == 3 ) return "MELEE";
    if ( kind == 4 ) return "POINTS";
    if ( kind == 5 ) return "REVIVES";
    if ( kind == 6 ) return "KPR";
    if ( kind == 7 ) return "PPR";
    if ( kind == 8 ) return "FASTEST";
    if ( kind == 9 ) return "MATCH EARNED";
    if ( kind == 10 ) return "MATCH KILLS";
    if ( kind == 11 ) return "HIGHEST ROUND";
    return "PB";
}

zs_pb_live_value_text( kind )
{
    if ( kind == 1 ) value = self.zstats.best_round_kills;
    else if ( kind == 2 ) value = self.zstats.best_round_headshots;
    else if ( kind == 3 ) value = self.zstats.best_round_melee_kills;
    else if ( kind == 4 ) value = self.zstats.best_round_points;
    else if ( kind == 5 ) value = self.zstats.best_round_revives;
    else if ( kind == 6 ) return zs_tenths_text( self.zstats.best_kpr_tenths );
    else if ( kind == 7 ) return zs_tenths_text( self.zstats.best_ppr_tenths );
    else if ( kind == 8 ) return zs_format_time( self.zstats.fastest_round );
    else return "";
    if ( self zs_pb_scope_career() )
    {
        if ( kind == 1 ) value = self.zstats.career_best_round_kills;
        else if ( kind == 2 ) value = self.zstats.career_best_round_headshots;
        else if ( kind == 3 ) value = self.zstats.career_best_round_melee_kills;
        else if ( kind == 4 ) value = self.zstats.career_best_round_points;
        else if ( kind == 5 ) value = self.zstats.career_best_round_revives;
    }
    return "" + value;
}

zs_announce_round_pbs()
{
    if ( !self.zstats.pb_announce )
        return;
    message = "^3[ZStats]^7 NEW PB";
    shown = 0;
    total = 0;
    for ( kind = 1; kind <= 8; kind++ )
    {
        if ( !isdefined( self.zstats.last_round_pb[kind] ) || !self.zstats.last_round_pb[kind] )
            continue;
        total++;
        if ( shown >= 3 )
            continue;
        if ( shown == 0 ) message = message + " - ";
        else message = message + " / ";
        message = message + zs_pb_kind_label( kind ) + " " + self zs_pb_live_value_text( kind );
        shown++;
    }
    if ( total <= 0 )
        return;
    if ( total > shown )
        message = message + " / +" + ( total - shown ) + " MORE";
    self iprintln( message );
}

zs_start_player()
{
    if ( isdefined( self.zstats_tracking ) )
        return;

    stable_key = zs_player_stable_key( self );
    resumed = zs_claim_departed_snapshot( stable_key );
    self.zstats_tracking = 1;
    self.zstats = spawnstruct();
    self.zstats.stable_key = stable_key;
    if ( isdefined( resumed ) )
        self.zstats.player_id = resumed.player_id;
    else
    {
        self.zstats.player_id = level.zstats.next_player_id;
        level.zstats.next_player_id++;
    }
    starting_score = self zs_stat( "score" );
    self.zstats.points_earned = starting_score;
    self.zstats.points_spent = 0;
    self.zstats.round_points_earned = 0;
    self.zstats.round_points_spent = 0;
    self.zstats.perks_acquired = 0;
    self.zstats.start_kills = self zs_stat( "kills" );
    self.zstats.start_headshots = self zs_stat( "headshots" );
    self.zstats.start_melee_kills = self zs_stat( "melee_kills" );
    self.zstats.start_revives = self zs_stat( "revives" );
    self.zstats.start_downs = self zs_stat( "downs" );
    self.zstats.start_doors = self zs_stat( "doors_purchased" );
    self.zstats.start_boards = self zs_stat( "boards" );
    self.zstats.start_perks = self zs_stat( "perks_drank" );
    self.zstats.rounds_played = 0;
    self.zstats.completed_rounds = 0;
    self.zstats.join_round = zs_current_round_number();
    self.zstats.last_round_number = 0;
    self.zstats.round_active = 0;
    self.zstats.round_full = 0;
    self.zstats.last_round_valid = 0;
    self.zstats.last_round_kills = 0;
    self.zstats.last_round_headshots = 0;
    self.zstats.last_round_melee_kills = 0;
    self.zstats.last_round_revives = 0;
    self.zstats.last_round_downs = 0;
    self.zstats.last_round_points = 0;
    self.zstats.last_round_points_spent = 0;
    self.zstats.best_round_kills = 0;
    self.zstats.best_round_points = 0;
    self.zstats.best_round_headshots = 0;
    self.zstats.best_round_melee_kills = 0;
    self.zstats.best_round_revives = 0;
    self.zstats.fastest_round = 0;
    self.zstats.slowest_round = 0;
    self.zstats.best_kpr_tenths = -1;
    self.zstats.best_ppr_tenths = -1;
    self.zstats.pb_scope = "career";
    self.zstats.pb_announce = 1;
    self.zstats.pb_loaded = 0;
    self.zstats.pb_request_epoch = 0;
    self.zstats.pb_update_epoch = 0;
    self.zstats.career_best_round_kills = 0;
    self.zstats.career_best_round_headshots = 0;
    self.zstats.career_best_round_melee_kills = 0;
    self.zstats.career_best_round_points = 0;
    self.zstats.career_best_round_revives = 0;
    self.zstats.career_best_kpr_tenths = 0;
    self.zstats.career_best_ppr_tenths = 0;
    self.zstats.career_fastest_round = 0;
    self.zstats.career_best_match_earned = 0;
    self.zstats.career_best_match_kills = 0;
    self.zstats.career_highest_round = 0;
    self.zstats.career_pb_new = [];
    self.zstats.career_pb_previous = [];
    self.zstats.match_pb_new = [];
    self.zstats.match_pb_previous = [];
    self.zstats.last_round_pb = [];
    self.zstats.last_score = starting_score;
    self.zstats.ending_score = undefined;
    self.zstats.score_supported = zs_numeric( self.score_total );
    self.zstats.chugabud_transition = 0;
    self.zstats.chugabud_no_corpse = 0;
    self.zstats.chugabud_serial = 0;
    self.zstats.chugabud_pending_spent = 0;
    self.zstats.chugabud_pending_rounds = [];
    self.zstats.last_completed_round_number = 0;
    self.zstats.last_score_total = 0;
    if ( self.zstats.score_supported )
    {
        self.zstats.last_score_total = int( self.score_total );
        level.zstats.capabilities.score_total = 1;
    }
    self.zstats.opening_points_pending = starting_score;
    self.zstats.custom_match = [];
    self.zstats.custom_round = [];
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" )
            self.zstats.custom_round[metric.id] = metric.default_value;
        else
            self.zstats.custom_match[metric.id] = metric.default_value;
    }
    self zs_reset_round_baselines();

    if ( isdefined( resumed ) )
        self zs_resume_player_snapshot( resumed );

    if ( level.zstats.in_round && !level.zstats.pending_round_completion )
        self zs_begin_round();

    self thread zs_score_watch();
    self thread zs_chugabud_watch();
    self thread zs_perk_watch();
    self thread zs_menu_response_watch();
    self thread zs_pb_request_watch();
    self thread zs_zpause_hud_watch();
    self thread zs_hud_watch();
    self thread zs_disconnect_watch();
    self notify( "zstats_player_ready" );
}

zs_player_stable_key( player )
{
    xuid = player getxuid( 1 );
    xuid_text = "" + xuid;
    guid_text = "" + player getguid();
    // Local guests can report the signed-in profile's identity. Keep the
    // local entity slot in their guarded fallback so two simultaneous
    // split-screen participants can never collapse into one competitor.
    if ( player issplitscreen() )
        return "split:" + xuid_text + ":" + guid_text + ":" + player getentitynumber();
    if ( xuid_text != "" && xuid_text != "0" && xuid_text != "0x0" )
        return "xuid:" + xuid_text;
    if ( guid_text != "" && guid_text != "0" )
        return "guid:" + guid_text;
    return "session:" + player getentitynumber() + ":" + player.name;
}

zs_claim_departed_snapshot( stable_key )
{
    claimed = undefined;
    claimed_player_id = undefined;
    kept = [];
    for ( i = 0; i < level.zstats.departed_snapshots.size; i++ )
    {
        snapshot = level.zstats.departed_snapshots[i];
        if ( isdefined( snapshot.stable_key ) && snapshot.stable_key == stable_key )
        {
            if ( !isdefined( claimed_player_id ) && isdefined( snapshot.player_id ) )
                claimed_player_id = snapshot.player_id;
            claimed = snapshot;
        }
        else
            kept[kept.size] = snapshot;
    }
    if ( isdefined( claimed ) && isdefined( claimed_player_id ) )
        claimed.player_id = claimed_player_id;
    level.zstats.departed_snapshots = kept;
    return claimed;
}

zs_upsert_snapshot( snapshots, incoming )
{
    if ( !isdefined( incoming ) )
        return snapshots;

    result = [];
    inserted = 0;
    preserved_player_id = undefined;
    for ( i = 0; i < snapshots.size; i++ )
    {
        existing = snapshots[i];
        same_player = isdefined( incoming.stable_key ) && isdefined( existing.stable_key ) &&
            incoming.stable_key == existing.stable_key;
        if ( same_player )
        {
            if ( !isdefined( preserved_player_id ) && isdefined( existing.player_id ) )
                preserved_player_id = existing.player_id;
            if ( !inserted )
            {
                result[result.size] = incoming;
                inserted = 1;
            }
        }
        else
            result[result.size] = existing;
    }
    if ( isdefined( preserved_player_id ) )
        incoming.player_id = preserved_player_id;
    if ( !inserted )
        result[result.size] = incoming;
    return result;
}

zs_resume_player_snapshot( snapshot )
{
    self.zstats.start_kills = self zs_stat( "kills" ) - snapshot.kills;
    self.zstats.start_headshots = self zs_stat( "headshots" ) - snapshot.headshots;
    self.zstats.start_melee_kills = self zs_stat( "melee_kills" ) - snapshot.melee_kills;
    self.zstats.start_revives = self zs_stat( "revives" ) - snapshot.revives;
    self.zstats.start_downs = self zs_stat( "downs" ) - snapshot.downs;
    self.zstats.start_doors = self zs_stat( "doors_purchased" ) - snapshot.doors;
    self.zstats.start_boards = self zs_stat( "boards" ) - snapshot.boards;
    self.zstats.start_perks = self zs_stat( "perks_drank" ) - snapshot.perks;
    self.zstats.points_earned = snapshot.points_earned;
    self.zstats.points_spent = snapshot.points_spent;
    self.zstats.perks_acquired = snapshot.perks;
    self.zstats.rounds_played = snapshot.rounds_played;
    if ( isdefined( snapshot.completed_rounds ) ) self.zstats.completed_rounds = snapshot.completed_rounds;
    self.zstats.join_round = snapshot.join_round;
    self.zstats.last_round_number = snapshot.last_round_number;
    self.zstats.round_active = snapshot.round_active && snapshot.current_round == zs_current_round_number();
    self.zstats.round_full = 0;
    self.zstats.last_round_valid = snapshot.last_round_valid;
    self.zstats.last_round_kills = snapshot.last_round_kills;
    self.zstats.last_round_headshots = snapshot.last_round_headshots;
    if ( isdefined( snapshot.last_round_melee_kills ) )
        self.zstats.last_round_melee_kills = snapshot.last_round_melee_kills;
    self.zstats.last_round_revives = snapshot.last_round_revives;
    self.zstats.last_round_downs = snapshot.last_round_downs;
    self.zstats.last_round_points = snapshot.last_round_points;
    self.zstats.last_round_points_spent = snapshot.last_round_points_spent;
    self.zstats.best_round_kills = snapshot.best_round_kills;
    self.zstats.best_round_points = snapshot.best_round_points;
    self.zstats.best_round_headshots = snapshot.best_round_headshots;
    if ( isdefined( snapshot.best_round_melee_kills ) )
        self.zstats.best_round_melee_kills = snapshot.best_round_melee_kills;
    self.zstats.best_round_revives = snapshot.best_round_revives;
    self.zstats.fastest_round = snapshot.fastest_round;
    self.zstats.slowest_round = snapshot.slowest_round;
    self.zstats.best_kpr_tenths = snapshot.best_kpr_tenths;
    self.zstats.best_ppr_tenths = snapshot.best_ppr_tenths;
    if ( isdefined( snapshot.pb_scope ) ) self.zstats.pb_scope = snapshot.pb_scope;
    if ( isdefined( snapshot.pb_announce ) ) self.zstats.pb_announce = snapshot.pb_announce;
    if ( isdefined( snapshot.pb_loaded ) ) self.zstats.pb_loaded = snapshot.pb_loaded;
    if ( isdefined( snapshot.career_best_round_kills ) ) self.zstats.career_best_round_kills = snapshot.career_best_round_kills;
    if ( isdefined( snapshot.career_best_round_headshots ) ) self.zstats.career_best_round_headshots = snapshot.career_best_round_headshots;
    if ( isdefined( snapshot.career_best_round_melee_kills ) ) self.zstats.career_best_round_melee_kills = snapshot.career_best_round_melee_kills;
    if ( isdefined( snapshot.career_best_round_points ) ) self.zstats.career_best_round_points = snapshot.career_best_round_points;
    if ( isdefined( snapshot.career_best_round_revives ) ) self.zstats.career_best_round_revives = snapshot.career_best_round_revives;
    if ( isdefined( snapshot.career_best_kpr_tenths ) ) self.zstats.career_best_kpr_tenths = snapshot.career_best_kpr_tenths;
    if ( isdefined( snapshot.career_best_ppr_tenths ) ) self.zstats.career_best_ppr_tenths = snapshot.career_best_ppr_tenths;
    if ( isdefined( snapshot.career_fastest_round ) ) self.zstats.career_fastest_round = snapshot.career_fastest_round;
    if ( isdefined( snapshot.career_best_match_earned ) ) self.zstats.career_best_match_earned = snapshot.career_best_match_earned;
    if ( isdefined( snapshot.career_best_match_kills ) ) self.zstats.career_best_match_kills = snapshot.career_best_match_kills;
    if ( isdefined( snapshot.career_highest_round ) ) self.zstats.career_highest_round = snapshot.career_highest_round;
    if ( isdefined( snapshot.career_pb_new ) ) self.zstats.career_pb_new = snapshot.career_pb_new;
    if ( isdefined( snapshot.career_pb_previous ) ) self.zstats.career_pb_previous = snapshot.career_pb_previous;
    if ( isdefined( snapshot.match_pb_new ) ) self.zstats.match_pb_new = snapshot.match_pb_new;
    if ( isdefined( snapshot.match_pb_previous ) ) self.zstats.match_pb_previous = snapshot.match_pb_previous;
    self.zstats.opening_points_pending = 0;
    if ( isdefined( snapshot.opening_points_pending ) )
        self.zstats.opening_points_pending = snapshot.opening_points_pending;
    if ( self.zstats.round_active )
    {
        self.zstats.round_kills_start = self zs_stat( "kills" ) - snapshot.round_kills;
        self.zstats.round_headshots_start = self zs_stat( "headshots" ) - snapshot.round_headshots;
        if ( isdefined( snapshot.round_melee_kills ) )
            self.zstats.round_melee_kills_start = self zs_stat( "melee_kills" ) - snapshot.round_melee_kills;
        self.zstats.round_revives_start = self zs_stat( "revives" ) - snapshot.round_revives;
        self.zstats.round_downs_start = self zs_stat( "downs" ) - snapshot.round_downs;
        self.zstats.round_points_earned = snapshot.round_points_earned;
        self.zstats.round_points_spent = snapshot.round_points_spent;
    }
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" && isdefined( snapshot.custom_round[metric.id] ) )
            self.zstats.custom_round[metric.id] = snapshot.custom_round[metric.id];
        else if ( metric.scope == "match" && isdefined( snapshot.custom_match[metric.id] ) )
            self.zstats.custom_match[metric.id] = snapshot.custom_match[metric.id];
    }
}

zs_stat( name )
{
    // self.score is the authoritative spendable balance. Several stock
    // penalties/map paths update it without immediately mirroring pers. Mob
    // temporarily zeros that field in Afterlife, so retain its saved corporeal
    // balance until the stock loadout is restored. Die Rise's Who's Who uses
    // the same saved-loadout pattern while its clone balance is temporary.
    if ( name == "score" && isdefined( self.loadout ) && zs_numeric( self.loadout.score ) )
    {
        if ( isdefined( level.zombiemode_using_afterlife ) && level.zombiemode_using_afterlife )
            return int( self.loadout.score );
        if ( isdefined( level.zombiemode_using_chugabud_perk ) && level.zombiemode_using_chugabud_perk &&
            self zs_score_transition_active() )
            return int( self.loadout.score );
    }
    if ( name == "score" && zs_numeric( self.score ) )
        return int( self.score );
    if ( isdefined( self.pers ) && zs_numeric( self.pers[name] ) )
        return int( self.pers[name] );
    return 0;
}

zs_score_available( player )
{
    return isdefined( player.zstats ) && isdefined( player.zstats.score_supported ) && player.zstats.score_supported;
}

zs_spending_available()
{
    return isdefined( level.zstats.capabilities.spending_events ) && level.zstats.capabilities.spending_events;
}

zs_numeric( value )
{
    return isdefined( value ) && ( isint( value ) || isfloat( value ) );
}

zs_nonnegative( value )
{
    if ( value < 0 )
        return 0;
    return value;
}

zs_current_round_number()
{
    round_number = 0;
    if ( zs_numeric( level.round_number ) )
        round_number = int( level.round_number );
    if ( round_number < 1 )
        round_number = level.zstats.current_round;
    if ( round_number < 1 )
        round_number = 1;
    return round_number;
}

zs_observed_rounds( player )
{
    if ( !isdefined( player.zstats ) )
        return 1;

    rounds = player.zstats.rounds_played;
    if ( rounds < 1 )
        rounds = 1;
    return rounds;
}

zs_match_value( player, metric )
{
    if ( !isdefined( player.zstats ) )
        return 0;
    if ( metric == "kills" )
        return zs_nonnegative( player zs_stat( "kills" ) - player.zstats.start_kills );
    if ( metric == "headshots" )
        return zs_nonnegative( player zs_stat( "headshots" ) - player.zstats.start_headshots );
    if ( metric == "melee_kills" )
        return zs_nonnegative( player zs_stat( "melee_kills" ) - player.zstats.start_melee_kills );
    if ( metric == "revives" )
        return zs_nonnegative( player zs_stat( "revives" ) - player.zstats.start_revives );
    if ( metric == "downs" )
        return zs_nonnegative( player zs_stat( "downs" ) - player.zstats.start_downs );
    if ( metric == "doors" )
        return zs_nonnegative( player zs_stat( "doors_purchased" ) - player.zstats.start_doors );
    if ( metric == "boards" )
        return zs_nonnegative( player zs_stat( "boards" ) - player.zstats.start_boards );
    if ( metric == "barriers" )
        return zs_nonnegative( player zs_stat( "boards" ) - player.zstats.start_boards );
    if ( metric == "score" )
    {
        if ( !zs_score_available( player ) )
            return 0;
        return player.zstats.points_earned;
    }
    if ( metric == "points_earned" )
    {
        if ( !zs_score_available( player ) )
            return 0;
        return player.zstats.points_earned;
    }
    if ( metric == "points_spent" )
    {
        if ( !zs_score_available( player ) )
            return 0;
        return player.zstats.points_spent;
    }
    if ( metric == "perks" || metric == "perks_acquired" )
    {
        perks = player.zstats.perks_acquired;
        stock_perks = zs_nonnegative( player zs_stat( "perks_drank" ) - player.zstats.start_perks );
        if ( stock_perks > perks )
            perks = stock_perks;
        return perks;
    }
    if ( metric == "match_elapsed_ms" )
        return zs_match_elapsed();
    if ( metric == "round_elapsed_ms" )
        return zs_round_elapsed();
    if ( metric == "current_round" )
        return zs_current_round_number();
    if ( isdefined( player.zstats.custom_match[metric] ) )
        return player.zstats.custom_match[metric];
    return 0;
}

zs_api_get_match_value( player, metric )
{
    if ( !level.zstats.enabled || !isdefined( player ) || !isplayer( player ) || !isdefined( metric ) || !isstring( metric ) )
        return 0;
    return zs_match_value( player, metric );
}

zs_reset_round_baselines()
{
    if ( !isdefined( self.zstats ) )
        return;

    self.zstats.round_kills_start = self zs_stat( "kills" );
    self.zstats.round_headshots_start = self zs_stat( "headshots" );
    self.zstats.round_melee_kills_start = self zs_stat( "melee_kills" );
    self.zstats.round_revives_start = self zs_stat( "revives" );
    self.zstats.round_downs_start = self zs_stat( "downs" );
    self.zstats.round_points_earned = 0;
    self.zstats.round_points_spent = 0;
    self.zstats.pending_round_frozen = 0;
    self.zstats.pending_round_elapsed = 0;
    self.zstats.pending_custom_round = [];
    if ( isdefined( self.zstats.custom_round ) )
    {
        for ( i = 0; i < level.zstats.metrics.size; i++ )
        {
            metric = level.zstats.metrics[i];
            if ( metric.scope == "round" )
                self.zstats.custom_round[metric.id] = metric.default_value;
        }
    }
}

zs_begin_round( round_number )
{
    if ( !isdefined( self.zstats ) )
        return;

    if ( !isdefined( round_number ) )
        round_number = zs_current_round_number();
    if ( self.zstats.round_active && self.zstats.last_round_number == round_number )
        return;

    self.zstats.rounds_played++;
    self.zstats.last_round_number = round_number;

    self.zstats.round_active = 1;
    self.zstats.round_full = 0;
    if ( level.zstats.round_start_seen && isdefined( level.zstats.round_start ) && gettime() - level.zstats.round_start <= 1000 )
        self.zstats.round_full = 1;
    self zs_reset_round_baselines();
    self.zstats.last_round_pb = [];
    if ( self.zstats.opening_points_pending > 0 )
    {
        self.zstats.round_points_earned += self.zstats.opening_points_pending;
        self.zstats.opening_points_pending = 0;
    }
}

zs_sample_score()
{
    if ( !isdefined( self.zstats ) )
        return;
    if ( isdefined( self.zstats.score_frozen ) && self.zstats.score_frozen )
        return;

    transition_active = self zs_score_transition_active();
    if ( transition_active )
        self.zstats.score_transition = 1;
    else
        self.zstats.score_transition = 0;

    current = self zs_stat( "score" );
    // Custom maps can temporarily remove or replace the cumulative counter.
    // Degrade score-derived rows while it is nonnumeric, then rebaseline both
    // counters when it returns instead of treating the transition as economy.
    if ( !zs_numeric( self.score_total ) )
    {
        self.zstats.score_supported = 0;
        self.zstats.last_score = current;
        return;
    }

    // Mob Afterlife and Die Rise Who's Who own temporary/rollback-capable
    // balances. Defer balance/spend classification until stock resolves the
    // loadout, while still consuming authoritative gross earnings.
    if ( transition_active )
    {
        // The spendable balance is rollback-capable during these states, but
        // score_total remains the authoritative gross-earnings counter. Consume
        // it continuously so a disconnect or game end inside the transition
        // cannot discard legitimate earnings.
        if ( !self.zstats.score_supported )
        {
            self.zstats.score_supported = 1;
            self.zstats.last_score_total = int( self.score_total );
            self.zstats.last_score = current;
            level.zstats.capabilities.score_total = 1;
            return;
        }
        score_total = int( self.score_total );
        earned = score_total - self.zstats.last_score_total;
        if ( earned > 0 )
        {
            self.zstats.points_earned += earned;
            if ( level.zstats.in_round && self.zstats.round_active )
                self.zstats.round_points_earned += earned;
        }
        self.zstats.last_score = current;
        self.zstats.last_score_total = score_total;
        return;
    }

    if ( !self.zstats.score_supported )
    {
        self.zstats.score_supported = 1;
        self.zstats.last_score_total = int( self.score_total );
        self.zstats.last_score = current;
        level.zstats.capabilities.score_total = 1;
        return;
    }
    score_total = int( self.score_total );
    earned = score_total - self.zstats.last_score_total;
    if ( earned < 0 )
        earned = 0;
    if ( earned > 0 )
    {
        self.zstats.points_earned += earned;
        if ( level.zstats.in_round && self.zstats.round_active )
            self.zstats.round_points_earned += earned;
    }

    // Spending is recorded by zs_spent_points_watch. Current balance changes
    // without that stock event include downs/deaths and must only rebaseline.
    self.zstats.last_score = current;
    self.zstats.last_score_total = score_total;
}

zs_score_transition_active()
{
    if ( !isdefined( self.loadout ) || !isdefined( self.loadout.score ) )
        return 0;
    if ( isdefined( level.zombiemode_using_afterlife ) && level.zombiemode_using_afterlife )
        return 1;
    if ( isdefined( level.zombiemode_using_chugabud_perk ) && level.zombiemode_using_chugabud_perk )
    {
        if ( isdefined( self.zstats ) && isdefined( self.zstats.chugabud_transition ) )
            return self.zstats.chugabud_transition &&
                ( !isdefined( self.zstats.chugabud_no_corpse ) || !self.zstats.chugabud_no_corpse );
        return 1;
    }
    return 0;
}

zs_freeze_round_end( round_end_time )
{
    if ( !isdefined( self.zstats ) || !self.zstats.round_active ||
        ( isdefined( self.zstats.pending_round_frozen ) && self.zstats.pending_round_frozen ) )
        return;

    self zs_sample_score();
    self.zstats.pending_round_kills = zs_nonnegative( self zs_stat( "kills" ) - self.zstats.round_kills_start );
    self.zstats.pending_round_headshots = zs_nonnegative( self zs_stat( "headshots" ) - self.zstats.round_headshots_start );
    self.zstats.pending_round_melee_kills = zs_nonnegative( self zs_stat( "melee_kills" ) - self.zstats.round_melee_kills_start );
    self.zstats.pending_round_revives = zs_nonnegative( self zs_stat( "revives" ) - self.zstats.round_revives_start );
    self.zstats.pending_round_downs = zs_nonnegative( self zs_stat( "downs" ) - self.zstats.round_downs_start );
    self.zstats.pending_round_points_earned = self.zstats.round_points_earned;
    self.zstats.pending_round_points_spent = self.zstats.round_points_spent;
    self.zstats.pending_round_elapsed = 0;
    if ( self.zstats.round_full && level.zstats.capabilities.round_events && zs_numeric( level.zstats.round_start ) )
    {
        elapsed_end = gettime();
        if ( zs_numeric( round_end_time ) && round_end_time >= level.zstats.round_start )
            elapsed_end = round_end_time;
        self.zstats.pending_round_elapsed = elapsed_end - level.zstats.round_start;
    }
    rounds = zs_observed_rounds( self );
    self.zstats.pending_round_kpr_tenths = zs_average_tenths( zs_match_value( self, "kills" ), rounds );
    self.zstats.pending_round_ppr_tenths = zs_average_tenths( self.zstats.points_earned, rounds );
    self.zstats.pending_custom_round = [];
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" )
            self.zstats.pending_custom_round[metric.id] = self.zstats.custom_round[metric.id];
    }
    self.zstats.pending_round_frozen = 1;
}

zs_finalize_round( round_end_time )
{
    if ( !isdefined( self.zstats ) || !self.zstats.round_active )
        return;

    self zs_freeze_round_end( round_end_time );
    if ( !isdefined( self.zstats.pending_round_frozen ) || !self.zstats.pending_round_frozen )
        return;

    self.zstats.last_round_kills = self.zstats.pending_round_kills;
    self.zstats.last_round_headshots = self.zstats.pending_round_headshots;
    self.zstats.last_round_melee_kills = self.zstats.pending_round_melee_kills;
    self.zstats.last_round_revives = self.zstats.pending_round_revives;
    self.zstats.last_round_downs = self.zstats.pending_round_downs;
    self.zstats.last_round_points = self.zstats.pending_round_points_earned;
    self.zstats.last_round_points_spent = self.zstats.pending_round_points_spent;
    self.zstats.last_completed_round_number = self.zstats.last_round_number;
    self.zstats.round_points_earned = self.zstats.pending_round_points_earned;
    self.zstats.round_points_spent = self.zstats.pending_round_points_spent;
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" )
            self.zstats.custom_round[metric.id] = self.zstats.pending_custom_round[metric.id];
    }
    self.zstats.last_round_valid = 1;
    self.zstats.completed_rounds++;

    self.zstats.last_round_pb[1] = self zs_round_pb_commit( 1, self.zstats.last_round_kills, self.zstats.best_round_kills );
    self.zstats.last_round_pb[2] = self zs_round_pb_commit( 2, self.zstats.last_round_headshots, self.zstats.best_round_headshots );
    self.zstats.last_round_pb[3] = self zs_round_pb_commit( 3, self.zstats.last_round_melee_kills, self.zstats.best_round_melee_kills );
    self.zstats.last_round_pb[4] = self zs_round_pb_commit( 4, self.zstats.last_round_points, self.zstats.best_round_points );
    self.zstats.last_round_pb[5] = self zs_round_pb_commit( 5, self.zstats.last_round_revives, self.zstats.best_round_revives );

    if ( self.zstats.last_round_kills > self.zstats.best_round_kills )
        self.zstats.best_round_kills = self.zstats.last_round_kills;
    if ( self.zstats.last_round_points > self.zstats.best_round_points )
        self.zstats.best_round_points = self.zstats.last_round_points;
    if ( self.zstats.last_round_headshots > self.zstats.best_round_headshots )
        self.zstats.best_round_headshots = self.zstats.last_round_headshots;
    if ( self.zstats.last_round_melee_kills > self.zstats.best_round_melee_kills )
        self.zstats.best_round_melee_kills = self.zstats.last_round_melee_kills;
    if ( self.zstats.last_round_revives > self.zstats.best_round_revives )
        self.zstats.best_round_revives = self.zstats.last_round_revives;

    elapsed = self.zstats.pending_round_elapsed;
    if ( elapsed > 0 )
    {
        if ( self zs_pb_scope_career() )
            self.zstats.last_round_pb[8] = self zs_career_pb_update( 8, elapsed );
        else
        {
            self.zstats.last_round_pb[8] = self.zstats.fastest_round <= 0 || elapsed < self.zstats.fastest_round;
            if ( self.zstats.last_round_pb[8] )
            {
                self.zstats.match_pb_new[8] = 1;
                self.zstats.match_pb_previous[8] = self.zstats.fastest_round;
            }
        }
        if ( self.zstats.fastest_round <= 0 || elapsed < self.zstats.fastest_round )
            self.zstats.fastest_round = elapsed;
        if ( elapsed > self.zstats.slowest_round )
            self.zstats.slowest_round = elapsed;
    }

    kpr = self.zstats.pending_round_kpr_tenths;
    ppr = self.zstats.pending_round_ppr_tenths;
    self.zstats.last_round_pb[6] = self zs_round_pb_commit( 6, kpr, self.zstats.best_kpr_tenths );
    self.zstats.last_round_pb[7] = self zs_round_pb_commit( 7, ppr, self.zstats.best_ppr_tenths );
    if ( kpr > self.zstats.best_kpr_tenths )
        self.zstats.best_kpr_tenths = kpr;
    if ( ppr > self.zstats.best_ppr_tenths )
        self.zstats.best_ppr_tenths = ppr;
    self.zstats.round_active = 0;
    self.zstats.pending_round_frozen = 0;
    self zs_announce_round_pbs();
}

zs_score_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    while ( 1 )
    {
        self zs_sample_score();
        wait 0.1;
    }
}

zs_spent_points_watch()
{
    level endon( "end_game" );

    while ( 1 )
    {
        level waittill( "spent_points", player, points );
        if ( !isdefined( player ) || !isplayer( player ) || !isdefined( player.zstats ) ||
            !zs_numeric( points ) || points <= 0 )
            continue;

        spent = int( points );
        level.zstats.capabilities.spending_events = 1;
        if ( isdefined( player.zstats.chugabud_transition ) && player.zstats.chugabud_transition )
            player zs_defer_chugabud_spending( spent );
        else
            player zs_commit_spending( spent, zs_current_round_number() );
    }
}

zs_commit_spending( spent, round_number )
{
    if ( !isdefined( self.zstats ) || spent <= 0 )
        return;

    self.zstats.points_spent += spent;
    if ( self.zstats.round_active && self.zstats.last_round_number == round_number )
    {
        if ( isdefined( self.zstats.pending_round_frozen ) && self.zstats.pending_round_frozen )
            self.zstats.pending_round_points_spent += spent;
        else
            self.zstats.round_points_spent += spent;
        return;
    }
    if ( self.zstats.last_round_valid && isdefined( self.zstats.last_completed_round_number ) &&
        self.zstats.last_completed_round_number == round_number )
    {
        self.zstats.last_round_points_spent += spent;
        if ( !self.zstats.round_active )
            self.zstats.round_points_spent = self.zstats.last_round_points_spent;
    }
}

zs_defer_chugabud_spending( spent )
{
    self.zstats.chugabud_pending_spent += spent;
    if ( !level.zstats.in_round || !self.zstats.round_active )
        return;

    round_number = self.zstats.last_round_number;
    for ( i = 0; i < self.zstats.chugabud_pending_rounds.size; i++ )
    {
        entry = self.zstats.chugabud_pending_rounds[i];
        if ( entry.round_number == round_number )
        {
            entry.spent += spent;
            return;
        }
    }
    entry = spawnstruct();
    entry.round_number = round_number;
    entry.spent = spent;
    self.zstats.chugabud_pending_rounds[self.zstats.chugabud_pending_rounds.size] = entry;
}

zs_settle_chugabud_spending( commit )
{
    if ( !isdefined( self.zstats ) || !isdefined( self.zstats.chugabud_transition ) ||
        !self.zstats.chugabud_transition )
        return;

    if ( commit )
    {
        self.zstats.points_spent += self.zstats.chugabud_pending_spent;
        for ( i = 0; i < self.zstats.chugabud_pending_rounds.size; i++ )
        {
            entry = self.zstats.chugabud_pending_rounds[i];
            if ( self.zstats.round_active && self.zstats.last_round_number == entry.round_number )
            {
                if ( isdefined( self.zstats.pending_round_frozen ) && self.zstats.pending_round_frozen )
                    self.zstats.pending_round_points_spent += entry.spent;
                else
                    self.zstats.round_points_spent += entry.spent;
            }
            else if ( self.zstats.last_round_valid && self.zstats.last_completed_round_number == entry.round_number )
            {
                self.zstats.last_round_points_spent += entry.spent;
                if ( !self.zstats.round_active )
                    self.zstats.round_points_spent = self.zstats.last_round_points_spent;
            }
        }
    }
    self.zstats.chugabud_pending_spent = 0;
    self.zstats.chugabud_pending_rounds = [];
    self.zstats.chugabud_transition = 0;
}

zs_chugabud_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    while ( 1 )
    {
        self waittill( "fake_death" );
        if ( !isdefined( level.zombiemode_using_chugabud_perk ) || !level.zombiemode_using_chugabud_perk )
            continue;

        self.zstats.chugabud_serial++;
        serial = self.zstats.chugabud_serial;
        self.zstats.chugabud_transition = 1;
        self.zstats.chugabud_no_corpse = 0;
        self.zstats.chugabud_pending_spent = 0;
        self.zstats.chugabud_pending_rounds = [];
        self thread zs_chugabud_fake_revive_watch( serial );
        self thread zs_chugabud_bleedout_watch( serial );
    }
}

zs_chugabud_fake_revive_watch( serial )
{
    self endon( "disconnect" );
    level endon( "end_game" );
    self waittill( "fake_revive" );
    if ( self.zstats.chugabud_serial != serial || !self.zstats.chugabud_transition )
        return;

    // Stock's no-body branch never clears loadout. The clone is the player's
    // final state, so stop treating that saved balance as a temporary owner.
    if ( !isdefined( self.e_chugabud_corpse ) )
    {
        self.zstats.chugabud_no_corpse = 1;
        self zs_settle_chugabud_spending( 1 );
        return;
    }

    while ( self.zstats.chugabud_serial == serial && self.zstats.chugabud_transition && isdefined( self.loadout ) )
        wait 0.05;
    wait 0.05;
    if ( self.zstats.chugabud_serial == serial && self.zstats.chugabud_transition )
        self zs_settle_chugabud_spending( 0 );
}

zs_chugabud_bleedout_watch( serial )
{
    self endon( "disconnect" );
    level endon( "end_game" );
    self waittill( "chugabud_bleedout" );
    if ( self.zstats.chugabud_serial == serial && self.zstats.chugabud_transition )
        self zs_settle_chugabud_spending( 1 );
}

zs_perk_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    while ( 1 )
    {
        self waittill( "perk_bought" );
        self.zstats.perks_acquired++;
    }
}

zs_round_watch()
{
    level endon( "end_game" );

    while ( 1 )
    {
        level waittill( "start_of_round" );
        // At round 255 stock starts a new wave without changing the numeric
        // round. Drain the completed lifecycle before identity checks so the
        // next capped wave still receives fresh baselines.
        zs_finalize_pending_round();
        first_start_event = !level.zstats.round_start_seen;
        level.zstats.round_start_seen = 1;
        if ( level.zstats.round_end_seen )
            level.zstats.capabilities.round_events = 1;
        level.zstats.capabilities.round_timing = 1;
        round_number = zs_current_round_number();
        continuing_round = level.zstats.in_round && level.zstats.current_round == round_number;
        if ( !continuing_round )
        {
            level.zstats.round_serial++;
            level.zstats.round_start = zs_stock_round_start_time();
            if ( level.zstats.round_start < 0 )
                level.zstats.round_start = gettime();
            level.zstats.current_round = round_number;
            level.zstats.in_round = 1;
        }
        else if ( first_start_event )
        {
            level.zstats.round_start = zs_stock_round_start_time();
            if ( level.zstats.round_start < 0 )
                level.zstats.round_start = gettime();
        }

        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            players[i] zs_begin_round( round_number );
            if ( first_start_event && continuing_round && isdefined( players[i].zstats ) && players[i].zstats.round_active )
                players[i].zstats.round_full = 1;
        }
    }
}

zs_round_end_watch()
{
    level endon( "end_game" );

    while ( 1 )
    {
        level waittill( "end_of_round" );
        level.zstats.round_end_seen = 1;
        if ( level.zstats.round_start_seen )
            level.zstats.capabilities.round_events = 1;

        // Buried emits a synthetic end/start pair while rewinding a Time Bomb.
        // Its dedicated checkpoint restore owns that transition.
        if ( isdefined( level.time_bomb_round_change ) && level.time_bomb_round_change )
            continue;

        completed_round = level.zstats.current_round;
        level.zstats.pending_round_number = completed_round;
        level.zstats.pending_round_end_time = gettime();
        level.zstats.pending_round_completion = 1;
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
            players[i] zs_finalize_round( level.zstats.pending_round_end_time );
        level.zstats.pending_round_mvp_candidates = zs_capture_round_mvp_candidates( players );
        level.zstats.in_round = 0;
        while ( level.zstats.pending_round_completion && zs_current_round_number() <= completed_round )
            wait 0.05;
        if ( level.zstats.pending_round_completion )
        {
            wait 0.05;
            zs_finalize_pending_round();
        }
    }
}

zs_finalize_pending_round()
{
    if ( !level.zstats.pending_round_completion )
        return;

    completed_round = level.zstats.pending_round_number;
    round_end_time = level.zstats.pending_round_end_time;
    // Claim before doing work so the poller, next-start hook, and game-over
    // fallback cannot finalize the same lifecycle twice.
    level.zstats.pending_round_completion = 0;
    level.zstats.pending_round_end_time = undefined;
    players = getplayers();
    for ( i = 0; i < players.size; i++ )
        players[i] zs_finalize_round( round_end_time );
    level notify( "zstats_round_finalized", completed_round );
    if ( zs_cfg_int( "zs_round_report", 1 ) )
        zs_announce_round_mvp();
    else
        level.zstats.pending_round_mvp_candidates = [];
    level.zstats.in_round = 0;
}

zs_time_bomb_save_watch()
{
    level endon( "end_game" );

    while ( 1 )
    {
        level waittill( "new_time_bomb_set" );
        level.zstats.time_bomb_checkpoint = spawnstruct();
        checkpoint = level.zstats.time_bomb_checkpoint;
        checkpoint.valid = 1;
        checkpoint.current_round = zs_current_round_number();
        checkpoint.round_serial = level.zstats.round_serial;
        checkpoint.in_round = level.zstats.in_round;
        checkpoint.departed_snapshots = [];
        for ( i = 0; i < level.zstats.departed_snapshots.size; i++ )
            checkpoint.departed_snapshots = zs_upsert_snapshot( checkpoint.departed_snapshots, level.zstats.departed_snapshots[i] );
        checkpoint.players = [];
        checkpoint.round_elapsed = 0;
        if ( isdefined( level.zstats.round_start ) )
            checkpoint.round_elapsed = gettime() - level.zstats.round_start;

        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            if ( isdefined( players[i].zstats ) )
                checkpoint.players[checkpoint.players.size] = players[i] zs_save_time_bomb_checkpoint();
        }
    }
}

zs_save_time_bomb_checkpoint()
{
    self zs_sample_score();
    saved = spawnstruct();
    saved.match_kills = zs_match_value( self, "kills" );
    saved.match_headshots = zs_match_value( self, "headshots" );
    saved.match_melee_kills = zs_match_value( self, "melee_kills" );
    saved.match_revives = zs_match_value( self, "revives" );
    saved.match_downs = zs_match_value( self, "downs" );
    saved.match_doors = zs_match_value( self, "doors" );
    saved.match_boards = zs_match_value( self, "boards" );
    saved.match_perks = zs_nonnegative( self zs_stat( "perks_drank" ) - self.zstats.start_perks );
    saved.round_kills = zs_round_value( self, "kills" );
    saved.round_headshots = zs_round_value( self, "headshots" );
    saved.round_melee_kills = zs_round_value( self, "melee_kills" );
    saved.round_revives = zs_round_value( self, "revives" );
    saved.round_downs = zs_round_value( self, "downs" );
    saved.points_earned = self.zstats.points_earned;
    saved.points_spent = self.zstats.points_spent;
    saved.round_points_earned = self.zstats.round_points_earned;
    saved.round_points_spent = self.zstats.round_points_spent;
    saved.perks_acquired = self.zstats.perks_acquired;
    saved.rounds_played = self.zstats.rounds_played;
    saved.completed_rounds = self.zstats.completed_rounds;
    saved.join_round = self.zstats.join_round;
    saved.last_round_number = self.zstats.last_round_number;
    saved.round_active = self.zstats.round_active;
    saved.round_full = self.zstats.round_full;
    saved.last_round_valid = self.zstats.last_round_valid;
    saved.last_round_kills = self.zstats.last_round_kills;
    saved.last_round_headshots = self.zstats.last_round_headshots;
    saved.last_round_melee_kills = self.zstats.last_round_melee_kills;
    saved.last_round_revives = self.zstats.last_round_revives;
    saved.last_round_downs = self.zstats.last_round_downs;
    saved.last_round_points = self.zstats.last_round_points;
    saved.last_round_points_spent = self.zstats.last_round_points_spent;
    saved.best_round_kills = self.zstats.best_round_kills;
    saved.best_round_points = self.zstats.best_round_points;
    saved.best_round_headshots = self.zstats.best_round_headshots;
    saved.best_round_melee_kills = self.zstats.best_round_melee_kills;
    saved.best_round_revives = self.zstats.best_round_revives;
    saved.fastest_round = self.zstats.fastest_round;
    saved.slowest_round = self.zstats.slowest_round;
    saved.best_kpr_tenths = self.zstats.best_kpr_tenths;
    saved.best_ppr_tenths = self.zstats.best_ppr_tenths;
    saved.opening_points_pending = self.zstats.opening_points_pending;
    saved.player_id = self.zstats.player_id;
    saved.stable_key = self.zstats.stable_key;
    saved.custom_match = [];
    saved.custom_round = [];
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" )
            saved.custom_round[metric.id] = self.zstats.custom_round[metric.id];
        else
            saved.custom_match[metric.id] = self.zstats.custom_match[metric.id];
    }
    saved.snapshot = self zs_player_snapshot();
    self.zstats.time_bomb_checkpoint = saved;
    return saved;
}

zs_find_time_bomb_player_checkpoint( checkpoint, stable_key )
{
    if ( !isdefined( checkpoint.players ) )
        return undefined;
    for ( i = 0; i < checkpoint.players.size; i++ )
    {
        if ( isdefined( checkpoint.players[i].stable_key ) && checkpoint.players[i].stable_key == stable_key )
            return checkpoint.players[i];
    }
    return undefined;
}

zs_find_time_bomb_departed_snapshot( checkpoint, stable_key )
{
    if ( !isdefined( checkpoint.departed_snapshots ) )
        return undefined;
    for ( i = 0; i < checkpoint.departed_snapshots.size; i++ )
    {
        snapshot = checkpoint.departed_snapshots[i];
        if ( isdefined( snapshot.stable_key ) && snapshot.stable_key == stable_key )
            return snapshot;
    }
    return undefined;
}

zs_time_bomb_player_connected( players, stable_key )
{
    if ( !isdefined( stable_key ) )
        return 0;
    for ( i = 0; i < players.size; i++ )
    {
        current_key = undefined;
        if ( isdefined( players[i].zstats ) && isdefined( players[i].zstats.stable_key ) )
            current_key = players[i].zstats.stable_key;
        else
            current_key = zs_player_stable_key( players[i] );
        if ( current_key == stable_key )
            return 1;
    }
    return 0;
}

zs_time_bomb_restore_watch()
{
    level endon( "end_game" );

    while ( 1 )
    {
        level waittill( "time_bomb_detonation_complete" );
        if ( !isdefined( level.zstats.time_bomb_checkpoint ) || !level.zstats.time_bomb_checkpoint.valid )
            continue;

        checkpoint = level.zstats.time_bomb_checkpoint;
        level.zstats.current_round = zs_current_round_number();
        level.zstats.round_serial = checkpoint.round_serial;
        level.zstats.in_round = checkpoint.in_round;
        level.zstats.round_start = gettime() - checkpoint.round_elapsed;
        players = getplayers();
        restored_departed = [];
        if ( isdefined( checkpoint.departed_snapshots ) )
        {
            for ( i = 0; i < checkpoint.departed_snapshots.size; i++ )
            {
                snapshot = checkpoint.departed_snapshots[i];
                if ( !isdefined( snapshot.stable_key ) || !zs_time_bomb_player_connected( players, snapshot.stable_key ) )
                    restored_departed = zs_upsert_snapshot( restored_departed, snapshot );
            }
        }
        level.zstats.departed_snapshots = restored_departed;
        for ( i = 0; i < players.size; i++ )
        {
            if ( !isdefined( players[i].zstats ) )
                continue;
            saved_player = zs_find_time_bomb_player_checkpoint( checkpoint, players[i].zstats.stable_key );
            if ( isdefined( saved_player ) )
                players[i] zs_restore_time_bomb_checkpoint( saved_player );
            else
            {
                saved_departed = zs_find_time_bomb_departed_snapshot( checkpoint, players[i].zstats.stable_key );
                if ( isdefined( saved_departed ) )
                    players[i] zs_restore_time_bomb_departed_snapshot( saved_departed );
                else
                    players[i] zs_reset_after_time_bomb();
            }
        }
        if ( isdefined( checkpoint.players ) )
        {
            for ( i = 0; i < checkpoint.players.size; i++ )
            {
                saved_player = checkpoint.players[i];
                if ( !zs_time_bomb_player_connected( players, saved_player.stable_key ) && isdefined( saved_player.snapshot ) )
                    level.zstats.departed_snapshots = zs_upsert_snapshot( level.zstats.departed_snapshots, saved_player.snapshot );
            }
        }
        checkpoint.valid = 0;
    }
}

zs_restore_time_bomb_departed_snapshot( snapshot )
{
    if ( !isdefined( snapshot ) )
        return;

    // Stock has no per-player Time Bomb save for someone absent when it was
    // placed, but their pre-save match history is still part of the restored
    // timeline. Reapply that history and treat their live entity as joining the
    // restored round only when the saved snapshot was not already active in it.
    if ( isdefined( snapshot.player_id ) )
        self.zstats.player_id = snapshot.player_id;
    self zs_reset_round_baselines();
    self zs_resume_player_snapshot( snapshot );
    if ( level.zstats.in_round && !level.zstats.pending_round_completion && !self.zstats.round_active )
        self zs_begin_round( level.zstats.current_round );

    self.zstats.pending_round_frozen = 0;
    self.zstats.pending_round_elapsed = 0;
    self.zstats.pending_custom_round = [];
    self.zstats.last_score = self zs_stat( "score" );
    self.zstats.score_supported = zs_numeric( self.score_total );
    self.zstats.last_score_total = 0;
    if ( self.zstats.score_supported )
    {
        self.zstats.last_score_total = int( self.score_total );
        level.zstats.capabilities.score_total = 1;
    }
    self.zstats.score_transition = 0;
    self.zstats.ending_score = undefined;
    self.zstats.time_bomb_checkpoint = undefined;
}

zs_restore_time_bomb_checkpoint( saved )
{
    if ( !isdefined( saved ) )
        saved = self.zstats.time_bomb_checkpoint;
    if ( !isdefined( saved ) )
        return;
    if ( isdefined( saved.player_id ) )
        self.zstats.player_id = saved.player_id;
    self.zstats.start_kills = self zs_stat( "kills" ) - saved.match_kills;
    self.zstats.start_headshots = self zs_stat( "headshots" ) - saved.match_headshots;
    self.zstats.start_melee_kills = self zs_stat( "melee_kills" ) - saved.match_melee_kills;
    self.zstats.start_revives = self zs_stat( "revives" ) - saved.match_revives;
    self.zstats.start_downs = self zs_stat( "downs" ) - saved.match_downs;
    self.zstats.start_doors = self zs_stat( "doors_purchased" ) - saved.match_doors;
    self.zstats.start_boards = self zs_stat( "boards" ) - saved.match_boards;
    self.zstats.start_perks = self zs_stat( "perks_drank" ) - saved.match_perks;
    self.zstats.round_kills_start = self zs_stat( "kills" ) - saved.round_kills;
    self.zstats.round_headshots_start = self zs_stat( "headshots" ) - saved.round_headshots;
    self.zstats.round_melee_kills_start = self zs_stat( "melee_kills" ) - saved.round_melee_kills;
    self.zstats.round_revives_start = self zs_stat( "revives" ) - saved.round_revives;
    self.zstats.round_downs_start = self zs_stat( "downs" ) - saved.round_downs;
    self.zstats.points_earned = saved.points_earned;
    self.zstats.points_spent = saved.points_spent;
    self.zstats.round_points_earned = saved.round_points_earned;
    self.zstats.round_points_spent = saved.round_points_spent;
    self.zstats.perks_acquired = saved.perks_acquired;
    self.zstats.rounds_played = saved.rounds_played;
    self.zstats.completed_rounds = saved.completed_rounds;
    self.zstats.join_round = saved.join_round;
    self.zstats.last_round_number = saved.last_round_number;
    self.zstats.round_active = saved.round_active;
    self.zstats.round_full = saved.round_full;
    self.zstats.pending_round_frozen = 0;
    self.zstats.pending_round_elapsed = 0;
    self.zstats.pending_custom_round = [];
    self.zstats.last_round_valid = saved.last_round_valid;
    self.zstats.last_round_kills = saved.last_round_kills;
    self.zstats.last_round_headshots = saved.last_round_headshots;
    self.zstats.last_round_melee_kills = saved.last_round_melee_kills;
    self.zstats.last_round_revives = saved.last_round_revives;
    self.zstats.last_round_downs = saved.last_round_downs;
    self.zstats.last_round_points = saved.last_round_points;
    self.zstats.last_round_points_spent = saved.last_round_points_spent;
    self.zstats.best_round_kills = saved.best_round_kills;
    self.zstats.best_round_points = saved.best_round_points;
    self.zstats.best_round_headshots = saved.best_round_headshots;
    self.zstats.best_round_melee_kills = saved.best_round_melee_kills;
    self.zstats.best_round_revives = saved.best_round_revives;
    self.zstats.fastest_round = saved.fastest_round;
    self.zstats.slowest_round = saved.slowest_round;
    self.zstats.best_kpr_tenths = saved.best_kpr_tenths;
    self.zstats.best_ppr_tenths = saved.best_ppr_tenths;
    self.zstats.opening_points_pending = saved.opening_points_pending;
    self.zstats.last_score = self zs_stat( "score" );
    self.zstats.score_supported = zs_numeric( self.score_total );
    self.zstats.last_score_total = 0;
    if ( self.zstats.score_supported )
        self.zstats.last_score_total = int( self.score_total );
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" )
            self.zstats.custom_round[metric.id] = saved.custom_round[metric.id];
        else
            self.zstats.custom_match[metric.id] = saved.custom_match[metric.id];
    }
    self.zstats.time_bomb_checkpoint = undefined;
}

zs_reset_after_time_bomb()
{
    starting_score = self zs_stat( "score" );
    self.zstats.points_earned = starting_score;
    self.zstats.points_spent = 0;
    self.zstats.round_points_earned = 0;
    self.zstats.round_points_spent = 0;
    self.zstats.perks_acquired = 0;
    self.zstats.start_kills = self zs_stat( "kills" );
    self.zstats.start_headshots = self zs_stat( "headshots" );
    self.zstats.start_melee_kills = self zs_stat( "melee_kills" );
    self.zstats.start_revives = self zs_stat( "revives" );
    self.zstats.start_downs = self zs_stat( "downs" );
    self.zstats.start_doors = self zs_stat( "doors_purchased" );
    self.zstats.start_boards = self zs_stat( "boards" );
    self.zstats.start_perks = self zs_stat( "perks_drank" );
    self.zstats.round_kills_start = self.zstats.start_kills;
    self.zstats.round_headshots_start = self.zstats.start_headshots;
    self.zstats.round_melee_kills_start = self.zstats.start_melee_kills;
    self.zstats.round_revives_start = self.zstats.start_revives;
    self.zstats.round_downs_start = self.zstats.start_downs;
    self.zstats.rounds_played = 0;
    self.zstats.completed_rounds = 0;
    self.zstats.join_round = zs_current_round_number();
    self.zstats.last_round_number = 0;
    self.zstats.round_active = level.zstats.in_round;
    self.zstats.round_full = 0;
    self.zstats.pending_round_frozen = 0;
    self.zstats.pending_round_elapsed = 0;
    self.zstats.pending_custom_round = [];
    self.zstats.last_round_valid = 0;
    self.zstats.last_round_kills = 0;
    self.zstats.last_round_headshots = 0;
    self.zstats.last_round_melee_kills = 0;
    self.zstats.last_round_revives = 0;
    self.zstats.last_round_downs = 0;
    self.zstats.last_round_points = 0;
    self.zstats.last_round_points_spent = 0;
    self.zstats.best_round_kills = 0;
    self.zstats.best_round_points = 0;
    self.zstats.best_round_headshots = 0;
    self.zstats.best_round_melee_kills = 0;
    self.zstats.best_round_revives = 0;
    self.zstats.fastest_round = 0;
    self.zstats.slowest_round = 0;
    self.zstats.best_kpr_tenths = -1;
    self.zstats.best_ppr_tenths = -1;
    self.zstats.match_pb_new = [];
    self.zstats.match_pb_previous = [];
    self.zstats.last_round_pb = [];
    self.zstats.opening_points_pending = starting_score;
    if ( level.zstats.in_round )
    {
        self.zstats.round_points_earned = starting_score;
        self.zstats.rounds_played = 1;
        self.zstats.last_round_number = self.zstats.join_round;
        self.zstats.opening_points_pending = 0;
    }
    self.zstats.last_score = starting_score;
    self.zstats.ending_score = undefined;
    self.zstats.score_supported = zs_numeric( self.score_total );
    self.zstats.last_score_total = 0;
    if ( self.zstats.score_supported )
        self.zstats.last_score_total = int( self.score_total );
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" )
            self.zstats.custom_round[metric.id] = metric.default_value;
        else
            self.zstats.custom_match[metric.id] = metric.default_value;
    }
}

zs_round_value( player, metric )
{
    if ( !isdefined( player.zstats ) )
        return 0;
    if ( player.zstats.last_round_valid && !player.zstats.round_active )
    {
        if ( metric == "kills" )
            return player.zstats.last_round_kills;
        if ( metric == "headshots" )
            return player.zstats.last_round_headshots;
        if ( metric == "melee_kills" )
            return player.zstats.last_round_melee_kills;
        if ( metric == "revives" )
            return player.zstats.last_round_revives;
        if ( metric == "downs" )
            return player.zstats.last_round_downs;
        if ( metric == "points" || metric == "points_earned" || metric == "round_points_earned" )
            return player.zstats.last_round_points;
        if ( metric == "points_spent" || metric == "round_points_spent" )
            return player.zstats.last_round_points_spent;
    }
    if ( metric == "kills" )
        return zs_nonnegative( player zs_stat( "kills" ) - player.zstats.round_kills_start );
    if ( metric == "headshots" )
        return zs_nonnegative( player zs_stat( "headshots" ) - player.zstats.round_headshots_start );
    if ( metric == "melee_kills" )
        return zs_nonnegative( player zs_stat( "melee_kills" ) - player.zstats.round_melee_kills_start );
    if ( metric == "revives" )
        return zs_nonnegative( player zs_stat( "revives" ) - player.zstats.round_revives_start );
    if ( metric == "downs" )
        return zs_nonnegative( player zs_stat( "downs" ) - player.zstats.round_downs_start );
    if ( metric == "points" )
        return player.zstats.round_points_earned;
    if ( metric == "points_earned" || metric == "round_points_earned" )
        return player.zstats.round_points_earned;
    if ( metric == "points_spent" || metric == "round_points_spent" )
        return player.zstats.round_points_spent;
    if ( metric == "round_kills" )
        return zs_round_value( player, "kills" );
    if ( metric == "round_headshots" )
        return zs_round_value( player, "headshots" );
    if ( metric == "round_revives" )
        return zs_round_value( player, "revives" );
    if ( metric == "round_downs" )
        return zs_round_value( player, "downs" );
    if ( isdefined( player.zstats.custom_round[metric] ) )
        return player.zstats.custom_round[metric];
    return 0;
}

zs_api_get_round_value( player, metric )
{
    if ( !level.zstats.enabled || !isdefined( player ) || !isplayer( player ) || !isdefined( metric ) || !isstring( metric ) )
        return 0;
    return zs_round_value( player, metric );
}

zs_capture_round_mvp_candidates( players )
{
    candidates = [];
    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i].zstats ) )
            candidates[candidates.size] = players[i] zs_player_snapshot();
    }
    return candidates;
}

zs_round_candidate_value( candidate, metric )
{
    if ( isdefined( candidate.zstats ) )
        return zs_round_value( candidate, metric );
    if ( metric == "kills" )
        return candidate.round_kills;
    if ( metric == "headshots" )
        return candidate.round_headshots;
    if ( metric == "revives" )
        return candidate.round_revives;
    if ( metric == "downs" )
        return candidate.round_downs;
    if ( metric == "points" || metric == "points_earned" || metric == "round_points_earned" )
        return candidate.round_points_earned;
    return 0;
}

zs_mvp_score( player )
{
    return zs_round_candidate_value( player, "kills" ) * 100 +
        zs_round_candidate_value( player, "headshots" ) * 35 +
        zs_round_candidate_value( player, "revives" ) * 250 +
        int( zs_round_candidate_value( player, "points" ) / 20 ) -
        zs_round_candidate_value( player, "downs" ) * 200;
}

zs_round_max( players, metric )
{
    best = 0;
    for ( i = 0; i < players.size; i++ )
    {
        value = zs_round_candidate_value( players[i], metric );
        if ( i == 0 || value > best )
            best = value;
    }
    return best;
}

zs_best_round_category( player, players )
{
    value = zs_round_candidate_value( player, "headshots" );
    if ( value > 0 && value == zs_round_max( players, "headshots" ) )
        return "most headshots (" + value + ")";

    value = zs_round_candidate_value( player, "revives" );
    if ( value > 0 && value == zs_round_max( players, "revives" ) )
        return "most revives (" + value + ")";

    value = zs_round_candidate_value( player, "kills" );
    if ( value > 0 && value == zs_round_max( players, "kills" ) )
        return "most kills (" + value + ")";

    value = zs_round_candidate_value( player, "points" );
    return "most points earned (" + value + ")";
}

zs_announce_round_mvp()
{
    players = level.zstats.pending_round_mvp_candidates;
    if ( !isarray( players ) || players.size == 0 )
        players = zs_tracked_players( getplayers() );
    if ( players.size == 0 )
    {
        level.zstats.pending_round_mvp_candidates = [];
        return;
    }

    best_score = zs_mvp_score( players[0] );
    winners = [];
    winners[0] = players[0];
    for ( i = 1; i < players.size; i++ )
    {
        score = zs_mvp_score( players[i] );
        if ( score > best_score )
        {
            best_score = score;
            winners = [];
            winners[0] = players[i];
        }
        else if ( score == best_score )
            winners[winners.size] = players[i];
    }

    names = zs_player_names( winners );
    category = zs_best_round_category( winners[0], players );
    round_number = level.zstats.current_round;
    if ( round_number <= 0 && zs_numeric( level.round_number ) )
        round_number = int( level.round_number );

    if ( winners.size > 1 )
        iprintln( "^5[ZStats]^7 Round " + round_number + " MVP tie: " + names + " - " + category );
    else
        iprintln( "^5[ZStats]^7 Round " + round_number + " MVP: " + names + " - " + category );
    level.zstats.pending_round_mvp_candidates = [];
}

zs_player_names( players )
{
    names = "";
    shown = players.size;
    if ( shown > 2 )
        shown = 2;
    for ( i = 0; i < shown; i++ )
    {
        if ( names != "" )
            names += " / ";
        names += zs_display_text( players[i].name, 16 );
    }
    if ( players.size > shown )
        names += " +" + ( players.size - shown );
    return names;
}

zs_display_text( value, max_length )
{
    text = "" + value;
    clean = "";
    for ( i = 0; i < text.size; i++ )
    {
        character = getsubstr( text, i, i + 1 );
        if ( character == "^" )
        {
            if ( i + 1 < text.size )
                i++;
            continue;
        }
        if ( character == "\n" || character == "\r" || character == "\t" )
        {
            clean += " ";
            continue;
        }
        clean += character;
    }
    text = clean;
    if ( text.size <= max_length )
        return text;
    if ( max_length < 4 )
        return getsubstr( text, 0, max_length );
    return getsubstr( text, 0, max_length - 3 ) + "...";
}

zs_zombies_left()
{
    if ( isdefined( level.on_the_moon ) && !level.on_the_moon )
        return -1;
    if ( !isdefined( level.zombie_team ) || !zs_numeric( level.zombie_total ) )
        return -1;

    level.zstats.capabilities.zombies_left = 1;

    active = zs_active_zombie_count();
    queued = 0;
    queued = int( level.zombie_total );
    total = active + queued;
    if ( total < 0 )
        total = 0;
    return total;
}

zs_active_zombie_count()
{
    if ( isdefined( level.custom_get_round_enemy_array_func ) )
    {
        custom_enemies = [[ level.custom_get_round_enemy_array_func ]]();
        if ( isarray( custom_enemies ) )
            return custom_enemies.size;
    }

    active = 0;
    ai = [];
    if ( isdefined( level.zombie_team ) )
        ai = getaispeciesarray( level.zombie_team, "all" );
    if ( isarray( ai ) )
    {
        for ( i = 0; i < ai.size; i++ )
        {
            if ( !isdefined( ai[i].ignore_enemy_count ) || !ai[i].ignore_enemy_count )
                active++;
        }
    }
    return active;
}

zs_format_time( milliseconds )
{
    seconds_total = int( milliseconds / 1000 );
    if ( seconds_total < 0 )
        seconds_total = 0;
    hours = int( seconds_total / 3600 );
    minutes = int( ( seconds_total - hours * 3600 ) / 60 );
    seconds = seconds_total - hours * 3600 - minutes * 60;

    seconds_text = "" + seconds;
    if ( seconds < 10 )
        seconds_text = "0" + seconds;
    minutes_text = "" + minutes;
    if ( hours > 0 && minutes < 10 )
        minutes_text = "0" + minutes;
    if ( hours > 0 )
        return hours + ":" + minutes_text + ":" + seconds_text;
    return minutes + ":" + seconds_text;
}

zs_match_elapsed()
{
    if ( !zs_numeric( level.zstats.match_start ) )
        return 0;
    return gettime() - level.zstats.match_start;
}

zs_round_elapsed()
{
    if ( !level.zstats.in_round || !level.zstats.capabilities.round_timing || !zs_numeric( level.zstats.round_start ) )
        return 0;
    return gettime() - level.zstats.round_start;
}

zs_average_tenths( value, rounds )
{
    if ( rounds < 1 )
        rounds = 1;
    return int( value * 10 / rounds );
}

zs_tenths_text( tenths )
{
    if ( tenths < 0 )
        tenths = 0;
    whole = int( tenths / 10 );
    fraction = tenths - whole * 10;
    return whole + "." + fraction;
}

zs_per_round_text( value, rounds )
{
    return zs_tenths_text( zs_average_tenths( value, rounds ) );
}

zs_percentage_text( numerator, denominator )
{
    if ( denominator <= 0 )
        return "N/A";
    return zs_tenths_text( int( numerator * 1000 / denominator ) ) + "%";
}

zs_ratio_text( numerator, denominator )
{
    if ( denominator <= 0 )
        return "N/A";
    return zs_tenths_text( int( numerator * 10 / denominator ) );
}

zs_hud_preset( player )
{
    preset = zs_cfg_string( "zs_hud_preset", "compact" );
    if ( preset != "minimal" && preset != "compact" && preset != "detailed" && preset != "custom" )
        preset = "compact";
    if ( isdefined( player.zstats.scoreboard_open ) && player.zstats.scoreboard_open )
    {
        scoreboard_preset = zs_cfg_string( "zs_scoreboard_hud_preset", "detailed" );
        if ( scoreboard_preset == "off" )
            return "off";
        if ( scoreboard_preset == "minimal" || scoreboard_preset == "compact" ||
            scoreboard_preset == "detailed" || scoreboard_preset == "custom" )
            return scoreboard_preset;
    }
    return preset;
}

zs_hud_metric_enabled( player, metric )
{
    preset = zs_hud_preset( player );
    if ( preset == "off" )
        return 0;
    if ( preset == "minimal" )
        return metric == "time" || metric == "zombies";
    if ( preset == "compact" )
        return metric == "time" || metric == "zombies" || metric == "ppr" || metric == "kpr";
    if ( preset == "detailed" )
        return 1;
    if ( metric == "time" )
        return zs_cfg_int( "zs_hud_time", 1 );
    if ( metric == "zombies" )
        return zs_cfg_int( "zs_hud_zombies_left", 1 );
    if ( metric == "ppr" )
        return zs_cfg_int( "zs_hud_ppr", 1 );
    if ( metric == "kpr" )
        return zs_cfg_int( "zs_hud_kpr", 1 );
    if ( metric == "round_time" )
        return zs_cfg_int( "zs_hud_round_time", 0 );
    if ( metric == "score" )
        return zs_cfg_int( "zs_hud_score", 0 );
    if ( metric == "round_kills" )
        return zs_cfg_int( "zs_hud_round_kills", 0 );
    if ( metric == "round_points" )
        return zs_cfg_int( "zs_hud_round_points", 0 );
    if ( metric == "headshots" )
        return zs_cfg_int( "zs_hud_headshots", 0 );
    if ( metric == "round_revives" )
        return zs_cfg_int( "zs_hud_round_revives", 0 );
    if ( metric == "round_number" )
        return zs_cfg_int( "zs_hud_round_number", 0 );
    return 0;
}

zs_hud_row( label, value )
{
    row = spawnstruct();
    row.label = label;
    row.value = value;
    row.mode = "text";
    row.token = value;
    row.pb = 0;
    return row;
}

zs_hud_number_row( label, value, pb_suffix )
{
    row = spawnstruct();
    row.label = label + pb_suffix;
    row.value = value;
    row.mode = "number";
    row.token = value;
    row.pb = pb_suffix != "";
    return row;
}

zs_hud_average_row( label, total, rounds, pb_suffix )
{
    row = zs_hud_row( label + pb_suffix, zs_per_round_text( total, rounds ) );
    row.pb = pb_suffix != "";
    return row;
}

zs_hud_timer_row( label, elapsed, anchor )
{
    row = spawnstruct();
    row.label = label;
    // SetTimerUp takes a negative offset to begin above zero.
    row.value = 0 - int( elapsed / 1000 );
    row.mode = "timer";
    row.token = anchor;
    row.pb = 0;
    return row;
}

zs_hud_pb_suffix( metric, total )
{
    if ( !zs_cfg_int( "zs_hud_personal_best", 1 ) || total <= 0 )
        return "";
    if ( self zs_pb_scope_career() && !self.zstats.pb_loaded )
        return "";
    current = zs_average_tenths( total, zs_observed_rounds( self ) );
    kind = 6;
    best = self.zstats.best_kpr_tenths;
    if ( metric == "ppr" )
    {
        kind = 7;
        best = self.zstats.best_ppr_tenths;
    }
    best = self zs_round_pb_threshold( kind, best );
    if ( !level.zstats.in_round && isdefined( self.zstats.last_round_pb[kind] ) && self.zstats.last_round_pb[kind] )
        return "  PB";
    if ( best < 0 || current > best )
        return "  PB";
    return "";
}

zs_hud_round_pb_suffix( kind, value, best )
{
    if ( !zs_cfg_int( "zs_hud_personal_best", 1 ) || value <= 0 )
        return "";
    if ( self zs_pb_scope_career() && !self.zstats.pb_loaded )
        return "";
    best = self zs_round_pb_threshold( kind, best );
    if ( level.zstats.in_round && value > best )
        return "  PB";
    if ( !level.zstats.in_round && self.zstats.last_round_valid &&
        isdefined( self.zstats.last_round_pb[kind] ) && self.zstats.last_round_pb[kind] )
        return "  PB";
    return "";
}

zs_hud_career_match_pb_suffix( kind, value )
{
    if ( !zs_cfg_int( "zs_hud_personal_best", 1 ) || value <= 0 ||
        !self zs_pb_scope_career() || !self.zstats.pb_loaded )
        return "";
    if ( value > self zs_round_pb_threshold( kind, 0 ) )
        return "  PB";
    return "";
}

zs_hud_rows()
{
    rows = [];
    rounds = zs_observed_rounds( self );
    match_kills = zs_match_value( self, "kills" );

    if ( zs_hud_metric_enabled( self, "time" ) )
        rows[rows.size] = zs_hud_timer_row( "TIME", zs_match_elapsed(), level.zstats.match_start );
    if ( zs_hud_metric_enabled( self, "zombies" ) )
    {
        zombies_row = zs_hud_row( "ZOMBIES", "--" );
        if ( level.zstats.in_round )
        {
            zombies_left = zs_zombies_left();
            if ( zombies_left >= 0 )
                zombies_row = zs_hud_number_row( "ZOMBIES", zombies_left, "" );
        }
        rows[rows.size] = zombies_row;
    }
    if ( zs_hud_metric_enabled( self, "ppr" ) )
    {
        ppr_pb = "";
        ppr_row = zs_hud_row( "PPR", "N/A" );
        if ( zs_score_available( self ) )
        {
            ppr_pb = self zs_hud_pb_suffix( "ppr", self.zstats.points_earned );
            ppr_row = zs_hud_average_row( "PPR", self.zstats.points_earned, rounds, ppr_pb );
        }
        rows[rows.size] = ppr_row;
    }
    if ( zs_hud_metric_enabled( self, "kpr" ) )
    {
        kpr_pb = self zs_hud_pb_suffix( "kpr", match_kills );
        rows[rows.size] = zs_hud_average_row( "KPR", match_kills, rounds, kpr_pb );
    }
    if ( zs_hud_metric_enabled( self, "round_time" ) )
    {
        round_time_row = zs_hud_row( "ROUND TIME", "--" );
        if ( level.zstats.in_round && level.zstats.capabilities.round_timing )
            round_time_row = zs_hud_timer_row( "ROUND TIME", zs_round_elapsed(), level.zstats.round_start );
        rows[rows.size] = round_time_row;
    }
    if ( zs_hud_metric_enabled( self, "score" ) )
    {
        earned_row = zs_hud_row( "EARNED", "N/A" );
        if ( zs_score_available( self ) )
            earned_row = zs_hud_number_row( "EARNED", self.zstats.points_earned,
                self zs_hud_career_match_pb_suffix( 9, self.zstats.points_earned ) );
        rows[rows.size] = earned_row;
    }
    if ( zs_hud_metric_enabled( self, "round_kills" ) )
    {
        round_kills = zs_round_value( self, "kills" );
        kills_pb = self zs_hud_round_pb_suffix( 1, round_kills, self.zstats.best_round_kills );
        if ( zs_hud_preset( self ) == "detailed" )
            rows[rows.size] = zs_hud_number_row( "KILLS", match_kills,
                self zs_hud_career_match_pb_suffix( 10, match_kills ) );
        else
            rows[rows.size] = zs_hud_number_row( "ROUND KILLS", round_kills, kills_pb );
    }
    if ( zs_hud_metric_enabled( self, "round_points" ) )
    {
        round_points = zs_round_value( self, "points" );
        points_row = zs_hud_row( "POINTS", "N/A" );
        if ( zs_score_available( self ) )
        {
            points_pb = self zs_hud_round_pb_suffix( 4, round_points, self.zstats.best_round_points );
            points_row = zs_hud_number_row( "POINTS", round_points, points_pb );
        }
        rows[rows.size] = points_row;
    }
    if ( zs_hud_metric_enabled( self, "headshots" ) )
    {
        round_headshots = zs_round_value( self, "headshots" );
        headshots_pb = self zs_hud_round_pb_suffix( 2, round_headshots, self.zstats.best_round_headshots );
        rows[rows.size] = zs_hud_number_row( "HEADSHOTS", round_headshots, headshots_pb );
    }
    if ( zs_hud_metric_enabled( self, "round_revives" ) )
    {
        players = getplayers();
        if ( zs_hud_preset( self ) == "detailed" )
        {
            revives_label = "REVIVES N/A";
            revives_pb = "";
            if ( players.size > 1 )
            {
                round_revives = zs_round_value( self, "revives" );
                revives_pb = self zs_hud_round_pb_suffix( 5, round_revives, self.zstats.best_round_revives );
                revives_label = "REVIVES " + round_revives + revives_pb;
            }
            revives_row = zs_hud_row( revives_label, "" );
            revives_row.mode = "single";
            revives_row.pb = revives_pb != "";
            rows[rows.size] = revives_row;
        }
        else if ( players.size <= 1 )
            rows[rows.size] = zs_hud_row( "REVIVES", "N/A" );
        else
        {
            round_revives = zs_round_value( self, "revives" );
            revives_pb = self zs_hud_round_pb_suffix( 5, round_revives, self.zstats.best_round_revives );
            rows[rows.size] = zs_hud_number_row( "REVIVES", round_revives, revives_pb );
        }
    }
    if ( zs_hud_metric_enabled( self, "round_number" ) )
    {
        current_round = zs_current_round_number();
        highest_round_pb = self zs_hud_career_match_pb_suffix( 11, current_round );
        round_label = "ROUND " + current_round + highest_round_pb;
        round_row = zs_hud_row( round_label, "" );
        round_row.mode = "single";
        round_row.pb = highest_round_pb != "";
        rows[rows.size] = round_row;
        if ( zs_hud_preset( self ) == "detailed" && zs_hud_metric_enabled( self, "round_kills" ) )
        {
            round_kills = zs_round_value( self, "kills" );
            round_pb = self zs_hud_round_pb_suffix( 1, round_kills, self.zstats.best_round_kills );
            kills_row = zs_hud_row( "ROUND KILLS " + round_kills + round_pb, "" );
            kills_row.mode = "single";
            kills_row.pb = round_pb != "";
            rows[rows.size] = kills_row;
        }
    }

    return rows;
}

zs_create_hud()
{
    self.zstats.hud_bg = newclienthudelem( self );
    self.zstats.hud_bg setshader( "white", 100, 76 );
    self.zstats.hud_bg.color = ( 0.01, 0.015, 0.02 );
    self.zstats.hud_bg.alpha = 0.22;
    self.zstats.hud_bg.sort = 5;
    self.zstats.hud_bg.foreground = 1;
    self.zstats.hud_bg.hidewheninmenu = 1;

    self.zstats.hud_accent = newclienthudelem( self );
    self.zstats.hud_accent setshader( "white", 100, 1 );
    self.zstats.hud_accent.color = ( 1, 0.35, 0.06 );
    self.zstats.hud_accent.alpha = 0.8;
    self.zstats.hud_accent.sort = 7;
    self.zstats.hud_accent.foreground = 1;
    self.zstats.hud_accent.hidewheninmenu = 1;

    self.zstats.hud_title = newclienthudelem( self );
    self.zstats.hud_title.font = "objective";
    self.zstats.hud_title.fontscale = 1.05;
    self.zstats.hud_title.color = ( 1, 0.45, 0.12 );
    self.zstats.hud_title.alpha = 0.9;
    self.zstats.hud_title.sort = 8;
    self.zstats.hud_title.foreground = 1;
    self.zstats.hud_title.hidewheninmenu = 1;
    self.zstats.hud_title settext( "ZSTATS" );

    self.zstats.hud_row_count = 0;
    self.zstats.hud_labels = [];
    self.zstats.hud_values = [];
    self.zstats.hud_label_text = [];
    self.zstats.hud_value_mode = [];
    self.zstats.hud_value_token = [];
    self.zstats.hud_last_row_single = 0;
}

zs_destroy_live_hud_elements()
{
    if ( !isdefined( self.zstats ) )
        return;

    if ( isdefined( self.zstats.hud_bg ) )
    {
        self.zstats.hud_bg destroy();
        self.zstats.hud_bg = undefined;
    }
    if ( isdefined( self.zstats.hud_accent ) )
    {
        self.zstats.hud_accent destroy();
        self.zstats.hud_accent = undefined;
    }
    if ( isdefined( self.zstats.hud_title ) )
    {
        self.zstats.hud_title destroy();
        self.zstats.hud_title = undefined;
    }
    if ( isdefined( self.zstats.hud_labels ) )
    {
        for ( i = 0; i < self.zstats.hud_labels.size; i++ )
        {
            if ( isdefined( self.zstats.hud_labels[i] ) )
                self.zstats.hud_labels[i] destroy();
            if ( isdefined( self.zstats.hud_values[i] ) )
                self.zstats.hud_values[i] destroy();
        }
    }
    self.zstats.hud_labels = [];
    self.zstats.hud_values = [];
    self.zstats.hud_label_text = [];
    self.zstats.hud_value_mode = [];
    self.zstats.hud_value_token = [];
    self.zstats.hud_last_row_single = 0;
    self.zstats.hud_row_count = 0;
}

zs_resize_hud_rows( count )
{
    single_last = 0;
    if ( count > 0 && zs_hud_metric_enabled( self, "round_number" ) )
    {
        single_last = 1;
        if ( zs_hud_preset( self ) == "detailed" && zs_hud_metric_enabled( self, "round_kills" ) )
            single_last = 3;
    }
    if ( self.zstats.hud_labels.size == count && self.zstats.hud_last_row_single == single_last )
        return;

    for ( i = 0; i < self.zstats.hud_labels.size; i++ )
    {
        self.zstats.hud_labels[i] destroy();
        if ( isdefined( self.zstats.hud_values[i] ) )
            self.zstats.hud_values[i] destroy();
    }
    self.zstats.hud_labels = [];
    self.zstats.hud_values = [];
    self.zstats.hud_label_text = [];
    self.zstats.hud_value_mode = [];
    self.zstats.hud_value_token = [];
    for ( i = 0; i < count; i++ )
    {
        label = newclienthudelem( self );
        label.font = "objective";
        label.fontscale = 1.0;
        label.color = ( 0.68, 0.72, 0.76 );
        label.alpha = 0;
        label.sort = 8;
        label.foreground = 1;
        label.hidewheninmenu = 1;
        self.zstats.hud_labels[i] = label;
        self.zstats.hud_label_text[i] = "";

        if ( i >= count - single_last )
            continue;
        value = newclienthudelem( self );
        value.font = "objective";
        value.fontscale = 1.0;
        value.color = ( 0.94, 0.96, 0.98 );
        value.alpha = 0;
        value.sort = 8;
        value.foreground = 1;
        value.hidewheninmenu = 1;
        self.zstats.hud_values[i] = value;
        self.zstats.hud_value_mode[i] = "";
        self.zstats.hud_value_token[i] = "";
    }
    self.zstats.hud_last_row_single = single_last;
}

zs_hud_base_width()
{
    preset = zs_hud_preset( self );
    if ( preset == "minimal" )
        return 86;
    if ( preset == "detailed" )
        return 126;
    if ( preset == "custom" && ( zs_cfg_int( "zs_hud_round_time", 0 ) || zs_cfg_int( "zs_hud_round_kills", 0 ) || zs_cfg_int( "zs_hud_round_points", 0 ) || zs_cfg_int( "zs_hud_headshots", 0 ) || zs_cfg_int( "zs_hud_round_revives", 0 ) || zs_cfg_int( "zs_hud_round_number", 0 ) ) )
        return 118;
    return 100;
}

zs_layout_hud()
{
    position = zs_cfg_string( "zs_hud_position", "top_right" );
    scale_percent = zs_cfg_int( "zs_hud_scale", 100 );
    if ( scale_percent < 75 )
        scale_percent = 75;
    if ( scale_percent > 125 )
        scale_percent = 125;
    if ( self issplitscreen() && scale_percent > 90 )
        scale_percent = 90;
    scale = scale_percent / 100.0;
    text_scale = 1.0 + ( scale_percent - 75 ) / 500.0;
    row_spacing = int( 17 * scale );
    if ( row_spacing < 15 )
        row_spacing = 15;
    show_header = zs_cfg_int( "zs_hud_header", 1 );
    header_height = int( 22 * scale );
    if ( !show_header )
        header_height = int( 8 * scale );
    if ( header_height < 6 )
        header_height = 6;

    right = position == "top_right" || position == "bottom_right";
    bottom = position == "bottom_right" || position == "bottom_left";
    width = int( zs_hud_base_width() * scale );
    height = header_height + self.zstats.hud_row_count * row_spacing + int( 6 * scale );

    horizontal = "left";
    vertical = "top";
    // T6's LEFT/RIGHT HUD anchors sit inside a narrower safe-area canvas on
    // widescreen than T7's. Offset past that inset to match the BO3 card's
    // screen-edge placement; retain the conservative split-screen margin.
    edge_x = 0 - int( 52 * scale );
    edge_y = 82;
    if ( self issplitscreen() )
    {
        edge_x = int( 18 * scale );
        edge_y = 34;
    }
    if ( right )
    {
        horizontal = "right";
        edge_x = 0 - edge_x;
    }
    if ( bottom )
    {
        vertical = "bottom";
        edge_y = 0 - int( 32 * scale );
        if ( self issplitscreen() )
            edge_y = 0 - int( 20 * scale );
    }

    self.zstats.hud_bg.horzalign = horizontal;
    self.zstats.hud_bg.vertalign = vertical;
    self.zstats.hud_bg.alignx = horizontal;
    self.zstats.hud_bg.aligny = vertical;
    self.zstats.hud_bg.x = edge_x;
    self.zstats.hud_bg.y = edge_y;
    self.zstats.hud_bg setshader( "white", width, height );

    top_y = edge_y;
    if ( bottom )
        top_y = edge_y - height;
    self.zstats.hud_accent.horzalign = horizontal;
    self.zstats.hud_accent.vertalign = vertical;
    self.zstats.hud_accent.alignx = horizontal;
    self.zstats.hud_accent.aligny = "top";
    self.zstats.hud_accent.x = edge_x;
    self.zstats.hud_accent.y = top_y;
    self.zstats.hud_accent setshader( "white", width, int( 1 * scale ) );

    self.zstats.hud_title.horzalign = horizontal;
    self.zstats.hud_title.vertalign = vertical;
    self.zstats.hud_title.alignx = "center";
    self.zstats.hud_title.aligny = "top";
    self.zstats.hud_title.x = edge_x + int( width / 2 );
    if ( right )
        self.zstats.hud_title.x = edge_x - int( width / 2 );
    self.zstats.hud_title.y = top_y + int( 5 * scale );
    self.zstats.hud_title.fontscale = text_scale;

    inset = int( 7 * scale );
    label_x = edge_x + inset;
    value_x = edge_x + width - inset;
    if ( right )
    {
        label_x = edge_x - width + inset;
        value_x = edge_x - inset;
    }
    for ( i = 0; i < self.zstats.hud_labels.size; i++ )
    {
        self.zstats.hud_labels[i].horzalign = horizontal;
        self.zstats.hud_labels[i].vertalign = vertical;
        self.zstats.hud_labels[i].alignx = "left";
        self.zstats.hud_labels[i].aligny = "top";
        self.zstats.hud_labels[i].x = label_x;
        self.zstats.hud_labels[i].y = top_y + header_height + i * row_spacing;
        self.zstats.hud_labels[i].fontscale = text_scale;

        if ( i >= self.zstats.hud_labels.size - self.zstats.hud_last_row_single )
        {
            self.zstats.hud_labels[i].alignx = "right";
            self.zstats.hud_labels[i].x = value_x;
        }
        if ( isdefined( self.zstats.hud_values[i] ) )
        {
            self.zstats.hud_values[i].horzalign = horizontal;
            self.zstats.hud_values[i].vertalign = vertical;
            self.zstats.hud_values[i].alignx = "right";
            self.zstats.hud_values[i].aligny = "top";
            self.zstats.hud_values[i].x = value_x;
            self.zstats.hud_values[i].y = top_y + header_height + i * row_spacing;
            self.zstats.hud_values[i].fontscale = text_scale;
        }
    }
}

zs_hud_effective_enabled()
{
    if ( isdefined( self.zstats.hud_client_override ) )
        return self.zstats.hud_client_override;
    return zs_cfg_int( "zs_hud_enabled", 1 );
}

zs_zpause_is_paused()
{
    // Consume only ZPause's published descriptor. ZStats may load before or
    // after ZPause, so absence is a normal standalone state rather than a
    // reason to reach into ZPause's private level fields.
    if ( !isdefined( level.zmods ) || !isdefined( level.zmods["zpause"] ) )
        return 0;
    if ( !isdefined( level.zmods["zpause"].enabled ) || !level.zmods["zpause"].enabled )
        return 0;
    if ( !isdefined( level.zmods["zpause"].is_paused ) )
        return 0;
    return [[ level.zmods["zpause"].is_paused ]]();
}

zs_zpause_hud_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    pause_suppressed = 0;
    while ( 1 )
    {
        paused = zs_zpause_is_paused();
        if ( paused && !pause_suppressed )
        {
            // ZPause publishes its state before its pause-HUD ease-in
            // completes. Release this client's live card during that window
            // so the pause clock, pauser name, and resume hint can render.
            pause_suppressed = 1;
            self.zstats.hud_pause_suppressed = 1;
            self zs_destroy_live_hud_elements();
        }
        else if ( !paused && pause_suppressed )
        {
            pause_suppressed = 0;
            self.zstats.hud_pause_suppressed = undefined;
        }
        wait 0.05;
    }
}

zs_menu_response_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    while ( 1 )
    {
        self waittill( "menuresponse", menu, response );
        if ( isdefined( response ) && isstring( response ) && response.size >= 10 &&
            getsubstr( response, 0, 10 ) == "zstats_pb|" )
        {
            self zs_pb_apply_record( response );
            continue;
        }
        if ( isdefined( response ) && isstring( response ) && response.size >= 16 &&
            getsubstr( response, 0, 16 ) == "zstats_pb_reset|" )
        {
            self zs_pb_reset_record( response );
            continue;
        }
        if ( isdefined( menu ) && menu == "class" && isdefined( response ) &&
            ( response == "zstats_scoreboard_on" || response == "zstats_scoreboard_off" ) )
        {
            self.zstats.scoreboard_open = response == "zstats_scoreboard_on";
            continue;
        }
        legacy_response = isdefined( menu ) && menu == "zstats" && isdefined( response ) && response == "toggle_hud";
        pause_response = isdefined( menu ) && menu == "class" && isdefined( response ) && response == "zstats_toggle_hud";
        if ( !legacy_response && !pause_response )
            continue;

        if ( self zs_hud_effective_enabled() )
        {
            self.zstats.hud_client_override = 0;
            self iprintlnbold( "^5ZStats HUD^7 hidden" );
        }
        else
        {
            self.zstats.hud_client_override = 1;
            self iprintlnbold( "^5ZStats HUD^7 shown" );
        }
    }
}

zs_hud_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    while ( !zs_gameplay_ready() )
        wait 0.1;

    while ( 1 )
    {
        // Game-over finalization hides the live card before intermission is
        // guaranteed. Do not let this refresh loop make it visible again.
        if ( isdefined( self.zstats.hud_hidden ) && self.zstats.hud_hidden )
            return;
        if ( isdefined( level.intermission ) && level.intermission )
        {
            self zs_hide_live_hud();
            return;
        }

        enabled = self zs_hud_effective_enabled();
        if ( isdefined( self.zstats.hud_pause_suppressed ) && self.zstats.hud_pause_suppressed )
            enabled = 0;
        if ( !enabled )
        {
            // A client-hidden panel must release its HUD slots and stop
            // publishing dynamic text, not merely become transparent.
            self zs_destroy_live_hud_elements();
            wait 0.25;
            continue;
        }
        if ( zs_hud_preset( self ) == "off" )
        {
            self zs_destroy_live_hud_elements();
            wait 0.25;
            continue;
        }
        rows = self zs_hud_rows();
        if ( rows.size == 0 && !zs_cfg_int( "zs_hud_header", 1 ) )
        {
            // A fully disabled Custom layout has no visible content. Avoid
            // retaining a blank card or rebuilding it every refresh.
            if ( isdefined( self.zstats.hud_bg ) )
                self zs_destroy_live_hud_elements();
            wait 0.25;
            continue;
        }
        if ( !isdefined( self.zstats.hud_bg ) )
            self zs_create_hud();

        self.zstats.hud_row_count = rows.size;
        self zs_resize_hud_rows( rows.size );
        self zs_layout_hud();
        for ( i = 0; i < self.zstats.hud_labels.size; i++ )
        {
            if ( i < rows.size )
            {
                if ( self.zstats.hud_label_text[i] != rows[i].label )
                {
                    self.zstats.hud_labels[i] settext( rows[i].label );
                    self.zstats.hud_label_text[i] = rows[i].label;
                }
                if ( isdefined( self.zstats.hud_values[i] ) &&
                    ( self.zstats.hud_value_mode[i] != rows[i].mode || self.zstats.hud_value_token[i] != rows[i].token ) )
                {
                    if ( rows[i].mode == "number" )
                        self.zstats.hud_values[i] setvalue( rows[i].value );
                    else if ( rows[i].mode == "timer" )
                        self.zstats.hud_values[i] settimerup( rows[i].value );
                    else
                        self.zstats.hud_values[i] settext( rows[i].value );
                    self.zstats.hud_value_mode[i] = rows[i].mode;
                    self.zstats.hud_value_token[i] = rows[i].token;
                }
                self.zstats.hud_labels[i].alpha = 0.78;
                if ( rows[i].mode == "single" )
                {
                    self.zstats.hud_labels[i].color = ( 0.94, 0.96, 0.98 );
                    if ( rows[i].pb ) self.zstats.hud_labels[i].color = ( 1, 0.45, 0.12 );
                }
                else
                    self.zstats.hud_labels[i].color = ( 0.68, 0.72, 0.76 );
                if ( isdefined( self.zstats.hud_values[i] ) )
                {
                    self.zstats.hud_values[i].alpha = 0.95;
                    self.zstats.hud_values[i].color = ( 0.94, 0.96, 0.98 );
                    if ( rows[i].pb )
                        self.zstats.hud_values[i].color = ( 1, 0.45, 0.12 );
                }
            }
            else
            {
                if ( self.zstats.hud_label_text[i] != "" )
                {
                    self.zstats.hud_labels[i] settext( "" );
                    self.zstats.hud_label_text[i] = "";
                }
                if ( isdefined( self.zstats.hud_values[i] ) &&
                    ( self.zstats.hud_value_mode[i] != "text" || self.zstats.hud_value_token[i] != "" ) )
                {
                    self.zstats.hud_values[i] settext( "" );
                    self.zstats.hud_value_mode[i] = "text";
                    self.zstats.hud_value_token[i] = "";
                }
                self.zstats.hud_labels[i].alpha = 0;
                if ( isdefined( self.zstats.hud_values[i] ) )
                    self.zstats.hud_values[i].alpha = 0;
            }
        }
        opacity = zs_cfg_int( "zs_hud_opacity", 22 );
        if ( opacity < 0 )
            opacity = 0;
        if ( opacity > 60 )
            opacity = 60;
        self.zstats.hud_bg.alpha = opacity / 100.0;
        self.zstats.hud_accent.alpha = 0.8;
        self.zstats.hud_title.alpha = 0;
        if ( zs_cfg_int( "zs_hud_header", 1 ) )
            self.zstats.hud_title.alpha = 0.9;
        wait 0.25;
    }
}

zs_player_snapshot()
{
    self zs_sample_score();
    snapshot = spawnstruct();
    snapshot.player_id = self.zstats.player_id;
    snapshot.stable_key = self.zstats.stable_key;
    snapshot.name = zs_display_text( self.name, 16 );
    snapshot.solo = level.zstats.next_player_id <= 2;
    snapshot.score_supported = self.zstats.score_supported;
    snapshot.spending_supported = zs_spending_available();
    snapshot.kills = zs_match_value( self, "kills" );
    snapshot.headshots = zs_match_value( self, "headshots" );
    snapshot.melee_kills = zs_match_value( self, "melee_kills" );
    snapshot.revives = zs_match_value( self, "revives" );
    snapshot.downs = zs_match_value( self, "downs" );
    snapshot.doors = zs_match_value( self, "doors" );
    snapshot.boards = zs_match_value( self, "boards" );
    snapshot.points_earned = self.zstats.points_earned;
    snapshot.points_spent = self.zstats.points_spent;
    snapshot.ending_score = self zs_stat( "score" );
    if ( isdefined( self.zstats.ending_score ) )
        snapshot.ending_score = self.zstats.ending_score;
    snapshot.perks = self.zstats.perks_acquired;
    stock_perks = zs_nonnegative( self zs_stat( "perks_drank" ) - self.zstats.start_perks );
    if ( stock_perks > snapshot.perks )
        snapshot.perks = stock_perks;
    snapshot.round_kills = zs_round_value( self, "kills" );
    snapshot.round_headshots = zs_round_value( self, "headshots" );
    snapshot.round_melee_kills = zs_round_value( self, "melee_kills" );
    snapshot.round_revives = zs_round_value( self, "revives" );
    snapshot.round_downs = zs_round_value( self, "downs" );
    snapshot.round_points_earned = zs_round_value( self, "points_earned" );
    snapshot.round_points_spent = zs_round_value( self, "points_spent" );
    snapshot.match_elapsed_ms = zs_match_elapsed();
    snapshot.round_elapsed_ms = zs_round_elapsed();
    snapshot.current_round = zs_current_round_number();
    // Reconnect persistence must retain zero when no numbered round was seen;
    // formatting/division helpers clamp only at the point of use.
    snapshot.rounds_played = self.zstats.rounds_played;
    snapshot.completed_rounds = self.zstats.completed_rounds;
    snapshot.join_round = self.zstats.join_round;
    snapshot.last_round_number = self.zstats.last_round_number;
    snapshot.opening_points_pending = self.zstats.opening_points_pending;
    snapshot.round_active = self.zstats.round_active;
    snapshot.last_round_valid = self.zstats.last_round_valid;
    snapshot.last_round_kills = self.zstats.last_round_kills;
    snapshot.last_round_headshots = self.zstats.last_round_headshots;
    snapshot.last_round_melee_kills = self.zstats.last_round_melee_kills;
    snapshot.last_round_revives = self.zstats.last_round_revives;
    snapshot.last_round_downs = self.zstats.last_round_downs;
    snapshot.last_round_points = self.zstats.last_round_points;
    snapshot.last_round_points_spent = self.zstats.last_round_points_spent;
    snapshot.best_round_kills = self.zstats.best_round_kills;
    snapshot.best_round_points = self.zstats.best_round_points;
    snapshot.best_round_headshots = self.zstats.best_round_headshots;
    snapshot.best_round_melee_kills = self.zstats.best_round_melee_kills;
    snapshot.best_round_revives = self.zstats.best_round_revives;
    snapshot.fastest_round = self.zstats.fastest_round;
    snapshot.slowest_round = self.zstats.slowest_round;
    snapshot.best_kpr_tenths = self.zstats.best_kpr_tenths;
    snapshot.best_ppr_tenths = self.zstats.best_ppr_tenths;
    snapshot.pb_scope = self.zstats.pb_scope;
    snapshot.pb_announce = self.zstats.pb_announce;
    snapshot.pb_loaded = self.zstats.pb_loaded;
    snapshot.career_best_round_kills = self.zstats.career_best_round_kills;
    snapshot.career_best_round_headshots = self.zstats.career_best_round_headshots;
    snapshot.career_best_round_melee_kills = self.zstats.career_best_round_melee_kills;
    snapshot.career_best_round_points = self.zstats.career_best_round_points;
    snapshot.career_best_round_revives = self.zstats.career_best_round_revives;
    snapshot.career_best_kpr_tenths = self.zstats.career_best_kpr_tenths;
    snapshot.career_best_ppr_tenths = self.zstats.career_best_ppr_tenths;
    snapshot.career_fastest_round = self.zstats.career_fastest_round;
    snapshot.career_best_match_earned = self.zstats.career_best_match_earned;
    snapshot.career_best_match_kills = self.zstats.career_best_match_kills;
    snapshot.career_highest_round = self.zstats.career_highest_round;
    snapshot.career_pb_new = self.zstats.career_pb_new;
    snapshot.career_pb_previous = self.zstats.career_pb_previous;
    snapshot.match_pb_new = self.zstats.match_pb_new;
    snapshot.match_pb_previous = self.zstats.match_pb_previous;
    snapshot.custom_match = [];
    snapshot.custom_round = [];
    for ( i = 0; i < level.zstats.metrics.size; i++ )
    {
        metric = level.zstats.metrics[i];
        if ( metric.scope == "round" && isdefined( self.zstats.custom_round[metric.id] ) )
            snapshot.custom_round[metric.id] = self.zstats.custom_round[metric.id];
        else if ( metric.scope == "match" && isdefined( self.zstats.custom_match[metric.id] ) )
            snapshot.custom_match[metric.id] = self.zstats.custom_match[metric.id];
    }
    // Active-round aggregates are partial samples, not personal bests. Normal
    // game-over and pending-round paths finalize before taking this snapshot.
    if ( !snapshot.round_active )
    {
        current_kpr = zs_average_tenths( snapshot.kills, snapshot.rounds_played );
        current_ppr = zs_average_tenths( snapshot.points_earned, snapshot.rounds_played );
        if ( current_kpr > snapshot.best_kpr_tenths )
            snapshot.best_kpr_tenths = current_kpr;
        if ( current_ppr > snapshot.best_ppr_tenths )
            snapshot.best_ppr_tenths = current_ppr;
    }
    return snapshot;
}

zs_api_get_player_snapshot( player )
{
    snapshot = spawnstruct();
    snapshot.score_supported = 0;
    snapshot.spending_supported = 0;
    snapshot.kills = 0;
    snapshot.headshots = 0;
    snapshot.revives = 0;
    snapshot.downs = 0;
    snapshot.doors = 0;
    snapshot.barriers = 0;
    snapshot.melee_kills = 0;
    snapshot.score = 0;
    snapshot.points_earned = 0;
    snapshot.points_spent = 0;
    snapshot.perks_acquired = 0;
    snapshot.round_kills = 0;
    snapshot.round_headshots = 0;
    snapshot.round_revives = 0;
    snapshot.round_downs = 0;
    snapshot.round_points_earned = 0;
    snapshot.round_points_spent = 0;
    snapshot.match_elapsed_ms = 0;
    snapshot.round_elapsed_ms = 0;
    snapshot.current_round = 0;
    if ( !level.zstats.enabled || !isdefined( player ) || !isplayer( player ) || !isdefined( player.zstats ) )
        return snapshot;
    snapshot.score_supported = player.zstats.score_supported;
    snapshot.spending_supported = zs_spending_available();
    snapshot.kills = zs_match_value( player, "kills" );
    snapshot.headshots = zs_match_value( player, "headshots" );
    snapshot.revives = zs_match_value( player, "revives" );
    snapshot.downs = zs_match_value( player, "downs" );
    snapshot.doors = zs_match_value( player, "doors" );
    snapshot.barriers = zs_match_value( player, "barriers" );
    snapshot.melee_kills = zs_match_value( player, "melee_kills" );
    snapshot.score = zs_match_value( player, "score" );
    snapshot.points_earned = zs_match_value( player, "points_earned" );
    snapshot.points_spent = zs_match_value( player, "points_spent" );
    snapshot.perks_acquired = zs_match_value( player, "perks_acquired" );
    snapshot.round_kills = zs_round_value( player, "kills" );
    snapshot.round_headshots = zs_round_value( player, "headshots" );
    snapshot.round_revives = zs_round_value( player, "revives" );
    snapshot.round_downs = zs_round_value( player, "downs" );
    snapshot.round_points_earned = zs_round_value( player, "points_earned" );
    snapshot.round_points_spent = zs_round_value( player, "points_spent" );
    snapshot.match_elapsed_ms = zs_match_elapsed();
    snapshot.round_elapsed_ms = zs_round_elapsed();
    snapshot.current_round = zs_current_round_number();
    return snapshot;
}

zs_disconnect_watch()
{
    level endon( "end_game" );
    self waittill( "disconnect" );
    if ( !isdefined( self.zstats ) )
        return;
    self zs_settle_chugabud_spending( 1 );
    if ( level.zstats.pending_round_completion && self.zstats.round_active )
        self zs_finalize_round();
    departed = self zs_player_snapshot();
    level.zstats.departed_snapshots = zs_upsert_snapshot( level.zstats.departed_snapshots, departed );
}

zs_collect_snapshots( players )
{
    snapshots = [];
    for ( i = 0; i < level.zstats.departed_snapshots.size; i++ )
        snapshots = zs_upsert_snapshot( snapshots, level.zstats.departed_snapshots[i] );
    return zs_merge_snapshots( snapshots, players );
}

zs_merge_snapshots( snapshots, players )
{
    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i].zstats ) )
        {
            active = players[i] zs_player_snapshot();
            snapshots = zs_upsert_snapshot( snapshots, active );
        }
    }
    return snapshots;
}

zs_find_snapshot( snapshots, player_id )
{
    for ( i = 0; i < snapshots.size; i++ )
    {
        if ( snapshots[i].player_id == player_id )
            return snapshots[i];
    }
    return undefined;
}

zs_tracked_players( players )
{
    tracked = [];
    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i].zstats ) && isdefined( players[i].zstats.player_id ) )
            tracked[tracked.size] = players[i];
    }
    return tracked;
}

zs_snapshot_metric( snapshot, metric )
{
    if ( metric == "kills" )
        return snapshot.kills;
    if ( metric == "headshots" )
        return snapshot.headshots;
    if ( metric == "melee_kills" )
        return snapshot.melee_kills;
    if ( metric == "revives" )
        return snapshot.revives;
    if ( metric == "downs" )
        return snapshot.downs;
    if ( metric == "doors" )
        return snapshot.doors;
    if ( metric == "boards" )
        return snapshot.boards;
    if ( metric == "barriers" )
        return snapshot.boards;
    if ( metric == "score" )
    {
        if ( isdefined( snapshot.score_supported ) && !snapshot.score_supported )
            return 0;
        return snapshot.points_earned;
    }
    if ( metric == "points_earned" )
    {
        if ( isdefined( snapshot.score_supported ) && !snapshot.score_supported )
            return 0;
        return snapshot.points_earned;
    }
    if ( metric == "points_spent" )
    {
        if ( !isdefined( snapshot.spending_supported ) || !snapshot.spending_supported )
            return 0;
        return snapshot.points_spent;
    }
    if ( metric == "perks" )
        return snapshot.perks;
    if ( metric == "perks_acquired" )
        return snapshot.perks;
    if ( metric == "round_kills" )
        return snapshot.round_kills;
    if ( metric == "round_headshots" )
        return snapshot.round_headshots;
    if ( metric == "round_revives" )
        return snapshot.round_revives;
    if ( metric == "round_downs" )
        return snapshot.round_downs;
    if ( metric == "round_points_earned" )
    {
        if ( isdefined( snapshot.score_supported ) && !snapshot.score_supported )
            return 0;
        return snapshot.round_points_earned;
    }
    if ( metric == "round_points_spent" )
    {
        if ( !isdefined( snapshot.spending_supported ) || !snapshot.spending_supported )
            return 0;
        return snapshot.round_points_spent;
    }
    if ( metric == "match_elapsed_ms" )
        return snapshot.match_elapsed_ms;
    if ( metric == "round_elapsed_ms" )
        return snapshot.round_elapsed_ms;
    if ( metric == "current_round" )
        return snapshot.current_round;
    if ( isdefined( snapshot.custom_match[metric] ) )
        return snapshot.custom_match[metric];
    if ( isdefined( snapshot.custom_round[metric] ) )
        return snapshot.custom_round[metric];
    return 0;
}

zs_award_line( label, snapshots, metric, lowest )
{
    best = zs_snapshot_metric( snapshots[0], metric );
    winners = [];
    winners[0] = snapshots[0];
    for ( i = 1; i < snapshots.size; i++ )
    {
        value = zs_snapshot_metric( snapshots[i], metric );
        better = value > best;
        if ( lowest )
            better = value < best;
        if ( better )
        {
            best = value;
            winners = [];
            winners[0] = snapshots[i];
        }
        else if ( value == best )
            winners[winners.size] = snapshots[i];
    }
    return label + "  " + zs_player_names( winners ) + "  " + best;
}

zs_metric_has_positive( snapshots, metric )
{
    for ( i = 0; i < snapshots.size; i++ )
    {
        if ( zs_snapshot_metric( snapshots[i], metric ) > 0 )
            return 1;
    }
    return 0;
}

zs_game_over_rows( snapshots )
{
    rows = [];
    rows[rows.size] = "ZSTATS TEAM AWARDS";
    if ( zs_metric_has_positive( snapshots, "kills" ) )
        rows[rows.size] = zs_award_line( "KILL LEADER", snapshots, "kills", 0 );
    if ( zs_metric_has_positive( snapshots, "headshots" ) )
        rows[rows.size] = zs_award_line( "HEADSHOT KING", snapshots, "headshots", 0 );
    if ( zs_metric_has_positive( snapshots, "melee_kills" ) )
        rows[rows.size] = zs_award_line( "BRAWLER", snapshots, "melee_kills", 0 );
    if ( zs_metric_has_positive( snapshots, "revives" ) )
        rows[rows.size] = zs_award_line( "FIELD MEDIC", snapshots, "revives", 0 );
    if ( zs_metric_has_positive( snapshots, "points_earned" ) )
        rows[rows.size] = zs_award_line( "TOP EARNER", snapshots, "points_earned", 0 );
    if ( zs_metric_has_positive( snapshots, "doors" ) )
        rows[rows.size] = zs_award_line( "EXPLORER", snapshots, "doors", 0 );
    if ( zs_metric_has_positive( snapshots, "boards" ) )
        rows[rows.size] = zs_award_line( "BUILDER", snapshots, "boards", 0 );
    if ( zs_metric_has_positive( snapshots, "perks" ) )
        rows[rows.size] = zs_award_line( "PERK FAN", snapshots, "perks", 0 );
    rows[rows.size] = zs_award_line( "SURVIVOR", snapshots, "downs", 1 );
    if ( zs_cfg_int( "zs_show_lowlights", 0 ) && zs_metric_has_positive( snapshots, "downs" ) )
        rows[rows.size] = zs_award_line( "MOST DOWNS", snapshots, "downs", 0 );
    custom_awards = 0;
    for ( i = 0; i < level.zstats.awards.size; i++ )
    {
        line = zs_registered_award_line( level.zstats.awards[i], snapshots );
        if ( line != "" )
        {
            if ( custom_awards >= 6 )
            {
                rows[rows.size] = "ADDITIONAL API AWARDS OMITTED";
                break;
            }
            rows[rows.size] = line;
            custom_awards++;
        }
    }
    return rows;
}

zs_registered_award_line( award, snapshots )
{
    if ( award.lowlight && !zs_cfg_int( "zs_show_lowlights", 0 ) )
        return "";
    if ( ( award.metric_id == "points_spent" || award.metric_id == "round_points_spent" ) &&
        !zs_spending_available() )
        return "";
    best = zs_snapshot_metric( snapshots[0], award.metric_id );
    winners = [];
    winners[0] = snapshots[0];
    for ( i = 1; i < snapshots.size; i++ )
    {
        value = zs_snapshot_metric( snapshots[i], award.metric_id );
        better = value > best;
        if ( award.lowest )
            better = value < best;
        if ( better )
        {
            best = value;
            winners = [];
            winners[0] = snapshots[i];
        }
        else if ( value == best && award.allow_ties )
            winners[winners.size] = snapshots[i];
    }
    if ( best == 0 && !award.show_zero )
        return "";
    return award.label + "  " + zs_player_names( winners ) + "  " + best;
}

zs_personal_summary_rows( snapshot )
{
    rows = [];
    rows[rows.size] = "ZSTATS PERSONAL SUMMARY";
    rows[rows.size] = "KILLS  " + snapshot.kills + "   HEADSHOTS  " + snapshot.headshots;
    spend_rate = "N/A";
    earned = "N/A";
    spent = "N/A";
    ppr = "N/A";
    if ( snapshot.score_supported )
    {
        earned = "+" + snapshot.points_earned;
        ppr = zs_per_round_text( snapshot.points_earned, snapshot.rounds_played );
    }
    if ( snapshot.spending_supported )
    {
        spent = "0";
        if ( snapshot.points_spent > 0 ) spent = "-" + snapshot.points_spent;
        if ( snapshot.score_supported )
            spend_rate = zs_percentage_text( snapshot.points_spent, snapshot.points_earned );
    }
    rows[rows.size] = "HEADSHOT RATE  " + zs_percentage_text( snapshot.headshots, snapshot.kills ) + "   SPEND RATE  " + spend_rate;
    rows[rows.size] = "EARNED  " + earned + "   SPENT  " + spent;
    rows[rows.size] = "ENDING POINTS  " + snapshot.ending_score;
    if ( snapshot.completed_rounds <= 0 )
    {
        rows[rows.size] = "ROUND AVERAGES  KPR N/A   PPR N/A";
        rows[rows.size] = "FINAL ROUND " + snapshot.current_round + " (GAME OVER)";
    }
    else
    {
        average_label = "COMPLETED AVG";
        if ( snapshot.round_active ) average_label = "FINAL MATCH AVG";
        rows[rows.size] = average_label + "  KPR " + zs_per_round_text( snapshot.kills, snapshot.rounds_played ) + "   PPR " + ppr;
        rows[rows.size] = "COMPLETED ROUNDS  " + snapshot.completed_rounds;
        if ( snapshot.round_active ) rows[rows.size] = "FINAL ROUND " + snapshot.current_round + " (GAME OVER)";
    }
    if ( isdefined( snapshot.solo ) && snapshot.solo )
        rows[rows.size] = "DOWNS  " + snapshot.downs + "   REVIVES  N/A   R/D  N/A";
    else
        rows[rows.size] = "DOWNS  " + snapshot.downs + "   REVIVES  " + snapshot.revives + "   R/D  " + zs_ratio_text( snapshot.revives, snapshot.downs );
    rows[rows.size] = "DOORS  " + snapshot.doors + "   BARRIERS  " + snapshot.boards;
    rows[rows.size] = "PERKS  " + snapshot.perks + "   MELEE KILLS  " + snapshot.melee_kills;
    return rows;
}

zs_time_or_dash( milliseconds )
{
    if ( milliseconds <= 0 )
        return "N/A";
    return zs_format_time( milliseconds );
}

zs_game_over_best_average_tenths( snapshot, total, completed_best )
{
    // PB averages are completed-round records. A game-over sample from an
    // unfinished round is still shown as a final match average, but never
    // promoted into KPR/PPR career or match records.
    if ( snapshot.completed_rounds <= 0 )
        return -1;
    return completed_best;
}

zs_snapshot_pb_value( snapshot, kind, match_value )
{
    if ( !isdefined( snapshot.pb_scope ) || snapshot.pb_scope != "career" || !snapshot.pb_loaded )
        return match_value;
    if ( kind == 1 ) return snapshot.career_best_round_kills;
    if ( kind == 2 ) return snapshot.career_best_round_headshots;
    if ( kind == 3 ) return snapshot.career_best_round_melee_kills;
    if ( kind == 4 ) return snapshot.career_best_round_points;
    if ( kind == 5 ) return snapshot.career_best_round_revives;
    if ( kind == 6 ) return snapshot.career_best_kpr_tenths;
    if ( kind == 7 ) return snapshot.career_best_ppr_tenths;
    if ( kind == 8 ) return snapshot.career_fastest_round;
    if ( kind == 9 ) return snapshot.career_best_match_earned;
    if ( kind == 10 ) return snapshot.career_best_match_kills;
    if ( kind == 11 ) return snapshot.career_highest_round;
    return match_value;
}

zs_snapshot_new_career_pb( snapshot, kind )
{
    return isdefined( snapshot.pb_scope ) && snapshot.pb_scope == "career" && snapshot.pb_loaded &&
        isdefined( snapshot.career_pb_new ) && isdefined( snapshot.career_pb_new[kind] ) && snapshot.career_pb_new[kind];
}

zs_snapshot_new_pb( snapshot, kind )
{
    if ( isdefined( snapshot.pb_scope ) && snapshot.pb_scope == "career" )
        return zs_snapshot_new_career_pb( snapshot, kind );
    return isdefined( snapshot.match_pb_new ) && isdefined( snapshot.match_pb_new[kind] ) && snapshot.match_pb_new[kind];
}

zs_snapshot_pb_previous( snapshot, kind )
{
    if ( isdefined( snapshot.pb_scope ) && snapshot.pb_scope == "career" )
    {
        if ( isdefined( snapshot.career_pb_previous ) && isdefined( snapshot.career_pb_previous[kind] ) )
            return snapshot.career_pb_previous[kind];
        return 0;
    }
    if ( isdefined( snapshot.match_pb_previous ) && isdefined( snapshot.match_pb_previous[kind] ) )
        return snapshot.match_pb_previous[kind];
    return 0;
}

zs_snapshot_current_pb( snapshot, kind )
{
    if ( isdefined( snapshot.pb_scope ) && snapshot.pb_scope == "career" )
        return zs_snapshot_pb_value( snapshot, kind, 0 );
    if ( kind == 1 ) return snapshot.best_round_kills;
    if ( kind == 2 ) return snapshot.best_round_headshots;
    if ( kind == 3 ) return snapshot.best_round_melee_kills;
    if ( kind == 4 ) return snapshot.best_round_points;
    if ( kind == 5 ) return snapshot.best_round_revives;
    if ( kind == 6 ) return snapshot.best_kpr_tenths;
    if ( kind == 7 ) return snapshot.best_ppr_tenths;
    if ( kind == 8 ) return snapshot.fastest_round;
    if ( kind == 9 ) return snapshot.points_earned;
    if ( kind == 10 ) return snapshot.kills;
    if ( kind == 11 ) return snapshot.current_round;
    return 0;
}

zs_pb_value_text( kind, value )
{
    if ( kind == 6 || kind == 7 ) return zs_tenths_text( value );
    if ( kind == 8 ) return zs_time_or_dash( value );
    return "" + value;
}

zs_career_pb_rows( snapshots )
{
    rows = [];
    for ( i = 0; i < snapshots.size; i++ )
    {
        snapshot = snapshots[i];
        any = 0;
        for ( kind = 1; kind <= 11; kind++ )
            if ( zs_snapshot_new_pb( snapshot, kind ) ) any = 1;
        if ( !any ) continue;
        if ( rows.size == 0 ) rows[rows.size] = "NEW PERSONAL BESTS";
        for ( kind = 1; kind <= 11; kind++ )
        {
            if ( !zs_snapshot_new_pb( snapshot, kind ) ) continue;
            current = zs_snapshot_current_pb( snapshot, kind );
            previous = zs_snapshot_pb_previous( snapshot, kind );
            line = "NEW PB  " + snapshot.name + "  " + zs_pb_kind_label( kind ) + " " + zs_pb_value_text( kind, current );
            if ( previous > 0 ) line = line + "  WAS " + zs_pb_value_text( kind, previous );
            else line = line + "  FIRST RECORD";
            rows[rows.size] = line;
        }
    }
    return rows;
}

zs_personal_record_rows( snapshot )
{
    rows = [];
    career = isdefined( snapshot.pb_scope ) && snapshot.pb_scope == "career";
    if ( career && !snapshot.pb_loaded )
    {
        rows[rows.size] = "ZSTATS CAREER BESTS";
        rows[rows.size] = "CAREER RECORD UNAVAILABLE";
        return rows;
    }
    title = "ZSTATS MATCH COMPLETED-ROUND BESTS";
    if ( career ) title = "ZSTATS CAREER BESTS";
    rows[rows.size] = title;
    rows[rows.size] = "MATCH COMPLETED ROUNDS  " + snapshot.completed_rounds;
    best_kills = zs_snapshot_pb_value( snapshot, 1, snapshot.best_round_kills );
    best_headshots = zs_snapshot_pb_value( snapshot, 2, snapshot.best_round_headshots );
    best_melee = zs_snapshot_pb_value( snapshot, 3, snapshot.best_round_melee_kills );
    best_points = zs_snapshot_pb_value( snapshot, 4, snapshot.best_round_points );
    best_revives = zs_snapshot_pb_value( snapshot, 5, snapshot.best_round_revives );
    if ( best_kills > 0 || best_headshots > 0 )
        rows[rows.size] = "COMBAT  KILLS " + best_kills + "   HEADSHOTS " + best_headshots;
    if ( best_melee > 0 ) rows[rows.size] = "MELEE KILLS  " + best_melee;
    if ( snapshot.score_supported && best_points > 0 )
        rows[rows.size] = "ECONOMY  POINTS EARNED " + best_points;
    if ( !snapshot.solo && best_revives > 0 )
        rows[rows.size] = "SUPPORT  REVIVES " + best_revives;
    else if ( snapshot.solo )
        rows[rows.size] = "SUPPORT  REVIVES N/A";
    best_kpr_tenths = zs_snapshot_pb_value( snapshot, 6, zs_game_over_best_average_tenths( snapshot, snapshot.kills, snapshot.best_kpr_tenths ) );
    best_ppr = "N/A";
    if ( snapshot.score_supported )
    {
        best_ppr_tenths = zs_snapshot_pb_value( snapshot, 7, zs_game_over_best_average_tenths( snapshot, snapshot.points_earned, snapshot.best_ppr_tenths ) );
        if ( best_ppr_tenths >= 0 ) best_ppr = zs_tenths_text( best_ppr_tenths );
    }
    best_kpr = "N/A";
    if ( best_kpr_tenths >= 0 ) best_kpr = zs_tenths_text( best_kpr_tenths );
    rows[rows.size] = "BEST KPR  " + best_kpr + "   BEST PPR  " + best_ppr;
    fastest = zs_snapshot_pb_value( snapshot, 8, snapshot.fastest_round );
    if ( career && fastest > 0 ) rows[rows.size] = "FASTEST ROUND  " + zs_time_or_dash( fastest );
    else if ( snapshot.fastest_round > 0 || snapshot.slowest_round > 0 )
        rows[rows.size] = "ROUND TIME  " + zs_time_or_dash( snapshot.fastest_round ) + " FAST   " + zs_time_or_dash( snapshot.slowest_round ) + " SLOW";
    if ( career )
    {
        match_earned = zs_snapshot_pb_value( snapshot, 9, snapshot.points_earned );
        match_kills = zs_snapshot_pb_value( snapshot, 10, snapshot.kills );
        highest_round = zs_snapshot_pb_value( snapshot, 11, snapshot.current_round );
        if ( snapshot.score_supported && match_earned > 0 )
            rows[rows.size] = "BEST MATCH EARNED  " + match_earned;
        if ( match_kills > 0 )
            rows[rows.size] = "BEST MATCH KILLS  " + match_kills;
        if ( highest_round > 0 )
            rows[rows.size] = "HIGHEST ROUND  " + highest_round;
    }
    return rows;
}

zs_personal_full_rows( snapshot )
{
    rows = zs_personal_summary_rows( snapshot );
    career = isdefined( snapshot.pb_scope ) && snapshot.pb_scope == "career" && snapshot.pb_loaded;
    best_kills = zs_snapshot_pb_value( snapshot, 1, snapshot.best_round_kills );
    best_headshots = zs_snapshot_pb_value( snapshot, 2, snapshot.best_round_headshots );
    best_melee = zs_snapshot_pb_value( snapshot, 3, snapshot.best_round_melee_kills );
    best_round_points = zs_snapshot_pb_value( snapshot, 4, snapshot.best_round_points );
    best_revives = zs_snapshot_pb_value( snapshot, 5, snapshot.best_round_revives );
    if ( best_kills > 0 || best_headshots > 0 )
    {
        prefix = "MATCH BESTS";
        if ( career ) prefix = "CAREER BESTS";
        rows[rows.size] = prefix + "  K " + best_kills + "   HS " + best_headshots;
    }
    if ( best_melee > 0 ) rows[rows.size] = "BEST ROUND MELEE  " + best_melee;
    if ( ( snapshot.score_supported && best_round_points > 0 ) || ( !snapshot.solo && best_revives > 0 ) )
    {
        best_points = "N/A";
        if ( snapshot.score_supported )
            best_points = "" + best_round_points;
        best_revives_text = "N/A";
        if ( !snapshot.solo ) best_revives_text = "" + best_revives;
        prefix = "MATCH BESTS";
        if ( career ) prefix = "CAREER BESTS";
        rows[rows.size] = prefix + "  PTS " + best_points + "   REV " + best_revives_text;
    }
    best_kpr_tenths = zs_snapshot_pb_value( snapshot, 6, zs_game_over_best_average_tenths( snapshot, snapshot.kills, snapshot.best_kpr_tenths ) );
    best_ppr = "N/A";
    if ( snapshot.score_supported )
    {
        best_ppr_tenths = zs_snapshot_pb_value( snapshot, 7, zs_game_over_best_average_tenths( snapshot, snapshot.points_earned, snapshot.best_ppr_tenths ) );
        if ( best_ppr_tenths >= 0 ) best_ppr = zs_tenths_text( best_ppr_tenths );
    }
    best_kpr = "N/A";
    if ( best_kpr_tenths >= 0 ) best_kpr = zs_tenths_text( best_kpr_tenths );
    rows[rows.size] = "BEST AVG  KPR " + best_kpr + "   PPR " + best_ppr;
    fastest = zs_snapshot_pb_value( snapshot, 8, snapshot.fastest_round );
    if ( career && fastest > 0 ) rows[rows.size] = "FASTEST ROUND  " + zs_time_or_dash( fastest );
    else if ( snapshot.fastest_round > 0 || snapshot.slowest_round > 0 )
        rows[rows.size] = "ROUND TIME  " + zs_time_or_dash( snapshot.fastest_round ) + " FAST   " + zs_time_or_dash( snapshot.slowest_round ) + " SLOW";
    return rows;
}

zs_show_recap_page( rows, seconds )
{
    height = 22 + rows.size * 17;
    center_y = 125;
    panel_width = 300;
    max_panel_width = 430;
    if ( self issplitscreen() )
    {
        center_y = 70;
        panel_width = 270;
        max_panel_width = 340;
    }
    // Size each page to its content rather than drawing the same wide slab
    // behind a short personal summary or an unavailable-record notice.
    for ( i = 0; i < rows.size; i++ )
    {
        preview = zs_display_text( rows[i], 64 );
        character_width = 6;
        if ( i == 0 ) character_width = 7;
        needed_width = 34 + preview.size * character_width;
        if ( needed_width > panel_width ) panel_width = needed_width;
    }
    if ( panel_width > max_panel_width ) panel_width = max_panel_width;
    row_limit = int( ( panel_width - 28 ) / 6 );
    if ( row_limit > 64 ) row_limit = 64;
    if ( self issplitscreen() && row_limit > 46 ) row_limit = 46;
    top_y = center_y - int( height / 2 );

    bg = newclienthudelem( self );
    bg.horzalign = "center";
    bg.vertalign = "middle";
    bg.alignx = "center";
    bg.aligny = "middle";
    bg.x = 0;
    bg.y = center_y;
    bg.color = ( 0.01, 0.015, 0.02 );
    bg.alpha = 0.55;
    bg.sort = 998;
    bg.foreground = 1;
    bg setshader( "white", panel_width, height );

    accent = newclienthudelem( self );
    accent.horzalign = "center";
    accent.vertalign = "middle";
    accent.alignx = "center";
    accent.aligny = "middle";
    accent.x = 0;
    accent.y = top_y;
    accent.color = ( 1, 0.35, 0.06 );
    accent.alpha = 0.9;
    accent.sort = 999;
    accent.foreground = 1;
    accent setshader( "white", panel_width, 2 );

    lines = [];
    for ( i = 0; i < rows.size; i++ )
    {
        line = newclienthudelem( self );
        line.horzalign = "center";
        line.vertalign = "middle";
        line.alignx = "left";
        line.aligny = "middle";
        line.x = 0 - int( panel_width / 2 ) + 14;
        line.y = top_y + 9 + i * 17;
        line.font = "objective";
        line.fontscale = 1.0;
        line.color = ( 0.86, 0.89, 0.92 );
        pb_line = rows[i].size >= 6 && getsubstr( rows[i], 0, 6 ) == "NEW PB";
        if ( i == 0 || pb_line )
        {
            if ( i == 0 ) line.fontscale = 1.08;
            line.color = ( 1, 0.45, 0.12 );
        }
        line.alpha = 1;
        line.sort = 1000;
        line.foreground = 1;
        line settext( zs_display_text( rows[i], row_limit ) );
        lines[i] = line;
    }

    wait seconds;
    bg fadeovertime( 0.3 );
    accent fadeovertime( 0.3 );
    bg.alpha = 0;
    accent.alpha = 0;
    for ( i = 0; i < lines.size; i++ )
    {
        lines[i] fadeovertime( 0.3 );
        lines[i].alpha = 0;
    }
    wait 0.3;
    bg destroy();
    accent destroy();
    for ( i = 0; i < lines.size; i++ )
        lines[i] destroy();
}

zs_show_game_over( first_page, second_page, seconds )
{
    pages = [];
    pages = zs_append_recap_pages( pages, first_page );
    pages = zs_append_recap_pages( pages, second_page );
    if ( pages.size == 0 )
        return;
    if ( seconds < pages.size )
        seconds = pages.size;
    base_seconds = int( seconds / pages.size );
    remainder = seconds - base_seconds * pages.size;
    for ( i = 0; i < pages.size; i++ )
    {
        page_seconds = base_seconds;
        if ( i < remainder )
            page_seconds++;
        self zs_show_recap_page( pages[i].rows, page_seconds );
    }
}

zs_append_recap_pages( pages, rows )
{
    if ( rows.size == 0 )
        return pages;
    index = 1;
    page_number = 1;
    while ( index < rows.size || page_number == 1 )
    {
        page = spawnstruct();
        page.rows = [];
        title = rows[0];
        if ( page_number > 1 )
            title += "  CONTINUED";
        page.rows[0] = title;
        while ( index < rows.size && page.rows.size < 8 )
        {
            page.rows[page.rows.size] = rows[index];
            index++;
        }
        pages[pages.size] = page;
        page_number++;
    }
    return pages;
}

zs_hide_live_hud()
{
    if ( !isdefined( self.zstats ) )
        return;
    self.zstats.hud_hidden = 1;
    if ( isdefined( self.zstats.hud_bg ) )
        self.zstats.hud_bg.alpha = 0;
    if ( isdefined( self.zstats.hud_accent ) )
        self.zstats.hud_accent.alpha = 0;
    if ( isdefined( self.zstats.hud_title ) )
        self.zstats.hud_title.alpha = 0;
    if ( isdefined( self.zstats.hud_labels ) )
    {
        for ( i = 0; i < self.zstats.hud_labels.size; i++ )
        {
            self.zstats.hud_labels[i].alpha = 0;
            self.zstats.hud_values[i].alpha = 0;
        }
    }
}

zs_release_live_hud()
{
    if ( !isdefined( self.zstats ) )
        return;

    // BO2 has a tight per-client HUD-element pool. Merely hiding the live
    // card leaves every detailed label/value allocated, which can allow the
    // recap shader through while starving all of its text rows.
    self.zstats.hud_hidden = 1;
    self zs_destroy_live_hud_elements();
}

zs_end_game_signal_watch()
{
    level waittill( "end_game" );
    level.zstats.game_over_signal = 1;
}

zs_intermission_ready()
{
    players = getplayers();
    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i].sessionstate ) && players[i].sessionstate == "intermission" )
            return 1;
    }
    return 0;
}

zs_reserve_recap_time()
{
    if ( !zs_cfg_int( "zs_game_over_report", 1 ) || !isdefined( level.zombie_vars ) )
        return;
    // Cover the custom-map readiness fallback, stock-scoreboard dwell, page
    // fades, and the configured ZStats recap itself.
    required = zs_cfg_int( "zs_recap_seconds", 20 ) + 15;
    if ( !isdefined( level.zombie_vars["zombie_intermission_time"] ) || level.zombie_vars["zombie_intermission_time"] < required )
        level.zombie_vars["zombie_intermission_time"] = required;
}

zs_freeze_ending_score()
{
    if ( !isdefined( self.zstats ) || isdefined( self.zstats.ending_score ) )
        return;

    self zs_settle_chugabud_spending( 1 );

    // Stock replaces the spendable balance during intermission. If that has
    // already happened, retain the last live sample instead.
    if ( isdefined( self.sessionstate ) && self.sessionstate == "intermission" )
    {
        self.zstats.ending_score = self.zstats.last_score;
        self.zstats.score_frozen = 1;
        return;
    }

    self zs_sample_score();
    self.zstats.ending_score = self zs_stat( "score" );
    self.zstats.score_frozen = 1;
}

zs_commit_match_career_bests()
{
    if ( !self zs_pb_scope_career() || !self.zstats.pb_loaded )
        return;
    if ( zs_score_available( self ) )
        self zs_career_pb_update( 9, self.zstats.points_earned );
    self zs_career_pb_update( 10, zs_match_value( self, "kills" ) );
    self zs_career_pb_update( 11, zs_current_round_number() );
}

zs_commit_terminal_career_averages()
{
    if ( !self zs_pb_scope_career() || !self.zstats.pb_loaded || self.zstats.round_active || self.zstats.completed_rounds <= 0 )
        return;
    rounds = zs_observed_rounds( self );
    self zs_career_pb_update( 6, zs_average_tenths( zs_match_value( self, "kills" ), rounds ) );
    if ( zs_score_available( self ) )
        self zs_career_pb_update( 7, zs_average_tenths( self.zstats.points_earned, rounds ) );
}

zs_game_over_watch()
{
    while ( !level.zstats.game_over_signal && ( !isdefined( level.intermission ) || !level.intermission ) )
        wait 0.05;

    zs_finalize_pending_round();
    zs_reserve_recap_time();
    seconds = zs_cfg_int( "zs_recap_seconds", 20 );
    players = getplayers();
    recipients = zs_tracked_players( players );
    for ( i = 0; i < recipients.size; i++ )
    {
        recipients[i] zs_freeze_ending_score();
        recipients[i] zs_commit_match_career_bests();
        recipients[i] zs_commit_terminal_career_averages();
    }
    snapshots = zs_collect_snapshots( recipients );
    level notify( "zstats_match_finalizing" );
    wait 0.05;
    level.zstats.accepting_values = 0;
    for ( i = 0; i < recipients.size; i++ )
        recipients[i] zs_release_live_hud();

    if ( !zs_cfg_int( "zs_game_over_report", 1 ) )
        return;

    waited = 0;
    intermission_seen = zs_intermission_ready();
    while ( !intermission_seen && waited < 10 )
    {
        wait 0.05;
        waited += 0.05;
        intermission_seen = zs_intermission_ready();
    }
    // Let the stock scoreboard own the first phase. Maps which never enter
    // stock intermission already spent the full fallback and start immediately.
    if ( intermission_seen && waited < 10 )
        wait 2.5;
    else
        wait 0.1;
    players = getplayers();
    recipients = zs_tracked_players( players );
    if ( recipients.size == 0 )
        return;
    snapshots = zs_merge_snapshots( snapshots, recipients );
    if ( snapshots.size == 0 )
        return;
    awards = zs_game_over_rows( snapshots );
    career_rows = zs_career_pb_rows( snapshots );
    for ( i = 0; i < career_rows.size; i++ )
        awards[awards.size] = career_rows[i];
    for ( i = 0; i < recipients.size; i++ )
    {
        local_snapshot = zs_find_snapshot( snapshots, recipients[i].zstats.player_id );
        if ( !isdefined( local_snapshot ) )
            continue;
        first_page = awards;
        second_page = zs_personal_full_rows( local_snapshot );
        if ( snapshots.size == 1 )
        {
            first_page = zs_personal_summary_rows( local_snapshot );
            second_page = zs_personal_record_rows( local_snapshot );
        }
        recipients[i] thread zs_show_game_over( first_page, second_page, seconds );
    }
}

zs_build_watermark()
{
    level endon( "end_game" );
    stamp = zs_build();
    if ( stamp == "" )
        return;

    while ( !zs_numeric( level.round_number ) )
        wait 0.5;

    e = createserverfontstring( "objective", 1.1 );
    e setpoint( "TOPRIGHT", "TOPRIGHT", 0, 62 );
    e.color = ( 1, 0.45, 0.12 );
    e.sort = 1000;
    e.foreground = 1;
    e.alpha = 0.7;
    e settext( stamp );
    level.zstats_build_hud = e;
}

zs_build()
{
    // ZS_BUILD_BEGIN
    return "";
    // ZS_BUILD_END
}
