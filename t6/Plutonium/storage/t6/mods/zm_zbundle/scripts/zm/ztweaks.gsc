// ZTWEAKS T6 v1.4
// Compatibility-first Zombies tweaks. Inactive live-boundary hooks preserve stock behavior.

// T6 custom scripts do not inherit the stock Zombies include table. These
// imports resolve the utility helpers used below when the script is linked.
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\gametypes_zm\_hud_util;

init()
{
    if ( zt_true( level.zt_loaded ) )
        return;

    level.zt_loaded = 1;
    level.zt = spawnstruct();
    level.zt.config = spawnstruct();
    level.zt.features = [];
    level.zt.feature_messages = [];
    // The report UI reads client dvars; server-only status dvars are not
    // sufficient. A per-match epoch rejects values left by the previous map.
    level.zt.report_epoch = "" + gettime();
    level.zt.powerup_effect_state = [];
    level.zt.powerup_filter_prev = [];
    level.zt.powerup_filter_owned = [];
    level.zt.powerup_filter_yielded = [];
    level.zt.powerup_filter_any_yielded = 0;
    level.zt.powerup_activation_serial = [];
    level.zt.powerup_activation_watch = [];
    level.zt.mods = [];

    zt_load_config();
    zt_register_self();
    level thread zt_build_watermark();
    // The load-time T6 client-dvar probe is retired: it repeatedly missed
    // stock casting and its enabled runs stalled during TranZit loading.
    // Keep this one-line marker so an old archived dvar cannot silently
    // appear to be an active character preference feature.
    if ( getdvarint( "zt_character_probe" ) == 1 )
        println( "ZT_CHAR_PROBE|port=t6|event=retired|reason=load_time_transport_failed" );
    if ( !level.zt.config.enabled )
        return;
    zt_boot_trace( "configured" );
    zt_feature( "perk_limit", "inherit", "" );
    zt_feature( "auto_restart", "inherit", "" );
    zt_feature( "next_map", "inherit", "" );
    zt_feature( "starting_round", "inherit", "" );
    zt_feature( "starting_points", "inherit", "" );
    zt_feature( "game_start_delay", "inherit", "" );
    zt_feature( "player_health", "inherit", "" );
    zt_feature( "health_regen_delay", "inherit", "" );
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
    zt_feature( "bank_limit", "inherit", "" );
    zt_feature( "start_power_on", "inherit", "" );
    zt_feature( "start_doors_open", "inherit", "" );
    zt_new_features_init();
    zt_boot_trace( "features_registered" );

    if ( level.zt.config.perk_limit != 0 || level.zt.config.challenge_no_perks )
        level thread zt_perk_limit_install();

    if ( zt_has_match_tweaks() )
        level thread zt_match_tweaks_install();

    if ( zt_has_pacing_tweaks() )
        level thread zt_pacing_install();

    if ( zt_has_box_tweaks() )
        level thread zt_box_tweaks_install();

    if ( level.zt.config.trap_price_multiplier >= 0 )
        level thread zt_trap_price_install();

    if ( level.zt.config.health_regen_delay > 0 )
        level thread zt_regen_delay_install();

    if ( level.zt.config.death_points_retained >= 0 )
        level thread zt_death_points_install();

    level thread zt_round_bonus_install();

    level thread zt_point_gain_install();
    level thread zt_challenges_install();
    if ( level.zt.config.challenge_one_weapon_slot )
        level thread zt_one_weapon_slot_install();

    if ( level.zt.config.bank_limit > 0 )
        level thread zt_bank_limit_install();

    if ( level.zt.config.start_power_on )
        level thread zt_start_power_install();

    if ( level.zt.config.start_doors_open )
        level thread zt_start_doors_install();

    // All passive NEXT SPAWN / NEXT ROUND / NEXT DROP adapters need the stock
    // round-ready boundary anyway. One waiter avoids a fan-out of pre-round
    // polling threads while stock is still connecting players and loading.
    level thread zt_round_ready_install();
    zt_boot_trace( "pre_round_workers_scheduled" );
}

zt_boot_trace( stage )
{
    if ( issubstr( zt_version(), ".d" ) )
        println( "ZTWEAKS_BOOT|version=" + zt_version() + "|stage=" + stage + "|doors=" + level.zt.config.start_doors_open + "|power=" + level.zt.config.start_power_on );
}

zt_round_ready_install()
{
    level endon( "end_game" );
    elapsed = 0;
    reported_10 = 0;
    reported_30 = 0;
    while ( !zt_game_ready() )
    {
        wait 0.1;
        elapsed += 0.1;
        if ( issubstr( zt_version(), ".d" ) && ( ( elapsed >= 10 && !reported_10 ) || ( elapsed >= 30 && !reported_30 ) ) )
        {
            if ( elapsed >= 30 )
                reported_30 = 1;
            else
                reported_10 = 1;
            println( "ZTWEAKS_BOOT|version=" + zt_version() + "|stage=waiting_round|seconds=" + int( elapsed ) + "|initial_players=" + zt_flag_is_set( "initial_players_connected" ) + "|expected=" + getnumexpectedplayers() + "|connected=" + getnumconnectedplayers() + "|textures=" + aretexturesloaded() );
        }
    }
    zt_boot_trace( "round_ready" );

    level thread zt_player_watch();
    level thread zt_match_value_owner_watch();
    level thread zt_zombies_per_round_install();
    level thread zt_powerup_controls_install();
    level thread zt_damage_tweaks_install();
    if ( level.zt.config.fast_barrier_rebuild ) level thread zt_fast_barrier_rebuild_install();
    level thread zt_down_tweaks_install();
    // Re-sample after stock startup so a frontend dvar write cannot race it.
    level thread zt_auto_restart_install();
    zt_boot_trace( "passive_workers_scheduled" );
}

zt_true( value )
{
    return isdefined( value ) && value;
}

zt_cfg_int( name, def )
{
    return int( set_dvar_if_unset( name, "" + def ) );
}

zt_cfg_string( name, def )
{
    return set_dvar_if_unset( name, def );
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
    level.zt.config.auto_restart = zt_cfg_int( "zt_auto_restart", 0 );
    level.zt.config.next_map = zt_cfg_string( "zt_next_map", "same" );
    level.zt.config.starting_round = zt_cfg_int( "zt_starting_round", 0 );
    level.zt.config.starting_points = zt_cfg_int( "zt_starting_points", 0 );
    level.zt.config.game_start_delay = zt_cfg_int( "zt_game_start_delay", -1 );
    level.zt.config.player_health = zt_cfg_int( "zt_player_health", 0 );
    level.zt.config.health_regen_delay = zt_cfg_int( "zt_health_regen_delay", 0 );
    level.zt.config.round_bonus = zt_cfg_int( "zt_round_bonus", 0 );
    level.zt.config.max_ammo_reload = zt_cfg_int( "zt_max_ammo_reload", 0 );
    level.zt.config.death_points_retained = zt_cfg_int( "zt_death_points_retained", -1 );
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
    level.zt.config.bank_limit = zt_cfg_int( "zt_bank_limit", 0 );
    level.zt.config.start_power_on = zt_cfg_int( "zt_start_power_on", 0 );
    level.zt.config.start_doors_open = zt_cfg_int( "zt_start_doors_open", 0 );
    level.zt.config.point_gain = zt_cfg_int( "zt_point_gain", 0 );
    level.zt.config.starting_ammo = zt_cfg_int( "zt_starting_ammo", 0 );
    level.zt.config.reserve_ammo = zt_cfg_int( "zt_reserve_ammo", 0 );
    level.zt.config.starting_weapon_upgraded = zt_cfg_string( "zt_starting_weapon_upgraded", "default" );
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
    level.zt.config.spawn_protection = zt_cfg_int( "zt_spawn_protection", 0 );
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

    // ZBundle's shared registry. Existing registrations are preserved.
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
    level.zt.features[name] = feature;

    if ( changed && ( state != "inherit" || had_previous ) )
    {
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            if ( zt_true( players[i].zt_report_ready ) )
                players[i] zt_report_publish( name, state, reason );
        }
    }

    // Development builds emit one structured line per real state transition.
    // Initial inherit rows stay quiet, while returning an active tweak to its
    // semantic default is still recorded for callback-ownership verification.
    if ( changed && ( state != "inherit" || had_previous ) && issubstr( zt_version(), ".d" ) )
        zt_feature_trace( name, state, reason );
}

zt_report_publish( name, state, reason )
{
    self SetClientDvar( "zt_ui_status_" + name, level.zt.report_epoch + "|" + state );
    self SetClientDvar( "zt_ui_reason_" + name, level.zt.report_epoch + "|" + reason );
}

zt_report_sync_player()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    while ( !zt_game_ready() )
        wait 0.1;

    // BO2's SetClientDvar is a reliable server command. A late, slow client
    // must not receive every active compatibility row in one loading burst.
    // This report is diagnostic; it can trail the actual gameplay join.
    wait 5;

    // Publish the epoch before rows so the menu rejects prior-match values.
    // Live zt_feature changes may publish concurrently; each snapshot row
    // reads its current value, so the latest state wins either ordering.
    self SetClientDvar( "zt_ui_report_epoch", level.zt.report_epoch );
    self.zt_report_ready = 1;

    keys = getarraykeys( level.zt.features );
    for ( i = 0; i < keys.size; i++ )
    {
        name = keys[i];
        feature = level.zt.features[name];
        if ( feature.state != "inherit" || feature.reason != "" )
        {
            self zt_report_publish( name, feature.state, feature.reason );
            wait 0.25;
        }
    }
}

zt_feature_trace( name, state, reason )
{
    map_name = getdvar( "mapname" );
    if ( map_name == "" && isdefined( level.script ) )
        map_name = level.script;
    if ( map_name == "" )
        map_name = "unknown";
    line = "ZTWEAKS_RUNTIME|version=" + zt_version() + "|port=t6|map=" + map_name + "|feature=" + name + "|state=" + state;
    if ( reason != "" )
        line = line + "|reason=" + reason;
    println( line );
}

zt_new_features_init()
{
    names = [];
    names[0] = "point_gain";
    names[1] = "starting_ammo";
    names[2] = "reserve_ammo";
    names[3] = "starting_weapon_upgraded";
    names[4] = "weapon_damage";
    names[5] = "melee_damage";
    names[6] = "no_explosive_self_damage";
    names[7] = "fall_damage";
    names[8] = "box_quality";
    names[9] = "box_lock";
    names[10] = "box_price_multiplier";
    names[11] = "fire_sale_box_price";
    names[12] = "teddy_chance";
    names[13] = "powerup_stacking";
    names[14] = "down_limit";
    names[15] = "revive_time";
    names[16] = "bleedout_time";
    names[17] = "spawn_protection";
    names[18] = "lose_perks_on_down";
    names[19] = "keep_weapons_bleedout";
    names[20] = "challenge_no_perks";
    names[21] = "challenge_no_pap";
    names[22] = "challenge_no_box";
    names[23] = "challenge_wall_only";
    names[24] = "challenge_starting_room";
    names[25] = "challenge_one_box";
    names[26] = "challenge_gun_game";
    names[27] = "challenge_random_loadout";
    names[28] = "challenge_random_rules";
    names[29] = "zombie_damage";
    names[30] = "box_no_repeat";
    names[31] = "trap_price_multiplier";
    names[32] = "health_regen_delay";
    names[33] = "round_bonus";
    names[34] = "max_ammo_reload";
    names[35] = "death_points_retained";
    names[36] = "challenge_one_weapon_slot";
    names[37] = "powerup_drop_filters";
    names[38] = "challenge_rising_damage";
    names[39] = "pap_damage_multiplier";
    names[40] = "fast_barrier_rebuild";
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
    if ( name == "health_regen_delay" ) return "Health Regen Delay";
    if ( name == "round_bonus" ) return "Round Bonus";
    if ( name == "max_ammo_reload" ) return "Max Ammo Reloads Magazines";
    if ( name == "death_points_retained" ) return "Points Retained After Death";
    if ( name == "challenge_one_weapon_slot" ) return "One Weapon Slot";
    if ( name == "challenge_rising_damage" ) return "Rising Player Damage";
    if ( name == "pap_damage_multiplier" ) return "Pack-a-Punch Damage";
    if ( name == "fast_barrier_rebuild" ) return "Faster Barrier Rebuild";
    if ( name == "powerup_drop_filters" ) return "Power-Up Drop Filters";
    if ( name == "start_power_on" ) return "Start With Power";
    if ( name == "start_doors_open" ) return "Start With Doors Open";
    if ( name == "bank_limit" ) return "Bank Limit";
    if ( name == "perk_limit" ) return "Perk Limit";
    return name;
}

zt_feature_message( name, reason )
{
    level endon( "end_game" );

    elapsed = 0;
    while ( elapsed < 30 )
    {
        players = get_players();
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
    self endon( "disconnect" );
    level endon( "end_game" );
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
                self SetClientDvar( "zt_ui_notice_" + self getentitynumber(), zt_notice_signature() + "|" + self.zt_notice_token + "|" + entry.code + "|" + int( elapsed ) );
            }
            wait 0.25;
            elapsed += 0.25;
        }
        if ( !self.zt_notice_received ) self iprintlnbold( entry.fallback );
        self.zt_notice_head++;
        wait 0.25;
    }
    self notify( "zt_notice_stop" );
    self.zt_notice_queue = [];
    self.zt_notice_head = 0;
    self.zt_notice_running = 0;
}

zt_notice_ack()
{
    self endon( "disconnect" );
    self endon( "zt_notice_stop" );
    level endon( "end_game" );
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
    return isdefined( level.flag ) && isdefined( level.flag["start_zombie_round_logic"] ) && level.flag["start_zombie_round_logic"];
}

zt_has_match_tweaks()
{
    return level.zt.config.starting_round > 0 || level.zt.config.starting_points > 0 || level.zt.config.game_start_delay >= 0 || level.zt.config.player_health > 0 || level.zt.config.zombie_health > 0 || level.zt.config.zombie_speed > 0 || level.zt.config.headshots_only || level.zt.config.starting_weapon != "default" || level.zt.config.secondary_starting_weapon != "default";
}

zt_has_player_tweaks()
{
    return level.zt.config.player_health > 0 || level.zt.config.max_grenades > 0 || level.zt.config.max_equipment > 0 || level.zt.config.starting_weapon != "default" || level.zt.config.secondary_starting_weapon != "default" || level.zt.config.random_starting_perks > 0 || level.zt.config.starting_grenade != "default" || level.zt.config.starting_grenade_count > 0 || level.zt.config.starting_equipment != "default" || level.zt.config.starting_equipment_count > 0 || level.zt.config.start_all_perks || level.zt.config.player_speed > 0 || level.zt.config.starting_ammo != 0 || level.zt.config.reserve_ammo > 0 || level.zt.config.starting_weapon_upgraded != "default" || level.zt.config.spawn_protection > 0 || level.zt.config.challenge_random_loadout;
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
    level endon( "end_game" );

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
        if ( isdefined( level.zombie_vars["game_start_delay"] ) )
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

    // Match-owned zombie curves were claimed before round logic. The
    // passive post-start owner may keep composing them only after this safe
    // initialization path completed; a late script attachment must remain
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
        return "m1911_zm";
    if ( choice == "burst" )
        return "beretta93r_zm";
    if ( choice == "smg" )
        return "mp7_zm";
    if ( choice == "shotgun" )
        return "870mcs_zm";
    if ( choice == "ar" )
        return "an94_zm";
    if ( choice == "lmg" )
        return "hamr_zm";
    if ( choice == "sniper" )
        return "dsr50_zm";
    return "";
}

zt_starting_weapon_candidates( choice )
{
    weapons = [];
    if ( choice == "pistol" )
    {
        weapons[weapons.size] = "m1911_zm";
        weapons[weapons.size] = "fiveseven_zm";
        weapons[weapons.size] = "kard_zm";
    }
    else if ( choice == "burst" )
    {
        weapons[weapons.size] = "beretta93r_zm";
    }
    else if ( choice == "smg" )
    {
        weapons[weapons.size] = "mp7_zm";
        weapons[weapons.size] = "pdw57_zm";
        weapons[weapons.size] = "msmc_zm";
        weapons[weapons.size] = "ak74u_zm";
        weapons[weapons.size] = "chicom_zm";
        weapons[weapons.size] = "skorpion_zm";
        weapons[weapons.size] = "uzi_zm";
    }
    else if ( choice == "shotgun" )
    {
        weapons[weapons.size] = "870mcs_zm";
        weapons[weapons.size] = "srm1216_zm";
        weapons[weapons.size] = "saiga12_zm";
        weapons[weapons.size] = "olympia_zm";
    }
    else if ( choice == "ar" )
    {
        weapons[weapons.size] = "an94_zm";
        weapons[weapons.size] = "galil_zm";
        weapons[weapons.size] = "m16_zm";
        weapons[weapons.size] = "m14_zm";
        weapons[weapons.size] = "mtar_zm";
        weapons[weapons.size] = "type95_zm";
        weapons[weapons.size] = "scar_zm";
        weapons[weapons.size] = "fnfal_zm";
    }
    else if ( choice == "lmg" )
    {
        weapons[weapons.size] = "hamr_zm";
        weapons[weapons.size] = "lsat_zm";
        weapons[weapons.size] = "rpd_zm";
        weapons[weapons.size] = "hk21_zm";
        weapons[weapons.size] = "mg08_zm";
    }
    else if ( choice == "sniper" )
    {
        weapons[weapons.size] = "dsr50_zm";
        weapons[weapons.size] = "svu_zm";
        weapons[weapons.size] = "barretm82_zm";
        weapons[weapons.size] = "ballista_zm";
    }
    return weapons;
}

zt_weapon_matches_class( weapon, choice )
{
    if ( !isdefined( weapon ) || weapon == "" || issubstr( weapon, "upgraded" ) || zt_t6_unsafe_random_weapon( weapon ) )
        return false;

    weapon_class = weaponclass( weapon );
    stats_class = maps\mp\_utility::getweaponclass( weapon );
    is_sniper = stats_class == "weapon_sniper" || issubstr( weapon, "sniper" );

    if ( choice == "burst" )
        return weapon_class == "pistol" && ( issubstr( weapon, "burst" ) || issubstr( weapon, "93r" ) );
    if ( choice == "pistol" )
        return ( weapon_class == "pistol" || weapon_class == "pistolspread" || weapon_class == "pistol spread" ) && !is_sniper;
    if ( choice == "smg" )
        return weapon_class == "smg";
    if ( choice == "shotgun" )
        return weapon_class == "spread";
    if ( choice == "ar" )
        return weapon_class == "rifle" && !is_sniper;
    if ( choice == "lmg" )
        return weapon_class == "mg";
    if ( choice == "sniper" )
        return is_sniper;
    return false;
}

zt_t6_unsafe_random_weapon( weapon )
{
    if ( !isdefined( weapon ) || weapon == "" )
        return true;

    // BO2 does not publish BO3's is_wonder_weapon registry bit. Several
    // stock wonder/quest weapons also use an ordinary firearm class and a
    // low registry cost (notably the Blundergat and Paralyzer), so neither
    // weaponclass nor the 5000-point sentinel is sufficient by itself.
    // Keep stock quest families and common custom-map wonder families out of
    // both RANDOM LOADOUT and the class-based fallback selector.
    return issubstr( weapon, "ray_gun" ) || issubstr( weapon, "raygun" ) ||
        issubstr( weapon, "blundergat" ) || issubstr( weapon, "blundersplat" ) ||
        issubstr( weapon, "slowgun" ) || issubstr( weapon, "slipgun" ) ||
        issubstr( weapon, "jetgun" ) || issubstr( weapon, "staff_" ) ||
        issubstr( weapon, "tesla" ) || issubstr( weapon, "thundergun" ) ||
        issubstr( weapon, "wavegun" ) || issubstr( weapon, "vr11" ) ||
        issubstr( weapon, "shrink" ) || issubstr( weapon, "wonder" );
}

zt_find_starting_weapon( choice, excluded )
{
    if ( !isdefined( level.zombie_weapons ) )
        return "";

    weapons = zt_starting_weapon_candidates( choice );
    for ( i = 0; i < weapons.size; i++ )
    {
        if ( weapons[i] != excluded && zt_starting_weapon_registry_safe( weapons[i] ) )
            return weapons[i];
    }

    // Custom maps frequently register weapons outside BO2's stock name list.
    // Fall back to the weapon asset/stat class while still preferring the
    // deterministic stock representative above when it is available.
    weapons = getarraykeys( level.zombie_weapons );
    for ( i = 0; i < weapons.size; i++ )
    {
        entry = level.zombie_weapons[weapons[i]];
        high_sentinel = isdefined( entry ) && isdefined( entry.cost ) && entry.cost >= 5000;
        if ( weapons[i] != excluded && !high_sentinel && zt_starting_weapon_registry_safe( weapons[i] ) && zt_weapon_matches_class( weapons[i], choice ) )
            return weapons[i];
    }
    return "";
}

