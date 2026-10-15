// ZTWEAKS T7 v1.4
// Compatibility-first Zombies tweaks. Inactive live-boundary hooks preserve stock behavior.

#include scripts\shared\callbacks_shared;
#include scripts\shared\system_shared;
#include scripts\shared\flag_shared;
#include scripts\shared\aat_shared;
#include scripts\shared\clientfield_shared;
#include scripts\shared\laststand_shared;
#include scripts\shared\util_shared;
#include scripts\zm\_zm;
#include scripts\zm\_zm_audio;
#include scripts\zm\_zm_bgb;
#include scripts\zm\_zm_blockers;
#include scripts\zm\_zm_equipment;
#include scripts\zm\_zm_laststand;
#include scripts\zm\_zm_magicbox;
#include scripts\zm\_zm_power;
#include scripts\zm\_zm_powerups;
#include scripts\zm\_zm_score;
#include scripts\zm\_zm_powerup_double_points;
#include scripts\zm\_zm_powerup_insta_kill;
#include scripts\zm\_zm_perks;
#include scripts\zm\_zm_pers_upgrades_functions;
#include scripts\zm\_zm_utility;
#include scripts\zm\_zm_weapons;
#include scripts\zm\_zm_zonemgr;

#precache( "eventstring", "ztCharProbe" );
#precache( "eventstring", "ztCharCoopPreference" );
#precache( "eventstring", "ztCompatPacket" );
#precache( "eventstring", "ztCompatPacket2" );
#precache( "eventstring", "ztLocalizedNotice" );

#namespace ztweaks;

autoexec __init__sytem__()
{
    system::register( "ztweaks", ::__init__, undefined, undefined );
}

__init__()
{
    callback::on_start_gametype( ::init );
    callback::on_connecting( ::on_connecting );
    callback::on_connect( ::init );
    callback::on_connect( ::on_connected );
    callback::on_spawned( ::on_spawned );
}

init()
{
    if ( zt_true( level.zt_loaded ) )
        return;

    level.zt_loaded = 1;
    level.zt = spawnstruct();
    level.zt.config = spawnstruct();
    level.zt.features = [];
    level.zt.feature_messages = [];
    level.zt.powerup_effect_state = [];
    level.zt.powerup_filter_prev = [];
    level.zt.powerup_filter_owned = [];
    level.zt.powerup_filter_yielded = [];
    level.zt.powerup_filter_any_yielded = 0;
    level.zt.powerup_exact_generation = [];
    level.zt.powerup_exact_wrapped = [];
    level.zt.powerup_grab_prev = [];
    level.zt.mods = [];
    level.zt.report_epoch = randomint( 1023 ) + 1;
    level.zt.report_names = zt_report_names();

    zt_load_config();
    zt_register_self();
    level thread zt_build_watermark();
    // Diagnostic only: measure remote storage/response ordering without
    // changing stock cast selection. Never enabled by ordinary settings.
    if ( getdvarint( "zt_character_probe" ) == 1 )
    {
        probe_sequence = getdvarint( "zt_char_probe_sequence" ) + 1;
        setdvar( "zt_char_probe_sequence", "" + probe_sequence );
        level.zt_character_probe_run = "" + probe_sequence + "_" + randomint( 1000000000 );
        setdvar( "zt_char_probe_run", level.zt_character_probe_run );
        setdvar( "zt_char_probe_lua_stage", "" );
        setdvar( "zt_char_probe_movie_stage", "" );
        setdvar( "zt_char_probe_poll_ready", "" );
        setdvar( "zt_char_probe_poll_sent", "" );
        setdvar( "zt_char_probe_defer_state", "" );
        level thread zt_character_probe_start();
        level thread zt_character_probe_movie_watch();
    }
    if ( !level.zt.config.enabled )
        return;

    zt_feature( "perk_limit", "inherit", "" );
    zt_feature( "auto_restart", "inherit", "" );
    zt_feature( "starting_round", "inherit", "" );
    zt_feature( "starting_points", "inherit", "" );
    zt_feature( "game_start_delay", "inherit", "" );
    zt_feature( "player_health", "inherit", "" );
    zt_feature( "zombie_health", "inherit", "" );
    zt_feature( "max_grenades", "inherit", "" );
    zt_feature( "max_equipment", "inherit", "" );
    zt_feature( "starting_weapon", "inherit", "" );
    zt_feature( "secondary_starting_weapon", "inherit", "" );
    zt_feature( "random_starting_perks", "inherit", "" );
    zt_feature( "starting_grenade", "inherit", "" );
    zt_feature( "starting_equipment", "inherit", "" );
    zt_feature( "start_all_perks", "inherit", "" );
    zt_feature( "player_speed", "inherit", "" );
    zt_feature( "zombie_speed", "inherit", "" );
    zt_feature( "headshots_only", "inherit", "" );
    zt_feature( "zombies_per_round", "inherit", "" );
    zt_feature( "round_delay", "inherit", "" );
    zt_feature( "zombie_spawn_rate", "inherit", "" );
    zt_feature( "powerup_ground_time", "inherit", "" );
    zt_feature( "powerup_effect_time", "inherit", "" );
    zt_feature( "powerup_drop_rate", "inherit", "" );
    zt_feature( "powerup_max_per_round", "inherit", "" );
    zt_feature( "start_power_on", "inherit", "" );
    zt_feature( "start_doors_open", "inherit", "" );
    zt_feature( "gobblegum_uses", "inherit", "" );
    zt_feature( "gobblegum_time", "inherit", "" );
    zt_feature( "gobblegum_rounds", "inherit", "" );
    zt_new_features_init();

    if ( level.zt.config.perk_limit != 0 || level.zt.config.challenge_no_perks )
        level thread zt_perk_limit_install();

    if ( level.zt.config.perk_price_multiplier >= 0 )
        level thread zt_perk_price_install();
    if ( level.zt.config.wunderfizz_price_multiplier >= 0 )
        level thread zt_wunderfizz_price_install();

    if ( level.zt.config.health_regen_delay > 0 )
        level thread zt_regen_delay_install();

    if ( level.zt.config.death_points_retained >= 0 )
        level thread zt_death_points_install();

    level thread zt_round_bonus_install();

    if ( zt_has_match_tweaks() )
        level thread zt_match_tweaks_install();

    // These passive boundary hooks are required so an in-game setting change
    // can take effect at NEXT ROUND / NEXT DROP / NEXT GUM. Each one preserves
    // stock behavior while its setting remains at GAME DEFAULT.
    level thread zt_zombies_per_round_install();

    if ( zt_has_pacing_tweaks() )
        level thread zt_pacing_install();

    level thread zt_powerup_controls_install();
    if ( level.zt.config.disable_stock_aat )
        level thread zt_disable_stock_aat_install();

    if ( level.zt.config.start_power_on )
        level thread zt_start_power_install();

    if ( level.zt.config.start_doors_open )
        level thread zt_start_doors_install();

    level thread zt_gobblegum_limits_install();

    // The player-damage callback is a passive boundary adapter. It must exist
    // before Spawn Protection is enabled from the in-game menu.
    level thread zt_damage_tweaks_install();
    if ( level.zt.config.fast_barrier_rebuild ) level thread zt_fast_barrier_rebuild_install();

    if ( zt_has_box_tweaks() )
        level thread zt_box_tweaks_install();

    if ( level.zt.config.trap_price_multiplier >= 0 )
        level thread zt_trap_price_install();

    // Revive and bleed-out time are NEXT DOWN settings, so their lightweight
    // owners must exist even when the match began at GAME DEFAULT.
    level thread zt_down_tweaks_install();

    level thread zt_point_gain_install();
    level thread zt_challenges_install();
    if ( level.zt.config.challenge_one_weapon_slot )
        level thread zt_one_weapon_slot_install();

    // Keep an independent player watcher alive instead of relying only on the
    // shared callback list. This starts before ordinary first spawn when the
    // stock lifecycle is available, and also discovers late T7x clients.
    level thread zt_player_watch();

    // Player Health is a NEXT SPAWN setting. Keep its shared-base owner
    // passive at GAME DEFAULT so enabling it after match start still composes
    // with late map/perk base-health publications after the next spawn.
    level thread zt_match_value_owner_watch();

}

on_spawned()
{
    init();

    if ( getdvarint( "zt_character_probe" ) == 1 )
    {
        line = "ZT_CHAR_PROBE|port=t7|event=spawned|ms=" + gettime() + "|player=" + self.name + "|index_set=" + isdefined( self.characterindex );
        logprint( line + "\n" );
        /# print( line ); #/
        self zt_character_probe_loadout_snapshot( "spawned" );
        self thread zt_character_probe_summary();
    }

    if ( !level.zt.config.enabled )
        return;

    if ( !zt_true( self.zt_report_started ) )
    {
        self.zt_report_started = 1;
        self thread zt_report_sync_player();
    }
    self zt_start_ready_listener();

    // T7x can attach the mod after the level watcher has already polled this
    // spawn. Start a one-shot catch-up watcher for that case. The per-player
    // guard prevents the callback and poller from applying random perks or
    // starting inventory twice.
    if ( !zt_true( self.zt_player_watch ) )
    {
        self.zt_player_watch = 1;
        self thread zt_player_spawn_watch( 1 );
        // This catch-up path can claim the player before zt_player_watch()
        // reaches its poll. Both paths must launch the saved preference once.
        if ( zt_character_preference_requested() )
            self thread zt_character_preference_apply();
        if ( getdvarint( "zt_character_coop_probe" ) == 1 || zt_character_coop_apply_enabled() )
            self thread zt_character_coop_probe_request();
    }
}

on_connected()
{
    // Start before the gameplay HUD can acknowledge a slow remote load.
    // on_spawned() repeats this guarded call for late-attached runtimes.
    if ( isdefined( level.zt ) && level.zt.config.enabled )
        self zt_start_ready_listener();
    // Request the diagnostic value at the earliest per-player callback we
    // already own, rather than waiting for the level poll near first spawn.
    // This remains opt-in and does not change character assignment.
    if ( getdvarint( "zt_character_probe" ) == 1 )
        self zt_character_probe_request( "connect" );
}

on_connecting()
{
    // Stock invokes this before the player's later connected/begin path.
    // Probe whether that lead time can carry a client-local preference;
    // do not wait here or change the map's character allocation.
    if ( getdvarint( "zt_character_probe" ) == 1 && isdefined( level.zt_character_probe_run ) )
        self zt_character_probe_request( "connecting" );
}

zt_character_probe_start()
{
    level endon( #"end_game" );
    line = "ZT_CHAR_PROBE|port=t7|event=init|run=" + level.zt_character_probe_run + "|ms=" + gettime() + "|map=" + getdvarstring( "mapname" ) + "|mode=" + getdvarstring( "g_gametype" );
    logprint( line + "\n" );
    /# print( line ); #/

    elapsed = 0;
    while ( !isdefined( level.givecustomcharacters ) && elapsed < 8 )
    {
        wait 0.05;
        elapsed += 0.05;
    }
    if ( isdefined( level.givecustomcharacters ) )
    {
        level.zt_character_probe_previous = level.givecustomcharacters;
        level.givecustomcharacters = ::zt_character_probe_callback;
        line = "ZT_CHAR_PROBE|port=t7|event=callback_hooked|ms=" + gettime();
        logprint( line + "\n" );
        /# print( line ); #/
    }
    else
    {
        line = "ZT_CHAR_PROBE|port=t7|event=callback_missing|ms=" + gettime();
        logprint( line + "\n" );
        /# print( line ); #/
    }

    elapsed = 0;
    while ( elapsed < 12 )
    {
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            player = players[i];
            if ( !zt_true( player.zt_character_probe_requested ) )
                player zt_character_probe_request( "poll" );
        }
        wait 0.05;
        elapsed += 0.05;
    }
}

zt_character_probe_movie_watch()
{
    level endon( #"end_game" );
    previous = "";
    for ( sample = 0; sample < 600; sample++ )
    {
        marker = getdvarstring( "zt_char_probe_movie_stage" );
        if ( marker != "" && marker != previous )
        {
            line = "ZT_CHAR_PROBE|port=t7|event=movie_state|run=" + level.zt_character_probe_run + "|ms=" + gettime() + "|marker=" + marker;
            logprint( line + "\n" );
            /# print( line ); #/
            previous = marker;
        }
        wait 0.25;
    }
}

zt_character_probe_request( source )
{
    if ( zt_true( self.zt_character_probe_requested ) )
        return;
    self.zt_character_probe_requested = 1;
    self.zt_character_probe_request_ms = gettime();
    self.zt_character_probe_request_source = source;
    self.zt_character_probe_request_run = level.zt_character_probe_run;
    self thread zt_character_probe_response();
    self thread zt_character_probe_timeout();
    self thread zt_character_probe_poll_ready();
    player_name = self.name;
    if ( !isdefined( player_name ) || !isstring( player_name ) )
        player_name = "PENDING";
    line = "ZT_CHAR_PROBE|port=t7|event=request|run=" + self.zt_character_probe_request_run + "|source=" + source + "|ms=" + self.zt_character_probe_request_ms + "|player=" + player_name;
    logprint( line + "\n" );
    /# print( line ); #/
    self thread zt_character_probe_notify_loop();
}

zt_character_probe_poll_ready()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    // Let the response watcher enter waittill before enabling an optional
    // loading-menu push. This separate thread never delays stock connecting.
    wait 0.05;
    if ( !isdefined( self ) || !isplayer( self ) ||
        self.zt_character_probe_request_run != level.zt_character_probe_run )
        return;
    setdvar( "zt_char_probe_poll_ready", level.zt_character_probe_run );
    line = "ZT_CHAR_PROBE|port=t7|event=poll_ready|run=" + level.zt_character_probe_run + "|ms=" + gettime();
    logprint( line + "\n" );
    /# print( line ); #/
    // Stock codecallback_menuresponse creates its queue pump on the first
    // response and immediately signals it. If that wake precedes the pump's
    // waittill, the response remains queued. One delayed wake of a proven
    // nonempty stock queue is diagnostic-only and never edits its entries.
    for ( sample = 0; sample < 12; sample++ )
    {
        if ( getdvarstring( "zt_char_probe_poll_sent" ) == level.zt_character_probe_run )
            break;
        wait 0.025;
    }
    // Give stock's just-created queue worker one scheduler turn to enter
    // its wait before waking a pending response.
    wait 0.05;
    if ( !isdefined( self ) || !isplayer( self ) ||
        self.zt_character_probe_request_run != level.zt_character_probe_run )
        return;
    pending = 0;
    if ( isdefined( level.menuresponsequeue ) )
        pending = level.menuresponsequeue.size;
    self iprintlnbold( "ZT CHAR QUEUE: pending=" + pending + "; reply=" + zt_true( self.zt_character_probe_reply_ms ) );
    if ( pending > 0 && getdvarstring( "zt_char_probe_poll_sent" ) == level.zt_character_probe_run &&
        !isdefined( self.zt_character_probe_reply_ms ) )
    {
        level notify( #"menuresponse_queue" );
        line = "ZT_CHAR_PROBE|port=t7|event=queue_wake|run=" + level.zt_character_probe_run + "|ms=" + gettime() + "|pending=" + pending;
        logprint( line + "\n" );
        /# print( line ); #/
    }
}

zt_character_probe_notify_loop()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    // LUINotifyEvent is a reliable server command. Wait for the HUD listener
    // marker, then emit at most one request; retrying at 10 Hz can overload
    // the command channel and causes duplicate Lua menu responses.
    prefix = level.zt_character_probe_run + ":";
    // on_connecting can precede HUD creation by the entire loading movie.
    // This is only a local readiness poll; no command is sent until HUD is
    // observed, and at most one command is ever emitted for this request.
    for ( attempt = 0; attempt < 480; attempt++ )
    {
        if ( !isdefined( self ) || !isplayer( self ) || isdefined( self.zt_character_probe_reply_ms ) )
            return;
        stage = getdvarstring( "zt_char_probe_lua_stage" );
        if ( stage.size >= prefix.size && getsubstr( stage, 0, prefix.size ) == prefix )
        {
            self.zt_character_probe_notify_ms = gettime();
            self LUINotifyEvent( &"ztCharProbe", 1, 2 );
            line = "ZT_CHAR_PROBE|port=t7|event=notify|run=" + level.zt_character_probe_run + "|ms=" + self.zt_character_probe_notify_ms + "|stage=" + stage;
            logprint( line + "\n" );
            /# print( line ); #/
            return;
        }
        wait 0.25;
    }
}

zt_character_probe_timeout()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    // An early on_connecting request may wait through loading before HUD
    // exists. Only start the reply deadline after the actual notification.
    for ( sample = 0; sample < 480; sample++ )
    {
        if ( !isdefined( self ) || !isplayer( self ) || isdefined( self.zt_character_probe_reply_ms ) )
            return;
        if ( isdefined( self.zt_character_probe_notify_ms ) )
            break;
        wait 0.25;
    }
    if ( !isdefined( self ) || !isplayer( self ) || !isdefined( self.zt_character_probe_notify_ms ) )
        return;
    wait 2;
    if ( !isdefined( self ) || !isplayer( self ) )
        return;
    if ( !isdefined( self.zt_character_probe_reply_ms ) )
    {
        line = "ZT_CHAR_PROBE|port=t7|event=timeout|ms=" + gettime() + "|player=" + self.name;
        logprint( line + "\n" );
        /# print( line ); #/
    }
}

zt_character_probe_response()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    while ( 1 )
    {
        // The public BO3 mod compiler emits the gameplay menu response
        // listener from a plain event string. T7/T7x may forward a different
        // first menu argument, so identify our reply by its unique payload.
        self waittill( "menuresponse", menu, response );
        if ( !isdefined( self ) || !isplayer( self ) )
            return;
        if ( !isdefined( response ) || !isstring( response ) || response.size < 14 ||
            getsubstr( response, 0, 14 ) != "zt_char_probe|" )
            continue;
        parts = strtok( response, "|" );
        if ( parts.size < 5 )
            continue;
        if ( parts[1] != self.zt_character_probe_request_run )
        {
            self iprintlnbold( "ZT CHAR STALE: reply run=" + parts[1] + "; current=" + self.zt_character_probe_request_run );
            continue;
        }
        self.zt_character_probe_reply_ms = gettime();
        self.zt_character_probe_reply_value = parts[2];
        reply_source = "LEGACY";
        if ( parts.size > 5 )
            reply_source = parts[5];
        line = "ZT_CHAR_PROBE|port=t7|event=response|run=" + parts[1] + "|ms=" + self.zt_character_probe_reply_ms + "|player=" + self.name + "|value=" + self.zt_character_probe_reply_value + "|movie_event=" + parts[3] + "|movie_send=" + parts[4] + "|source=" + reply_source;
        logprint( line + "\n" );
        /# print( line ); #/
        callback_delta = "NO CAST";
        if ( isdefined( self.zt_character_probe_callback_ms ) )
            callback_delta = "" + ( self.zt_character_probe_reply_ms - self.zt_character_probe_callback_ms ) + "ms";
        request_delta = "UNKNOWN";
        if ( isdefined( self.zt_character_probe_request_ms ) )
            request_delta = "" + ( self.zt_character_probe_reply_ms - self.zt_character_probe_request_ms ) + "ms";
        if ( isdefined( self.zt_character_probe_callback_ms ) )
        {
            self iprintlnbold( "ZT CHAR REPLY: value=" + self.zt_character_probe_reply_value + "; cast delta=" + callback_delta + "; request delta=" + request_delta );
            self iprintlnbold( "ZT CHAR MOVIE REPLY: event=" + parts[3] + "; send=" + parts[4] + "; source=" + reply_source + "; latest=" + getdvarstring( "zt_char_probe_movie_stage" ) );
        }
        return;
    }
}

zt_character_probe_loadout_snapshot( stage )
{
    // Probe a second, genuinely player-addressed carrier without modifying
    // the stock character allocator. Lua's offline-loadout format marker is
    // class 0 / primaryattachment5; the existing saved test value is class 1
    // / primaryattachment6. Reading both distinguishes that exact backing
    // record from an unrelated gameplay attachment that happens to equal 2.
    marker = self getloadoutitem( 0, "primaryattachment5" );
    sample = self getloadoutitem( 1, "primaryattachment6" );
    marker_text = "UNDEFINED";
    sample_text = "UNDEFINED";
    if ( isdefined( marker ) )
        marker_text = "" + marker;
    if ( isdefined( sample ) )
        sample_text = "" + sample;
    line = "ZT_CHAR_PROBE|port=t7|event=direct_loadout|run=" + level.zt_character_probe_run + "|ms=" + gettime() + "|stage=" + stage + "|player=" + self.name + "|marker=" + marker_text + "|slot2=" + sample_text;
    logprint( line + "\n" );
    /# print( line ); #/
    self iprintlnbold( "ZT CHAR DIRECT: " + stage + "; marker=" + marker_text + "; slot2=" + sample_text );
}

zt_character_probe_callback()
{
    // Only the first cast is relevant to the saved preference. Respawn and
    // hot-join callbacks must never inherit this diagnostic delay.
    if ( zt_true( self.zt_character_probe_callback_seen ) )
    {
        self [[ level.zt_character_probe_previous ]]();
        return;
    }
    replied = isdefined( self.zt_character_probe_reply_ms );
    self.zt_character_probe_callback_seen = 1;
    self.zt_character_probe_callback_ms = gettime();
    self.zt_character_probe_stage_at_cast = getdvarstring( "zt_char_probe_lua_stage" );
    self.zt_character_probe_movie_at_cast = getdvarstring( "zt_char_probe_movie_stage" );
    self.zt_character_probe_frontend_at_cast = getdvarstring( "zt_char_probe_frontend_slot2" );
    self.zt_character_probe_queue_at_cast = 0;
    if ( isdefined( level.menuresponsequeue ) )
        self.zt_character_probe_queue_at_cast = level.menuresponsequeue.size;
    self.zt_character_probe_before = replied;
    self zt_character_probe_loadout_snapshot( "first_callback" );
    line = "ZT_CHAR_PROBE|port=t7|event=first_callback|ms=" + self.zt_character_probe_callback_ms + "|player=" + self.name + "|response_before=" + replied + "|lua_stage=" + self.zt_character_probe_stage_at_cast + "|frontend_slot2=" + self.zt_character_probe_frontend_at_cast + "|queue_depth=" + self.zt_character_probe_queue_at_cast + "|prior_index=" + isdefined( self.characterindex );
    logprint( line + "\n" );
    self iprintlnbold( "ZT CHAR FRONTEND: " + self.zt_character_probe_frontend_at_cast );
    /# print( line ); #/
    if ( getdvarint( "zt_character_delay_probe" ) == 1 )
    {
        // This test deliberately changes no character state. Yield only this
        // player's first spawn script, and always release it by the deadline.
        delay_start_ms = gettime();
        setdvar( "zt_char_probe_defer_state", level.zt_character_probe_run + ":ACTIVE" );
        line = "ZT_CHAR_PROBE|port=t7|event=defer_start|run=" + level.zt_character_probe_run + "|ms=" + delay_start_ms + "|player=" + self.name + "|reply_before=" + replied + "|movie=" + self.zt_character_probe_movie_at_cast;
        logprint( line + "\n" );
        /# print( line ); #/
        while ( !isdefined( self.zt_character_probe_reply_ms ) && gettime() - delay_start_ms < 10000 )
        {
            wait 0.05;
            if ( !isdefined( self ) || !isplayer( self ) )
            {
                setdvar( "zt_char_probe_defer_state", level.zt_character_probe_run + ":DONE" );
                return;
            }
        }
        setdvar( "zt_char_probe_defer_state", level.zt_character_probe_run + ":DONE" );
        delay_result = "TIMEOUT";
        delay_value = "NO REPLY";
        if ( isdefined( self.zt_character_probe_reply_ms ) )
        {
            delay_result = "REPLY";
            delay_value = self.zt_character_probe_reply_value;
        }
        delay_elapsed = gettime() - delay_start_ms;
        line = "ZT_CHAR_PROBE|port=t7|event=defer_end|run=" + level.zt_character_probe_run + "|ms=" + gettime() + "|player=" + self.name + "|result=" + delay_result + "|elapsed_ms=" + delay_elapsed + "|value=" + delay_value + "|movie=" + getdvarstring( "zt_char_probe_movie_stage" );
        logprint( line + "\n" );
        /# print( line ); #/
        self iprintlnbold( "ZT CHAR DEFER: " + delay_result + " after " + delay_elapsed + "ms; Lua=" + getdvarstring( "zt_char_probe_lua_stage" ) + "; movie=" + getdvarstring( "zt_char_probe_movie_stage" ) );
    }
    self [[ level.zt_character_probe_previous ]]();
}

zt_character_probe_summary()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    wait 2;
    if ( !isdefined( self ) || !isplayer( self ) )
        return;
    value = "NO REPLY";
    if ( isdefined( self.zt_character_probe_reply_value ) )
        value = self.zt_character_probe_reply_value;
    lua_stage = getdvarstring( "zt_char_probe_lua_stage" );
    if ( lua_stage == "" )
        lua_stage = "NOT SEEN";
    stage_at_cast = self.zt_character_probe_stage_at_cast;
    if ( !isdefined( stage_at_cast ) || stage_at_cast == "" )
        stage_at_cast = "NOT SEEN";
    request_source = self.zt_character_probe_request_source;
    if ( !isdefined( request_source ) )
        request_source = "NONE";
    self iprintlnbold( "ZT CHAR TIMING: Lua at cast=" + stage_at_cast + "; request=" + request_source + "; queue=" + self.zt_character_probe_queue_at_cast );
    movie_at_cast = self.zt_character_probe_movie_at_cast;
    if ( !isdefined( movie_at_cast ) || movie_at_cast == "" )
        movie_at_cast = "NOT SEEN";
    movie_now = getdvarstring( "zt_char_probe_movie_stage" );
    if ( movie_now == "" )
        movie_now = "NOT SEEN";
    self iprintlnbold( "ZT CHAR MOVIE: run=" + level.zt_character_probe_run + "; cast=" + movie_at_cast + "; now=" + movie_now );
    if ( !zt_true( self.zt_character_probe_callback_seen ) )
        self iprintlnbold( "ZT CHAR PROBE: callback not observed; value=" + value + "; lua=" + lua_stage );
    else if ( zt_true( self.zt_character_probe_before ) )
        self iprintlnbold( "ZT CHAR PROBE: reply BEFORE cast; value=" + value + "; lua=" + lua_stage );
    else
        self iprintlnbold( "ZT CHAR PROBE: reply LATE/missing; value=" + value + "; lua=" + lua_stage );
}

zt_true( value )
{
    return isdefined( value ) && value;
}

zt_cfg_int( name, def )
{
    if ( getdvarstring( name ) == "" )
        setdvar( name, "" + def );
    return int( getdvarstring( name ) );
}

zt_cfg_string( name, def )
{
    if ( getdvarstring( name ) == "" )
        setdvar( name, def );
    return getdvarstring( name );
}

zt_random_zombie_health_percent()
{
    values = [];
    values[0] = 25;
    values[1] = 50;
    values[2] = 75;
    values[3] = 100;
    values[4] = 150;
    values[5] = 200;
    values[6] = 300;
    values[7] = 500;
    return values[randomint( values.size )];
}

zt_random_zombie_speed_percent()
{
    values = [];
    values[0] = 50;
    values[1] = 75;
    values[2] = 100;
    values[3] = 125;
    values[4] = 150;
    values[5] = 200;
    values[6] = 300;
    return values[randomint( values.size )];
}

zt_load_config()
{
    level.zt.config.enabled = zt_cfg_int( "zt_enabled", 1 );
    level.zt.config.perk_limit = zt_cfg_int( "zt_perk_limit", 0 );
    level.zt.config.perk_price_multiplier = zt_cfg_int( "zt_perk_price_multiplier", -1 );
    level.zt.config.wunderfizz_price_multiplier = zt_cfg_int( "zt_wunderfizz_price_multiplier", -1 );
    level.zt.config.health_regen_delay = zt_cfg_int( "zt_health_regen_delay", 0 );
    level.zt.config.round_bonus = zt_cfg_int( "zt_round_bonus", 0 );
    level.zt.config.max_ammo_reload = zt_cfg_int( "zt_max_ammo_reload", 0 );
    level.zt.config.disable_stock_aat = zt_cfg_int( "zt_disable_stock_aat", 0 );
    level.zt.config.death_points_retained = zt_cfg_int( "zt_death_points_retained", -1 );
    level.zt.config.auto_restart = zt_cfg_int( "zt_auto_restart", 0 );
    level.zt.config.starting_round = zt_cfg_int( "zt_starting_round", 0 );
    level.zt.config.starting_points = zt_cfg_int( "zt_starting_points", 0 );
    level.zt.config.game_start_delay = zt_cfg_int( "zt_game_start_delay", -1 );
    level.zt.config.player_health = zt_cfg_int( "zt_player_health", 0 );
    level.zt.config.zombie_health = zt_cfg_int( "zt_zombie_health", 0 );
    level.zt.config.zombie_damage = zt_cfg_int( "zt_zombie_damage", 0 );
    level.zt.config.max_grenades = zt_cfg_int( "zt_max_grenades", 0 );
    level.zt.config.max_equipment = zt_cfg_int( "zt_max_equipment", 0 );
    level.zt.config.starting_weapon = zt_cfg_string( "zt_starting_weapon", "default" );
    level.zt.config.secondary_starting_weapon = zt_cfg_string( "zt_secondary_starting_weapon", "default" );
    level.zt.config.random_starting_perks = zt_cfg_int( "zt_random_starting_perks", 0 );
    level.zt.config.starting_grenade = zt_cfg_string( "zt_starting_grenade", "default" );
    level.zt.config.starting_grenade_count = zt_cfg_int( "zt_starting_grenade_count", 0 );
    level.zt.config.starting_equipment = zt_cfg_string( "zt_starting_equipment", "default" );
    level.zt.config.starting_equipment_count = zt_cfg_int( "zt_starting_equipment_count", 0 );
    level.zt.config.start_all_perks = zt_cfg_int( "zt_start_all_perks", 0 );
    level.zt.config.player_speed = zt_cfg_int( "zt_player_speed", 0 );
    level.zt.config.zombie_speed = zt_cfg_int( "zt_zombie_speed", 0 );
    level.zt.config.headshots_only = zt_cfg_int( "zt_headshots_only", 0 );
    level.zt.config.zombies_per_round = zt_cfg_int( "zt_zombies_per_round", 0 );
    level.zt.config.round_delay = zt_cfg_int( "zt_round_delay", -1 );
    level.zt.config.zombie_spawn_rate = zt_cfg_int( "zt_zombie_spawn_rate", 0 );
    level.zt.config.powerup_ground_time = zt_cfg_int( "zt_powerup_ground_time", 0 );
    level.zt.config.powerup_effect_time = zt_cfg_int( "zt_powerup_effect_time", 0 );
    level.zt.config.powerup_drop_rate = zt_cfg_int( "zt_powerup_drop_rate", 0 );
    level.zt.config.powerup_max_per_round = zt_cfg_int( "zt_powerup_max_per_round", 0 );
    level.zt.config.disable_nuke_drops = zt_cfg_int( "zt_disable_nuke_drops", 0 );
    level.zt.config.disable_max_ammo_drops = zt_cfg_int( "zt_disable_max_ammo_drops", 0 );
    level.zt.config.disable_insta_kill_drops = zt_cfg_int( "zt_disable_insta_kill_drops", 0 );
    level.zt.config.disable_double_points_drops = zt_cfg_int( "zt_disable_double_points_drops", 0 );
    level.zt.config.disable_carpenter_drops = zt_cfg_int( "zt_disable_carpenter_drops", 0 );
    level.zt.config.disable_fire_sale_drops = zt_cfg_int( "zt_disable_fire_sale_drops", 0 );
    level.zt.config.start_power_on = zt_cfg_int( "zt_start_power_on", 0 );
    level.zt.config.start_doors_open = zt_cfg_int( "zt_start_doors_open", 0 );
    level.zt.config.gobblegum_uses = zt_cfg_int( "zt_gobblegum_uses", 0 );
    level.zt.config.gobblegum_time = zt_cfg_int( "zt_gobblegum_time", 0 );
    level.zt.config.gobblegum_rounds = zt_cfg_int( "zt_gobblegum_rounds", 0 );
    level.zt.config.point_gain = zt_cfg_int( "zt_point_gain", 0 );
    level.zt.config.starting_ammo = zt_cfg_int( "zt_starting_ammo", 0 );
    level.zt.config.reserve_ammo = zt_cfg_int( "zt_reserve_ammo", 0 );
    level.zt.config.starting_weapon_upgraded = zt_cfg_string( "zt_starting_weapon_upgraded", "default" );
    level.zt.config.starting_weapon_aat = zt_cfg_string( "zt_starting_weapon_aat", "default" );
    level.zt.config.weapon_damage = zt_cfg_int( "zt_weapon_damage", 0 );
    level.zt.config.melee_damage = zt_cfg_int( "zt_melee_damage", 0 );
    level.zt.config.challenge_rising_damage = zt_cfg_int( "zt_challenge_rising_damage", 0 );
    level.zt.config.pap_damage_multiplier = zt_cfg_int( "zt_pap_damage_multiplier", 0 );
    level.zt.config.experimental_tweaks = zt_cfg_int( "zt_experimental_tweaks", 0 );
    level.zt.config.fast_barrier_rebuild = zt_cfg_int( "zt_fast_barrier_rebuild", 0 );
    level.zt.config.no_explosive_self_damage = zt_cfg_int( "zt_no_explosive_self_damage", 0 );
    level.zt.config.fall_damage = zt_cfg_int( "zt_fall_damage", 0 );
    level.zt.config.box_price_multiplier = zt_cfg_int( "zt_box_price_multiplier", -1 );
    level.zt.config.fire_sale_box_price = zt_cfg_int( "zt_fire_sale_box_price", -1 );
    level.zt.config.teddy_bear_chance = zt_cfg_int( "zt_teddy_chance", -1 );
    level.zt.config.box_no_repeat = zt_cfg_int( "zt_box_no_repeat", 0 );
    level.zt.config.trap_price_multiplier = zt_cfg_int( "zt_trap_price_multiplier", -1 );
    level.zt.config.box_quality = zt_cfg_string( "zt_box_quality", "default" );
    level.zt.config.box_lock = zt_cfg_int( "zt_box_lock", 0 );
    level.zt.config.powerup_stacking = zt_cfg_string( "zt_powerup_stacking", "default" );
    level.zt.config.down_limit = zt_cfg_int( "zt_down_limit", 0 );
    level.zt.config.revive_time = zt_cfg_int( "zt_revive_time", 0 );
    level.zt.config.bleedout_time = zt_cfg_int( "zt_bleedout_time", 0 );
    level.zt.config.spawn_protection = zt_cfg_int( "zt_spawn_protection", 0 );
    level.zt.config.lose_perks_on_down = zt_cfg_string( "zt_lose_perks_on_down", "default" );
    level.zt.config.keep_weapons_bleedout = zt_cfg_int( "zt_keep_weapons_bleedout", 0 );
    level.zt.config.challenge_no_perks = zt_cfg_int( "zt_challenge_no_perks", 0 );
    level.zt.config.challenge_no_pap = zt_cfg_int( "zt_challenge_no_pap", 0 );
    level.zt.config.challenge_no_box = zt_cfg_int( "zt_challenge_no_box", 0 );
    level.zt.config.challenge_wall_only = zt_cfg_int( "zt_challenge_wall_only", 0 );
    level.zt.config.challenge_starting_room = zt_cfg_int( "zt_challenge_starting_room", 0 );
    level.zt.config.challenge_one_box = zt_cfg_int( "zt_challenge_one_box", 0 );
    level.zt.config.challenge_gun_game = zt_cfg_int( "zt_challenge_gun_game", 0 );
    level.zt.config.challenge_random_loadout = zt_cfg_int( "zt_challenge_random_loadout", 0 );
    level.zt.config.challenge_random_rules = zt_cfg_int( "zt_challenge_random_rules", 0 );
    level.zt.config.challenge_one_weapon_slot = zt_cfg_int( "zt_challenge_one_weapon_slot", 0 );
    zt_resolve_random_challenge();
    if ( level.zt.config.zombie_health == -1 )
        level.zt.config.zombie_health = zt_random_zombie_health_percent();
    if ( level.zt.config.zombie_speed == -1 )
        level.zt.config.zombie_speed = zt_random_zombie_speed_percent();
}

zt_refresh_spawn_config()
{
    old_secondary = level.zt.config.secondary_starting_weapon;

    level.zt.config.player_health = zt_cfg_int( "zt_player_health", 0 );
    level.zt.config.max_grenades = zt_cfg_int( "zt_max_grenades", 0 );
    level.zt.config.max_equipment = zt_cfg_int( "zt_max_equipment", 0 );
    level.zt.config.secondary_starting_weapon = zt_cfg_string( "zt_secondary_starting_weapon", "default" );
    level.zt.config.random_starting_perks = zt_cfg_int( "zt_random_starting_perks", 0 );
    level.zt.config.starting_grenade = zt_cfg_string( "zt_starting_grenade", "default" );
    level.zt.config.starting_grenade_count = zt_cfg_int( "zt_starting_grenade_count", 0 );
    level.zt.config.starting_equipment = zt_cfg_string( "zt_starting_equipment", "default" );
    level.zt.config.starting_equipment_count = zt_cfg_int( "zt_starting_equipment_count", 0 );
    level.zt.config.start_all_perks = zt_cfg_int( "zt_start_all_perks", 0 );
    level.zt.config.player_speed = zt_cfg_int( "zt_player_speed", 0 );
    level.zt.config.starting_ammo = zt_cfg_int( "zt_starting_ammo", 0 );
    level.zt.config.reserve_ammo = zt_cfg_int( "zt_reserve_ammo", 0 );
    level.zt.config.starting_weapon_upgraded = zt_cfg_string( "zt_starting_weapon_upgraded", "default" );
    level.zt.config.starting_weapon_aat = zt_cfg_string( "zt_starting_weapon_aat", "default" );
    level.zt.config.spawn_protection = zt_cfg_int( "zt_spawn_protection", 0 );
    level.zt.config.revive_time = zt_cfg_int( "zt_revive_time", 0 );
    level.zt.config.down_limit = zt_cfg_int( "zt_down_limit", 0 );
    level.zt.config.challenge_random_loadout = zt_cfg_int( "zt_challenge_random_loadout", 0 );

    if ( old_secondary != level.zt.config.secondary_starting_weapon )
        level.zt.secondary_start_weapon_override = undefined;
}

zt_resolve_random_challenge()
{
    if ( !level.zt.config.challenge_random_rules )
        return;

    candidates = [];
    if ( !level.zt.config.challenge_no_perks ) candidates[candidates.size] = "no_perks";
    if ( !level.zt.config.challenge_no_box ) candidates[candidates.size] = "no_box";
    if ( !level.zt.config.challenge_wall_only ) candidates[candidates.size] = "wall_only";
    if ( !level.zt.config.challenge_random_loadout ) candidates[candidates.size] = "random_loadout";

    if ( candidates.size == 0 )
    {
        level.zt.random_challenge_name = "NO ADDITIONAL RULE";
        return;
    }

    selected = candidates[randomint( candidates.size )];
    if ( selected == "no_perks" )
    {
        level.zt.config.challenge_no_perks = 1;
        level.zt.random_challenge_name = "NO PERKS";
    }
    else if ( selected == "no_box" )
    {
        level.zt.config.challenge_no_box = 1;
        level.zt.random_challenge_name = "NO MYSTERY BOX";
    }
    else if ( selected == "wall_only" )
    {
        level.zt.config.challenge_wall_only = 1;
        level.zt.random_challenge_name = "WALL WEAPONS ONLY";
    }
    else
    {
        level.zt.config.challenge_random_loadout = 1;
        level.zt.random_challenge_name = "RANDOM LOADOUT";
    }
}

zt_register_self()
{
    mod = spawnstruct();
    mod.version = zt_version();
    mod.enabled = level.zt.config.enabled;
    mod.settings_manifest_version = 1;
    level.zt.mods["ztweaks"] = mod;

    if ( !isdefined( level.zmods ) )
        level.zmods = [];
    level.zmods["ztweaks"] = mod;
}

zt_version()
{
    // ZT_VERSION_BEGIN
    return "1.4";
    // ZT_VERSION_END
}

zt_report_names()
{
    names = [];
    names[0] = "auto_restart";
    names[1] = "starting_round";
    names[2] = "starting_points";
    names[3] = "game_start_delay";
    names[4] = "headshots_only";
    names[5] = "perk_limit";
    names[6] = "player_health";
    names[7] = "player_speed";
    names[8] = "random_starting_perks";
    names[9] = "start_all_perks";
    names[10] = "point_gain";
    names[11] = "weapon_damage";
    names[12] = "melee_damage";
    names[13] = "no_explosive_self_damage";
    names[14] = "fall_damage";
    names[15] = "down_limit";
    names[16] = "revive_time";
    names[17] = "bleedout_time";
    names[18] = "spawn_protection";
    names[19] = "lose_perks_on_down";
    names[20] = "keep_weapons_bleedout";
    names[21] = "starting_weapon";
    names[22] = "secondary_starting_weapon";
    names[23] = "starting_weapon_upgraded";
    names[24] = "starting_weapon_aat";
    names[25] = "starting_ammo";
    names[26] = "reserve_ammo";
    names[27] = "starting_grenade";
    names[28] = "max_grenades";
    names[29] = "starting_equipment";
    names[30] = "max_equipment";
    names[31] = "zombie_health";
    names[32] = "zombie_damage";
    names[33] = "zombie_speed";
    names[34] = "zombies_per_round";
    names[35] = "round_delay";
    names[36] = "zombie_spawn_rate";
    names[37] = "start_power_on";
    names[38] = "start_doors_open";
    names[39] = "powerup_ground_time";
    names[40] = "powerup_effect_time";
    names[41] = "powerup_drop_rate";
    names[42] = "powerup_max_per_round";
    names[43] = "powerup_stacking";
    names[44] = "box_quality";
    names[45] = "box_lock";
    names[46] = "box_price_multiplier";
    names[47] = "fire_sale_box_price";
    names[48] = "teddy_chance";
    names[49] = "gobblegum_uses";
    names[50] = "gobblegum_time";
    names[51] = "gobblegum_rounds";
    names[52] = "challenge_no_perks";
    names[53] = "challenge_no_pap";
    names[54] = "challenge_no_box";
    names[55] = "challenge_wall_only";
    names[56] = "challenge_starting_room";
    names[57] = "challenge_one_box";
    names[58] = "challenge_gun_game";
    names[59] = "challenge_random_loadout";
    names[60] = "challenge_random_rules";
    names[61] = "box_no_repeat";
    names[62] = "health_regen_delay";
    names[63] = "round_bonus";
    names[64] = "max_ammo_reload";
    names[65] = "death_points_retained";
    names[66] = "challenge_one_weapon_slot";
    names[67] = "powerup_drop_filters";
    names[68] = "disable_stock_aat";
    names[69] = "wunderfizz_price_multiplier";
    names[70] = "challenge_rising_damage";
    names[71] = "pap_damage_multiplier";
    names[72] = "fast_barrier_rebuild";
    return names;
}

zt_report_state_code( state )
{
    if ( state == "inherit" ) return 1;
    if ( state == "active" ) return 2;
    if ( state == "degraded" ) return 3;
    if ( state == "unavailable" ) return 4;
    if ( state == "conflict" ) return 5;
    return 0;
}

zt_report_reason_code( reason )
{
    if ( reason == "" ) return 0;
    if ( reason == "activated the stock main-power finalizer without marking temporary-generator/web/defend objectives complete" ) return 1;
    if ( reason == "completed both stock water-wheel switches; Shangri-La's wait_for_power owns global activation" ) return 2;
    if ( reason == "composed before Revelations' per-player damage pipeline" ) return 3;
    if ( reason == "composed before the map's player-damage pipeline" ) return 4;
    if ( reason == "composed with a late map callback" ) return 5;
    if ( reason == "composed with late map and perk health owners" ) return 6;
    if ( reason == "composed with late map drop thresholds" ) return 7;
    if ( reason == "composed with late map round caps" ) return 8;
    if ( reason == "composed with the map's live bleed-out duration" ) return 9;
    if ( reason == "composed with the map's spawn movement scale" ) return 10;
    if ( reason == "custom/counter/quest blocker owners were preserved; no ordinary blocker was safe to claim" ) return 11;
    if ( reason == "first-round spawning began before the tweak could be applied" ) return 12;
    if ( reason == "generic inventory restoration would duplicate map quest weapons" ) return 13;
    if ( reason == "ignored an active duplicate at the pickup boundary" ) return 14;
    if ( reason == "independent safe box firearm selected for each player" ) return 15;
    if ( reason == "map and perk revive-time callbacks are composed before scaling" ) return 16;
    if ( reason == "map callback returned no spawn cadence" ) return 17;
    if ( reason == "map did not expose the standard round zombie total" ) return 18;
    if ( reason == "map does not enable standard score-threshold power-up drops" ) return 19;
    if ( reason == "map exposes no authoritative starting-weapon replacement seam" ) return 20;
    if ( reason == "map exposes no base player-health variable" ) return 21;
    if ( reason == "map exposes no composable player-damage override" ) return 22;
    if ( reason == "map exposes no initialized ordinary traversal blockers" ) return 23;
    if ( reason == "map exposes no initialized published perk/door power zones" ) return 24;
    if ( reason == "map exposes no initialized stock global-power consumers" ) return 25;
    if ( reason == "map exposes no registered perk list" ) return 26;
    if ( reason == "map exposes no registered weapon pool" ) return 27;
    if ( reason == "map exposes no safely owned timed effect storage" ) return 28;
    if ( reason == "map exposes no standard between-round delay callback" ) return 29;
    if ( reason == "map exposes no standard game-start delay" ) return 30;
    if ( reason == "map exposes no standard zombie spawn cadence callback" ) return 31;
    if ( reason == "map exposes no standard zombie-health curve" ) return 32;
    if ( reason == "map exposes no standard zombie-speed curve" ) return 33;
    if ( reason == "map has not published a finalized stock GobbleGum registry" ) return 34;
    if ( reason == "map has not published a perk-limit capability" ) return 35;
    if ( reason == "map has not published a registered timed power-up capability" ) return 36;
    if ( reason == "map has not published a standard Mystery Box" ) return 37;
    if ( reason == "map has not published a standard Mystery Box registry" ) return 38;
    if ( reason == "map has not published a standard power-up drop capability" ) return 39;
    if ( reason == "map has not published a standard power-up timeout capability" ) return 40;
    if ( reason == "map has not published an actor-damage callback" ) return 41;
    if ( reason == "map registered no activation-limited GobbleGums" ) return 42;
    if ( reason == "map registered no compatible carried weapons" ) return 43;
    if ( reason == "map registered no perks" ) return 44;
    if ( reason == "map registered no round-limited GobbleGums" ) return 45;
    if ( reason == "map registered no time-limited GobbleGums" ) return 46;
    if ( reason == "map starts with power already enabled" ) return 47;
    if ( reason == "map-composed candidates are preserved, while stock safety and ownership exclusions remain" ) return 48;
    if ( reason == "map-owned Insta-Kill override preserved" ) return 49;
    if ( reason == "map-owned or multi-FX timed lifecycle preserved" ) return 50;
    if ( reason == "map's published power consumers rejected activation" ) return 51;
    if ( reason == "map's starting loadout already fills every primary slot" ) return 52;
    if ( reason == "map's stock always-on power path completed" ) return 53;
    if ( reason == "map's stock always-on power path did not initialize" ) return 54;
    if ( reason == "map's stock global-power consumers rejected activation" ) return 55;
    if ( reason == "no second registered weapon matches the selected class" ) return 56;
    if ( reason == "opened every initialized ordinary door, linked barrier, debris group and Moon buy airlock" ) return 57;
    if ( reason == "opened initialized ordinary traversal blockers; custom, counter, cycling-airlock and quest owners were preserved" ) return 58;
    if ( reason == "ordinary enemy hits compose outside the map's actor-damage pipeline" ) return 59;
    if ( reason == "Origins did not publish all six generator consumer zones" ) return 60;
    if ( reason == "Origins exposes no initialized generator-consumer registry" ) return 61;
    if ( reason == "pickup-bound stock lifecycle owner" ) return 62;
    if ( reason == "pickup-owned fixed effects; timer-owned remaining effects" ) return 63;
    if ( reason == "player already owns every registered perk" ) return 64;
    if ( reason == "powered all four stock grids and their portals/Pack-a-Punch; ritual count and completion remain map-owned" ) return 65;
    if ( reason == "powered all six generator consumers; capture count and Pack-a-Punch progression remain map-owned" ) return 66;
    if ( reason == "powered all six stock traversal stairs and published perk/door transformers; quest outputs 20/21/23 remain map-owned" ) return 67;
    if ( reason == "powered published perk/door transformers; other Beast and quest interactions remain map-owned" ) return 68;
    if ( reason == "powered the map's published perk/door consumer zones" ) return 69;
    if ( reason == "powered the stock global consumers and Verruckt trap controls" ) return 70;
    if ( reason == "powered the stock global consumers, Pack-a-Punch and Giant traversal links" ) return 71;
    if ( reason == "Revelations exposes no initialized corruption-grid consumers" ) return 72;
    if ( reason == "Revelations' stock power consumers rejected activation" ) return 73;
    if ( reason == "scaled the stock baseline before map special-round thresholds" ) return 74;
    if ( reason == "selected equipment is not registered by this map" ) return 75;
    if ( reason == "selected grenade is not registered by this map" ) return 76;
    if ( reason == "selected weapon is not registered by this map" ) return 77;
    if ( reason == "Shadows exposes no complete six-stair/perk/door consumer registry" ) return 78;
    if ( reason == "Shadows exposes no initialized perk/door power zones" ) return 79;
    if ( reason == "Shadows' stock power consumers rejected activation" ) return 80;
    if ( reason == "Shadows' stock stair/perk/door consumers rejected activation" ) return 81;
    if ( reason == "Shangri-La exposes no initialized two-switch power route" ) return 82;
    if ( reason == "Shangri-La's stock two-switch power route did not complete" ) return 83;
    if ( reason == "standard Mystery Boxes disabled" ) return 84;
    if ( reason == "standard Mystery Boxes disabled; scripted quest rewards remain map-owned" ) return 85;
    if ( reason == "standard purchases and ZTweaks grants are blocked; scripted quest grants remain map-owned" ) return 86;
    if ( reason == "stock earned score is scaled; direct map score restoration remains map-owned" ) return 87;
    if ( reason == "stock exposes completion notifications but no safe per-player pre-use veto" ) return 88;
    if ( reason == "stock ordinary blocker routes did not publish completion" ) return 89;
    if ( reason == "stock purchase-triggered relocation disabled; explicit map/quest moves remain map-owned" ) return 90;
    if ( reason == "stock removes perks inside its private last-stand pipeline" ) return 91;
    if ( reason == "stock weapon grant rejected the registered Pack-a-Punch upgrade" ) return 92;
    if ( reason == "stock weapon grant rejected the selected firearm" ) return 93;
    if ( reason == "the map does not publish a safe starting-zone exit set" ) return 94;
    if ( reason == "the map exposes no standard bleed-out duration" ) return 95;
    if ( reason == "the map exposes no universal safe Pack-a-Punch disable callback" ) return 96;
    if ( reason == "the registered weapon pool cannot guarantee quest-safe replacement" ) return 97;
    if ( reason == "the selected starting weapon has no registered Pack-a-Punch upgrade" ) return 98;
    if ( reason == "unknown weapon class" ) return 99;
    if ( reason == "weapon assets still own the absolute engine ammo ceiling" ) return 100;
    if ( reason == "Zetsubou exposes no initialized main-power consumer" ) return 101;
    if ( reason == "Zetsubou's stock main-power consumer rejected activation" ) return 102;
    if ( reason == "custom or changed perk purchases remain map-owned" ) return 103;
    if ( reason == "map owns its perk purchase hints or prices" ) return 104;
    if ( reason == "map has no standard perk machines" ) return 105;
    if ( reason == "map exposes no standard health-regeneration delay" ) return 106;
    if ( reason == "map exposes no standard death-point penalty" ) return 107;
    if ( reason == "map owns a nonstandard death-point penalty" ) return 108;
    if ( reason == "map owns the primary-weapon limit" ) return 109;
    if ( reason == "map replaced the primary-weapon limit" ) return 110;
    if ( reason == "one-weapon-slot challenge takes precedence" ) return 111;
    return 127; // Dynamic or future reason: preserve state without inventing detail.
}

zt_report_sync_player()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    // A remote player may still be completing the map load when the server
    // reaches round readiness. Do not queue any report commands until that
    // player's gameplay HUD has installed the packet listener.
    self zt_start_ready_listener();
    while ( !zt_game_ready() )
        wait 0.1;
    // Leave the join/intro command channel clear. The report is diagnostic UI,
    // not gameplay state, so a short delay is preferable to a failed join.
    wait 5;

    // Row 0 carries the 10-bit match marker. Each event bank carries row
    // (6 bits), state (3), and reason (7). The second event bank preserves
    // the proven 16-bit packet width while allowing more than 63 settings.
    // Gameplay-to-Lua notification does not reserve
    // clientuimodel bits, which Shadows needs for its stock HUD and quest data.
    // Send one paced snapshot per HUD request, then changed rows only. The
    // former 10 Hz full sweep never stopped and could saturate a joining
    // client's reliable command queue, especially with other Z mods active.
    sent = 0;
    previous = [];
    while ( 1 )
    {
        if ( self.zt_report_requests != sent )
        {
            sent = self.zt_report_requests;
            self LUINotifyEvent( &"ztCompatPacket", 1, 0 );
            wait 0.25;
            self LUINotifyEvent( &"ztCompatPacket", 1, level.zt.report_epoch );
            wait 0.25;
            for ( i = 0; i < level.zt.report_names.size; i++ )
            {
                packet = zt_report_row_packet( i );
                self zt_report_send_row( i, packet );
                previous[i] = packet;
                wait 0.25;
            }
        }
        else if ( sent > 0 )
        {
            for ( i = 0; i < level.zt.report_names.size; i++ )
            {
                packet = zt_report_row_packet( i );
                if ( !isdefined( previous[i] ) || previous[i] != packet )
                {
                    self zt_report_send_row( i, packet );
                    previous[i] = packet;
                    wait 0.25;
                }
            }
        }
        wait 1;
    }
}

zt_start_ready_listener()
{
    if ( zt_true( self.zt_ready_listener_started ) )
        return;
    self.zt_ready_listener_started = 1;
    self.zt_report_requests = 0;
    self thread zt_report_ready_listener();
}

zt_report_ready_listener()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    while ( 1 )
    {
        self waittill( "menuresponse", menu, response );
        if ( isdefined( response ) && response == "zt_join_ready" )
        {
            if ( !zt_true( self.zt_client_hud_ready ) )
            {
                self.zt_client_hud_ready = 1;
                self thread zt_apply_pending_remote_spawn();
            }
            continue;
        }
        if ( isdefined( response ) && response == "zt_compat_ready" )
        {
            now = gettime();
            if ( !isdefined( self.zt_report_last_request ) || now - self.zt_report_last_request >= 2000 )
            {
                self.zt_report_last_request = now;
                self.zt_report_requests++;
            }
        }
    }
}

zt_report_row_packet( i )
{
    name = level.zt.report_names[i];
    state = 1;
    reason = 0;
    if ( isdefined( level.zt.features[name] ) )
    {
        state = level.zt.features[name].report_state;
        reason = level.zt.features[name].report_reason;
    }
    if ( i < 63 )
        return ( i + 1 ) * 1024 + state * 128 + reason;
    return ( i - 62 ) * 1024 + state * 128 + reason;
}

zt_report_send_row( i, packet )
{
    if ( i < 63 )
        self LUINotifyEvent( &"ztCompatPacket", 1, packet );
    else
        self LUINotifyEvent( &"ztCompatPacket2", 1, packet );
}

zt_feature( name, state, reason )
{
    had_previous = isdefined( level.zt.features[name] );
    changed = !had_previous || level.zt.features[name].state != state || level.zt.features[name].reason != reason;
    setdvar( "zt_status_" + name, state );
    setdvar( "zt_status_reason_" + name, reason );
    if ( state == "unavailable" && reason != "" )
    {
        key = name + "|" + reason;
        if ( !isdefined( level.zt.feature_messages[key] ) )
        {
            level.zt.feature_messages[key] = 1;
            level thread zt_feature_message( name, reason );
        }
    }

    feature = spawnstruct();
    feature.state = state;
    feature.reason = reason;
    feature.report_state = zt_report_state_code( state );
    feature.report_reason = zt_report_reason_code( reason );
    level.zt.features[name] = feature;

    // Development builds emit one structured line per real state transition.
    // Initial inherit rows stay quiet, while returning an active tweak to its
    // semantic default is still recorded for callback-ownership verification.
    if ( changed && ( state != "inherit" || had_previous ) && issubstr( zt_version(), ".d" ) )
        zt_feature_trace( name, state, reason );
}

zt_feature_trace( name, state, reason )
{
    map_name = "unknown";
    if ( isdefined( level.script ) )
        map_name = level.script;
    line = "ZTWEAKS_RUNTIME|version=" + zt_version() + "|port=t7|map=" + map_name + "|feature=" + name + "|state=" + state;
    if ( reason != "" )
        line = line + "|reason=" + reason;
    // BO3 marks both print and println as developer-only builtins. The stock
    // compiler requires such calls to carry the devblock opcode even when
    // T7x starts the server with developer enabled.
    /# print( line ); #/
}

zt_new_features_init()
{
    names = [];
    names[0] = "point_gain";
    names[1] = "starting_ammo";
    names[2] = "reserve_ammo";
    names[3] = "starting_weapon_upgraded";
    names[4] = "starting_weapon_aat";
    names[5] = "weapon_damage";
    names[6] = "melee_damage";
    names[7] = "no_explosive_self_damage";
    names[8] = "fall_damage";
    names[9] = "box_quality";
    names[10] = "box_lock";
    names[11] = "box_price_multiplier";
    names[12] = "fire_sale_box_price";
    names[13] = "teddy_chance";
    names[14] = "powerup_stacking";
    names[15] = "down_limit";
    names[16] = "revive_time";
    names[17] = "bleedout_time";
    names[18] = "spawn_protection";
    names[19] = "lose_perks_on_down";
    names[20] = "keep_weapons_bleedout";
    names[21] = "challenge_no_perks";
    names[22] = "challenge_no_pap";
    names[23] = "challenge_no_box";
    names[24] = "challenge_wall_only";
    names[25] = "challenge_starting_room";
    names[26] = "challenge_one_box";
    names[27] = "challenge_gun_game";
    names[28] = "challenge_random_loadout";
    names[29] = "challenge_random_rules";
    names[30] = "zombie_damage";
    names[31] = "box_no_repeat";
    names[32] = "trap_price_multiplier";
    names[33] = "perk_price_multiplier";
    names[34] = "health_regen_delay";
    names[35] = "round_bonus";
    names[36] = "max_ammo_reload";
    names[37] = "death_points_retained";
    names[38] = "challenge_one_weapon_slot";
    names[39] = "powerup_drop_filters";
    names[40] = "disable_stock_aat";
    names[41] = "wunderfizz_price_multiplier";
    names[42] = "challenge_rising_damage";
    names[43] = "pap_damage_multiplier";
    names[44] = "fast_barrier_rebuild";
    for ( i = 0; i < names.size; i++ )
        zt_feature( names[i], "inherit", "" );
}

zt_feature_label( name )
{
    if ( name == "starting_round" ) return "Starting Round";
    if ( name == "starting_points" ) return "Starting Points";
    if ( name == "game_start_delay" ) return "Game Start Delay";
    if ( name == "player_health" ) return "Player Health";
    if ( name == "zombie_health" ) return "Zombie Health";
    if ( name == "zombie_damage" ) return "Zombie Damage";
    if ( name == "zombie_speed" ) return "Zombie Speed";
    if ( name == "starting_weapon" ) return "Starting Weapon";
    if ( name == "secondary_starting_weapon" ) return "Secondary Weapon";
    if ( name == "starting_weapon_upgraded" ) return "Starting Weapon Pack-a-Punch";
    if ( name == "starting_weapon_aat" ) return "Starting Weapon AAT";
    if ( name == "starting_grenade" ) return "Starting Grenade";
    if ( name == "starting_equipment" ) return "Starting Equipment";
    if ( name == "powerup_ground_time" ) return "Power-Up Ground Time";
    if ( name == "powerup_effect_time" ) return "Power-Up Effect Time";
    if ( name == "powerup_drop_rate" ) return "Power-Up Drop Rate";
    if ( name == "powerup_max_per_round" ) return "Power-Up Drop Cap";
    if ( name == "box_price_multiplier" ) return "Mystery Box Price";
    if ( name == "fire_sale_box_price" ) return "Fire Sale Box Price";
    if ( name == "teddy_chance" ) return "Teddy-Bear Chance";
    if ( name == "box_no_repeat" ) return "Avoid Repeat Box Weapons";
    if ( name == "trap_price_multiplier" ) return "Trap Price";
    if ( name == "perk_price_multiplier" ) return "Perk Price";
    if ( name == "health_regen_delay" ) return "Health Regen Delay";
    if ( name == "round_bonus" ) return "Round Bonus";
    if ( name == "max_ammo_reload" ) return "Max Ammo Reloads Magazines";
    if ( name == "death_points_retained" ) return "Points Retained After Death";
    if ( name == "challenge_one_weapon_slot" ) return "One Weapon Slot";
    if ( name == "powerup_drop_filters" ) return "Power-Up Drop Filters";
    if ( name == "disable_stock_aat" ) return "Disable Stock AATs";
    if ( name == "wunderfizz_price_multiplier" ) return "Wunderfizz Price";
    if ( name == "challenge_rising_damage" ) return "Rising Player Damage";
    if ( name == "pap_damage_multiplier" ) return "Pack-a-Punch Damage";
    if ( name == "fast_barrier_rebuild" ) return "Faster Barrier Rebuild";
    if ( name == "start_power_on" ) return "Start With Power";
    if ( name == "start_doors_open" ) return "Start With Doors Open";
    if ( name == "perk_limit" ) return "Perk Limit";
    if ( name == "gobblegum_uses" ) return "GobbleGum Uses";
    if ( name == "gobblegum_time" ) return "GobbleGum Time";
    if ( name == "gobblegum_rounds" ) return "GobbleGum Rounds";
    return name;
}

zt_feature_message( name, reason )
{
    level endon( #"end_game" );

    elapsed = 0;
    while ( elapsed < 30 )
    {
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            if ( players[i] ishost() )
            {
                players[i] zt_notice( zt_notice_code( name, reason ), "ZTweaks: " + zt_feature_label( name ) + " disabled - " + reason );
                return;
            }
        }
        wait 0.5;
        elapsed = elapsed + 0.5;
    }
}

// ZT_NOTICE_DICTIONARY_BEGIN
zt_notice_signature() { return 11531363; }
zt_notice_code( name, reason )
{
    feature = 0;
    if ( name == "auto_restart" ) feature = 1;
    if ( name == "bank_limit" ) feature = 2;
    if ( name == "bleedout_time" ) feature = 3;
    if ( name == "box_lock" ) feature = 4;
    if ( name == "box_no_repeat" ) feature = 5;
    if ( name == "box_price_multiplier" ) feature = 6;
    if ( name == "box_quality" ) feature = 7;
    if ( name == "challenge_gun_game" ) feature = 8;
    if ( name == "challenge_no_box" ) feature = 9;
    if ( name == "challenge_no_pap" ) feature = 10;
    if ( name == "challenge_no_perks" ) feature = 11;
    if ( name == "challenge_one_box" ) feature = 12;
    if ( name == "challenge_one_weapon_slot" ) feature = 13;
    if ( name == "challenge_random_loadout" ) feature = 14;
    if ( name == "challenge_random_rules" ) feature = 15;
    if ( name == "challenge_rising_damage" ) feature = 16;
    if ( name == "challenge_starting_room" ) feature = 17;
    if ( name == "challenge_wall_only" ) feature = 18;
    if ( name == "death_points_retained" ) feature = 19;
    if ( name == "disable_carpenter_drops" ) feature = 20;
    if ( name == "disable_double_points_drops" ) feature = 21;
    if ( name == "disable_fire_sale_drops" ) feature = 22;
    if ( name == "disable_insta_kill_drops" ) feature = 23;
    if ( name == "disable_max_ammo_drops" ) feature = 24;
    if ( name == "disable_nuke_drops" ) feature = 25;
    if ( name == "disable_stock_aat" ) feature = 26;
    if ( name == "down_limit" ) feature = 27;
    if ( name == "experimental_tweaks" ) feature = 28;
    if ( name == "fall_damage" ) feature = 29;
    if ( name == "fast_barrier_rebuild" ) feature = 30;
    if ( name == "fire_sale_box_price" ) feature = 31;
    if ( name == "game_start_delay" ) feature = 32;
    if ( name == "gobblegum_rounds" ) feature = 33;
    if ( name == "gobblegum_time" ) feature = 34;
    if ( name == "gobblegum_uses" ) feature = 35;
    if ( name == "headshots_only" ) feature = 36;
    if ( name == "health_regen_delay" ) feature = 37;
    if ( name == "keep_weapons_bleedout" ) feature = 38;
    if ( name == "lose_perks_on_down" ) feature = 39;
    if ( name == "max_ammo_reload" ) feature = 40;
    if ( name == "max_equipment" ) feature = 41;
    if ( name == "max_grenades" ) feature = 42;
    if ( name == "melee_damage" ) feature = 43;
    if ( name == "next_map" ) feature = 44;
    if ( name == "no_explosive_self_damage" ) feature = 45;
    if ( name == "pap_damage_multiplier" ) feature = 46;
    if ( name == "perk_limit" ) feature = 47;
    if ( name == "perk_price_multiplier" ) feature = 48;
    if ( name == "player_health" ) feature = 49;
    if ( name == "player_speed" ) feature = 50;
    if ( name == "point_gain" ) feature = 51;
    if ( name == "powerup_drop_filters" ) feature = 52;
    if ( name == "powerup_drop_rate" ) feature = 53;
    if ( name == "powerup_effect_time" ) feature = 54;
    if ( name == "powerup_ground_time" ) feature = 55;
    if ( name == "powerup_max_per_round" ) feature = 56;
    if ( name == "powerup_stacking" ) feature = 57;
    if ( name == "random_starting_perks" ) feature = 58;
    if ( name == "reserve_ammo" ) feature = 59;
    if ( name == "revive_time" ) feature = 60;
    if ( name == "round_bonus" ) feature = 61;
    if ( name == "round_delay" ) feature = 62;
    if ( name == "secondary_starting_weapon" ) feature = 63;
    if ( name == "spawn_protection" ) feature = 64;
    if ( name == "start_all_perks" ) feature = 65;
    if ( name == "start_doors_open" ) feature = 66;
    if ( name == "start_power_on" ) feature = 67;
    if ( name == "starting_ammo" ) feature = 68;
    if ( name == "starting_equipment" ) feature = 69;
    if ( name == "starting_equipment_count" ) feature = 70;
    if ( name == "starting_grenade" ) feature = 71;
    if ( name == "starting_grenade_count" ) feature = 72;
    if ( name == "starting_points" ) feature = 73;
    if ( name == "starting_round" ) feature = 74;
    if ( name == "starting_weapon" ) feature = 75;
    if ( name == "starting_weapon_aat" ) feature = 76;
    if ( name == "starting_weapon_upgraded" ) feature = 77;
    if ( name == "teddy_chance" ) feature = 78;
    if ( name == "trap_price_multiplier" ) feature = 79;
    if ( name == "weapon_damage" ) feature = 80;
    if ( name == "wunderfizz_price_multiplier" ) feature = 81;
    if ( name == "zombie_damage" ) feature = 82;
    if ( name == "zombie_health" ) feature = 83;
    if ( name == "zombie_spawn_rate" ) feature = 84;
    if ( name == "zombie_speed" ) feature = 85;
    if ( name == "zombies_per_round" ) feature = 86;
    if ( feature == 0 ) return 0;
    code = 0;
    if ( code == 0 ) code = zt_notice_reason_0( reason );
    if ( code == 0 ) code = zt_notice_reason_48( reason );
    if ( code == 0 ) code = zt_notice_reason_96( reason );
    if ( code == 0 ) code = zt_notice_reason_144( reason );
    if ( code == 0 ) return 0;
    return feature * 512 + code;
}
zt_notice_reason_0( reason )
{
    if ( reason == "Alternate Ammo Type applied only to compatible Pack-a-Punched starting weapons" ) return 1;
    if ( reason == "BO2 exposes no composable revive-time callback" ) return 2;
    if ( reason == "BO2 has no safe pre-dispatch seam for ignoring a repeated timed power-up; stock stacking remains in control" ) return 3;
    if ( reason == "BO2 weapon registrations do not identify wonder weapons generically" ) return 4;
    if ( reason == "Buried did not initialize its single stock power switch" ) return 5;
    if ( reason == "Buried rejected its stock switch request" ) return 6;
    if ( reason == "Die Rise did not initialize its single stock power switch" ) return 7;
    if ( reason == "Die Rise rejected its stock switch request" ) return 8;
    if ( reason == "Double Points did not expose its stock team scalar" ) return 9;
    if ( reason == "Enable Experimental Tweaks to edit this stock-map-only setting." ) return 10;
    if ( reason == "Insta-Kill did not expose its stock team state" ) return 11;
    if ( reason == "Mob did not initialize its Afterlife perk-box waiter" ) return 12;
    if ( reason == "Mob final-showdown health remains map-owned" ) return 13;
    if ( reason == "Mystery Box relocation is disabled" ) return 14;
    if ( reason == "Nuketown owns its randomized perk and Pack-a-Punch arrival cadence" ) return 15;
    if ( reason == "Origins did not publish all six generator consumer zones" ) return 16;
    if ( reason == "Origins did not publish its generator perk consumers" ) return 17;
    if ( reason == "Origins exposes no initialized generator-consumer registry" ) return 18;
    if ( reason == "POWER-UP DROP FILTERS" ) return 19;
    if ( reason == "Revelations exposes no initialized corruption-grid consumers" ) return 20;
    if ( reason == "Revelations' stock power consumers rejected activation" ) return 21;
    if ( reason == "Shadows exposes no complete six-stair/perk/door consumer registry" ) return 22;
    if ( reason == "Shadows exposes no initialized perk/door power zones" ) return 23;
    if ( reason == "Shadows' stock power consumers rejected activation" ) return 24;
    if ( reason == "Shadows' stock stair/perk/door consumers rejected activation" ) return 25;
    if ( reason == "Shangri-La exposes no initialized two-switch power route" ) return 26;
    if ( reason == "Shangri-La's stock two-switch power route did not complete" ) return 27;
    if ( reason == "The game reported a newer compatibility reason; see the ZTweaks runtime log." ) return 28;
    if ( reason == "TranZit did not publish registered global-power consumers" ) return 29;
    if ( reason == "Turned/Cleansed owns its 0.05-second role-conversion sentinel" ) return 30;
    if ( reason == "Turned/Cleansed owns its arena and exposes no meaningful power capability" ) return 31;
    if ( reason == "Turned/Cleansed owns its arena doors and barriers" ) return 32;
    if ( reason == "Zetsubou exposes no initialized main-power consumer" ) return 33;
    if ( reason == "Zetsubou's stock main-power consumer rejected activation" ) return 34;
    if ( reason == "activated the stock main-power finalizer without marking temporary-generator/web/defend objectives complete" ) return 35;
    if ( reason == "classic Double Points/Insta-Kill scaling requires an exact stock team scope" ) return 36;
    if ( reason == "completed both stock water-wheel switches; Shangri-La's wait_for_power owns global activation" ) return 37;
    if ( reason == "composed before Revelations' per-player damage pipeline" ) return 38;
    if ( reason == "composed before the map's player-damage pipeline" ) return 39;
    if ( reason == "composed with a late map callback" ) return 40;
    if ( reason == "composed with late map and perk health owners" ) return 41;
    if ( reason == "composed with late map drop thresholds" ) return 42;
    if ( reason == "composed with late map round caps" ) return 43;
    if ( reason == "composed with the map's live bleed-out duration" ) return 44;
    if ( reason == "composed with the map's spawn movement scale" ) return 45;
    if ( reason == "custom map exposes no authoritative base player-health variable" ) return 46;
    if ( reason == "custom or changed perk purchases remain map-owned" ) return 47;
    if ( reason == "custom or changed trap purchases remain map-owned" ) return 48;
    return 0;
}
zt_notice_reason_48( reason )
{
    if ( reason == "custom/counter/quest blocker owners were preserved; no ordinary blocker was safe to claim" ) return 49;
    if ( reason == "first-round spawning began before the tweak could be applied" ) return 50;
    if ( reason == "generic inventory restoration would duplicate map quest weapons" ) return 51;
    if ( reason == "global stock AAT disable takes precedence" ) return 52;
    if ( reason == "ignored an active duplicate at the pickup boundary" ) return 53;
    if ( reason == "independent safe box firearm selected for each player" ) return 54;
    if ( reason == "map and perk revive-time callbacks are composed before scaling" ) return 55;
    if ( reason == "map callback returned no spawn cadence" ) return 56;
    if ( reason == "map did not expose standard Zombies match variables" ) return 57;
    if ( reason == "map did not expose the standard round zombie total" ) return 58;
    if ( reason == "map did not initialize round logic before the door-capability timeout" ) return 59;
    if ( reason == "map did not initialize the stock Alternate Ammo Type system" ) return 60;
    if ( reason == "map did not register any supported Alternate Ammo Types" ) return 61;
    if ( reason == "map does not enable standard score-threshold power-up drops" ) return 62;
    if ( reason == "map exposes no active player for stock blocker callbacks" ) return 63;
    if ( reason == "map exposes no authoritative starting-weapon replacement seam" ) return 64;
    if ( reason == "map exposes no base player-health variable" ) return 65;
    if ( reason == "map exposes no composable player-damage override" ) return 66;
    if ( reason == "map exposes no composable player-last-stand callback" ) return 67;
    if ( reason == "map exposes no initialized ordinary traversal blockers" ) return 68;
    if ( reason == "map exposes no initialized published perk/door power zones" ) return 69;
    if ( reason == "map exposes no initialized registered global-power consumers" ) return 70;
    if ( reason == "map exposes no initialized standard door capability" ) return 71;
    if ( reason == "map exposes no initialized stock global-power consumers" ) return 72;
    if ( reason == "map exposes no registered perk list" ) return 73;
    if ( reason == "map exposes no registered weapon pool" ) return 74;
    if ( reason == "map exposes no safe standard purchasable doors" ) return 75;
    if ( reason == "map exposes no safely owned timed effect storage" ) return 76;
    if ( reason == "map exposes no standard Wunderfizz machine or price" ) return 77;
    if ( reason == "map exposes no standard between-round delay" ) return 78;
    if ( reason == "map exposes no standard between-round delay callback" ) return 79;
    if ( reason == "map exposes no standard death-point penalty" ) return 80;
    if ( reason == "map exposes no standard game-start delay" ) return 81;
    if ( reason == "map exposes no standard health-regeneration delay" ) return 82;
    if ( reason == "map exposes no standard zombie spawn cadence" ) return 83;
    if ( reason == "map exposes no standard zombie spawn cadence callback" ) return 84;
    if ( reason == "map exposes no standard zombie-health curve" ) return 85;
    if ( reason == "map exposes no standard zombie-speed curve" ) return 86;
    if ( reason == "map exposes no stock-compatible perk machines" ) return 87;
    if ( reason == "map has no standard perk machines" ) return 88;
    if ( reason == "map has no standard purchase traps" ) return 89;
    if ( reason == "map has not published a compatible BO2 bank capability" ) return 90;
    if ( reason == "map has not published a finalized stock GobbleGum registry" ) return 91;
    if ( reason == "map has not published a perk-limit capability" ) return 92;
    if ( reason == "map has not published a registered timed power-up capability" ) return 93;
    if ( reason == "map has not published a standard Mystery Box" ) return 94;
    if ( reason == "map has not published a standard Mystery Box registry" ) return 95;
    if ( reason == "map has not published a standard between-round delay" ) return 96;
    return 0;
}
zt_notice_reason_96( reason )
{
    if ( reason == "map has not published a standard power-up drop capability" ) return 97;
    if ( reason == "map has not published a standard power-up timeout capability" ) return 98;
    if ( reason == "map has not published a standard zombie spawn cadence" ) return 99;
    if ( reason == "map has not published an actor-damage callback" ) return 100;
    if ( reason == "map mode did not publish its stock startup power state" ) return 101;
    if ( reason == "map mode starts with power already enabled" ) return 102;
    if ( reason == "map owns Mystery Box teddy-bear chance" ) return 103;
    if ( reason == "map owns a nonstandard death-point penalty" ) return 104;
    if ( reason == "map owns its perk purchase hints or prices" ) return 105;
    if ( reason == "map owns its trap purchase callbacks or prices" ) return 106;
    if ( reason == "map owns the primary-weapon limit" ) return 107;
    if ( reason == "map published an invalid bank denomination" ) return 108;
    if ( reason == "map registered no activation-limited GobbleGums" ) return 109;
    if ( reason == "map registered no compatible carried weapons" ) return 110;
    if ( reason == "map registered no perks" ) return 111;
    if ( reason == "map registered no round-limited GobbleGums" ) return 112;
    if ( reason == "map registered no time-limited GobbleGums" ) return 113;
    if ( reason == "map rejected its standard door-open requests" ) return 114;
    if ( reason == "map replaced Mystery Box teddy-bear chance" ) return 115;
    if ( reason == "map replaced a Mystery Box price; that location remains map-owned" ) return 116;
    if ( reason == "map replaced the Wunderfizz price; its value remains map-owned" ) return 117;
    if ( reason == "map replaced the primary-weapon limit" ) return 118;
    if ( reason == "map replaces stock power-up pickup dispatch; classic Double Points/Insta-Kill remain map-owned" ) return 119;
    if ( reason == "map starts with power already enabled" ) return 120;
    if ( reason == "map supplies a custom Insta-Kill lifecycle and remains authoritative" ) return 121;
    if ( reason == "map uses fixed-price legacy Mystery Box hints" ) return 122;
    if ( reason == "map's published power consumers rejected activation" ) return 123;
    if ( reason == "map's registered power consumers were already enabled" ) return 124;
    if ( reason == "map's starting loadout already fills every primary slot" ) return 125;
    if ( reason == "map's stock always-on power path completed" ) return 126;
    if ( reason == "map's stock always-on power path did not initialize" ) return 127;
    if ( reason == "map's stock global-power consumers rejected activation" ) return 128;
    if ( reason == "map-composed candidates are preserved, while stock safety and ownership exclusions remain" ) return 129;
    if ( reason == "map-owned Insta-Kill override preserved" ) return 130;
    if ( reason == "map-owned or multi-FX timed lifecycle preserved" ) return 131;
    if ( reason == "no second registered weapon matches the selected class" ) return 132;
    if ( reason == "no selected Pack-a-Punched starting weapon supports Alternate Ammo Types" ) return 133;
    if ( reason == "one-weapon-slot challenge takes precedence" ) return 134;
    if ( reason == "opened common traversal blockers; custom, counter, airlock, and quest-owned blockers were preserved" ) return 135;
    if ( reason == "opened every initialized ordinary door, linked barrier, debris group and Moon buy airlock" ) return 136;
    if ( reason == "opened initialized ordinary traversal blockers; custom, counter, cycling-airlock and quest owners were preserved" ) return 137;
    if ( reason == "ordinary enemy hits compose outside the map's actor-damage pipeline" ) return 138;
    if ( reason == "pickup-bound stock lifecycle owner" ) return 139;
    if ( reason == "pickup-owned fixed effects; timer-owned remaining effects" ) return 140;
    if ( reason == "player already owns every registered perk" ) return 141;
    if ( reason == "player-only power-up did not publish player timer vars; broader scopes were left untouched" ) return 142;
    if ( reason == "powered all four stock grids and their portals/Pack-a-Punch; ritual count and completion remain map-owned" ) return 143;
    if ( reason == "powered all six generator consumers; capture count and Pack-a-Punch progression remain map-owned" ) return 144;
    return 0;
}
zt_notice_reason_144( reason )
{
    if ( reason == "powered all six stock traversal stairs and published perk/door transformers; quest outputs 20/21/23 remain map-owned" ) return 145;
    if ( reason == "powered generator perk consumers; captures, Mystery Boxes, and Pack-a-Punch remain map-owned" ) return 146;
    if ( reason == "powered perk shock boxes; other Afterlife panels and quest state remain map-owned" ) return 147;
    if ( reason == "powered published perk/door transformers; other Beast and quest interactions remain map-owned" ) return 148;
    if ( reason == "powered registered consumers; the buildable switch, reactor, Avogadro, gates, bus, morse code, and quest flags remain map-owned" ) return 149;
    if ( reason == "powered registered global consumers; custom switches, local power, and quest state remain map-owned" ) return 150;
    if ( reason == "powered the map's published perk/door consumer zones" ) return 151;
    if ( reason == "powered the stock global consumers and Verruckt trap controls" ) return 152;
    if ( reason == "powered the stock global consumers, Pack-a-Punch and Giant traversal links" ) return 153;
    if ( reason == "race-team Double Points has additional map-owned state and remains stock" ) return 154;
    if ( reason == "recognized stock map required" ) return 155;
    if ( reason == "registered upgrades only; custom upgrade systems remain map-owned" ) return 156;
    if ( reason == "round logic began before the tweak could be applied" ) return 157;
    if ( reason == "scaled from BO2's stock base and composed with perk/map health bonuses" ) return 158;
    if ( reason == "scaled the stock baseline before map special-round thresholds" ) return 159;
    if ( reason == "selected Alternate Ammo Type is not registered by this map" ) return 160;
    if ( reason == "selected NO ADDITIONAL RULE for this match" ) return 161;
    if ( reason == "selected NO MYSTERY BOX for this match" ) return 162;
    if ( reason == "selected NO PERKS for this match" ) return 163;
    if ( reason == "selected RANDOM LOADOUT for this match" ) return 164;
    if ( reason == "selected WALL WEAPONS ONLY for this match" ) return 165;
    if ( reason == "selected equipment is not registered by this map" ) return 166;
    if ( reason == "selected grenade is not registered by this map" ) return 167;
    if ( reason == "selected weapon is not registered by this map" ) return 168;
    if ( reason == "standard Mystery Boxes disabled" ) return 169;
    if ( reason == "standard Mystery Boxes disabled; scripted quest rewards remain map-owned" ) return 170;
    if ( reason == "standard door capability disappeared during map initialization" ) return 171;
    if ( reason == "standard purchases and ZTweaks grants are blocked; scripted quest grants remain map-owned" ) return 172;
    if ( reason == "stock barriers without map-authored delays only" ) return 173;
    if ( reason == "stock blocker system has no unowned repair delay" ) return 174;
    if ( reason == "stock classic co-op already permits unlimited ordinary downs" ) return 175;
    if ( reason == "stock earned score and box refunds are scaled; direct map score restoration remains map-owned" ) return 176;
    if ( reason == "stock earned score is scaled; direct map score restoration remains map-owned" ) return 177;
    if ( reason == "stock exposes completion notifications but no safe per-player pre-use veto" ) return 178;
    if ( reason == "stock ordinary blocker routes did not publish completion" ) return 179;
    if ( reason == "stock purchase-triggered relocation disabled; explicit map/quest moves remain map-owned" ) return 180;
    if ( reason == "stock removes perks inside its private last-stand pipeline" ) return 181;
    if ( reason == "stock weapon grant rejected the registered Pack-a-Punch upgrade" ) return 182;
    if ( reason == "stock weapon grant rejected the selected firearm" ) return 183;
    if ( reason == "the map does not publish a safe starting-zone exit set" ) return 184;
    if ( reason == "the map exposes no standard bleed-out duration" ) return 185;
    if ( reason == "the map exposes no universal safe Pack-a-Punch disable callback" ) return 186;
    if ( reason == "the registered weapon pool cannot guarantee quest-safe replacement" ) return 187;
    if ( reason == "the selected starting weapon has no registered Pack-a-Punch upgrade" ) return 188;
    if ( reason == "unknown weapon class" ) return 189;
    if ( reason == "waiting for game over" ) return 190;
    if ( reason == "weapon assets still own the absolute engine ammo ceiling" ) return 191;
    return 0;
}
// Generated from the portable warning transport template. Never hold spawn.
zt_notice( code, fallback )
{
    if ( !isdefined( self ) || !isplayer( self ) ) return;
    if ( code == 0 ) { self iprintlnbold( fallback ); return; }
    if ( !isdefined( self.zt_notice_queue ) )
    {
        self.zt_notice_queue = [];
        self.zt_notice_head = 0;
    }
    if ( self.zt_notice_queue.size - self.zt_notice_head >= 32 )
    {
        self iprintlnbold( fallback );
        return;
    }
    entry = spawnstruct();
    entry.code = code;
    entry.fallback = fallback;
    self.zt_notice_queue[self.zt_notice_queue.size] = entry;
    if ( !isdefined( self.zt_notice_running ) || !self.zt_notice_running )
    {
        self.zt_notice_running = 1;
        self thread zt_notice_worker();
    }
}

zt_notice_worker()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    self thread zt_notice_ack();
    // Arm the response listener before publishing any packet.
    wait 0.05;
    while ( self.zt_notice_head < self.zt_notice_queue.size )
    {
        entry = self.zt_notice_queue[self.zt_notice_head];
        if ( !isdefined( level.zt.notice_serial ) ) level.zt.notice_serial = gettime() % 4000000;
        level.zt.notice_serial = ( level.zt.notice_serial % 8000000 ) + 1;
        self.zt_notice_token = level.zt.notice_serial;
        self.zt_notice_received = 0;
        elapsed = 0;
        while ( elapsed < 4 && !self.zt_notice_received )
        {
            // One initial send and one retry, serialized per player. No burst
            // or per-frame reliable request; gameplay never waits for this.
            if ( elapsed == 0 || elapsed == 2 )
            {
                self LUINotifyEvent( &"ztLocalizedNotice", 3, zt_notice_signature(), self.zt_notice_token, entry.code );
            }
            wait 0.25;
            elapsed += 0.25;
        }
        if ( !self.zt_notice_received ) self iprintlnbold( entry.fallback );
        self.zt_notice_head++;
        wait 0.25;
    }
    self notify( #"zt_notice_stop" );
    self.zt_notice_queue = [];
    self.zt_notice_head = 0;
    self.zt_notice_running = 0;
}

zt_notice_ack()
{
    self endon( #"disconnect" );
    self endon( #"zt_notice_stop" );
    level endon( #"end_game" );
    while ( 1 )
    {
        self waittill( "menuresponse", menu, response );
        if ( isdefined( self.zt_notice_token ) && isdefined( response ) &&
            response == "zt_notice|" + self.zt_notice_token )
            self.zt_notice_received = 1;
    }
}

// ZT_NOTICE_DICTIONARY_END

zt_game_ready()
{
    // round_number is intentionally cleared during parts of the stock round
    // transition.  The flag is the authoritative common lifecycle boundary;
    // requiring both can reject an otherwise initialized stock map.
    return level flag::exists( "start_zombie_round_logic" ) && level flag::get( "start_zombie_round_logic" );
}

zt_has_match_tweaks()
{
    return level.zt.config.starting_round > 0 || level.zt.config.starting_points > 0 || level.zt.config.game_start_delay >= 0 || level.zt.config.player_health > 0 || level.zt.config.zombie_health > 0 || level.zt.config.zombie_speed > 0 || level.zt.config.headshots_only || level.zt.config.starting_weapon != "default" || level.zt.config.secondary_starting_weapon != "default";
}

zt_has_player_tweaks()
{
    return level.zt.config.player_health > 0 || level.zt.config.max_grenades > 0 || level.zt.config.max_equipment > 0 || level.zt.config.max_ammo_reload > 0 || level.zt.config.starting_weapon != "default" || level.zt.config.secondary_starting_weapon != "default" || level.zt.config.random_starting_perks > 0 || level.zt.config.starting_grenade != "default" || level.zt.config.starting_grenade_count > 0 || level.zt.config.starting_equipment != "default" || level.zt.config.starting_equipment_count > 0 || level.zt.config.start_all_perks || level.zt.config.player_speed > 0 || level.zt.config.starting_ammo != 0 || level.zt.config.reserve_ammo > 0 || level.zt.config.starting_weapon_upgraded != "default" || level.zt.config.starting_weapon_aat != "default" || level.zt.config.spawn_protection > 0 || level.zt.config.revive_time > 0 || level.zt.config.challenge_random_loadout;
}

zt_has_damage_tweaks()
{
    return level.zt.config.weapon_damage > 0 || level.zt.config.melee_damage > 0 || level.zt.config.challenge_rising_damage > 0 || level.zt.config.pap_damage_multiplier > 0 || level.zt.config.zombie_damage > 0 || level.zt.config.no_explosive_self_damage || level.zt.config.fall_damage != 0 || level.zt.config.spawn_protection > 0;
}

zt_has_box_tweaks()
{
    return level.zt.config.box_price_multiplier >= 0 || level.zt.config.fire_sale_box_price >= 0 || level.zt.config.teddy_bear_chance >= 0 || level.zt.config.box_no_repeat || level.zt.config.box_quality != "default" || level.zt.config.box_lock || level.zt.config.challenge_no_box || level.zt.config.challenge_wall_only || level.zt.config.challenge_one_box;
}

zt_has_down_tweaks()
{
    return level.zt.config.down_limit != 0 || level.zt.config.revive_time > 0 || level.zt.config.bleedout_time > 0 || level.zt.config.lose_perks_on_down != "default" || level.zt.config.keep_weapons_bleedout;
}

zt_has_pacing_tweaks()
{
    return level.zt.config.round_delay >= 0 || level.zt.config.zombie_spawn_rate > 0;
}

zt_match_tweaks_install()
{
    level endon( #"end_game" );

    // These values must be claimed before round logic starts, but a stock
    // cinematic or a slow custom-map bootstrap can legitimately last longer
    // than any wall-clock deadline. Wait for either the capability or the
    // authoritative point at which applying it would be too late.
    while ( ( !isdefined( level.zombie_vars ) || !isdefined( level.round_number ) ) && !zt_game_ready() )
        wait 0.05;

    if ( !isdefined( level.zombie_vars ) || !isdefined( level.round_number ) )
    {
        zt_match_tweaks_unavailable( "map did not expose standard Zombies match variables" );
        return;
    }

    // T7x can attach the script route after a match is already underway. Do
    // not rewrite match-owned round, curve or score baselines at that point;
    // spawn-boundary settings still have their independent player watcher.
    if ( zt_game_ready() )
    {
        zt_match_tweaks_unavailable( "round logic began before the tweak could be applied" );
        return;
    }

    if ( level.zt.config.zombie_speed > 0 )
    {
        applied = 0;
        if ( isdefined( level.zombie_vars["zombie_move_speed_multiplier"] ) )
        {
            state = zt_scale_owned_match_value( level.zombie_vars["zombie_move_speed_multiplier"], undefined, undefined, level.zt.config.zombie_speed );
            level.zt.zombie_speed_stock = state.stock;
            level.zt.zombie_speed_applied = state.applied;
            level.zombie_vars["zombie_move_speed_multiplier"] = state.applied;
            applied = 1;
        }
        if ( isdefined( level.zombie_vars["zombie_move_speed_multiplier_easy"] ) )
        {
            state = zt_scale_owned_match_value( level.zombie_vars["zombie_move_speed_multiplier_easy"], undefined, undefined, level.zt.config.zombie_speed );
            level.zt.zombie_speed_easy_stock = state.stock;
            level.zt.zombie_speed_easy_applied = state.applied;
            level.zombie_vars["zombie_move_speed_multiplier_easy"] = state.applied;
            applied = 1;
        }
        if ( applied && isdefined( level.zombie_move_speed ) )
            level.zombie_move_speed = int( level.zombie_move_speed * level.zt.config.zombie_speed / 100.0 + 0.5 );
        if ( applied )
            zt_feature( "zombie_speed", "active", "" );
        else
            zt_feature( "zombie_speed", "unavailable", "map exposes no standard zombie-speed curve" );
    }

    if ( level.zt.config.headshots_only )
    {
        level.headshots_only = 1;
        zt_feature( "headshots_only", "active", "" );
    }

    if ( level.zt.config.game_start_delay >= 0 )
    {
        if ( level flag::exists( "begin_spawning" ) && level flag::get( "begin_spawning" ) )
            zt_feature( "game_start_delay", "unavailable", "first-round spawning began before the tweak could be applied" );
        else if ( isdefined( level.zombie_vars["game_start_delay"] ) )
        {
            level.zombie_vars["game_start_delay"] = level.zt.config.game_start_delay;
            zt_feature( "game_start_delay", "active", "" );
        }
        else
            zt_feature( "game_start_delay", "unavailable", "map exposes no standard game-start delay" );
    }

    if ( level.zt.config.starting_round > 0 )
    {
        level.start_round = level.zt.config.starting_round;
        level.round_number = level.zt.config.starting_round;
        // BO3's round controller reads the obfuscated world.roundnumber value
        // and continuously mirrors it back to level.round_number. Update the
        // authoritative value so a requested start round cannot snap back to 1
        // while retaining the selected round's movement speed.
        zm::set_round_number( level.round_number );
        level.player_starting_points = level.round_number * 500;
        if ( level.round_number == 1 )
            level.zombie_move_speed = 1;
        else if ( isdefined( level.gamedifficulty ) && level.gamedifficulty == 0 && isdefined( level.zombie_vars["zombie_move_speed_multiplier_easy"] ) )
            level.zombie_move_speed = level.round_number * level.zombie_vars["zombie_move_speed_multiplier_easy"];
        else if ( isdefined( level.zombie_vars["zombie_move_speed_multiplier"] ) )
            level.zombie_move_speed = level.round_number * level.zombie_vars["zombie_move_speed_multiplier"];
        zt_feature( "starting_round", "active", "" );
    }

    if ( level.zt.config.starting_points > 0 )
    {
        level.player_starting_points = level.zt.config.starting_points;
        zt_feature( "starting_points", "active", "" );
    }

    if ( level.zt.config.player_health > 0 )
        zt_player_health_target();

    if ( level.zt.config.zombie_health > 0 )
    {
        if ( isdefined( level.zombie_vars["zombie_health_start"] ) && isdefined( level.zombie_vars["zombie_health_increase"] ) )
        {
            state = zt_scale_owned_match_value( level.zombie_vars["zombie_health_start"], undefined, undefined, level.zt.config.zombie_health );
            level.zt.zombie_health_start_stock = state.stock;
            level.zt.zombie_health_start_applied = state.applied;
            level.zombie_vars["zombie_health_start"] = state.applied;
            state = zt_scale_owned_match_value( level.zombie_vars["zombie_health_increase"], undefined, undefined, level.zt.config.zombie_health );
            level.zt.zombie_health_increase_stock = state.stock;
            level.zt.zombie_health_increase_applied = state.applied;
            level.zombie_vars["zombie_health_increase"] = state.applied;
            if ( isdefined( level.zombie_health ) )
                level.zombie_health = level.zombie_vars["zombie_health_start"];
            zt_feature( "zombie_health", "active", "" );
        }
        else
            zt_feature( "zombie_health", "unavailable", "map exposes no standard zombie-health curve" );
    }

    if ( level.zt.config.starting_weapon != "default" )
        zt_starting_weapon_apply();
    if ( level.zt.config.secondary_starting_weapon != "default" && !level.zt.config.challenge_one_weapon_slot )
        zt_secondary_starting_weapon_apply();

    // Match-owned zombie curves were claimed before round logic.  The
    // passive post-start owner may keep composing them only after this safe
    // initialization path completed; a late T7x attachment must remain
    // fail-closed for NEXT MATCH settings.
    level.zt.match_value_owner_ready = 1;
}

zt_match_tweaks_unavailable( reason )
{
    if ( level.zt.config.starting_round > 0 )
        zt_feature( "starting_round", "unavailable", reason );
    if ( level.zt.config.starting_points > 0 )
        zt_feature( "starting_points", "unavailable", reason );
    if ( level.zt.config.game_start_delay >= 0 )
        zt_feature( "game_start_delay", "unavailable", reason );
    if ( level.zt.config.player_health > 0 )
        zt_feature( "player_health", "unavailable", reason );
    if ( level.zt.config.zombie_health > 0 )
        zt_feature( "zombie_health", "unavailable", reason );
    if ( level.zt.config.zombie_speed > 0 )
        zt_feature( "zombie_speed", "unavailable", reason );
    if ( level.zt.config.headshots_only )
        zt_feature( "headshots_only", "unavailable", reason );
    if ( level.zt.config.starting_weapon != "default" )
        zt_feature( "starting_weapon", "unavailable", reason );
    if ( level.zt.config.secondary_starting_weapon != "default" )
        zt_feature( "secondary_starting_weapon", "unavailable", reason );
}

zt_starting_weapon_name( choice )
{
    if ( choice == "pistol" )
        return "pistol_standard";
    if ( choice == "burst" )
        return "pistol_burst";
    if ( choice == "smg" )
        return "smg_standard";
    if ( choice == "shotgun" )
        return "shotgun_pump";
    if ( choice == "ar" )
        return "ar_standard";
    if ( choice == "lmg" )
        return "lmg_light";
    if ( choice == "sniper" )
        return "sniper_fastbolt";
    return "";
}

zt_starts_with( text, prefix )
{
    return text.size >= prefix.size && getsubstr( text, 0, prefix.size ) == prefix;
}

zt_weapon_matches_class( weapon, choice )
{
    if ( !isdefined( weapon ) || !isdefined( weapon.name ) )
        return 0;

    name = weapon.name;
    if ( issubstr( name, "_upgraded" ) || issubstr( name, "_dw" ) )
        return 0;

    weapon_class = weapon.weapclass;
    stats_class = util::getweaponclass( weapon );
    is_sniper = stats_class == "weapon_sniper" || zt_starts_with( name, "sniper_" );

    if ( choice == "burst" )
        return weapon_class == "pistol" && ( issubstr( name, "burst" ) || issubstr( name, "93r" ) );
    if ( choice == "pistol" )
        return ( weapon_class == "pistol" || weapon_class == "pistol spread" ) && !weapon.isdualwield && !is_sniper;
    if ( choice == "smg" )
        return weapon_class == "smg" || stats_class == "weapon_smg";
    if ( choice == "shotgun" )
        return weapon_class == "spread" || stats_class == "weapon_cqb" || stats_class == "weapon_shotgun";
    if ( choice == "ar" )
        return ( weapon_class == "rifle" || stats_class == "weapon_assault" ) && !is_sniper;
    if ( choice == "lmg" )
        return weapon_class == "mg" || stats_class == "weapon_lmg";
    if ( choice == "sniper" )
        return is_sniper;
    return 0;
}

zt_find_starting_weapon( choice, excluded )
{
    if ( !isdefined( level.zombie_weapons ) )
        return level.weaponnone;

    preferred = getweapon( zt_starting_weapon_name( choice ) );
    if ( preferred != excluded && zt_starting_weapon_registry_safe( preferred ) )
        return preferred;

    weapons = getarraykeys( level.zombie_weapons );
    for ( i = 0; i < weapons.size; i++ )
    {
        if ( weapons[i] != excluded && zt_starting_weapon_registry_safe( weapons[i] ) && zt_weapon_matches_class( weapons[i], choice ) )
            return weapons[i];
    }
    return level.weaponnone;
}

zt_starting_weapon_registry_safe( weapon )
{
    if ( !zt_valid_inventory_weapon( weapon ) || !isdefined( weapon.rootweapon ) || !isdefined( level.zombie_weapons ) || !isdefined( level.zombie_weapons[weapon.rootweapon] ) )
        return 0;

    entry = level.zombie_weapons[weapon.rootweapon];
    if ( isdefined( entry.is_wonder_weapon ) && entry.is_wonder_weapon )
        return 0;

    // Limited entries are quest/map inventory even while their live quota is
    // available. Starting-loadout selection must never consume that quota.
    if ( isdefined( level.limited_weapons ) && ( isdefined( level.limited_weapons[weapon] ) || isdefined( level.limited_weapons[weapon.rootweapon] ) ) )
        return 0;

    // Do not infer quest safety from firearm class alone. Custom maps often
    // register quest inventory in zombie_weapons without setting the wonder
    // or limited flags. Require an authoritative ordinary acquisition route.
    if ( isdefined( level.zt.map_start_weapon ) && zt_same_weapon_root( weapon, level.zt.map_start_weapon ) )
        return 1;
    if ( isdefined( level.start_weapon ) && zt_same_weapon_root( weapon, level.start_weapon ) )
        return 1;
    if ( isdefined( entry.is_in_box ) && entry.is_in_box )
        return 1;
    if ( isdefined( level._spawned_wallbuys ) && zm_weapons::is_wallbuy( weapon ) )
        return 1;
    return 0;
}

zt_starting_weapon_apply()
{
    choice = level.zt.config.starting_weapon;
    if ( zt_starting_weapon_name( choice ) == "" )
    {
        zt_feature( "starting_weapon", "unavailable", "unknown weapon class" );
        return;
    }

    while ( !isdefined( level.zombie_weapons ) && !zt_game_ready() )
        wait 0.05;

    weapon = zt_find_starting_weapon( choice, level.weaponnone );
    if ( !isdefined( weapon ) || weapon == level.weaponnone )
    {
        zt_feature( "starting_weapon", "unavailable", "selected weapon is not registered by this map" );
        return;
    }

    if ( !isdefined( level.zt.map_start_weapon ) && isdefined( level.start_weapon ) )
        level.zt.map_start_weapon = level.start_weapon;
    level.zt.start_weapon_override = weapon;
    level.start_weapon = level.zt.start_weapon_override;
    zt_feature( "starting_weapon", "active", "" );
}

zt_secondary_starting_weapon_apply()
{
    if ( level.zt.config.challenge_one_weapon_slot )
    {
        zt_feature( "secondary_starting_weapon", "unavailable", "one-weapon-slot challenge takes precedence" );
        return;
    }
    choice = level.zt.config.secondary_starting_weapon;
    if ( zt_starting_weapon_name( choice ) == "" )
    {
        zt_feature( "secondary_starting_weapon", "unavailable", "unknown weapon class" );
        return;
    }

    while ( !isdefined( level.zombie_weapons ) && !zt_game_ready() )
        wait 0.05;

    excluded = level.weaponnone;
    if ( isdefined( level.zt.start_weapon_override ) )
        excluded = level.zt.start_weapon_override;
    else if ( isdefined( level.start_weapon ) )
        excluded = level.start_weapon;
    weapon = zt_find_starting_weapon( choice, excluded );
    if ( !isdefined( weapon ) || weapon == level.weaponnone )
    {
        zt_feature( "secondary_starting_weapon", "unavailable", "no second registered weapon matches the selected class" );
        return;
    }

    level.zt.secondary_start_weapon_override = weapon;
    zt_feature( "secondary_starting_weapon", "active", "" );
}

zt_player_health_target()
{
    if ( !isdefined( level.zombie_vars ) || !isdefined( level.zombie_vars["player_base_health"] ) )
    {
        if ( level.zt.config.player_health > 0 )
            zt_feature( "player_health", "unavailable", "map exposes no base player-health variable" );
        return 0;
    }

    // Keep the map's unmodified base separate from the value ZTweaks owns.
    // This makes NEXT SPAWN changes absolute instead of multiplying an old
    // setting, and lets GAME DEFAULT restore the value exactly once.
    current = level.zombie_vars["player_base_health"];
    if ( !isdefined( level.zt.player_base_health_stock ) )
        level.zt.player_base_health_stock = current;
    else if ( zt_true( level.zt.player_health_owned ) && isdefined( level.zt.player_base_health_applied ) && current != level.zt.player_base_health_applied )
    {
        // A late map/perk owner replaced our base. Adopt that value as the new
        // input instead of either fighting it or scaling our previous result.
        level.zt.player_base_health_stock = current;
        level.zt.player_health_owned = 0;
    }

    health = level.zt.player_base_health_stock;
    if ( level.zt.config.player_health > 0 )
    {
        health = int( level.zt.player_base_health_stock * level.zt.config.player_health / 100 );
        if ( health < 1 )
            health = 1;
        level.zombie_vars["player_base_health"] = health;
        level.zt.player_base_health_applied = health;
        level.zt.player_health_owned = 1;
        zt_feature( "player_health", "active", "composed with late map and perk health owners" );
    }
    else if ( zt_true( level.zt.player_health_owned ) )
    {
        if ( !isdefined( level.zt.player_base_health_applied ) || current == level.zt.player_base_health_applied )
            level.zombie_vars["player_base_health"] = health;
        level.zt.player_health_owned = 0;
        level.zt.player_base_health_applied = undefined;
        zt_feature( "player_health", "inherit", "" );
    }

    return health;
}

zt_scale_owned_match_value( current, stock, applied, percent )
{
    if ( !isdefined( stock ) || ( isdefined( applied ) && current != applied ) )
        stock = current;
    scaled = int( stock * percent / 100.0 + 0.5 );
    if ( scaled < 1 ) scaled = 1;
    result = spawnstruct();
    result.stock = stock;
    result.applied = scaled;
    return result;
}

zt_match_value_owner_watch()
{
    level endon( #"end_game" );

    // Never race the pre-round initializer. Player Health may be enabled
    // later at NEXT SPAWN, while zombie curves remain gated by the successful
    // NEXT MATCH claim above.
    while ( !zt_game_ready() )
        wait 0.05;

    while ( 1 )
    {
        wait 0.25;

        if ( level.zt.config.player_health > 0 && isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["player_base_health"] ) )
            zt_player_health_target();

        if ( zt_true( level.zt.match_value_owner_ready ) && level.zt.config.zombie_health > 0 && isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_health_start"] ) && isdefined( level.zombie_vars["zombie_health_increase"] ) )
        {
            state = zt_scale_owned_match_value( level.zombie_vars["zombie_health_start"], level.zt.zombie_health_start_stock, level.zt.zombie_health_start_applied, level.zt.config.zombie_health );
            level.zt.zombie_health_start_stock = state.stock;
            level.zt.zombie_health_start_applied = state.applied;
            level.zombie_vars["zombie_health_start"] = state.applied;

            state = zt_scale_owned_match_value( level.zombie_vars["zombie_health_increase"], level.zt.zombie_health_increase_stock, level.zt.zombie_health_increase_applied, level.zt.config.zombie_health );
            level.zt.zombie_health_increase_stock = state.stock;
            level.zt.zombie_health_increase_applied = state.applied;
            level.zombie_vars["zombie_health_increase"] = state.applied;
        }

        if ( zt_true( level.zt.match_value_owner_ready ) && level.zt.config.zombie_speed > 0 && isdefined( level.zombie_vars ) )
        {
            if ( isdefined( level.zombie_vars["zombie_move_speed_multiplier"] ) )
            {
                state = zt_scale_owned_match_value( level.zombie_vars["zombie_move_speed_multiplier"], level.zt.zombie_speed_stock, level.zt.zombie_speed_applied, level.zt.config.zombie_speed );
                level.zt.zombie_speed_stock = state.stock;
                level.zt.zombie_speed_applied = state.applied;
                level.zombie_vars["zombie_move_speed_multiplier"] = state.applied;
            }
            if ( isdefined( level.zombie_vars["zombie_move_speed_multiplier_easy"] ) )
            {
                state = zt_scale_owned_match_value( level.zombie_vars["zombie_move_speed_multiplier_easy"], level.zt.zombie_speed_easy_stock, level.zt.zombie_speed_easy_applied, level.zt.config.zombie_speed );
                level.zt.zombie_speed_easy_stock = state.stock;
                level.zt.zombie_speed_easy_applied = state.applied;
                level.zombie_vars["zombie_move_speed_multiplier_easy"] = state.applied;
            }
        }
    }
}

zt_apply_random_loadout()
{
    if ( !level.zt.config.challenge_random_loadout || level.zt.config.starting_weapon != "default" )
        return;
    if ( !isdefined( level.zombie_weapons ) )
    {
        zt_feature( "challenge_random_loadout", "unavailable", "map exposes no registered weapon pool" );
        return;
    }
    if ( !isdefined( level.start_weapon ) || level.start_weapon == level.weaponnone )
    {
        zt_feature( "challenge_random_loadout", "unavailable", "map exposes no authoritative starting-weapon replacement seam" );
        return;
    }
    if ( !isdefined( level.zt.map_start_weapon ) && isdefined( level.start_weapon ) )
        level.zt.map_start_weapon = level.start_weapon;
    keys = getarraykeys( level.zombie_weapons );
    candidates = [];
    for ( i = 0; i < keys.size; i++ )
    {
        weapon = keys[i];
        entry = level.zombie_weapons[weapon];
        // Restrict the challenge to ordinary box-eligible firearms.  The
        // registry also contains quest items, specialist weapons, offhands
        // and map-owned wonder weapons which are unsafe to grant generically.
        if ( ( !isdefined( level.zt.secondary_start_weapon_override ) || !zt_same_weapon_root( weapon, level.zt.secondary_start_weapon_override ) ) && self zt_safe_random_starting_weapon( weapon, entry ) )
            candidates[candidates.size] = weapon;
    }
    if ( candidates.size <= 0 )
    {
        zt_feature( "challenge_random_loadout", "unavailable", "map registered no compatible carried weapons" );
        return;
    }
    weapon = candidates[randomint( candidates.size )];
    self zt_remove_map_start_weapon( weapon );
    weapon = self zm_weapons::weapon_give( weapon, 0, 0, 1, 0 );
    if ( !zt_valid_inventory_weapon( weapon ) )
    {
        zt_feature( "challenge_random_loadout", "unavailable", "stock weapon grant rejected the selected firearm" );
        return;
    }
    self.zt_random_start_weapon = weapon;
    self.zt_start_primary_weapon = weapon;
    self.zt_starting_ammo_weapons = [];
    self.zt_starting_ammo_weapons[weapon] = 1;
    self switchtoweapon( weapon );
    zt_feature( "challenge_random_loadout", "active", "independent safe box firearm selected for each player" );
}

zt_safe_random_starting_weapon( weapon, entry )
{
    if ( !isdefined( weapon ) || weapon == level.weaponnone || !isdefined( weapon.rootweapon ) || !isdefined( entry ) )
        return 0;
    if ( !isdefined( entry.is_in_box ) || !entry.is_in_box || ( isdefined( entry.is_wonder_weapon ) && entry.is_wonder_weapon ) )
        return 0;
    // A spawn grant must not consume a quest/limited weapon merely because
    // its quota happens to be free. The stock box predicate below still owns
    // DLC entitlement and every map-authored receive/selection callback.
    if ( isdefined( level.limited_weapons ) && ( isdefined( level.limited_weapons[weapon] ) || isdefined( level.limited_weapons[weapon.rootweapon] ) ) )
        return 0;
    if ( !( self zm_weapons::player_can_use_content( weapon ) ) || !( zm_magicbox::treasure_chest_canplayerreceiveweapon( self, weapon, undefined ) ) )
        return 0;
    if ( !isdefined( weapon.type ) || weapon.type == "grenade" || weapon.type == "melee" || weapon.type == "special" )
        return 0;
    weapon_class = weapon.weapclass;
    return weapon_class == "pistol" || weapon_class == "pistol spread" || weapon_class == "smg" || weapon_class == "spread" || weapon_class == "rifle" || weapon_class == "mg";
}

zt_same_weapon_root( left, right )
{
    return zt_valid_inventory_weapon( left ) && zt_valid_inventory_weapon( right ) && isdefined( left.rootweapon ) && isdefined( right.rootweapon ) && left.rootweapon == right.rootweapon;
}

zt_owned_primary_weapon( weapon )
{
    if ( !zt_valid_inventory_weapon( weapon ) )
        return level.weaponnone;

    primaries = self getweaponslistprimaries();
    for ( i = 0; i < primaries.size; i++ )
    {
        if ( zt_same_weapon_root( primaries[i], weapon ) )
            return primaries[i];
    }
    return level.weaponnone;
}

zt_remove_map_start_weapon( replacement )
{
    if ( !isdefined( level.zt.map_start_weapon ) )
        return;

    primaries = self getweaponslistprimaries();
    for ( i = 0; i < primaries.size; i++ )
    {
        if ( zt_same_weapon_root( primaries[i], level.zt.map_start_weapon ) && !zt_same_weapon_root( primaries[i], replacement ) )
            self zm_weapons::weapon_take( primaries[i] );
    }
}

zt_apply_player_starting_weapon()
{
    if ( level.zt.config.starting_weapon == "default" )
        return;

    if ( !isdefined( level.zt.start_weapon_override ) )
        zt_starting_weapon_apply();
    if ( !isdefined( level.zt.start_weapon_override ) || level.zt.start_weapon_override == level.weaponnone )
        return;

    weapon = level.zt.start_weapon_override;
    self zt_remove_map_start_weapon( weapon );
    owned_weapon = self zt_owned_primary_weapon( weapon );
    if ( !zt_valid_inventory_weapon( owned_weapon ) )
        owned_weapon = self zm_weapons::weapon_give( weapon, 0, 0, 1, 0 );
    if ( !zt_valid_inventory_weapon( owned_weapon ) )
    {
        zt_feature( "starting_weapon", "unavailable", "stock weapon grant rejected the selected firearm" );
        return;
    }

    self.zt_start_primary_weapon = owned_weapon;
    self.zt_starting_ammo_weapons = [];
    self.zt_starting_ammo_weapons[owned_weapon] = 1;
    level.start_weapon = weapon;
    self switchtoweapon( owned_weapon );
}

zt_upgraded_weapon( weapon )
{
    if ( !zt_valid_inventory_weapon( weapon ) || !( zm_weapons::can_upgrade_weapon( weapon ) ) )
        return level.weaponnone;
    return zm_weapons::get_upgrade_weapon( weapon, 0 );
}

zt_upgrade_starting_slot( weapon, feature )
{
    upgraded = zt_upgraded_weapon( weapon );
    if ( upgraded == level.weaponnone )
    {
        zt_feature( feature, "unavailable", "the selected starting weapon has no registered Pack-a-Punch upgrade" );
        return weapon;
    }
    upgraded_owned = self zt_owned_primary_weapon( upgraded );
    if ( self hasweapon( weapon ) )
        self zm_weapons::weapon_take( weapon );
    if ( !zt_valid_inventory_weapon( upgraded_owned ) )
        upgraded_owned = self zm_weapons::weapon_give( upgraded, 1, 0, 1, 0 );
    if ( !zt_valid_inventory_weapon( upgraded_owned ) )
    {
        restored = self zm_weapons::weapon_give( weapon, 0, 0, 1, 0 );
        zt_feature( feature, "unavailable", "stock weapon grant rejected the registered Pack-a-Punch upgrade" );
        if ( zt_valid_inventory_weapon( restored ) )
            return restored;
        return weapon;
    }
    if ( isdefined( self.zt_starting_ammo_weapons ) )
    {
        self.zt_starting_ammo_weapons[weapon] = undefined;
        self.zt_starting_ammo_weapons[upgraded_owned] = 1;
    }
    zt_feature( feature, "active", "" );
    return upgraded_owned;
}

zt_apply_player_secondary_starting_weapon()
{
    if ( level.zt.config.secondary_starting_weapon == "default" )
        return;

    if ( !isdefined( level.zt.secondary_start_weapon_override ) )
        zt_secondary_starting_weapon_apply();
    if ( !isdefined( level.zt.secondary_start_weapon_override ) || level.zt.secondary_start_weapon_override == level.weaponnone )
        return;

    weapon = level.zt.secondary_start_weapon_override;
    owned_weapon = self zt_owned_primary_weapon( weapon );
    if ( !zt_valid_inventory_weapon( owned_weapon ) )
    {
        primaries = self getweaponslistprimaries();
        if ( primaries.size >= zm_utility::get_player_weapon_limit( self ) )
        {
            zt_feature( "secondary_starting_weapon", "unavailable", "map's starting loadout already fills every primary slot" );
            return;
        }
        owned_weapon = self zm_weapons::weapon_give( weapon, 0, 0, 1, 0 );
    }
    if ( !zt_valid_inventory_weapon( owned_weapon ) )
    {
        zt_feature( "secondary_starting_weapon", "unavailable", "stock weapon grant rejected the selected firearm" );
        return;
    }
    self.zt_start_secondary_weapon = owned_weapon;
    self.zt_starting_ammo_weapons[owned_weapon] = 1;
}

zt_apply_starting_upgrades()
{
    mode = level.zt.config.starting_weapon_upgraded;
    if ( mode == "default" )
        return;
    primary = undefined;
    random_primary = isdefined( self.zt_random_start_weapon );
    if ( random_primary )
        primary = self.zt_random_start_weapon;
    else if ( isdefined( self.zt_start_primary_weapon ) )
        primary = self.zt_start_primary_weapon;
    if ( ( mode == "primary" || mode == "both" ) && isdefined( primary ) )
    {
        self.zt_start_primary_weapon = self zt_upgrade_starting_slot( primary, "starting_weapon_upgraded" );
        if ( random_primary )
            self.zt_random_start_weapon = self.zt_start_primary_weapon;
        self switchtoweapon( self.zt_start_primary_weapon );
    }
    if ( ( mode == "secondary" || mode == "both" ) && isdefined( self.zt_start_secondary_weapon ) )
        self.zt_start_secondary_weapon = self zt_upgrade_starting_slot( self.zt_start_secondary_weapon, "starting_weapon_upgraded" );
}

zt_disable_stock_aat_install()
{
    level endon( #"end_game" );
    // Register exemptions only after the stock AAT table is initialized.
    // Applying them before the intro completes would reopen a sensitive
    // T7x startup seam. The starting-weapon AAT grant is separately gated.
    while ( !zt_game_ready() )
        wait 0.25;

    level.zt.aat_exempt_owned = [];
    level.zt.aat_exempt_yielded = [];
    elapsed = 0;
    while ( 1 )
    {
        if ( isdefined( level.aat_in_use ) && !level.aat_in_use )
        {
            zt_transition_feature( "disable_stock_aat", "active", "" );
            return;
        }
        if ( !isdefined( level.aat_exemptions ) || !isdefined( level.zombie_weapons_upgraded ) )
        {
            if ( elapsed >= 20 )
                zt_transition_feature( "disable_stock_aat", "unavailable", "map did not initialize the stock Alternate Ammo Type system" );
            elapsed += 0.5;
            wait 0.5;
            continue;
        }

        weapons = getarraykeys( level.zombie_weapons_upgraded );
        active = 0;
        yielded = 0;
        for ( i = 0; i < weapons.size; i++ )
        {
            weapon = weapons[i];
            if ( zt_true( level.zt.aat_exempt_owned[weapon] ) )
            {
                if ( !aat::is_exempt_weapon( weapon ) )
                {
                    level.zt.aat_exempt_owned[weapon] = 0;
                    level.zt.aat_exempt_yielded[weapon] = 1;
                }
                else
                    active++;
                continue;
            }
            if ( zt_true( level.zt.aat_exempt_yielded[weapon] ) )
            {
                yielded++;
                continue;
            }
            // Keep map-authored exemptions untouched. Only adopt weapons
            // which the stock Pack-a-Punch path currently accepts for AATs.
            if ( !zm_weapons::weapon_supports_aat( weapon ) )
                continue;
            aat::register_aat_exemption( weapon );
            level.zt.aat_exempt_owned[weapon] = 1;
            active++;
        }
        if ( yielded > 0 )
            zt_transition_feature( "disable_stock_aat", "degraded", "" );
        else if ( active > 0 )
            zt_transition_feature( "disable_stock_aat", "active", "" );
        else if ( elapsed >= 20 )
            zt_transition_feature( "disable_stock_aat", "unavailable", "map did not register any supported Alternate Ammo Types" );
        elapsed += 0.5;
        wait 0.5;
    }
}

zt_starting_aat_candidates()
{
    candidates = [];
    if ( !isdefined( level.aat ) )
        return candidates;
    if ( isdefined( level.aat["zm_aat_dead_wire"] ) ) candidates[candidates.size] = "zm_aat_dead_wire";
    if ( isdefined( level.aat["zm_aat_blast_furnace"] ) ) candidates[candidates.size] = "zm_aat_blast_furnace";
    if ( isdefined( level.aat["zm_aat_fire_works"] ) ) candidates[candidates.size] = "zm_aat_fire_works";
    if ( isdefined( level.aat["zm_aat_thunder_wall"] ) ) candidates[candidates.size] = "zm_aat_thunder_wall";
    if ( isdefined( level.aat["zm_aat_turned"] ) ) candidates[candidates.size] = "zm_aat_turned";
    return candidates;
}

zt_resolve_starting_aat()
{
    requested = level.zt.config.starting_weapon_aat;
    if ( requested == "default" )
        return "";
    if ( requested == "random" )
    {
        candidates = zt_starting_aat_candidates();
        if ( candidates.size == 0 )
            return "";
        return candidates[randomint( candidates.size )];
    }
    if ( isdefined( level.aat ) && isdefined( level.aat[requested] ) )
        return requested;
    return "";
}

zt_apply_starting_aat_slot( weapon, name )
{
    if ( !zt_valid_inventory_weapon( weapon ) || !( zm_weapons::weapon_supports_aat( weapon ) ) )
        return 0;
    self aat::acquire( weapon, name );
    aat_state = self aat::getaatonweapon( weapon );
    if ( !isdefined( aat_state ) )
        return 0;
    return 1;
}

zt_apply_starting_aat()
{
    requested = level.zt.config.starting_weapon_aat;
    if ( requested == "default" )
        return;
    if ( level.zt.config.disable_stock_aat )
    {
        zt_feature( "starting_weapon_aat", "unavailable", "global stock AAT disable takes precedence" );
        return;
    }
    if ( !isdefined( level.aat_in_use ) || !level.aat_in_use || !isdefined( level.aat ) || !isdefined( self.aat ) )
    {
        zt_feature( "starting_weapon_aat", "unavailable", "map did not initialize the stock Alternate Ammo Type system" );
        return;
    }

    name = zt_resolve_starting_aat();
    if ( name == "" )
    {
        if ( requested == "random" )
            zt_feature( "starting_weapon_aat", "unavailable", "map did not register any supported Alternate Ammo Types" );
        else
            zt_feature( "starting_weapon_aat", "unavailable", "selected Alternate Ammo Type is not registered by this map" );
        return;
    }

    mode = level.zt.config.starting_weapon_upgraded;
    requested_slots = 0;
    applied_slots = 0;
    if ( mode == "primary" || mode == "both" )
    {
        requested_slots++;
        if ( isdefined( self.zt_start_primary_weapon ) && self zt_apply_starting_aat_slot( self.zt_start_primary_weapon, name ) )
            applied_slots++;
    }
    if ( mode == "secondary" || mode == "both" )
    {
        requested_slots++;
        if ( isdefined( self.zt_start_secondary_weapon ) && self zt_apply_starting_aat_slot( self.zt_start_secondary_weapon, name ) )
            applied_slots++;
    }

    if ( applied_slots == 0 )
        zt_feature( "starting_weapon_aat", "unavailable", "no selected Pack-a-Punched starting weapon supports Alternate Ammo Types" );
    else if ( applied_slots < requested_slots )
        zt_feature( "starting_weapon_aat", "degraded", "Alternate Ammo Type applied only to compatible Pack-a-Punched starting weapons" );
    else
        zt_feature( "starting_weapon_aat", "active", "" );
}

zt_apply_starting_ammo()
{
    percent = level.zt.config.starting_ammo;
    reserve = level.zt.config.reserve_ammo;
    if ( percent == 0 && reserve <= 0 )
        return;
    weapons = self getweaponslistprimaries();
    applied = 0;
    for ( i = 0; i < weapons.size; i++ )
    {
        weapon = weapons[i];
        if ( !self zt_is_starting_ammo_weapon( weapon ) )
            continue;
        maxstock = weapon.maxammo;
        maxclip = weapon.clipsize;
        if ( percent != 0 )
        {
            if ( percent < 0 )
            {
                self setweaponammoclip( weapon, 0 );
                self setweaponammostock( weapon, 0 );
            }
            else
            {
                self setweaponammoclip( weapon, int( maxclip * percent / 100.0 + 0.5 ) );
                reserve_target = maxstock;
                if ( reserve > 0 ) reserve_target = int( maxstock * reserve / 100.0 + 0.5 );
                self setweaponammostock( weapon, int( reserve_target * percent / 100.0 + 0.5 ) );
            }
        }
        else if ( reserve > 0 )
            self setweaponammostock( weapon, int( maxstock * reserve / 100.0 + 0.5 ) );
        applied++;
    }
    if ( percent != 0 && applied > 0 )
        zt_feature( "starting_ammo", "active", "" );
    if ( reserve > 0 && applied > 0 )
        zt_feature( "reserve_ammo", "degraded", "weapon assets still own the absolute engine ammo ceiling" );
}

zt_is_starting_ammo_weapon( weapon )
{
    return isdefined( self.zt_starting_ammo_weapons ) && isdefined( self.zt_starting_ammo_weapons[weapon] );
}

zt_apply_random_starting_perks()
{
    if ( level.zt.config.challenge_no_perks )
        return;
    count = level.zt.config.random_starting_perks;
    feature = "random_starting_perks";
    if ( level.zt.config.start_all_perks )
    {
        count = 999;
        feature = "start_all_perks";
    }
    if ( count <= 0 )
        return;

    elapsed = 0;
    while ( ( !isdefined( level._custom_perks ) || !isdefined( self.num_perks ) ) && elapsed < 5 )
    {
        wait 0.05;
        elapsed += 0.05;
    }

    if ( !isdefined( level._custom_perks ) || !isdefined( self.num_perks ) )
    {
        zt_feature( feature, "unavailable", "map exposes no registered perk list" );
        return;
    }

    perks = getarraykeys( level._custom_perks );
    if ( perks.size <= 0 )
    {
        zt_feature( feature, "unavailable", "map registered no perks" );
        return;
    }

    selected = [];
    granted = 0;
    while ( granted < count && granted < perks.size )
    {
        start = randomint( perks.size );
        found = 0;
        for ( offset = 0; offset < perks.size; offset++ )
        {
            index = ( start + offset ) % perks.size;
            perk = perks[index];
            if ( !self hasperk( perk ) && !isdefined( selected[perk] ) )
            {
                selected[perk] = 1;
                self zm_perks::give_perk( perk, 0 );
                granted++;
                found = 1;
                break;
            }
        }
        if ( !found )
            break;
    }

    if ( granted > 0 )
        zt_feature( feature, "active", "" );
    else
        zt_feature( feature, "unavailable", "player already owns every registered perk" );
}

zt_starting_grenade_weapon()
{
    name = "";
    if ( level.zt.config.starting_grenade == "frag" )
        name = "frag_grenade";
    else if ( level.zt.config.starting_grenade == "semtex" )
        name = "sticky_grenade";
    weapon = getweapon( name );
    if ( name != "" && weapon != level.weaponnone && zm_utility::is_lethal_grenade( weapon ) )
        return weapon;
    return level.weaponnone;
}

zt_starting_equipment_weapon()
{
    name = "";
    if ( level.zt.config.starting_equipment == "monkey" )
        name = "cymbal_monkey";
    else if ( level.zt.config.starting_equipment == "emp" )
        name = "emp_grenade";
    if ( name != "" )
    {
        weapon = getweapon( name );
        if ( weapon != level.weaponnone && zm_utility::is_tactical_grenade( weapon ) )
            return weapon;
    }
    else if ( level.zt.config.starting_equipment == "mine" && isdefined( level.placeable_mines ) )
    {
        for ( i = 0; i < 2; i++ )
        {
            if ( i == 0 )
                name = "bouncingbetty";
            else
                name = "claymore";
            weapon = getweapon( name );
            if ( weapon != level.weaponnone && zm_utility::is_placeable_mine( weapon ) )
                return weapon;
        }
    }
    return level.weaponnone;
}

zt_spawn_count( requested, maximum )
{
    if ( requested <= 0 )
        return maximum;
    if ( maximum > 0 && requested > maximum )
        return maximum;
    return requested;
}

zt_apply_starting_throwables()
{
    if ( level.zt.config.starting_grenade != "default" )
    {
        weapon = zt_starting_grenade_weapon();
        if ( weapon == level.weaponnone )
            zt_feature( "starting_grenade", "unavailable", "selected grenade is not registered by this map" );
        else
        {
            self zm_weapons::weapon_give( weapon, 0, 0, 1, 0 );
            zt_feature( "starting_grenade", "active", "" );
        }
    }

    if ( level.zt.config.starting_equipment != "default" )
    {
        weapon = zt_starting_equipment_weapon();
        if ( weapon == level.weaponnone )
            zt_feature( "starting_equipment", "unavailable", "selected equipment is not registered by this map" );
        else
        {
            self zm_weapons::weapon_give( weapon, 0, 0, 1, 0 );
            zt_feature( "starting_equipment", "active", "" );
        }
    }

    // weapon_give publishes the active offhand slot asynchronously. Inventory
    // initialization owns the count after that stock assignment has settled.
    wait 0.05;
}

zt_apply_spawn_tweaks()
{
    self endon( #"disconnect" );

    // Snapshot only the primaries supplied by the stock spawn pipeline. The
    // explicit/random paths replace this set, secondary selection extends it,
    // and upgrades exchange the base asset for its upgraded asset. This keeps
    // Starting Ammo away from unrelated quest weapons retained by the player.
    self.zt_random_start_weapon = undefined;
    self.zt_start_primary_weapon = undefined;
    self.zt_start_secondary_weapon = undefined;
    self.zt_starting_ammo_weapons = [];
    spawn_weapons = self getweaponslistprimaries();
    for ( spawn_index = 0; spawn_index < spawn_weapons.size; spawn_index++ )
        self.zt_starting_ammo_weapons[spawn_weapons[spawn_index]] = 1;

    self zt_apply_random_loadout();
    self zt_apply_player_starting_weapon();
    self zt_apply_player_secondary_starting_weapon();
    self zt_apply_starting_upgrades();
    self zt_apply_starting_aat();
    self zt_apply_starting_ammo();
    self zt_apply_starting_throwables();

    if ( level.zt.config.player_health > 0 || zt_true( self.zt_player_health_owned ) )
    {
        health_was_owned = zt_true( self.zt_player_health_owned );
        previous_base = 0;
        if ( isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["player_base_health"] ) )
            previous_base = level.zombie_vars["player_base_health"];
        current_max = self.maxhealth;
        health = zt_player_health_target();
        if ( health > 0 && ( level.zt.config.player_health > 0 || health_was_owned ) )
        {
            // Preserve an already-restored perk/map contribution instead of
            // replacing the player's composed maximum with the bare base.
            bonus = current_max - previous_base;
            if ( bonus < 0 ) bonus = 0;
            composed = health + bonus;
            self setmaxhealth( composed );
            self.health = composed;
        }
        self.zt_player_health_owned = level.zt.config.player_health > 0;
    }

    self zt_apply_random_starting_perks();

    if ( level.zt.config.spawn_protection > 0 )
    {
        self.zt_spawn_protection_until = gettime() + level.zt.config.spawn_protection * 1000;
        zt_feature( "spawn_protection", "active", "" );
    }

    self zt_update_revive_time_owner();

    self zt_apply_player_speed();

    inventory_enabled = level.zt.config.max_grenades > 0 || level.zt.config.max_equipment > 0 || level.zt.config.starting_grenade_count > 0 || level.zt.config.starting_equipment_count > 0;
    max_enabled = level.zt.config.max_grenades > 0 || level.zt.config.max_equipment > 0 || level.zt.config.max_ammo_reload > 0;
    if ( !inventory_enabled && zt_true( self.zt_inventory_cap_watch ) )
    {
        self notify( #"zt_stop_inventory_cap_watch" );
        self.zt_inventory_cap_watch = 0;
    }
    if ( inventory_enabled && !zt_true( self.zt_inventory_cap_watch ) )
    {
        self.zt_inventory_cap_watch = 1;
        self thread zt_inventory_cap_watch();
    }

    if ( !max_enabled && zt_true( self.zt_max_ammo_watch ) )
    {
        self notify( #"zt_stop_max_ammo_watch" );
        self.zt_max_ammo_watch = 0;
    }
    if ( max_enabled && !zt_true( self.zt_max_ammo_watch ) )
    {
        self.zt_max_ammo_watch = 1;
        self thread zt_max_ammo_watch();
    }

    if ( level.zt.config.max_grenades <= 0 && zt_true( self.zt_grenade_round_refill_watch ) )
    {
        self notify( #"zt_stop_grenade_round_refill_watch" );
        self.zt_grenade_round_refill_watch = 0;
    }
    if ( level.zt.config.max_grenades > 0 && !zt_true( self.zt_grenade_round_refill_watch ) )
    {
        self.zt_grenade_round_refill_watch = 1;
        self thread zt_grenade_round_refill_watch();
    }

    self.zt_last_lethal = undefined;
    self.zt_last_tactical = undefined;
    self.zt_last_placeable = undefined;
    self.zt_lethal_reserve = 0;
    self.zt_tactical_reserve = 0;
    self.zt_placeable_reserve = 0;
    self zt_initialize_inventory();
}

zt_apply_player_speed()
{
    current = self getmovespeedscale();
    if ( level.zt.config.player_speed > 0 )
    {
        // Compose with the scale the map/spawn pipeline supplied. Temporary
        // effects commonly save our published value, install an absolute
        // slow/boost, then restore the saved value. Remember the root owner
        // so that restoration cannot become a fresh base and compound us.
        if ( zt_true( self.zt_player_speed_owned ) && isdefined( self.zt_player_speed_applied ) && current != self.zt_player_speed_applied )
        {
            if ( isdefined( self.zt_player_speed_restore_applied ) && abs( current - self.zt_player_speed_restore_applied ) < 0.001 )
            {
                self.zt_player_speed_base = self.zt_player_speed_restore_base;
                self.zt_player_speed_restore_applied = undefined;
                self.zt_player_speed_restore_base = undefined;
            }
            else
            {
                if ( !isdefined( self.zt_player_speed_restore_applied ) )
                {
                    self.zt_player_speed_restore_applied = self.zt_player_speed_applied;
                    self.zt_player_speed_restore_base = self.zt_player_speed_base;
                }
                if ( isdefined( self.movementspeedmodifier ) && abs( current - self.movementspeedmodifier ) < 0.001 )
                    self.zt_player_speed_base = current * 100.0 / level.zt.config.player_speed;
                else
                    self.zt_player_speed_base = current;
            }
        }
        else if ( !zt_true( self.zt_player_speed_owned ) || !isdefined( self.zt_player_speed_applied ) )
            self.zt_player_speed_base = current;
        // Zero can be a scripted movement lock. Scaling it must keep it zero.
        if ( !isdefined( self.zt_player_speed_base ) || self.zt_player_speed_base < 0 )
            self.zt_player_speed_base = 1.0;
        self.zt_player_speed_applied = self.zt_player_speed_base * level.zt.config.player_speed / 100.0;
        self setmovespeedscale( self.zt_player_speed_applied );
        self.zt_player_speed_owned = 1;
        zt_feature( "player_speed", "active", "composed with the map's spawn movement scale" );
        if ( !zt_true( self.zt_player_speed_watch ) )
        {
            self.zt_player_speed_watch = 1;
            self thread zt_player_speed_owner_watch();
        }
    }
    else if ( zt_true( self.zt_player_speed_owned ) )
    {
        // Do not erase a map/perk effect that replaced our value meanwhile.
        if ( isdefined( self.zt_player_speed_applied ) && current == self.zt_player_speed_applied && isdefined( self.zt_player_speed_base ) )
            self setmovespeedscale( self.zt_player_speed_base );
        self.zt_player_speed_owned = 0;
        self.zt_player_speed_base = undefined;
        self.zt_player_speed_applied = undefined;
        self.zt_player_speed_restore_base = undefined;
        self.zt_player_speed_restore_applied = undefined;
        zt_feature( "player_speed", "inherit", "" );
        if ( zt_true( self.zt_player_speed_watch ) )
        {
            self notify( #"zt_stop_player_speed_watch" );
            self.zt_player_speed_watch = 0;
        }
    }
}

zt_player_speed_owner_watch()
{
    self endon( #"disconnect" );
    self endon( #"zt_stop_player_speed_watch" );
    level endon( #"end_game" );
    while ( 1 )
    {
        wait 0.1;
        self zt_apply_player_speed();
    }
}

zt_player_watch()
{
    level endon( #"end_game" );

    // Keep the T6/T7 player-listener boundary identical.  A cinematic or
    // initial connection still owns its players until round logic begins;
    // zt_player_spawn_watch catches up players already in play afterwards.
    while ( !zt_game_ready() )
        wait 0.1;

    if ( zt_character_coop_apply_enabled() )
        level thread zt_character_coop_assign();

    while ( 1 )
    {
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            player = players[i];
            if ( !zt_true( player.zt_player_watch ) )
            {
                player.zt_player_watch = 1;
                apply_current = isdefined( player.sessionstate ) && player.sessionstate == "playing";
                player thread zt_player_spawn_watch( apply_current );
                if ( zt_character_preference_requested() )
                    player thread zt_character_preference_apply();
                if ( getdvarint( "zt_character_coop_probe" ) == 1 || zt_character_coop_apply_enabled() )
                    player thread zt_character_coop_probe_request();
                // Stock refires player_downed for perked players. The watcher
                // debounces that notification and stays passive at DEFAULT.
            }
        }
        wait 0.25;
    }
}

// Optional map-owned adapter. Never infer a named roster from skins/map names,
// or import zm_usermap (its autoexec also registers clientfields).
zt_character_custom_binding()
{
    if ( !isdefined( level.zt_character_adapter ) || !isarray( level.zt_character_adapter ) )
        return undefined;
    binding = level.zt_character_adapter;
    if ( !isdefined( binding["version"] ) || !isint( binding["version"] ) || binding["version"] != 1 ||
        !isdefined( binding["replay_safe"] ) || !isint( binding["replay_safe"] ) || binding["replay_safe"] != 1 )
        return undefined;
    if ( !isdefined( binding["roster"] ) || !isstring( binding["roster"] ) )
        return undefined;
    roster = binding["roster"];
    if ( roster != "victis" && roster != "mob" && roster != "origins" && roster != "soe" && roster != "primis" && roster != "ultimis" )
        return undefined;
    if ( !isdefined( level.givecustomcharacters ) || !isdefined( binding["callback"] ) || binding["callback"] != level.givecustomcharacters )
        return undefined;
    if ( !isdefined( binding["indices"] ) || !isarray( binding["indices"] ) || binding["indices"].size != 4 ||
        !isdefined( binding["required_slot"] ) || !isint( binding["required_slot"] ) || binding["required_slot"] < -1 || binding["required_slot"] > 3 ||
        !isdefined( binding["ready"] ) || !isint( binding["ready"] ) || ( binding["ready"] != 0 && binding["ready"] != 1 ) )
        return undefined;
    indices = binding["indices"];
    for ( i = 0; i < 4; i++ )
    {
        if ( !isdefined( indices[i] ) || !isint( indices[i] ) || indices[i] < 0 || indices[i] > 31 )
            return undefined;
        for ( j = 0; j < i; j++ )
            if ( indices[j] == indices[i] ) return undefined;
    }
    return binding;
}

zt_character_custom_dvar()
{
    binding = zt_character_custom_binding();
    if ( !isdefined( binding ) ) return "";
    return "scr_zt_char_" + binding["roster"];
}

// Excludes the live ready bit: a map may clear it during a temporary body.
// Everything defining the cast must stay identical through request + commit.
zt_character_custom_stamp()
{
    if ( !isdefined( level.zt_character_adapter ) ) return "stock";
    binding = zt_character_custom_binding();
    if ( !isdefined( binding ) ) return "";
    indices = binding["indices"];
    return binding["roster"] + ":" + binding["required_slot"] + ":" + indices[0] + ":" + indices[1] + ":" + indices[2] + ":" + indices[3];
}

zt_character_decode_index( index )
{
    if ( !isdefined( index ) || !isint( index ) ) return -1;
    if ( !isdefined( level.zt_character_adapter ) )
    {
        if ( index >= 0 && index < 4 ) return index;
        return -1;
    }
    binding = zt_character_custom_binding();
    if ( !isdefined( binding ) ) return -1;
    indices = binding["indices"];
    for ( slot = 0; slot < 4; slot++ )
        if ( indices[slot] == index ) return slot;
    return -1;
}

zt_character_encode_index( slot )
{
    if ( !isdefined( slot ) || !isint( slot ) || slot < 0 || slot > 3 ) return -1;
    if ( !isdefined( level.zt_character_adapter ) ) return slot;
    binding = zt_character_custom_binding();
    if ( !isdefined( binding ) ) return -1;
    indices = binding["indices"];
    return indices[slot];
}

zt_character_route_unchanged( map_name, mode, preference_dvar, stamp, callback )
{
    return isdefined( level.givecustomcharacters ) && level.givecustomcharacters == callback &&
        zt_character_postspawn_dvar( map_name, mode ) == preference_dvar && zt_character_custom_stamp() == stamp;
}

zt_character_custom_applied( players, original, target )
{
    if ( !isdefined( level.zt_character_adapter ) ) return;
    // Canonical roster slots; all native indices/callbacks are already committed.
    // The map retains ownership of its quest/role fields, attachments and VO.
    level notify( #"zt_character_preferences_applied", players, original, target );
}

// Stock routes or an explicit, validated map-owned roster declaration.
zt_character_postspawn_dvar( map_name, mode )
{
    if ( mode != "zclassic" )
        return "";
    // A malformed opt-in must not fall through to a stock-name guess.
    if ( isdefined( level.zt_character_adapter ) )
        return zt_character_custom_dvar();
    if ( map_name == "zm_zod" )
        return "scr_zt_char_soe";
    if ( map_name == "zm_factory" || map_name == "zm_castle" || map_name == "zm_island" || map_name == "zm_stalingrad" || map_name == "zm_genesis" )
        return "scr_zt_char_primis";
    if ( map_name == "zm_tomb" )
        return "scr_zt_char_origins";
    if ( map_name == "zm_prototype" || map_name == "zm_asylum" || map_name == "zm_sumpf" || map_name == "zm_theater" || map_name == "zm_cosmodrome" || map_name == "zm_temple" || map_name == "zm_moon" )
        return "scr_zt_char_ultimis";
    return "";
}

zt_character_preference_requested()
{
    preference_dvar = zt_character_postspawn_dvar( getdvarstring( "mapname" ), getdvarstring( "g_gametype" ) );
    if ( preference_dvar == "" )
        return false;
    requested = getdvarstring( preference_dvar );
    return requested == "0" || requested == "1" || requested == "2" || requested == "3";
}

// A saved solo preference is applied after stock has entered the round.
// Unknown maps, RANDOM, and multiplayer never alter stock character state.
// The map's own callback remains responsible for complete identity fields.
zt_character_preference_apply()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    // The catch-up hook may fire during the intro, before stock round logic
    // and character assignment are ready. Match the poller's lifecycle gate.
    while ( !zt_game_ready() )
        wait 0.1;
    if ( getdvarint( "zt_character_probe" ) == 1 || getdvarint( "zt_character_delay_probe" ) == 1 )
        return;
    map_name = getdvarstring( "mapname" );
    mode = getdvarstring( "g_gametype" );
    preference_dvar = zt_character_postspawn_dvar( map_name, mode );
    if ( preference_dvar == "" )
        return;
    requested = getdvarstring( preference_dvar );
    if ( requested != "0" && requested != "1" && requested != "2" && requested != "3" )
        return;
    players = getplayers();
    if ( players.size != 1 || !level flag::get( "solo_game" ) || !isdefined( level.givecustomcharacters ) )
        return;
    callback = level.givecustomcharacters;
    stamp = zt_character_custom_stamp();
    if ( !zt_character_wait_identity_ready( players ) )
        return;
    if ( !zt_character_route_unchanged( map_name, mode, preference_dvar, stamp, callback ) ) return;
    players = getplayers();
    if ( !isdefined( self.characterindex ) || !isdefined( self.sessionstate ) || self.sessionstate != "playing" || players.size != 1 || !level flag::get( "solo_game" ) )
        return;
    original = zt_character_decode_index( self.characterindex );
    if ( original < 0 || original > 3 ) return;
    // Retain the validated match-start snapshot across any temporary-body wait.
    selected = int( requested );
    if ( original == selected )
    {
        if ( issubstr( zt_version(), ".d" ) )
            self iprintlnbold( "ZT preferred character already selected: " + selected );
        return;
    }
    // The stock callbacks own body, hands, exert voice, and per-map role
    // fields. Clear only stale references to this player before reapplying.
    if ( !isdefined( level.zt_character_adapter ) && isdefined( level.rich_sq_player ) && level.rich_sq_player == self )
        level.rich_sq_player = undefined;
    if ( zt_character_owns_radio_role( map_name ) && isdefined( level.sndradioa ) && level.sndradioa == self )
        level.sndradioa = undefined;
    self.characterindex = zt_character_encode_index( selected );
    self zt_character_apply_identity( map_name );
    zt_character_refresh_ultimis_roles( map_name );
    old_cast = []; new_cast = [];
    old_cast[0] = original; new_cast[0] = selected;
    zt_character_custom_applied( players, old_cast, new_cast );
    if ( issubstr( zt_version(), ".d" ) )
        self iprintlnbold( "ZT preferred character: " + map_name + " " + original + " -> " + self.characterindex );
}

zt_character_owns_radio_role( map_name )
{
    if ( isdefined( level.zt_character_adapter ) ) return false;
    return map_name == "zm_factory" || map_name == "zm_castle" || map_name == "zm_tomb" ||
        zt_character_postspawn_dvar( map_name, "zclassic" ) == "scr_zt_char_ultimis";
}

zt_character_wait_identity_ready( players )
{
    callback = level.givecustomcharacters;
    stamp = zt_character_custom_stamp();
    if ( stamp == "" ) return false;
    // A delayed preference must not replay a human body over Beast mode,
    // Zombie Blood or a down. Only this worker waits; gameplay stays stock.
    for ( attempt = 0; attempt < 240; attempt++ )
    {
        current = getplayers();
        if ( current.size != players.size || !isdefined( level.givecustomcharacters ) || level.givecustomcharacters != callback )
            return false;
        if ( zt_character_custom_stamp() != stamp ) return false;
        ready = 1;
        if ( isdefined( level.zt_character_adapter ) )
        {
            binding = zt_character_custom_binding();
            if ( !isdefined( binding ) ) return false;
            ready = binding["ready"];
        }
        foreach ( player in players )
        {
            if ( !isdefined( player ) || !isplayer( player ) )
                return false;
            present = 0;
            foreach ( member in current )
                if ( member == player ) present = 1;
            if ( !present ) return false;
            if ( !isdefined( player.characterindex ) || !isdefined( player.sessionstate ) || player.sessionstate != "playing" || !isalive( player ) ||
                player laststand::player_is_in_laststand() || zt_true( player.altbody ) || zt_true( player.beastmode ) )
                ready = 0;
            if ( isdefined( player.zombie_vars ) && zt_true( player.zombie_vars["zombie_powerup_zombie_blood_on"] ) )
                ready = 0;
        }
        if ( ready ) return true;
        wait 0.25;
    }
    if ( isdefined( players[0] ) )
        players[0] zt_notice( 1, "ZTweaks: character preferences skipped; a temporary player state remained active." );
    return false;
}

zt_character_apply_identity( map_name )
{
    // The stock spawn callback rebuilds the character, but also resets speed.
    // Preserve the live movement owner (map effects/perks/ZTweaks), not 1.0.
    movement = self getmovespeedscale();
    self [[ level.givecustomcharacters ]]();
    self setmovespeedscale( movement );
    if ( isdefined( level.zt_character_adapter ) ) return;
    if ( zt_character_postspawn_dvar( map_name, "zclassic" ) != "scr_zt_char_ultimis" )
        return;

    // The shared BO3 character asset order is Dempsey, Nikolai, Richtofen,
    // Takeo. Some remaster favorite-weapon switches retain BO1's 2/3 order;
    // they are NOT evidence for swapping the saved/body indices. Explicitly
    // refresh the existing audio field, including Nacht/Verruckt callbacks
    // which do not refresh exert voice themselves. No new clientfields.
    self zm_audio::setexertvoice( self.characterindex + 1 );
    self.talks_in_danger = self.characterindex == 2;
    if ( map_name == "zm_moon" )
    {
        // A co-op reply can arrive after someone collects/enables their PES.
        // Do not leave the callback's bare-body style on a suited player.
        // Use the map's published cosmetic callback only: no re-give, equip
        // notification, oxygen change, or new activation animation.
        gasmask = getweapon( "equip_gasmask" );
        if ( self zm_equipment::has_player_equipment( gasmask ) && isdefined( level.zombiemode_gasmask_change_player_headmodel ) )
            self [[ level.zombiemode_gasmask_change_player_headmodel ]]( self.characterindex, self zm_equipment::is_active( gasmask ) );
    }
}

zt_character_refresh_ultimis_roles( map_name )
{
    if ( isdefined( level.zt_character_adapter ) ) return;
    // Primis/Origins also cache this in their first-cast allocator. A solo
    // post-spawn swap must not leave a stale presence bit for a later join.
    if ( map_name != "zm_zod" && zt_character_postspawn_dvar( map_name, "zclassic" ) != "" && isdefined( level.has_richtofen ) )
    {
        level.has_richtofen = 0;
        foreach ( player in getplayers() )
            if ( isdefined( player.characterindex ) && player.characterindex == 2 ) level.has_richtofen = 1;
    }
    if ( zt_character_postspawn_dvar( map_name, "zclassic" ) != "scr_zt_char_ultimis" )
        return;
    // Reconcile after ALL stock callbacks, not partway through a co-op swap.
    // The asset table and Moon/Ascension/Shangri allocators use Richtofen=2;
    // several older remaster callbacks still assign these role refs at 3.
    level.rich_sq_player = undefined;
    level.sndradioa = undefined;
    has_richtofen = 0;
    foreach ( player in getplayers() )
    {
        if ( isdefined( player.characterindex ) && player.characterindex == 2 )
        {
            level.rich_sq_player = player;
            level.sndradioa = player;
            has_richtofen = 1;
        }
    }
    if ( isdefined( level.has_richtofen ) )
        level.has_richtofen = has_richtofen;
}

zt_character_moon_transfer_role( old_player, new_player )
{
    if ( !isdefined( old_player ) || !isdefined( new_player ) || old_player == new_player )
        return;
    // init_sidequest gives the original Richtofen the assembled Vril device.
    // Move existing inventory icons with that role, never award an item or
    // mark a quest stage complete. Other players' wire/datalog stay theirs.
    foreach ( icon in array( "vril", "anti115", "generator", "cgenerator" ) )
    {
        field = "sidequestIcons." + icon + ".icon";
        if ( old_player clientfield::get_player_uimodel( field ) )
        {
            new_player clientfield::set_player_uimodel( field, 1 );
            old_player clientfield::set_player_uimodel( field, 0 );
            old_player clientfield::set_player_uimodel( "sidequestIcons." + icon + ".notification", 0 );
        }
    }
}

// One targeted, read-only request per co-op player after stock round
// readiness. A remote client's gameplay Lua must answer with its own saved
// preference before co-op assignment can be considered. No character write.
zt_character_coop_probe_request()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    if ( zt_true( self.zt_character_coop_probe_started ) ||
        getdvarint( "zt_character_probe" ) == 1 || getdvarint( "zt_character_delay_probe" ) == 1 )
        return;
    while ( !zt_game_ready() )
        wait 0.1;
    players = getplayers();
    preference_dvar = zt_character_postspawn_dvar( getdvarstring( "mapname" ), getdvarstring( "g_gametype" ) );
    if ( players.size < 2 || preference_dvar == "" )
        return;
    roster_code = 0;
    if ( preference_dvar == "scr_zt_char_victis" )
        roster_code = 1;
    else if ( preference_dvar == "scr_zt_char_mob" )
        roster_code = 2;
    else if ( preference_dvar == "scr_zt_char_origins" )
        roster_code = 3;
    else if ( preference_dvar == "scr_zt_char_soe" )
        roster_code = 4;
    else if ( preference_dvar == "scr_zt_char_primis" )
        roster_code = 5;
    else if ( preference_dvar == "scr_zt_char_ultimis" )
        roster_code = 6;
    if ( roster_code == 0 )
        return;
    self.zt_character_coop_probe_started = 1;
    self.zt_character_coop_probe_done = 0;
    self.zt_character_coop_probe_value = "NO_REPLY";
    self.zt_character_coop_probe_dvar = preference_dvar;
    self.zt_character_coop_probe_stamp = zt_character_custom_stamp();
    token = getdvarint( "zt_char_coop_sequence" ) + 1;
    if ( token > 1023 )
        token = 1;
    setdvar( "zt_char_coop_sequence", "" + token );
    self.zt_character_coop_probe_token = token;
    self thread zt_character_coop_probe_response();
    wait 0.05;
    elapsed = 0;
    next_request = 0;
    requests = 0;
    while ( !self.zt_character_coop_probe_done && elapsed < 8 )
    {
        // At match startup the gameplay HUD or offline-loadout attachment
        // may appear after the first request. Three widely spaced targeted
        // attempts avoid both a false RANDOM fallback and a command burst.
        if ( elapsed >= next_request && requests < 3 )
        {
            self LUINotifyEvent( &"ztCharCoopPreference", 1, token * 8 + roster_code );
            requests++;
            next_request += 2;
        }
        wait 0.1;
        elapsed += 0.1;
    }
    self notify( #"zt_character_coop_probe_stop" );
    if ( !isdefined( self ) || !isplayer( self ) )
        return;
    host_text = "0";
    if ( self ishost() )
        host_text = "1";
    stock_index = "UNSET";
    if ( isdefined( self.characterindex ) )
        stock_index = "" + self.characterindex;
    line = "ZT_CHAR_COOP|port=t7|event=transport|player=" + self.name + "|host=" + host_text + "|token=" + token + "|dvar=" + preference_dvar + "|value=" + self.zt_character_coop_probe_value + "|ms=" + int( elapsed * 1000 ) + "|stock_index=" + stock_index;
    logprint( line + "\n" );
    /# print( line ); #/
    if ( getdvarint( "zt_character_coop_probe" ) == 1 )
        self iprintlnbold( "ZT coop preference: " + self.zt_character_coop_probe_value );
}

zt_character_coop_probe_response()
{
    self endon( #"disconnect" );
    self endon( #"zt_character_coop_probe_stop" );
    level endon( #"end_game" );
    while ( 1 )
    {
        self waittill( "menuresponse", menu, response );
        if ( !isdefined( self ) || !isplayer( self ) )
            return;
        if ( !isdefined( response ) || !isstring( response ) || response.size < 13 ||
            getsubstr( response, 0, 13 ) != "zt_char_coop|" )
            continue;
        parts = strtok( response, "|" );
        if ( parts.size != 3 || parts[1] != "" + self.zt_character_coop_probe_token )
            continue;
        value = parts[2];
        if ( value != "-1" && value != "0" && value != "1" && value != "2" && value != "3" && value != "UNAVAILABLE" )
            value = "INVALID";
        self.zt_character_coop_probe_value = value;
        if ( value == "UNAVAILABLE" )
            continue;
        self.zt_character_coop_probe_done = 1;
        return;
    }
}

zt_character_coop_apply_enabled()
{
    return getdvarstring( "zt_character_coop_apply" ) != "0";
}

// Post-spawn co-op reconciliation is transactional: collect each player's
// own local preference, resolve host-first ties, assign a unique target cast,
// then let the map's original callback rebuild each changed identity.
zt_character_coop_assign()
{
    level endon( #"end_game" );
    if ( zt_true( level.zt_character_coop_assign_started ) )
        return;
    level.zt_character_coop_assign_started = 1;
    map_name = getdvarstring( "mapname" );
    mode = getdvarstring( "g_gametype" );
    preference_dvar = zt_character_postspawn_dvar( map_name, mode );
    if ( preference_dvar == "" || !isdefined( level.givecustomcharacters ) )
        return;
    callback = level.givecustomcharacters;
    stamp = zt_character_custom_stamp();
    players = getplayers();
    if ( players.size < 2 || players.size > 4 )
        return;
    elapsed = 0;
    while ( elapsed < 8.3 )
    {
        all_done = 1;
        for ( i = 0; i < players.size; i++ )
        {
            // The level-owned collector survives individual disconnects.
            if ( !isdefined( players[i] ) || !isplayer( players[i] ) )
                return;
            if ( !zt_true( players[i].zt_character_coop_probe_done ) )
                all_done = 0;
        }
        if ( all_done )
            break;
        wait 0.1;
        elapsed += 0.1;
    }
    // RANDOM/missing replies never delay identity work or emit a timeout.
    requested = 0;
    foreach ( player in players )
    {
        if ( !isdefined( player ) || !isplayer( player ) ) return;
        if ( !isdefined( player.zt_character_coop_probe_value ) ) continue;
        for ( slot = 0; slot < 4; slot++ )
            if ( player.zt_character_coop_probe_value == "" + slot ) requested = 1;
    }
    if ( !requested ) return;
    if ( !zt_character_route_unchanged( map_name, mode, preference_dvar, stamp, callback ) ) return;
    if ( !zt_character_wait_identity_ready( players ) )
        return;
    if ( !zt_character_route_unchanged( map_name, mode, preference_dvar, stamp, callback ) ) return;
    current = getplayers();
    if ( current.size != players.size )
        return;
    original = [];
    preference = [];
    target = [];
    stock_seen = [];
    used = [];
    for ( slot = 0; slot < 4; slot++ )
    {
        stock_seen[slot] = 0;
        used[slot] = 0;
    }
    valid_requests = 0;
    for ( i = 0; i < players.size; i++ )
    {
        present = 0;
        for ( j = 0; j < current.size; j++ )
        {
            if ( current[j] == players[i] )
                present = 1;
        }
        if ( !present || !isdefined( players[i].sessionstate ) || players[i].sessionstate != "playing" || !isdefined( players[i].characterindex ) )
            return;
        index = zt_character_decode_index( players[i].characterindex );
        if ( index < 0 || index > 3 || stock_seen[index] )
            return;
        stock_seen[index] = 1;
        original[i] = index;
        target[i] = -1;
        preference[i] = -1;
        if ( isdefined( players[i].zt_character_coop_probe_value ) )
        {
            if ( !isdefined( players[i].zt_character_coop_probe_dvar ) || players[i].zt_character_coop_probe_dvar != preference_dvar ||
                !isdefined( players[i].zt_character_coop_probe_stamp ) || players[i].zt_character_coop_probe_stamp != stamp ) return;
            for ( slot = 0; slot < 4; slot++ )
            {
                if ( players[i].zt_character_coop_probe_value == "" + slot )
                    preference[i] = slot;
            }
        }
        if ( preference[i] >= 0 )
            valid_requests++;
    }
    if ( valid_requests == 0 )
        return;
    for ( slot = 0; slot < 4; slot++ )
    {
        contenders = [];
        host_winner = -1;
        for ( i = 0; i < players.size; i++ )
        {
            if ( preference[i] != slot )
                continue;
            if ( players[i] ishost() )
                host_winner = i;
            else
                contenders[contenders.size] = i;
        }
        winner = host_winner;
        if ( winner < 0 && contenders.size > 0 )
            winner = contenders[randomint( contenders.size )];
        if ( winner >= 0 )
        {
            target[winner] = slot;
            used[slot] = 1;
        }
    }
    required = -1;
    if ( isdefined( level.zt_character_adapter ) )
    {
        binding = zt_character_custom_binding();
        required = binding["required_slot"];
    }
    else if ( map_name == "zm_tomb" || map_name == "zm_factory" || map_name == "zm_castle" || map_name == "zm_island" || map_name == "zm_stalingrad" || map_name == "zm_genesis" || map_name == "zm_moon" || map_name == "zm_cosmodrome" || map_name == "zm_temple" )
        required = 2;
    if ( required >= 0 && !used[required] )
    {
        free = [];
        for ( i = 0; i < players.size; i++ )
        {
            if ( target[i] < 0 )
                free[free.size] = i;
        }
        if ( free.size == 0 )
        {
            revoke = [];
            for ( i = 0; i < players.size; i++ )
            {
                if ( !( players[i] ishost() ) )
                    revoke[revoke.size] = i;
            }
            if ( revoke.size == 0 )
                return;
            loser = revoke[randomint( revoke.size )];
            used[target[loser]] = 0;
            target[loser] = -1;
            free[free.size] = loser;
        }
        recipient = free[0];
        for ( i = 0; i < free.size; i++ )
        {
            if ( original[free[i]] == required )
                recipient = free[i];
        }
        target[recipient] = required;
        used[required] = 1;
    }
    for ( i = 0; i < players.size; i++ )
    {
        if ( target[i] < 0 && !used[original[i]] )
        {
            target[i] = original[i];
            used[original[i]] = 1;
        }
    }
    for ( i = 0; i < players.size; i++ )
    {
        if ( target[i] >= 0 )
            continue;
        available = [];
        for ( slot = 0; slot < 4; slot++ )
        {
            if ( !used[slot] )
                available[available.size] = slot;
        }
        if ( available.size == 0 )
            return;
        target[i] = available[randomint( available.size )];
        used[target[i]] = 1;
    }
    old_richtofen = undefined;
    changes = 0;
    for ( i = 0; i < players.size; i++ )
    {
        if ( original[i] == 2 )
            old_richtofen = players[i];
        if ( target[i] == original[i] )
            continue;
        changes++;
        if ( !isdefined( level.zt_character_adapter ) && isdefined( level.rich_sq_player ) && level.rich_sq_player == players[i] )
            level.rich_sq_player = undefined;
        if ( zt_character_owns_radio_role( map_name ) && isdefined( level.sndradioa ) && level.sndradioa == players[i] )
            level.sndradioa = undefined;
    }
    if ( changes == 0 )
        return;
    for ( i = 0; i < players.size; i++ )
        players[i].characterindex = zt_character_encode_index( target[i] );
    for ( i = 0; i < players.size; i++ )
    {
        if ( target[i] == original[i] )
            continue;
        player = players[i];
        player zt_character_apply_identity( map_name );
        host_text = "0";
        if ( player ishost() )
            host_text = "1";
        line = "ZT_CHAR_COOP|port=t7|event=assigned|player=" + player.name + "|host=" + host_text + "|old=" + original[i] + "|new=" + target[i] + "|wanted=" + preference[i];
        logprint( line + "\n" );
        /# print( line ); #/
    }
    zt_character_refresh_ultimis_roles( map_name );
    zt_character_custom_applied( players, original, target );
    if ( !isdefined( level.zt_character_adapter ) && map_name == "zm_moon" )
        zt_character_moon_transfer_role( old_richtofen, level.rich_sq_player );
}

zt_player_spawn_watch( apply_current )
{
    self endon( #"disconnect" );
    level endon( #"end_game" );

    // BO3 can report the cinematic player as "playing" long before stock
    // Zombies has released startup.  Shadows of Evil is especially sensitive
    // here: replacing weapons/offhands, granting perks, or changing movement
    // during its full intro can prevent start_zombie_round_logic entirely.
    // Treat that stock flag as the transaction boundary for both the initial
    // catch-up path and the per-player revive owner.
    while ( !zt_game_ready() )
        wait 0.1;

    // The level watcher can discover a player before sessionstate changes to
    // playing. Re-evaluate after the authoritative boundary so a first-spawn
    // notification consumed by the cinematic is not missed.
    apply_current = apply_current || ( isdefined( self.sessionstate ) && self.sessionstate == "playing" );
    self thread zt_revive_time_owner_watch();

    if ( apply_current )
    {
        self zt_inventory_begin_generation();
        self.zt_point_gain_baseline_pending = 1;
        // Let the stock spawn pipeline finish assigning its default offhand
        // slots and ammo before ZTweaks replaces or expands them.
        self.zt_spawn_apply_after = gettime() + 400;
        wait 0.4;
        if ( isdefined( self.sessionstate ) && self.sessionstate == "playing" )
        {
            self zt_apply_current_spawn_tweaks();
            if ( self ishost() || zt_true( self.zt_client_hud_ready ) )
                self zt_point_gain_rebaseline();
        }
    }

    while ( 1 )
    {
        self waittill( #"spawned_player" );
        // Invalidate delayed grenade_fire releases at the spawn boundary,
        // before the stock offhand pipeline is allowed to settle.
        self zt_inventory_begin_generation();
        // Starting points and map-authored respawn restoration are baselines,
        // not score awards. Suppress the frame sampler until that pipeline and
        // the ZTweaks spawn transaction have both settled.
        self.zt_point_gain_baseline_pending = 1;
        self.zt_spawn_apply_after = gettime() + 400;
        wait 0.4;
        self zt_apply_current_spawn_tweaks();
        if ( self ishost() || zt_true( self.zt_client_hud_ready ) )
            self zt_point_gain_rebaseline();
    }
}

zt_apply_pending_remote_spawn()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    if ( self ishost() )
        return;
    // A joining client's HUD can come up long after the host's round flag.
    // Apply only after both the client acknowledgment and the stock 0.4 s
    // inventory settle; an absent acknowledgment leaves map state untouched.
    while ( !isdefined( self.zt_player_watch ) || !isdefined( self.zt_inventory_generation ) )
        wait 0.1;
    while ( isdefined( self.zt_spawn_apply_after ) && gettime() < self.zt_spawn_apply_after )
        wait 0.05;
    if ( isdefined( self.sessionstate ) && self.sessionstate == "playing" )
    {
        self zt_apply_current_spawn_tweaks();
        self zt_point_gain_rebaseline();
    }
}

zt_inventory_begin_generation()
{
    if ( !isdefined( self.zt_inventory_generation ) )
        self.zt_inventory_generation = 0;
    self.zt_inventory_generation++;
}

zt_apply_current_spawn_tweaks()
{
    if ( !( self ishost() ) && !zt_true( self.zt_client_hud_ready ) )
        return;
    if ( isdefined( self.zt_spawn_applied_generation ) && isdefined( self.zt_inventory_generation ) &&
         self.zt_spawn_applied_generation == self.zt_inventory_generation )
        return;
    zt_refresh_spawn_config();

    if ( zt_has_player_tweaks() || zt_true( self.zt_player_health_owned ) || zt_true( self.zt_player_speed_owned ) || zt_true( self.zt_inventory_cap_watch ) || zt_true( self.zt_max_ammo_watch ) || zt_true( self.zt_grenade_round_refill_watch ) )
        self zt_apply_spawn_tweaks();
    self.zt_spawn_applied_generation = self.zt_inventory_generation;
}

zt_inventory_cap_watch()
{
    self endon( #"disconnect" );
    self endon( #"zt_stop_inventory_cap_watch" );
    level endon( #"end_game" );

    if ( level.zt.config.max_grenades > 0 )
        zt_feature( "max_grenades", "active", "" );
    if ( level.zt.config.max_equipment > 0 )
        zt_feature( "max_equipment", "active", "" );

    // Never feed an offhand clip from the polling loop. Rewriting that clip
    // while the engine is consuming a throw can make the remaining inventory
    // cascade to zero. A confirmed throw releases exactly one hidden item.
    self thread zt_inventory_throw_watch();

    while ( 1 )
    {
        self zt_clamp_inventory();
        wait 0.2;
    }
}

zt_inventory_throw_watch()
{
    self endon( #"disconnect" );
    self endon( #"zt_stop_inventory_cap_watch" );
    level endon( #"end_game" );

    if ( !isdefined( self.zt_lethal_reserve ) )
        self.zt_lethal_reserve = 0;
    if ( !isdefined( self.zt_tactical_reserve ) )
        self.zt_tactical_reserve = 0;
    if ( !isdefined( self.zt_placeable_reserve ) )
        self.zt_placeable_reserve = 0;

    while ( 1 )
    {
        self waittill( #"grenade_fire", grenade, weapon );
        // Capture the slot and hidden reserve at the notification boundary.
        // The engine can clear current_* when the visible last item is thrown,
        // and the cap poller may observe that transient empty slot before the
        // offhand animation completes.
        was_lethal = zt_supported_inventory_weapon( weapon ) && ( weapon == self.current_lethal_grenade || ( isdefined( self.zt_last_lethal ) && weapon == self.zt_last_lethal ) );
        was_tactical = zt_supported_inventory_weapon( weapon ) && ( weapon == self.current_tactical_grenade || ( isdefined( self.zt_last_tactical ) && weapon == self.zt_last_tactical ) );
        was_placeable = zt_supported_inventory_weapon( weapon ) && ( weapon == self.current_placeable_mine || ( isdefined( self.zt_last_placeable ) && weapon == self.zt_last_placeable ) );
        // grenade_fire also covers projectile primaries and wonder weapons.
        // Never let those unrelated events occupy this serial listener while
        // the player may throw an actual offhand item.
        if ( !was_lethal && !was_tactical && !was_placeable )
            continue;
        generation = self.zt_inventory_generation;
        if ( was_lethal ) self.zt_lethal_throw_active = 1;
        if ( was_tactical ) self.zt_tactical_throw_active = 1;
        if ( was_placeable ) self.zt_placeable_throw_active = 1;
        lethal_reserve = self.zt_lethal_reserve;
        tactical_reserve = self.zt_tactical_reserve;
        placeable_reserve = self.zt_placeable_reserve;
        // grenade_fire is raised at the engine's fire boundary. Let its ammo
        // transaction and offhand animation finish before exposing one reserve
        // item; doing this in the same frame can retrigger consumption.
        wait 0.35;

        // A delayed throw from the prior life must not grant inventory into a
        // newly initialized spawn.
        if ( !isdefined( self.zt_inventory_generation ) || self.zt_inventory_generation != generation )
        {
            if ( was_lethal ) self.zt_lethal_throw_active = 0;
            if ( was_tactical ) self.zt_tactical_throw_active = 0;
            if ( was_placeable ) self.zt_placeable_throw_active = 0;
            continue;
        }

        if ( isdefined( self.zt_lethal_reserve ) && self.zt_lethal_reserve > lethal_reserve )
            lethal_reserve = self.zt_lethal_reserve;
        if ( isdefined( self.zt_tactical_reserve ) && self.zt_tactical_reserve > tactical_reserve )
            tactical_reserve = self.zt_tactical_reserve;
        if ( isdefined( self.zt_placeable_reserve ) && self.zt_placeable_reserve > placeable_reserve )
            placeable_reserve = self.zt_placeable_reserve;

        if ( was_lethal )
        {
            self.zt_lethal_throw_active = 0;
            self.zt_lethal_reserve = self zt_feed_clip_reserve( weapon, lethal_reserve );
        }
        else if ( was_tactical )
        {
            self.zt_tactical_throw_active = 0;
            self.zt_tactical_reserve = self zt_feed_clip_reserve( weapon, tactical_reserve );
        }
        else if ( was_placeable )
        {
            self.zt_placeable_throw_active = 0;
            self.zt_placeable_reserve = self zt_feed_stock_reserve( weapon, placeable_reserve );
        }
    }
}

zt_grenade_round_refill_watch()
{
    self endon( #"disconnect" );
    self endon( #"zt_stop_grenade_round_refill_watch" );
    level endon( #"end_game" );

    while ( 1 )
    {
        level waittill( #"start_of_round" );
        wait 0.25;
        while ( zt_true( self.zt_lethal_throw_active ) ) wait 0.05;
        if ( level.zt.config.max_grenades > 0 && zt_supported_inventory_weapon( self.current_lethal_grenade ) && zt_stock_max_ammo_allows( self.current_lethal_grenade, 1 ) )
            self.zt_lethal_reserve = self zt_set_clip_inventory( self.current_lethal_grenade, level.zt.config.max_grenades );
    }
}

zt_max_ammo_watch()
{
    self endon( #"disconnect" );
    self endon( #"zt_stop_max_ammo_watch" );
    level endon( #"end_game" );

    while ( 1 )
    {
        self waittill( #"zmb_max_ammo" );
        // Snapshot the exact stock slots at the notification boundary. Map
        // scripts can exchange quest offhands while Max Ammo is still running;
        // never refill a replacement that was not part of this pickup.
        lethal = self.current_lethal_grenade;
        tactical = self.current_tactical_grenade;
        placeable = self.current_placeable_mine;
        primaries = [];
        if ( level.zt.config.max_ammo_reload > 0 )
            primaries = self getweaponslistprimaries();
        // Stock sends the notification before it finishes givemaxammo.
        wait 0.1;

        if ( level.zt.config.max_ammo_reload > 0 )
        {
            reloaded = 0;
            for ( i = 0; i < primaries.size; i++ )
            {
                weapon = primaries[i];
                if ( !zt_stock_max_ammo_allows_primary( weapon ) || !self hasweapon( weapon ) )
                    continue;
                clip = weapon.clipsize;
                if ( !isdefined( clip ) || clip <= 0 )
                    continue;
                self setweaponammoclip( weapon, clip );
                reloaded++;
            }
            if ( reloaded > 0 )
                zt_feature( "max_ammo_reload", "active", "" );
        }

        while ( zt_true( self.zt_lethal_throw_active ) || zt_true( self.zt_tactical_throw_active ) || zt_true( self.zt_placeable_throw_active ) ) wait 0.05;

        if ( level.zt.config.max_grenades > 0 && zt_supported_inventory_weapon( lethal ) && lethal == self.current_lethal_grenade && self hasweapon( lethal ) && zt_stock_max_ammo_allows( lethal, 1 ) )
            self.zt_lethal_reserve = self zt_set_clip_inventory( lethal, level.zt.config.max_grenades );

        if ( level.zt.config.max_equipment > 0 )
        {
            if ( zt_supported_inventory_weapon( tactical ) && tactical == self.current_tactical_grenade && self hasweapon( tactical ) && zt_stock_max_ammo_allows( tactical, 0 ) )
                self.zt_tactical_reserve = self zt_set_clip_inventory( tactical, level.zt.config.max_equipment );
            if ( zt_supported_inventory_weapon( placeable ) && placeable == self.current_placeable_mine && self hasweapon( placeable ) && zt_stock_max_ammo_allows( placeable, 0 ) )
                self.zt_placeable_reserve = self zt_set_total_inventory( placeable, level.zt.config.max_equipment );
        }
    }
}

zt_initialize_inventory()
{
    if ( ( level.zt.config.starting_grenade_count > 0 || level.zt.config.max_grenades > 0 ) && zt_supported_inventory_weapon( self.current_lethal_grenade ) )
    {
        amount = zt_spawn_count( level.zt.config.starting_grenade_count, level.zt.config.max_grenades );
        self.zt_lethal_reserve = self zt_set_clip_inventory( self.current_lethal_grenade, amount );
        self.zt_last_lethal = self.current_lethal_grenade;
    }

    if ( level.zt.config.starting_equipment_count <= 0 && level.zt.config.max_equipment <= 0 )
        return;

    restrict_slot = level.zt.config.starting_equipment != "default";
    selected_equipment = zt_starting_equipment_weapon();

    if ( zt_supported_inventory_weapon( self.current_tactical_grenade ) && ( !restrict_slot || ( isdefined( selected_equipment ) && self.current_tactical_grenade == selected_equipment ) ) )
    {
        amount = zt_spawn_count( level.zt.config.starting_equipment_count, level.zt.config.max_equipment );
        self.zt_tactical_reserve = self zt_set_clip_inventory( self.current_tactical_grenade, amount );
        self.zt_last_tactical = self.current_tactical_grenade;
    }
    if ( zt_supported_inventory_weapon( self.current_placeable_mine ) && ( !restrict_slot || ( isdefined( selected_equipment ) && self.current_placeable_mine == selected_equipment ) ) )
    {
        amount = zt_spawn_count( level.zt.config.starting_equipment_count, level.zt.config.max_equipment );
        self.zt_placeable_reserve = self zt_set_total_inventory( self.current_placeable_mine, amount );
        self.zt_last_placeable = self.current_placeable_mine;
    }
}

zt_valid_inventory_weapon( weapon )
{
    return isdefined( weapon ) && ( !isdefined( level.weaponnone ) || weapon != level.weaponnone );
}

zt_supported_inventory_weapon( weapon )
{
    if ( !zt_valid_inventory_weapon( weapon ) || !isdefined( weapon.name ) )
        return 0;

    // These are ordinary stock consumable offhands. Map/quest equipment (for
    // example Dragon Strike and hero weapons) owns its own capacity, refill,
    // HUD and progression lifecycle and must never be adopted by this cap.
    return weapon.name == "frag_grenade" || weapon.name == "sticky_grenade" || weapon.name == "cymbal_monkey" || weapon.name == "emp_grenade" || weapon.name == "bouncingbetty" || weapon.name == "claymore";
}

zt_stock_max_ammo_allows( weapon, lethal_slot )
{
    if ( !zt_supported_inventory_weapon( weapon ) )
        return 0;
    if ( lethal_slot && zt_true( level.headshots_only ) )
        return 0;
    if ( isdefined( level.zombie_include_equipment ) && isdefined( level.zombie_include_equipment[weapon] ) )
    {
        if ( !isdefined( level.zombie_equipment ) || !isdefined( level.zombie_equipment[weapon] ) || !isdefined( level.zombie_equipment[weapon].refill_max_ammo ) || !level.zombie_equipment[weapon].refill_max_ammo )
            return 0;
    }
    if ( isdefined( level.zombie_weapons_no_max_ammo ) && isdefined( level.zombie_weapons_no_max_ammo[weapon.name] ) )
        return 0;
    if ( zm_utility::is_hero_weapon( weapon ) )
        return 0;
    return 1;
}

zt_stock_max_ammo_allows_primary( weapon )
{
    if ( !zt_valid_inventory_weapon( weapon ) || !isdefined( weapon.name ) )
        return 0;
    if ( isdefined( level.zombie_include_equipment ) && isdefined( level.zombie_include_equipment[weapon] ) )
    {
        if ( !isdefined( level.zombie_equipment ) || !isdefined( level.zombie_equipment[weapon] ) || !isdefined( level.zombie_equipment[weapon].refill_max_ammo ) || !level.zombie_equipment[weapon].refill_max_ammo )
            return 0;
    }
    if ( isdefined( level.zombie_weapons_no_max_ammo ) && isdefined( level.zombie_weapons_no_max_ammo[weapon.name] ) )
        return 0;
    if ( zm_utility::is_hero_weapon( weapon ) )
        return 0;
    return 1;
}

// Offhand assets clamp their visible clip to the weapon's stock capacity. Keep
// any configured excess entirely script-owned and expose one item only after a
// confirmed throw. Using the weapon's stock pool as a staging area is unsafe:
// some offhands treat clip/stock rewrites during their animation as more uses.
zt_set_clip_inventory( weapon, amount )
{
    if ( !zt_valid_inventory_weapon( weapon ) || amount <= 0 )
        return 0;

    self setweaponammostock( weapon, 0 );
    self setweaponammoclip( weapon, amount );
    clip = self getweaponammoclip( weapon );
    reserve = amount - clip;
    if ( reserve < 0 )
        reserve = 0;
    return reserve;
}

zt_set_total_inventory( weapon, amount )
{
    if ( !zt_valid_inventory_weapon( weapon ) || amount <= 0 )
        return 0;

    self setweaponammoclip( weapon, 0 );
    self setweaponammostock( weapon, amount );
    actual = self getweaponammoclip( weapon ) + self getweaponammostock( weapon );
    reserve = amount - actual;
    if ( reserve < 0 )
        reserve = 0;
    return reserve;
}

zt_reconcile_clip_inventory( weapon, maximum, reserve )
{
    if ( !zt_valid_inventory_weapon( weapon ) )
        return 0;

    clip = self getweaponammoclip( weapon );
    stock = self getweaponammostock( weapon );
    current = clip + stock;
    if ( maximum > 0 && current + reserve > maximum )
    {
        excess = current + reserve - maximum;
        if ( reserve >= excess )
            reserve -= excess;
        else
        {
            excess -= reserve;
            reserve = 0;
            self zt_clamp_total_ammo( weapon, current - excess );
            clip = self getweaponammoclip( weapon );
            stock = self getweaponammostock( weapon );
            current = clip + stock;
        }
    }

    return reserve;
}

zt_reconcile_total_inventory( weapon, maximum, reserve )
{
    if ( !zt_valid_inventory_weapon( weapon ) )
        return 0;

    clip = self getweaponammoclip( weapon );
    stock = self getweaponammostock( weapon );
    current = clip + stock;
    if ( maximum > 0 && current + reserve > maximum )
    {
        excess = current + reserve - maximum;
        if ( reserve >= excess )
            reserve -= excess;
        else
        {
            excess -= reserve;
            reserve = 0;
            self zt_clamp_total_ammo( weapon, current - excess );
            clip = self getweaponammoclip( weapon );
            stock = self getweaponammostock( weapon );
            current = clip + stock;
        }
    }

    return reserve;
}

zt_feed_clip_reserve( weapon, reserve )
{
    if ( reserve <= 0 || !zt_valid_inventory_weapon( weapon ) )
        return reserve;

    before = self getweaponammoclip( weapon );
    self setweaponammoclip( weapon, before + 1 );
    moved = self getweaponammoclip( weapon ) - before;
    if ( moved > 0 )
        reserve -= moved;
    return reserve;
}

zt_feed_stock_reserve( weapon, reserve )
{
    if ( reserve <= 0 || !zt_valid_inventory_weapon( weapon ) )
        return reserve;

    before = self getweaponammostock( weapon );
    self setweaponammostock( weapon, before + 1 );
    moved = self getweaponammostock( weapon ) - before;
    if ( moved > 0 )
        reserve -= moved;
    return reserve;
}

zt_clamp_clip( weapon, maximum )
{
    if ( !isdefined( weapon ) || ( isdefined( level.weaponnone ) && weapon == level.weaponnone ) )
        return;
    current = self getweaponammoclip( weapon );
    if ( current > maximum )
        self setweaponammoclip( weapon, maximum );
}

zt_clamp_total_ammo( weapon, maximum )
{
    if ( !isdefined( weapon ) || ( isdefined( level.weaponnone ) && weapon == level.weaponnone ) )
        return;

    clip = self getweaponammoclip( weapon );
    stock = self getweaponammostock( weapon );
    excess = clip + stock - maximum;
    if ( excess <= 0 )
        return;

    // Preserve immediately usable ammo where possible and remove reserve
    // first. Placeable mines use stock on initial grant and clip on pickup, so
    // clamping only one pool allows their real carried count to exceed the cap.
    if ( stock >= excess )
        self setweaponammostock( weapon, stock - excess );
    else
    {
        self setweaponammostock( weapon, 0 );
        self setweaponammoclip( weapon, clip - ( excess - stock ) );
    }
}

zt_clamp_inventory()
{
    if ( !isdefined( self.zt_lethal_reserve ) )
        self.zt_lethal_reserve = 0;
    if ( !isdefined( self.zt_tactical_reserve ) )
        self.zt_tactical_reserve = 0;
    if ( !isdefined( self.zt_placeable_reserve ) )
        self.zt_placeable_reserve = 0;

    if ( zt_supported_inventory_weapon( self.current_lethal_grenade ) )
    {
        if ( !isdefined( self.zt_last_lethal ) || self.zt_last_lethal != self.current_lethal_grenade )
        {
            // A max is a ceiling, not a free refill when a pickup changes type.
            self.zt_lethal_reserve = 0;
            if ( level.zt.config.max_grenades > 0 )
                self zt_clamp_total_ammo( self.current_lethal_grenade, level.zt.config.max_grenades );
            self.zt_last_lethal = self.current_lethal_grenade;
        }
        else
            self.zt_lethal_reserve = self zt_reconcile_clip_inventory( self.current_lethal_grenade, level.zt.config.max_grenades, self.zt_lethal_reserve );
    }
    else
    {
        self.zt_lethal_reserve = 0;
        self.zt_last_lethal = undefined;
    }

    if ( zt_supported_inventory_weapon( self.current_tactical_grenade ) )
    {
        if ( !isdefined( self.zt_last_tactical ) || self.zt_last_tactical != self.current_tactical_grenade )
        {
            self.zt_tactical_reserve = 0;
            if ( level.zt.config.max_equipment > 0 )
                self zt_clamp_total_ammo( self.current_tactical_grenade, level.zt.config.max_equipment );
            self.zt_last_tactical = self.current_tactical_grenade;
        }
        else
            self.zt_tactical_reserve = self zt_reconcile_clip_inventory( self.current_tactical_grenade, level.zt.config.max_equipment, self.zt_tactical_reserve );
    }
    else
    {
        self.zt_tactical_reserve = 0;
        self.zt_last_tactical = undefined;
    }

    if ( zt_supported_inventory_weapon( self.current_placeable_mine ) )
    {
        if ( !isdefined( self.zt_last_placeable ) || self.zt_last_placeable != self.current_placeable_mine )
        {
            self.zt_placeable_reserve = 0;
            if ( level.zt.config.max_equipment > 0 )
                self zt_clamp_total_ammo( self.current_placeable_mine, level.zt.config.max_equipment );
            self.zt_last_placeable = self.current_placeable_mine;
        }
        else
            self.zt_placeable_reserve = self zt_reconcile_total_inventory( self.current_placeable_mine, level.zt.config.max_equipment, self.zt_placeable_reserve );
    }
    else
    {
        self.zt_placeable_reserve = 0;
        self.zt_last_placeable = undefined;
    }
}

zt_pacing_install()
{
    level endon( #"end_game" );

    // Match-owned pacing callbacks must not be replaced while a stock intro
    // or cinematic still owns startup.  Shadows of Evil can remain before
    // start_zombie_round_logic for longer than a fixed timeout.
    while ( !zt_game_ready() )
        wait 0.05;

    // Let the map publish its final callback owners, then compose with those
    // owners instead of bypassing custom round pacing.
    wait 0.25;

    level.zt_round_delay_chain = [];
    level.zt_round_delay_inside = 0;
    level.zt_spawn_delay_chain = [];
    level.zt_spawn_delay_inside = 0;

    if ( level.zt.config.round_delay >= 0 )
    {
        if ( isdefined( level.func_get_delay_between_rounds ) )
        {
            level.zt_round_delay_prev = level.func_get_delay_between_rounds;
            level.zt_round_delay_base = level.func_get_delay_between_rounds;
            level.func_get_delay_between_rounds = ::zt_round_delay_override;
            level.zt_round_delay_installed = 1;
            zt_feature( "round_delay", "active", "" );
        }
        else
            zt_feature( "round_delay", "unavailable", "map exposes no standard between-round delay callback" );
    }

    if ( level.zt.config.zombie_spawn_rate > 0 )
    {
        if ( isdefined( level.func_get_zombie_spawn_delay ) )
        {
            level.zt_spawn_delay_prev = level.func_get_zombie_spawn_delay;
            level.zt_spawn_delay_base = level.func_get_zombie_spawn_delay;
            level.func_get_zombie_spawn_delay = ::zt_zombie_spawn_delay_override;
            level.zt_spawn_delay_installed = 1;
            if ( isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_spawn_delay"] ) )
                level.zombie_vars["zombie_spawn_delay"] = zt_scale_spawn_delay( level.zombie_vars["zombie_spawn_delay"] );
            zt_feature( "zombie_spawn_rate", "active", "" );
        }
        else
            zt_feature( "zombie_spawn_rate", "unavailable", "map exposes no standard zombie spawn cadence callback" );
    }

    if ( level.zt.config.round_delay >= 0 || level.zt.config.zombie_spawn_rate > 0 )
        level thread zt_pacing_owner_watch();
}

zt_pacing_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        if ( level.zt.config.round_delay >= 0 )
        {
            if ( !zt_true( level.zt_round_delay_installed ) && isdefined( level.func_get_delay_between_rounds ) )
            {
                level.zt_round_delay_prev = level.func_get_delay_between_rounds;
                level.zt_round_delay_base = level.func_get_delay_between_rounds;
                level.func_get_delay_between_rounds = ::zt_round_delay_override;
                level.zt_round_delay_installed = 1;
                zt_feature( "round_delay", "active", "composed with a late map callback" );
            }
            else if ( zt_true( level.zt_round_delay_installed ) && isdefined( level.func_get_delay_between_rounds ) && level.func_get_delay_between_rounds != ::zt_round_delay_override )
            {
                zt_round_delay_adopt_owner( level.func_get_delay_between_rounds );
                level.func_get_delay_between_rounds = ::zt_round_delay_override;
            }
            else if ( zt_true( level.zt_round_delay_installed ) && !isdefined( level.func_get_delay_between_rounds ) )
            {
                zt_round_delay_release_owner();
                level.func_get_delay_between_rounds = ::zt_round_delay_override;
            }
        }
        if ( level.zt.config.zombie_spawn_rate > 0 )
        {
            if ( !zt_true( level.zt_spawn_delay_installed ) && isdefined( level.func_get_zombie_spawn_delay ) )
            {
                level.zt_spawn_delay_prev = level.func_get_zombie_spawn_delay;
                level.zt_spawn_delay_base = level.func_get_zombie_spawn_delay;
                level.func_get_zombie_spawn_delay = ::zt_zombie_spawn_delay_override;
                level.zt_spawn_delay_installed = 1;
                zt_feature( "zombie_spawn_rate", "active", "composed with a late map callback" );
            }
            else if ( zt_true( level.zt_spawn_delay_installed ) && isdefined( level.func_get_zombie_spawn_delay ) && level.func_get_zombie_spawn_delay != ::zt_zombie_spawn_delay_override )
            {
                zt_spawn_delay_adopt_owner( level.func_get_zombie_spawn_delay );
                level.func_get_zombie_spawn_delay = ::zt_zombie_spawn_delay_override;
            }
            else if ( zt_true( level.zt_spawn_delay_installed ) && !isdefined( level.func_get_zombie_spawn_delay ) )
            {
                zt_spawn_delay_release_owner();
                level.func_get_zombie_spawn_delay = ::zt_zombie_spawn_delay_override;
            }
        }
        wait 0.25;
    }
}

zt_round_delay_release_owner()
{
    if ( !isdefined( level.zt_round_delay_chain ) || level.zt_round_delay_chain.size <= 0 )
    {
        level.zt_round_delay_chain = [];
        level.zt_round_delay_prev = level.zt_round_delay_base;
        return;
    }

    previous_index = level.zt_round_delay_chain.size - 1;
    previous = level.zt_round_delay_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_round_delay_chain[i];
    level.zt_round_delay_chain = restored_chain;
    level.zt_round_delay_prev = previous;
}

zt_round_delay_adopt_owner( owner )
{
    if ( !isdefined( level.zt_round_delay_chain ) )
        level.zt_round_delay_chain = [];
    if ( !isdefined( level.zt_round_delay_prev ) )
    {
        level.zt_round_delay_prev = owner;
        return;
    }
    if ( level.zt_round_delay_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_round_delay_chain.size; i++ )
        if ( level.zt_round_delay_chain[i] == owner )
            restored_index = i;
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_round_delay_chain[i];
        level.zt_round_delay_chain = restored_chain;
    }
    else
        level.zt_round_delay_chain[level.zt_round_delay_chain.size] = level.zt_round_delay_prev;
    level.zt_round_delay_prev = owner;
}

zt_round_delay_forward()
{
    depth = 0;
    if ( isdefined( level.zt_round_delay_inside ) )
        depth = level.zt_round_delay_inside;

    callback = level.zt_round_delay_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_round_delay_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_round_delay_chain[chain_index];
        else
            callback = level.zt_round_delay_base;
    }
    if ( !isdefined( callback ) )
    {
        if ( isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_between_round_time"] ) )
            return level.zombie_vars["zombie_between_round_time"];
        return 5.0;
    }

    level.zt_round_delay_inside = depth + 1;
    result = [[ callback ]]();
    level.zt_round_delay_inside = depth;
    return result;
}

zt_round_delay_override()
{
    // Invoke every map/mod owner in publication order. A late owner may have
    // captured this wrapper; depth selects the predecessor it captured rather
    // than recursing back into that same owner.
    if ( zt_true( level.zt_round_delay_inside ) )
        return zt_round_delay_forward();

    zt_round_delay_forward();

    if ( level.zt.config.round_delay == 0 )
        return 0.05;
    return level.zt.config.round_delay;
}

zt_spawn_delay_release_owner()
{
    if ( !isdefined( level.zt_spawn_delay_chain ) || level.zt_spawn_delay_chain.size <= 0 )
    {
        level.zt_spawn_delay_chain = [];
        level.zt_spawn_delay_prev = level.zt_spawn_delay_base;
        return;
    }

    previous_index = level.zt_spawn_delay_chain.size - 1;
    previous = level.zt_spawn_delay_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_spawn_delay_chain[i];
    level.zt_spawn_delay_chain = restored_chain;
    level.zt_spawn_delay_prev = previous;
}

zt_spawn_delay_adopt_owner( owner )
{
    if ( !isdefined( level.zt_spawn_delay_chain ) )
        level.zt_spawn_delay_chain = [];
    if ( !isdefined( level.zt_spawn_delay_prev ) )
    {
        level.zt_spawn_delay_prev = owner;
        return;
    }
    if ( level.zt_spawn_delay_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_spawn_delay_chain.size; i++ )
        if ( level.zt_spawn_delay_chain[i] == owner )
            restored_index = i;
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_spawn_delay_chain[i];
        level.zt_spawn_delay_chain = restored_chain;
    }
    else
        level.zt_spawn_delay_chain[level.zt_spawn_delay_chain.size] = level.zt_spawn_delay_prev;
    level.zt_spawn_delay_prev = owner;
}

zt_spawn_delay_forward( n_round )
{
    depth = 0;
    if ( isdefined( level.zt_spawn_delay_inside ) )
        depth = level.zt_spawn_delay_inside;

    callback = level.zt_spawn_delay_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_spawn_delay_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_spawn_delay_chain[chain_index];
        else
            callback = level.zt_spawn_delay_base;
    }
    if ( !isdefined( callback ) )
        return undefined;

    level.zt_spawn_delay_inside = depth + 1;
    result = [[ callback ]]( n_round );
    level.zt_spawn_delay_inside = depth;
    return result;
}

zt_scale_spawn_delay( delay )
{
    delay = delay * 100.0 / level.zt.config.zombie_spawn_rate;
    if ( delay < 0.01 )
        delay = 0.01;
    return delay;
}

zt_zombie_spawn_delay_override( n_round )
{
    if ( zt_true( level.zt_spawn_delay_inside ) )
        return zt_spawn_delay_forward( n_round );

    delay = zt_spawn_delay_forward( n_round );
    if ( !isdefined( delay ) )
    {
        zt_feature( "zombie_spawn_rate", "degraded", "map callback returned no spawn cadence" );
        if ( isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_spawn_delay"] ) )
            return level.zombie_vars["zombie_spawn_delay"];
        return 0.1;
    }

    return zt_scale_spawn_delay( delay );
}

zt_zombies_per_round_install()
{
    level endon( #"end_game" );

    // zombie_total_set_func is shared match state.  Never claim it merely
    // because a long intro exceeded an arbitrary readiness timeout.
    while ( !zt_game_ready() )
        wait 0.05;

    wait 0.25;
    level.zt_zombie_total_set_chain = [];
    level.zt_zombie_total_set_inside = 0;
    if ( isdefined( level.zombie_total_set_func ) )
    {
        level.zt_zombie_total_set_prev = level.zombie_total_set_func;
        level.zt_zombie_total_set_base = level.zombie_total_set_func;
    }
    level.zombie_total_set_func = ::zt_zombies_per_round_after_map;
    level thread zt_zombies_per_round_owner_watch();
}

zt_zombies_per_round_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        if ( !isdefined( level.zombie_total_set_func ) )
        {
            zt_zombie_total_set_release_owner();
            level.zombie_total_set_func = ::zt_zombies_per_round_after_map;
        }
        else if ( level.zombie_total_set_func != ::zt_zombies_per_round_after_map )
        {
            zt_zombie_total_set_adopt_owner( level.zombie_total_set_func );
            level.zombie_total_set_func = ::zt_zombies_per_round_after_map;
        }
        wait 0.25;
    }
}

zt_zombie_total_set_release_owner()
{
    if ( !isdefined( level.zt_zombie_total_set_chain ) || level.zt_zombie_total_set_chain.size <= 0 )
    {
        level.zt_zombie_total_set_chain = [];
        level.zt_zombie_total_set_prev = level.zt_zombie_total_set_base;
        return;
    }

    previous_index = level.zt_zombie_total_set_chain.size - 1;
    previous = level.zt_zombie_total_set_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_zombie_total_set_chain[i];
    level.zt_zombie_total_set_chain = restored_chain;
    level.zt_zombie_total_set_prev = previous;
}

zt_zombie_total_set_adopt_owner( owner )
{
    if ( !isdefined( level.zt_zombie_total_set_chain ) )
        level.zt_zombie_total_set_chain = [];
    if ( !isdefined( level.zt_zombie_total_set_prev ) )
    {
        level.zt_zombie_total_set_prev = owner;
        return;
    }
    if ( level.zt_zombie_total_set_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_zombie_total_set_chain.size; i++ )
        if ( level.zt_zombie_total_set_chain[i] == owner )
            restored_index = i;
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_zombie_total_set_chain[i];
        level.zt_zombie_total_set_chain = restored_chain;
    }
    else
        level.zt_zombie_total_set_chain[level.zt_zombie_total_set_chain.size] = level.zt_zombie_total_set_prev;
    level.zt_zombie_total_set_prev = owner;
}

zt_zombie_total_set_forward()
{
    depth = 0;
    if ( isdefined( level.zt_zombie_total_set_inside ) )
        depth = level.zt_zombie_total_set_inside;

    callback = level.zt_zombie_total_set_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_zombie_total_set_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_zombie_total_set_chain[chain_index];
        else
            callback = level.zt_zombie_total_set_base;
    }
    if ( !isdefined( callback ) )
        return;

    level.zt_zombie_total_set_inside = depth + 1;
    [[ callback ]]();
    level.zt_zombie_total_set_inside = depth;
}

zt_zombies_per_round_after_map()
{
    // Stock computes and publishes the ordinary round total before dispatching
    // this callback. Scale that baseline first so map callbacks which derive
    // special-enemy thresholds (Shangri-La monkeys/napalm/sonic, Moon astro)
    // observe the final total. A map's already-applied delta is preserved.
    if ( zt_true( level.zt_zombie_total_set_inside ) )
    {
        zt_zombie_total_set_forward();
        return;
    }

    level.zt.config.zombies_per_round = zt_cfg_int( "zt_zombies_per_round", 0 );
    kill_counter_owned = isdefined( level.kill_counter_hud ) && isdefined( level.zombie_total ) && level.zombie_total > 0;
    if ( level.zt.config.zombies_per_round > 0 && !kill_counter_owned )
    {
        if ( !isdefined( level.zombie_total ) || !isdefined( level.players ) )
            zt_feature( "zombies_per_round", "unavailable", "map did not expose the standard round zombie total" );
        else
        {
            baseline = zm::get_zombie_count_for_round( level.round_number, level.players.size );
            delta = level.zombie_total - baseline;
            scaled = int( baseline * level.zt.config.zombies_per_round / 100 );
            if ( scaled < 1 )
                scaled = 1;
            level.zombie_total = scaled + delta;
            if ( level.zombie_total < 1 )
                level.zombie_total = 1;
            zt_feature( "zombies_per_round", "active", "scaled the stock baseline before map special-round thresholds" );
        }
    }

    // Kill-counter rounds deliberately carry their own positive total across
    // the stock baseline assignment. Preserve it verbatim, but still dispatch
    // the saved map callback exactly once as stock does.
    zt_zombie_total_set_forward();
}

zt_powerup_controls_install()
{
    level endon( #"end_game" );

    // These callback seams and counters are live match state.  Leave them
    // untouched while a stock intro/cinematic still owns startup.
    while ( !zt_game_ready() )
        wait 0.05;

    elapsed = 0;
    missing_reported = 0;
    while ( !isdefined( level.zombie_vars ) || !isdefined( level.zombie_powerups ) )
    {
        wait 0.05;
        elapsed += 0.05;
        if ( elapsed >= 20 && !missing_reported )
        {
            if ( level.zt.config.powerup_ground_time > 0 ) zt_feature( "powerup_ground_time", "unavailable", "map has not published a standard power-up timeout capability" );
            if ( level.zt.config.powerup_effect_time > 0 ) zt_feature( "powerup_effect_time", "unavailable", "map has not published a registered timed power-up capability" );
            if ( level.zt.config.powerup_drop_rate > 0 ) zt_feature( "powerup_drop_rate", "unavailable", "map has not published a standard power-up drop capability" );
            if ( level.zt.config.powerup_max_per_round > 0 ) zt_feature( "powerup_max_per_round", "unavailable", "map has not published a standard power-up drop capability" );
            missing_reported = 1;
        }
    }

    level thread zt_powerup_exact_grab_install();
    level thread zt_powerup_effect_watch();

    // Keep a passive wrapper installed so NEXT DROP changes made in the pause
    // menu can be read at the actual drop boundary.
    if ( isdefined( level._powerup_timeout_custom_time ) )
    {
        level.zt_powerup_timeout_prev = level._powerup_timeout_custom_time;
        level.zt_powerup_timeout_base = level._powerup_timeout_custom_time;
    }
    level.zt_powerup_timeout_chain = [];
    level.zt_powerup_timeout_inside = 0;
    level._powerup_timeout_custom_time = ::zt_powerup_ground_time;
    level thread zt_powerup_ground_time_owner_watch();
    if ( level.zt.config.powerup_ground_time > 0 )
        zt_feature( "powerup_ground_time", "active", "" );

    if ( level.zt.config.powerup_drop_rate > 0 )
    {
        if ( !isdefined( level.enable_magic ) || !level.enable_magic || !isdefined( level.zombie_vars["zombie_powerup_drop_increment"] ) )
        {
            zt_feature( "powerup_drop_rate", "unavailable", "map does not enable standard score-threshold power-up drops" );
        }
        else
        {
            level.zt.powerup_drop_increment_stock = level.zombie_vars["zombie_powerup_drop_increment"];
            scaled = int( level.zt.powerup_drop_increment_stock * 100.0 / level.zt.config.powerup_drop_rate + 0.5 );
            if ( scaled < 1 )
                scaled = 1;
            level.zombie_vars["zombie_powerup_drop_increment"] = scaled;
            level.zt.powerup_drop_increment_applied = scaled;
            zt_feature( "powerup_drop_rate", "active", "" );
        }
    }

    if ( level.zt.config.powerup_max_per_round > 0 )
    {
        if ( !isdefined( level.enable_magic ) || !level.enable_magic || !isdefined( level.zombie_vars["zombie_powerup_drop_max_per_round"] ) )
        {
            zt_feature( "powerup_max_per_round", "unavailable", "map does not enable standard score-threshold power-up drops" );
        }
        else
        {
            level.zt.powerup_max_per_round_stock = level.zombie_vars["zombie_powerup_drop_max_per_round"];
            level.zombie_vars["zombie_powerup_drop_max_per_round"] = level.zt.config.powerup_max_per_round;
            level.zt.powerup_max_per_round_applied = level.zt.config.powerup_max_per_round;
            zt_feature( "powerup_max_per_round", "active", "" );
        }
    }
    level thread zt_powerup_max_finalize();
    if ( level.zt.config.disable_nuke_drops || level.zt.config.disable_max_ammo_drops || level.zt.config.disable_insta_kill_drops || level.zt.config.disable_double_points_drops || level.zt.config.disable_carpenter_drops || level.zt.config.disable_fire_sale_drops )
        level thread zt_powerup_filter_watch();
}

zt_stock_powerup_grab( powerup_name )
{
    if ( powerup_name == "insta_kill" )
        return zm_powerup_insta_kill::grab_insta_kill;
    if ( powerup_name == "double_points" )
        return zm_powerup_double_points::grab_double_points;
    return undefined;
}

zt_powerup_exact_grab_install()
{
    level endon( #"end_game" );

    names = [];
    names[0] = "insta_kill";
    names[1] = "double_points";
    // Adopt anything already finalized, then keep the passive owner alive for
    // custom maps which publish or replace the registry later in the match.
    // The watcher is inert while the registry is absent.
    foreach ( powerup_name in names )
        zt_powerup_exact_grab_adopt( powerup_name );
    level thread zt_powerup_exact_grab_owner_watch();
}

zt_powerup_exact_grab_adopt( powerup_name )
{
    if ( !isdefined( level._custom_powerups ) || !isdefined( level._custom_powerups[powerup_name] ) || !isdefined( level._custom_powerups[powerup_name].grab_powerup ) )
        return 0;

    stock_grab = zt_stock_powerup_grab( powerup_name );
    current_grab = level._custom_powerups[powerup_name].grab_powerup;
    if ( current_grab != stock_grab )
        return 0;

    level.zt.powerup_grab_prev[powerup_name] = current_grab;
    level._custom_powerups[powerup_name].grab_powerup = ::zt_powerup_grab_wrapper;
    level.zt.powerup_exact_wrapped[powerup_name] = 1;
    return 1;
}

zt_powerup_exact_grab_owner_watch()
{
    level endon( #"end_game" );
    names = [];
    names[0] = "insta_kill";
    names[1] = "double_points";

    while ( 1 )
    {
        if ( !isdefined( level._custom_powerups ) )
        {
            foreach ( powerup_name in names )
                level.zt.powerup_exact_wrapped[powerup_name] = 0;
            wait 0.25;
            continue;
        }

        foreach ( powerup_name in names )
        {
            if ( !isdefined( level._custom_powerups[powerup_name] ) || !isdefined( level._custom_powerups[powerup_name].grab_powerup ) )
            {
                level.zt.powerup_exact_wrapped[powerup_name] = 0;
                continue;
            }

            current_grab = level._custom_powerups[powerup_name].grab_powerup;
            if ( current_grab == ::zt_powerup_grab_wrapper )
                continue;

            // Re-adopt only Treyarch's exact callback. A map/mod replacement
            // remains authoritative and receives no timer or lifecycle writes.
            level.zt.powerup_exact_wrapped[powerup_name] = 0;
            stock_grab = zt_stock_powerup_grab( powerup_name );
            if ( current_grab == stock_grab )
                zt_powerup_exact_grab_adopt( powerup_name );
        }
        wait 0.25;
    }
}

zt_powerup_exact_release( powerup_name, team )
{
    key = powerup_name + "_" + team;
    if ( !isdefined( level.zt.powerup_exact_generation[key] ) )
        level.zt.powerup_exact_generation[key] = 0;
    level.zt.powerup_exact_generation[key]++;
}

zt_powerup_exact_duration( percent )
{
    duration = 30;
    if ( bgb::is_team_enabled( "zm_bgb_temporal_gift" ) )
        duration += 30;
    if ( percent > 0 )
        duration = duration * percent / 100.0;
    if ( duration < 0.05 )
        duration = 0.05;
    return duration;
}

zt_powerup_exact_pickup_side_effects( powerup_name, player )
{
    player thread zm_powerups::powerup_vo( powerup_name );
    if ( powerup_name == "insta_kill" && zm_utility::is_classic() )
        player thread zm_pers_upgrades_functions::pers_upgrade_insta_kill_upgrade_check();
    else if ( powerup_name == "double_points" && isdefined( level.pers_upgrade_double_points ) && level.pers_upgrade_double_points )
        player thread zm_pers_upgrades_functions::pers_upgrade_double_points_pickup_start();
}

zt_powerup_grab_wrapper( player )
{
    powerup_name = self.powerup_name;
    if ( !isdefined( level.zt.powerup_grab_prev[powerup_name] ) )
        return;

    percent = zt_cfg_int( "zt_powerup_effect_time", 0 );
    stacking = zt_cfg_string( "zt_powerup_stacking", "default" );
    configured = percent > 0 || stacking != "default";
    if ( !configured || !isdefined( player ) || !isplayer( player ) || !isdefined( player.team ) )
    {
        if ( isdefined( player ) && isdefined( player.team ) )
            zt_powerup_exact_release( powerup_name, player.team );
        return self [[ level.zt.powerup_grab_prev[powerup_name] ]]( player );
    }

    // A map-authored Insta-Kill override owns its complete lifecycle. Passing
    // through the saved stock grab preserves that override instead of running
    // a second cleanup owner beside it.
    if ( powerup_name == "insta_kill" && isdefined( level.insta_kill_powerup_override ) )
    {
        zt_powerup_exact_release( powerup_name, player.team );
        zt_feature( "powerup_effect_time", "degraded", "map-owned Insta-Kill override preserved" );
        return self [[ level.zt.powerup_grab_prev[powerup_name] ]]( player );
    }

    if ( !isdefined( level.zombie_vars[player.team] ) )
        return self [[ level.zt.powerup_grab_prev[powerup_name] ]]( player );

    if ( powerup_name == "insta_kill" )
    {
        time_name = "zombie_powerup_insta_kill_time";
        on_name = "zombie_powerup_insta_kill_on";
    }
    else
    {
        time_name = "zombie_powerup_double_points_time";
        on_name = "zombie_powerup_double_points_on";
    }
    if ( !isdefined( level.zombie_vars[player.team][time_name] ) || !isdefined( level.zombie_vars[player.team][on_name] ) )
        return self [[ level.zt.powerup_grab_prev[powerup_name] ]]( player );

    vars = level.zombie_vars[player.team];
    was_active = zt_true( vars[on_name] );
    old_remaining = vars[time_name];
    if ( old_remaining < 0 )
        old_remaining = 0;

    zt_powerup_exact_pickup_side_effects( powerup_name, player );
    if ( was_active && stacking == "ignore" )
    {
        if ( percent > 0 ) zt_feature( "powerup_effect_time", "active", "pickup-bound stock lifecycle owner" );
        zt_feature( "powerup_stacking", "active", "ignored an active duplicate at the pickup boundary" );
        return;
    }

    if ( powerup_name == "insta_kill" )
        level notify( "powerup instakill_" + player.team );
    else
        level notify( "powerup points scaled_" + player.team );

    level zm_powerups::show_on_hud( player.team, powerup_name );
    // On first activation show_on_hud starts its stock countdown thread. Let
    // that thread apply Temporal Gift before publishing our one owned timer.
    util::wait_network_frame();
    duration = zt_powerup_exact_duration( percent );
    if ( was_active && stacking == "extend" )
        duration += old_remaining;
    vars[time_name] = duration;

    key = powerup_name + "_" + player.team;
    zt_powerup_exact_release( powerup_name, player.team );
    generation = level.zt.powerup_exact_generation[key];
    if ( powerup_name == "insta_kill" )
        vars["zombie_insta_kill"] = 1;
    else
    {
        vars["zombie_point_scalar"] = 2;
        if ( isdefined( level.current_game_module ) && level.current_game_module == 2 && isdefined( player._race_team ) )
        {
            if ( player._race_team == 1 ) level._race_team_double_points = 1;
            else level._race_team_double_points = 2;
        }
        players = getplayers();
        foreach ( team_player in players )
            if ( team_player.team == player.team )
                team_player clientfield::set_player_uimodel( "hudItems.doublePointsActive", 1 );
    }
    level thread zt_powerup_exact_cleanup( powerup_name, player.team, time_name, on_name, generation );

    if ( percent > 0 ) zt_feature( "powerup_effect_time", "active", "pickup-bound stock lifecycle owner" );
    if ( stacking != "default" ) zt_feature( "powerup_stacking", "active", "pickup-bound stock lifecycle owner" );
}

zt_powerup_exact_cleanup( powerup_name, team, time_name, on_name, generation )
{
    level endon( #"end_game" );
    key = powerup_name + "_" + team;
    while ( isdefined( level.zt.powerup_exact_generation[key] ) && level.zt.powerup_exact_generation[key] == generation && isdefined( level.zombie_vars[team] ) && zt_true( level.zombie_vars[team][on_name] ) )
        wait 0.05;

    if ( !isdefined( level.zt.powerup_exact_generation[key] ) || level.zt.powerup_exact_generation[key] != generation || !isdefined( level.zombie_vars[team] ) )
        return;

    if ( powerup_name == "insta_kill" )
    {
        level.zombie_vars[team]["zombie_insta_kill"] = 0;
        players = getplayers( team );
        foreach ( team_player in players )
            if ( isdefined( team_player ) )
                team_player notify( #"insta_kill_over" );
    }
    else
    {
        level.zombie_vars[team]["zombie_point_scalar"] = 1;
        level._race_team_double_points = undefined;
        players = getplayers();
        foreach ( team_player in players )
            if ( team_player.team == team )
                team_player clientfield::set_player_uimodel( "hudItems.doublePointsActive", 0 );
    }
}

zt_powerup_filter_requested( name )
{
    if ( name == "nuke" ) return level.zt.config.disable_nuke_drops;
    if ( name == "full_ammo" ) return level.zt.config.disable_max_ammo_drops;
    if ( name == "insta_kill" ) return level.zt.config.disable_insta_kill_drops;
    if ( name == "double_points" ) return level.zt.config.disable_double_points_drops;
    if ( name == "carpenter" ) return level.zt.config.disable_carpenter_drops;
    if ( name == "fire_sale" ) return level.zt.config.disable_fire_sale_drops;
    return 0;
}

zt_powerup_filter_callback( name )
{
    if ( name == "nuke" ) return ::zt_powerup_filter_nuke;
    if ( name == "full_ammo" ) return ::zt_powerup_filter_full_ammo;
    if ( name == "insta_kill" ) return ::zt_powerup_filter_insta_kill;
    if ( name == "double_points" ) return ::zt_powerup_filter_double_points;
    if ( name == "carpenter" ) return ::zt_powerup_filter_carpenter;
    if ( name == "fire_sale" ) return ::zt_powerup_filter_fire_sale;
    return undefined;
}

zt_powerup_filter_names()
{
    names = [];
    names[0] = "nuke";
    names[1] = "full_ammo";
    names[2] = "insta_kill";
    names[3] = "double_points";
    names[4] = "carpenter";
    names[5] = "fire_sale";
    return names;
}

zt_powerup_filter_in_pool( name )
{
    if ( !isdefined( level.zombie_powerup_array ) )
        return 0;
    for ( i = 0; i < level.zombie_powerup_array.size; i++ )
    {
        if ( level.zombie_powerup_array[i] == name )
            return 1;
    }
    return 0;
}

zt_powerup_filter_original( name )
{
    if ( !isdefined( level.zombie_powerups ) || !isdefined( level.zombie_powerups[name] ) )
        return undefined;
    current = level.zombie_powerups[name].func_should_drop_with_regular_powerups;
    wrapper = zt_powerup_filter_callback( name );
    if ( isdefined( wrapper ) && current == wrapper && isdefined( level.zt.powerup_filter_prev[name] ) )
        return level.zt.powerup_filter_prev[name];
    return current;
}

zt_powerup_filter_eligible( name )
{
    callback = zt_powerup_filter_original( name );
    if ( !isdefined( callback ) )
        return 0;
    return [[ callback ]]();
}

zt_powerup_filter_allowed( name )
{
    // Preserve the map's own eligibility before considering the user filter.
    if ( !zt_powerup_filter_eligible( name ) )
        return 0;
    if ( !zt_powerup_filter_requested( name ) )
        return 1;

    // Stock selection keeps asking until one regular drop qualifies. Never
    // remove its last candidate, even when the user excludes every type.
    pool = level.zombie_powerup_array;
    if ( !isdefined( pool ) || pool.size <= 0 )
        return 1;
    first_excluded = undefined;
    for ( i = 0; i < pool.size; i++ )
    {
        candidate = pool[i];
        if ( !isdefined( level.zombie_powerups[candidate] ) )
            continue;
        if ( !zt_powerup_filter_eligible( candidate ) )
            continue;
        if ( !zt_powerup_filter_requested( candidate ) )
            return 0;
        if ( !isdefined( first_excluded ) )
            first_excluded = candidate;
    }
    if ( !isdefined( first_excluded ) )
        return 1;
    return name == first_excluded;
}

zt_powerup_filter_nuke()
{
    return zt_powerup_filter_allowed( "nuke" );
}
zt_powerup_filter_full_ammo()
{
    return zt_powerup_filter_allowed( "full_ammo" );
}
zt_powerup_filter_insta_kill()
{
    return zt_powerup_filter_allowed( "insta_kill" );
}
zt_powerup_filter_double_points()
{
    return zt_powerup_filter_allowed( "double_points" );
}
zt_powerup_filter_carpenter()
{
    return zt_powerup_filter_allowed( "carpenter" );
}
zt_powerup_filter_fire_sale()
{
    return zt_powerup_filter_allowed( "fire_sale" );
}
zt_powerup_filter_watch()
{
    level endon( #"end_game" );
    names = zt_powerup_filter_names();
    elapsed = 0;
    reported_missing = 0;
    while ( 1 )
    {
        active = 0;
        for ( i = 0; i < names.size; i++ )
        {
            name = names[i];
            if ( !zt_powerup_filter_requested( name ) || !zt_powerup_filter_in_pool( name ) || !isdefined( level.zombie_powerups[name] ) )
                continue;
            wrapper = zt_powerup_filter_callback( name );
            current = level.zombie_powerups[name].func_should_drop_with_regular_powerups;
            if ( zt_true( level.zt.powerup_filter_owned[name] ) )
            {
                if ( current != wrapper )
                {
                    level.zt.powerup_filter_owned[name] = 0;
                    level.zt.powerup_filter_yielded[name] = 1;
                    level.zt.powerup_filter_any_yielded = 1;
                    zt_feature( "powerup_drop_filters", "degraded", "" );
                }
                else
                    active++;
            }
            else if ( !zt_true( level.zt.powerup_filter_yielded[name] ) && isdefined( current ) )
            {
                level.zt.powerup_filter_prev[name] = current;
                level.zombie_powerups[name].func_should_drop_with_regular_powerups = wrapper;
                level.zt.powerup_filter_owned[name] = 1;
                active++;
            }
        }
        if ( active > 0 && !zt_true( level.zt.powerup_filter_any_yielded ) )
            zt_feature( "powerup_drop_filters", "active", "" );
        if ( active == 0 && elapsed >= 20 && !reported_missing )
        {
            zt_feature( "powerup_drop_filters", "unavailable", "map has not published a standard power-up drop capability" );
            reported_missing = 1;
        }
        elapsed += 0.5;
        wait 0.5;
    }
}


zt_powerup_effect_watch()
{
    level endon( #"end_game" );

    while ( true )
    {
        percent = zt_cfg_int( "zt_powerup_effect_time", 0 );
        stacking = zt_cfg_string( "zt_powerup_stacking", "default" );
        configured = percent > 0 || stacking != "default";
        // Keep a low-frequency passive baseline even at GAME DEFAULT. That
        // lets a NEXT POWER-UP menu change distinguish an already-running
        // stock effect from the next real timer discontinuity.
        if ( isdefined( level.zombie_powerups ) )
        {
            found = 0;
            controlled = 0;
            unsafe_owner = 0;
            visited = [];
            keys = getarraykeys( level.zombie_powerups );
            players = getplayers();
            for ( i = 0; i < keys.size; i++ )
            {
                powerup_name = keys[i];
                powerup = level.zombie_powerups[keys[i]];
                if ( !isdefined( powerup.time_name ) || !isdefined( powerup.on_name ) )
                    continue;

                // The fixed-wait stock effects are owned at their verified
                // grab callbacks above. Polling them would scale twice and let
                // the original coroutine clear gameplay before the HUD timer.
                if ( powerup_name == "insta_kill" || powerup_name == "double_points" )
                {
                    if ( zt_true( level.zt.powerup_exact_wrapped[powerup_name] ) )
                        found = 1;
                    else if ( configured )
                        unsafe_owner = 1;
                    continue;
                }

                // Zombie Blood's callback also owns body style, ignore-me,
                // FX and visionset duration. A timer-only rewrite cannot keep
                // that lifecycle coherent, so preserve it until an exact stock
                // callback can be proven instead of partially taking control.
                if ( powerup_name == "zombie_blood" )
                {
                    if ( configured )
                        unsafe_owner = 1;
                    continue;
                }

                time_name = powerup.time_name;
                on_name = powerup.on_name;
                only_grabber = isdefined( powerup.only_affects_grabber ) && powerup.only_affects_grabber;
                if ( only_grabber )
                {
                    // Player-only registration is authoritative. Missing
                    // player vars means this effect is not initialized for
                    // that player; never fall through into same-named team or
                    // global storage.
                    for ( p = 0; p < players.size; p++ )
                    {
                        player = players[p];
                        if ( !isdefined( player.zombie_vars ) || !isdefined( player.zombie_vars[time_name] ) || !isdefined( player.zombie_vars[on_name] ) )
                            continue;
                        found = 1;
                        entity_number = player getentitynumber();
                        scope_key = "player_" + entity_number + "_" + time_name;
                        if ( !isdefined( visited[scope_key] ) )
                        {
                            visited[scope_key] = 1;
                            effect_controlled = zt_powerup_effect_scale_vars( player.zombie_vars, scope_key, powerup_name, time_name, on_name, percent, stacking );
                            if ( effect_controlled ) controlled = 1;
                        }
                    }
                    continue;
                }

                team_scope_found = 0;
                for ( p = 0; p < players.size; p++ )
                {
                    player = players[p];
                    if ( isdefined( level.zombie_vars[player.team] ) && isdefined( level.zombie_vars[player.team][time_name] ) && isdefined( level.zombie_vars[player.team][on_name] ) )
                    {
                        found = 1;
                        team_scope_found = 1;
                        scope_key = "team_" + player.team + "_" + time_name;
                        if ( !isdefined( visited[scope_key] ) )
                        {
                            visited[scope_key] = 1;
                            effect_controlled = zt_powerup_effect_scale_vars( level.zombie_vars[player.team], scope_key, powerup_name, time_name, on_name, percent, stacking );
                            if ( effect_controlled ) controlled = 1;
                        }
                    }
                }
                if ( !team_scope_found && isdefined( level.zombie_vars[time_name] ) && isdefined( level.zombie_vars[on_name] ) )
                {
                    found = 1;
                    scope_key = "level_" + time_name;
                    if ( !isdefined( visited[scope_key] ) )
                    {
                        visited[scope_key] = 1;
                        effect_controlled = zt_powerup_effect_scale_vars( level.zombie_vars, scope_key, powerup_name, time_name, on_name, percent, stacking );
                        if ( effect_controlled ) controlled = 1;
                    }
                }
            }
            level.zt.powerup_effect_controlled = controlled;
            if ( configured && unsafe_owner )
            {
                if ( percent > 0 ) zt_feature( "powerup_effect_time", "degraded", "map-owned or multi-FX timed lifecycle preserved" );
                if ( stacking != "default" ) zt_feature( "powerup_stacking", "degraded", "map-owned or multi-FX timed lifecycle preserved" );
            }
            else if ( found )
            {
                if ( percent > 0 ) zt_feature( "powerup_effect_time", "active", "pickup-owned fixed effects; timer-owned remaining effects" );
                if ( stacking != "default" ) zt_feature( "powerup_stacking", "active", "pickup-owned fixed effects; timer-owned remaining effects" );
            }
            else if ( configured )
            {
                if ( percent > 0 ) zt_feature( "powerup_effect_time", "unavailable", "map exposes no safely owned timed effect storage" );
                if ( stacking != "default" ) zt_feature( "powerup_stacking", "unavailable", "map exposes no safely owned timed effect storage" );
            }
        }
        if ( configured || zt_true( level.zt.powerup_effect_controlled ) )
            wait 0.05;
        else
            wait 0.5;
    }
}

zt_powerup_effect_scale_vars( vars, key, powerup_name, time_name, on_name, percent, stacking )
{
    if ( !isdefined( level.zt.powerup_effect_state[key] ) )
    {
        level.zt.powerup_effect_state[key] = spawnstruct();
        level.zt.powerup_effect_state[key].active = 0;
        level.zt.powerup_effect_state[key].last = 0;
        level.zt.powerup_effect_state[key].duration = 0;
        level.zt.powerup_effect_state[key].base_duration = 0;
        level.zt.powerup_effect_state[key].percent = 0;
        level.zt.powerup_effect_state[key].sample_time = gettime();
        level.zt.powerup_effect_state[key].controlled = 0;
    }

    state = level.zt.powerup_effect_state[key];
    current = vars[time_name];
    elapsed = ( gettime() - state.sample_time ) / 1000.0;
    if ( !zt_true( vars[on_name] ) || current <= 0 )
    {
        if ( zt_true( state.controlled ) )
            zt_powerup_effect_runtime( vars, powerup_name, 0 );
        state.active = 0;
        state.controlled = 0;
        state.last = current;
        state.sample_time = gettime();
        return 0;
    }

    if ( !state.active )
    {
        state.controlled = percent > 0 || stacking != "default";
        state.base_duration = current;
        state.percent = percent;
        if ( percent > 0 ) current = current * percent / 100.0;
        if ( current < 0.05 )
            current = 0.05;
        vars[time_name] = current;
        state.active = 1;
        state.duration = current;
    }
    else
    {
        expected_remaining = state.last - elapsed;
        if ( expected_remaining < 0 )
            expected_remaining = 0;
        pickup_changed_timer = current > expected_remaining + 0.5 || ( current < expected_remaining - 0.5 && current > 2 );
        if ( pickup_changed_timer )
        {
            // Fire Sale adds one stock duration to an active timer. Other
            // stock timer consumers publish their new base/refresh duration.
            // Re-learn that base on every pickup so map/BGB duration changes
            // are not frozen from the first sample.
            if ( powerup_name == "fire_sale" && current > expected_remaining )
                state.base_duration = current - expected_remaining;
            else
                state.base_duration = current;
            state.duration = state.base_duration;
            if ( percent > 0 )
                state.duration = state.duration * percent / 100.0;
            if ( state.duration < 0.05 )
                state.duration = 0.05;
            state.percent = percent;
            state.controlled = zt_true( state.controlled ) || percent > 0 || stacking != "default";

            if ( zt_true( state.controlled ) )
            {
                if ( stacking == "refresh" ) current = state.duration;
                else if ( stacking == "extend" ) current = expected_remaining + state.duration;
                else if ( stacking == "ignore" ) current = expected_remaining;
                else if ( powerup_name == "fire_sale" ) current = expected_remaining + state.duration;
                else current = state.duration;
                vars[time_name] = current;
            }
        }
    }
    if ( zt_true( state.controlled ) )
        zt_powerup_effect_runtime( vars, powerup_name, 1 );
    state.last = current;
    state.sample_time = gettime();
    return zt_true( state.controlled );
}

zt_powerup_effect_runtime( vars, powerup_name, active )
{
    // BO3's Insta-Kill and Double Points gameplay functions wait on local
    // stock durations while their HUD uses the registered timer variables.
    // Keep the actual effect synchronized to the timer ZTweaks owns. Fire
    // Sale and weapon power-ups already consume their timer variables.
    if ( powerup_name == "insta_kill" && isdefined( vars["zombie_insta_kill"] ) )
        vars["zombie_insta_kill"] = active;
    else if ( powerup_name == "double_points" && isdefined( vars["zombie_point_scalar"] ) )
    {
        if ( active ) vars["zombie_point_scalar"] = 2;
        else vars["zombie_point_scalar"] = 1;
    }
}

zt_powerup_max_finalize()
{
    level endon( #"end_game" );

    elapsed = 0;
    while ( ( !level flag::exists( "start_zombie_round_logic" ) || !level flag::get( "start_zombie_round_logic" ) ) && elapsed < 20 )
    {
        wait 0.05;
        elapsed += 0.05;
    }

    // Der Eisendrache and custom maps can publish these values after common
    // power-up init. Adopt late map values as new inputs, reapply only while
    // configured, and restore them when the menu returns to GAME DEFAULT.
    while ( 1 )
    {
        level.zt.config.powerup_drop_rate = zt_cfg_int( "zt_powerup_drop_rate", 0 );
        level.zt.config.powerup_max_per_round = zt_cfg_int( "zt_powerup_max_per_round", 0 );
        if ( isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_powerup_drop_increment"] ) )
        {
            current = level.zombie_vars["zombie_powerup_drop_increment"];
            if ( level.zt.config.powerup_drop_rate > 0 )
            {
                if ( !isdefined( level.zt.powerup_drop_increment_stock ) )
                    level.zt.powerup_drop_increment_stock = current;
                else if ( isdefined( level.zt.powerup_drop_increment_applied ) && current != level.zt.powerup_drop_increment_applied )
                {
                    // Stock advances the live threshold by 14% after every
                    // ordinary drop. Because that live value is already
                    // scaled, adopting it as a fresh base would apply the
                    // configured percentage twice on every drop.
                    expected_stock_growth = level.zt.powerup_drop_increment_applied * 1.14;
                    if ( abs( current - expected_stock_growth ) < 0.01 )
                        level.zt.powerup_drop_increment_stock = level.zt.powerup_drop_increment_stock * 1.14;
                    else
                        level.zt.powerup_drop_increment_stock = current;
                }
                scaled = int( level.zt.powerup_drop_increment_stock * 100.0 / level.zt.config.powerup_drop_rate + 0.5 );
                if ( scaled < 1 ) scaled = 1;
                level.zombie_vars["zombie_powerup_drop_increment"] = scaled;
                level.zt.powerup_drop_increment_applied = scaled;
                zt_feature( "powerup_drop_rate", "active", "composed with late map drop thresholds" );
            }
            else if ( isdefined( level.zt.powerup_drop_increment_applied ) )
            {
                if ( current == level.zt.powerup_drop_increment_applied && isdefined( level.zt.powerup_drop_increment_stock ) )
                    level.zombie_vars["zombie_powerup_drop_increment"] = level.zt.powerup_drop_increment_stock;
                level.zt.powerup_drop_increment_applied = undefined;
                level.zt.powerup_drop_increment_stock = undefined;
                zt_feature( "powerup_drop_rate", "inherit", "" );
            }
        }
        if ( isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_powerup_drop_max_per_round"] ) )
        {
            current = level.zombie_vars["zombie_powerup_drop_max_per_round"];
            if ( level.zt.config.powerup_max_per_round > 0 )
            {
                if ( !isdefined( level.zt.powerup_max_per_round_stock ) || ( isdefined( level.zt.powerup_max_per_round_applied ) && current != level.zt.powerup_max_per_round_applied ) )
                    level.zt.powerup_max_per_round_stock = current;
                level.zombie_vars["zombie_powerup_drop_max_per_round"] = level.zt.config.powerup_max_per_round;
                level.zt.powerup_max_per_round_applied = level.zt.config.powerup_max_per_round;
                zt_feature( "powerup_max_per_round", "active", "composed with late map round caps" );
            }
            else if ( isdefined( level.zt.powerup_max_per_round_applied ) )
            {
                if ( current == level.zt.powerup_max_per_round_applied && isdefined( level.zt.powerup_max_per_round_stock ) )
                    level.zombie_vars["zombie_powerup_drop_max_per_round"] = level.zt.powerup_max_per_round_stock;
                level.zt.powerup_max_per_round_applied = undefined;
                level.zt.powerup_max_per_round_stock = undefined;
                zt_feature( "powerup_max_per_round", "inherit", "" );
            }
        }
        wait 0.25;
    }
}

zt_powerup_ground_time_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        // Some maps temporarily replace and clear this callback for a special
        // quest drop. Their no-yield transaction remains untouched; restore
        // our passive wrapper on the following tick and compose persistent
        // late owners beneath it.
        if ( !isdefined( level._powerup_timeout_custom_time ) )
        {
            zt_powerup_timeout_release_owner();
            level._powerup_timeout_custom_time = ::zt_powerup_ground_time;
        }
        else if ( level._powerup_timeout_custom_time != ::zt_powerup_ground_time )
        {
            zt_powerup_timeout_adopt_owner( level._powerup_timeout_custom_time );
            level._powerup_timeout_custom_time = ::zt_powerup_ground_time;
        }
        wait 0.1;
    }
}

zt_powerup_timeout_release_owner()
{
    if ( !isdefined( level.zt_powerup_timeout_chain ) || level.zt_powerup_timeout_chain.size <= 0 )
    {
        level.zt_powerup_timeout_chain = [];
        level.zt_powerup_timeout_prev = level.zt_powerup_timeout_base;
        return;
    }

    previous_index = level.zt_powerup_timeout_chain.size - 1;
    previous = level.zt_powerup_timeout_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_powerup_timeout_chain[i];
    level.zt_powerup_timeout_chain = restored_chain;
    level.zt_powerup_timeout_prev = previous;
}

zt_powerup_timeout_adopt_owner( owner )
{
    if ( !isdefined( level.zt_powerup_timeout_chain ) )
        level.zt_powerup_timeout_chain = [];
    if ( !isdefined( level.zt_powerup_timeout_prev ) )
    {
        level.zt_powerup_timeout_prev = owner;
        return;
    }
    if ( level.zt_powerup_timeout_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_powerup_timeout_chain.size; i++ )
    {
        if ( level.zt_powerup_timeout_chain[i] == owner )
            restored_index = i;
    }
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_powerup_timeout_chain[i];
        level.zt_powerup_timeout_chain = restored_chain;
    }
    else
        level.zt_powerup_timeout_chain[level.zt_powerup_timeout_chain.size] = level.zt_powerup_timeout_prev;
    level.zt_powerup_timeout_prev = owner;
}

zt_powerup_timeout_forward( powerup )
{
    depth = 0;
    if ( isdefined( level.zt_powerup_timeout_inside ) )
        depth = level.zt_powerup_timeout_inside;

    callback = level.zt_powerup_timeout_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_powerup_timeout_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_powerup_timeout_chain[chain_index];
        else
            callback = level.zt_powerup_timeout_base;
    }
    if ( !isdefined( callback ) )
        return 15;

    level.zt_powerup_timeout_inside = depth + 1;
    result = [[ callback ]]( powerup );
    level.zt_powerup_timeout_inside = depth;
    if ( !isdefined( result ) )
        result = 15;
    return result;
}

zt_powerup_ground_time( powerup )
{
    level.zt.config.powerup_ground_time = zt_cfg_int( "zt_powerup_ground_time", 0 );
    if ( isdefined( powerup ) && isdefined( powerup.powerup_name ) && powerup.powerup_name == "teller_withdrawl" )
        return 15;

    if ( zt_true( level.zt_powerup_timeout_inside ) )
        return zt_powerup_timeout_forward( powerup );

    map_time = zt_powerup_timeout_forward( powerup );
    if ( level.zt.config.powerup_ground_time <= 0 || map_time != 15 )
        return map_time;

    zt_feature( "powerup_ground_time", "active", "" );
    return level.zt.config.powerup_ground_time;
}

zt_power_flag_is_set()
{
    return level flag::exists( "power_on" ) && level flag::get( "power_on" );
}

zt_add_power_zone( zones, power_zone )
{
    if ( !isdefined( power_zone ) )
        return zones;

    foreach ( existing_zone in zones )
        if ( existing_zone == power_zone )
            return zones;

    zones[zones.size] = power_zone;
    return zones;
}

zt_collect_power_zones()
{
    zones = [];
    // Only consumers may publish a zone here.  Shadows of Evil also puts a
    // script_int on every Beast transformer, but several of those transformers
    // reveal quest items or move stairs.  Following the switch target chain
    // would therefore complete unrelated Beast interactions.  Standard zoned
    // perks, Wunderfizz machines and electric doors carry the same script_int
    // that their stock consumer waits use.
    vending_triggers = getentarray( "zombie_vending", "targetname" );
    foreach ( vending_trigger in vending_triggers )
        if ( isdefined( vending_trigger.script_int ) )
            zones = zt_add_power_zone( zones, vending_trigger.script_int );

    random_perk_machines = getentarray( "perk_random_machine", "targetname" );
    foreach ( random_perk_machine in random_perk_machines )
        if ( isdefined( random_perk_machine.script_int ) )
            zones = zt_add_power_zone( zones, random_perk_machine.script_int );

    zombie_doors = getentarray( "zombie_door", "targetname" );
    foreach ( door in zombie_doors )
    {
        if ( !isdefined( door.script_int ) || !isdefined( door.script_noteworthy ) )
            continue;
        if ( door.script_noteworthy == "electric_door" || door.script_noteworthy == "electric_buyable_door" || door.script_noteworthy == "local_electric_door" )
            zones = zt_add_power_zone( zones, door.script_int );
    }

    return zones;
}

zt_power_zones_are_set( power_zones )
{
    if ( power_zones.size == 0 )
        return 0;

    foreach ( power_zone in power_zones )
        if ( !level flag::exists( "power_on" + power_zone ) || !level flag::get( "power_on" + power_zone ) )
            return 0;

    return 1;
}

zt_power_zone_sets_equal( first, second )
{
    if ( first.size != second.size )
        return 0;
    foreach ( power_zone in first )
    {
        found = 0;
        foreach ( other_zone in second )
        {
            if ( power_zone == other_zone )
            {
                found = 1;
                break;
            }
        }
        if ( !found )
            return 0;
    }
    return 1;
}

zt_activate_power_zone( power_zone )
{
    level thread zm_perks::perk_unpause_all_perks( power_zone );
    level zm_power::turn_power_on_and_open_doors( power_zone );
}

zt_zod_quest_only_power_zone( power_zone )
{
    // These transformer outputs exclusively reveal the magician's memento,
    // open the canal memento door, and move the burlesque/deco quest door.
    // They are not ordinary perk/door power consumers.
    return power_zone == 20 || power_zone == 21 || power_zone == 23;
}

zt_start_power_published_zones( exclude_zod_quest_zones )
{
    elapsed = 0;
    power_zones = [];
    previous_zones = [];
    stable_samples = 0;
    while ( elapsed < 20 )
    {
        published_zones = zt_collect_power_zones();
        power_zones = [];
        foreach ( published_zone in published_zones )
            if ( !exclude_zod_quest_zones || !zt_zod_quest_only_power_zone( published_zone ) )
                power_zones = zt_add_power_zone( power_zones, published_zone );
        zones_ready = power_zones.size > 0;
        foreach ( power_zone in power_zones )
        {
            if ( !level flag::exists( "power_on" + power_zone ) )
            {
                zones_ready = 0;
                break;
            }
        }
        if ( zones_ready && zt_power_zone_sets_equal( power_zones, previous_zones ) )
            stable_samples++;
        else
            stable_samples = 0;
        previous_zones = power_zones;
        // Consumer arrays are published by several independent system init
        // threads. Require a stable initialized set instead of accepting the
        // first perk/door which happens to register.
        if ( zones_ready && stable_samples >= 5 )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( power_zones.size == 0 || !zones_ready )
    {
        if ( exclude_zod_quest_zones )
            zt_feature( "start_power_on", "unavailable", "Shadows exposes no initialized perk/door power zones" );
        else
            zt_feature( "start_power_on", "unavailable", "map exposes no initialized published perk/door power zones" );
        return;
    }

    foreach ( power_zone in power_zones )
        zt_activate_power_zone( power_zone );

    if ( zt_power_zones_are_set( power_zones ) )
    {
        if ( exclude_zod_quest_zones )
            zt_feature( "start_power_on", "active", "powered published perk/door transformers; other Beast and quest interactions remain map-owned" );
        else
            zt_feature( "start_power_on", "active", "powered the map's published perk/door consumer zones" );
    }
    else
    {
        if ( exclude_zod_quest_zones )
            zt_feature( "start_power_on", "unavailable", "Shadows' stock power consumers rejected activation" );
        else
            zt_feature( "start_power_on", "unavailable", "map's published power consumers rejected activation" );
    }
}

zt_start_power_zod()
{
    stair_zones = [];
    stair_zones[0] = 11;
    stair_zones[1] = 12;
    stair_zones[2] = 13;
    stair_zones[3] = 14;
    stair_zones[4] = 15;
    stair_zones[5] = 16;

    elapsed = 0;
    stable_samples = 0;
    previous_zones = [];
    power_zones = [];
    zones_ready = 0;
    while ( elapsed < 20 )
    {
        zones_ready = isdefined( level.a_o_stair );
        power_zones = [];
        foreach ( stair_zone in stair_zones )
        {
            if ( !zones_ready || !isdefined( level.a_o_stair[stair_zone] ) || !level flag::exists( "power_on" + stair_zone ) )
                zones_ready = 0;
            power_zones = zt_add_power_zone( power_zones, stair_zone );
        }
        published_zones = zt_collect_power_zones();
        foreach ( published_zone in published_zones )
            if ( !zt_zod_quest_only_power_zone( published_zone ) )
                power_zones = zt_add_power_zone( power_zones, published_zone );
        foreach ( power_zone in power_zones )
            if ( !level flag::exists( "power_on" + power_zone ) )
                zones_ready = 0;

        if ( zones_ready && zt_power_zone_sets_equal( power_zones, previous_zones ) )
            stable_samples++;
        else
            stable_samples = 0;
        previous_zones = power_zones;
        if ( zones_ready && stable_samples >= 5 )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !zones_ready || stable_samples < 5 )
    {
        zt_feature( "start_power_on", "unavailable", "Shadows exposes no complete six-stair/perk/door consumer registry" );
        return;
    }

    foreach ( power_zone in power_zones )
        zt_activate_power_zone( power_zone );

    if ( zt_power_zones_are_set( power_zones ) )
        zt_feature( "start_power_on", "active", "powered all six stock traversal stairs and published perk/door transformers; quest outputs 20/21/23 remain map-owned" );
    else
        zt_feature( "start_power_on", "unavailable", "Shadows' stock stair/perk/door consumers rejected activation" );
}

zt_stock_global_power_map( map_name )
{
    return map_name == "zm_factory" || map_name == "zm_castle" || map_name == "zm_stalingrad" || map_name == "zm_asylum" || map_name == "zm_theater" || map_name == "zm_cosmodrome" || map_name == "zm_temple" || map_name == "zm_moon";
}

zt_start_power_temple( door_user )
{
    elapsed = 0;
    ready = 0;
    while ( elapsed < 20 )
    {
        left_trigger = getent( "power_trigger_left", "targetname" );
        right_trigger = getent( "power_trigger_right", "targetname" );
        flags_ready = level flag::exists( "left_switch_pulled" ) && level flag::exists( "right_switch_pulled" ) && level flag::exists( "left_switch_done" ) && level flag::exists( "right_switch_done" ) && level flag::exists( "power_on" );
        left_ready = flags_ready && ( level flag::get( "left_switch_pulled" ) || isdefined( left_trigger ) );
        right_ready = flags_ready && ( level flag::get( "right_switch_pulled" ) || isdefined( right_trigger ) );
        ready = isdefined( level.var_c43f63de ) && left_ready && right_ready;
        if ( ready )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !ready )
    {
        zt_feature( "start_power_on", "unavailable", "Shangri-La exposes no initialized two-switch power route" );
        return;
    }

    // Feed both real stock switch waiters with a real player. Their animation
    // threads own the pulled/done flags, water wheels and, after both finish,
    // the sole global-power call. Never pre-set power_on here.
    elapsed = 0;
    while ( elapsed < 8 && ( !level flag::get( "left_switch_pulled" ) || !level flag::get( "right_switch_pulled" ) ) )
    {
        if ( !level flag::get( "left_switch_pulled" ) )
        {
            left_trigger = getent( "power_trigger_left", "targetname" );
            if ( isdefined( left_trigger ) )
                left_trigger notify( #"trigger", door_user );
        }
        if ( !level flag::get( "right_switch_pulled" ) )
        {
            right_trigger = getent( "power_trigger_right", "targetname" );
            if ( isdefined( right_trigger ) )
                right_trigger notify( #"trigger", door_user );
        }
        wait 0.25;
        elapsed += 0.25;
    }

    elapsed = 0;
    while ( elapsed < 12 && ( !level flag::get( "left_switch_done" ) || !level flag::get( "right_switch_done" ) || !zt_power_flag_is_set() ) )
    {
        wait 0.1;
        elapsed += 0.1;
    }

    left_trigger = getent( "power_trigger_left", "targetname" );
    right_trigger = getent( "power_trigger_right", "targetname" );
    if ( level flag::get( "left_switch_done" ) && level flag::get( "right_switch_done" ) && !isdefined( left_trigger ) && !isdefined( right_trigger ) && zt_power_flag_is_set() )
        zt_feature( "start_power_on", "active", "completed both stock water-wheel switches; Shangri-La's wait_for_power owns global activation" );
    else
        zt_feature( "start_power_on", "unavailable", "Shangri-La's stock two-switch power route did not complete" );
}

zt_start_power_genesis()
{
    // Revelations' four power_on<N> flags are the consumer outputs of its
    // corruption rituals.  The separate ritual count/volume state remains
    // untouched, so all four rituals can still be played normally.  The map
    // deliberately keys portals and Pack-a-Punch to these same real-power
    // flags, so those downstream consumers necessarily unlock here.
    power_zones = [];
    power_zones[0] = 1;
    power_zones[1] = 2;
    power_zones[2] = 3;
    power_zones[3] = 4;

    elapsed = 0;
    zones_ready = 0;
    while ( elapsed < 20 )
    {
        zones_ready = isdefined( level.var_eada0345 );
        foreach ( power_zone in power_zones )
        {
            if ( !level flag::exists( "power_on" + power_zone ) )
            {
                zones_ready = 0;
                break;
            }
        }
        if ( zones_ready )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !zones_ready )
    {
        zt_feature( "start_power_on", "unavailable", "Revelations exposes no initialized corruption-grid consumers" );
        return;
    }

    foreach ( power_zone in power_zones )
        zt_activate_power_zone( power_zone );

    if ( zt_power_zones_are_set( power_zones ) )
        zt_feature( "start_power_on", "active", "powered all four stock grids and their portals/Pack-a-Punch; ritual count and completion remain map-owned" );
    else
        zt_feature( "start_power_on", "unavailable", "Revelations' stock power consumers rejected activation" );
}

zt_tomb_perk_validation_release_owner()
{
    if ( !isdefined( level.zt_tomb_perk_validation_chain ) || level.zt_tomb_perk_validation_chain.size <= 0 )
    {
        level.zt_tomb_perk_validation_chain = [];
        level.zt_tomb_perk_validation_prev = level.zt_tomb_perk_validation_base;
        return;
    }

    previous_index = level.zt_tomb_perk_validation_chain.size - 1;
    previous = level.zt_tomb_perk_validation_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_tomb_perk_validation_chain[i];
    level.zt_tomb_perk_validation_chain = restored_chain;
    level.zt_tomb_perk_validation_prev = previous;
}

zt_tomb_perk_validation_adopt_owner( owner )
{
    if ( !isdefined( level.zt_tomb_perk_validation_chain ) )
        level.zt_tomb_perk_validation_chain = [];
    if ( !isdefined( level.zt_tomb_perk_validation_prev ) )
    {
        level.zt_tomb_perk_validation_prev = owner;
        return;
    }
    if ( level.zt_tomb_perk_validation_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_tomb_perk_validation_chain.size; i++ )
        if ( level.zt_tomb_perk_validation_chain[i] == owner )
            restored_index = i;
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_tomb_perk_validation_chain[i];
        level.zt_tomb_perk_validation_chain = restored_chain;
    }
    else
        level.zt_tomb_perk_validation_chain[level.zt_tomb_perk_validation_chain.size] = level.zt_tomb_perk_validation_prev;
    level.zt_tomb_perk_validation_prev = owner;
}

zt_tomb_perk_validation_forward( player )
{
    depth = 0;
    if ( isdefined( level.zt_tomb_perk_validation_inside ) )
        depth = level.zt_tomb_perk_validation_inside;

    callback = level.zt_tomb_perk_validation_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_tomb_perk_validation_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_tomb_perk_validation_chain[chain_index];
        else
            callback = level.zt_tomb_perk_validation_base;
    }
    if ( !isdefined( callback ) )
        return 1;

    level.zt_tomb_perk_validation_inside = depth + 1;
    result = self [[ callback ]]( player );
    level.zt_tomb_perk_validation_inside = depth;
    if ( !isdefined( result ) )
        result = 1;
    return result;
}

zt_tomb_powered_perk_validation( player )
{
    if ( zt_true( level.zt_tomb_perk_validation_inside ) )
        return self zt_tomb_perk_validation_forward( player );

    if ( level.zt.config.start_power_on && isdefined( self.str_zone_name ) && isdefined( level.zone_capture ) && isdefined( level.zone_capture.zones ) && isdefined( level.zone_capture.zones[self.str_zone_name] ) )
    {
        self zt_tomb_perk_validation_forward( player );
        return 1;
    }

    return self zt_tomb_perk_validation_forward( player );
}

zt_tomb_unlock_generator_perks( generator, force )
{
    if ( !isdefined( generator.perk_machines ) || !isarray( generator.perk_machines ) )
        return;

    perk_keys = getarraykeys( generator.perk_machines );
    foreach ( perk_key in perk_keys )
    {
        perk_trigger = generator.perk_machines[perk_key];
        if ( !isdefined( perk_trigger ) )
            continue;
        if ( !force && isdefined( perk_trigger.is_locked ) && !perk_trigger.is_locked )
            continue;

        // This is the consumer half of Origins'
        // enable_perk_machines_in_zone: it does not set player_controlled,
        // update the generator count, or unlock Pack-a-Punch.
        level notify( perk_key + "_on" );
        perk_trigger.is_locked = 0;
        perk_trigger zm_perks::reset_vending_hint_string();
        if ( isdefined( perk_trigger.script_noteworthy ) )
            zm_perks::perk_unpause( perk_trigger.script_noteworthy );
    }
}

zt_tomb_unlock_generator_random_perks( generator, force )
{
    if ( !isdefined( generator.perk_machines_random ) || !isarray( generator.perk_machines_random ) )
        return;

    foreach ( random_perk_machine in generator.perk_machines_random )
    {
        if ( !isdefined( random_perk_machine ) )
            continue;
        if ( !force && isdefined( random_perk_machine.is_locked ) && !random_perk_machine.is_locked )
            continue;

        // Origins' recapture path changes the current Wunderfizz back to its
        // initial state even after the common power flag has already fired.
        random_perk_machine.is_locked = 0;
        if ( isdefined( random_perk_machine.current_perk_random_machine ) && random_perk_machine.current_perk_random_machine )
            random_perk_machine thread zt_tomb_set_perk_random_machine_state( "idle" );
        else
            random_perk_machine thread zt_tomb_set_perk_random_machine_state( "away" );
    }
}

zt_tomb_set_perk_random_machine_state( state )
{
    // Origins loads _zm_perk_random and publishes this renderer. Other maps,
    // including Shadows of Evil, do not carry that scriptparsetree. Calling
    // its namespace directly therefore made those maps fail while linking an
    // otherwise dormant Origins adapter. Mirror the stock dispatch wrapper
    // through Origins' published function pointer instead.
    if ( !isdefined( level.perk_random_machine_state_func ) )
        return;

    wait 0.1;
    for ( i = 0; i < self GetNumZBarrierPieces(); i++ )
        self HideZBarrierPiece( i );
    self notify( "zbarrier_state_change" );
    self [[ level.perk_random_machine_state_func ]]( state );
}

zt_tomb_power_owner_watch()
{
    level endon( #"end_game" );

    while ( level.zt.config.start_power_on )
    {
        if ( !isdefined( level.custom_perk_validation ) )
        {
            zt_tomb_perk_validation_release_owner();
            level.custom_perk_validation = ::zt_tomb_powered_perk_validation;
        }
        else if ( level.custom_perk_validation != ::zt_tomb_powered_perk_validation )
        {
            zt_tomb_perk_validation_adopt_owner( level.custom_perk_validation );
            level.custom_perk_validation = ::zt_tomb_powered_perk_validation;
        }

        if ( isdefined( level.zone_capture ) && isdefined( level.zone_capture.zones ) )
        {
            foreach ( generator in level.zone_capture.zones )
            {
                if ( !isdefined( generator.script_int ) )
                    continue;
                power_flag = "power_on" + generator.script_int;
                if ( level flag::exists( power_flag ) && !level flag::get( power_flag ) )
                    zt_activate_power_zone( generator.script_int );
                zt_tomb_unlock_generator_perks( generator, 0 );
                zt_tomb_unlock_generator_random_perks( generator, 0 );
            }
        }
        wait 0.5;
    }
}

zt_start_power_tomb()
{
    elapsed = 0;
    tomb_ready = 0;
    while ( elapsed < 20 )
    {
        tomb_ready = isdefined( level.zone_capture ) && isdefined( level.zone_capture.zones ) && getarraykeys( level.zone_capture.zones ).size >= 6 && isdefined( level.custom_perk_validation ) && level flag::exists( "capture_zones_init_done" ) && level flag::get( "capture_zones_init_done" );
        if ( tomb_ready )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !tomb_ready )
    {
        zt_feature( "start_power_on", "unavailable", "Origins exposes no initialized generator-consumer registry" );
        return;
    }

    if ( level.custom_perk_validation != ::zt_tomb_powered_perk_validation )
    {
        level.zt_tomb_perk_validation_base = level.custom_perk_validation;
        level.zt_tomb_perk_validation_prev = level.custom_perk_validation;
        level.zt_tomb_perk_validation_chain = [];
        level.zt_tomb_perk_validation_inside = 0;
        level.custom_perk_validation = ::zt_tomb_powered_perk_validation;
    }

    power_zones = [];
    foreach ( generator in level.zone_capture.zones )
    {
        if ( !isdefined( generator.script_int ) || !level flag::exists( "power_on" + generator.script_int ) )
            continue;
        power_zones = zt_add_power_zone( power_zones, generator.script_int );
        zt_activate_power_zone( generator.script_int );
        zt_tomb_unlock_generator_perks( generator, 1 );
        zt_tomb_unlock_generator_random_perks( generator, 1 );
    }

    if ( power_zones.size < 6 || !zt_power_zones_are_set( power_zones ) )
    {
        zt_feature( "start_power_on", "unavailable", "Origins did not publish all six generator consumer zones" );
        return;
    }

    level thread zt_tomb_power_owner_watch();
    zt_feature( "start_power_on", "active", "powered all six generator consumers; capture count and Pack-a-Punch progression remain map-owned" );
}

zt_start_power_island()
{
    // Zetsubou's deferred main switch feeds zone 4.  Its stock zone-4 watcher
    // performs the map's global-power finalization while leaving the two
    // temporary water generators, web and defend state untouched.
    elapsed = 0;
    while ( elapsed < 20 && ( !level flag::exists( "power_on4" ) || !isdefined( level.var_769c0729 ) ) )
    {
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !level flag::exists( "power_on4" ) || !isdefined( level.var_769c0729 ) )
    {
        zt_feature( "start_power_on", "unavailable", "Zetsubou exposes no initialized main-power consumer" );
        return;
    }

    zt_activate_power_zone( 4 );
    elapsed = 0;
    while ( !zt_power_flag_is_set() && elapsed < 5 )
    {
        wait 0.1;
        elapsed += 0.1;
    }

    if ( zt_power_flag_is_set() )
        zt_feature( "start_power_on", "active", "activated the stock main-power finalizer without marking temporary-generator/web/defend objectives complete" );
    else
        zt_feature( "start_power_on", "unavailable", "Zetsubou's stock main-power consumer rejected activation" );
}

zt_has_electric_power_doors()
{
    doors = getentarray( "zombie_door", "targetname" );
    foreach ( door in doors )
        if ( isdefined( door.script_noteworthy ) && ( door.script_noteworthy == "electric_door" || door.script_noteworthy == "electric_buyable_door" || door.script_noteworthy == "local_electric_door" ) )
            return 1;
    return 0;
}

zt_factory_power_consumers()
{
    // The Giant's custom switch publishes two consumers after setting the
    // common flag.  Reproduce those consumer calls without invoking its
    // switch animation/recording callback.
    level notify( #"sleight_on", 0 );
    util::wait_network_frame();
    level notify( #"revive_on" );
    util::wait_network_frame();
    level notify( #"doubletap_on" );
    util::wait_network_frame();
    level notify( #"juggernog_on" );
    util::wait_network_frame();
    level notify( #"pack_a_punch_on" );
    util::wait_network_frame();
    level notify( #"specialty_armorvest_power_on" );
    util::wait_network_frame();
    level notify( #"specialty_rof_power_on" );
    util::wait_network_frame();
    level notify( #"specialty_quickrevive_power_on" );
    util::wait_network_frame();
    level notify( #"specialty_fastreload_power_on" );
    util::wait_network_frame();
    level util::set_lighting_state( 0 );
    util::clientnotify( "ZPO" );
    zm_zonemgr::connect_zones( "outside_east_zone", "outside_south_zone" );
    zm_zonemgr::connect_zones( "outside_west_zone", "outside_south_zone", 1 );

    power_switch = getent( "use_power_switch", "targetname" );
    if ( isdefined( power_switch ) )
    {
        power_switch setinvisibletoall();
        power_switch delete();
    }
}

zt_asylum_power_consumers()
{
    if ( level flag::exists( "electric_switch_used" ) )
        level flag::set( "electric_switch_used" );

    traps = getentarray( "gas_access", "targetname" );
    foreach ( trap in traps )
    {
        trap sethintstring( &"ZOMBIE_ELECTRIC_SWITCH" );
        trap setcursorhint( "HINT_NOICON" );
        trap.is_available = 1;
    }
    level notify( #"switch_flipped" );
    level notify( #"master_switch_activated" );
    util::setclientsysstate( "levelNotify", "start_lights" );
    level notify( #"sleight_on" );
    level notify( #"revive_on" );
    level notify( #"doubletap_on" );
    level notify( #"juggernog_on" );

    power_switch = getent( "use_master_switch", "targetname" );
    if ( isdefined( power_switch ) )
    {
        power_switch setinvisibletoall();
        power_switch delete();
    }
}

zt_castle_power_consumers()
{
    // Der Eisendrache's remaining consumers are flag waiters.  Retire its
    // custom trigger so the switch callback cannot be played a second time.
    util::clientnotify( "ZPO" );
    power_switch = getent( "use_power_switch", "targetname" );
    if ( isdefined( power_switch ) )
    {
        power_switch setinvisibletoall();
        power_switch delete();
    }
}

zt_start_power_global( map_name )
{
    elapsed = 0;
    switches = [];
    vending_triggers = [];
    while ( elapsed < 20 )
    {
        switches = getentarray( "use_elec_switch", "targetname" );
        vending_triggers = getentarray( "zombie_vending", "targetname" );
        has_powered_items = isdefined( level.powered_items ) && level.powered_items.size > 0;
        has_consumers = has_powered_items || vending_triggers.size > 0 || zt_has_electric_power_doors();
        if ( level flag::exists( "power_on" ) && has_consumers )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !level flag::exists( "power_on" ) || !has_consumers )
    {
        zt_feature( "start_power_on", "unavailable", "map exposes no initialized stock global-power consumers" );
        return;
    }

    level thread zm_perks::perk_unpause_all_perks( undefined );
    level zm_power::turn_power_on_and_open_doors( undefined );

    if ( map_name == "zm_factory" )
        zt_factory_power_consumers();
    else if ( map_name == "zm_asylum" )
        zt_asylum_power_consumers();
    else if ( map_name == "zm_castle" )
        zt_castle_power_consumers();

    elapsed = 0;
    while ( !zt_power_flag_is_set() && elapsed < 5 )
    {
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !zt_power_flag_is_set() )
    {
        zt_feature( "start_power_on", "unavailable", "map's stock global-power consumers rejected activation" );
        return;
    }

    standard_global_switch = switches.size == 1 && isdefined( switches[0] ) && !isdefined( switches[0].script_int ) && ( !isdefined( switches[0].script_noteworthy ) || switches[0].script_noteworthy != "allow_power_off" ) && !isdefined( level.temporary_power_switch_logic );
    if ( standard_global_switch )
    {
        switches[0] setinvisibletoall();
        switches[0] delete();
    }

    if ( map_name == "zm_factory" )
        zt_feature( "start_power_on", "active", "powered the stock global consumers, Pack-a-Punch and Giant traversal links" );
    else if ( map_name == "zm_asylum" )
        zt_feature( "start_power_on", "active", "powered the stock global consumers and Verruckt trap controls" );
    else
        zt_feature( "start_power_on", "active", "" );
}

zt_start_power_install()
{
    level endon( #"end_game" );

    // Do not inspect or mutate map power while a stock intro/cinematic still
    // owns startup. Shadows of Evil can remain here longer than a fixed
    // timeout; start_zombie_round_logic is the shared authoritative boundary.
    while ( !zt_game_ready() )
        wait 0.1;

    players = getplayers();
    while ( players.size == 0 )
    {
        wait 0.1;
        players = getplayers();
    }

    map_name = level.script;
    if ( zt_power_flag_is_set() )
    {
        zt_feature( "start_power_on", "active", "map starts with power already enabled" );
        return;
    }

    // Nacht and Shi No Numa deliberately publish global power themselves at
    // the same round-logic boundary.  Let their stock thread win rather than
    // racing a duplicate helper call.
    if ( map_name == "zm_prototype" || map_name == "zm_sumpf" )
    {
        elapsed = 0;
        while ( !zt_power_flag_is_set() && elapsed < 5 )
        {
            wait 0.1;
            elapsed += 0.1;
        }
        if ( zt_power_flag_is_set() )
            zt_feature( "start_power_on", "active", "map's stock always-on power path completed" );
        else
            zt_feature( "start_power_on", "unavailable", "map's stock always-on power path did not initialize" );
        return;
    }

    if ( map_name == "zm_zod" )
    {
        zt_start_power_zod();
        return;
    }
    if ( map_name == "zm_tomb" )
    {
        zt_start_power_tomb();
        return;
    }
    if ( map_name == "zm_genesis" )
    {
        zt_start_power_genesis();
        return;
    }
    if ( map_name == "zm_island" )
    {
        zt_start_power_island();
        return;
    }
    if ( map_name == "zm_temple" )
    {
        zt_start_power_temple( players[0] );
        return;
    }

    if ( !zt_stock_global_power_map( map_name ) && zt_collect_power_zones().size > 0 )
    {
        zt_start_power_published_zones( 0 );
        return;
    }

    zt_start_power_global( map_name );
}

zt_supported_door_trigger( door, map_name )
{
    if ( !isdefined( door ) )
        return 0;
    // Stock _zm_blockers::init_blockers owns every zombie_door. Shadows uses
    // map-specific noteworthy values for ordinary gates, so a whitelist
    // rejects its traversal routes. The 0.1.130.d complete-registry path
    // reached gameplay and opened those gates; retain the later post-intro
    // readiness gate and custom-owner checks around this classification.
    return 1;
}

zt_door_group_triggers( door )
{
    if ( !isdefined( door ) || !isdefined( door.target ) )
    {
        empty = [];
        return empty;
    }
    return getentarray( door.target, "target" );
}

zt_door_group_ready( door )
{
    if ( !isdefined( door ) || !isdefined( door._door_open ) || !isdefined( door.doors ) )
        return 0;
    linked_triggers = zt_door_group_triggers( door );
    if ( linked_triggers.size == 0 )
        return 0;
    foreach ( linked_trigger in linked_triggers )
        if ( !isdefined( linked_trigger._door_open ) )
            return 0;
    return 1;
}

zt_door_group_has_open_trigger( door )
{
    linked_triggers = zt_door_group_triggers( door );
    foreach ( linked_trigger in linked_triggers )
        if ( isdefined( linked_trigger._door_open ) && linked_trigger._door_open )
            return 1;
    return 0;
}

zt_door_group_is_moving( door )
{
    if ( isdefined( door.door_is_moving ) && door.door_is_moving )
        return 1;
    linked_triggers = zt_door_group_triggers( door );
    foreach ( linked_trigger in linked_triggers )
        if ( isdefined( linked_trigger.door_is_moving ) && linked_trigger.door_is_moving )
            return 1;
    return 0;
}

zt_door_group_stop_buy_waiters( door )
{
    linked_triggers = zt_door_group_triggers( door );
    foreach ( linked_trigger in linked_triggers )
        linked_trigger notify( #"kill_door_think" );
}

zt_door_group_normalize_open( door )
{
    if ( !isdefined( door ) )
        return;
    linked_triggers = zt_door_group_triggers( door );
    zt_door_group_stop_buy_waiters( door );
    door.has_been_opened = 1;
    normalized = 0;
    foreach ( linked_trigger in linked_triggers )
    {
        linked_trigger triggerenable( 0 );
        linked_trigger.has_been_opened = 1;
        if ( !isdefined( linked_trigger._door_open ) || !linked_trigger._door_open )
        {
            // The physical blocker already moved with another member of this
            // linked group. Publish the same semantic state as stock without
            // calling door_opened again and toggling that model closed.
            linked_trigger._door_open = 1;
            linked_trigger notify( #"door_opened" );
            if ( isdefined( linked_trigger.script_flag ) )
            {
                tokens = strtok( linked_trigger.script_flag, "," );
                foreach ( token in tokens )
                    if ( level flag::exists( token ) )
                        level flag::set( token );
            }
            normalized = 1;
        }
    }
    if ( normalized )
        level notify( #"door_opened" );
}

zt_open_standard_door_group( door )
{
    if ( !zt_door_group_ready( door ) )
        return 0;
    // Any open trigger proves that the one physical blocker group has already
    // moved. Normalize the remaining linked trigger state to open; never call
    // the stock toggle on a mixed group or it will close the open members.
    if ( zt_door_group_has_open_trigger( door ) )
    {
        zt_door_group_normalize_open( door );
        return 1;
    }
    if ( zt_door_group_is_moving( door ) )
        return 0;

    // door_think may still be suspended inside door_buy. Retire every waiter
    // immediately before the authoritative stock open call so no queued buy
    // notification can race and toggle the group back closed.
    if ( isdefined( level.script ) && level.script == "zm_tomb" )
        return zt_open_tomb_door_group( door );
    // Map initialization/quests can retire physical parts after registering
    // their trigger. Stock door_opened dereferences every array entry.
    surviving_parts = [];
    foreach ( part in door.doors )
        if ( isdefined( part ) )
            surviving_parts[surviving_parts.size] = part;
    door.doors = surviving_parts;
    zt_door_group_stop_buy_waiters( door );
    door zm_blockers::door_opened( 0 );
    return zt_door_group_has_open_trigger( door );
}

zt_open_tomb_door_group( door )
{
    // Origins' bunker_door_clean_up deletes these models on movedone.
    // The generic door_activate also forks door_solid_thread, which resumes
    // on the same movedone and calls IsTouching on the removed model forever.
    // Keep stock trigger/flag/zone semantics, but give ONLY these disposable
    // moving models a one-shot opener with no post-move collision waiter.
    original_parts = door.doors;
    stock_parts = [];
    bunker_parts = [];
    foreach ( part in original_parts )
    {
        if ( !isdefined( part ) )
            continue;
        if ( !isdefined( part.script_noteworthy ) || part.script_noteworthy != "bunker_door" )
        {
            stock_parts[stock_parts.size] = part;
            continue;
        }
        // Unknown animation/class variants remain map-owned, not guessed.
        if ( ( part.classname != "script_model" && part.classname != "script_brushmodel" ) ||
            !isdefined( part.script_string ) || ( part.script_string != "move" && part.script_string != "slide_apart" ) ||
            !isdefined( part.script_vector ) ||
            ( isdefined( part.script_transition_time ) && part.script_transition_time <= 0 ) )
            return 0;
        bunker_parts[bunker_parts.size] = part;
    }
    zt_door_group_stop_buy_waiters( door );
    door.doors = stock_parts;
    foreach ( part in bunker_parts )
        part zt_tomb_bunker_open();
    // Stock still opens every linked trigger, publishes flags and zone access,
    // and animates the other physical parts (including clips/traversal nodes).
    door zm_blockers::door_opened( 0 );
    // The stock call yields. Never restore references deleted during it.
    surviving_parts = [];
    foreach ( part in original_parts )
        if ( isdefined( part ) )
            surviving_parts[surviving_parts.size] = part;
    if ( isdefined( door ) )
        door.doors = surviving_parts;
    return zt_door_group_has_open_trigger( door );
}

zt_tomb_bunker_open()
{
    if ( isdefined( self.door_moving ) )
        return;
    time = 1;
    if ( isdefined( self.script_transition_time ) )
        time = self.script_transition_time;
    self.door_moving = 1;
    level notify( #"snddooropening" );
    self notsolid();
    self connectpaths();
    if ( isdefined( self.script_sound ) )
        playsoundatposition( self.script_sound, self.origin );
    else
        zm_utility::play_sound_at_pos( "zmb_heavy_door_open", self.origin );
    if ( isdefined( self.script_firefx ) )
        playfx( level._effect[self.script_firefx], self.origin );
    // Match stock travel and easing. The MAP owns movedone and deletion;
    // no synthetic movement notification, wait, Solid, or Delete belongs here.
    if ( time >= 0.5 )
        self moveto( self.origin + self.script_vector, time, time * 0.25, time * 0.25 );
    else
        self moveto( self.origin + self.script_vector, time );
}

zt_moon_airlock_hackable( airlock )
{
    if ( !isdefined( level._hackable_objects ) )
        return undefined;
    foreach ( hackable in level._hackable_objects )
    {
        if ( isdefined( hackable.door ) && hackable.door == airlock && isdefined( hackable.door_activate_func ) && isdefined( hackable._hack_callback_func ) )
            return hackable;
    }
    return undefined;
}

zt_moon_airlock_ready( airlock )
{
    if ( !isdefined( airlock ) || !isdefined( airlock.trigs ) || !isarray( airlock.trigs ) )
        return 0;
    hackable = zt_moon_airlock_hackable( airlock );
    return isdefined( hackable );
}

zt_open_moon_airlock( airlock, door_user )
{
    if ( !isdefined( airlock ) || !isdefined( door_user ) || !isplayer( door_user ) )
        return 0;
    if ( isdefined( airlock._door_open ) && airlock._door_open )
        return 1;
    hackable = zt_moon_airlock_hackable( airlock );
    if ( !isdefined( hackable ) )
        return 0;
    // Invoke the registered hacker callback rather than a one-shot purchase
    // notification. Stock door_hack retires the buy thinker and hack registry,
    // calls Moon's stored moon_door_opened function, and publishes _door_open.
    hackable [[ hackable._hack_callback_func ]]( door_user );
    if ( !isdefined( airlock ) || !isdefined( airlock._door_open ) || !airlock._door_open )
        return 0;
    linked_airlocks = getentarray( airlock.target, "target" );
    foreach ( linked_airlock in linked_airlocks )
    {
        linked_airlock notify( #"kill_door_think" );
        linked_airlock._door_open = 1;
    }
    return 1;
}

zt_start_doors_unlock_cleanup( previous_value, generation )
{
    // Deliberately has no end_game endon: even a match-end interrupt must put
    // the process-global affordability DVAR back exactly as it was.
    util::wait_network_frame();
    if ( isdefined( level.zt.start_doors_unlock_generation ) && level.zt.start_doors_unlock_generation == generation )
        setdvar( "zombie_unlock_all", previous_value );
}

zt_force_standard_debris( blocker, door_user )
{
    if ( !isdefined( blocker ) || !isdefined( door_user ) || !isplayer( door_user ) )
        return;
    if ( !isdefined( level.zt.start_doors_unlock_generation ) )
        level.zt.start_doors_unlock_generation = 0;
    level.zt.start_doors_unlock_generation++;
    generation = level.zt.start_doors_unlock_generation;
    previous_value = getdvarint( "zombie_unlock_all" );
    setdvar( "zombie_unlock_all", 1 );
    level thread zt_start_doors_unlock_cleanup( previous_value, generation );
    blocker notify( #"trigger", door_user, 1 );
    util::wait_network_frame();
    if ( level.zt.start_doors_unlock_generation == generation )
        setdvar( "zombie_unlock_all", previous_value );
}

zt_debris_completed( blocker )
{
    if ( !isdefined( blocker ) )
        return 1;
    if ( isdefined( blocker.script_flag ) )
    {
        tokens = strtok( blocker.script_flag, "," );
        all_set = tokens.size > 0;
        foreach ( token in tokens )
            if ( !level flag::exists( token ) || !level flag::get( token ) )
                all_set = 0;
        if ( all_set )
            return 1;
    }
    if ( isdefined( blocker.target ) && getentarray( blocker.target, "target" ).size == 0 )
        return 1;
    return 0;
}

zt_start_doors_install()
{
    level endon( #"end_game" );

    // Blocker registries are not stable during stock cinematics. In
    // particular, scanning Shadows of Evil throughout its intro both produces
    // a false no-blockers result and competes with map startup. Stay dormant
    // until the same lifecycle boundary used by the stock round system.
    while ( !zt_game_ready() )
        wait 0.1;

    map_name = level.script;
    elapsed = 0;
    doors = [];
    airlocks = [];
    debris = [];
    players = [];
    supported = 0;
    all_ready = 0;
    // Once gameplay owns the map, allow late blocker threads a bounded window
    // to finish publishing linked groups without doing work during the intro.
    while ( elapsed < 30 )
    {
        doors = getentarray( "zombie_door", "targetname" );
        airlocks = getentarray( "zombie_airlock_buy", "targetname" );
        debris = getentarray( "zombie_debris", "targetname" );
        players = getplayers();
        supported = 0;
        all_ready = 1;
        foreach ( door in doors )
        {
            if ( !zt_supported_door_trigger( door, map_name ) )
                continue;
            supported++;
            if ( !zt_door_group_ready( door ) )
                all_ready = 0;
        }
        foreach ( blocker in debris )
        {
            if ( !isdefined( blocker ) )
                continue;
            if ( isdefined( blocker.script_noteworthy ) && blocker.script_noteworthy != "default" )
                continue;
            supported++;
            if ( !isdefined( blocker.target ) || !isdefined( blocker.zombie_cost ) )
                all_ready = 0;
        }
        if ( map_name == "zm_moon" )
        {
            foreach ( airlock in airlocks )
            {
                supported++;
                if ( !zt_moon_airlock_ready( airlock ) )
                    all_ready = 0;
            }
        }

        if ( players.size > 0 && supported > 0 && all_ready )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( players.size == 0 || supported == 0 )
    {
        zt_feature( "start_doors_open", "unavailable", "map exposes no initialized ordinary traversal blockers" );
        return;
    }
    custom_door_owner = isdefined( level.custom_door_buy_check ) || isdefined( level._default_door_custom_logic );
    custom_debris_owner = isdefined( level.custom_debris_function );
    map_owned_skipped = 0;
    completed = 0;
    owned_total = 0;
    group_doors = [];
    seen_targets = [];

    if ( !custom_door_owner )
    {
        foreach ( door in doors )
        {
            if ( !zt_supported_door_trigger( door, map_name ) )
            {
                map_owned_skipped++;
                continue;
            }
            if ( !zt_door_group_ready( door ) || !isdefined( door.target ) )
            {
                map_owned_skipped++;
                continue;
            }
            if ( isdefined( seen_targets[door.target] ) )
                continue;
            seen_targets[door.target] = 1;
            group_doors[group_doors.size] = door;
            owned_total++;
        }
        if ( group_doors.size > 0 )
            level.local_doors_stay_open = 1;

        // Moving groups are left untouched until their stock animation has
        // completed. Re-evaluate for up to five seconds; every pass is an
        // idempotent any-open check followed by a proven-closed open attempt.
        for ( retry = 0; retry < 20; retry++ )
        {
            pending = 0;
            foreach ( retry_door in group_doors )
            {
                if ( zt_door_group_has_open_trigger( retry_door ) )
                {
                    zt_door_group_normalize_open( retry_door );
                    continue;
                }
                pending++;
                zt_open_standard_door_group( retry_door );
            }
            if ( pending == 0 )
                break;
            wait 0.25;
        }

        foreach ( door in group_doors )
        {
            if ( zt_door_group_has_open_trigger( door ) )
                completed++;
            else
                map_owned_skipped++;
        }
    }
    else
    {
        foreach ( door in doors )
            if ( zt_supported_door_trigger( door, map_name ) )
                map_owned_skipped++;
    }

    airlock_candidates = [];
    if ( map_name == "zm_moon" )
    {
        airlock_targets = [];
        foreach ( airlock in airlocks )
        {
            if ( !zt_moon_airlock_ready( airlock ) || !isdefined( airlock.target ) )
            {
                map_owned_skipped++;
                continue;
            }
            if ( isdefined( airlock_targets[airlock.target] ) )
                continue;
            airlock_targets[airlock.target] = 1;
            airlock_candidates[airlock_candidates.size] = airlock;
            owned_total++;
            if ( zt_open_moon_airlock( airlock, players[0] ) )
                completed++;
            else
                map_owned_skipped++;
        }
    }

    debris_candidates = [];
    if ( !custom_debris_owner )
    {
        foreach ( blocker in debris )
        {
            // Ordinary zombie_debris handlers move their linked models,
            // zbarriers, clips and traversal nodes. Standalone repair barriers,
            // flag_blocker and explicitly noteworthy quest blockers are never
            // enumerated or globally notified.
            if ( !isdefined( blocker ) || ( isdefined( blocker.script_noteworthy ) && blocker.script_noteworthy != "default" ) || !isdefined( blocker.target ) )
            {
                map_owned_skipped++;
                continue;
            }
            debris_candidates[debris_candidates.size] = blocker;
            owned_total++;
            zt_force_standard_debris( blocker, players[0] );
        }
        wait 0.5;
        foreach ( blocker in debris_candidates )
        {
            if ( zt_debris_completed( blocker ) )
                completed++;
            else
                map_owned_skipped++;
        }
    }
    else
    {
        foreach ( blocker in debris )
            if ( isdefined( blocker ) && ( !isdefined( blocker.script_noteworthy ) || blocker.script_noteworthy == "default" ) )
                map_owned_skipped++;
    }

    if ( owned_total == 0 )
        zt_feature( "start_doors_open", "degraded", "custom/counter/quest blocker owners were preserved; no ordinary blocker was safe to claim" );
    else if ( completed == owned_total && map_owned_skipped == 0 && all_ready )
        zt_feature( "start_doors_open", "active", "opened every initialized ordinary door, linked barrier, debris group and Moon buy airlock" );
    else if ( completed > 0 )
        zt_feature( "start_doors_open", "degraded", "opened initialized ordinary traversal blockers; custom, counter, cycling-airlock and quest owners were preserved" );
    else
        zt_feature( "start_doors_open", "unavailable", "stock ordinary blocker routes did not publish completion" );
}

zt_scaled_limit( value, percent )
{
    scaled = int( value * percent / 100.0 + 0.5 );
    if ( scaled < 1 )
        scaled = 1;
    return scaled;
}

zt_gobblegum_limits_install()
{
    level endon( #"end_game" );

    // bgb::register creates entries before bgb_finalize assigns item_index.
    // Wait for that final marker instead of scaling a partially built snapshot.
    // A late custom registry remains recoverable after the compatibility page
    // has reported its initial absence.
    post_ready_elapsed = 0;
    missing_reported = 0;
    keys = [];
    while ( 1 )
    {
        finalized_count = 0;
        if ( isdefined( level.bgb ) )
        {
            keys = getarraykeys( level.bgb );
            foreach ( key in keys )
                if ( isdefined( level.bgb[key].item_index ) )
                    finalized_count++;
            // One malformed or still-building custom entry must not hold the
            // finalized stock registry hostage. The live loop below skips it
            // until its own item_index appears.
            if ( finalized_count > 0 )
                break;
        }

        if ( zt_game_ready() )
        {
            post_ready_elapsed += 0.1;
            if ( post_ready_elapsed >= 20 && !missing_reported )
            {
                if ( level.zt.config.gobblegum_uses > 0 ) zt_feature( "gobblegum_uses", "unavailable", "map has not published a finalized stock GobbleGum registry" );
                if ( level.zt.config.gobblegum_time > 0 ) zt_feature( "gobblegum_time", "unavailable", "map has not published a finalized stock GobbleGum registry" );
                if ( level.zt.config.gobblegum_rounds > 0 ) zt_feature( "gobblegum_rounds", "unavailable", "map has not published a finalized stock GobbleGum registry" );
                missing_reported = 1;
            }
        }
        wait 0.1;
    }

    while ( 1 )
    {
        // NEXT GUM settings are read live. Re-enumeration also catches gums a
        // custom map registers after the stock registry finalized.
        level.zt.config.gobblegum_uses = zt_cfg_int( "zt_gobblegum_uses", 0 );
        level.zt.config.gobblegum_time = zt_cfg_int( "zt_gobblegum_time", 0 );
        level.zt.config.gobblegum_rounds = zt_cfg_int( "zt_gobblegum_rounds", 0 );
        keys = getarraykeys( level.bgb );
        uses_count = 0;
        time_count = 0;
        rounds_count = 0;
        foreach ( key in keys )
        {
            gum = level.bgb[key];
            if ( !isdefined( gum.item_index ) || !isdefined( gum.limit_type ) || !isdefined( gum.limit ) )
                continue;
            percent = 0;
            if ( gum.limit_type == "activated" )
            {
                percent = level.zt.config.gobblegum_uses;
                uses_count++;
            }
            else if ( gum.limit_type == "time" )
            {
                percent = level.zt.config.gobblegum_time;
                time_count++;
            }
            else if ( gum.limit_type == "rounds" )
            {
                percent = level.zt.config.gobblegum_rounds;
                rounds_count++;
            }

            if ( percent > 0 )
            {
                if ( !isdefined( gum.ztweaks_base_limit ) )
                    gum.ztweaks_base_limit = gum.limit;
                gum.limit = zt_scaled_limit( gum.ztweaks_base_limit, percent );
                gum.ztweaks_owned = 1;
            }
            else if ( zt_true( gum.ztweaks_owned ) )
            {
                if ( isdefined( gum.ztweaks_base_limit ) )
                    gum.limit = gum.ztweaks_base_limit;
                gum.ztweaks_owned = 0;
                gum.ztweaks_base_limit = undefined;
            }
        }

        if ( level.zt.config.gobblegum_uses > 0 )
        {
            if ( uses_count > 0 )
                zt_feature( "gobblegum_uses", "active", "" );
            else
                zt_feature( "gobblegum_uses", "unavailable", "map registered no activation-limited GobbleGums" );
        }
        if ( level.zt.config.gobblegum_time > 0 )
        {
            if ( time_count > 0 )
                zt_feature( "gobblegum_time", "active", "" );
            else
                zt_feature( "gobblegum_time", "unavailable", "map registered no time-limited GobbleGums" );
        }
        if ( level.zt.config.gobblegum_rounds > 0 )
        {
            if ( rounds_count > 0 )
                zt_feature( "gobblegum_rounds", "active", "" );
            else
                zt_feature( "gobblegum_rounds", "unavailable", "map registered no round-limited GobbleGums" );
        }

        if ( level.zt.config.gobblegum_uses > 0 || level.zt.config.gobblegum_time > 0 || level.zt.config.gobblegum_rounds > 0 )
            wait 0.25;
        else
            wait 1;
    }
}

// BO3's stock vending loop charges current_cost from self.cost for every use.
// Wait until a machine has completed its power-on hint setup, then update the
// charged value and localized stock hint together. BO2 instead caches a local
// cost before its endless loop, so this adapter intentionally has no T6 twin.
zt_transition_feature( name, state, reason )
{
    if ( isdefined( level.zt.features[name] ) && level.zt.features[name].state == state && level.zt.features[name].reason == reason ) return;
    zt_feature( name, state, reason );
}

// Both stock Zombies health-regeneration loops read this delay from level on
// each damage check. Keep the late map baseline so custom maps can still set
// their own delay; no script-local regeneration rate is replaced.
zt_regen_delay_install()
{
    level endon( #"end_game" );
    while ( !zt_game_ready() ) wait 0.25;
    elapsed = 0;
    while ( true )
    {
        if ( isdefined( level.playerhealth_regularregendelay ) && level.playerhealth_regularregendelay > 0 )
        {
            state = zt_scale_owned_match_value( level.playerhealth_regularregendelay, level.zt.regen_delay_stock, level.zt.regen_delay_applied, level.zt.config.health_regen_delay );
            level.zt.regen_delay_stock = state.stock;
            level.zt.regen_delay_applied = state.applied;
            level.playerhealth_regularregendelay = state.applied;
            zt_transition_feature( "health_regen_delay", "active", "" );
        }
        else if ( elapsed >= 10 )
            zt_transition_feature( "health_regen_delay", "unavailable", "map exposes no standard health-regeneration delay" );
        wait 0.5;
        elapsed = elapsed + 0.5;
    }
}

zt_perk_price_install()
{
    level endon( #"end_game" );
    elapsed = 0;
    while ( true )
    {
        machines = GetEntArray( "zombie_vending", "targetname" );
        applied = 0;
        skipped = 0;
        powered = 0;
        for ( i = 0; i < machines.size; i++ )
        {
            machine = machines[i];
            if ( !isdefined( machine.cost ) || !isdefined( machine.script_noteworthy ) ) continue;
            perk = machine.script_noteworthy;
            if ( !isdefined( level._custom_perks ) || !isdefined( level._custom_perks[perk] ) || !isdefined( level._custom_perks[perk].hint_string ) || ( isdefined( level._custom_perks[perk].cost ) && isfunctionptr( level._custom_perks[perk].cost ) ) )
            {
                skipped++;
                continue;
            }
            if ( zt_true( machine.zt_perk_price_owner_lost ) )
            {
                skipped++;
                continue;
            }
            if ( !zt_true( machine.power_on ) )
            {
                machine.zt_perk_price_ready_ticks = 0;
                machine.zt_perk_price_rearm = 1;
                machine.zt_perk_hint_applied = 0;
                continue;
            }
            powered++;
            if ( !isdefined( machine.zt_perk_price_ready_ticks ) ) machine.zt_perk_price_ready_ticks = 0;
            // Stock vending_trigger_think may defer its own hint while power
            // propagates across the perk-machine network. Let it finish first.
            if ( machine.zt_perk_price_ready_ticks < 8 )
            {
                machine.zt_perk_price_ready_ticks++;
                continue;
            }
            if ( !isdefined( machine.zt_perk_price_base ) ) machine.zt_perk_price_base = machine.cost;
            cost = int( machine.zt_perk_price_base * level.zt.config.perk_price_multiplier / 100.0 + 0.5 );
            if ( isdefined( machine.zt_perk_price_applied ) && machine.cost != machine.zt_perk_price_applied && !( zt_true( machine.zt_perk_price_rearm ) && machine.cost == machine.zt_perk_price_base ) )
            {
                machine.zt_perk_price_owner_lost = 1;
                skipped++;
                continue;
            }
            machine.cost = cost;
            machine.zt_perk_price_applied = cost;
            applied++;
            if ( !zt_true( machine.zt_perk_hint_applied ) )
            {
                machine SetHintString( level._custom_perks[perk].hint_string, cost );
                machine.zt_perk_hint_applied = 1;
            }
            machine.zt_perk_price_rearm = 0;
        }
        if ( applied > 0 )
        {
            if ( skipped > 0 ) zt_transition_feature( "perk_price_multiplier", "degraded", "custom or changed perk purchases remain map-owned" );
            else zt_transition_feature( "perk_price_multiplier", "active", "" );
        }
        else if ( elapsed >= 10 && ( machines.size == 0 || powered > 0 ) )
        {
            if ( skipped > 0 ) zt_transition_feature( "perk_price_multiplier", "unavailable", "map owns its perk purchase hints or prices" );
            else zt_transition_feature( "perk_price_multiplier", "unavailable", "map has no standard perk machines" );
        }
        wait 0.25;
        elapsed = elapsed + 0.25;
    }
}

zt_wunderfizz_price_install()
{
    level endon( #"end_game" );
    // Stock Wunderfizz reads this live level value for hint, purchase and
    // refund. Its per-machine cost is not the value actually charged.
    while ( !zt_game_ready() )
        wait 0.25;
    elapsed = 0;
    while ( 1 )
    {
        if ( isdefined( level.perk_random_machines ) && level.perk_random_machines.size > 0 && isdefined( level._random_zombie_perk_cost ) && ( level._random_zombie_perk_cost > 0 || isdefined( level.zt.wunderfizz_price_applied ) ) )
        {
            current = level._random_zombie_perk_cost;
            if ( isdefined( level.zt.wunderfizz_price_applied ) && current != level.zt.wunderfizz_price_applied )
            {
                zt_transition_feature( "wunderfizz_price_multiplier", "degraded", "map replaced the Wunderfizz price; its value remains map-owned" );
                return;
            }
            if ( !isdefined( level.zt.wunderfizz_price_stock ) )
                level.zt.wunderfizz_price_stock = current;
            price = int( level.zt.wunderfizz_price_stock * level.zt.config.wunderfizz_price_multiplier / 100.0 + 0.5 );
            if ( price < 0 ) price = 0;
            level._random_zombie_perk_cost = price;
            level.zt.wunderfizz_price_applied = price;
            zt_transition_feature( "wunderfizz_price_multiplier", "active", "" );
        }
        else if ( elapsed >= 20 )
            zt_transition_feature( "wunderfizz_price_multiplier", "unavailable", "map exposes no standard Wunderfizz machine or price" );
        elapsed += 0.5;
        wait 0.5;
    }
}

zt_perk_limit_install()
{
    level endon( #"end_game" );

    while ( !zt_game_ready() )
        wait 0.25;

    // ZShare waits two seconds on this engine. Install after it so the
    // explicit ZTweaks value owns the final callback.
    wait 3.25;

    elapsed = 0;
    missing_reported = 0;
    while ( !isdefined( level.get_player_perk_purchase_limit ) && !isdefined( level.perk_purchase_limit ) )
    {
        wait 0.25;
        elapsed += 0.25;
        if ( elapsed >= 20 && !missing_reported )
        {
            zt_feature( "perk_limit", "unavailable", "map has not published a perk-limit capability" );
            missing_reported = 1;
        }
    }

    if ( isdefined( level.get_player_perk_purchase_limit ) )
    {
        level.zt_perk_limit_prev = level.get_player_perk_purchase_limit;
        level.zt_perk_limit_base = level.get_player_perk_purchase_limit;
    }
    level.zt_perk_limit_chain = [];
    level.zt_perk_limit_inside = 0;

    level.get_player_perk_purchase_limit = ::zt_perk_limit_get;
    level thread zt_perk_limit_owner_watch();
    zt_feature( "perk_limit", "active", "" );
}

zt_perk_limit_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        if ( !isdefined( level.get_player_perk_purchase_limit ) )
        {
            zt_perk_limit_release_owner();
            level.get_player_perk_purchase_limit = ::zt_perk_limit_get;
        }
        else if ( level.get_player_perk_purchase_limit != ::zt_perk_limit_get )
        {
            zt_perk_limit_adopt_owner( level.get_player_perk_purchase_limit );
            level.get_player_perk_purchase_limit = ::zt_perk_limit_get;
        }
        wait 0.25;
    }
}

zt_perk_limit_release_owner()
{
    if ( !isdefined( level.zt_perk_limit_chain ) || level.zt_perk_limit_chain.size <= 0 )
    {
        level.zt_perk_limit_chain = [];
        level.zt_perk_limit_prev = level.zt_perk_limit_base;
        return;
    }

    previous_index = level.zt_perk_limit_chain.size - 1;
    previous = level.zt_perk_limit_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_perk_limit_chain[i];
    level.zt_perk_limit_chain = restored_chain;
    level.zt_perk_limit_prev = previous;
}

zt_perk_limit_adopt_owner( owner )
{
    if ( !isdefined( level.zt_perk_limit_chain ) )
        level.zt_perk_limit_chain = [];
    if ( !isdefined( level.zt_perk_limit_prev ) )
    {
        level.zt_perk_limit_prev = owner;
        return;
    }
    if ( level.zt_perk_limit_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_perk_limit_chain.size; i++ )
    {
        if ( level.zt_perk_limit_chain[i] == owner )
            restored_index = i;
    }
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_perk_limit_chain[i];
        level.zt_perk_limit_chain = restored_chain;
    }
    else
        level.zt_perk_limit_chain[level.zt_perk_limit_chain.size] = level.zt_perk_limit_prev;
    level.zt_perk_limit_prev = owner;
}

zt_zshare_stock_perk_limit_available()
{
    return isdefined( level.zmods ) && isdefined( level.zmods["zshare"] ) &&
           isdefined( level.zmods["zshare"].api_version ) && level.zmods["zshare"].api_version >= 1 &&
           isdefined( level.zmods["zshare"].get_stock_perk_limit );
}

zt_perk_limit_forward()
{
    depth = 0;
    if ( isdefined( level.zt_perk_limit_inside ) )
        depth = level.zt_perk_limit_inside;

    callback = level.zt_perk_limit_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_perk_limit_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_perk_limit_chain[chain_index];
        else
            callback = level.zt_perk_limit_base;
    }
    if ( !isdefined( callback ) || isdefined( level.zt_perk_limit_base ) && callback == level.zt_perk_limit_base )
        return self zt_base_perk_limit();

    level.zt_perk_limit_inside = depth + 1;
    result = self [[ callback ]]();
    level.zt_perk_limit_inside = depth;
    if ( !isdefined( result ) )
        result = self zt_base_perk_limit();
    return result;
}

zt_map_perk_limit()
{
    return self zt_perk_limit_forward();
}

zt_base_perk_limit()
{
    if ( zt_zshare_stock_perk_limit_available() )
        return [[ level.zmods["zshare"].get_stock_perk_limit ]]( self );

    // Legacy fallback for an older ZShare build which predates its public
    // descriptor. New builds are consumed only through level.zmods.
    if ( zt_true( level.zs_loaded ) && isdefined( level.zs_perk_limit_stock ) )
        return self [[ level.zs_perk_limit_stock ]]();

    if ( isdefined( level.zt_perk_limit_base ) )
        return self [[ level.zt_perk_limit_base ]]();

    if ( isdefined( level.perk_purchase_limit ) )
        return level.perk_purchase_limit;

    return 4;
}

zt_perk_limit_get()
{
    if ( zt_true( level.zt_perk_limit_inside ) )
        return self zt_perk_limit_forward();

    if ( level.zt.config.challenge_no_perks )
        return 0;
    wanted = level.zt.config.perk_limit;
    if ( wanted < 0 )
        return 32;

    map_limit = self zt_map_perk_limit();
    extra = map_limit - 4;
    if ( extra < 0 )
        extra = 0;

    return wanted + extra;
}

zt_damage_tweaks_install()
{
    // The outer player-damage owner introduced in 0.1.132.d coincides exactly
    // with Shadows' post-intro black-screen regression. Restore the passive
    // stock callback route from the last gameplay-proven build while leaving
    // the map's level/per-player overrides entirely under stock ownership.
    zm::register_player_damage_callback( ::zt_player_damage );

    if ( level.zt.config.weapon_damage > 0 || level.zt.config.melee_damage > 0 || level.zt.config.challenge_rising_damage > 0 || level.zt.config.pap_damage_multiplier > 0 )
    {
        // actor_damage_callbacks is a first-non--1 chain. Registering a
        // multiplier there can bypass later map/quest handlers, while being
        // registered later can prevent the multiplier from running at all.
        // Own the published outer callback instead so the entire stock/map
        // pipeline receives the scaled input and can still override it.
        elapsed = 0;
        missing_reported = 0;
        while ( !isdefined( level.callbackactordamage ) )
        {
            wait 0.05;
            elapsed += 0.05;
            if ( elapsed >= 20 && !missing_reported )
            {
                if ( level.zt.config.weapon_damage > 0 ) zt_feature( "weapon_damage", "unavailable", "map has not published an actor-damage callback" );
                if ( level.zt.config.melee_damage > 0 ) zt_feature( "melee_damage", "unavailable", "map has not published an actor-damage callback" );
                if ( level.zt.config.challenge_rising_damage > 0 ) zt_feature( "challenge_rising_damage", "unavailable", "map has not published an actor-damage callback" );
                if ( level.zt.config.pap_damage_multiplier > 0 ) zt_feature( "pap_damage_multiplier", "unavailable", "map has not published an actor-damage callback" );
                missing_reported = 1;
            }
        }
        level.zt_actor_damage_prev = level.callbackactordamage;
        level.zt_actor_damage_base = level.callbackactordamage;
        level.zt_actor_damage_chain = [];
        level.zt_actor_damage_inside = 0;
        level.callbackactordamage = ::zt_actor_damage_wrapper;
        level thread zt_actor_damage_owner_watch();
        if ( level.zt.config.weapon_damage > 0 ) zt_feature( "weapon_damage", "active", "ordinary enemy hits compose outside the map's actor-damage pipeline" );
        if ( level.zt.config.melee_damage > 0 ) zt_feature( "melee_damage", "active", "ordinary enemy hits compose outside the map's actor-damage pipeline" );
        if ( level.zt.config.challenge_rising_damage > 0 ) zt_feature( "challenge_rising_damage", "active", "ordinary enemy hits compose outside the map's actor-damage pipeline" );
        if ( level.zt.config.pap_damage_multiplier > 0 ) zt_feature( "pap_damage_multiplier", "active", "registered upgrades only; custom upgrade systems remain map-owned" );
    }
    if ( level.zt.config.no_explosive_self_damage ) zt_feature( "no_explosive_self_damage", "active", "" );
    if ( level.zt.config.fall_damage != 0 ) zt_feature( "fall_damage", "active", "" );
}

zt_player_damage_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        spawn_protection = zt_cfg_int( "zt_spawn_protection", 0 );
        no_self_damage = zt_cfg_int( "zt_no_explosive_self_damage", 0 );
        fall_damage = zt_cfg_int( "zt_fall_damage", 0 );
        zombie_damage = level.zt.config.zombie_damage;
        level.zt.config.spawn_protection = spawn_protection;
        level.zt.config.no_explosive_self_damage = no_self_damage;
        level.zt.config.fall_damage = fall_damage;
        enabled = spawn_protection > 0 || no_self_damage || fall_damage != 0 || zombie_damage > 0;

        if ( enabled && !zt_true( level.zt_player_damage_owned ) && isdefined( level.overrideplayerdamage ) )
        {
            if ( !isdefined( level.zt_player_damage_base ) )
                level.zt_player_damage_base = level.overrideplayerdamage;
            zt_player_damage_adopt_owner( level.overrideplayerdamage, 1 );
            level.overrideplayerdamage = ::zt_player_damage_wrapper;
            level.zt_player_damage_installed = 1;
            level.zt_player_damage_owned = 1;
            level.zt_player_damage_detached = 0;
            level.zt_player_damage_missing_reported = 0;
            if ( spawn_protection > 0 ) zt_feature( "spawn_protection", "active", "composed before the map's player-damage pipeline" );
            if ( no_self_damage ) zt_feature( "no_explosive_self_damage", "active", "composed before the map's player-damage pipeline" );
            if ( fall_damage != 0 ) zt_feature( "fall_damage", "active", "composed before the map's player-damage pipeline" );
            if ( zombie_damage > 0 ) zt_feature( "zombie_damage", "active", "composed before the map's player-damage pipeline" );
        }
        else if ( enabled && zt_true( level.zt_player_damage_owned ) && !isdefined( level.overrideplayerdamage ) )
        {
            zt_player_damage_release_owner();
            level.overrideplayerdamage = ::zt_player_damage_wrapper;
        }
        else if ( enabled && zt_true( level.zt_player_damage_owned ) && level.overrideplayerdamage != ::zt_player_damage_wrapper )
        {
            zt_player_damage_adopt_owner( level.overrideplayerdamage, 0 );
            level.overrideplayerdamage = ::zt_player_damage_wrapper;
        }
        else if ( enabled && !zt_true( level.zt_player_damage_owned ) && !isdefined( level.overrideplayerdamage ) )
        {
            level.zt_player_damage_installed = 0;
            if ( !zt_true( level.zt_player_damage_missing_reported ) )
            {
                if ( spawn_protection > 0 ) zt_feature( "spawn_protection", "unavailable", "map exposes no composable player-damage override" );
                if ( no_self_damage ) zt_feature( "no_explosive_self_damage", "unavailable", "map exposes no composable player-damage override" );
                if ( fall_damage != 0 ) zt_feature( "fall_damage", "unavailable", "map exposes no composable player-damage override" );
                if ( zombie_damage > 0 ) zt_feature( "zombie_damage", "unavailable", "map exposes no composable player-damage override" );
                level.zt_player_damage_missing_reported = 1;
            }
        }
        else if ( !enabled && zt_true( level.zt_player_damage_owned ) )
        {
            if ( isdefined( level.overrideplayerdamage ) && level.overrideplayerdamage == ::zt_player_damage_wrapper )
                level.overrideplayerdamage = level.zt_player_damage_prev;
            else if ( isdefined( level.overrideplayerdamage ) )
                zt_player_damage_adopt_owner( level.overrideplayerdamage, 0 );
            else
            {
                zt_player_damage_release_owner();
                level.overrideplayerdamage = level.zt_player_damage_prev;
            }
            level.zt_player_damage_installed = 0;
            level.zt_player_damage_owned = 0;
            level.zt_player_damage_detached = 1;
            zt_feature( "spawn_protection", "inherit", "" );
            zt_feature( "no_explosive_self_damage", "inherit", "" );
            zt_feature( "fall_damage", "inherit", "" );
            zt_feature( "zombie_damage", "inherit", "" );
        }
        else if ( !enabled )
        {
            level.zt_player_damage_installed = 0;
            level.zt_player_damage_missing_reported = 0;
        }
        // This permanent ownership poll does not need frame-boundary precision.
        // A bounded yield keeps it responsive without continuously rescheduling
        // at T7x's frame-end boundary, which can starve server command traffic.
        wait 0.05;
    }
}

zt_personal_damage_player_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            player = players[i];
            if ( !zt_true( player.zt_personal_damage_watch ) )
            {
                player.zt_personal_damage_watch = 1;
                player thread zt_personal_damage_owner_watch();
            }
        }
        wait 0.25;
    }
}

zt_personal_damage_owner_watch()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    self.zt_personal_damage_owned = 0;
    self.zt_personal_damage_detached = 1;
    self.zt_personal_damage_chain = [];
    self.zt_personal_damage_inside = 0;

    while ( 1 )
    {
        spawn_protection = zt_cfg_int( "zt_spawn_protection", 0 );
        no_self_damage = zt_cfg_int( "zt_no_explosive_self_damage", 0 );
        fall_damage = zt_cfg_int( "zt_fall_damage", 0 );
        zombie_damage = level.zt.config.zombie_damage;
        enabled = spawn_protection > 0 || no_self_damage || fall_damage != 0 || zombie_damage > 0;

        if ( enabled && !zt_true( self.zt_personal_damage_owned ) && isdefined( self.overrideplayerdamage ) )
        {
            if ( !isdefined( self.zt_personal_damage_base ) )
                self.zt_personal_damage_base = self.overrideplayerdamage;
            self zt_personal_damage_adopt_owner( self.overrideplayerdamage, 1 );
            self.overrideplayerdamage = ::zt_personal_damage_wrapper;
            self.zt_personal_damage_owned = 1;
            self.zt_personal_damage_detached = 0;
            if ( spawn_protection > 0 ) zt_feature( "spawn_protection", "active", "composed before Revelations' per-player damage pipeline" );
            if ( no_self_damage ) zt_feature( "no_explosive_self_damage", "active", "composed before Revelations' per-player damage pipeline" );
            if ( fall_damage != 0 ) zt_feature( "fall_damage", "active", "composed before Revelations' per-player damage pipeline" );
            if ( zombie_damage > 0 ) zt_feature( "zombie_damage", "active", "composed before Revelations' per-player damage pipeline" );
        }
        else if ( enabled && zt_true( self.zt_personal_damage_owned ) && !isdefined( self.overrideplayerdamage ) )
        {
            self zt_personal_damage_release_owner();
            self.overrideplayerdamage = ::zt_personal_damage_wrapper;
        }
        else if ( enabled && zt_true( self.zt_personal_damage_owned ) && self.overrideplayerdamage != ::zt_personal_damage_wrapper )
        {
            self zt_personal_damage_adopt_owner( self.overrideplayerdamage, 0 );
            self.overrideplayerdamage = ::zt_personal_damage_wrapper;
        }
        else if ( !enabled && zt_true( self.zt_personal_damage_owned ) )
        {
            if ( isdefined( self.overrideplayerdamage ) && self.overrideplayerdamage == ::zt_personal_damage_wrapper )
                self.overrideplayerdamage = self.zt_personal_damage_prev;
            else if ( isdefined( self.overrideplayerdamage ) )
                self zt_personal_damage_adopt_owner( self.overrideplayerdamage, 0 );
            else
            {
                self zt_personal_damage_release_owner();
                self.overrideplayerdamage = self.zt_personal_damage_prev;
            }
            self.zt_personal_damage_owned = 0;
            self.zt_personal_damage_detached = 1;
        }
        // Keep the per-player ownership check bounded for the same reason as
        // the level owner above. Damage callbacks remain synchronous; only the
        // low-priority ownership reconciliation runs at 20 Hz.
        wait 0.05;
    }
}

zt_personal_damage_release_owner()
{
    if ( !isdefined( self.zt_personal_damage_chain ) || self.zt_personal_damage_chain.size <= 0 )
    {
        self.zt_personal_damage_chain = [];
        self.zt_personal_damage_prev = self.zt_personal_damage_base;
        return;
    }

    previous_index = self.zt_personal_damage_chain.size - 1;
    previous = self.zt_personal_damage_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = self.zt_personal_damage_chain[i];
    self.zt_personal_damage_chain = restored_chain;
    self.zt_personal_damage_prev = previous;
}

zt_personal_damage_adopt_owner( owner, detached )
{
    if ( !isdefined( self.zt_personal_damage_chain ) )
        self.zt_personal_damage_chain = [];
    if ( !isdefined( self.zt_personal_damage_prev ) )
    {
        self.zt_personal_damage_prev = owner;
        return;
    }
    if ( self.zt_personal_damage_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < self.zt_personal_damage_chain.size; i++ )
    {
        if ( self.zt_personal_damage_chain[i] == owner )
            restored_index = i;
    }
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = self.zt_personal_damage_chain[i];
        self.zt_personal_damage_chain = restored_chain;
    }
    else if ( !detached )
        self.zt_personal_damage_chain[self.zt_personal_damage_chain.size] = self.zt_personal_damage_prev;
    self.zt_personal_damage_prev = owner;
}

zt_personal_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime )
{
    depth = 0;
    if ( isdefined( self.zt_personal_damage_inside ) )
        depth = self.zt_personal_damage_inside;

    callback = self.zt_personal_damage_prev;
    if ( depth > 0 )
    {
        chain_index = self.zt_personal_damage_chain.size - depth;
        if ( chain_index >= 0 )
            callback = self.zt_personal_damage_chain[chain_index];
        else
            callback = self.zt_personal_damage_base;
    }
    if ( !isdefined( callback ) )
        return damage;

    self.zt_personal_damage_inside = depth + 1;
    result = self [[ callback ]]( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
    self.zt_personal_damage_inside = depth;
    if ( !isdefined( result ) )
        result = damage;
    return result;
}

zt_player_damage_release_owner()
{
    if ( !isdefined( level.zt_player_damage_chain ) || level.zt_player_damage_chain.size <= 0 )
    {
        level.zt_player_damage_chain = [];
        level.zt_player_damage_prev = level.zt_player_damage_base;
        return;
    }

    previous_index = level.zt_player_damage_chain.size - 1;
    previous = level.zt_player_damage_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_player_damage_chain[i];
    level.zt_player_damage_chain = restored_chain;
    level.zt_player_damage_prev = previous;
}

zt_player_damage_adopt_owner( owner, detached )
{
    if ( !isdefined( level.zt_player_damage_chain ) )
        level.zt_player_damage_chain = [];
    if ( !isdefined( level.zt_player_damage_prev ) )
    {
        level.zt_player_damage_prev = owner;
        return;
    }
    if ( level.zt_player_damage_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_player_damage_chain.size; i++ )
    {
        if ( level.zt_player_damage_chain[i] == owner )
            restored_index = i;
    }
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_player_damage_chain[i];
        level.zt_player_damage_chain = restored_chain;
    }
    else if ( !detached )
        level.zt_player_damage_chain[level.zt_player_damage_chain.size] = level.zt_player_damage_prev;
    // A newly published owner seen while detached already captured the prior
    // outer function; do not duplicate that predecessor in our explicit stack.
    level.zt_player_damage_prev = owner;
}

zt_player_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime )
{
    depth = 0;
    if ( isdefined( level.zt_player_damage_inside ) )
        depth = level.zt_player_damage_inside;

    callback = level.zt_player_damage_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_player_damage_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_player_damage_chain[chain_index];
        else
            callback = level.zt_player_damage_base;
    }
    if ( !isdefined( callback ) )
        return damage;

    level.zt_player_damage_inside = depth + 1;
    result = self [[ callback ]]( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
    level.zt_player_damage_inside = depth;
    if ( !isdefined( result ) )
        result = damage;
    return result;
}

zt_actor_damage_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        if ( !isdefined( level.callbackactordamage ) )
        {
            zt_actor_damage_release_owner();
            level.callbackactordamage = ::zt_actor_damage_wrapper;
        }
        else if ( level.callbackactordamage != ::zt_actor_damage_wrapper )
        {
            zt_actor_damage_adopt_owner( level.callbackactordamage );
            level.callbackactordamage = ::zt_actor_damage_wrapper;
        }
        wait 0.25;
    }
}

zt_actor_damage_release_owner()
{
    if ( !isdefined( level.zt_actor_damage_chain ) || level.zt_actor_damage_chain.size <= 0 )
    {
        level.zt_actor_damage_chain = [];
        level.zt_actor_damage_prev = level.zt_actor_damage_base;
        return;
    }

    // Clearing a temporary late owner reveals its immediate predecessor, not
    // necessarily the callback that happened to exist when ZTweaks started.
    // Pop one link so a predecessor that captured our wrapper can still re-enter
    // the next older owner without recursion or duplicate finishActorDamage.
    previous_index = level.zt_actor_damage_chain.size - 1;
    previous = level.zt_actor_damage_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_actor_damage_chain[i];
    level.zt_actor_damage_chain = restored_chain;
    level.zt_actor_damage_prev = previous;
}

zt_actor_damage_adopt_owner( owner )
{
    if ( !isdefined( level.zt_actor_damage_chain ) )
        level.zt_actor_damage_chain = [];
    if ( !isdefined( level.zt_actor_damage_prev ) )
    {
        level.zt_actor_damage_prev = owner;
        return;
    }
    if ( level.zt_actor_damage_prev == owner )
        return;

    // A late wrapper can save and re-enter our published function. Retain the
    // owner it wrapped so that every earlier callback result and side effect
    // still runs exactly once. If an older owner is restored, unwind to its
    // original predecessor rather than building a cyclic callback chain.
    restored_index = -1;
    for ( i = 0; i < level.zt_actor_damage_chain.size; i++ )
    {
        if ( level.zt_actor_damage_chain[i] == owner )
            restored_index = i;
    }
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_actor_damage_chain[i];
        level.zt_actor_damage_chain = restored_chain;
    }
    else
        level.zt_actor_damage_chain[level.zt_actor_damage_chain.size] = level.zt_actor_damage_prev;
    level.zt_actor_damage_prev = owner;
}

zt_actor_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, damageorigin, offsettime, boneindex, modelindex, surfacetype, surfacenormal )
{
    depth = 0;
    if ( isdefined( level.zt_actor_damage_inside ) )
        depth = level.zt_actor_damage_inside;

    callback = level.zt_actor_damage_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_actor_damage_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_actor_damage_chain[chain_index];
        else
            callback = level.zt_actor_damage_base;
    }
    if ( !isdefined( callback ) )
        return;

    level.zt_actor_damage_inside = depth + 1;
    result = self [[ callback ]]( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, damageorigin, offsettime, boneindex, modelindex, surfacetype, surfacenormal );
    level.zt_actor_damage_inside = depth;
    return result;
}

zt_is_explosive_mod( meansofdeath )
{
    return meansofdeath == "MOD_PROJECTILE" || meansofdeath == "MOD_PROJECTILE_SPLASH" || meansofdeath == "MOD_GRENADE" || meansofdeath == "MOD_GRENADE_SPLASH" || meansofdeath == "MOD_EXPLOSIVE";
}

zt_spawn_protection_applies( inflictor, attacker, meansofdeath )
{
    // Spawn protection is combat protection, not environmental immunity.
    if ( meansofdeath == "MOD_FALLING" || meansofdeath == "MOD_SUICIDE" || meansofdeath == "MOD_TRIGGER_HURT" || meansofdeath == "MOD_CRUSH" || meansofdeath == "MOD_DROWN" )
        return 0;
    if ( attacker == self || inflictor == self )
        return 0;
    if ( isdefined( inflictor ) && isdefined( inflictor.owner ) && inflictor.owner == self )
        return 0;
    return isdefined( attacker ) || isdefined( inflictor );
}

zt_adjust_player_damage( inflictor, attacker, damage, meansofdeath )
{
    adjusted = spawnstruct();
    adjusted.damage = damage;
    adjusted.force_zero = 0;
    adjusted.zombie_scaled = 0;
    if ( level.zt.config.zombie_damage > 0 && !zt_true( self.zt_zombie_damage_adjusting ) && zt_ordinary_zombie_melee_damage( attacker, meansofdeath ) )
    {
        adjusted.damage = int( adjusted.damage * level.zt.config.zombie_damage / 100.0 + 0.5 );
        if ( adjusted.damage < 1 ) adjusted.damage = 1;
        adjusted.zombie_scaled = 1;
    }
    if ( isdefined( self.zt_spawn_protection_until ) && gettime() < self.zt_spawn_protection_until && self zt_spawn_protection_applies( inflictor, attacker, meansofdeath ) )
    {
        adjusted.damage = 0;
        adjusted.force_zero = 1;
    }
    if ( meansofdeath == "MOD_FALLING" && level.zt.config.fall_damage != 0 )
    {
        if ( level.zt.config.fall_damage < 0 )
        {
            adjusted.damage = 0;
            adjusted.force_zero = 1;
        }
        else
            adjusted.damage = int( adjusted.damage * level.zt.config.fall_damage / 100.0 + 0.5 );
    }
    if ( level.zt.config.no_explosive_self_damage && zt_is_explosive_mod( meansofdeath ) )
    {
        if ( attacker == self || inflictor == self || ( isdefined( inflictor ) && isdefined( inflictor.owner ) && inflictor.owner == self ) )
        {
            adjusted.damage = 0;
            adjusted.force_zero = 1;
        }
    }
    return adjusted;
}

zt_ordinary_zombie_melee_damage( attacker, meansofdeath )
{
    if ( meansofdeath != "MOD_MELEE" || !isdefined( attacker ) || isplayer( attacker ) )
        return 0;
    if ( !isdefined( attacker.is_zombie ) || !attacker.is_zombie )
        return 0;
    if ( !isdefined( attacker.targetname ) || attacker.targetname != "zombie" )
        return 0;
    if ( !isdefined( level.zombie_team ) || !isdefined( attacker.team ) || attacker.team != level.zombie_team )
        return 0;
    if ( zt_true( attacker.ignore_enemy_count ) || isdefined( attacker.script_noteworthy ) ||
         isdefined( attacker.actor_damage_func ) || isdefined( attacker.aioverridedamage ) ||
         isdefined( attacker.non_attacker_func ) || zt_true( attacker.dont_die_on_me ) ||
         zt_true( attacker.b_zombie_blood_damage_only ) || zt_true( attacker.aat_turned ) )
        return 0;
    return 1;
}

zt_personal_damage_wrapper( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime )
{
    if ( zt_true( self.zt_personal_damage_inside ) )
        return self zt_personal_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );

    if ( zt_true( self.zt_personal_damage_detached ) )
    {
        self.zt_personal_damage_inside = 1;
        detached_result = self zt_personal_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
        self.zt_personal_damage_inside = 0;
        return detached_result;
    }

    adjusted = self zt_adjust_player_damage( inflictor, attacker, damage, meansofdeath );
    if ( adjusted.zombie_scaled ) self.zt_zombie_damage_adjusting = 1;
    result = self zt_personal_damage_forward( inflictor, attacker, adjusted.damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
    if ( adjusted.zombie_scaled ) self.zt_zombie_damage_adjusting = 0;
    if ( adjusted.force_zero )
        return 0;
    if ( !isdefined( result ) )
        result = adjusted.damage;
    return result;
}

zt_player_damage_wrapper( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime )
{
    if ( zt_true( level.zt_player_damage_inside ) )
        return self zt_player_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );

    // A late custom owner may retain this function after ZTweaks detaches.
    // Re-enter at its immediate predecessor instead of recursing into that
    // detached outer owner.
    if ( zt_true( level.zt_player_damage_detached ) )
    {
        level.zt_player_damage_inside = 1;
        detached_result = self zt_player_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
        level.zt_player_damage_inside = 0;
        return detached_result;
    }

    adjusted = self zt_adjust_player_damage( inflictor, attacker, damage, meansofdeath );
    if ( adjusted.zombie_scaled ) self.zt_zombie_damage_adjusting = 1;
    result = self zt_player_damage_forward( inflictor, attacker, adjusted.damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
    if ( adjusted.zombie_scaled ) self.zt_zombie_damage_adjusting = 0;
    if ( adjusted.force_zero )
        return 0;
    if ( !isdefined( result ) )
        result = adjusted.damage;
    return result;
}

zt_player_damage( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime )
{
    if ( isdefined( self.zt_spawn_protection_until ) && gettime() < self.zt_spawn_protection_until && self zt_spawn_protection_applies( inflictor, attacker, meansofdeath ) )
        return 0;
    if ( meansofdeath == "MOD_FALLING" && level.zt.config.fall_damage != 0 )
    {
        if ( level.zt.config.fall_damage < 0 )
            return 0;
        return int( damage * level.zt.config.fall_damage / 100.0 + 0.5 );
    }
    if ( level.zt.config.no_explosive_self_damage && zt_is_explosive_mod( meansofdeath ) )
    {
        if ( attacker == self || inflictor == self || ( isdefined( inflictor ) && isdefined( inflictor.owner ) && inflictor.owner == self ) )
            return 0;
    }
    return -1;
}

zt_normal_enemy_weapon_damage( attacker, damage, meansofdeath, weapon )
{
    if ( !isdefined( damage ) || damage <= 0 || !isdefined( attacker ) || !isplayer( attacker ) )
        return 0;
    if ( !zt_valid_inventory_weapon( weapon ) || !isdefined( weapon.name ) || weapon.name == "none" )
        return 0;
    registered_weapon = isdefined( weapon.rootweapon ) && isdefined( level.zombie_weapons ) && isdefined( level.zombie_weapons[weapon.rootweapon] );
    native_melee = meansofdeath == "MOD_MELEE" && ( ( isdefined( weapon.type ) && weapon.type == "melee" ) || ( isdefined( weapon.ismeleeweapon ) && weapon.ismeleeweapon ) );
    if ( ( !registered_weapon && !native_melee ) || !( attacker zt_player_owns_damage_weapon( weapon ) ) )
        return 0;
    if ( !isdefined( meansofdeath ) || meansofdeath == "" || meansofdeath == "MOD_UNKNOWN" )
        return 0;

    // Stock ordinary zombies publish this exact identity. Origins capture and
    // zombie-blood quest actors use script_noteworthy/ignore_enemy_count;
    // Moon's astronaut and other bosses publish actor_damage_func. Turned and
    // friendly actors leave the zombie team. All remain map-owned.
    if ( !isdefined( self.is_zombie ) || !self.is_zombie ||
         !isdefined( self.targetname ) || self.targetname != "zombie" ||
         !isdefined( level.zombie_team ) || !isdefined( self.team ) || self.team != level.zombie_team )
        return 0;
    if ( zt_true( self.ignore_enemy_count ) || isdefined( self.script_noteworthy ) ||
         isdefined( self.actor_damage_func ) || isdefined( self.aioverridedamage ) ||
         isdefined( self.non_attacker_func ) || zt_true( self.dont_die_on_me ) ||
         zt_true( self.b_zombie_blood_damage_only ) || zt_true( self.aat_turned ) )
        return 0;

    // Stock scripted instant-kill paths use health + 666 as a force-kill
    // sentinel. Scaling it can accidentally keep an objective actor alive.
    if ( isdefined( self.health ) && damage == self.health + 666 )
        return 0;
    return 1;
}

zt_player_owns_damage_weapon( weapon )
{
    if ( self hasweapon( weapon ) || self getcurrentweapon() == weapon )
        return 1;
    carried_weapons = self getweaponslist();
    for ( i = 0; i < carried_weapons.size; i++ )
    {
        if ( zt_same_weapon_root( carried_weapons[i], weapon ) )
            return 1;
    }
    return 0;
}

zt_actor_damage_wrapper( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, damageorigin, offsettime, boneindex, modelindex, surfacetype, surfacenormal )
{
    if ( zt_true( level.zt_actor_damage_inside ) )
        return self zt_actor_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, damageorigin, offsettime, boneindex, modelindex, surfacetype, surfacenormal );

    percent = level.zt.config.weapon_damage;
    if ( meansofdeath == "MOD_MELEE" )
        percent = level.zt.config.melee_damage;
    growth = level.zt.config.challenge_rising_damage;
    pap_percent = level.zt.config.pap_damage_multiplier;
    if ( ( percent > 0 || growth > 0 || pap_percent > 0 ) && self zt_normal_enemy_weapon_damage( attacker, damage, meansofdeath, weapon ) )
    {
        if ( percent <= 0 ) percent = 100;
        round_scale = 100;
        if ( growth > 0 && isdefined( level.round_number ) && level.round_number > 1 )
        {
            round_scale = 100 + ( level.round_number - 1 ) * growth;
            if ( round_scale > 500 ) round_scale = 500;
        }
        damage = int( damage * percent * round_scale / 10000.0 + 0.5 );
        if ( pap_percent > 0 && isdefined( level.zombie_weapons_upgraded ) && zm_weapons::is_weapon_upgraded( weapon ) )
            damage = int( damage * pap_percent / 100.0 + 0.5 );
        if ( damage < 1 ) damage = 1;
    }

    return self zt_actor_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, damageorigin, offsettime, boneindex, modelindex, surfacetype, surfacenormal );
}

zt_fast_barrier_rebuild_install()
{
    // Only known stock map scripts use this path. Preserve map-authored delays,
    // stock blocker callbacks, animation, reward accounting, and other mods.
    if ( !level.zt.config.experimental_tweaks )
    {
        zt_feature( "fast_barrier_rebuild", "unavailable", "Enable Experimental Tweaks to edit this stock-map-only setting." );
        return;
    }
    map_name = "";
    if ( isdefined( level.script ) ) map_name = level.script;
    if ( map_name != "zm_zod" && map_name != "zm_factory" && map_name != "zm_castle" && map_name != "zm_island" &&
         map_name != "zm_stalingrad" && map_name != "zm_genesis" && map_name != "zm_prototype" && map_name != "zm_asylum" &&
         map_name != "zm_sumpf" && map_name != "zm_theater" && map_name != "zm_cosmodrome" && map_name != "zm_temple" &&
         map_name != "zm_moon" && map_name != "zm_tomb" )
    {
        zt_feature( "fast_barrier_rebuild", "unavailable", "recognized stock map required" );
        return;
    }
    level endon( #"end_game" );
    // On T7 this installer is started during init, before the round-logic
    // boundary. Do not inspect or mark blocker structs while the map is still
    // assembling them; a slow intro must not consume the 20-second window.
    while ( !zt_game_ready() ) wait 0.1;
    applied = 0;
    reported = 0;
    for ( tick = 0; tick < 40; tick++ )
    {
        if ( isdefined( level.exterior_goals ) )
        {
            for ( i = 0; i < level.exterior_goals.size; i++ )
            {
                barrier = level.exterior_goals[i];
                if ( !isdefined( barrier ) || !isdefined( barrier.barrier_chunks ) || barrier.barrier_chunks.size == 0 || isdefined( barrier.zt_fast_repair_checked ) )
                    continue;
                barrier.zt_fast_repair_checked = 1;
                if ( isdefined( barrier.script_delay ) || isdefined( barrier.script_delay_min ) || isdefined( barrier.script_delay_max ) )
                    continue;
                barrier.script_delay = 0.25;
                applied++;
            }
        }
        if ( applied > 0 && !reported )
        {
            zt_feature( "fast_barrier_rebuild", "active", "stock barriers without map-authored delays only" );
            reported = 1;
        }
        wait 0.5;
    }
    if ( applied == 0 ) zt_feature( "fast_barrier_rebuild", "unavailable", "stock blocker system has no unowned repair delay" );
}

zt_point_gain_install()
{
    if ( level.zt.config.point_gain <= 0 )
        return;
    // Do not subscribe to earned_points during level initialization. On T7x,
    // that extra listener can hold the stock map-start transaction before the
    // start_zombie_round_logic boundary, leaving the client at a black screen.
    // The per-player sampler and even its compatibility-state publication
    // start only after that authoritative boundary. Keeping this installer a
    // true no-op before gameplay means a non-default Point Gain selection
    // cannot add any work to a stock map's cinematic/start transaction.
}

zt_point_gain_watch()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    while ( 1 )
    {
        // A frame-end-only loop can continuously reschedule inside T7x's
        // server script pass after gameplay becomes ready.  The client then
        // renders our HUD but receives no further server traffic and finally
        // reports EXE_ERR_SERVER_TIMEOUT.  Stock and established T7 sampling
        // loops use an explicit timed yield; 20 Hz is more than sufficient to
        // observe score awards without starving the server command channel.
        wait 0.05;
        if ( !isdefined( self.score ) )
            continue;
        if ( zt_true( self.zt_point_gain_baseline_pending ) || !isdefined( self.zt_point_gain_previous ) )
        {
            self.zt_point_gain_previous = self.score;
            if ( isdefined( self.score_total ) ) self.zt_point_gain_total_previous = self.score_total;
            continue;
        }
        current = self.score;
        // Stock award/spend functions update pers["score"] with the currency.
        // A mismatch identifies a map-owned direct score presentation/write
        // (and the matching restoration frame), neither of which is an award.
        if ( isdefined( self.pers ) && isdefined( self.pers["score"] ) && self.pers["score"] != current )
        {
            self.zt_point_gain_map_rewrite = 1;
            self.zt_point_gain_previous = current;
            if ( isdefined( self.score_total ) ) self.zt_point_gain_total_previous = self.score_total;
            continue;
        }
        total_delta = 0;
        current_total = 0;
        if ( isdefined( self.score_total ) )
        {
            current_total = self.score_total;
            if ( isdefined( self.zt_point_gain_total_previous ) )
                total_delta = current_total - self.zt_point_gain_total_previous;
        }
        // BO3 increments score_total only for an earned award. Currency costs
        // reduce score without touching it, and map-owned wallet restoration
        // normally changes score/pers["score"] only. This makes total_delta a
        // safer reward boundary than installing another stock notify listener.
        if ( total_delta > 0 && level.zt.config.point_gain > 0 )
        {
            scaled = int( total_delta * level.zt.config.point_gain / 100.0 + 0.5 );
            bonus = scaled - total_delta;
            if ( bonus != 0 )
            {
                self.score = current + bonus;
                if ( isdefined( self.pers ) ) self.pers["score"] = self.score;
                // Mirror the multiplier bonus into the stock earned-points
                // stat so wallet, recap, and persistent accounting agree.
                self incrementplayerstat( "scoreEarned", bonus );
                current = self.score;
                if ( isdefined( self.score_total ) )
                {
                    self.score_total = current_total + bonus;
                    if ( isdefined( level.score_total ) ) level.score_total += bonus;
                    current_total = self.score_total;
                }
            }
        }
        self.zt_point_gain_map_rewrite = 0;
        self.zt_point_gain_previous = current;
        if ( isdefined( self.score_total ) )
            self.zt_point_gain_total_previous = current_total;
    }
}

zt_point_gain_rebaseline()
{
    if ( level.zt.config.point_gain <= 0 )
    {
        self.zt_point_gain_baseline_pending = 0;
        return;
    }

    if ( isdefined( self.score ) )
        self.zt_point_gain_previous = self.score;
    if ( isdefined( self.score_total ) )
        self.zt_point_gain_total_previous = self.score_total;
    self.zt_point_gain_map_rewrite = 0;
    self.zt_point_gain_baseline_pending = 0;

    // zt_player_spawn_watch reaches this function only after
    // start_zombie_round_logic. Publish the enabled state here, not from the
    // level initializer, so the setting is completely inert during startup.
    zt_feature( "point_gain", "active", "" );

    if ( !zt_true( self.zt_point_gain_watch ) )
    {
        self.zt_point_gain_watch = 1;
        self thread zt_point_gain_watch();
    }
}

zt_revive_time_get( revivee )
{
    if ( zt_true( self.zt_revive_time_inside ) )
        return self zt_base_revive_time( revivee );

    if ( zt_true( self.zt_revive_time_had_previous ) && isdefined( self.zt_revive_time_previous ) )
    {
        self.zt_revive_time_inside = 1;
        seconds = self [[ self.zt_revive_time_previous ]]( revivee );
        self.zt_revive_time_inside = 0;
    }
    else
        seconds = self zt_base_revive_time( revivee );
    seconds = seconds * level.zt.config.revive_time / 100.0;
    if ( seconds < 0.05 ) seconds = 0.05;
    return seconds;
}

zt_base_revive_time( revivee )
{
    if ( zt_true( self.zt_revive_time_base_had_previous ) && isdefined( self.zt_revive_time_base_previous ) )
        return self [[ self.zt_revive_time_base_previous ]]( revivee );

    seconds = 3.0;
    if ( self hasperk( "specialty_quickrevive" ) ) seconds = seconds / 2.0;
    // Mod Tools does not expose pers_revive_active as an external even though
    // stock last-stand code calls it. Mirror its awarded-state test locally so
    // the persistent revive upgrade still composes with this owner.
    if ( isdefined( self.pers_upgrades_awarded ) &&
         isdefined( self.pers_upgrades_awarded["revive"] ) &&
         self.pers_upgrades_awarded["revive"] )
        seconds = seconds * 0.5;
    return seconds;
}

zt_update_revive_time_owner()
{
    if ( level.zt.config.revive_time > 0 )
    {
        if ( !zt_true( self.zt_revive_time_owned ) )
        {
            self.zt_revive_time_had_previous = isdefined( self.get_revive_time );
            if ( self.zt_revive_time_had_previous )
                self.zt_revive_time_previous = self.get_revive_time;
            self.zt_revive_time_base_had_previous = self.zt_revive_time_had_previous;
            self.zt_revive_time_base_previous = self.zt_revive_time_previous;
            self.zt_revive_time_owned = 1;
        }
        else if ( self.get_revive_time != ::zt_revive_time_get )
        {
            // Shadows of Evil's Beast form temporarily replaces this owner.
            // Compose while present; when the map clears it, return to the
            // player's original callback rather than retaining Beast timing.
            if ( isdefined( self.get_revive_time ) )
            {
                self.zt_revive_time_had_previous = 1;
                self.zt_revive_time_previous = self.get_revive_time;
            }
            else
            {
                self.zt_revive_time_had_previous = self.zt_revive_time_base_had_previous;
                self.zt_revive_time_previous = self.zt_revive_time_base_previous;
            }
        }
        self.get_revive_time = ::zt_revive_time_get;
    }
    else if ( zt_true( self.zt_revive_time_owned ) )
    {
        // If a map claimed the callback between watcher ticks, it already
        // owns the live value and must not be overwritten during release.
        if ( self.get_revive_time == ::zt_revive_time_get )
        {
            if ( zt_true( self.zt_revive_time_had_previous ) && isdefined( self.zt_revive_time_previous ) )
                self.get_revive_time = self.zt_revive_time_previous;
            else
                self.get_revive_time = undefined;
        }
        self.zt_revive_time_owned = 0;
        self.zt_revive_time_had_previous = 0;
        self.zt_revive_time_previous = undefined;
        self.zt_revive_time_base_had_previous = 0;
        self.zt_revive_time_base_previous = undefined;
    }
}

zt_revive_time_owner_watch()
{
    self endon( #"disconnect" );
    level endon( #"end_game" );
    while ( 1 )
    {
        self zt_update_revive_time_owner();
        wait 0.1;
    }
}

zt_down_tweaks_install()
{
    level endon( #"end_game" );
    while ( !zt_game_ready() ) wait 0.1;

    level.zt.bleedout_time_stock = getdvarfloat( "player_lastStandBleedoutTime" );
    level.zt.bleedout_time_applied = level.zt.bleedout_time_stock;
    level.zt.bleedout_time_owned = 0;
    level thread zt_down_config_watch();
    level.zt_player_laststand_owned = 0;
    level.zt_player_laststand_detached = 1;
    level.zt_player_laststand_chain = [];
    level.zt_player_laststand_inside = 0;
    level.zt_player_laststand_last_limit = 0;
    level thread zt_player_laststand_owner_watch();

    if ( level.zt.config.revive_time > 0 )
        zt_feature( "revive_time", "active", "map and perk revive-time callbacks are composed before scaling" );
    if ( level.zt.config.lose_perks_on_down != "default" )
        zt_feature( "lose_perks_on_down", "unavailable", "stock removes perks inside its private last-stand pipeline" );
    if ( level.zt.config.keep_weapons_bleedout )
        zt_feature( "keep_weapons_bleedout", "unavailable", "generic inventory restoration would duplicate map quest weapons" );
}

zt_down_config_watch()
{
    level endon( #"end_game" );
    previous_bleedout = -999;
    previous_revive = -999;
    previous_lose_perks = level.zt.config.lose_perks_on_down;
    previous_keep_weapons = level.zt.config.keep_weapons_bleedout;

    while ( 1 )
    {
        bleedout = zt_cfg_int( "zt_bleedout_time", 0 );
        revive = zt_cfg_int( "zt_revive_time", 0 );
        current = getdvarfloat( "player_lastStandBleedoutTime" );
        base_changed = 0;
        ownership_changed = 0;

        if ( bleedout > 0 )
        {
            // Treat any value other than our last output as a late map/mod
            // owner. Adopt it as the new base, then apply this percentage
            // once. Watching the dvar as well as the menu setting is required
            // for modes which publish their bleed-out duration after common
            // Zombies initialization.
            if ( !zt_true( level.zt.bleedout_time_owned ) )
            {
                if ( current != level.zt.bleedout_time_stock ) base_changed = 1;
                level.zt.bleedout_time_stock = current;
            }
            else if ( current != level.zt.bleedout_time_applied )
            {
                level.zt.bleedout_time_stock = current;
                base_changed = 1;
            }

            if ( level.zt.bleedout_time_stock > 0 )
            {
                target = level.zt.bleedout_time_stock * bleedout / 100.0;
                if ( !zt_true( level.zt.bleedout_time_owned ) || target != level.zt.bleedout_time_applied || current != target )
                {
                    level.zt.bleedout_time_applied = target;
                    setdvar( "player_lastStandBleedoutTime", level.zt.bleedout_time_applied );
                    ownership_changed = 1;
                }
                level.zt.bleedout_time_owned = 1;
                if ( bleedout != previous_bleedout || base_changed || ownership_changed )
                    zt_feature( "bleedout_time", "active", "composed with the map's live bleed-out duration" );
            }
            else
            {
                level.zt.bleedout_time_owned = 0;
                if ( bleedout != previous_bleedout || base_changed )
                    zt_feature( "bleedout_time", "unavailable", "the map exposes no standard bleed-out duration" );
            }
        }
        else if ( zt_true( level.zt.bleedout_time_owned ) )
        {
            if ( current == level.zt.bleedout_time_applied )
                setdvar( "player_lastStandBleedoutTime", level.zt.bleedout_time_stock );
            level.zt.bleedout_time_owned = 0;
            zt_feature( "bleedout_time", "inherit", "" );
        }
        else if ( current > 0 )
            level.zt.bleedout_time_stock = current;

        if ( bleedout != level.zt.config.bleedout_time )
            level.zt.config.bleedout_time = bleedout;
        previous_bleedout = bleedout;

        if ( revive != previous_revive )
        {
            level.zt.config.revive_time = revive;
            players = getplayers();
            for ( i = 0; i < players.size; i++ )
                players[i] zt_update_revive_time_owner();
            if ( revive > 0 ) zt_feature( "revive_time", "active", "map and perk revive-time callbacks are composed before scaling" );
            else zt_feature( "revive_time", "inherit", "" );
            previous_revive = revive;
        }

        // These rows deliberately fail closed, but they are still NEXT DOWN /
        // NEXT BLEED-OUT settings. Keep their requested values and report
        // state live instead of leaving the compatibility page at the state
        // captured when the match started.
        lose_perks = zt_cfg_string( "zt_lose_perks_on_down", "default" );
        if ( lose_perks != previous_lose_perks )
        {
            level.zt.config.lose_perks_on_down = lose_perks;
            if ( lose_perks != "default" )
                zt_feature( "lose_perks_on_down", "unavailable", "stock removes perks inside its private last-stand pipeline" );
            else
                zt_feature( "lose_perks_on_down", "inherit", "" );
            previous_lose_perks = lose_perks;
        }

        keep_weapons = zt_cfg_int( "zt_keep_weapons_bleedout", 0 );
        if ( keep_weapons != previous_keep_weapons )
        {
            level.zt.config.keep_weapons_bleedout = keep_weapons;
            if ( keep_weapons )
                zt_feature( "keep_weapons_bleedout", "unavailable", "generic inventory restoration would duplicate map quest weapons" );
            else
                zt_feature( "keep_weapons_bleedout", "inherit", "" );
            previous_keep_weapons = keep_weapons;
        }

        wait 0.25;
    }
}

zt_down_limit_unavailable_reason()
{
    // Capability-based: stock-derived custom maps may compose too. Unknown
    // outer transactions must not be forced through stock bleed-out cleanup.
    if ( !isdefined( level.callbackplayerlaststand ) || level.callbackplayerlaststand != zm::callback_playerlaststand )
        return "map owns a nonstandard outer last-stand transaction";
    if ( !isdefined( level.laststandgetupallowed ) || level.laststandgetupallowed || zt_true( level.is_zombie_level ) )
        return "map owns a get-up or role-conversion last-stand transaction";
    if ( level flag::exists( "solo_game" ) && level flag::get( "solo_game" ) )
        return "solo Quick Revive owns a separate auto-revive transaction";
    return "";
}

zt_player_laststand_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        limit = zt_cfg_int( "zt_down_limit", 0 );
        level.zt.config.down_limit = limit;
        unavailable = "";
        if ( limit != 0 )
            unavailable = zt_down_limit_unavailable_reason();
        enabled = limit > 0 && unavailable == "";

        if ( enabled && !zt_true( level.zt_player_laststand_owned ) && isdefined( level.playerlaststand_func ) )
        {
            if ( !isdefined( level.zt_player_laststand_base ) )
                level.zt_player_laststand_base = level.playerlaststand_func;
            zt_player_laststand_adopt_owner( level.playerlaststand_func, zt_true( level.zt_player_laststand_detached ) );
            level.playerlaststand_func = ::zt_player_laststand_wrapper;
            level.zt_player_laststand_owned = 1;
            level.zt_player_laststand_detached = 0;
            level.zt_player_laststand_missing_reported = 0;
            level.zt_player_laststand_unavailable = "";
            zt_feature( "down_limit", "active", "" );
        }
        else if ( enabled && zt_true( level.zt_player_laststand_owned ) && !isdefined( level.playerlaststand_func ) )
        {
            zt_player_laststand_release_owner();
            level.playerlaststand_func = ::zt_player_laststand_wrapper;
        }
        else if ( enabled && zt_true( level.zt_player_laststand_owned ) && level.playerlaststand_func != ::zt_player_laststand_wrapper )
        {
            zt_player_laststand_adopt_owner( level.playerlaststand_func, 0 );
            level.playerlaststand_func = ::zt_player_laststand_wrapper;
        }
        else if ( enabled && !zt_true( level.zt_player_laststand_owned ) && !isdefined( level.playerlaststand_func ) )
        {
            if ( !zt_true( level.zt_player_laststand_missing_reported ) )
            {
                zt_feature( "down_limit", "unavailable", "map exposes no composable player-last-stand callback" );
                level.zt_player_laststand_missing_reported = 1;
            }
        }
        else if ( !enabled && zt_true( level.zt_player_laststand_owned ) )
        {
            if ( isdefined( level.playerlaststand_func ) && level.playerlaststand_func == ::zt_player_laststand_wrapper )
                level.playerlaststand_func = level.zt_player_laststand_prev;
            else if ( isdefined( level.playerlaststand_func ) )
                zt_player_laststand_adopt_owner( level.playerlaststand_func, 0 );
            else
            {
                zt_player_laststand_release_owner();
                level.playerlaststand_func = level.zt_player_laststand_prev;
            }
            level.zt_player_laststand_owned = 0;
            level.zt_player_laststand_detached = 1;
        }

        if ( unavailable != "" && ( !isdefined( level.zt_player_laststand_unavailable ) || level.zt_player_laststand_unavailable != unavailable ) )
        {
            zt_feature( "down_limit", "unavailable", unavailable );
            level.zt_player_laststand_unavailable = unavailable;
            level.zt_player_laststand_missing_reported = 0;
        }
        else if ( limit < 0 && unavailable == "" && ( !isdefined( level.zt_player_laststand_last_limit ) || level.zt_player_laststand_last_limit != limit || isdefined( level.zt_player_laststand_unavailable ) && level.zt_player_laststand_unavailable != "" ) )
        {
            zt_feature( "down_limit", "active", "stock classic co-op already permits unlimited ordinary downs" );
            level.zt_player_laststand_unavailable = "";
        }
        else if ( limit == 0 && ( !isdefined( level.zt_player_laststand_last_limit ) || level.zt_player_laststand_last_limit != 0 ) )
        {
            zt_feature( "down_limit", "inherit", "" );
            level.zt_player_laststand_unavailable = "";
            level.zt_player_laststand_missing_reported = 0;
        }
        level.zt_player_laststand_last_limit = limit;
        // This passive owner runs at DEFAULT; yield real time between checks.
        wait 0.1;
    }
}

zt_player_laststand_release_owner()
{
    if ( !isdefined( level.zt_player_laststand_chain ) || level.zt_player_laststand_chain.size <= 0 )
    {
        level.zt_player_laststand_chain = [];
        level.zt_player_laststand_prev = level.zt_player_laststand_base;
        return;
    }

    previous_index = level.zt_player_laststand_chain.size - 1;
    previous = level.zt_player_laststand_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_player_laststand_chain[i];
    level.zt_player_laststand_chain = restored_chain;
    level.zt_player_laststand_prev = previous;
}

zt_player_laststand_adopt_owner( owner, detached )
{
    if ( !isdefined( level.zt_player_laststand_chain ) )
        level.zt_player_laststand_chain = [];
    if ( !isdefined( level.zt_player_laststand_prev ) )
    {
        level.zt_player_laststand_prev = owner;
        return;
    }
    if ( level.zt_player_laststand_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_player_laststand_chain.size; i++ )
        if ( level.zt_player_laststand_chain[i] == owner )
            restored_index = i;
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_player_laststand_chain[i];
        level.zt_player_laststand_chain = restored_chain;
    }
    else if ( !detached )
        level.zt_player_laststand_chain[level.zt_player_laststand_chain.size] = level.zt_player_laststand_prev;
    level.zt_player_laststand_prev = owner;
}

zt_player_laststand_forward( inflictor, attacker, damage, meansofdeath, weapon, direction, hitloc, offsettime, deathanimduration )
{
    depth = 0;
    if ( isdefined( level.zt_player_laststand_inside ) )
        depth = level.zt_player_laststand_inside;

    callback = level.zt_player_laststand_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_player_laststand_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_player_laststand_chain[chain_index];
        else
            callback = level.zt_player_laststand_base;
    }
    if ( !isdefined( callback ) )
        return;

    level.zt_player_laststand_inside = depth + 1;
    self [[ callback ]]( inflictor, attacker, damage, meansofdeath, weapon, direction, hitloc, offsettime, deathanimduration );
    level.zt_player_laststand_inside = depth;
}

zt_player_laststand_wrapper( inflictor, attacker, damage, meansofdeath, weapon, direction, hitloc, offsettime, deathanimduration )
{
    if ( zt_true( level.zt_player_laststand_inside ) )
    {
        self zt_player_laststand_forward( inflictor, attacker, damage, meansofdeath, weapon, direction, hitloc, offsettime, deathanimduration );
        return;
    }

    if ( zt_true( level.zt_player_laststand_detached ) )
    {
        level.zt_player_laststand_inside = 1;
        self zt_player_laststand_forward( inflictor, attacker, damage, meansofdeath, weapon, direction, hitloc, offsettime, deathanimduration );
        level.zt_player_laststand_inside = 0;
        return;
    }

    limit = zt_cfg_int( "zt_down_limit", 0 );
    over_limit = 0;
    if ( !zt_true( self.is_zombie ) && limit > 0 && zt_down_limit_unavailable_reason() == "" )
    {
        if ( !isdefined( self.zt_downs ) )
            self.zt_downs = 0;
        self.zt_downs++;
        over_limit = self.zt_downs > limit;
        zt_feature( "down_limit", "active", "" );
    }

    self zt_player_laststand_forward( inflictor, attacker, damage, meansofdeath, weapon, direction, hitloc, offsettime, deathanimduration );

    if ( over_limit )
    {
        // The outer stock playerlaststand transaction observes this and owns
        // undolaststand, bled_out, bleed_out and all cleanup exactly once.
        if ( !zt_true( self.no_revive_trigger ) )
        {
            self.no_revive_trigger = 1;
            self.zt_down_limit_no_revive_owned = 1;
            self thread zt_down_limit_release_no_revive();
        }
    }
}

zt_down_limit_release_no_revive()
{
    self endon( #"disconnect" );
    self notify( #"zt_down_limit_release_no_revive" );
    self endon( #"zt_down_limit_release_no_revive" );
    self util::waittill_any( "player_revived", "bled_out", "death", "spawned_player" );
    util::wait_network_frame();
    if ( zt_true( self.zt_down_limit_no_revive_owned ) )
    {
        self.no_revive_trigger = undefined;
        self.zt_down_limit_no_revive_owned = 0;
    }
}

// Stock round_think publishes end_of_round after the normal round wait.
// Add an optional separate award through the stock score API, preserving
// map-authored round-end callbacks and other mods' score listeners. A
// per-player round marker ignores duplicate notifications from a custom map.
zt_death_points_install()
{
    level endon( #"end_game" );
    while ( !zt_game_ready() ) wait 0.25;
    if ( !isdefined( level.zombie_vars ) || !isdefined( level.zombie_vars["penalty_died"] ) )
    {
        zt_feature( "death_points_retained", "unavailable", "map exposes no standard death-point penalty" );
        return;
    }
    // Stock spectator_respawn reads this live value after spawned_player.
    // Yield to a custom map's initial or later death-score owner.
    if ( level.zombie_vars["penalty_died"] != 0 )
    {
        zt_feature( "death_points_retained", "degraded", "map owns a nonstandard death-point penalty" );
        return;
    }
    penalty = 1.0 - level.zt.config.death_points_retained / 100.0;
    level.zombie_vars["penalty_died"] = penalty;
    zt_feature( "death_points_retained", "active", "" );
    while ( true )
    {
        wait 0.25;
        if ( level.zombie_vars["penalty_died"] != penalty )
        {
            zt_feature( "death_points_retained", "degraded", "map owns a nonstandard death-point penalty" );
            return;
        }
    }
}

zt_round_bonus_install()
{
    level endon( #"end_game" );
    while ( !zt_game_ready() ) wait 0.25;
    while ( true )
    {
        level waittill( #"end_of_round" );
        level.zt.config.round_bonus = zt_cfg_int( "zt_round_bonus", 0 );
        if ( level.zt.config.round_bonus <= 0 )
        {
            zt_transition_feature( "round_bonus", "inherit", "" );
            continue;
        }
        if ( !isdefined( level.round_number ) || level.round_number < 1 || ( isdefined( level.intermission ) && level.intermission ) ) continue;
        players = getplayers();
        awarded = 0;
        for ( i = 0; i < players.size; i++ )
        {
            player = players[i];
            if ( !isdefined( player.sessionstate ) || player.sessionstate != "playing" || !isdefined( player.score ) ) continue;
            if ( isdefined( player.zt_round_bonus_awarded ) && player.zt_round_bonus_awarded == level.round_number ) continue;
            player.zt_round_bonus_awarded = level.round_number;
            player zm_score::add_to_player_score( level.zt.config.round_bonus, 1, "ztweaks_round_bonus" );
            awarded++;
        }
        if ( awarded > 0 ) zt_transition_feature( "round_bonus", "active", "" );
    }
}

// Stock trap_use_think reads trap.zombie_cost at purchase time. Only mutate
// initialized stock traps; custom use callbacks and later map price owners win.
zt_trap_price_install()
{
    level endon( #"end_game" );
    elapsed = 0;
    while ( true )
    {
        traps = GetEntArray( "zombie_trap", "targetname" );
        applied = 0;
        custom = 0;
        conflict = 0;
        for ( i = 0; i < traps.size; i++ )
        {
            trap = traps[i];
            if ( !isdefined( trap.zombie_cost ) || !isdefined( trap._trap_use_trigs ) || !isdefined( trap._trap_type ) ) continue;
            if ( isdefined( level._zombiemode_trap_use_funcs ) && isdefined( level._zombiemode_trap_use_funcs[trap._trap_type] ) )
            {
                custom++;
                continue;
            }
            if ( zt_true( trap.zt_trap_price_owner_lost ) )
            {
                conflict++;
                continue;
            }
            if ( !isdefined( trap.zt_trap_price_base ) ) trap.zt_trap_price_base = trap.zombie_cost;
            cost = int( trap.zt_trap_price_base * level.zt.config.trap_price_multiplier / 100.0 + 0.5 );
            if ( isdefined( trap.zt_trap_price_applied ) && trap.zombie_cost != trap.zt_trap_price_applied )
            {
                trap.zt_trap_price_owner_lost = 1;
                conflict++;
                continue;
            }
            trap.zombie_cost = cost;
            trap.zt_trap_price_applied = cost;
            applied++;
            if ( !isdefined( trap.zt_trap_hint_applied ) && !zt_true( trap._trap_in_use ) && !zt_true( trap._trap_cooling_down ) && zt_trap_price_ready( trap ) )
            {
                for ( j = 0; j < trap._trap_use_trigs.size; j++ )
                    trap._trap_use_trigs[j] SetHintString( &"ZOMBIE_BUTTON_BUY_TRAP", cost );
                trap.zt_trap_hint_applied = 1;
            }
        }
        if ( applied > 0 )
        {
            if ( custom > 0 || conflict > 0 ) zt_transition_feature( "trap_price_multiplier", "degraded", "custom or changed trap purchases remain map-owned" );
            else zt_transition_feature( "trap_price_multiplier", "active", "" );
        }
        else if ( elapsed >= 10 )
        {
            if ( custom > 0 || conflict > 0 ) zt_transition_feature( "trap_price_multiplier", "unavailable", "map owns its trap purchase callbacks or prices" );
            else zt_transition_feature( "trap_price_multiplier", "unavailable", "map has no standard purchase traps" );
        }
        wait 0.5;
        elapsed = elapsed + 0.5;
    }
}

zt_trap_price_ready( trap )
{
    flag_name = "power_on";
    if ( isdefined( trap.script_flag_wait ) ) flag_name = trap.script_flag_wait;
    return level flag::exists( flag_name ) && level flag::get( flag_name );
}

zt_box_tweaks_install()
{
    level endon( #"end_game" );
    post_ready_elapsed = 0;
    missing_reported = 0;
    while ( !isdefined( level.chests ) || level.chests.size == 0 || ( ( level.zt.config.box_quality != "default" || level.zt.config.box_no_repeat ) && !isdefined( level.zombie_weapons ) ) )
    {
        wait 0.1;
        if ( zt_game_ready() )
        {
            post_ready_elapsed += 0.1;
            if ( post_ready_elapsed >= 20 && !missing_reported )
            {
                if ( level.zt.config.box_quality != "default" ) zt_feature( "box_quality", "unavailable", "map has not published a standard Mystery Box registry" );
                if ( level.zt.config.box_no_repeat ) zt_feature( "box_no_repeat", "unavailable", "map has not published a standard Mystery Box registry" );
                if ( level.zt.config.box_lock ) zt_feature( "box_lock", "unavailable", "map has not published a standard Mystery Box" );
                if ( level.zt.config.box_price_multiplier >= 0 ) zt_feature( "box_price_multiplier", "unavailable", "map has not published a standard Mystery Box" );
                if ( level.zt.config.fire_sale_box_price >= 0 ) zt_feature( "fire_sale_box_price", "unavailable", "map has not published a standard Mystery Box" );
                if ( level.zt.config.teddy_bear_chance >= 0 ) zt_feature( "teddy_chance", "unavailable", "map has not published a standard Mystery Box" );
                if ( level.zt.config.challenge_no_box ) zt_feature( "challenge_no_box", "unavailable", "map has not published a standard Mystery Box" );
                if ( level.zt.config.challenge_wall_only ) zt_feature( "challenge_wall_only", "unavailable", "map has not published a standard Mystery Box" );
                if ( level.zt.config.challenge_one_box ) zt_feature( "challenge_one_box", "unavailable", "map has not published a standard Mystery Box" );
                missing_reported = 1;
            }
        }
    }
    if ( level.zt.config.box_lock )
    {
        zt_box_lock_claim();
        setdvar( "magic_chest_movable", 0 );
        zt_feature( "box_lock", "active", "stock purchase-triggered relocation disabled; explicit map/quest moves remain map-owned" );
    }
    if ( level.zt.config.box_quality != "default" || level.zt.config.box_no_repeat )
    {
        level.zt_box_weights_chain = [];
        level.zt_box_weights_inside = 0;
        if ( isdefined( level.customrandomweaponweights ) )
        {
            level.zt_box_weights_prev = level.customrandomweaponweights;
            level.zt_box_weights_base = level.customrandomweaponweights;
        }
        level.customrandomweaponweights = ::zt_box_weights;
        if ( level.zt.config.box_quality != "default" )
        {
            if ( level.zt.config.box_quality == "everything" ) zt_feature( "box_quality", "degraded", "map-composed candidates are preserved, while stock safety and ownership exclusions remain" );
            else zt_feature( "box_quality", "active", "" );
        }
        if ( level.zt.config.box_no_repeat ) zt_feature( "box_no_repeat", "active", "" );
    }
    if ( level.zt.config.box_price_multiplier >= 0 || level.zt.config.fire_sale_box_price >= 0 )
        zt_box_prices_apply();
    if ( level.zt.config.teddy_bear_chance >= 0 )
        zt_teddy_chance_claim();
    if ( level.zt.config.box_lock || level.zt.config.box_quality != "default" || level.zt.config.box_no_repeat || level.zt.config.box_price_multiplier >= 0 || level.zt.config.fire_sale_box_price >= 0 || zt_true( level.zt.teddy_chance_owned ) || level.zt.config.challenge_no_box || level.zt.config.challenge_wall_only )
        level thread zt_box_owner_watch();
    if ( level.zt.config.challenge_no_box || level.zt.config.challenge_wall_only )
    {
        for ( i = 0; i < level.chests.size; i++ ) level.chests[i].disabled = 1;
        if ( level.zt.config.challenge_no_box ) zt_feature( "challenge_no_box", "active", "standard Mystery Boxes disabled" );
        if ( level.zt.config.challenge_wall_only ) zt_feature( "challenge_wall_only", "degraded", "standard Mystery Boxes disabled; scripted quest rewards remain map-owned" );
    }
    if ( level.zt.config.challenge_one_box )
        zt_feature( "challenge_one_box", "unavailable", "stock exposes completion notifications but no safe per-player pre-use veto" );
}

zt_box_lock_claim()
{
    if ( isdefined( level.zt.box_lock_dvar_owned ) && level.zt.box_lock_dvar_owned )
        return;

    level.zt.box_lock_movable_stock = getdvarint( "magic_chest_movable" );
    level.zt.box_lock_dvar_owned = 1;
    level thread zt_box_lock_release_watch();
}

zt_box_lock_release_watch()
{
    // Capture only after this map has initialized its box. Restoring a value
    // carried from another map would break maps whose stock box is immovable.
    level waittill( #"end_game" );
    if ( !isdefined( level.zt.box_lock_dvar_owned ) || !level.zt.box_lock_dvar_owned )
        return;

    setdvar( "magic_chest_movable", level.zt.box_lock_movable_stock );
    level.zt.box_lock_dvar_owned = 0;
}

zt_box_owner_watch()
{
    level endon( #"end_game" );
    while ( 1 )
    {
        if ( level.zt.config.box_lock )
        {
            setdvar( "magic_chest_movable", 0 );
        }
        if ( level.zt.config.box_quality != "default" || level.zt.config.box_no_repeat )
        {
            if ( !isdefined( level.customrandomweaponweights ) )
            {
                zt_box_weights_release_owner();
                level.customrandomweaponweights = ::zt_box_weights;
            }
            else if ( level.customrandomweaponweights != ::zt_box_weights )
            {
                zt_box_weights_adopt_owner( level.customrandomweaponweights );
                level.customrandomweaponweights = ::zt_box_weights;
            }
        }
        if ( level.zt.config.box_price_multiplier >= 0 || level.zt.config.fire_sale_box_price >= 0 )
            zt_box_prices_apply();
        if ( level.zt.config.box_no_repeat ) zt_box_record_offers();
        if ( zt_true( level.zt.teddy_chance_owned ) && ( !isdefined( level._zombiemode_chest_joker_chance_override_func ) || level._zombiemode_chest_joker_chance_override_func != ::zt_teddy_chance ) )
        {
            level.zt.teddy_chance_owned = 0;
            zt_feature( "teddy_chance", "unavailable", "map replaced Mystery Box teddy-bear chance" );
        }
        if ( ( level.zt.config.challenge_no_box || level.zt.config.challenge_wall_only ) && isdefined( level.chests ) )
        {
            for ( i = 0; i < level.chests.size; i++ )
                level.chests[i].disabled = 1;
        }
        if ( level.zt.config.fire_sale_box_price >= 0 && isdefined( level.zombie_vars ) && zt_true( level.zombie_vars["zombie_powerup_fire_sale_on"] ) ) wait 0.05;
        else wait 0.25;
    }
}

zt_teddy_chance_claim()
{
    // The stock callback is called after the map's own eligibility checks.
    // Never replace a callback another map/mod installed first.
    if ( !isdefined( level.chests ) || level.chests.size == 0 )
    {
        zt_feature( "teddy_chance", "unavailable", "map has not published a standard Mystery Box" );
        return;
    }
    if ( level.zt.config.box_lock || getdvarint( "magic_chest_movable" ) != 1 )
    {
        zt_feature( "teddy_chance", "unavailable", "Mystery Box relocation is disabled" );
        return;
    }
    if ( isdefined( level._zombiemode_chest_joker_chance_override_func ) )
    {
        zt_feature( "teddy_chance", "unavailable", "map owns Mystery Box teddy-bear chance" );
        return;
    }
    level._zombiemode_chest_joker_chance_override_func = ::zt_teddy_chance;
    level.zt.teddy_chance_owned = 1;
    zt_feature( "teddy_chance", "active", "" );
}

zt_teddy_chance( stock_chance )
{
    // The stock -1 also represents a missed stock pre-roll, not just an
    // ineligible box. Reconstruct the safety exclusions before rolling our
    // independent percentage, and preserve stock if the active chest is unknown.
    if ( !isdefined( level.chests ) || !isdefined( level.chest_index ) || level.chest_index < 0 || level.chest_index >= level.chests.size )
        return stock_chance;
    if ( !isdefined( level.chest_accessed ) || !isdefined( level.chest_min_move_usage ) )
        return stock_chance;
    if ( level.chest_accessed < level.chest_min_move_usage )
        return -1;
    if ( isdefined( level.chests[level.chest_index].no_fly_away ) )
        return -1;
    if ( isdefined( level.zombie_vars ) && zt_true( level.zombie_vars["zombie_powerup_fire_sale_on"] ) )
        return -1;
    if ( randomint( 100 ) < level.zt.config.teddy_bear_chance )
        return 100;
    return -1;
}

zt_box_prices_apply()
{
    if ( !isdefined( level.chests ) )
        return 0;

    // Legacy hints use a separate localized key for each price. An arbitrary
    // custom price could leave the prompt blank, so leave those maps alone.
    if ( zt_true( level.legacy_hint_system ) )
    {
        if ( level.zt.config.box_price_multiplier >= 0 ) zt_box_price_feature( "box_price_multiplier", "unavailable", "map uses fixed-price legacy Mystery Box hints" );
        if ( level.zt.config.fire_sale_box_price >= 0 ) zt_box_price_feature( "fire_sale_box_price", "unavailable", "map uses fixed-price legacy Mystery Box hints" );
        return 0;
    }

    fire_sale_on = isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_powerup_fire_sale_on"] ) && level.zombie_vars["zombie_powerup_fire_sale_on"];
    applied = 0;
    conflict = 0;
    for ( i = 0; i < level.chests.size; i++ )
    {
        chest = level.chests[i];
        if ( zt_true( chest.zt_box_price_owner_lost ) )
        {
            conflict++;
            continue;
        }
        if ( !isdefined( chest.old_cost ) || !isdefined( chest.zombie_cost ) )
            continue;

        if ( !isdefined( chest.zt_box_normal_base ) )
            chest.zt_box_normal_base = chest.old_cost;

        if ( fire_sale_on ) chest.zt_box_sale_restore_grace = 20;
        else if ( isdefined( chest.zt_box_sale_restore_grace ) && chest.zt_box_sale_restore_grace > 0 ) chest.zt_box_sale_restore_grace = chest.zt_box_sale_restore_grace - 1;

        if ( level.zt.config.box_price_multiplier >= 0 )
        {
            // Stock fire_sale_fix writes 950 during a sale. Outside that brief
            // restore window, an unexpected old_cost means a map owns it now.
            if ( isdefined( chest.zt_box_normal_applied ) && chest.old_cost != chest.zt_box_normal_applied && !fire_sale_on && !( zt_true( chest.zt_box_sale_restore_grace ) && chest.old_cost == 950 ) )
            {
                chest.zt_box_price_owner_lost = 1;
                conflict++;
                continue;
            }
            if ( isdefined( chest.zt_box_normal_applied ) && !fire_sale_on && !zt_true( chest.zt_box_sale_applied ) && chest.zombie_cost != chest.zt_box_normal_applied && !( zt_true( chest.zt_box_sale_restore_grace ) && ( chest.zombie_cost == 950 || chest.zombie_cost == 10 ) ) )
            {
                chest.zt_box_price_owner_lost = 1;
                conflict++;
                continue;
            }

            normal_cost = int( chest.zt_box_normal_base * level.zt.config.box_price_multiplier / 100.0 + 0.5 );
            if ( normal_cost < 0 ) normal_cost = 0;
            if ( chest.old_cost != normal_cost ) chest.old_cost = normal_cost;
            chest.zt_box_normal_applied = normal_cost;
            if ( !fire_sale_on )
                zt_box_price_set( chest, normal_cost );
            applied++;
        }

        if ( fire_sale_on && level.zt.config.fire_sale_box_price >= 0 )
        {
            zt_box_price_set( chest, level.zt.config.fire_sale_box_price );
            chest.zt_box_sale_applied = 1;
            applied++;
        }
        else if ( !fire_sale_on && isdefined( chest.zt_box_sale_applied ) && chest.zt_box_sale_applied )
        {
            zt_box_price_set( chest, chest.old_cost );
            chest.zt_box_sale_applied = 0;
        }
    }

    if ( applied > 0 || conflict > 0 )
    {
        if ( level.zt.config.box_price_multiplier >= 0 )
        {
            if ( conflict > 0 ) zt_box_price_feature( "box_price_multiplier", "degraded", "map replaced a Mystery Box price; that location remains map-owned" );
            else zt_box_price_feature( "box_price_multiplier", "active", "" );
        }
        if ( level.zt.config.fire_sale_box_price >= 0 )
        {
            if ( conflict > 0 ) zt_box_price_feature( "fire_sale_box_price", "degraded", "map replaced a Mystery Box price; that location remains map-owned" );
            else zt_box_price_feature( "fire_sale_box_price", "active", "" );
        }
    }
    return applied;
}

zt_box_price_feature( name, state, reason )
{
    if ( isdefined( level.zt.features[name] ) && level.zt.features[name].state == state && level.zt.features[name].reason == reason ) return;
    zt_feature( name, state, reason );
}

zt_box_price_set( chest, cost )
{
    changed = chest.zombie_cost != cost;
    if ( changed ) chest.zombie_cost = cost;
    if ( !changed && isdefined( chest.zt_box_hint_applied ) && chest.zt_box_hint_applied == cost ) return;
    if ( zt_true( chest.hidden ) || zt_true( chest._box_open ) || !isdefined( chest.unitrigger_stub ) ) return;
    stub = chest.unitrigger_stub;
    if ( zt_true( stub.trigger_per_player ) )
    {
        if ( !isdefined( stub.playertrigger ) ) return;
    }
    else if ( !isdefined( stub.trigger ) ) return;
    stub zm_utility::unitrigger_set_hint_string( chest, "default_treasure_chest", cost );
    chest.zt_box_hint_applied = cost;
}

zt_box_weights_release_owner()
{
    if ( !isdefined( level.zt_box_weights_chain ) || level.zt_box_weights_chain.size <= 0 )
    {
        level.zt_box_weights_chain = [];
        level.zt_box_weights_prev = level.zt_box_weights_base;
        return;
    }

    previous_index = level.zt_box_weights_chain.size - 1;
    previous = level.zt_box_weights_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_box_weights_chain[i];
    level.zt_box_weights_chain = restored_chain;
    level.zt_box_weights_prev = previous;
}

zt_box_record_offers()
{
    if ( !isdefined( level.chests ) ) return;
    for ( i = 0; i < level.chests.size; i++ )
    {
        chest = level.chests[i];
        if ( !isdefined( chest ) ) continue;
        // Stock raises this hint only for a finalized, non-teddy offer. Clear
        // our edge latch on closure so an identical later offer is observable.
        if ( !zt_true( chest.grab_weapon_hint ) )
        {
            chest.zt_box_offer_recorded = 0;
            continue;
        }
        if ( zt_true( chest.zt_box_offer_recorded ) || !isdefined( chest.chest_user ) || !isplayer( chest.chest_user ) || !isdefined( chest.grab_weapon ) || chest.grab_weapon == level.weaponNone ) continue;
        chest.chest_user.zt_box_last_offered_weapon = chest.grab_weapon;
        chest.zt_box_offer_recorded = 1;
    }
}

zt_box_avoid_duplicate( keys )
{
    if ( !level.zt.config.box_no_repeat || !isdefined( self ) || !isplayer( self ) || !isdefined( self.zt_box_last_offered_weapon ) || !isdefined( keys ) || keys.size < 2 ) return keys;
    alternatives = [];
    repeats = [];
    for ( i = 0; i < keys.size; i++ )
    {
        if ( keys[i] == self.zt_box_last_offered_weapon ) repeats[repeats.size] = keys[i];
        else alternatives[alternatives.size] = keys[i];
    }
    if ( alternatives.size == 0 || repeats.size == 0 ) return keys;
    // Keep every map-provided candidate and its relative order; stock still
    // decides eligibility. A single eligible weapon may therefore repeat.
    for ( i = 0; i < repeats.size; i++ ) alternatives[alternatives.size] = repeats[i];
    return alternatives;
}

zt_box_weights_adopt_owner( owner )
{
    if ( !isdefined( level.zt_box_weights_chain ) )
        level.zt_box_weights_chain = [];
    if ( !isdefined( level.zt_box_weights_prev ) )
    {
        level.zt_box_weights_prev = owner;
        return;
    }
    if ( level.zt_box_weights_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_box_weights_chain.size; i++ )
    {
        if ( level.zt_box_weights_chain[i] == owner )
            restored_index = i;
    }
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_box_weights_chain[i];
        level.zt_box_weights_chain = restored_chain;
    }
    else
        level.zt_box_weights_chain[level.zt_box_weights_chain.size] = level.zt_box_weights_prev;
    level.zt_box_weights_prev = owner;
}

zt_box_weights_forward( keys )
{
    depth = 0;
    if ( isdefined( level.zt_box_weights_inside ) )
        depth = level.zt_box_weights_inside;

    callback = level.zt_box_weights_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_box_weights_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_box_weights_chain[chain_index];
        else
            callback = level.zt_box_weights_base;
    }
    if ( !isdefined( callback ) )
        return keys;

    level.zt_box_weights_inside = depth + 1;
    result = self [[ callback ]]( keys );
    level.zt_box_weights_inside = depth;
    if ( !isdefined( result ) )
        result = keys;
    return result;
}

zt_box_weights( keys )
{
    if ( zt_true( level.zt_box_weights_inside ) )
        return self zt_box_weights_forward( keys );

    // Every mode composes after the complete map/custom callback chain.
    // EVERYTHING means no additional ZTweaks filtering or promotion; it must
    // not bypass a map's eligibility, side effects, or authored weighting.
    keys = self zt_box_weights_forward( keys );
    if ( level.zt.config.box_quality == "no_wonders" )
    {
        filtered = [];
        for ( i = 0; i < keys.size; i++ )
            if ( isdefined( level.zombie_weapons[keys[i]] ) && ( !isdefined( level.zombie_weapons[keys[i]].is_wonder_weapon ) || !level.zombie_weapons[keys[i]].is_wonder_weapon ) ) filtered[filtered.size] = keys[i];
        // An empty safe pool must stop the pull. Falling through would hand
        // the box its original wonder-only list and violate NO WONDERS.
        return self zt_box_avoid_duplicate( filtered );
    }
    if ( level.zt.config.box_quality == "improved" )
    {
        high = [];
        for ( i = 0; i < keys.size; i++ )
        {
            if ( isdefined( level.zombie_weapons[keys[i]].cost ) && level.zombie_weapons[keys[i]].cost >= 1500 ) high[high.size] = keys[i];
        }
        // Promote a random strong candidate most of the time without sorting
        // the entire pool into a guaranteed high-tier result.
        if ( high.size > 0 && randomint( 100 ) < 65 )
        {
            promoted = high[randomint( high.size )];
            result = [];
            result[0] = promoted;
            for ( i = 0; i < keys.size; i++ )
                if ( keys[i] != promoted ) result[result.size] = keys[i];
            return self zt_box_avoid_duplicate( result );
        }
    }
    return self zt_box_avoid_duplicate( keys );
}

zt_challenges_install()
{
    if ( level.zt.config.challenge_no_perks ) zt_feature( "challenge_no_perks", "degraded", "standard purchases and ZTweaks grants are blocked; scripted quest grants remain map-owned" );
    if ( level.zt.config.challenge_no_pap ) zt_feature( "challenge_no_pap", "unavailable", "the map exposes no universal safe Pack-a-Punch disable callback" );
    if ( level.zt.config.challenge_starting_room ) zt_feature( "challenge_starting_room", "unavailable", "the map does not publish a safe starting-zone exit set" );
    if ( level.zt.config.challenge_gun_game ) zt_feature( "challenge_gun_game", "unavailable", "the registered weapon pool cannot guarantee quest-safe replacement" );
    if ( level.zt.config.challenge_random_rules )
        zt_feature( "challenge_random_rules", "active", "selected " + level.zt.random_challenge_name + " for this match" );
}

zt_one_weapon_slot_install()
{
    // Stock weapon pickups consult this level callback after any per-player
    // override. Leave a map's level rule alone and yield to late owners.
    if ( isdefined( level.get_player_weapon_limit ) )
    {
        zt_feature( "challenge_one_weapon_slot", "unavailable", "map owns the primary-weapon limit" );
        return;
    }
    level.get_player_weapon_limit = ::zt_one_weapon_slot_limit;
    zt_feature( "challenge_one_weapon_slot", "active", "" );
    if ( level.zt.config.secondary_starting_weapon != "default" )
        zt_feature( "secondary_starting_weapon", "unavailable", "one-weapon-slot challenge takes precedence" );
    level endon( #"end_game" );
    while ( 1 )
    {
        if ( level.get_player_weapon_limit != ::zt_one_weapon_slot_limit )
        {
            zt_feature( "challenge_one_weapon_slot", "degraded", "map replaced the primary-weapon limit" );
            return;
        }
        wait 0.5;
    }
}

zt_one_weapon_slot_limit( player )
{
    return 1;
}

zt_build_watermark()
{
    level endon( #"end_game" );

    stamp = build();
    if ( stamp == "" )
        return;

    while ( !zt_game_ready() )
        wait 0.5;

    if ( zt_cfg_int( "zt_auto_restart", 0 ) )
        stamp = stamp + "  [AR ON]";

    if ( zt_cfg_int( "zt_start_doors_open", 0 ) )
        stamp = stamp + "  [DOORS ON]";

    grenade_name = zt_cfg_string( "zt_starting_grenade", "default" );
    grenade_count = zt_cfg_int( "zt_starting_grenade_count", 0 );
    grenade_max = zt_cfg_int( "zt_max_grenades", 0 );
    if ( grenade_name != "default" || grenade_count > 0 || grenade_max > 0 )
        stamp = stamp + "  [G " + grenade_name + " " + grenade_count + "/" + grenade_max + "]";

    equipment_name = zt_cfg_string( "zt_starting_equipment", "default" );
    equipment_count = zt_cfg_int( "zt_starting_equipment_count", 0 );
    equipment_max = zt_cfg_int( "zt_max_equipment", 0 );
    if ( equipment_name != "default" || equipment_count > 0 || equipment_max > 0 )
        stamp = stamp + "  [E " + equipment_name + " " + equipment_count + "/" + equipment_max + "]";

    if ( isdefined( level.zt_build_hud ) )
        return;

    // ZPause uses y=8 and ZShare uses y=26. ZTweaks owns the third row.
    e = newhudelem();
    e.horzalign = "right";
    e.vertalign = "top";
    e.alignx = "right";
    e.aligny = "top";
    e.x = 0;
    e.y = 44;
    e.fontscale = 1.1;
    e.color = ( 1, 0.72, 0.32 );
    e.sort = 1000;
    e.foreground = 1;
    e.alpha = 0.7;
    e settext( stamp );
    level.zt_build_hud = e;
}

build()
{
    // ZT_BUILD_BEGIN
    return "";
    // ZT_BUILD_END
}