zt_starting_weapon_registry_safe( weapon )
{
    if ( !isdefined( weapon ) || weapon == "" || !isdefined( level.zombie_weapons ) || !isdefined( level.zombie_weapons[weapon] ) )
        return false;
    if ( zt_t6_unsafe_random_weapon( weapon ) )
        return false;
    if ( isdefined( level.limited_weapons ) && isdefined( level.limited_weapons[weapon] ) )
        return false;
    entry = level.zombie_weapons[weapon];
    if ( isdefined( entry.cost ) && entry.cost >= 5000 )
        return false;

    // A custom map can register quest inventory with an ordinary firearm
    // class and forget both the limited-weapon table and a sentinel price.
    // Implicit class selection therefore requires a stock acquisition seam:
    // the authoritative starter, a real spawned wall-buy, or box eligibility.
    if ( ( isdefined( level.start_weapon ) && weapon == level.start_weapon ) ||
         ( isdefined( level.zt.map_start_weapon ) && weapon == level.zt.map_start_weapon ) )
        return true;
    if ( isdefined( entry.is_in_box ) && entry.is_in_box )
        return true;
    if ( isdefined( level._spawned_wallbuys ) )
    {
        foreach ( wallbuy in level._spawned_wallbuys )
        {
            if ( ( isdefined( wallbuy.zombie_weapon_upgrade ) && wallbuy.zombie_weapon_upgrade == weapon ) ||
                 ( isdefined( wallbuy.weapon_upgrade ) && wallbuy.weapon_upgrade == weapon ) )
                return true;
        }
    }
    return false;
}

zt_starting_weapon_apply()
{
    choice = level.zt.config.starting_weapon;
    if ( zt_starting_weapon_name( choice ) == "" )
    {
        zt_feature( "starting_weapon", "unavailable", "unknown weapon class" );
        return;
    }

    while ( ( !isdefined( level.zombie_weapons ) || !isdefined( level.start_weapon ) ) && !zt_game_ready() )
        wait 0.05;

    if ( !isdefined( level.start_weapon ) || level.start_weapon == "" )
    {
        zt_feature( "starting_weapon", "unavailable", "map exposes no authoritative starting-weapon replacement seam" );
        return;
    }

    weapon = zt_find_starting_weapon( choice, "" );
    if ( weapon == "" )
    {
        zt_feature( "starting_weapon", "unavailable", "selected weapon is not registered by this map" );
        return;
    }

    if ( !isdefined( level.zt.map_start_weapon ) )
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

    excluded = "";
    if ( isdefined( level.start_weapon ) )
        excluded = level.start_weapon;
    if ( isdefined( level.zt.start_weapon_override ) )
        excluded = level.zt.start_weapon_override;
    weapon = zt_find_starting_weapon( choice, excluded );
    if ( weapon == "" )
    {
        zt_feature( "secondary_starting_weapon", "unavailable", "no second registered weapon matches the selected class" );
        return;
    }

    level.zt.secondary_start_weapon_override = weapon;
    zt_feature( "secondary_starting_weapon", "active", "" );
}

zt_apply_player_starting_weapon()
{
    if ( level.zt.config.starting_weapon == "default" )
        return;

    if ( !isdefined( level.zt.start_weapon_override ) )
        zt_starting_weapon_apply();
    if ( !isdefined( level.zt.start_weapon_override ) || level.zt.start_weapon_override == "" )
        return;

    weapon = level.zt.start_weapon_override;
    self.zt_start_primary_weapon = weapon;
    self.zt_starting_ammo_weapons = [];
    self.zt_starting_ammo_weapons[weapon] = 1;
    level.start_weapon = weapon;
    primaries = self getweaponslistprimaries();
    for ( i = 0; i < primaries.size; i++ )
    {
        // Replace only the map starter so late script attachment cannot
        // delete carried quest weapons or map-authored utility primaries.
        if ( isdefined( level.zt.map_start_weapon ) && primaries[i] == level.zt.map_start_weapon && primaries[i] != weapon )
            self takeweapon( primaries[i] );
    }
    if ( !( self hasweapon( weapon ) ) )
        self maps\mp\zombies\_zm_weapons::weapon_give( weapon, 0, 0, 1 );
    self switchtoweapon( weapon );
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
    if ( !isdefined( level.start_weapon ) || level.start_weapon == "" )
    {
        zt_feature( "challenge_random_loadout", "unavailable", "map exposes no authoritative starting-weapon replacement seam" );
        return;
    }
    if ( !isdefined( level.zt.map_start_weapon ) )
        level.zt.map_start_weapon = level.start_weapon;
    keys = getarraykeys( level.zombie_weapons );
    candidates = [];
    for ( i = 0; i < keys.size; i++ )
    {
        weapon = keys[i];
        if ( weapon != level.zt.secondary_start_weapon_override && self zt_safe_random_starting_weapon( weapon, level.zombie_weapons[weapon] ) )
            candidates[candidates.size] = weapon;
    }
    if ( candidates.size <= 0 )
    {
        zt_feature( "challenge_random_loadout", "unavailable", "map registered no compatible carried weapons" );
        return;
    }
    weapon = candidates[randomint( candidates.size )];
    self.zt_random_start_weapon = weapon;
    self.zt_starting_ammo_weapons = [];
    self.zt_starting_ammo_weapons[weapon] = 1;
    primaries = self getweaponslistprimaries();
    for ( i = 0; i < primaries.size; i++ )
    {
        if ( isdefined( level.zt.map_start_weapon ) && primaries[i] == level.zt.map_start_weapon && primaries[i] != weapon )
            self takeweapon( primaries[i] );
    }
    self maps\mp\zombies\_zm_weapons::weapon_give( weapon, 0, 0, 1 );
    self switchtoweapon( weapon );
    zt_feature( "challenge_random_loadout", "active", "independent safe box firearm selected for each player" );
}

zt_safe_random_starting_weapon( weapon, entry )
{
    if ( !isdefined( weapon ) || weapon == "" || !isdefined( entry ) || !isdefined( entry.is_in_box ) || !entry.is_in_box )
        return false;
    // BO2 does not publish the explicit wonder-weapon bit used by BO3.  Its
    // ordinary box firearms are classed and have a sub-5000 registry cost;
    // quest/wonder entries use special classes or the high sentinel cost.
    if ( zt_t6_unsafe_random_weapon( weapon ) || ( isdefined( entry.cost ) && entry.cost >= 5000 ) )
        return false;
    // Starting-loadout randomization is intentionally narrower than a live
    // box pull: limited/quest weapons must never be consumed at spawn even
    // while their quota is technically free.
    if ( isdefined( level.limited_weapons ) && isdefined( level.limited_weapons[weapon] ) )
        return false;
    if ( self has_weapon_or_upgrade( weapon ) )
        return false;
    if ( !( self maps\mp\zombies\_zm_weapons::player_can_use_content( weapon ) ) ||
         !( maps\mp\zombies\_zm_magicbox::treasure_chest_canplayerreceiveweapon( self, weapon, undefined ) ) )
        return false;
    weapon_class = weaponclass( weapon );
    return weapon_class == "pistol" || weapon_class == "pistolspread" || weapon_class == "pistol spread" || weapon_class == "smg" || weapon_class == "spread" || weapon_class == "rifle" || weapon_class == "mg";
}

zt_upgraded_weapon( weapon )
{
    if ( !isdefined( weapon ) || weapon == "" || !isdefined( level.zombie_weapons ) || !isdefined( level.zombie_weapons[weapon] ) || !( maps\mp\zombies\_zm_weapons::can_upgrade_weapon( weapon ) ) )
        return "";
    return maps\mp\zombies\_zm_weapons::get_upgrade_weapon( weapon, 0 );
}

zt_upgrade_starting_slot( weapon, feature )
{
    upgraded = zt_upgraded_weapon( weapon );
    if ( upgraded == "" )
    {
        zt_feature( feature, "unavailable", "the selected starting weapon has no registered Pack-a-Punch upgrade" );
        return weapon;
    }
    if ( self hasweapon( weapon ) )
        self takeweapon( weapon );
    if ( !( self hasweapon( upgraded ) ) )
        self maps\mp\zombies\_zm_weapons::weapon_give( upgraded, 1, 0, 1 );
    if ( isdefined( self.zt_starting_ammo_weapons ) )
    {
        self.zt_starting_ammo_weapons[weapon] = undefined;
        self.zt_starting_ammo_weapons[upgraded] = 1;
    }
    zt_feature( feature, "active", "" );
    return upgraded;
}

zt_apply_player_secondary_starting_weapon()
{
    if ( level.zt.config.secondary_starting_weapon == "default" )
        return;

    if ( !isdefined( level.zt.secondary_start_weapon_override ) )
        zt_secondary_starting_weapon_apply();
    if ( !isdefined( level.zt.secondary_start_weapon_override ) || level.zt.secondary_start_weapon_override == "" )
        return;

    weapon = level.zt.secondary_start_weapon_override;
    self.zt_start_secondary_weapon = weapon;
    self.zt_starting_ammo_weapons[weapon] = 1;
    if ( !( self hasweapon( weapon ) ) )
    {
        primaries = self getweaponslistprimaries();
        if ( primaries.size >= get_player_weapon_limit( self ) )
        {
            zt_feature( "secondary_starting_weapon", "unavailable", "map's starting loadout already fills every primary slot" );
            return;
        }
        self maps\mp\zombies\_zm_weapons::weapon_give( weapon, 0, 0, 1 );
    }
}

zt_apply_starting_upgrades()
{
    mode = level.zt.config.starting_weapon_upgraded;
    if ( mode == "default" )
        return;
    primary = undefined;
    if ( isdefined( self.zt_random_start_weapon ) )
        primary = self.zt_random_start_weapon;
    else if ( isdefined( level.zt.start_weapon_override ) )
        primary = level.zt.start_weapon_override;
    if ( ( mode == "primary" || mode == "both" ) && isdefined( primary ) )
    {
        self.zt_start_primary_weapon = self zt_upgrade_starting_slot( primary, "starting_weapon_upgraded" );
        self switchtoweapon( self.zt_start_primary_weapon );
    }
    if ( ( mode == "secondary" || mode == "both" ) && isdefined( level.zt.secondary_start_weapon_override ) )
        self.zt_start_secondary_weapon = self zt_upgrade_starting_slot( level.zt.secondary_start_weapon_override, "starting_weapon_upgraded" );
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
        maxstock = weaponmaxammo( weapon );
        maxclip = weaponclipsize( weapon );
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
    vending_triggers = getentarray( "zombie_vending", "targetname" );
    while ( ( vending_triggers.size <= 0 || !isdefined( self.num_perks ) ) && elapsed < 5 )
    {
        wait 0.05;
        elapsed += 0.05;
        vending_triggers = getentarray( "zombie_vending", "targetname" );
    }

    if ( vending_triggers.size <= 0 || !isdefined( self.num_perks ) )
    {
        zt_feature( feature, "unavailable", "map exposes no stock-compatible perk machines" );
        return;
    }

    granted = 0;
    while ( granted < count )
    {
        // Stock owns the complete map-available set through zombie_vending
        // triggers (ordinary and custom perks), plus paused/already-owned/PaP
        // exclusions. level._custom_perks alone contains only DLC additions.
        perk = self maps\mp\zombies\_zm_perks::give_random_perk();
        if ( !isdefined( perk ) )
            break;
        granted++;
    }

    if ( granted > 0 )
        zt_feature( feature, "active", "" );
    else
        zt_feature( feature, "unavailable", "player already owns every registered perk" );
}

zt_starting_grenade_weapon()
{
    choice = level.zt.config.starting_grenade;
    weapon = "";
    if ( choice == "frag" )
        weapon = "frag_grenade_zm";
    else if ( choice == "semtex" )
        weapon = "sticky_grenade_zm";
    if ( weapon != "" && isdefined( level.zombie_lethal_grenade_list ) && isdefined( level.zombie_lethal_grenade_list[weapon] ) )
        return weapon;
    return "";
}

zt_starting_equipment_weapon()
{
    choice = level.zt.config.starting_equipment;
    weapon = "";
    if ( choice == "monkey" )
        weapon = "cymbal_monkey_zm";
    else if ( choice == "emp" )
        weapon = "emp_grenade_zm";
    else if ( choice == "mine" )
    {
        weapon = "claymore_zm";
        if ( isdefined( level.zombie_placeable_mine_list ) && isdefined( level.zombie_placeable_mine_list[weapon] ) )
            return weapon;
        return "";
    }
    if ( weapon != "" && isdefined( level.zombie_tactical_grenade_list ) && isdefined( level.zombie_tactical_grenade_list[weapon] ) )
        return weapon;
    return "";
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
        if ( weapon == "" )
            zt_feature( "starting_grenade", "unavailable", "selected grenade is not registered by this map" );
        else
        {
            self maps\mp\zombies\_zm_weapons::weapon_give( weapon, 0, 0, 1 );
            zt_feature( "starting_grenade", "active", "" );
        }
    }

    if ( level.zt.config.starting_equipment != "default" )
    {
        weapon = zt_starting_equipment_weapon();
        if ( weapon == "" )
            zt_feature( "starting_equipment", "unavailable", "selected equipment is not registered by this map" );
        else
        {
            self maps\mp\zombies\_zm_weapons::weapon_give( weapon, 0, 0, 1 );
            zt_feature( "starting_equipment", "active", "" );
        }
    }

    // weapon_give publishes the active offhand slot asynchronously. Inventory
    // initialization owns the count after that stock assignment has settled.
    wait 0.05;
}

zt_player_watch()
{
    level endon( "end_game" );

    // Stock Zombies must finish connecting its initial players and release
    // round logic before we attach per-player listeners.  The spawn watcher
    // catches up already-playing clients, so no first-spawn tweak is lost.
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
                player thread zt_player_spawn_watch();
                if ( zt_character_preference_requested() )
                    player thread zt_character_preference_apply();
                if ( getdvarint( "zt_character_coop_probe" ) == 1 || zt_character_coop_apply_enabled() )
                    player thread zt_character_coop_probe_request();
                player thread zt_report_sync_player();
                player thread zt_player_role_watch();
                // Who's Who saves only the engine-visible offhand clips. Keep
                // ZTweaks' hidden overflow transactionally attached to the
                // original life while stock owns the temporary clone loadout.
                player thread zt_whos_who_inventory_watch();
            }
        }
        wait 0.5;
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
    level notify( "zt_character_preferences_applied", players, original, target );
}

// Stock routes or an explicit, validated map-owned roster declaration.
zt_character_postspawn_dvar( map_name, mode )
{
    if ( mode != "zclassic" )
        return "";
    // A malformed opt-in must not fall through to a stock-name guess.
    if ( isdefined( level.zt_character_adapter ) )
        return zt_character_custom_dvar();
    if ( map_name == "zm_transit" || map_name == "zm_highrise" || map_name == "zm_buried" )
        return "scr_zt_char_victis";
    if ( map_name == "zm_prison" )
        return "scr_zt_char_mob";
    if ( map_name == "zm_tomb" )
        return "scr_zt_char_origins";
    return "";
}

zt_character_preference_requested()
{
    preference_dvar = zt_character_postspawn_dvar( getdvar( "mapname" ), getdvar( "g_gametype" ) );
    if ( preference_dvar == "" )
        return 0;
    requested = getdvar( preference_dvar );
    return requested == "0" || requested == "1" || requested == "2" || requested == "3";
}

// Solo-only preference: let stock cast first, then ask the map's own callback
// to rebuild body, hands, voice and map-specific role/name fields. Multiplayer
// and RANDOM leave the original cast untouched; there is no late join claim.
zt_character_preference_apply()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    map_name = getdvar( "mapname" );
    mode = getdvar( "g_gametype" );
    preference_dvar = zt_character_postspawn_dvar( map_name, mode );
    if ( preference_dvar == "" )
        return;
    requested = getdvar( preference_dvar );
    if ( requested != "0" && requested != "1" && requested != "2" && requested != "3" )
        return;
    players = getplayers();
    if ( players.size != 1 || !zt_flag_is_set( "solo_game" ) || !isdefined( level.givecustomcharacters ) )
        return;
    callback = level.givecustomcharacters;
    stamp = zt_character_custom_stamp();
    if ( !zt_character_wait_identity_ready( players ) )
        return;
    if ( !zt_character_route_unchanged( map_name, mode, preference_dvar, stamp, callback ) ) return;
    players = getplayers();
    if ( !isdefined( self.characterindex ) || !isdefined( self.sessionstate ) || self.sessionstate != "playing" || players.size != 1 || !zt_flag_is_set( "solo_game" ) )
        return;
    original = zt_character_decode_index( self.characterindex );
    if ( original < 0 || original > 3 ) return;
    // Retain the validated match-start snapshot across any temporary-body wait.
    selected = int( requested );
    if ( original == selected )
    {
        if ( issubstr( zt_version(), ".d" ) )
            println( "ZT_CHAR_PREFERENCE|port=t6|map=" + map_name + "|result=already_selected|index=" + selected );
        return;
    }
    // TranZit, Die Rise, and Buried publish a role owner from their own
    // character callback. Clear only a reference to this player; the new
    // callback republishes it if the selected character owns that role.
    if ( !isdefined( level.zt_character_adapter ) && isdefined( level.rich_sq_player ) && level.rich_sq_player == self )
        level.rich_sq_player = undefined;
    // Die Rise sets this only on the initial random cast. Re-running its
    // callback with a defined index does not repair the story-presence flag.
    if ( !isdefined( level.zt_character_adapter ) && map_name == "zm_highrise" )
    {
        level.isstuhlingeringame = undefined;
        if ( selected == 1 )
            level.isstuhlingeringame = 1;
    }
    self.characterindex = zt_character_encode_index( selected );
    self zt_character_apply_identity();
    zt_character_refresh_presence( map_name );
    old_cast = []; new_cast = [];
    old_cast[0] = original; new_cast[0] = selected;
    zt_character_custom_applied( players, old_cast, new_cast );
    if ( issubstr( zt_version(), ".d" ) )
    {
        println( "ZT_CHAR_PREFERENCE|port=t6|map=" + map_name + "|result=applied|old=" + original + "|new=" + self.characterindex );
        self iprintlnbold( "ZT preferred character: " + original + " -> " + self.characterindex );
    }
}

zt_character_apply_identity()
{
    // Stock character callbacks also reset movement. A delayed co-op reply
    // must not discard a map/perk/ZTweaks speed already applied at spawn.
    movement = self getmovespeedscale();
    self [[ level.givecustomcharacters ]]();
    self setmovespeedscale( movement );
}

// The transport timeout does not authorize replacing a temporary map body.
// Wait only in our independent worker (never stock spawn), then fail closed.
zt_character_wait_identity_ready( players )
{
    callback = level.givecustomcharacters;
    stamp = zt_character_custom_stamp();
    if ( stamp == "" ) return 0;
    for ( attempt = 0; attempt < 240; attempt++ )
    {
        current = getplayers();
        if ( current.size != players.size || !isdefined( level.givecustomcharacters ) || level.givecustomcharacters != callback )
            return 0;
        if ( zt_character_custom_stamp() != stamp ) return 0;
        ready = 1;
        if ( isdefined( level.zt_character_adapter ) )
        {
            binding = zt_character_custom_binding();
            if ( !isdefined( binding ) ) return 0;
            ready = binding["ready"];
        }
        foreach ( player in players )
        {
            if ( !isdefined( player ) || !isplayer( player ) )
                return 0;
            present = 0;
            foreach ( member in current )
                if ( member == player ) present = 1;
            if ( !present ) return 0;
            if ( !isdefined( player.characterindex ) || !isdefined( player.sessionstate ) || player.sessionstate != "playing" || !isalive( player ) ||
                player maps\mp\zombies\_zm_laststand::player_is_in_laststand() || zt_true( player.afterlife ) || zt_true( player.zt_whos_who_inventory_frozen ) )
                ready = 0;
            if ( isdefined( player.zombie_vars ) && zt_true( player.zombie_vars["zombie_powerup_zombie_blood_on"] ) )
                ready = 0;
        }
        if ( ready ) return 1;
        wait 0.25;
    }
    if ( isdefined( players[0] ) )
        players[0] zt_notice( 1, "ZTweaks: character preferences skipped; a temporary player state remained active." );
    return 0;
}

zt_character_refresh_presence( map_name )
{
    if ( isdefined( level.zt_character_adapter ) ) return;
    has_role = 0;
    foreach ( player in getplayers() )
    {
        if ( !isdefined( player.characterindex ) ) continue;
        if ( ( map_name == "zm_prison" && player.characterindex == 3 ) ||
            ( map_name == "zm_tomb" && player.characterindex == 2 ) ||
            ( map_name == "zm_highrise" && player.characterindex == 1 ) )
            has_role = 1;
    }
    // Stock allocators normally set these only while choosing a fresh index.
    if ( map_name == "zm_prison" ) level.has_weasel = has_role;
    if ( map_name == "zm_tomb" ) level.has_richtofen = has_role;
    if ( map_name == "zm_highrise" )
    {
        level.isstuhlingeringame = undefined;
        if ( has_role ) level.isstuhlingeringame = 1;
    }
}

// Opt-in post-spawn transport check. This never changes characterindex.
// The old load-time client-dvar probe was retired after loading stalls;
// request only after stock round readiness and only in a co-op match.
zt_character_coop_probe_request()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    if ( zt_true( self.zt_character_coop_probe_started ) )
        return;
    players = getplayers();
    preference_dvar = zt_character_postspawn_dvar( getdvar( "mapname" ), getdvar( "g_gametype" ) );
    if ( players.size < 2 || preference_dvar == "" )
        return;
    self.zt_character_coop_probe_started = 1;
    self.zt_character_coop_probe_done = 0;
    self.zt_character_coop_probe_value = "NO_REPLY";
    self.zt_character_coop_probe_dvar = preference_dvar;
    self.zt_character_coop_probe_stamp = zt_character_custom_stamp();
    self thread zt_character_coop_probe_response( preference_dvar );
    wait 0.05;
    elapsed = 0;
    next_request = 0;
    requests = 0;
    while ( !self.zt_character_coop_probe_done && elapsed < 8 )
    {
        // The client may still be bringing up its mod/profile after the
        // stock round boundary. Retry only twice, well apart, instead of
        // treating one lost response as an absent preference.
        if ( elapsed >= next_request && requests < 3 )
        {
            self getClientDvar( preference_dvar );
            requests++;
            next_request += 2;
        }
        wait 0.1;
        elapsed += 0.1;
    }
    self notify( "zt_character_coop_probe_stop" );
    if ( !isdefined( self ) || !isplayer( self ) )
        return;
    host_text = "0";
    if ( self ishost() )
        host_text = "1";
    stock_index = "UNSET";
    if ( isdefined( self.characterindex ) )
        stock_index = "" + self.characterindex;
    println( "ZT_CHAR_COOP|port=t6|event=transport|player=" + self.name + "|host=" + host_text + "|dvar=" + preference_dvar + "|value=" + self.zt_character_coop_probe_value + "|ms=" + int( elapsed * 1000 ) + "|stock_index=" + stock_index );
}

zt_character_coop_probe_response( expected_dvar )
{
    self endon( "disconnect" );
    self endon( "zt_character_coop_probe_stop" );
    level endon( "end_game" );
    while ( 1 )
    {
        self waittill( "get_client_dvar_response", name, value );
        if ( name != expected_dvar )
            continue;
        if ( value == "-1" || value == "0" || value == "1" || value == "2" || value == "3" )
            self.zt_character_coop_probe_value = value;
        else
            self.zt_character_coop_probe_value = "INVALID";
        self.zt_character_coop_probe_done = 1;
        return;
    }
}

// Enabled in public and development builds, with an explicit host escape hatch.
// The regular solo path is unchanged, and zt_character_coop_probe remains
// read-only when zt_character_coop_apply is set to 0.
zt_character_coop_apply_enabled()
{
    return getdvar( "zt_character_coop_apply" ) != "0";
}

// Reconcile a complete post-spawn cast, not individual players. This keeps
// every character index unique and retains map-required story characters.
// Missing/invalid client replies are RANDOM; unsupported maps stay stock.
zt_character_coop_assign()
{
    level endon( "end_game" );
    if ( zt_true( level.zt_character_coop_assign_started ) )
        return;
    level.zt_character_coop_assign_started = 1;
    map_name = getdvar( "mapname" );
    mode = getdvar( "g_gametype" );
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
            // A disconnect terminates the player's request thread, not this
            // level-owned transaction. Never dereference the stale snapshot.
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
    else if ( map_name == "zm_prison" )
        required = 3;
    else if ( map_name == "zm_tomb" )
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
    // A RANDOM player keeps their stock identity whenever the slot remains
    // available. Only a displaced player draws from the unused stock roster.
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
    changes = 0;
    for ( i = 0; i < players.size; i++ )
    {
        if ( target[i] == original[i] )
            continue;
        changes++;
        if ( !isdefined( level.zt_character_adapter ) && isdefined( level.rich_sq_player ) && level.rich_sq_player == players[i] )
            level.rich_sq_player = undefined;
    }
    if ( changes == 0 )
        return;
    if ( !isdefined( level.zt_character_adapter ) && map_name == "zm_highrise" )
    {
        level.isstuhlingeringame = undefined;
        for ( i = 0; i < players.size; i++ )
        {
            if ( target[i] == 1 )
                level.isstuhlingeringame = 1;
        }
    }
    for ( i = 0; i < players.size; i++ )
        players[i].characterindex = zt_character_encode_index( target[i] );
    for ( i = 0; i < players.size; i++ )
    {
        if ( target[i] == original[i] )
            continue;
        player = players[i];
        player zt_character_apply_identity();
        host_text = "0";
        if ( player ishost() )
            host_text = "1";
        println( "ZT_CHAR_COOP|port=t6|event=assigned|player=" + player.name + "|host=" + host_text + "|old=" + original[i] + "|new=" + target[i] + "|wanted=" + preference[i] );
    }
    zt_character_refresh_presence( map_name );
    zt_character_custom_applied( players, original, target );
}

zt_player_spawn_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    // Keep the per-player transaction in lock-step with T7. Some maps expose
    // a playing sessionstate while their intro still owns the player; changing
    // inventory, perks, health, or movement at that point can deadlock stock
    // startup. The round-logic flag is the common authoritative boundary.
    while ( !zt_game_ready() )
        wait 0.1;

    if ( isdefined( self.sessionstate ) && self.sessionstate == "playing" )
    {
        self zt_inventory_begin_generation();
        self.zt_point_gain_baseline_pending = 1;
        wait 0.4;
        if ( isdefined( self.sessionstate ) && self.sessionstate == "playing" )
        {
            self zt_apply_spawn_inventory();
            self zt_point_gain_rebaseline();
        }
    }

    while ( 1 )
    {
        self waittill( "spawned_player" );
        // Invalidate delayed grenade_fire releases at the spawn boundary,
        // before the stock offhand pipeline is allowed to settle.
        self zt_inventory_begin_generation();
        // Starting points and map-authored respawn restoration are baselines,
        // not score awards. Suppress the frame sampler until the complete
        // spawn transaction has settled.
        self.zt_point_gain_baseline_pending = 1;

        // Buried's Time Bomb respawns saved spectators through level.spawnplayer,
        // then restores the captured loadout asynchronously.  Treat that as a
        // rewind transaction rather than a new life: starting weapons, perks,
        // ammo and offhands must not overwrite the saved snapshot.
        if ( zt_time_bomb_restore_active() )
        {
            level waittill( "time_bomb_detonation_complete" );
            wait 0.05;
            zt_refresh_spawn_config();
            if ( self zt_player_tweaks_allowed() )
            {
                self zt_apply_player_health( 1 );
                self zt_apply_player_speed();
            }
            self zt_point_gain_rebaseline();
            continue;
        }

        wait 0.4;
        self zt_apply_spawn_inventory();
        self zt_point_gain_rebaseline();
    }
}

zt_time_bomb_restore_active()
{
    return isdefined( level.flag ) && isdefined( level.flag["time_bomb_restore_active"] ) && level.flag["time_bomb_restore_active"];
}

zt_player_role_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    while ( 1 )
    {
        event = self waittill_any_return( "zombify", "humanify" );
        wait 0.05;
        if ( event == "zombify" )
        {
            self zt_release_spawn_ownership();
            continue;
        }

        // Turned emits humanify before its stock human loadout transaction and
        // never emits spawned_player afterwards.  Wait for that transaction to
        // finish, then apply the same human-only spawn boundary exactly once.
        while ( isdefined( self.is_in_process_of_humanify ) && self.is_in_process_of_humanify )
            wait 0.05;
        wait 0.1;
        if ( self zt_player_tweaks_allowed() && isdefined( self.sessionstate ) && self.sessionstate == "playing" )
        {
            self zt_inventory_begin_generation();
            self.zt_point_gain_baseline_pending = 1;
            self zt_apply_spawn_inventory();
            self zt_point_gain_rebaseline();
        }
    }
}

zt_player_tweaks_allowed()
{
    if ( isdefined( self.is_in_process_of_zombify ) && self.is_in_process_of_zombify )
        return 0;
    if ( isdefined( level.is_zombie_level ) && level.is_zombie_level )
    {
        // Turned publishes the role explicitly. Before that role exists, fail
        // closed rather than granting a human loadout to a player-zombie.
        if ( !isdefined( self.is_zombie ) || self.is_zombie )
            return 0;
    }
    return 1;
}

zt_release_spawn_ownership()
{
    if ( zt_true( self.zt_player_health_perk_watch ) ) self notify( "zt_stop_player_health_perk_watch" );
    if ( zt_true( self.zt_player_speed_watch ) ) self notify( "zt_stop_player_speed_watch" );
    if ( zt_true( self.zt_inventory_cap_watch ) ) self notify( "zt_stop_inventory_cap_watch" );
    if ( zt_true( self.zt_max_ammo_watch ) ) self notify( "zt_stop_max_ammo_watch" );
    if ( zt_true( self.zt_grenade_round_refill_watch ) ) self notify( "zt_stop_grenade_round_refill_watch" );
    self.zt_player_health_perk_watch = 0;
    self.zt_player_speed_watch = 0;
    self.zt_inventory_cap_watch = 0;
    self.zt_max_ammo_watch = 0;
    self.zt_grenade_round_refill_watch = 0;
    self.zt_player_health_owned = 0;
    self.zt_player_health_bonus = undefined;
    self.zt_player_health_applied_max = undefined;
    self.zt_player_speed_owned = 0;
    self.zt_player_speed_base = undefined;
    self.zt_player_speed_applied = undefined;
    self.zt_player_speed_restore_base = undefined;
    self.zt_player_speed_restore_applied = undefined;
    self.zt_lethal_reserve = 0;
    self.zt_tactical_reserve = 0;
    self.zt_placeable_reserve = 0;
    self.zt_lethal_throw_active = 0;
    self.zt_tactical_throw_active = 0;
    self.zt_placeable_throw_active = 0;
    self.zt_whos_who_inventory_frozen = 0;
    self.zt_whos_who_inventory_snapshot = undefined;
    self.zt_spawn_protection_until = undefined;
}

zt_inventory_begin_generation()
{
    if ( !isdefined( self.zt_inventory_generation ) )
        self.zt_inventory_generation = 0;
    self.zt_inventory_generation++;
    self.zt_lethal_throw_active = 0;
    self.zt_tactical_throw_active = 0;
    self.zt_placeable_throw_active = 0;
    self.zt_whos_who_inventory_frozen = 0;
    self.zt_whos_who_inventory_snapshot = undefined;
}

zt_apply_spawn_inventory()
{
    zt_refresh_spawn_config();
    if ( !self zt_player_tweaks_allowed() )
    {
        self zt_release_spawn_ownership();
        return;
    }
    self zt_apply_player_health();

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
    self zt_apply_starting_ammo();
    self zt_apply_starting_throwables();
    self zt_apply_random_starting_perks();
    if ( level.zt.config.spawn_protection > 0 && zt_true( level.zt_player_damage_installed ) )
    {
        self.zt_spawn_protection_until = gettime() + level.zt.config.spawn_protection * 1000;
        zt_feature( "spawn_protection", "active", "" );
    }
    else if ( level.zt.config.spawn_protection > 0 )
    {
        self.zt_spawn_protection_until = undefined;
        zt_feature( "spawn_protection", "unavailable", "map exposes no composable player-damage override" );
    }
    else
        self.zt_spawn_protection_until = undefined;
    self zt_apply_player_speed();
    inventory_enabled = level.zt.config.max_grenades > 0 || level.zt.config.max_equipment > 0 || level.zt.config.starting_grenade_count > 0 || level.zt.config.starting_equipment_count > 0;
    max_enabled = level.zt.config.max_grenades > 0 || level.zt.config.max_equipment > 0 || level.zt.config.max_ammo_reload > 0;
    if ( !inventory_enabled && zt_true( self.zt_inventory_cap_watch ) )
    {
        self notify( "zt_stop_inventory_cap_watch" );
        self.zt_inventory_cap_watch = 0;
    }
    if ( inventory_enabled && !zt_true( self.zt_inventory_cap_watch ) )
    {
        self.zt_inventory_cap_watch = 1;
        self thread zt_inventory_cap_watch();
    }

    if ( !max_enabled && zt_true( self.zt_max_ammo_watch ) )
    {
        self notify( "zt_stop_max_ammo_watch" );
        self.zt_max_ammo_watch = 0;
    }
    if ( max_enabled && !zt_true( self.zt_max_ammo_watch ) )
    {
        self.zt_max_ammo_watch = 1;
        self thread zt_max_ammo_watch();
    }

    if ( level.zt.config.max_grenades <= 0 && zt_true( self.zt_grenade_round_refill_watch ) )
    {
        self notify( "zt_stop_grenade_round_refill_watch" );
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

zt_apply_player_health( preserve_current )
{
    if ( level.zt.config.player_health <= 0 && !zt_true( self.zt_player_health_owned ) )
        return;

    // Mob's final showdown assigns Weasel a map-owned 2000-health multiple
    // after changing his team. It is neither ordinary base health nor a perk
    // bonus, and must not be folded into the configured player-health scale.
    if ( self zt_mob_final_showdown_health_owned() )
    {
        self.zt_player_health_owned = 0;
        self.zt_player_health_bonus = undefined;
        self.zt_player_health_applied_max = undefined;
        if ( !zt_true( self.zt_player_health_final_showdown ) )
        {
            self.zt_player_health_final_showdown = 1;
            zt_feature( "player_health", "degraded", "Mob final-showdown health remains map-owned" );
        }
        return;
    }
    self.zt_player_health_final_showdown = 0;

    if ( level.zt.config.player_health > 0 && !zt_true( self.zt_player_health_perk_watch ) )
    {
        self.zt_player_health_perk_watch = 1;
        self thread zt_player_health_perk_watch();
    }

    health_was_owned = zt_true( self.zt_player_health_owned );
    current_max = self.maxhealth;
    current_health = self.health;
    health = zt_player_health_target();
    if ( health > 0 && ( level.zt.config.player_health > 0 || health_was_owned ) )
    {
        bonus = self zt_player_health_stock_bonus( current_max );
        composed = health + bonus;
        self.maxhealth = composed;
        self setmaxhealth( composed );
        if ( zt_true( preserve_current ) )
        {
            if ( current_health > composed ) current_health = composed;
            self.health = current_health;
        }
        else
            self.health = composed;
        self.zt_player_health_bonus = bonus;
        self.zt_player_health_applied_max = composed;
    }
    self.zt_player_health_owned = level.zt.config.player_health > 0;

    if ( level.zt.config.player_health <= 0 && zt_true( self.zt_player_health_perk_watch ) )
    {
        self notify( "zt_stop_player_health_perk_watch" );
        self.zt_player_health_perk_watch = 0;
        self.zt_player_health_bonus = undefined;
        self.zt_player_health_applied_max = undefined;
    }
}

zt_player_health_stock_bonus( current_max )
{
    if ( isdefined( self.zt_player_health_applied_max ) && current_max == self.zt_player_health_applied_max && isdefined( self.zt_player_health_bonus ) )
        return self.zt_player_health_bonus;

    stock_base = 100;
    if ( isdefined( level.zt.player_base_health_stock ) )
        stock_base = level.zt.player_base_health_stock;

    stock_total = stock_base;
    if ( self hasperk( "specialty_armorvest_upgrade" ) && isdefined( level.zombie_vars["zombie_perk_juggernaut_health_upgrade"] ) )
        stock_total = level.zombie_vars["zombie_perk_juggernaut_health_upgrade"];
    else if ( self hasperk( "specialty_armorvest" ) && isdefined( level.zombie_vars["zombie_perk_juggernaut_health"] ) )
        stock_total = level.zombie_vars["zombie_perk_juggernaut_health"];

    bonus = stock_total - stock_base;
    if ( bonus < 0 )
        bonus = 0;

    // Persistent upgrades and map-authored health bonuses are layered on top
    // of BO2's absolute Juggernog totals. Preserve any positive remainder.
    if ( current_max > stock_total )
        bonus = bonus + current_max - stock_total;

    return bonus;
}

zt_mob_final_showdown_health_owned()
{
    return zt_map_script() == "zm_prison" && isdefined( level.final_flight_activated ) && level.final_flight_activated;
}

zt_player_health_perk_watch()
{
    self endon( "disconnect" );
    self endon( "zt_stop_player_health_perk_watch" );

    while ( 1 )
    {
        // Stock can rewrite the absolute maximum without perk notifications:
        // EMP pause/unpause, Mob Afterlife exit and Who's Who restoration all
        // use health_reboot directly.  Poll the published maximum while this
        // setting owns it so those late stock writes are composed immediately.
        wait 0.1;

        if ( !self zt_player_tweaks_allowed() )
        {
            self zt_release_spawn_ownership();
            return;
        }

        // Mob's Afterlife temporarily raises health to 1000 while the ghost
        // transaction owns the player.  Preserve that state; the same watcher
        // will recompose the stock health_reboot value after Afterlife clears.
        if ( isdefined( self.afterlife ) && self.afterlife )
            continue;

        if ( self zt_mob_final_showdown_health_owned() )
        {
            self.zt_player_health_owned = 0;
            self.zt_player_health_bonus = undefined;
            self.zt_player_health_applied_max = undefined;
            if ( !zt_true( self.zt_player_health_final_showdown ) )
            {
                self.zt_player_health_final_showdown = 1;
                zt_feature( "player_health", "degraded", "Mob final-showdown health remains map-owned" );
            }
            continue;
        }
        self.zt_player_health_final_showdown = 0;

        if ( level.zt.config.player_health > 0 || zt_true( self.zt_player_health_owned ) )
            // Stock Juggernog changes maximum health without granting a free
            // heal. Recompose the maximum while preserving current damage.
            self zt_apply_player_health( 1 );
    }
}

zt_apply_player_speed()
{
    current = self getmovespeedscale();
    if ( level.zt.config.player_speed > 0 )
    {
        route_base = self zt_stock_player_speed_route_base();
        if ( isdefined( route_base ) )
        {
            // TranZit's Denizen and Buried's ghosts publish absolute .5/1
            // values every frame.  Their route state, not equality against our
            // own output, is the authoritative native scale.
            self.zt_player_speed_base = route_base;
            self.zt_player_speed_restore_applied = undefined;
            self.zt_player_speed_restore_base = undefined;
        }
        else if ( zt_true( self.zt_player_speed_owned ) && isdefined( self.zt_player_speed_applied ) && current != self.zt_player_speed_applied )
        {
            // Map traps/effects commonly save our published value, install a
            // temporary absolute scale, then restore the saved value. Treat
            // that restoration as a return to our earlier native base rather
            // than multiplying the tweak into itself. Keep one root restore
            // point while a map moves through several temporary scales.
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
                // BO2 game-variant actions may derive a new scale by
                // multiplying our live value. That result already contains
                // the ZTweaks factor, so recover its native component first.
                if ( isdefined( self.movementspeedmodifier ) && abs( current - self.movementspeedmodifier ) < 0.001 )
                    self.zt_player_speed_base = current * 100.0 / level.zt.config.player_speed;
                else
                    self.zt_player_speed_base = current;
            }
        }
        else if ( !isdefined( route_base ) && ( !zt_true( self.zt_player_speed_owned ) || !isdefined( self.zt_player_speed_applied ) ) )
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
            self notify( "zt_stop_player_speed_watch" );
            self.zt_player_speed_watch = 0;
        }
    }
}

zt_stock_player_speed_route_base()
{
    script = getdvar( "mapname" );
    if ( isdefined( level.script ) )
        script = tolower( level.script );

    if ( script == "zm_transit" )
    {
        if ( isdefined( self.screecher ) && isdefined( self.screecher.linked_ent ) && self.screecher.linked_ent == self && isalive( self.screecher ) )
            return 0.5;
        return 1.0;
    }

    if ( script == "zm_buried" )
    {
        if ( self maps\mp\zombies\_zm_laststand::player_is_in_laststand() )
            return 1.0;
        if ( isdefined( level.zombie_ghost_round_states ) && isdefined( level.zombie_ghost_round_states.is_started ) && level.zombie_ghost_round_states.is_started )
        {
            ghosts = getaiarray( level.zombie_team );
            foreach ( ghost in ghosts )
                if ( isdefined( ghost.is_ghost ) && ghost.is_ghost && !( isdefined( ghost.force_killable ) && ghost.force_killable ) && distancesquared( ghost.origin, self.origin ) < 60 * 60 )
                    return 0.5;
        }
        return 1.0;
    }

    return undefined;
}

zt_player_speed_owner_watch()
{
    self endon( "disconnect" );
    self endon( "zt_stop_player_speed_watch" );
    level endon( "end_game" );
    while ( 1 )
    {
        // Buried's ghost worker publishes its absolute .5/1 route scale on
        // the same 0.1-second cadence. Reassert at the frame boundary while
        // that route owns movement so the composed value wins after stock.
        if ( zt_buried_ghost_speed_route_active() )
            waittillframeend;
        else
            wait 0.1;
        self zt_apply_player_speed();
    }
}

zt_buried_ghost_speed_route_active()
{
    return zt_map_script() == "zm_buried" && isdefined( level.zombie_ghost_round_states ) && isdefined( level.zombie_ghost_round_states.is_started ) && level.zombie_ghost_round_states.is_started;
}

zt_player_health_target()
{
    // BO2 does not publish player_base_health on any stock Zombies route.
    // _zm_playerhealth delegates each spawn to perk_set_max_health_if_jugg,
    // whose unperked absolute base is 100.  Retain support for custom maps
    // which do publish the BO3-style variable, but use the proven BO2 base
    // otherwise and let zt_player_health_stock_bonus preserve Juggernog,
    // persistent-upgrade, and map-authored additions on each player.
    shared_base = isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["player_base_health"] );
    if ( !shared_base && !zt_stock_bo2_health_route() )
    {
        if ( level.zt.config.player_health > 0 )
            zt_feature( "player_health", "unavailable", "custom map exposes no authoritative base player-health variable" );
        return 0;
    }
    if ( shared_base )
    {
        current = level.zombie_vars["player_base_health"];
        if ( !zt_true( level.zt.player_health_uses_shared_base ) )
        {
            level.zt.player_base_health_stock = current;
            level.zt.player_health_uses_shared_base = 1;
        }
        else if ( zt_true( level.zt.player_health_owned ) && isdefined( level.zt.player_base_health_applied ) && current != level.zt.player_base_health_applied )
        {
            level.zt.player_base_health_stock = current;
            level.zt.player_health_owned = 0;
        }
    }
    else if ( !isdefined( level.zt.player_base_health_stock ) || zt_true( level.zt.player_health_uses_shared_base ) )
    {
        level.zt.player_base_health_stock = 100;
        level.zt.player_health_uses_shared_base = 0;
    }

    health = level.zt.player_base_health_stock;
    if ( level.zt.config.player_health > 0 )
    {
        health = int( level.zt.player_base_health_stock * level.zt.config.player_health / 100 );
        if ( health < 1 )
            health = 1;
        if ( shared_base )
        {
            level.zombie_vars["player_base_health"] = health;
            level.zt.player_base_health_applied = health;
        }
        else
            level.zt.player_base_health_applied = undefined;
        level.zt.player_health_owned = 1;
        zt_feature( "player_health", "active", "scaled from BO2's stock base and composed with perk/map health bonuses" );
    }
    else if ( zt_true( level.zt.player_health_owned ) )
    {
        if ( shared_base && ( !isdefined( level.zt.player_base_health_applied ) || current == level.zt.player_base_health_applied ) )
            level.zombie_vars["player_base_health"] = health;
        level.zt.player_health_owned = 0;
        level.zt.player_base_health_applied = undefined;
        zt_feature( "player_health", "inherit", "" );
    }

    return health;
}

zt_stock_bo2_health_route()
{
    script = getdvar( "mapname" );
    if ( isdefined( level.script ) )
        script = tolower( level.script );
    return script == "zm_transit" || script == "zm_transit_dr" || script == "zm_nuked" || script == "zm_highrise" || script == "zm_prison" || script == "zm_buried" || script == "zm_tomb";
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
    level endon( "end_game" );

    // Never race the pre-round initializer. Player Health may be enabled
    // later at NEXT SPAWN, while zombie curves remain gated by the successful
    // NEXT MATCH claim above.
    while ( !zt_game_ready() )
        wait 0.05;

    while ( 1 )
    {
        wait 0.25;

        if ( level.zt.config.player_health > 0 )
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

zt_inventory_cap_watch()
{
    self endon( "disconnect" );
    self endon( "zt_stop_inventory_cap_watch" );
    level endon( "end_game" );

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

zt_whos_who_inventory_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    while ( 1 )
    {
        self waittill( "fake_death" );
        if ( !self zt_whos_who_inventory_transaction() )
            continue;

        snapshot = spawnstruct();
        snapshot.generation = 0;
        snapshot.lethal_reserve = 0;
        snapshot.tactical_reserve = 0;
        snapshot.placeable_reserve = 0;
        snapshot.lethal = "";
        snapshot.tactical = "";
        snapshot.placeable = "";
        snapshot.corpse_seen = 0;
        snapshot.bleedout = 0;
        if ( isdefined( self.zt_inventory_generation ) ) snapshot.generation = self.zt_inventory_generation;
        if ( isdefined( self.zt_lethal_reserve ) ) snapshot.lethal_reserve = self.zt_lethal_reserve;
        if ( isdefined( self.zt_tactical_reserve ) ) snapshot.tactical_reserve = self.zt_tactical_reserve;
        if ( isdefined( self.zt_placeable_reserve ) ) snapshot.placeable_reserve = self.zt_placeable_reserve;
        if ( isdefined( self.zt_last_lethal ) ) snapshot.lethal = self.zt_last_lethal;
        if ( isdefined( self.zt_last_tactical ) ) snapshot.tactical = self.zt_last_tactical;
        if ( isdefined( self.zt_last_placeable ) ) snapshot.placeable = self.zt_last_placeable;

        self.zt_whos_who_inventory_snapshot = snapshot;
        self.zt_whos_who_inventory_frozen = 1;
        self.zt_lethal_throw_active = 0;
        self.zt_tactical_throw_active = 0;
        self.zt_placeable_throw_active = 0;

        // Stock publishes the same cleanup event for a restored corpse, a
        // rejected corpse and a corpse which bled out. Track the transaction
        // itself so identical clone/original offhand slots cannot make a
        // rejected or dead temporary life look restored.
        self thread zt_whos_who_corpse_watch( snapshot );
        self thread zt_whos_who_bleedout_watch( snapshot );

        // Stock restores the original visible clips before publishing this
        // cleanup boundary. Bleed-out and rejected-corpse paths publish the
        // same event without restoring the original slots, so verify them.
        self waittill( "chugabud_effects_cleanup" );
        // Stock keeps a real corpse defined for one final 0.1-second cleanup
        // window after this notify. Sample synchronously as well as polling so
        // an unusually fast revive cannot fall between observer frames.
        if ( isdefined( self.e_chugabud_corpse ) )
            snapshot.corpse_seen = 1;
        wait 0.15;

        restored = self zt_whos_who_original_inventory_restored( snapshot );
        self notify( "zt_whos_who_inventory_outcome_complete" );
        self.zt_whos_who_inventory_frozen = 0;
        if ( restored )
        {
            self.zt_lethal_reserve = snapshot.lethal_reserve;
            self.zt_tactical_reserve = snapshot.tactical_reserve;
            self.zt_placeable_reserve = snapshot.placeable_reserve;
            if ( snapshot.lethal != "" ) self.zt_last_lethal = snapshot.lethal;
            if ( snapshot.tactical != "" ) self.zt_last_tactical = snapshot.tactical;
            if ( snapshot.placeable != "" ) self.zt_last_placeable = snapshot.placeable;
            self zt_clamp_inventory();
        }
        else
        {
            // The original life was not restored. Never leak its hidden
            // overflow into the temporary clone or a later spawn.
            self.zt_lethal_reserve = 0;
            self.zt_tactical_reserve = 0;
            self.zt_placeable_reserve = 0;
            self.zt_last_lethal = undefined;
            self.zt_last_tactical = undefined;
            self.zt_last_placeable = undefined;
        }
        self.zt_whos_who_inventory_snapshot = undefined;
    }
}

zt_whos_who_corpse_watch( snapshot )
{
    self endon( "disconnect" );
    self endon( "chugabud_effects_cleanup" );
    self endon( "zt_whos_who_inventory_outcome_complete" );
    level endon( "end_game" );

    while ( 1 )
    {
        if ( isdefined( self.e_chugabud_corpse ) )
            snapshot.corpse_seen = 1;
        wait 0.05;
    }
}

zt_whos_who_bleedout_watch( snapshot )
{
    self endon( "disconnect" );
    self endon( "zt_whos_who_inventory_outcome_complete" );
    level endon( "end_game" );

    self waittill( "chugabud_bleedout" );
    snapshot.bleedout = 1;
}

zt_whos_who_inventory_transaction()
{
    return isdefined( level.zombiemode_using_chugabud_perk ) && level.zombiemode_using_chugabud_perk && isdefined( self.loadout ) && isdefined( self.loadout.player ) && self.loadout.player == self && zt_true( self.hasperkspecialtychugabud );
}

zt_whos_who_original_inventory_restored( snapshot )
{
    if ( !isdefined( snapshot ) || !isdefined( self.zt_inventory_generation ) || self.zt_inventory_generation != snapshot.generation )
        return false;
    if ( !zt_true( snapshot.corpse_seen ) || zt_true( snapshot.bleedout ) )
        return false;
    if ( !isdefined( self.sessionstate ) || self.sessionstate != "playing" || self maps\mp\zombies\_zm_laststand::player_is_in_laststand() )
        return false;
    if ( snapshot.lethal != "" && ( !isdefined( self.current_lethal_grenade ) || self.current_lethal_grenade != snapshot.lethal ) )
        return false;
    if ( snapshot.tactical != "" && ( !isdefined( self.current_tactical_grenade ) || self.current_tactical_grenade != snapshot.tactical ) )
        return false;
    if ( snapshot.placeable != "" && ( !isdefined( self.current_placeable_mine ) || self.current_placeable_mine != snapshot.placeable ) )
        return false;
    return true;
}

zt_inventory_throw_watch()
{
    self endon( "disconnect" );
    self endon( "zt_stop_inventory_cap_watch" );
    level endon( "end_game" );

    if ( !isdefined( self.zt_lethal_reserve ) )
        self.zt_lethal_reserve = 0;
    if ( !isdefined( self.zt_tactical_reserve ) )
        self.zt_tactical_reserve = 0;
    if ( !isdefined( self.zt_placeable_reserve ) )
        self.zt_placeable_reserve = 0;

    while ( 1 )
    {
        self waittill( "grenade_fire", grenade, weapon );
        if ( zt_true( self.zt_whos_who_inventory_frozen ) )
            continue;
        // Capture the slot and hidden reserve at the notification boundary.
        // The engine can clear current_* when the visible last item is thrown,
        // and the cap poller may observe that transient empty slot before the
        // offhand animation completes.
        was_lethal = zt_safe_lethal_inventory_weapon( weapon ) && ( weapon == self.current_lethal_grenade || ( isdefined( self.zt_last_lethal ) && weapon == self.zt_last_lethal ) );
        was_tactical = zt_safe_tactical_inventory_weapon( weapon ) && ( weapon == self.current_tactical_grenade || ( isdefined( self.zt_last_tactical ) && weapon == self.zt_last_tactical ) );
        was_placeable = zt_safe_placeable_inventory_weapon( weapon ) && ( weapon == self.current_placeable_mine || ( isdefined( self.zt_last_placeable ) && weapon == self.zt_last_placeable ) );
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
        // Let the engine finish its ammo transaction and offhand animation
        // before exposing one reserve item. Same-frame writes can be consumed
        // as part of the throw that produced this notification.
        wait 0.35;

        // A delayed throw from the prior life must not grant inventory into a
        // newly initialized spawn.
        if ( !isdefined( self.zt_inventory_generation ) || self.zt_inventory_generation != generation || zt_true( self.zt_whos_who_inventory_frozen ) )
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
    self endon( "disconnect" );
    self endon( "zt_stop_grenade_round_refill_watch" );
    level endon( "end_game" );

    while ( 1 )
    {
        level waittill( "start_of_round" );
        wait 0.25;
        if ( zt_true( self.zt_whos_who_inventory_frozen ) )
            continue;
        while ( zt_true( self.zt_lethal_throw_active ) ) wait 0.05;
        // Stock does not award round-start grenades in Headshots Only. Keep
        // the configured cap compositional instead of restoring an inventory
        // source that the active mode deliberately suppresses.
        if ( level.zt.config.max_grenades > 0 && zt_safe_lethal_inventory_weapon( self.current_lethal_grenade ) && zt_stock_max_ammo_allows( self.current_lethal_grenade, 1 ) )
            self.zt_lethal_reserve = self zt_set_clip_inventory( self.current_lethal_grenade, level.zt.config.max_grenades );
    }
}

zt_max_ammo_watch()
{
    self endon( "disconnect" );
    self endon( "zt_stop_max_ammo_watch" );
    level endon( "end_game" );

    while ( 1 )
    {
        self waittill( "zmb_max_ammo" );
        // Snapshot the exact stock slots at the notification boundary. Map
        // scripts can exchange quest offhands while Max Ammo is still
        // running; never refill a replacement that was not part of this
        // pickup.
        lethal = self.current_lethal_grenade;
        tactical = self.current_tactical_grenade;
        placeable = self.current_placeable_mine;
        primaries = [];
        if ( level.zt.config.max_ammo_reload > 0 )
            primaries = self getweaponslistprimaries();
        // Stock sends the notification before it finishes givemaxammo.
        wait 0.1;

        if ( zt_true( self.zt_whos_who_inventory_frozen ) )
            continue;

        if ( level.zt.config.max_ammo_reload > 0 && self zt_player_tweaks_allowed() )
        {
            reloaded = 0;
            for ( i = 0; i < primaries.size; i++ )
            {
                weapon = primaries[i];
                if ( !zt_stock_max_ammo_allows( weapon, 0 ) || !self hasweapon( weapon ) )
                    continue;
                clip = weaponclipsize( weapon );
                if ( clip <= 0 )
                    continue;
                self setweaponammoclip( weapon, clip );
                reloaded++;
            }
            if ( reloaded > 0 )
                zt_feature( "max_ammo_reload", "active", "" );
        }

        while ( zt_true( self.zt_lethal_throw_active ) || zt_true( self.zt_tactical_throw_active ) || zt_true( self.zt_placeable_throw_active ) ) wait 0.05;

        if ( level.zt.config.max_grenades > 0 && zt_safe_lethal_inventory_weapon( lethal ) && lethal == self.current_lethal_grenade && self hasweapon( lethal ) && zt_stock_max_ammo_allows( lethal, 1 ) )
            self.zt_lethal_reserve = self zt_set_clip_inventory( lethal, level.zt.config.max_grenades );

        if ( level.zt.config.max_equipment > 0 )
        {
            if ( zt_safe_tactical_inventory_weapon( tactical ) && tactical == self.current_tactical_grenade && self hasweapon( tactical ) && zt_stock_max_ammo_allows( tactical, 0 ) )
                self.zt_tactical_reserve = self zt_set_clip_inventory( tactical, level.zt.config.max_equipment );
            if ( zt_safe_placeable_inventory_weapon( placeable ) && placeable == self.current_placeable_mine && self hasweapon( placeable ) && zt_stock_max_ammo_allows( placeable, 0 ) )
                self.zt_placeable_reserve = self zt_set_total_inventory( placeable, level.zt.config.max_equipment );
        }
    }
}

zt_initialize_inventory()
{
    if ( ( level.zt.config.starting_grenade_count > 0 || level.zt.config.max_grenades > 0 ) && zt_safe_lethal_inventory_weapon( self.current_lethal_grenade ) )
    {
        amount = zt_spawn_count( level.zt.config.starting_grenade_count, level.zt.config.max_grenades );
        self.zt_lethal_reserve = self zt_set_clip_inventory( self.current_lethal_grenade, amount );
        self.zt_last_lethal = self.current_lethal_grenade;
    }

    if ( level.zt.config.starting_equipment_count <= 0 && level.zt.config.max_equipment <= 0 )
        return;

    restrict_slot = level.zt.config.starting_equipment != "default";
    selected_equipment = zt_starting_equipment_weapon();

    if ( zt_safe_tactical_inventory_weapon( self.current_tactical_grenade ) && ( !restrict_slot || ( isdefined( selected_equipment ) && self.current_tactical_grenade == selected_equipment ) ) )
    {
        amount = zt_spawn_count( level.zt.config.starting_equipment_count, level.zt.config.max_equipment );
        self.zt_tactical_reserve = self zt_set_clip_inventory( self.current_tactical_grenade, amount );
        self.zt_last_tactical = self.current_tactical_grenade;
    }
    if ( zt_safe_placeable_inventory_weapon( self.current_placeable_mine ) && ( !restrict_slot || ( isdefined( selected_equipment ) && self.current_placeable_mine == selected_equipment ) ) )
    {
        amount = zt_spawn_count( level.zt.config.starting_equipment_count, level.zt.config.max_equipment );
        self.zt_placeable_reserve = self zt_set_total_inventory( self.current_placeable_mine, amount );
        self.zt_last_placeable = self.current_placeable_mine;
    }
}

zt_valid_inventory_weapon( weapon )
{
    return isdefined( weapon ) && weapon != "";
}

zt_inventory_weapon_excluded( weapon )
{
    if ( !zt_valid_inventory_weapon( weapon ) )
        return true;
    if ( isdefined( level.zombie_weapons_no_max_ammo ) && isdefined( level.zombie_weapons_no_max_ammo[weapon] ) )
        return true;
    if ( isdefined( level.limited_weapons ) && isdefined( level.limited_weapons[weapon] ) )
        return true;
    return weapon == "time_bomb_zm" || weapon == "time_bomb_detonator_zm" || weapon == "bouncing_tomahawk_zm" || weapon == "upgraded_tomahawk_zm" || weapon == "beacon_zm";
}

zt_safe_lethal_inventory_weapon( weapon )
{
    return !zt_inventory_weapon_excluded( weapon ) && isdefined( level.zombie_lethal_grenade_list ) && isdefined( level.zombie_lethal_grenade_list[weapon] );
}

zt_safe_tactical_inventory_weapon( weapon )
{
    if ( zt_inventory_weapon_excluded( weapon ) || !isdefined( level.zombie_tactical_grenade_list ) || !isdefined( level.zombie_tactical_grenade_list[weapon] ) )
        return false;
    // These are the stock BO2 tactical consumables whose acquisition and Max
    // Ammo paths are count-based. Unknown custom callbacks remain map-owned.
    return weapon == "cymbal_monkey_zm" || weapon == "emp_grenade_zm";
}

zt_safe_placeable_inventory_weapon( weapon )
{
    return !zt_inventory_weapon_excluded( weapon ) && weapon == "claymore_zm" && isdefined( level.zombie_placeable_mine_list ) && isdefined( level.zombie_placeable_mine_list[weapon] );
}

zt_stock_max_ammo_allows( weapon, lethal_slot )
{
    if ( !zt_valid_inventory_weapon( weapon ) )
        return false;
    if ( lethal_slot && zt_true( level.headshots_only ) )
        return false;
    // BO2's stock Max Ammo loop skips every entry registered through the
    // buildable-equipment system. Those items own their own use, recovery and
    // quest lifecycle and expose no BO3-style refill_max_ammo opt-in.
    if ( isdefined( level.zombie_include_equipment ) && isdefined( level.zombie_include_equipment[weapon] ) )
        return false;
    if ( isdefined( level.zombie_weapons_no_max_ammo ) && isdefined( level.zombie_weapons_no_max_ammo[weapon] ) )
        return false;
    return true;
}

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

zt_clamp_total_ammo( weapon, maximum )
{
    if ( !isdefined( weapon ) || weapon == "" )
        return;
    clip = self getweaponammoclip( weapon );
    stock = self getweaponammostock( weapon );
    excess = clip + stock - maximum;
    if ( excess <= 0 )
        return;
    if ( stock >= excess )
        self setweaponammostock( weapon, stock - excess );
    else
    {
        self setweaponammostock( weapon, 0 );
        self setweaponammoclip( weapon, clip - ( excess - stock ) );
    }
}

zt_clamp_clip( weapon, maximum )
{
    if ( !isdefined( weapon ) || weapon == "" )
        return;
    current = self getweaponammoclip( weapon );
    if ( current > maximum )
        self setweaponammoclip( weapon, maximum );
}

zt_clamp_inventory()
{
    if ( !isdefined( self.zt_lethal_reserve ) )
        self.zt_lethal_reserve = 0;
    if ( !isdefined( self.zt_tactical_reserve ) )
        self.zt_tactical_reserve = 0;
    if ( !isdefined( self.zt_placeable_reserve ) )
        self.zt_placeable_reserve = 0;

    // Mob clears its engine offhand slots while Afterlife owns the player.
    // Preserve the script-owned excess until stock restores those slots.
    if ( ( isdefined( self.afterlife ) && self.afterlife ) || zt_true( self.zt_whos_who_inventory_frozen ) )
        return;

    if ( zt_safe_lethal_inventory_weapon( self.current_lethal_grenade ) )
    {
        if ( !isdefined( self.zt_last_lethal ) || self.zt_last_lethal != self.current_lethal_grenade )
        {
            self.zt_lethal_reserve = 0;
            if ( level.zt.config.max_grenades > 0 )
                self zt_clamp_total_ammo( self.current_lethal_grenade, level.zt.config.max_grenades );
            self.zt_last_lethal = self.current_lethal_grenade;
        }
        else
            self.zt_lethal_reserve = self zt_reconcile_clip_inventory( self.current_lethal_grenade, level.zt.config.max_grenades, self.zt_lethal_reserve );
    }
    else
        self.zt_lethal_reserve = 0;

    if ( zt_safe_tactical_inventory_weapon( self.current_tactical_grenade ) )
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
        self.zt_tactical_reserve = 0;

    if ( zt_safe_placeable_inventory_weapon( self.current_placeable_mine ) )
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
        self.zt_placeable_reserve = 0;
}

zt_pacing_install()
{
    level endon( "end_game" );

    // Keep the T6/T7 lifecycle boundary identical: never take ownership of
    // pacing state while a long stock intro still owns startup.
    while ( !zt_game_ready() )
        wait 0.05;

    elapsed = 0;
    missing_reported = 0;
    while ( !isdefined( level.zombie_vars ) )
    {
        wait 0.05;
        elapsed += 0.05;
        if ( elapsed >= 20 && !missing_reported )
        {
            if ( level.zt.config.round_delay >= 0 ) zt_feature( "round_delay", "unavailable", "map has not published a standard between-round delay" );
            if ( level.zt.config.zombie_spawn_rate > 0 ) zt_feature( "zombie_spawn_rate", "unavailable", "map has not published a standard zombie spawn cadence" );
            missing_reported = 1;
        }
    }

    if ( level.zt.config.round_delay >= 0 )
    {
        if ( isdefined( level.zombie_vars["zombie_between_round_time"] ) )
        {
            delay = level.zt.config.round_delay;
            if ( delay == 0 )
                delay = 0.05;
            level.zombie_vars["zombie_between_round_time"] = delay;
            level.zt_round_delay_applied = delay;
            zt_feature( "round_delay", "active", "" );
        }
        else
            zt_feature( "round_delay", "unavailable", "map exposes no standard between-round delay" );
    }

    if ( level.zt.config.zombie_spawn_rate > 0 )
    {
        if ( isdefined( level.zombie_vars["zombie_spawn_delay"] ) )
        {
            level.zt_spawn_delay_base = level.zombie_vars["zombie_spawn_delay"];
            delay = level.zt_spawn_delay_base * 100.0 / level.zt.config.zombie_spawn_rate;
            if ( delay < 0.01 )
                delay = 0.01;
            level.zombie_vars["zombie_spawn_delay"] = delay;
            level.zt_spawn_delay_applied = delay;
            level thread zt_spawn_delay_round_watch();
            zt_feature( "zombie_spawn_rate", "active", "" );
        }
        else
            zt_feature( "zombie_spawn_rate", "unavailable", "map exposes no standard zombie spawn cadence" );
    }

    if ( level.zt.config.round_delay >= 0 || level.zt.config.zombie_spawn_rate > 0 )
        level thread zt_pacing_value_owner_watch();
}

zt_pacing_value_owner_watch()
{
    level endon( "end_game" );
    while ( 1 )
    {
        if ( level.zt.config.round_delay >= 0 && isdefined( level.zombie_vars["zombie_between_round_time"] ) )
        {
            wanted = level.zt.config.round_delay;
            if ( wanted == 0 ) wanted = 0.05;
            // Buried's Time Bomb sets this to zero around its synthetic round
            // transition. Preserve that map-owned sentinel until it restores
            // the configured value it captured before the transaction.
            if ( level.zombie_vars["zombie_between_round_time"] > 0 && level.zombie_vars["zombie_between_round_time"] != wanted )
                level.zombie_vars["zombie_between_round_time"] = wanted;
            level.zt_round_delay_applied = wanted;
        }
        if ( level.zt.config.zombie_spawn_rate > 0 && isdefined( level.zombie_vars["zombie_spawn_delay"] ) )
        {
            current = level.zombie_vars["zombie_spawn_delay"];
            // Buried's Time Bomb publishes zero while it reconstructs its
            // saved enemy wave, then restores the value it observed before
            // that transaction. Zero is a map-owned sentinel, not a new
            // pacing base: scaling it to 0.01 slows the restore, and adopting
            // the subsequently restored (already-scaled) value compounds the
            // configured rate for the rest of the match.
            if ( current > 0 && !zt_true( level.zt_spawn_delay_round_pending ) )
            {
                if ( !isdefined( level.zt_spawn_delay_applied ) || current != level.zt_spawn_delay_applied )
                    level.zt_spawn_delay_base = current;
                wanted = level.zt_spawn_delay_base * 100.0 / level.zt.config.zombie_spawn_rate;
                if ( wanted < 0.01 ) wanted = 0.01;
                level.zombie_vars["zombie_spawn_delay"] = wanted;
                level.zt_spawn_delay_applied = wanted;
            }
        }
        wait 0.25;
    }
}

zt_spawn_delay_round_watch()
{
    level endon( "end_game" );

    while ( 1 )
    {
        level waittill( "end_of_round" );
        level.zt_spawn_delay_round_pending = 1;

        // Time Bomb emits end_of_round only to move the stock state machine
        // to its saved round. It owns both pacing sentinels for that synthetic
        // transition, so it must not advance the ordinary spawn-delay curve.
        if ( zt_true( level.time_bomb_round_change ) )
        {
            level.zt_spawn_delay_round_pending = 0;
            continue;
        }

        // end_of_round is emitted before map round-end callbacks and before
        // stock mutates this value. Bind the recompose to the authoritative
        // round-number transition instead of racing those callbacks with a
        // fixed delay. Round 255 is capped back to 255, so observe stock's
        // live-value mutation there; at the native floor/100% no write is
        // needed because stock already leaves the wanted value in place.
        completed_round = level.round_number;
        if ( completed_round >= 255 )
        {
            if ( level.zt_spawn_delay_base <= 0.08 && level.zt.config.zombie_spawn_rate == 100 )
            {
                level.zt_spawn_delay_round_pending = 0;
                continue;
            }
            while ( level.round_number == completed_round && isdefined( level.zt_spawn_delay_applied ) && level.zombie_vars["zombie_spawn_delay"] == level.zt_spawn_delay_applied )
                wait 0.01;
        }
        else
        {
            while ( level.round_number == completed_round )
                wait 0.01;
        }

        if ( level.zt.config.zombie_spawn_rate > 0 && isdefined( level.zt_spawn_delay_base ) && isdefined( level.zombie_vars ) && isdefined( level.zombie_vars["zombie_spawn_delay"] ) )
        {
            if ( level.zt_spawn_delay_base > 0.08 )
                level.zt_spawn_delay_base = level.zt_spawn_delay_base * 0.95;
            else if ( level.zt_spawn_delay_base < 0.08 )
                level.zt_spawn_delay_base = 0.08;

            wanted = level.zt_spawn_delay_base * 100.0 / level.zt.config.zombie_spawn_rate;
            if ( wanted < 0.01 ) wanted = 0.01;
            level.zombie_vars["zombie_spawn_delay"] = wanted;
            level.zt_spawn_delay_applied = wanted;
        }
        level.zt_spawn_delay_round_pending = 0;
    }
}

/*
    round_spawning reads max_zombie_func synchronously, then starts the
    zombie_total_set_func callback in a separate thread. Own the synchronous
    seam so the very first spawn-loop comparison sees the configured total.
*/
zt_zombies_per_round_install()
{
    level endon( "end_game" );
    level.zt_max_zombie_owned = 0;
    level.zt_max_zombie_detached = 1;
    level.zt_max_zombie_chain = [];
    level.zt_max_zombie_inside = 0;
    level thread zt_zombies_per_round_owner_watch();
}

zt_zombies_per_round_owner_watch()
{
    level endon( "end_game" );

    // max_zombie_func is live round state.  Do not claim it during a stock
    // intro, even when a persisted non-default value is already selected.
    while ( !zt_game_ready() )
        wait 0.05;

    while ( 1 )
    {
        percent = zt_cfg_int( "zt_zombies_per_round", 0 );
        level.zt.config.zombies_per_round = percent;

        if ( percent > 0 )
        {
            if ( !zt_true( level.zt_max_zombie_owned ) )
            {
                if ( isdefined( level.max_zombie_func ) )
                {
                    if ( !isdefined( level.zt_max_zombie_base ) )
                    {
                        level.zt_max_zombie_base = level.max_zombie_func;
                        level.zt_max_zombie_prev = level.max_zombie_func;
                    }
                    else
                        zt_max_zombie_adopt_owner( level.max_zombie_func, zt_true( level.zt_max_zombie_detached ) );
                }
                else
                {
                    if ( !isdefined( level.zt_max_zombie_base ) )
                    {
                        level.zt_max_zombie_base = maps\mp\zombies\_zm::default_max_zombie_func;
                        level.zt_max_zombie_prev = maps\mp\zombies\_zm::default_max_zombie_func;
                    }
                    else
                        zt_max_zombie_release_owner();
                }
                level.max_zombie_func = ::zt_max_zombie_count;
                level.zt_max_zombie_owned = 1;
                level.zt_max_zombie_detached = 0;
            }
            else if ( !isdefined( level.max_zombie_func ) )
            {
                // A temporary map owner may deliberately clear itself. Do not
                // keep invoking that expired callback after reclaiming the seam.
                zt_max_zombie_release_owner();
                level.max_zombie_func = ::zt_max_zombie_count;
            }
            else if ( level.max_zombie_func != ::zt_max_zombie_count )
            {
                zt_max_zombie_adopt_owner( level.max_zombie_func, 0 );
                level.max_zombie_func = ::zt_max_zombie_count;
            }
        }
        else if ( zt_true( level.zt_max_zombie_owned ) )
        {
            // Restore only while our wrapper still owns the seam. A map/mod
            // replacement published on the same boundary wins untouched.
            if ( isdefined( level.max_zombie_func ) && level.max_zombie_func == ::zt_max_zombie_count )
                level.max_zombie_func = level.zt_max_zombie_prev;
            else if ( isdefined( level.max_zombie_func ) )
                zt_max_zombie_adopt_owner( level.max_zombie_func, 0 );
            else
                zt_max_zombie_release_owner();
            level.zt_max_zombie_owned = 0;
            // A restored late owner may have captured our wrapper. Detached
            // calls begin at that owner's immediate predecessor in the chain.
            level.zt_max_zombie_detached = 1;
            zt_feature( "zombies_per_round", "inherit", "" );
        }
        // The isolated T6 default-value owner reproduced startup script-loop
        // warnings with a frame-end yield. Sleep for real time between polls.
        wait 0.05;
    }
}

zt_max_zombie_release_owner()
{
    if ( !isdefined( level.zt_max_zombie_chain ) || level.zt_max_zombie_chain.size <= 0 )
    {
        level.zt_max_zombie_chain = [];
        level.zt_max_zombie_prev = level.zt_max_zombie_base;
        return;
    }

    previous_index = level.zt_max_zombie_chain.size - 1;
    previous = level.zt_max_zombie_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt_max_zombie_chain[i];
    level.zt_max_zombie_chain = restored_chain;
    level.zt_max_zombie_prev = previous;
}

zt_max_zombie_adopt_owner( owner, detached )
{
    if ( !isdefined( level.zt_max_zombie_chain ) )
        level.zt_max_zombie_chain = [];
    if ( !isdefined( level.zt_max_zombie_prev ) )
    {
        level.zt_max_zombie_prev = owner;
        return;
    }
    if ( level.zt_max_zombie_prev == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt_max_zombie_chain.size; i++ )
        if ( level.zt_max_zombie_chain[i] == owner )
            restored_index = i;
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt_max_zombie_chain[i];
        level.zt_max_zombie_chain = restored_chain;
    }
    else if ( !detached )
        level.zt_max_zombie_chain[level.zt_max_zombie_chain.size] = level.zt_max_zombie_prev;
    // While detached, a new outer owner captured the currently published
    // predecessor rather than ZTweaks, so that predecessor is already linked.
    level.zt_max_zombie_prev = owner;
}

zt_max_zombie_forward( max_num )
{
    depth = 0;
    if ( isdefined( level.zt_max_zombie_inside ) )
        depth = level.zt_max_zombie_inside;

    callback = level.zt_max_zombie_prev;
    if ( depth > 0 )
    {
        chain_index = level.zt_max_zombie_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt_max_zombie_chain[chain_index];
        else
            callback = level.zt_max_zombie_base;
    }
    if ( !isdefined( callback ) )
        return max_num;

    level.zt_max_zombie_inside = depth + 1;
    result = [[ callback ]]( max_num );
    level.zt_max_zombie_inside = depth;
    if ( !isdefined( result ) )
        result = max_num;
    return result;
}

zt_max_zombie_count( max_num )
{
    if ( zt_true( level.zt_max_zombie_inside ) )
        return zt_max_zombie_forward( max_num );

    if ( zt_true( level.zt_max_zombie_detached ) )
    {
        level.zt_max_zombie_inside = 1;
        total = zt_max_zombie_forward( max_num );
        level.zt_max_zombie_inside = 0;
        return total;
    }

    total = zt_max_zombie_forward( max_num );

    level.zt.config.zombies_per_round = zt_cfg_int( "zt_zombies_per_round", 0 );
    if ( level.zt.config.zombies_per_round <= 0 )
        return total;

    adjusted = int( total * level.zt.config.zombies_per_round / 100 );
    if ( adjusted < 1 )
        adjusted = 1;
    zt_feature( "zombies_per_round", "active", "" );
    return adjusted;
}

zt_powerup_controls_install()
{
    level endon( "end_game" );

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

    // This watcher reads the duration dvar at each activation boundary. With
    // GAME DEFAULT selected it only observes the registry and changes nothing.
    level thread zt_powerup_effect_watch();

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
    level endon( "end_game" );
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
    level endon( "end_game" );

    while ( true )
    {
        percent = zt_cfg_int( "zt_powerup_effect_time", 0 );
        requested_stacking = zt_cfg_string( "zt_powerup_stacking", "default" );
        stacking = requested_stacking;
        if ( stacking == "ignore" )
            stacking = "default";
        managed = percent > 0 || stacking != "default";
        state_keys = getarraykeys( level.zt.powerup_effect_state );
        observe = managed || state_keys.size > 0;
        if ( observe && isdefined( level.zombie_powerups ) )
        {
            found = 0;
            visited = [];
            keys = getarraykeys( level.zombie_powerups );
            players = get_players();
            for ( i = 0; i < keys.size; i++ )
            {
                powerup = level.zombie_powerups[keys[i]];
                if ( !isdefined( powerup.time_name ) || !isdefined( powerup.on_name ) )
                    continue;

                if ( !found )
                {
                    found = 1;
                    if ( percent > 0 ) zt_feature( "powerup_effect_time", "active", "" );
                    if ( requested_stacking != "default" && requested_stacking != "ignore" ) zt_feature( "powerup_stacking", "active", "" );
                }
                time_name = powerup.time_name;
                on_name = powerup.on_name;
                for ( p = 0; p < players.size; p++ )
                {
                    player = players[p];
                    if ( isdefined( powerup.solo ) && powerup.solo )
                    {
                        // A player-only registration must never fall through to
                        // a team or level timer merely because this player does
                        // not expose the expected vars.
                        if ( !isdefined( player.zombie_vars ) || !isdefined( player.zombie_vars[time_name] ) || !isdefined( player.zombie_vars[on_name] ) )
                        {
                            if ( managed ) zt_feature( "powerup_effect_time", "degraded", "player-only power-up did not publish player timer vars; broader scopes were left untouched" );
                            continue;
                        }
                        entity_number = player getentitynumber();
                        scope_key = "player_" + entity_number + "_" + time_name;
                        if ( !isdefined( visited[scope_key] ) )
                        {
                            visited[scope_key] = 1;
                            zt_powerup_effect_scale_vars( player.zombie_vars, scope_key, time_name, on_name, percent, stacking, player, managed );
                        }
                        continue;
                    }
                    if ( isdefined( level.zombie_vars[player.team] ) && isdefined( level.zombie_vars[player.team][time_name] ) && isdefined( level.zombie_vars[player.team][on_name] ) )
                    {
                        scope_key = "team_" + player.team + "_" + time_name;
                        if ( !isdefined( visited[scope_key] ) )
                        {
                            visited[scope_key] = 1;
                            zt_t6_powerup_activation_watch_ensure( scope_key, time_name, player.team );
                            zt_powerup_effect_scale_vars( level.zombie_vars[player.team], scope_key, time_name, on_name, percent, stacking, player.team, managed );
                        }
                    }
                    else if ( isdefined( level.zombie_vars[time_name] ) && isdefined( level.zombie_vars[on_name] ) )
                    {
                        scope_key = "level_" + time_name;
                        if ( !isdefined( visited[scope_key] ) )
                        {
                            visited[scope_key] = 1;
                            zt_powerup_effect_scale_vars( level.zombie_vars, scope_key, time_name, on_name, percent, stacking, undefined, managed );
                        }
                    }
                }
            }
        }

        // BO2 exposes the timers only after pickup dispatch. By then every
        // stock/custom side effect has already fired, so IGNORE cannot be
        // implemented without pretending to undo an unknown lifecycle.
        if ( requested_stacking == "ignore" )
            zt_feature( "powerup_stacking", "unavailable", "BO2 has no safe pre-dispatch seam for ignoring a repeated timed power-up; stock stacking remains in control" );

        active_state = 0;
        state_keys = getarraykeys( level.zt.powerup_effect_state );
        for ( s = 0; s < state_keys.size; s++ )
        {
            state = level.zt.powerup_effect_state[state_keys[s]];
            if ( isdefined( state ) && zt_true( state.active ) )
            {
                active_state = 1;
                break;
            }
        }
        if ( managed || active_state )
            wait 0.05;
        else
            wait 0.5;
    }
}

zt_powerup_effect_scale_vars( vars, key, time_name, on_name, percent, stacking, owner, managed )
{
    if ( !managed && !isdefined( level.zt.powerup_effect_state[key] ) )
        return;

    if ( !isdefined( level.zt.powerup_effect_state[key] ) )
    {
        level.zt.powerup_effect_state[key] = spawnstruct();
        level.zt.powerup_effect_state[key].active = 0;
        level.zt.powerup_effect_state[key].last = 0;
        level.zt.powerup_effect_state[key].duration = 0;
        level.zt.powerup_effect_state[key].base_duration = 0;
        level.zt.powerup_effect_state[key].percent = 0;
        level.zt.powerup_effect_state[key].sample_time = gettime();
        level.zt.powerup_effect_state[key].gameplay_active = 0;
        level.zt.powerup_effect_state[key].gameplay_owned = 0;
        level.zt.powerup_effect_state[key].activation_serial = 0;
    }

    state = level.zt.powerup_effect_state[key];
    current = vars[time_name];
    activation_serial = 0;
    if ( isdefined( level.zt.powerup_activation_serial[key] ) ) activation_serial = level.zt.powerup_activation_serial[key];
    elapsed = ( gettime() - state.sample_time ) / 1000.0;
    if ( !zt_true( vars[on_name] ) || current <= 0 )
    {
        zt_sync_t6_powerup_gameplay( vars, state, time_name, 0, owner );
        state.active = 0;
        state.last = current;
        state.sample_time = gettime();
        return;
    }

    if ( !state.active )
    {
        if ( !managed || !zt_t6_powerup_timer_supported( time_name, owner, vars ) )
            return;
        state.base_duration = current;
        state.percent = percent;
        if ( percent > 0 ) current = current * percent / 100.0;
        if ( current < 0.05 )
            current = 0.05;
        vars[time_name] = current;
        state.active = 1;
        state.duration = current;
        state.activation_serial = activation_serial;
        zt_take_t6_powerup_gameplay_ownership( vars, state, time_name, owner );
    }
    else
    {
        remaining = state.last - elapsed;
        if ( remaining < 0 ) remaining = 0;
        pickup_event = activation_serial > state.activation_serial;
        pickup_up = pickup_event || current > remaining + 0.2;
        pickup_down = current < remaining - 0.5 && current > 0.2;
        if ( pickup_up || pickup_down )
        {
            if ( !managed )
            {
                // A fresh stock pickup now owns both its timer and fixed wait.
                // Relinquish an older scaled activation without killing it.
                state.gameplay_owned = 0;
                state.gameplay_active = 0;
                state.active = 0;
                state.last = current;
                state.sample_time = gettime();
                state.activation_serial = activation_serial;
                return;
            }
            if ( !zt_t6_powerup_timer_supported( time_name, owner, vars ) )
                return;
            if ( percent != state.percent )
            {
                state.duration = state.base_duration;
                if ( percent > 0 ) state.duration = state.duration * percent / 100.0;
                state.percent = percent;
            }
            // Preserve map extensions by scaling only a newly-added interval.
            // Stock may also reset 30 over a longer scaled remainder, which is
            // the downward activation path handled here.
            if ( stacking == "refresh" ) current = state.duration;
            else if ( stacking == "extend" ) current = remaining + state.duration;
            else if ( percent > 0 && pickup_down ) current = current * percent / 100.0;
            else if ( percent > 0 ) current = remaining + ( current - remaining ) * percent / 100.0;
            vars[time_name] = current;
            state.activation_serial = activation_serial;
            zt_take_t6_powerup_gameplay_ownership( vars, state, time_name, owner );
        }
    }
    state.last = current;
    state.sample_time = gettime();
    zt_sync_t6_powerup_gameplay( vars, state, time_name, 1, owner );
}

zt_t6_powerup_activation_watch_ensure( key, time_name, owner )
{
    if ( time_name != "zombie_powerup_point_doubler_time" && time_name != "zombie_powerup_insta_kill_time" )
        return;
    if ( !isdefined( owner ) || isplayer( owner ) || zt_true( level.zt.powerup_activation_watch[key] ) )
        return;
    level.zt.powerup_activation_watch[key] = 1;
    level.zt.powerup_activation_serial[key] = 0;
    level thread zt_t6_powerup_activation_watch( key, time_name, owner );
}

zt_t6_powerup_activation_watch( key, time_name, owner )
{
    level endon( "end_game" );
    if ( time_name == "zombie_powerup_point_doubler_time" )
        event = "powerup points scaled_" + owner;
    else
        event = "powerup instakill_" + owner;

    while ( 1 )
    {
        level waittill( event, source );
        if ( isdefined( source ) && source == "ztweaks_owner" )
            continue;
        level.zt.powerup_activation_serial[key]++;
    }
}

zt_t6_powerup_timer_supported( time_name, owner, vars )
{
    if ( time_name != "zombie_powerup_point_doubler_time" && time_name != "zombie_powerup_insta_kill_time" )
        return true;

    if ( !isdefined( owner ) || isplayer( owner ) )
    {
        zt_feature( "powerup_effect_time", "degraded", "classic Double Points/Insta-Kill scaling requires an exact stock team scope" );
        return false;
    }
    if ( isdefined( level.zombie_powerup_grab_func ) )
    {
        zt_feature( "powerup_effect_time", "degraded", "map replaces stock power-up pickup dispatch; classic Double Points/Insta-Kill remain map-owned" );
        return false;
    }
    if ( time_name == "zombie_powerup_point_doubler_time" )
    {
        if ( isdefined( level.current_game_module ) && level.current_game_module == 2 )
        {
            zt_feature( "powerup_effect_time", "degraded", "race-team Double Points has additional map-owned state and remains stock" );
            return false;
        }
        if ( !isdefined( vars["zombie_point_scalar"] ) )
        {
            zt_feature( "powerup_effect_time", "degraded", "Double Points did not expose its stock team scalar" );
            return false;
        }
    }
    else
    {
        if ( isdefined( level.insta_kill_powerup_override ) )
        {
            zt_feature( "powerup_effect_time", "degraded", "map supplies a custom Insta-Kill lifecycle and remains authoritative" );
            return false;
        }
        if ( !isdefined( vars["zombie_insta_kill"] ) )
        {
            zt_feature( "powerup_effect_time", "degraded", "Insta-Kill did not expose its stock team state" );
            return false;
        }
    }
    return true;
}

zt_take_t6_powerup_gameplay_ownership( vars, state, time_name, owner )
{
    if ( time_name == "zombie_powerup_point_doubler_time" )
    {
        // Cancel the stock literal wait-30 worker. Its HUD countdown remains
        // alive and is the clock ZTweaks owns below.
        level notify( "powerup points scaled_" + owner, "ztweaks_owner" );
        state.gameplay_owned = 1;
        state.gameplay_active = 1;
        zt_sync_t6_powerup_gameplay( vars, state, time_name, 1, owner );
    }
    else if ( time_name == "zombie_powerup_insta_kill_time" )
    {
        level notify( "powerup instakill_" + owner, "ztweaks_owner" );
        state.gameplay_owned = 1;
        state.gameplay_active = 1;
        zt_sync_t6_powerup_gameplay( vars, state, time_name, 1, owner );
    }
}

zt_sync_t6_powerup_gameplay( vars, state, time_name, active, owner )
{
    // BO2's stock Double Points and Insta-Kill gameplay workers use literal
    // 30-second waits, while the registered timer drives only the HUD. Keep
    // their authoritative gameplay fields attached to the owned timer so
    // shorter, extended and refreshed durations match what the menu promises.
    if ( !zt_true( state.gameplay_owned ) )
        return;

    if ( time_name == "zombie_powerup_point_doubler_time" && isdefined( vars["zombie_point_scalar"] ) )
    {
        if ( active ) vars["zombie_point_scalar"] = 2;
        else vars["zombie_point_scalar"] = 1;
        if ( isdefined( owner ) && !isplayer( owner ) )
        {
            players = get_players( owner );
            foreach ( player in players )
                player setclientfield( "score_cf_double_points_active", active );
        }
        state.gameplay_active = active;
        if ( !active ) state.gameplay_owned = 0;
    }
    else if ( time_name == "zombie_powerup_insta_kill_time" && isdefined( vars["zombie_insta_kill"] ) )
    {
        vars["zombie_insta_kill"] = active;
        if ( !active && zt_true( state.gameplay_active ) && isdefined( owner ) && !isplayer( owner ) )
        {
            players = get_players( owner );
            foreach ( player in players )
                player notify( "insta_kill_over" );
        }
        state.gameplay_active = active;
        if ( !active ) state.gameplay_owned = 0;
    }
}

zt_powerup_max_finalize()
{
    level endon( "end_game" );

    // Drop-rate ownership is match state; do not mutate it during a stock
    // intro simply because the intro lasts longer than a fixed timeout.
    while ( !zt_game_ready() )
        wait 0.05;

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
    level endon( "end_game" );
    while ( 1 )
    {
        if ( !isdefined( level._powerup_timeout_custom_time ) )
        {
            // Quest drops can install a temporary timeout callback and clear
            // it when their transaction ends. Resume the original owner, not
            // the expired quest callback retained in *_prev.
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
    // The BO2 bank reuses a power-up entity for cash withdrawals; it is not a
    // regular collectible and must retain its stock timeout.
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

zt_bank_limit_install()
{
    level endon( "end_game" );

    post_ready_elapsed = 0;
    missing_reported = 0;
    while ( !isdefined( level.bank_deposit_max_amount ) || !isdefined( level.bank_deposit_ddl_increment_amount ) || !isdefined( level.bank_account_max ) )
    {
        wait 0.1;
        if ( zt_game_ready() )
        {
            post_ready_elapsed += 0.1;
            if ( post_ready_elapsed >= 20 && !missing_reported )
            {
                zt_feature( "bank_limit", "unavailable", "map has not published a compatible BO2 bank capability" );
                missing_reported = 1;
            }
        }
    }

    if ( level.bank_deposit_ddl_increment_amount <= 0 )
    {
        zt_feature( "bank_limit", "unavailable", "map published an invalid bank denomination" );
        return;
    }

    units = int( level.zt.config.bank_limit / level.bank_deposit_ddl_increment_amount );
    if ( units < 1 )
        units = 1;

    level.bank_deposit_max_amount = units * level.bank_deposit_ddl_increment_amount;
    level.bank_account_max = units;
    zt_feature( "bank_limit", "active", "" );
}

zt_map_script()
{
    script = getdvar( "mapname" );
    if ( isdefined( level.script ) )
        script = tolower( level.script );
    return script;
}

zt_game_mode_name()
{
    mode = getdvar( "ui_gametype" );
    if ( isdefined( level.scr_zm_ui_gametype ) )
        mode = tolower( level.scr_zm_ui_gametype );
    return mode;
}

zt_flag_is_set( name )
{
    return isdefined( level.flag ) && isdefined( level.flag[name] ) && level.flag[name];
}

zt_power_flag_is_set()
{
    return zt_flag_is_set( "power_on" );
}

zt_registered_global_power_state()
{
    state = spawnstruct();
    state.count = 0;
    state.powered = 0;
    state.unpowered = 0;
    state.malformed = 0;

    if ( !isdefined( level.powered_items ) )
        return state;

    foreach ( powered in level.powered_items )
    {
        if ( !isdefined( powered ) || !isdefined( powered.target ) )
            continue;

        // set_global_power iterates the complete published list, so one
        // malformed globally eligible entry makes the custom-map fallback
        // unsafe even when another entry is valid.
        if ( !isdefined( powered.power_sources ) )
        {
            state.malformed++;
            continue;
        }
        if ( powered.power_sources == 1 )
            continue;
        if ( !isdefined( powered.power ) || !isdefined( powered.powered_count ) || !isdefined( powered.power_on_func ) || !isdefined( powered.power_off_func ) )
        {
            state.malformed++;
            continue;
        }

        state.count++;
        if ( isdefined( powered.power ) && powered.power )
            state.powered++;
        else
            state.unpowered++;
    }

    return state;
}

zt_start_power_global_consumer_owner()
{
    level endon( "end_game" );

    while ( zt_true( level.zt.start_power_global_consumer_owned ) )
    {
        // A later real switch cycle owns one additional power reference.  Its
        // off transition must not erase the base reference owned by ZTweaks,
        // but calling set_global_power again would leak another count.
        if ( !isdefined( level._power_global ) || !level._power_global )
            level._power_global = 1;
        level setclientfield( "zombie_power_on", 1 );
        wait 0.25;
    }
}

zt_start_power_registered_consumers( detail )
{
    state = zt_registered_global_power_state();
    if ( state.count == 0 || state.malformed > 0 )
        return 0;

    if ( state.unpowered == 0 )
    {
        zt_feature( "start_power_on", "active", "map's registered power consumers were already enabled" );
        return 1;
    }

    level thread maps\mp\zombies\_zm_perks::perk_unpause_all_perks();
    maps\mp\zombies\_zm_power::set_global_power( 1 );
    level setclientfield( "zombie_power_on", 1 );
    level.zt.start_power_global_consumer_owned = 1;
    level thread zt_start_power_global_consumer_owner();
    zt_feature( "start_power_on", "degraded", detail );
    return 1;
}

zt_origins_power_zones_ready()
{
    if ( !isdefined( level.zone_capture ) || !isdefined( level.zone_capture.zones ) )
        return 0;

    zone_names = array( "generator_start_bunker", "generator_tank_trench", "generator_mid_trench", "generator_nml_right", "generator_nml_left", "generator_church" );
    foreach ( zone_name in zone_names )
    {
        if ( !isdefined( level.zone_capture.zones[zone_name] ) )
            return 0;
    }
    return 1;
}

zt_origins_enable_power_consumers( force )
{
    zone_names = array( "generator_start_bunker", "generator_tank_trench", "generator_mid_trench", "generator_nml_right", "generator_nml_left", "generator_church" );
    foreach ( zone_name in zone_names )
    {
        zone = level.zone_capture.zones[zone_name];
        if ( isdefined( zone.perk_machines ) && isarray( zone.perk_machines ) )
        {
            perk_keys = getarraykeys( zone.perk_machines );
            foreach ( perk_key in perk_keys )
            {
                perk_trigger = zone.perk_machines[perk_key];
                if ( !isdefined( perk_trigger ) || ( !force && ( !isdefined( perk_trigger.is_locked ) || !perk_trigger.is_locked ) ) )
                    continue;

                level notify( perk_key + "_on" );
                perk_trigger.is_locked = 0;
                perk_trigger maps\mp\zombies\_zm_perks::reset_vending_hint_string();
            }
        }

        if ( isdefined( zone.perk_machines_random ) && isarray( zone.perk_machines_random ) )
        {
            foreach ( random_perk_machine in zone.perk_machines_random )
            {
                if ( !isdefined( random_perk_machine ) || ( !force && ( !isdefined( random_perk_machine.is_locked ) || !random_perk_machine.is_locked ) ) )
                    continue;

                random_perk_machine.is_locked = 0;
                if ( isdefined( level._random_zombie_perk_cost ) )
                    random_perk_machine sethintstring( &"ZM_TOMB_RPB", level._random_zombie_perk_cost );
            }
        }
    }
}

zt_origins_perk_validation_release_owner()
{
    if ( !isdefined( level.zt.start_power_origins_validation_chain ) || level.zt.start_power_origins_validation_chain.size <= 0 )
    {
        level.zt.start_power_origins_validation_chain = [];
        level.zt.start_power_origins_prev_validation = level.zt.start_power_origins_base_validation;
        return;
    }

    previous_index = level.zt.start_power_origins_validation_chain.size - 1;
    previous = level.zt.start_power_origins_validation_chain[previous_index];
    restored_chain = [];
    for ( i = 0; i < previous_index; i++ )
        restored_chain[restored_chain.size] = level.zt.start_power_origins_validation_chain[i];
    level.zt.start_power_origins_validation_chain = restored_chain;
    level.zt.start_power_origins_prev_validation = previous;
}

zt_origins_perk_validation_adopt_owner( owner )
{
    if ( !isdefined( level.zt.start_power_origins_validation_chain ) )
        level.zt.start_power_origins_validation_chain = [];
    if ( !isdefined( level.zt.start_power_origins_prev_validation ) )
    {
        level.zt.start_power_origins_prev_validation = owner;
        return;
    }
    if ( level.zt.start_power_origins_prev_validation == owner )
        return;

    restored_index = -1;
    for ( i = 0; i < level.zt.start_power_origins_validation_chain.size; i++ )
        if ( level.zt.start_power_origins_validation_chain[i] == owner )
            restored_index = i;
    if ( restored_index >= 0 )
    {
        restored_chain = [];
        for ( i = 0; i < restored_index; i++ )
            restored_chain[restored_chain.size] = level.zt.start_power_origins_validation_chain[i];
        level.zt.start_power_origins_validation_chain = restored_chain;
    }
    else
        level.zt.start_power_origins_validation_chain[level.zt.start_power_origins_validation_chain.size] = level.zt.start_power_origins_prev_validation;
    level.zt.start_power_origins_prev_validation = owner;
}

zt_origins_perk_validation_forward( player )
{
    depth = 0;
    if ( isdefined( level.zt.start_power_origins_validation_inside ) )
        depth = level.zt.start_power_origins_validation_inside;

    callback = level.zt.start_power_origins_prev_validation;
    if ( depth > 0 )
    {
        chain_index = level.zt.start_power_origins_validation_chain.size - depth;
        if ( chain_index >= 0 )
            callback = level.zt.start_power_origins_validation_chain[chain_index];
        else
            callback = level.zt.start_power_origins_base_validation;
    }
    if ( !isdefined( callback ) )
        return 1;

    level.zt.start_power_origins_validation_inside = depth + 1;
    result = self [[ callback ]]( player );
    level.zt.start_power_origins_validation_inside = depth;
    if ( !isdefined( result ) )
        result = 1;
    return result;
}

zt_origins_perk_validation( player )
{
    if ( zt_true( level.zt.start_power_origins_validation_inside ) )
        return self zt_origins_perk_validation_forward( player );

    if ( zt_true( level.zt.start_power_origins_owned ) && isdefined( self.str_zone_name ) && isdefined( level.zone_capture ) && isdefined( level.zone_capture.zones ) && isdefined( level.zone_capture.zones[self.str_zone_name] ) )
    {
        self zt_origins_perk_validation_forward( player );
        return 1;
    }

    return self zt_origins_perk_validation_forward( player );
}

zt_start_power_origins_owner()
{
    level endon( "end_game" );
    while ( zt_true( level.zt.start_power_origins_owned ) )
    {
        if ( !isdefined( level.custom_perk_validation ) )
        {
            zt_origins_perk_validation_release_owner();
            level.custom_perk_validation = ::zt_origins_perk_validation;
        }
        else if ( level.custom_perk_validation != ::zt_origins_perk_validation )
        {
            zt_origins_perk_validation_adopt_owner( level.custom_perk_validation );
            level.custom_perk_validation = ::zt_origins_perk_validation;
        }

        zt_origins_enable_power_consumers( 0 );
        wait 0.25;
    }
}

zt_start_power_origins()
{
    elapsed = 0;
    while ( ( !zt_flag_is_set( "capture_zones_init_done" ) || !zt_origins_power_zones_ready() || !isdefined( level.custom_perk_validation ) ) && elapsed < 20 )
    {
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !zt_flag_is_set( "capture_zones_init_done" ) || !zt_origins_power_zones_ready() || !isdefined( level.custom_perk_validation ) )
    {
        zt_feature( "start_power_on", "unavailable", "Origins did not publish its generator perk consumers" );
        return;
    }

    level.zt.start_power_origins_base_validation = level.custom_perk_validation;
    level.zt.start_power_origins_prev_validation = level.custom_perk_validation;
    level.zt.start_power_origins_validation_chain = [];
    level.zt.start_power_origins_validation_inside = 0;
    level.zt.start_power_origins_owned = 1;
    level.custom_perk_validation = ::zt_origins_perk_validation;
    zt_origins_enable_power_consumers( 1 );
    level thread zt_start_power_origins_owner();
    zt_feature( "start_power_on", "active", "powered generator perk consumers; captures, Mystery Boxes, and Pack-a-Punch remain map-owned" );
}

zt_start_power_mob()
{
    if ( zt_game_mode_name() != "zclassic" )
    {
        zt_start_power_wait_for_stock( "map mode starts with power already enabled" );
        return;
    }

    elapsed = 0;
    perk_shockboxes = [];
    while ( elapsed < 20 )
    {
        perk_shockboxes = getentarray( "perk_afterlife_trigger", "script_noteworthy" );
        if ( zt_game_ready() && perk_shockboxes.size > 0 )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( !zt_game_ready() || perk_shockboxes.size == 0 )
    {
        zt_feature( "start_power_on", "unavailable", "Mob did not initialize its Afterlife perk-box waiter" );
        return;
    }

    // Stock installs this one-shot waiter immediately after round logic.  A
    // short frame boundary prevents an early notify from being discarded.
    wait 0.1;
    level notify( "unlock_all_perk_machines" );
    zt_feature( "start_power_on", "active", "powered perk shock boxes; other Afterlife panels and quest state remain map-owned" );
}

zt_start_power_stock_switch( map_label )
{
    elapsed = 0;
    switches = [];
    while ( elapsed < 20 )
    {
        switches = getentarray( "use_elec_switch", "targetname" );
        if ( zt_power_flag_is_set() || ( zt_game_ready() && switches.size == 1 ) )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( zt_power_flag_is_set() )
    {
        zt_feature( "start_power_on", "active", "map mode starts with power already enabled" );
        return;
    }
    if ( !zt_game_ready() || switches.size != 1 )
    {
        zt_feature( "start_power_on", "unavailable", map_label + " did not initialize its single stock power switch" );
        return;
    }

    wait 0.1;
    // Die Rise and Buried are explicitly audited: their callbacks only own the
    // stock switch presentation and functional power state.  No player is
    // supplied, so player dialogue/stat paths remain untouched.
    switches[0] notify( "trigger" );
    elapsed = 0;
    while ( !zt_power_flag_is_set() && elapsed < 5 )
    {
        wait 0.1;
        elapsed += 0.1;
    }

    if ( zt_power_flag_is_set() )
        zt_feature( "start_power_on", "active", "" );
    else
        zt_feature( "start_power_on", "unavailable", map_label + " rejected its stock switch request" );
}

zt_start_power_wait_for_stock( detail )
{
    elapsed = 0;
    while ( !zt_power_flag_is_set() && elapsed < 20 )
    {
        wait 0.1;
        elapsed += 0.1;
    }

    if ( zt_power_flag_is_set() )
        zt_feature( "start_power_on", "active", detail );
    else
        zt_feature( "start_power_on", "unavailable", "map mode did not publish its stock startup power state" );
}

zt_start_power_generic()
{
    while ( !zt_game_ready() )
        wait 0.1;

    elapsed = 0;
    state = zt_registered_global_power_state();
    while ( state.count == 0 && state.malformed == 0 && elapsed < 20 )
    {
        wait 0.1;
        elapsed += 0.1;
        state = zt_registered_global_power_state();
    }

    if ( !zt_start_power_registered_consumers( "powered registered global consumers; custom switches, local power, and quest state remain map-owned" ) )
        zt_feature( "start_power_on", "unavailable", "map exposes no initialized registered global-power consumers" );
}

zt_start_power_install()
{
    level endon( "end_game" );
    script = zt_map_script();
    mode = zt_game_mode_name();

    if ( script == "zm_transit_dr" )
    {
        zt_feature( "start_power_on", "unavailable", "Turned/Cleansed owns its arena and exposes no meaningful power capability" );
        return;
    }

    // Power consumers are match-owned.  A stock intro may last longer than
    // any fixed timeout, so wait for the authoritative round-logic boundary
    // before inspecting or activating map power state.
    while ( !zt_game_ready() )
        wait 0.1;
    zt_boot_trace( "power_ready" );

    if ( script == "zm_tomb" )
    {
        zt_start_power_origins();
        return;
    }
    if ( script == "zm_prison" )
    {
        zt_start_power_mob();
        return;
    }
    if ( script == "zm_nuked" )
    {
        zt_start_power_wait_for_stock( "Nuketown owns its randomized perk and Pack-a-Punch arrival cadence" );
        return;
    }
    if ( script == "zm_highrise" )
    {
        zt_start_power_stock_switch( "Die Rise" );
        return;
    }
    if ( script == "zm_buried" )
    {
        if ( mode == "zclassic" )
            zt_start_power_stock_switch( "Buried" );
        else
            zt_start_power_wait_for_stock( "map mode starts with power already enabled" );
        return;
    }
    if ( script == "zm_transit" )
    {
        if ( mode == "zclassic" )
        {
            while ( !zt_game_ready() )
                wait 0.1;

            elapsed = 0;
            state = zt_registered_global_power_state();
            while ( state.count == 0 && state.malformed == 0 && elapsed < 20 )
            {
                wait 0.1;
                elapsed += 0.1;
                state = zt_registered_global_power_state();
            }
            if ( !zt_start_power_registered_consumers( "powered registered consumers; the buildable switch, reactor, Avogadro, gates, bus, morse code, and quest flags remain map-owned" ) )
                zt_feature( "start_power_on", "unavailable", "TranZit did not publish registered global-power consumers" );
        }
        else
            zt_start_power_wait_for_stock( "map mode starts with power already enabled" );
        return;
    }

    zt_start_power_generic();
}

zt_start_doors_unlock_cleanup()
{
    level waittill( "end_game" );
    if ( zt_true( level.zt.start_doors_unlock_owned ) )
    {
        if ( getdvarint( "zombie_unlock_all" ) == 1 )
            setdvar( "zombie_unlock_all", level.zt.start_doors_unlock_prev );
        level.zt.start_doors_unlock_owned = 0;
    }
}

zt_start_doors_unlock_begin()
{
    if ( !zt_true( level.zt.start_doors_unlock_cleanup_started ) )
    {
        level.zt.start_doors_unlock_cleanup_started = 1;
        level thread zt_start_doors_unlock_cleanup();
    }

    level.zt.start_doors_unlock_prev = getdvarint( "zombie_unlock_all" );
    level.zt.start_doors_unlock_owned = 1;
    setdvar( "zombie_unlock_all", 1 );
}

zt_start_doors_unlock_end()
{
    if ( !zt_true( level.zt.start_doors_unlock_owned ) )
        return;
    if ( getdvarint( "zombie_unlock_all" ) == 1 )
        setdvar( "zombie_unlock_all", level.zt.start_doors_unlock_prev );
    level.zt.start_doors_unlock_owned = 0;
}

zt_door_group_has_open_trigger( linked_triggers )
{
    foreach ( linked_trigger in linked_triggers )
    {
        if ( !isdefined( linked_trigger ) )
            continue;
        if ( isdefined( linked_trigger._door_open ) && linked_trigger._door_open )
            return 1;
        if ( isdefined( linked_trigger.has_been_opened ) && linked_trigger.has_been_opened )
            return 1;
    }
    return 0;
}

zt_door_group_normalize_open( door, linked_triggers )
{
    if ( !isdefined( door ) )
        return;
    // One open member proves that the shared physical blocker already moved.
    // Retire every buy waiter and publish the stock semantic state for only
    // the still-closed triggers; calling door_opened here would toggle the
    // already-open member (and the shared model) closed again.
    zt_door_group_stop_buy_waiters( linked_triggers );
    door.has_been_opened = 1;
    normalized = 0;
    foreach ( linked_trigger in linked_triggers )
    {
        if ( !isdefined( linked_trigger ) )
            continue;
        linked_trigger trigger_off();
        linked_trigger.has_been_opened = 1;
        if ( !isdefined( linked_trigger._door_open ) || !linked_trigger._door_open )
        {
            linked_trigger._door_open = 1;
            linked_trigger notify( "door_opened" );
            if ( isdefined( linked_trigger.script_flag ) )
            {
                tokens = strtok( linked_trigger.script_flag, "," );
                foreach ( token in tokens )
                    if ( level flag_exists( token ) )
                        flag_set( token );
            }
            normalized = 1;
        }
    }
    if ( normalized )
        level notify( "door_opened" );
}

zt_door_group_is_moving( linked_triggers )
{
    foreach ( linked_trigger in linked_triggers )
    {
        if ( isdefined( linked_trigger ) && isdefined( linked_trigger.door_is_moving ) && linked_trigger.door_is_moving )
            return 1;
    }
    return 0;
}

zt_door_group_stop_buy_waiters( linked_triggers )
{
    foreach ( linked_trigger in linked_triggers )
        if ( isdefined( linked_trigger ) )
            linked_trigger notify( "kill_door_think" );
}

zt_open_standard_door_group( door, linked_triggers )
{
    if ( !isdefined( door ) || !isdefined( door._door_open ) || !isdefined( door.doors ) )
        return 0;
    if ( zt_door_group_has_open_trigger( linked_triggers ) )
    {
        zt_door_group_normalize_open( door, linked_triggers );
        return 1;
    }
    if ( zt_door_group_is_moving( linked_triggers ) )
        return 0;
    if ( zt_map_script() == "zm_tomb" )
        return zt_open_tomb_door_group( door, linked_triggers );
    // Do not forward stale physical-part references to stock door_opened.
    surviving_parts = [];
    foreach ( part in door.doors )
        if ( isdefined( part ) )
            surviving_parts[surviving_parts.size] = part;
    door.doors = surviving_parts;
    zt_door_group_stop_buy_waiters( linked_triggers );
    door maps\mp\zombies\_zm_blockers::door_opened( 0 );
    return zt_door_group_has_open_trigger( linked_triggers );
}

zt_open_tomb_door_group( door, linked_triggers )
{
    // BO2 has the same movedone/delete vs door_solid_thread lifetime race
    // as BO3 Origins. Exclude only the disposable bunker models; stock still
    // owns linked trigger state, zones, clips and all other physical parts.
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
        if ( ( part.classname != "script_model" && part.classname != "script_brushmodel" ) ||
            !isdefined( part.script_string ) || ( part.script_string != "move" && part.script_string != "slide_apart" ) ||
            !isdefined( part.script_vector ) ||
            ( isdefined( part.script_transition_time ) && part.script_transition_time <= 0 ) )
            return 0;
        bunker_parts[bunker_parts.size] = part;
    }
    zt_door_group_stop_buy_waiters( linked_triggers );
    door.doors = stock_parts;
    foreach ( part in bunker_parts )
        part zt_tomb_bunker_open();
    door maps\mp\zombies\_zm_blockers::door_opened( 0 );
    surviving_parts = [];
    foreach ( part in original_parts )
        if ( isdefined( part ) )
            surviving_parts[surviving_parts.size] = part;
    if ( isdefined( door ) )
        door.doors = surviving_parts;
    return zt_door_group_has_open_trigger( linked_triggers );
}

zt_tomb_bunker_open()
{
    if ( isdefined( self.door_moving ) )
        return;
    time = 1;
    if ( isdefined( self.script_transition_time ) )
        time = self.script_transition_time;
    self.door_moving = 1;
    self notsolid();
    if ( self.classname == "script_brushmodel" )
        self connectpaths();
    if ( isdefined( self.script_sound ) )
        playsoundatposition( self.script_sound, self.origin );
    else
        maps\mp\zombies\_zm_utility::play_sound_at_pos( "door_slide_open", self.origin );
    if ( isdefined( self.script_firefx ) )
        playfx( level._effect[self.script_firefx], self.origin );
    // Match stock travel/easing; the map owns completion and deletion.
    if ( time >= 0.5 )
        self moveto( self.origin + self.script_vector, time, time * 0.25, time * 0.25 );
    else
        self moveto( self.origin + self.script_vector, time );
}

zt_start_doors_install()
{
    level endon( "end_game" );

    if ( zt_map_script() == "zm_transit_dr" || zt_game_mode_name() == "zcleansed" )
    {
        zt_feature( "start_doors_open", "unavailable", "Turned/Cleansed owns its arena doors and barriers" );
        return;
    }

    // Register cleanup before capability waits so an end-game transition can
    // never race the short affordability-bypass window later in this worker.
    if ( !zt_true( level.zt.start_doors_unlock_cleanup_started ) )
    {
        level.zt.start_doors_unlock_cleanup_started = 1;
        level thread zt_start_doors_unlock_cleanup();
    }

    // Door registries are match-owned.  Separate the unbounded lifecycle wait
    // from the bounded capability-publication window below.
    while ( !zt_game_ready() )
        wait 0.1;
    zt_boot_trace( "doors_ready" );

    elapsed = 0;
    doors = [];
    airlocks = [];
    debris = [];
    players = [];
    while ( elapsed < 20 )
    {
        doors = getentarray( "zombie_door", "targetname" );
        airlocks = getentarray( "zombie_airlock_buy", "targetname" );
        debris = getentarray( "zombie_debris", "targetname" );
        players = getplayers();
        ready = zt_game_ready();
        supported_doors = 0;
        foreach ( door in doors )
        {
            if ( !isdefined( door ) )
                continue;
            standard_door = !isdefined( door.script_noteworthy ) || door.script_noteworthy == "default";
            delayed_door = isdefined( door.script_noteworthy ) && door.script_noteworthy == "delay_door";
            powered_door = isdefined( door.script_noteworthy ) && ( door.script_noteworthy == "electric_door" || door.script_noteworthy == "electric_buyable_door" || door.script_noteworthy == "local_electric_door" );
            if ( !standard_door && !delayed_door && !powered_door )
                continue;

            supported_doors++;
            if ( !isdefined( door._door_open ) || !isdefined( door.doors ) )
            {
                ready = 0;
                break;
            }
        }
        if ( supported_doors == 0 && airlocks.size == 0 && debris.size == 0 )
            ready = 0;
        if ( players.size > 0 && ready )
            break;
        wait 0.1;
        elapsed += 0.1;
    }

    if ( ( doors.size == 0 && airlocks.size == 0 && debris.size == 0 ) || players.size == 0 )
    {
        zt_feature( "start_doors_open", "unavailable", "map exposes no initialized standard door capability" );
        return;
    }
    if ( !zt_game_ready() )
    {
        zt_feature( "start_doors_open", "unavailable", "map did not initialize round logic before the door-capability timeout" );
        return;
    }

    wait_network_frame();
    // Re-sample after the readiness boundary so entities published on the
    // same final initialization frame are included in the startup pass.
    doors = getentarray( "zombie_door", "targetname" );
    airlocks = getentarray( "zombie_airlock_buy", "targetname" );
    debris = getentarray( "zombie_debris", "targetname" );
    players = getplayers();
    if ( ( doors.size == 0 && airlocks.size == 0 && debris.size == 0 ) || players.size == 0 )
    {
        zt_feature( "start_doors_open", "unavailable", "standard door capability disappeared during map initialization" );
        return;
    }
    door_user = undefined;
    foreach ( player in players )
    {
        if ( isdefined( player.sessionstate ) && player.sessionstate == "playing" )
        {
            door_user = player;
            break;
        }
    }
    if ( !isdefined( door_user ) )
    {
        zt_feature( "start_doors_open", "unavailable", "map exposes no active player for stock blocker callbacks" );
        return;
    }
    candidates = [];
    opened_targets = [];
    airlocks_requested = 0;
    debris_opened = 0;
    skipped = 0;
    door_stay_open_owned = 0;
    stock_route = zt_stock_bo2_health_route();
    custom_direct_door_owner = ( isdefined( level._default_door_custom_logic ) || isdefined( level.custom_door_buy_check ) ) && !stock_route;
    custom_debris_owner = isdefined( level.custom_debris_function );

    // The common routine is a toggle.  Invoke it once per linked target only
    // for published traversal types, and never reinterpret quest/counter or
    // custom callback ownership as a normal door purchase.
    foreach ( door in doors )
    {
        if ( !isdefined( door ) )
            continue;
        custom_direct_door_owner = ( isdefined( level._default_door_custom_logic ) || isdefined( level.custom_door_buy_check ) ) && !stock_route;
        // Stock normalizes an omitted subtype to "default", but compatible
        // custom maps can publish the initialized common-door fields without
        // copying that cosmetic normalization. Match the capability probe so
        // a door declared safe is not silently skipped by the open pass.
        standard_door = !isdefined( door.script_noteworthy ) || door.script_noteworthy == "default";
        delayed_door = isdefined( door.script_noteworthy ) && door.script_noteworthy == "delay_door";
        powered_door = isdefined( door.script_noteworthy ) && ( door.script_noteworthy == "electric_door" || door.script_noteworthy == "electric_buyable_door" || door.script_noteworthy == "local_electric_door" );
        if ( ( !standard_door && !delayed_door && !powered_door ) || !isdefined( door._door_open ) || !isdefined( door.doors ) || custom_direct_door_owner )
        {
            skipped++;
            continue;
        }
        if ( !isdefined( door.target ) || isdefined( opened_targets[door.target] ) )
            continue;

        linked_triggers = getentarray( door.target, "target" );
        if ( linked_triggers.size == 0 )
        {
            skipped++;
            continue;
        }

        opened_targets[door.target] = 1;
        candidates[candidates.size] = door;
        if ( !door_stay_open_owned )
        {
            level.local_doors_stay_open = 1;
            door_stay_open_owned = 1;
        }

        // Stock updates every linked trigger atomically.  Any open member is
        // therefore evidence that the physical group already moved; normalize
        // metadata to open instead of translating/rotating the model twice.
        zt_open_standard_door_group( door, linked_triggers );
    }

    // No BO2 stock route currently publishes an airlock, but retain the stock
    // forced-trigger seam for a future stock entity and fail closed on custom
    // handlers whose ownership cannot be inferred.
    foreach ( airlock in airlocks )
    {
        if ( !stock_route || !isdefined( airlock ) )
        {
            skipped++;
            continue;
        }

        zt_start_doors_unlock_begin();
        airlock notify( "trigger", door_user, 1 );
        airlocks_requested++;
        wait_network_frame();
        zt_start_doors_unlock_end();
    }

    foreach ( blocker in debris )
    {
        if ( isdefined( level.custom_debris_function ) )
            custom_debris_owner = 1;
        if ( custom_debris_owner || !isdefined( blocker ) || ( isdefined( blocker.script_noteworthy ) && blocker.script_noteworthy != "default" ) || !isdefined( blocker.target ) )
        {
            skipped++;
            continue;
        }

        zt_start_doors_unlock_begin();
        blocker notify( "trigger", door_user, 1 );
        wait_network_frame();
        zt_start_doors_unlock_end();
        if ( !isdefined( blocker ) )
            debris_opened++;
        else
            skipped++;
    }

    // A common door ignores door_opened while moving.  Retry only groups still
    // proven closed; an open or mixed group is metadata-normalized and never
    // toggled a second time.
    for ( retry = 0; retry < 2; retry++ )
    {
        retry_targets = [];
        foreach ( retry_door in candidates )
        {
            if ( !isdefined( retry_door ) || !isdefined( retry_door.target ) || isdefined( retry_targets[retry_door.target] ) )
                continue;
            retry_targets[retry_door.target] = 1;
            linked_triggers = getentarray( retry_door.target, "target" );
            if ( linked_triggers.size == 0 )
                continue;
            zt_open_standard_door_group( retry_door, linked_triggers );
            wait 0.05;
        }
        wait 0.5;
    }

    opened = 0;
    foreach ( door in candidates )
    {
        if ( !isdefined( door ) || !isdefined( door.target ) )
            continue;
        linked_triggers = getentarray( door.target, "target" );
        if ( linked_triggers.size > 0 && zt_door_group_has_open_trigger( linked_triggers ) )
            opened++;
    }

    if ( candidates.size == 0 && airlocks_requested == 0 && debris_opened == 0 )
        zt_feature( "start_doors_open", "unavailable", "map exposes no safe standard purchasable doors" );
    else if ( opened == 0 && airlocks_requested == 0 && debris_opened == 0 )
        zt_feature( "start_doors_open", "unavailable", "map rejected its standard door-open requests" );
    else if ( opened < candidates.size || skipped > 0 )
        zt_feature( "start_doors_open", "degraded", "opened common traversal blockers; custom, counter, airlock, and quest-owned blockers were preserved" );
    else
        zt_feature( "start_doors_open", "active", "" );
}

zt_perk_limit_install()
{
    level endon( "end_game" );

    while ( !zt_game_ready() )
        wait 0.25;

    wait 2.25;

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
    level endon( "end_game" );
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
    if ( zt_true( level.zs_loaded ) && isdefined( level.zs_perk_limit_prev ) )
        return self [[ level.zs_perk_limit_prev ]]();

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
        return 99;

    map_limit = self zt_map_perk_limit();
    base = 4;
    if ( isdefined( level.perk_purchase_limit ) )
        base = level.perk_purchase_limit;

    extra = map_limit - base;
    if ( extra < 0 )
        extra = 0;

    return wanted + extra;
}

zt_damage_tweaks_install()
{
    level endon( "end_game" );
    while ( !zt_game_ready() ) wait 0.1;

    // Observe the live rows without owning the map's callback while every row
    // is DEFAULT. The watcher claims before an enabled row can apply and gives
    // the exact latest owner back when all three rows return to DEFAULT.
    level.zt_player_damage_installed = 0;
    level.zt_player_damage_owned = 0;
    level.zt_player_damage_detached = 1;
    level.zt_player_damage_chain = [];
    level.zt_player_damage_inside = 0;
    level thread zt_player_damage_owner_watch();
    if ( level.zt.config.weapon_damage > 0 || level.zt.config.melee_damage > 0 || level.zt.config.challenge_rising_damage > 0 || level.zt.config.pap_damage_multiplier > 0 )
    {
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
        if ( level.zt.config.weapon_damage > 0 ) zt_feature( "weapon_damage", "active", "" );
        if ( level.zt.config.melee_damage > 0 ) zt_feature( "melee_damage", "active", "" );
        if ( level.zt.config.challenge_rising_damage > 0 ) zt_feature( "challenge_rising_damage", "active", "" );
        if ( level.zt.config.pap_damage_multiplier > 0 ) zt_feature( "pap_damage_multiplier", "active", "registered upgrades only; custom upgrade systems remain map-owned" );
    }
    if ( zt_true( level.zt_player_damage_installed ) && level.zt.config.no_explosive_self_damage ) zt_feature( "no_explosive_self_damage", "active", "" );
    if ( zt_true( level.zt_player_damage_installed ) && level.zt.config.fall_damage != 0 ) zt_feature( "fall_damage", "active", "" );
}

zt_player_damage_owner_watch()
{
    level endon( "end_game" );
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
            if ( no_self_damage ) zt_feature( "no_explosive_self_damage", "active", "" );
            if ( fall_damage != 0 ) zt_feature( "fall_damage", "active", "" );
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
        // This passive owner runs at DEFAULT; yield real time between checks.
        wait 0.05;
    }
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
    // While detached, a new outer owner captured the previously published
    // owner rather than ZTweaks. Do not duplicate that already-linked owner.
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
    level endon( "end_game" );
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

zt_actor_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime, boneindex )
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
    result = self [[ callback ]]( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime, boneindex );
    level.zt_actor_damage_inside = depth;
    return result;
}

zt_is_explosive_mod( meansofdeath )
{
    return meansofdeath == "MOD_PROJECTILE" || meansofdeath == "MOD_PROJECTILE_SPLASH" || meansofdeath == "MOD_GRENADE" || meansofdeath == "MOD_GRENADE_SPLASH" || meansofdeath == "MOD_EXPLOSIVE";
}

zt_spawn_protection_applies( inflictor, attacker, meansofdeath )
{
    if ( meansofdeath == "MOD_FALLING" || meansofdeath == "MOD_SUICIDE" || meansofdeath == "MOD_TRIGGER_HURT" || meansofdeath == "MOD_CRUSH" || meansofdeath == "MOD_DROWN" )
        return 0;
    if ( attacker == self || inflictor == self )
        return 0;
    if ( isdefined( inflictor ) && isdefined( inflictor.owner ) && inflictor.owner == self )
        return 0;
    return isdefined( attacker ) || isdefined( inflictor );
}

zt_player_damage_wrapper( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime )
{
    if ( zt_true( level.zt_player_damage_inside ) )
        return self zt_player_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );

    // A custom owner can retain this function after ZTweaks releases the
    // published slot. Enter one level down so its immediate predecessor runs
    // rather than recursively invoking the detached outer owner.
    if ( zt_true( level.zt_player_damage_detached ) )
    {
        level.zt_player_damage_inside = 1;
        result = self zt_player_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
        level.zt_player_damage_inside = 0;
        return result;
    }

    if ( !self zt_player_tweaks_allowed() )
    {
        return self zt_player_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
    }

    // Transform the damage before delegating. The stock override performs
    // lethal/end-game side effects internally, so zeroing only its return
    // value would be too late even though the engine health write is blocked.
    adjusted_damage = damage;
    force_zero = 0;
    if ( level.zt.config.zombie_damage > 0 && self zt_ordinary_zombie_melee_damage( attacker, meansofdeath ) )
    {
        adjusted_damage = int( adjusted_damage * level.zt.config.zombie_damage / 100.0 + 0.5 );
        if ( adjusted_damage < 1 ) adjusted_damage = 1;
    }
    if ( isdefined( self.zt_spawn_protection_until ) && gettime() < self.zt_spawn_protection_until && self zt_spawn_protection_applies( inflictor, attacker, meansofdeath ) )
    {
        adjusted_damage = 0;
        force_zero = 1;
    }
    if ( meansofdeath == "MOD_FALLING" && level.zt.config.fall_damage != 0 )
    {
        if ( level.zt.config.fall_damage < 0 )
        {
            adjusted_damage = 0;
            force_zero = 1;
        }
        else
            adjusted_damage = int( adjusted_damage * level.zt.config.fall_damage / 100.0 + 0.5 );
    }
    if ( level.zt.config.no_explosive_self_damage && zt_is_explosive_mod( meansofdeath ) )
    {
        if ( attacker == self || inflictor == self || ( isdefined( inflictor ) && isdefined( inflictor.owner ) && inflictor.owner == self ) )
        {
            adjusted_damage = 0;
            force_zero = 1;
        }
    }

    result = self zt_player_damage_forward( inflictor, attacker, adjusted_damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime );
    if ( force_zero )
        return 0;
    if ( !isdefined( result ) )
        result = adjusted_damage;
    return result;
}

zt_ordinary_zombie_melee_damage( attacker, meansofdeath )
{
    if ( meansofdeath != "MOD_MELEE" || !isdefined( attacker ) || isplayer( attacker ) )
        return false;
    if ( !isdefined( attacker.is_zombie ) || !attacker.is_zombie )
        return false;
    if ( isdefined( level.zombie_team ) && ( !isdefined( attacker.team ) || attacker.team != level.zombie_team ) )
        return false;
    if ( isdefined( attacker.targetname ) && attacker.targetname != "zombie" )
        return false;
    if ( ( isdefined( attacker.is_sloth ) && attacker.is_sloth ) || ( isdefined( attacker.is_friendly ) && attacker.is_friendly ) )
        return false;
    if ( ( isdefined( attacker.ignore_enemy_count ) && attacker.ignore_enemy_count ) || isdefined( attacker.script_noteworthy ) )
        return false;
    return true;
}

zt_actor_damage_wrapper( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime, boneindex )
{
    if ( zt_true( level.zt_actor_damage_inside ) )
        return self zt_actor_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime, boneindex );

    percent = level.zt.config.weapon_damage;
    if ( meansofdeath == "MOD_MELEE" ) percent = level.zt.config.melee_damage;
    // Scale only concrete player-weapon hits on actual zombies. Friendly NPC
    // and quest-actor damage share this callback on several stock maps and
    // must remain map-owned.
    growth = level.zt.config.challenge_rising_damage;
    pap_percent = level.zt.config.pap_damage_multiplier;
    if ( self zt_damage_scaling_target( attacker, weapon ) && ( percent > 0 || growth > 0 || pap_percent > 0 ) )
    {
        if ( percent <= 0 ) percent = 100;
        round_scale = 100;
        if ( growth > 0 && isdefined( level.round_number ) && level.round_number > 1 )
        {
            round_scale = 100 + ( level.round_number - 1 ) * growth;
            if ( round_scale > 500 ) round_scale = 500;
        }
        damage = int( damage * percent * round_scale / 10000.0 + 0.5 );
        if ( pap_percent > 0 && isdefined( level.zombie_weapons_upgraded ) && maps\mp\zombies\_zm_weapons::is_weapon_upgraded( weapon ) )
            damage = int( damage * pap_percent / 100.0 + 0.5 );
        if ( damage < 1 ) damage = 1;
    }
    return self zt_actor_damage_forward( inflictor, attacker, damage, flags, meansofdeath, weapon, point, direction, hitloc, offsettime, boneindex );
}

zt_damage_scaling_target( attacker, weapon )
{
    if ( !isdefined( self.is_zombie ) || !self.is_zombie || !isdefined( attacker ) || !isplayer( attacker ) )
        return false;
    if ( isdefined( self.is_sloth ) && self.is_sloth )
        return false;
    if ( isdefined( self.is_friendly ) && self.is_friendly )
        return false;
    if ( isdefined( level.zombie_team ) && isdefined( self.team ) && self.team != level.zombie_team )
        return false;
    if ( !isdefined( weapon ) || weapon == "" || weapon == "none" )
        return false;

    base_weapon = get_base_name( weapon );
    if ( self zt_player_owns_damage_weapon( attacker, weapon, base_weapon ) )
        return true;
    return isdefined( level.zombie_weapons ) && isdefined( level.zombie_weapons[base_weapon] ) && attacker hasweapon( base_weapon );
}

zt_fast_barrier_rebuild_install()
{
    // This opt-in changes only the stock post-board pause, never the blocker
    // script or map-authored delays. A saved ON row is inert when the master
    // experimental switch is OFF.
    if ( !level.zt.config.experimental_tweaks )
    {
        zt_feature( "fast_barrier_rebuild", "unavailable", "Enable Experimental Tweaks to edit this stock-map-only setting." );
        return;
    }
    if ( !zt_stock_bo2_health_route() )
    {
        zt_feature( "fast_barrier_rebuild", "unavailable", "recognized stock map required" );
        return;
    }
    level endon( "end_game" );
    applied = 0;
    reported = 0;
    for ( tick = 0; tick < 40; tick++ )
    {
        if ( isdefined( level.exterior_goals ) )
        {
            foreach ( barrier in level.exterior_goals )
            {
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

zt_player_owns_damage_weapon( attacker, weapon, base_weapon )
{
    if ( attacker hasweapon( weapon ) || attacker getcurrentweapon() == weapon )
        return true;
    weapons = attacker getweaponslist();
    foreach ( carried in weapons )
        if ( carried == weapon || get_base_name( carried ) == base_weapon )
            return true;
    return false;
}

zt_point_gain_install()
{
    if ( level.zt.config.point_gain <= 0 ) return;
    level thread zt_point_spend_watch();
    zt_feature( "point_gain", "active", "stock earned score and box refunds are scaled; direct map score restoration remains map-owned" );
}

zt_point_spend_watch()
{
    level endon( "end_game" );
    while ( 1 )
    {
        level waittill( "spent_points", player, points );
        if ( !isdefined( player ) || !isplayer( player ) || !isdefined( points ) || points <= 0 ) continue;
        if ( !isdefined( player.zt_point_spent_since_sample ) ) player.zt_point_spent_since_sample = 0;
        player.zt_point_spent_since_sample += points;
    }
}

zt_point_gain_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    while ( 1 )
    {
        // Plutonium can resume a frame-end polling loop repeatedly before a
        // useful score transaction advances. The earlier T6 connection stall
        // had this shape in other passive workers. A short timed yield keeps
        // this enabled-only sampler off that watchdog path while score_total
        // and spent_points still aggregate every transaction between samples.
        wait 0.05;
        if ( !isdefined( self.score ) ) continue;
        if ( zt_true( self.zt_point_gain_baseline_pending ) || !isdefined( self.zt_point_gain_previous ) )
        {
            self.zt_point_gain_previous = self.score;
            if ( isdefined( self.score_total ) ) self.zt_point_gain_total_previous = self.score_total;
            self.zt_point_spent_since_sample = 0;
            continue;
        }
        current = self.score;
        pers_in_sync = isdefined( self.pers ) && isdefined( self.pers["score"] ) && self.pers["score"] == current;
        spent = self.zt_point_spent_since_sample;
        self.zt_point_spent_since_sample = 0;
        delta = current - self.zt_point_gain_previous + spent;
        total_delta = 0;
        current_total = 0;
        if ( isdefined( self.score_total ) )
        {
            current_total = self.score_total;
            if ( isdefined( self.zt_point_gain_total_previous ) )
                total_delta = current_total - self.zt_point_gain_total_previous;
        }
        // BO2 has no earned-points notification. Stock positive awards raise
        // score_total; the only stock positive currency-only path is the
        // moving-box refund. Derive that refund as the currency-only residual
        // so an award and a refund in the same frame are both represented.
        earned = total_delta;
        if ( earned < 0 ) earned = 0;
        refund = 0;
        if ( delta > earned && self zt_moving_box_refund_context() )
            refund = delta - earned;
        if ( refund < 0 ) refund = 0;

        // Other positive score-only rewrites are map-owned restores.
        time_bomb_restore = isdefined( level._time_bomb ) && flag( "time_bomb_restore_active" );
        gain = earned + refund;
        if ( gain > 0 && !time_bomb_restore && level.zt.config.point_gain > 0 )
        {
            scaled = int( gain * level.zt.config.point_gain / 100.0 + 0.5 );
            bonus = scaled - gain;
            if ( bonus != 0 )
            {
                self.score = current + bonus;
                if ( pers_in_sync ) self.pers["score"] = self.score;
                // Stock add_to_player_score records every currency award,
                // including add_to_total=0 refunds, in this player stat.
                // Keep end-game/leaderboard accounting aligned with the
                // spendable-score multiplier without touching map restores.
                self incrementplayerstat( "score", bonus );
                current = self.score;
            }
        }
        // Refunds are spendable currency, not lifetime earned score.
        if ( earned > 0 && !time_bomb_restore && level.zt.config.point_gain > 0 )
        {
            scaled_total = int( earned * level.zt.config.point_gain / 100.0 + 0.5 );
            total_bonus = scaled_total - earned;
            if ( total_bonus != 0 )
            {
                self.score_total = current_total + total_bonus;
                current_total = self.score_total;
            }
        }
        self.zt_point_gain_previous = current;
        if ( isdefined( self.score_total ) )
            self.zt_point_gain_total_previous = current_total;
    }
}

zt_moving_box_refund_context()
{
    if ( !isdefined( level.flag ) || !isdefined( level.flag["moving_chest_now"] ) || !level.flag["moving_chest_now"] || !isdefined( level.chests ) )
        return false;
    foreach ( chest in level.chests )
        if ( isdefined( chest.chest_user ) && chest.chest_user == self && isdefined( chest.weapon_out ) && chest.weapon_out )
            return true;
    return false;
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
    self.zt_point_spent_since_sample = 0;
    self.zt_point_gain_baseline_pending = 0;

    if ( !zt_true( self.zt_point_gain_watch ) )
    {
        self.zt_point_gain_watch = 1;
        self thread zt_point_gain_watch();
    }
}

zt_down_tweaks_install()
{
    level endon( "end_game" );
    while ( !zt_game_ready() ) wait 0.1;

    level.zt.bleedout_time_stock = getdvarfloat( "player_lastStandBleedoutTime" );
    level.zt.bleedout_time_applied = level.zt.bleedout_time_stock;
    level.zt.bleedout_time_owned = 0;
    level thread zt_bleedout_time_watch();

    level.zt_player_laststand_owned = 0;
    level.zt_player_laststand_detached = 1;
    level.zt_player_laststand_chain = [];
    level.zt_player_laststand_inside = 0;
    level.zt_player_laststand_last_limit = level.zt.config.down_limit;
    level thread zt_player_laststand_owner_watch();

    if ( level.zt.config.revive_time > 0 ) zt_feature( "revive_time", "unavailable", "BO2 exposes no composable revive-time callback" );
    if ( level.zt.config.lose_perks_on_down != "default" ) zt_feature( "lose_perks_on_down", "unavailable", "stock removes perks inside its private last-stand pipeline" );
    if ( level.zt.config.keep_weapons_bleedout ) zt_feature( "keep_weapons_bleedout", "unavailable", "generic inventory restoration would duplicate map quest weapons" );
}

zt_down_limit_unavailable_reason()
{
    if ( !zt_stock_bo2_health_route() )
        return "unknown/custom map down routing is not safely composable";
    if ( zt_game_mode_name() == "zcleansed" )
        return "Turned/Cleansed owns its role-conversion last-stand transaction";
    if ( zt_flag_is_set( "solo_game" ) )
        return "solo Quick Revive eligibility resolves before the composable last-stand callback";
    if ( zt_true( level.zombiemode_using_chugabud_perk ) )
        return "Who's Who resolves before the composable last-stand callback";
    if ( zt_true( level.zombiemode_using_afterlife ) )
        return "Mob Afterlife resolves before the composable last-stand callback";
    return "";
}

zt_bleedout_time_watch()
{
    level endon( "end_game" );
    previous_bleedout = -999;
    previous_revive = level.zt.config.revive_time;
    previous_lose_perks = level.zt.config.lose_perks_on_down;
    previous_keep_weapons = level.zt.config.keep_weapons_bleedout;

    while ( 1 )
    {
        percent = zt_cfg_int( "zt_bleedout_time", 0 );
        current = getdvarfloat( "player_lastStandBleedoutTime" );
        base_changed = 0;
        ownership_changed = 0;

        // Turned/Cleansed uses 0.05 as a role-conversion sentinel, not a human
        // bleed-out duration. Never adopt, scale, or restore that mode-owned
        // value; doing so changes its core death transaction.
        if ( isdefined( level.gametype ) && level.gametype == "zcleansed" )
        {
            if ( zt_true( level.zt.bleedout_time_owned ) && current == level.zt.bleedout_time_applied )
                setdvar( "player_lastStandBleedoutTime", level.zt.bleedout_time_stock );
            level.zt.bleedout_time_owned = 0;
            level.zt.config.bleedout_time = percent;
            if ( percent > 0 && percent != previous_bleedout )
                zt_feature( "bleedout_time", "unavailable", "Turned/Cleansed owns its 0.05-second role-conversion sentinel" );
            else if ( percent <= 0 && percent != previous_bleedout )
                zt_feature( "bleedout_time", "inherit", "" );
            previous_bleedout = percent;
            wait 0.25;
            continue;
        }

        if ( percent > 0 )
        {
            // Compose with modes which publish or replace their bleed-out
            // duration after common Zombies initialization. A value other
            // than our last output is a new owner/base, not another value to
            // multiply on top of the previous ZTweaks result.
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
                target = level.zt.bleedout_time_stock * percent / 100.0;
                if ( !zt_true( level.zt.bleedout_time_owned ) || target != level.zt.bleedout_time_applied || current != target )
                {
                    level.zt.bleedout_time_applied = target;
                    setdvar( "player_lastStandBleedoutTime", level.zt.bleedout_time_applied );
                    ownership_changed = 1;
                }
                level.zt.bleedout_time_owned = 1;
                if ( percent != previous_bleedout || base_changed || ownership_changed )
                    zt_feature( "bleedout_time", "active", "composed with the map's live bleed-out duration" );
            }
            else
            {
                level.zt.bleedout_time_owned = 0;
                if ( percent != previous_bleedout || base_changed )
                    zt_feature( "bleedout_time", "unavailable", "the map exposes no standard bleed-out duration" );
            }
        }
        else if ( zt_true( level.zt.bleedout_time_owned ) )
        {
            // Restore only while our last value still owns the dvar. A late
            // map/mod assignment wins instead of being overwritten.
            if ( current == level.zt.bleedout_time_applied )
                setdvar( "player_lastStandBleedoutTime", level.zt.bleedout_time_stock );
            level.zt.bleedout_time_owned = 0;
            zt_feature( "bleedout_time", "inherit", "" );
        }
        else if ( current > 0 )
            level.zt.bleedout_time_stock = current;

        if ( percent != level.zt.config.bleedout_time )
            level.zt.config.bleedout_time = percent;
        previous_bleedout = percent;

        // BO2 exposes no safe common owner for these private last-stand
        // operations. They still have live NEXT DOWN / NEXT BLEED-OUT menu
        // boundaries, so resample them and keep the compatibility report in
        // sync with the current request rather than the match-start snapshot.
        revive = zt_cfg_int( "zt_revive_time", 0 );
        if ( revive != previous_revive )
        {
            level.zt.config.revive_time = revive;
            if ( revive > 0 )
                zt_feature( "revive_time", "unavailable", "BO2 exposes no composable revive-time callback" );
            else
                zt_feature( "revive_time", "inherit", "" );
            previous_revive = revive;
        }

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

zt_player_laststand_owner_watch()
{
    level endon( "end_game" );
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
        wait 0.05;
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
    if ( self zt_player_tweaks_allowed() && limit > 0 )
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
    self endon( "disconnect" );
    self notify( "zt_down_limit_release_no_revive" );
    self endon( "zt_down_limit_release_no_revive" );
    self waittill_any( "player_revived", "bled_out", "death", "spawned_player" );
    wait_network_frame();
    if ( zt_true( self.zt_down_limit_no_revive_owned ) )
    {
        self.no_revive_trigger = undefined;
        self.zt_down_limit_no_revive_owned = 0;
    }
}

zt_transition_feature( name, state, reason )
{
    if ( isdefined( level.zt.features[name] ) && level.zt.features[name].state == state && level.zt.features[name].reason == reason ) return;
    zt_feature( name, state, reason );
}

// Stock BO2 Zombies health regeneration reads this delay from level on each
// damage check. Compose with a later map baseline; leave the private stock
// healing rate and any custom replacement system untouched.
zt_regen_delay_install()
{
    level endon( "end_game" );
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

// Stock round_think publishes end_of_round after the normal round wait.
// Add an optional separate award through the stock score API, preserving
// map-authored round-end callbacks and other mods' score listeners. A
// per-player round marker ignores duplicate notifications from a custom map.
zt_death_points_install()
{
    level endon( "end_game" );
    while ( !zt_game_ready() ) wait 0.25;
    if ( !isdefined( level.zombie_vars ) || !isdefined( level.zombie_vars["penalty_died"] ) )
    {
        zt_feature( "death_points_retained", "unavailable", "map exposes no standard death-point penalty" );
        return;
    }
    // Stock defaults to zero loss and reads this value only when a spectator
    // respawns. A map-specific starting penalty owns its own death economy.
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
    level endon( "end_game" );
    while ( !zt_game_ready() ) wait 0.25;
    while ( true )
    {
        level waittill( "end_of_round" );
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
            player maps\mp\zombies\_zm_score::add_to_player_score( level.zt.config.round_bonus );
            awarded++;
        }
        if ( awarded > 0 ) zt_transition_feature( "round_bonus", "active", "" );
    }
}

// Stock trap_use_think reads trap.zombie_cost at purchase time. Only mutate
// initialized stock traps; custom use callbacks and later map price owners win.
zt_trap_price_install()
{
    level endon( "end_game" );
    elapsed = 0;
    while ( 1 )
    {
        traps = getentarray( "zombie_trap", "targetname" );
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
                    trap._trap_use_trigs[j] sethintstring( &"ZOMBIE_BUTTON_BUY_TRAP", cost );
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
    if ( isdefined( trap.script_flag_wait ) ) return zt_flag_is_set( trap.script_flag_wait );
    return zt_flag_is_set( "power_on" );
}

zt_box_tweaks_install()
{
    level endon( "end_game" );
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
            if ( level.zt.config.box_quality == "no_wonders" ) zt_feature( "box_quality", "unavailable", "BO2 weapon registrations do not identify wonder weapons generically" );
            else if ( level.zt.config.box_quality == "everything" ) zt_feature( "box_quality", "degraded", "map-composed candidates are preserved, while stock safety and ownership exclusions remain" );
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
    if ( level.zt.config.challenge_one_box ) zt_feature( "challenge_one_box", "unavailable", "stock exposes completion notifications but no safe per-player pre-use veto" );
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
    level waittill( "end_game" );
    if ( !isdefined( level.zt.box_lock_dvar_owned ) || !level.zt.box_lock_dvar_owned )
        return;

    setdvar( "magic_chest_movable", level.zt.box_lock_movable_stock );
    level.zt.box_lock_dvar_owned = 0;
}

zt_box_owner_watch()
{
    level endon( "end_game" );
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
    stub unitrigger_set_hint_string( chest, "default_treasure_chest", cost );
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
        if ( zt_true( chest.zt_box_offer_recorded ) || !isdefined( chest.chest_user ) || !isplayer( chest.chest_user ) || !isdefined( chest.grab_weapon_name ) ) continue;
        chest.chest_user.zt_box_last_offered_weapon = chest.grab_weapon_name;
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
    if ( level.zt.config.box_quality == "improved" )
    {
        high = [];
        for ( i = 0; i < keys.size; i++ )
        {
            if ( isdefined( level.zombie_weapons[keys[i]].cost ) && level.zombie_weapons[keys[i]].cost >= 1500 ) high[high.size] = keys[i];
        }
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
    // The stock pickup path asks this callback for its primary-weapon limit.
    // Never replace a map's own rule, including a late publication.
    if ( isdefined( level.get_player_weapon_limit ) )
    {
        zt_feature( "challenge_one_weapon_slot", "unavailable", "map owns the primary-weapon limit" );
        return;
    }
    level.get_player_weapon_limit = ::zt_one_weapon_slot_limit;
    zt_feature( "challenge_one_weapon_slot", "active", "" );
    if ( level.zt.config.secondary_starting_weapon != "default" )
        zt_feature( "secondary_starting_weapon", "unavailable", "one-weapon-slot challenge takes precedence" );
    level endon( "end_game" );
    while ( true )
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

zt_auto_restart_install()
{
    while ( !zt_game_ready() )
        wait 0.25;

    level.zt.config.auto_restart = zt_cfg_int( "zt_auto_restart", 0 );
    level.zt.config.next_map = zt_cfg_string( "zt_next_map", "same" );
    if ( !level.zt.config.auto_restart && level.zt.config.next_map == "same" )
        return;

    if ( level.zt.config.auto_restart )
        zt_feature( "auto_restart", "active", "waiting for game over" );
    if ( level.zt.config.next_map != "same" )
        zt_feature( "next_map", "active", "waiting for game over" );
    level thread zt_auto_restart();
}

zt_auto_restart()
{
    level waittill( "end_game" );

    restart = zt_cfg_int( "zt_auto_restart", 0 );
    next_map = zt_cfg_string( "zt_next_map", "same" );
    manual_end = isdefined( level.host_ended_game ) && level.host_ended_game;

    // The stock End Game action also sends end_game, after marking the match
    // as host-ended and freezing players. It must return to the lobby without
    // launching another match. Next Map may still update the lobby selection.
    if ( manual_end && next_map == "same" )
        return;

    if ( !restart && next_map == "same" )
        return;

    // Never race stock end_game/exitlevel from a separate GSC thread. Hand
    // the action to the private lobby after the normal results and exit.
    autostart = 0;
    if ( restart && !manual_end )
        autostart = 1;
    setdvar( "zt_t6_endgame_pending", 1 );
    setdvar( "zt_t6_endgame_autostart", autostart );
}

zt_build_watermark()
{
    level endon( "end_game" );

    stamp = zt_build();
    if ( stamp == "" )
        return;

    while ( !zt_game_ready() )
        wait 0.5;

    if ( zt_cfg_int( "zt_auto_restart", 0 ) )
        stamp = stamp + "  [AR ON]";

    if ( zt_cfg_int( "zt_start_doors_open", 0 ) )
        stamp = stamp + "  [DOORS ON]";

    if ( isdefined( level.zt_build_hud ) )
        return;

    // ZPause uses y=8 and ZShare uses y=26. ZTweaks owns the third row.
    e = createserverfontstring( "objective", 1.1 );
    e setpoint( "TOPRIGHT", "TOPRIGHT", 0, 44 );
    e.color = ( 1, 0.72, 0.32 );
    e.sort = 1000;
    e.foreground = 1;
    e.alpha = 0.7;
    e settext( stamp );
    level.zt_build_hud = e;
}

zt_build()
{
    // ZT_BUILD_BEGIN
    return "";
    // ZT_BUILD_END
}
