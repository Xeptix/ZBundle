/*
======================================================================
    ZPAUSE T7 v1.8  --  Synced co-op pause for Black Ops III Zombies

    by Xep

======================================================================

    A port of ZPause (Plutonium T6) to Black Ops III. A fork of the T6
    build rather than the older two: T7 has the same button set, the same
    HUD API, the same _hud_util parent bookkeeping and real timer
    elements. What changes is the entry point, the dialect's small print,
    and the freeze -- which this engine does properly.

        Buttons  hold crouch + melee

    Everything runs on the host. Nobody else needs this file.

----------------------------------------------------------------------
    HOW IT WORKS, AND HOW IT DIFFERS FROM THE T6 BUILD

    T6 leans on disablezombies(), the engine-level AI freeze host
    migration uses. Black Ops III has something better and Treyarch uses
    it in zombies already -- the Killing Time GobbleGum, in
    scripts\zm\bgbs\_zm_bgb_killing_time.gsc:

        level flag::set( "world_is_paused" );
        setpauseworld( 1 );

    setpauseworld() is a true world freeze: AI, physics and animation all
    stop, so zombies hold their pose mid-stride rather than standing in an
    idle. zp_freeze_anims has nothing left to do here.

    The flag matters more than the builtin. A large amount of stock
    zombies script already watches it:

        _zm.gsc                   round_spawning blocks on it, so the
                                  spawner stops without touching a gate
        zm_castle_ee_bossfight    boss phase timer waits it out
        zm_siegebot_nikolai       three separate waits
        zm_stalingrad_dragon      skips its think, refuses damage
        zm_stalingrad_zombie      two spawn paths wait
        _zm_ai_napalm             early-out
        _zm_ai_sentinel_drone     waits
        _zm_weap_shrink_ray       early-out

    So a ZPause pause on this engine is deeper than on any of the others:
    boss fights and scripted encounters hold themselves.

    Players have to be exempted from it. setpauseworld() freezes them
    too -- which is why the campaign calls setignorepauseworld( 1 ) on a
    player it wants to keep moving through a paused scene. Here the reason
    is existential: a player who stops being simulated stops reporting
    usebuttonpressed(), and nobody could ever unpause. So players are
    exempted from the world freeze and locked the ordinary way, with
    freezecontrols(). Treyarch pairs the same two calls in campaign.

    Everything else is the T6 build:

        player freezecontrols( 1 )      lock players
        player enableinvulnerability()  nobody can be hurt
        locktimer()                     hold level.discardtime

    locktimer() is byte-for-byte the same function on both engines.

----------------------------------------------------------------------
    NOT PORTED

    One setting is inert rather than absent, so that one config works
    across every port: zp_freeze_anims, since the engine freeze already
    stops animation here.

----------------------------------------------------------------------
    VERIFICATION

    gsc-tool advertises t7 and answers "not implemented" for both
    dialects, so it is no help here. This gets the T5 and T4 treatment
    instead: every call, field, notify, flag and zombie_var checked
    against the stock script dump. See tools/audit.py and
    tools/deep_check.py.

    The t7-compiler is a real compiler, so a bad script is rejected at
    build time rather than on load.

----------------------------------------------------------------------
    CREDITS

        Xep           author
        Treyarch      _zm_bgb_killing_time.gsc, the pause recipe here
        Serious       t7-source, and the compiler this builds with

----------------------------------------------------------------------
    LICENSE

        MIT -- see LICENSE. Keep this header on copies.

======================================================================
*/

#include scripts\codescripts\struct;
#include scripts\shared\array_shared;
#include scripts\shared\callbacks_shared;
#include scripts\shared\flag_shared;
#include scripts\shared\hud_util_shared;
#include scripts\shared\lui_shared;
#include scripts\shared\system_shared;
#include scripts\shared\util_shared;
#include scripts\zm\_zm_powerups;

// The LUI event zp_ui_tell() sends. Declared, as the stock scripts declare
// theirs: an event name nothing has precached throws when it is sent.
#precache( "eventstring", "zpause_state" );

#namespace zpause;


/* ==================================================================
    ENTRY POINT

    Black Ops III registers a script with the system manager and hangs its
    work off the shared callbacks, rather than exposing an init() the
    loader happens to call. system::register runs __init__ once the game
    is up; the callbacks fire per player from there.
   ================================================================== */

/*
    zp_origin_wanted() reads level.zp, which zp_load_config() fills. This
    runs before the gametype starts, so it reads the dvars straight
    instead -- one nobody has set comes back "", which carries on, and
    that is the default.
*/
zp_origin_allowed()
{
    origin = zp_origin();

    if ( getdvarstring( "zp_only_script" ) == "1" && origin != "script" )
        return 0;

    if ( getdvarstring( "zp_only_mod" ) == "1" && origin != "mod" )
        return 0;

    return 1;
}

/*
    Whether ZPause is installed this match. Black Ops III is the one port
    where the player callbacks are registered outside init() -- the system
    manager runs __init__ and the shared callbacks fire from there -- so
    init()'s own gate does not reach them, and a switched-off ZPause still
    gave every player a watcher, a button combo and a pause. Everything the
    callbacks start asks this first.

    The config struct once init() has read it, and the dvar before that: a
    player can be connected before the gametype starts, and a callback that
    cannot answer would be one that guesses.
*/
zp_switched_on()
{
    if ( zp_true( level.zp_off ) )
        return 0;

    if ( isdefined( level.zp ) && isdefined( level.zp.enabled ) )
        return level.zp.enabled;

    return getdvarstring( "zp_enabled" ) != "0";
}

autoexec __init__sytem__()
{
    system::register( "zpause", ::__init__, undefined, undefined );
}

/*
    The callbacks register whatever the gate says, and each one checks it
    for itself. They used to go behind it, which is wrong in the Workshop
    build: that copy stands in for scripts\zm\gametypes\_clientids.gsc, so
    its init() and on_connect are that stock script's work as well as
    ZPause's -- level.clientid and the clientid every player is handed.
    Losing the gate there left .clientid undefined while the game's own
    zombies scripts index attackerdamage[player.clientid] outside a
    devblock, so turning zp_only_script on took a stock script down with
    the copy it was meant to silence.

    The gate is still on everything of ours. Both copies register their own
    callbacks -- under different system names, "zpause" and "clientids", so
    neither displaces the other -- and the losing copy's on_spawned would
    otherwise still fire and could win the self.zp_thinking race. Nothing
    would misbehave, since both are the same code, but the level would be
    set up by one copy and the player watchers by the other, which is not
    the test zp_only_script and zp_only_mod exist to run.

    init() has the gate already, in the shape it can afford there:
    zp_origin_wanted(), read off the config rather than the dvars.
*/
__init__()
{
    callback::on_start_gametype( ::init );
    callback::on_connect( ::zp_on_connect );
    callback::on_spawned( ::zp_on_spawned );
}

zp_on_connect()
{
    if ( !zp_origin_allowed() || !zp_switched_on() )
        return;

    self thread zp_player_think();
}

zp_on_spawned()
{
    if ( !zp_origin_allowed() || !zp_switched_on() )
        return;

    // zp_player_think() waits on "spawned_player" itself; the callback is
    // only here so a player who connected before the script was up still
    // gets a watcher.
    if ( !zp_true( self.zp_thinking ) )
        self thread zp_player_think();
}

/*
    is_true() does not exist on this engine -- it appears in the dump only
    as a parameter name, never as a function -- so it is carried here, the
    same as on T4.

    getplayers() is not reachable either. getplayers() is the builtin, and
    is called directly throughout rather than wrapped.
*/
zp_true( v )
{
    return isdefined( v ) && v;
}

/*
    set_dvar_if_unset() has no Black Ops III equivalent that a zombies
    script can reach, so the same behaviour is done by hand. Creating the
    dvar is the point: the console can only assign to one that already
    exists, so a plain read would leave every setting unreachable in game.
*/
set_dvar_if_unset( dvar, def )
{
    cur = getdvarstring( dvar );

    if ( cur == "" )
    {
        setdvar( dvar, def );
        return def;
    }

    return cur;
}

init()
{
    // The injected and mod builds can both reach this. Only ever set up
    // once.
    if ( zp_true( level.zp_loaded ) )
        return;

    /*
        Config first, and the flag after: zp_only_script and zp_only_mod
        are read from it, and a copy that is not the one being asked for
        has to leave level.zp_loaded alone so the other one can still take
        it.
    */
    zp_load_config();

    if ( !zp_origin_wanted() )
        return;

    level.zp_loaded = 1;
    level.zp_copy = zp_copy_id();

    /*
        Switched off. The descriptor still goes up, because "not here" and
        "here, and off" are different answers to a mod asking whether it
        can hand ZPause a pause.
    */
    if ( !level.zp.enabled )
    {
        // Read by the player callbacks, which the system manager registered
        // before any of this ran and which are not behind this gate.
        level.zp_off = 1;
        zp_api_register( 0 );
        return;
    }

    level.zp_off = undefined;

    level.zp_paused = 0;
    level.zp_busy = 0;
    level.zp_last_toggle = 0;
    level.zp_pause_start = 0;
    level.zp_pause_count = 0;
    level.zp_pending = 0;
    level.zp_pending_by = undefined;
    level.zp_menu_sync_held = undefined;
    level.zp_spawn_flag_was_set = 0;
    level.zp_held_vars = [];
    level.zp_pauser_name = "someone";
    level.zp_pauser = undefined;
    level.zp_hud = undefined;
    level.zp_hud_sub_override = undefined;
    level.zp_hud_meta = undefined;
    level.zp_hud_clock = undefined;
    level.zp_vote_clock = undefined;
    level.zp_panel = undefined;

    level.zp_vote_active = 0;
    level.zp_vote_serial = 0;
    level.zp_vote_kind = "pause";
    level.zp_vote_approval = 0;
    level.zp_vote_end_time = 0;
    level.zp_vote_last_fail = 0;
    level.zp_vote_provisional = 0;
    level.zp_vote_initiator = undefined;
    level.zp_vote_name = "someone";
    level.zp_vote_hud = undefined;
    level.zp_vote_rows = [];

    /*
        The flag the stock scripts watch. Killing Time flag::init()s it,
        but that script is only in the zone when the GobbleGum is in the
        map's pool, so it cannot be relied on to exist.
    */
    if ( !level flag::exists( "world_is_paused" ) )
        level flag::init( "world_is_paused" );

    // Built once: arrays are parent variables, and the menu is opened
    // many times a match.
    zp_menu_table();

    level thread zp_endgame_safety();
    level thread zp_round_watcher();
    level thread zp_personal_watcher();
    level thread zp_menu_sync_watcher();
    level thread zp_config_watcher();
    level thread zp_config_printer();
    /*
        Made here, not read into existence: the console can only assign to a
        dvar that already exists, so "Unknown cmd zp_hud_debug" is what a
        switch nobody created looks like from in the game.
    */
    if ( getdvarstring( "zp_hud_debug" ) == "" )
        setdvar( "zp_hud_debug", "0" );

    level thread zp_build_watermark();
    level thread zp_ui_publisher();

    // Last, so the first thing that reads it finds a mod already up.
    zp_api_register( 1 );
}


/* ==================================================================
    CONFIG

    Every value below can also be overridden with a dvar of the same
    name (set it in your config before the map loads), so server hosts
    do not have to edit this file.
   ================================================================== */

/*
    Which copy of the script this is: "script" for the loose build the
    injector and T7x load, "mod" for the Workshop fastfile.

    With both installed both reach init(), and the first one there wins.
    zp_only_script and zp_only_mod pick the winner instead, which is worth
    having only while testing one against the other.

    Written by mk_t7_variants.py when it generates the Workshop build, the
    same way build.py writes the version stamp. Never edit it by hand.
*/
zp_origin()
{
    // ZP_ORIGIN_BEGIN
    return "script";
    // ZP_ORIGIN_END
}

/*
    Which copy this is, as far as two loaded copies need telling apart: where
    it came from and which build it is. Two loose copies of one build are the
    same code and may share players; a bundle's copy and a loose one may not.
*/
zp_copy_id()
{
    return zp_origin() + "|" + zp_version();
}

/*
    Whether this copy is the one that was asked for. Neither setting on --
    which is the default -- means whichever loads first, as before.
*/
zp_origin_wanted()
{
    origin = zp_origin();

    if ( level.zp.only_script && origin != "script" )
        return 0;

    if ( level.zp.only_mod && origin != "mod" )
        return 0;

    return 1;
}

zp_load_config()
{
    /*
        Reuse the struct rather than making a new one. spawnstruct() takes
        a parent script variable, and this runs on every pause request --
        including ones that bail on the cooldown -- so allocating each time
        walks a long session into "exceeded maximum number of parent server
        script variables" and drops it. The fields below are all overwritten
        on every pass, so there is nothing stale to clear.
    */
    if ( !isdefined( level.zp ) )
        level.zp = spawnstruct();

    // --- general ---------------------------------------------------

    /*
        ZPause itself. On by default. Off, the script still loads, still
        says so on level.zmods -- with enabled 0 -- and installs nothing
        else: no threads, no HUD, no chat words, no button watcher and nothing
        precached. The match runs as it would with the file gone.

        Read once, as the match loads. Taking a pause that is already
        installed back out safely is not something a switch can do in the
        middle of a game, so this one lands on the next match, which is
        what a bundle's MODS page says about it.
    */
    level.zp.enabled = zp_cfg_int( "zp_enabled", 1 );

    // --- debug -----------------------------------------------------
    /*
        Which copy of the script runs when more than one is installed --
        the loose one the injector and T7x load, or the Workshop mod.
        Both off is whichever gets there first, which is the normal case.

        For testing one against the other. Setting both leaves nothing
        running at all.
        Read once, when the script loads: init() runs a single time per
        game, so changing either of these mid-match cannot move which copy
        is already running. End the game and start a new one. Re-running
        init() on a live match would mean tearing down threads, HUD and any
        held state, which is not worth it for a debug switch.
    */
    level.zp.only_script = zp_cfg_int( "zp_only_script", 0 );
    level.zp.only_mod    = zp_cfg_int( "zp_only_mod", 0 );

    // --- input -----------------------------------------------------

    /*
        Only the host may pause. With this on the script behaves as though
        the host is the only player in the game: nobody else can start or
        end a pause, and a pause never goes to a vote, because there is no
        one left to ask.

        The host is the player in the first slot. On a dedicated server
        nobody is really the host, and it falls to whoever holds it.
    */
    level.zp.host_only = zp_cfg_int( "zp_host_only", 0 );

    /*
        A personal pause. Off by default. With it on, the pause input holds
        only the player who pressed it -- frozen, protected, and ignored by
        the zombies -- while everybody else plays on. The whole game pauses
        by itself once nobody is left playing: everybody else paused too,
        or down. The first one back brings it back. See zp_personal_start().

        Personal to each player, so it never goes to a vote, the host's
        approval or the ready check, and zp_host_only does not stop it:
        what that setting protects is a game the others are playing, which
        a personal pause does not touch. It does spend one of the match's
        zp_max_pauses, and zp_max_pause_time ends it, the same as a pause.
    */
    level.zp.personal_pause = zp_cfg_int( "zp_personal_pause", 0 );

    /*
        The game's own pause menu pauses the game. Off by default. Opening
        it is the pause input and closing it is the resume input, so it
        answers to everything else here -- zp_host_only, a vote, the host's
        approval, the cooldown, zp_max_pauses -- exactly as the combo does,
        and with zp_personal_pause on it takes that player out of the game
        on their own.

        Every route but the t7-compiler's: the menu is heard through Lua,
        and an injected script reaches a stock client that loads none. Each
        player's own game reports their own menu, so a player without
        ZPause opening theirs pauses nothing. See
        lui/ui/zpause/zpausepausemenu.lua.
    */
    level.zp.pause_menu = zp_cfg_str( "zp_pause_menu", "off" );

    /*
        The host's settings menu, opened while paused by holding fire and
        melee. See zp_menu_watcher().
    */
    level.zp.menu      = zp_cfg_int( "zp_menu", 1 );

    // Chat words that toggle the pause. "!p" is the short form.
    level.zp.allow_short_words = zp_cfg_int( "zp_allow_short_words", 0 );

    // Hold two buttons together to toggle the pause.
    level.zp.button_combo      = zp_cfg_int( "zp_button_combo", 1 );

    /*
        Which combo does it. Defaults to crouch + melee, the same as every
        other port.

            crouch_melee | crouch_use | crouch_frag | crouch_ads
            jump_melee | use_frag | frag_only | use_ads | use_attack
            attack_ads

        A different list from T5 and T4, which read getstance() where this
        engine has stancebuttonpressed() -- so the two do not offer the
        same combos even though the dvar, the default and the meaning are
        the same. zp_combo_pressed() below is the whole vocabulary; a name
        it does not know falls through to jump + melee.
    */
    level.zp.combo             = zp_cfg_str( "zp_combo", "crouch_melee" );
    level.zp.button_hold_time  = zp_cfg_float( "zp_button_hold_time", 0.3 );

    /*
        Down on the floor or bled out and spectating, the stance and melee
        buttons stop reaching the server, so the normal combo goes dead.
        Use, aim and fire all keep coming through -- _killcam.gsc sets
        sessionstate to "spectator" and then reads usebuttonpressed() to
        skip the killcam, and last stand code reads the same.

        These are the combos used in that state instead. use_frag and
        frag_only are also available if a build turns out to deliver a
        different set; zp_input_debug prints exactly which buttons arrive
        in which state. Setting either to "" leaves a player in that state
        with nothing but chat to act through -- so leave them bound unless
        you mean it.
    */
    level.zp.button_combo_dead  = zp_cfg_str( "zp_button_combo_dead", "use_ads" );
    level.zp.vote_no_combo_dead = zp_cfg_str( "zp_vote_no_combo_dead", "use_attack" );
    level.zp.input_debug        = zp_cfg_int( "zp_input_debug", 0 );

    // --- voting ----------------------------------------------------

    /*
        Resuming waits for the players to say they are back, rather than
        the first one to press the button deciding for everybody. Off by
        default.

        Not a vote, and not built on one: nobody votes no, it cannot fail
        and it has no clock. It waits. That is why it does not need zp_vote
        turned on, and why it wins over zp_vote_unpause where both are set.
        zp_max_pause_time is what ends a pause nobody ever answers.
    */
    level.zp.ready_check = zp_cfg_int( "zp_ready_check", 0 );

    /*
        How much of the room has to be ready. 100 is everybody, which is
        the point of it; lower it where one person going quiet should not
        be able to hold the rest.
    */
    level.zp.ready_percent = zp_cfg_int( "zp_ready_percent", 100 );

    /*
        The host pauses at once; anybody else has to ask, and the host
        answers yes or no. Off by default.

        It is a vote with an electorate of one, and reuses the whole of
        one: the same yes/no combos, the same HUD, the same clock and the
        same timeout -- which is also what makes it work on Black Ops 4,
        the one port with no chat. Narrowing eligibility to the host is
        what stops the asker's own automatic yes from carrying it.

        Pausing only. A resume still follows zp_vote and zp_vote_unpause:
        needing the host's permission to un-pause would strand everybody
        if the host put the controller down, which is the opposite of what
        this is for.

        zp_host_only wins where both are set -- it turns the request away
        before there is anything to approve.
    */
    level.zp.host_approve = zp_cfg_int( "zp_host_approve", 0 );
    /*
        Off by default: without it any player pauses on their own, which
        is what ZPause has always done. Turn it on and a pause has to
        carry the room first.

        The bar is whichever is higher, zp_vote_min or zp_vote_percent of
        the players in the game, and it is then clamped to the number of
        players -- so a lobby can never set a bar nobody present can
        clear. When that works out to a single vote, as it does solo, the
        vote is skipped and the pause just happens.
    */
    level.zp.vote               = zp_cfg_int( "zp_vote", 0 );
    level.zp.vote_min           = zp_cfg_int( "zp_vote_min", 2 );
    level.zp.vote_percent       = zp_cfg_int( "zp_vote_percent", 51 );
    level.zp.vote_time          = zp_cfg_float( "zp_vote_time", 30 );
    level.zp.vote_unpause       = zp_cfg_int( "zp_vote_unpause", 0 );

    /*
        Freeze the game for the duration of the vote and put it back if
        the vote fails, so nobody dies while the room decides. Off by
        default: it lets one player stop play on their own, which is the
        thing voting is there to prevent.
    */
    level.zp.vote_hold          = zp_cfg_int( "zp_vote_hold", 0 );
    level.zp.vote_initiator_yes = zp_cfg_int( "zp_vote_initiator_yes", 1 );
    level.zp.vote_lockout       = zp_cfg_float( "zp_vote_lockout", 10 );
    level.zp.vote_hud           = zp_cfg_int( "zp_vote_hud", 1 );
    level.zp.vote_show_voters   = zp_cfg_int( "zp_vote_show_voters", 1 );
    level.zp.vote_hud_position  = zp_cfg_str( "zp_vote_hud_position", "top" );

    /*
        Leave the dead out of the maths. On by default because counting
        them makes votes unwinnable exactly when you most want one: two
        players, one bled out, a threshold of two and only one person left
        who can answer. Players in last stand still count -- they are
        alive, and they still care whether the game stops.
    */
    level.zp.vote_alive_only    = zp_cfg_int( "zp_vote_alive_only", 1 );

    // How long the result stands on the tally once a vote resolves.
    level.zp.vote_result_time   = zp_cfg_float( "zp_vote_result_time", 2 );

    /*
        Which combo votes no. Only watched while a vote is open, so the
        only clash that matters is one you might hit during those few
        seconds. jump + melee is not something you hold in normal play;
        the crouch_* alternatives are easier to reach but all collide
        with something (use = buy/revive, ads = crouch-aiming).

        jump_melee | crouch_use | crouch_frag | crouch_ads | crouch_melee
    */
    level.zp.vote_no_combo      = zp_cfg_str( "zp_vote_no_combo", "jump_melee" );

    // --- timing ----------------------------------------------------

    /*
        Hold a pause until the round is over instead of freezing the game
        mid-horde. Asking again while one is pending calls it off.

        Off by default: it takes "pause now" away, and that is often
        exactly why somebody is reaching for the button.
    */
    level.zp.round_pause = zp_cfg_int( "zp_round_pause", 0 );

    /*
        A cap on how many times one match can be paused, for a server where
        that would otherwise become an argument. 0 is no cap.

        Only a pause somebody asked for spends one: an automatic pause is
        not theirs to spend.
    */
    level.zp.max_pauses = zp_cfg_int( "zp_max_pauses", 0 );

    /*
        Pause when somebody drops. A crash or a dropped connection
        otherwise leaves whoever is left to be overrun, and on these
        clients the player can come back.

        Nothing here un-pauses on its own, so zp_max_pause_time is the
        way out when they do not come back.
    */
    level.zp.pause_on_disconnect = zp_cfg_int( "zp_pause_on_disconnect", 0 );
    level.zp.countdown         = zp_cfg_int( "zp_countdown", 3 );   // 3..2..1 before play resumes

    /*
        Ease time down into the pause and back out of it, rather than
        cutting to a stop. Treyarch's own presentation for a world pause,
        and the same lerp _killcam.gsc uses going into a kill cam.

        This is NOT the timescale trap the README warns about. Two things
        make it safe where "timescale 0" is not:

            - The scale never reaches zero, so script waits keep running
              and the unpause loop can never be frozen with it.
            - Time is snapped back to normal the moment the world is
              actually frozen. Nothing is moving by then, so the snap is
              invisible, and the server spends only zp_ease_time at a
              reduced rate rather than the whole pause.

        Set zp_ease 0 for a hard cut.
    */
    level.zp.ease              = zp_cfg_int( "zp_ease", 1 );
    level.zp.ease_time         = zp_cfg_float( "zp_ease_time", 0.35 );
    level.zp.grace             = zp_cfg_float( "zp_grace", 2 );     // seconds of invuln after resuming
    level.zp.cooldown          = zp_cfg_float( "zp_cooldown", 2 );  // min seconds between toggles
    level.zp.max_pause_time    = zp_cfg_int( "zp_max_pause_time", 0 ); // 0 = unlimited

    // --- what gets frozen ------------------------------------------
    level.zp.engine_freeze     = zp_cfg_int( "zp_engine_freeze", 1 );      // disablezombies()/enablezombies()
    level.zp.drift_guard       = zp_cfg_int( "zp_drift_guard", 1 );        // snap back any AI that still moves

    /*
        Cosmetic. Without this a paused zombie holds whatever animation it
        was in and loops it, because disablezombies() stops the animscript
        updating the state while the engine carries on playing it. This
        switches them into "zm_inert", the standing pose the game uses for
        dormant zombies.

        Only the pose is borrowed, not start_inert() -- its inert_wakeup()
        watcher would un-freeze any zombie a player walked near or sprinted
        past. Standard zombies only; dogs and boss AI use their own animsets.
    */
    level.zp.freeze_anims      = zp_cfg_int( "zp_freeze_anims", 1 );

    /*
        Shut the zombies up while the game is held. A frozen horde stood
        next to you keeps growling, which is loud and misleading when
        nothing is happening.

        _zm_audio.gsc::do_zombies_playvocals() returns early for anything
        flagged is_inert, so setting that flag stops new vocals at the
        source; stopsounds() cuts whatever was already in the air. Only the
        flag is borrowed, never start_inert() -- its inert_wakeup() watcher
        would un-freeze any zombie a player walked near, the same reason
        zp_freeze_anims takes only the pose.

        The game's own zm_novocals switch is no use here -- it sits inside
        a developer-only block and is compiled out of a release build.
    */
    level.zp.silence_zombies   = zp_cfg_int( "zp_silence_zombies", 1 );
    level.zp.godmode           = zp_cfg_int( "zp_godmode", 1 );
    level.zp.freeze_players    = zp_cfg_int( "zp_freeze_players", 1 );

    /*
        Re-assert the player freeze while the game is held. Map scripts
        that carry a player somewhere lock the controls for the ride and
        call freezecontrols( 0 ) when it ends -- Ascension's lander is the
        one that bites -- which hands control back mid-pause and lets that
        player walk around a frozen game. Nothing can read the freeze state
        back, so the guard simply re-applies it; it re-pins godmode and
        ignoreme at the same time.
    */
    level.zp.control_guard     = zp_cfg_int( "zp_control_guard", 1 );
    level.zp.freeze_clock      = zp_cfg_int( "zp_freeze_clock", 1 );
    level.zp.freeze_powerups   = zp_cfg_int( "zp_freeze_powerups", 1 );
    level.zp.freeze_effects    = zp_cfg_int( "zp_freeze_effects", 1 );     // insta-kill / double points
    level.zp.freeze_bleedout   = zp_cfg_int( "zp_freeze_bleedout", 1 );

    // --- presentation ----------------------------------------------

    /*
        Draw the pause block at all. Off leaves everything else working --
        the freeze, the vote, the chat replies -- with nothing on screen,
        which is what a recording or a server drawing its own overlay
        wants.

        The vote HUD is separate and keeps drawing, because a vote nobody
        can see is a vote nobody can answer.
    */
    level.zp.hud               = zp_cfg_int( "zp_hud", 1 );
    level.zp.blackout          = zp_cfg_int( "zp_blackout", 1 );

    /*
        How dark it goes. 1 is fully black; lower leaves the screen
        readable, for when the point is to discourage scouting rather than
        to make it impossible.
    */
    level.zp.blackout_alpha = zp_cfg_float( "zp_blackout_alpha", 0.2 );  // black out screens while paused
    level.zp.show_hint         = zp_cfg_int( "zp_show_hint", 1 ); // tell players how to pause on spawn

    /*
        Where each block of HUD text sits: top, center, middle, bottom,
        left or right. The left and right slots align their text to that
        edge rather than staying centred.

        "center" is the classic banner spot -- horizontally centred and
        high enough to stay out of the fight, which is where the pause
        banner has sat since v1.0. "middle" is the actual centre of the
        screen, over the crosshair.
    */
    level.zp.hud_position      = zp_cfg_str( "zp_hud_position", "center" );

    /*
        Draw the combos as the buttons each player actually has bound
        rather than as words. [{+bind}] is substituted by the client at
        draw time, so the same string renders as a key on a keyboard and
        as a pad glyph on a controller, per player, with no detection
        needed -- and it follows rebound keys. Stock code does the same
        in _ai_tank.gsc and _rcbomb.gsc.

        Turn it off for plain words if a glyph does not render on your
        build. Chat is always words, since only the HUD substitutes.
    */
    level.zp.hud_binds         = zp_cfg_int( "zp_hud_binds", 1 );

    // Black glow behind the text, the same thing the stock notify
    // messages use. Zombies skyboxes are bright and the HUD sits on top
    // of them; this is what keeps it readable.
    level.zp.hud_glow          = zp_cfg_int( "zp_hud_glow", 1 );

    /*
        Heavier alternative to the glow: a black slab behind the whole
        block. Off by default -- it is a lot of screen for a co-op pause,
        and the glow already carries the text on most maps.

        The width is a dvar because nothing here can measure a rendered
        string. Widen it if a long line overhangs the slab.
    */
    level.zp.hud_panel         = zp_cfg_int( "zp_hud_panel", 0 );
    level.zp.hud_panel_alpha   = zp_cfg_float( "zp_hud_panel_alpha", 0.45 );
    level.zp.hud_panel_width   = zp_cfg_int( "zp_hud_panel_width", 340 );

    // "paused by Xep -- 2:14" under the banner, counting up. Counts down
    // to the auto-resume instead when zp_max_pause_time is set.
    level.zp.hud_timer         = zp_cfg_int( "zp_hud_timer", 1 );

    /*
        Softer alternative to the blackout: setblur() is the same
        post-process the game runs when you buy a perk, which uses 4.
        1.5 reads as "the game has stepped back" without hiding it.
    */
    level.zp.blur              = zp_cfg_int( "zp_blur", 1 );
    level.zp.blur_amount       = zp_cfg_float( "zp_blur_amount", 2 );

    /*
        Stock aliases, so the script stays one drop-in file -- a custom
        sound would have to be installed by every player rather than just
        the host.

        T6's defaults are Black Ops II aliases and none of the three exist
        here, so these are the Black Ops III equivalents. The pause and
        resume sounds are the game's own: Killing Time plays
        killingtime_start when it stops the world and killingtime_end when
        it lets go, which is precisely what is happening. The tick is the
        final-countdown timer marker.

        Set any of them to "" for silence.
    */
    level.zp.pause_sound       = zp_cfg_str( "zp_pause_sound", "zmb_bgb_killingtime_start" );
    level.zp.countdown_sound   = zp_cfg_str( "zp_countdown_sound", "zmb_finalcountdown_timer_marker" );
    level.zp.resume_sound      = zp_cfg_str( "zp_resume_sound", "zmb_bgb_killingtime_end" );

    // Drift guard tolerance, in units squared. 64 = 8 units.
    level.zp.drift_tolerance   = 64;
}

/*
    set_dvar_if_unset() (maps\mp\_utility) creates the dvar with our default
    the first time the config is read, and leaves alone anything already set
    in config.cfg. Creating it is the point: the console can only assign to a
    dvar that already exists, so a read-only getdvar would leave every setting
    unreachable from in game.
*/
zp_cfg_int( dvar, def )
{
    return int( zp_cfg_echo( dvar, set_dvar_if_unset( dvar, "" + def ), def ) );
}

zp_cfg_float( dvar, def )
{
    return float( zp_cfg_echo( dvar, set_dvar_if_unset( dvar, "" + def ), def ) );
}

/*
    "none" is how a string setting is emptied in game. set_dvar_if_unset()
    takes an empty dvar for one that was never set and writes the default
    straight back, so "" typed into the console lasted until the next read,
    and the settings menu has no other way to write nothing.
*/
zp_cfg_str( dvar, def )
{
    value = zp_cfg_echo( dvar, set_dvar_if_unset( dvar, def ), def );

    if ( value == "none" )
        return "";

    return value;
}


/* ==================================================================
    INPUT -- CHAT

    Black Ops III raises the notify; nothing in the dump listens for it,
    which is only absence -- and absence is what had this port documented
    as button-only for a year. It arrives on the player rather than on
    level, with the message as its one argument:

        self waittill( "say", message )

    so the listener is one per player, started by zp_player_think() and
    ended with them. Every route carries it: stock and the Workshop build
    from the engine itself, BOIII and T7x because their own chat handlers
    re-raise it after taking their turn with it.

    "say_team" and "chat" are raised the same way and are not listened
    for, which keeps this to the one notify T6 binds.
   ================================================================== */

zp_chat_listener()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for (;;)
    {
        self waittill( "say", message );

        if ( !isdefined( message ) )
            continue;

        msg = tolower( message );

        if ( zp_true( level.zp_vote_active ) && zp_is_no_word( msg ) )
            zp_cast_vote( self, 0 );
        else if ( zp_true( level.zp_vote_active ) && zp_is_yes_word( msg ) )
            zp_cast_vote( self, 1 );
        else if ( zp_is_pause_word( msg ) )
            level thread zp_request_toggle( self );
        else if ( zp_is_unpause_word( msg ) )
            level thread zp_request_unpause( self );
    }
}

/*
    Every comparison is done twice, once on the raw string and once on the
    string less its first character. Plutonium hands T6 the message behind
    a stray control character, and BOIII and T7x strip a leading character
    of their own before re-raising the notify; which shape arrives here
    depends on the route, and this costs nothing to cover both.
*/
zp_word_is( msg, token )
{
    if ( msg == token )
        return 1;

    /*
        Only when that first character is not one a word is made of. It
        used to be dropped from anything: with a vote open "my" and "by"
        cast a yes, "on", "in", "an" and "un" cast a no, and "eyes" was a
        yes. A control character or a prefix is what this is for.
    */
    if ( msg.size > 1
         && !issubstr( "abcdefghijklmnopqrstuvwxyz0123456789", getsubstr( msg, 0, 1 ) )
         && getsubstr( msg, 1 ) == token )
        return 1;

    return 0;
}

zp_is_pause_word( msg )
{
    if ( zp_word_is( msg, "!pause" ) )
        return 1;

    if ( zp_word_is( msg, "!p" ) )
        return 1;

    if ( level.zp.allow_short_words )
    {
        if ( zp_word_is( msg, "pause" ) )
            return 1;

        if ( zp_word_is( msg, "p" ) )
            return 1;
    }

    return 0;
}

zp_is_unpause_word( msg )
{
    if ( zp_word_is( msg, "!unpause" ) )
        return 1;

    if ( zp_word_is( msg, "!resume" ) )
        return 1;

    if ( zp_word_is( msg, "!u" ) )
        return 1;

    if ( level.zp.allow_short_words )
    {
        if ( zp_word_is( msg, "unpause" ) )
            return 1;

        if ( zp_word_is( msg, "resume" ) )
            return 1;

        if ( zp_word_is( msg, "u" ) )
            return 1;
    }

    return 0;
}

/*
    Only consulted while a vote is open, so the bare forms cannot cast
    anything during normal conversation.
*/
zp_is_yes_word( msg )
{
    if ( zp_word_is( msg, "!yes" ) )
        return 1;

    if ( zp_word_is( msg, "!y" ) )
        return 1;

    if ( zp_word_is( msg, "yes" ) )
        return 1;

    if ( zp_word_is( msg, "y" ) )
        return 1;

    return 0;
}

zp_is_no_word( msg )
{
    if ( zp_word_is( msg, "!no" ) )
        return 1;

    if ( zp_word_is( msg, "!n" ) )
        return 1;

    if ( zp_word_is( msg, "no" ) )
        return 1;

    if ( zp_word_is( msg, "n" ) )
        return 1;

    return 0;
}

/* ==================================================================
    INPUT -- BUTTON COMBO (crouch/prone + melee by default)

    freezecontrols() blocks movement and weapon use but the button state
    still reaches the server, so this keeps working while paused. That is
    what lets a frozen player unpause without touching chat.
   ================================================================== */

/*
    Every combo the script can watch for, in one place. stancebuttonpressed()
    is crouch and prone both, which is why the yes combo covers either.
*/
zp_combo_pressed( combo )
{
    if ( combo == "crouch_use" )
        return self stancebuttonpressed() && self usebuttonpressed();

    if ( combo == "crouch_frag" )
        return self stancebuttonpressed() && self fragbuttonpressed();

    if ( combo == "crouch_ads" )
        return self stancebuttonpressed() && self adsbuttonpressed();

    if ( combo == "crouch_melee" )
        return self stancebuttonpressed() && self meleebuttonpressed();

    // The two buttons that survive last stand and spectating.
    if ( combo == "use_frag" )
        return self usebuttonpressed() && self fragbuttonpressed();

    // Deliberately excludes use, so it cannot fire while use_frag is held.
    if ( combo == "frag_only" )
        return self fragbuttonpressed() && !( self usebuttonpressed() );

    if ( combo == "use_ads" )
        return self usebuttonpressed() && self adsbuttonpressed();

    if ( combo == "use_attack" )
        return self usebuttonpressed() && self attackbuttonpressed();

    if ( combo == "attack_ads" )
        return self attackbuttonpressed() && self adsbuttonpressed();

    return self jumpbuttonpressed() && self meleebuttonpressed();
}

zp_combo_label( combo, binds )
{
    if ( zp_true( binds ) )
        return zp_combo_binds( combo );

    if ( combo == "crouch_use" )
        return "crouch + use";

    if ( combo == "crouch_frag" )
        return "crouch + grenade";

    if ( combo == "crouch_ads" )
        return "crouch + aim";

    if ( combo == "crouch_melee" )
        return "crouch + melee";

    if ( combo == "use_frag" )
        return "use + grenade";

    if ( combo == "frag_only" )
        return "grenade";

    if ( combo == "use_ads" )
        return "use + aim";

    if ( combo == "use_attack" )
        return "use + fire";

    if ( combo == "attack_ads" )
        return "fire + aim";

    return "jump + melee";
}

/*
    The same table as button glyphs. Anything unbound draws as the macro's
    own fallback rather than breaking the line, so a wrong guess here is
    cosmetic -- zp_hud_binds 0 goes back to words.
*/
zp_combo_binds( combo )
{
    if ( combo == "crouch_use" )
        return "[{+stance}] + [{+activate}]";

    if ( combo == "crouch_frag" )
        return "[{+stance}] + [{+frag}]";

    if ( combo == "crouch_ads" )
        return "[{+stance}] + [{+speed_throw}]";

    if ( combo == "crouch_melee" )
        return "[{+stance}] + [{+melee}]";

    if ( combo == "use_frag" )
        return "[{+activate}] + [{+frag}]";

    if ( combo == "frag_only" )
        return "[{+frag}]";

    if ( combo == "use_ads" )
        return "[{+activate}] + [{+speed_throw}]";

    if ( combo == "use_attack" )
        return "[{+activate}] + [{+attack}]";

    if ( combo == "attack_ads" )
        return "[{+attack}] + [{+speed_throw}]";

    return "[{+gostand}] + [{+melee}]";
}

/*
    Bled out and spectating. This is the electorate question -- who the vote
    maths runs over -- and it is deliberately not the same as the input
    question below: a downed player is still alive and still voting.
*/
zp_player_is_spectating( player )
{
    if ( !isdefined( player ) )
        return 0;

    if ( isdefined( player.sessionstate ) && player.sessionstate == "spectator" )
        return 1;

    return !isalive( player );
}

/*
    Whether the normal combo can still reach the server. You cannot crouch
    or melee from the floor, and once you are spectating the engine stops
    delivering those buttons at all -- stock last stand code reads
    usebuttonpressed() and nothing else, which is the tell for both states.
*/
zp_player_input_limited( player )
{
    if ( !isdefined( player ) )
        return 0;

    if ( zp_true( player.laststand ) )
        return 1;

    return zp_player_is_spectating( player );
}

zp_active_combo( up_combo, dead_combo )
{
    if ( !isdefined( dead_combo ) || dead_combo == "" )
        return up_combo;

    if ( !zp_player_input_limited( self ) )
        return up_combo;

    return dead_combo;
}

zp_button_watcher()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for (;;)
    {
        wait 0.05;

        if ( !level.zp.button_combo )
            continue;

        // The host's menu reads these buttons while it is open.
        if ( zp_true( self.zp_menu_open ) )
            continue;

        combo = self zp_active_combo( level.zp.combo, level.zp.button_combo_dead );

        if ( !( self zp_combo_pressed( combo ) ) || self zp_menu_combo_held() )
            continue;

        // Require a short hold so a crouch-melee in normal play does
        // not pause the game by accident.
        held = 0;
        while ( ( self zp_combo_pressed( combo ) ) && !( self zp_menu_combo_held() ) && held < level.zp.button_hold_time )
        {
            held = held + 0.05;
            wait 0.05;
        }

        if ( held < level.zp.button_hold_time || self zp_menu_combo_held() )
            continue;

        level thread zp_request_toggle( self );

        // Debounce: wait for release, then a beat.
        while ( self zp_combo_pressed( combo ) )
            wait 0.05;

        wait 0.5;
    }
}


/*
    Troubleshooting aid. zp_input_debug 1 gives every player a readout of
    which buttons the server is actually receiving from them and what state
    they are in, printed only when the set changes.

    Which buttons survive last stand and spectating is the whole difficulty
    behind zp_button_combo_dead, and it varies by build -- this answers it
    in one game rather than by inference.
*/
zp_input_debug_watcher()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    last = "";

    for (;;)
    {
        wait 0.25;

        if ( !level.zp.input_debug )
            continue;

        txt = "";

        if ( self usebuttonpressed() )
            txt = txt + "use ";

        if ( self attackbuttonpressed() )
            txt = txt + "fire ";

        if ( self adsbuttonpressed() )
            txt = txt + "aim ";

        if ( self meleebuttonpressed() )
            txt = txt + "melee ";

        if ( self stancebuttonpressed() )
            txt = txt + "stance ";

        if ( self jumpbuttonpressed() )
            txt = txt + "jump ";

        if ( self fragbuttonpressed() )
            txt = txt + "frag ";

        if ( self secondaryoffhandbuttonpressed() )
            txt = txt + "offhand ";

        if ( txt == last )
            continue;

        last = txt;

        if ( txt == "" )
            continue;

        state = "up";

        if ( zp_true( self.laststand ) )
            state = "^3laststand";
        else if ( zp_player_is_spectating( self ) )
            state = "^3spectating";

        self iprintln( "^5[input]^7 " + state + "^7: " + txt );
    }
}

/*
    The no half of the button voting. Idle unless a vote is actually open,
    so the combo is inert during normal play -- which is what lets it be a
    combo you could otherwise hit by accident.
*/
zp_vote_no_watcher()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for (;;)
    {
        wait 0.05;

        if ( !zp_true( level.zp_vote_active ) || !level.zp.button_combo )
            continue;

        if ( zp_true( self.zp_menu_open ) )
            continue;

        combo = self zp_active_combo( level.zp.vote_no_combo, level.zp.vote_no_combo_dead );

        if ( !( self zp_combo_pressed( combo ) ) )
            continue;

        held = 0;
        while ( zp_true( level.zp_vote_active ) && ( self zp_combo_pressed( combo ) ) && held < level.zp.button_hold_time )
        {
            held = held + 0.05;
            wait 0.05;
        }

        if ( held < level.zp.button_hold_time )
            continue;

        zp_cast_vote( self, 0 );

        while ( self zp_combo_pressed( combo ) )
            wait 0.05;

        wait 0.5;
    }
}


/* ==================================================================
    REQUEST GATES
   ================================================================== */

zp_game_ready()
{
    if ( zp_true( level.gameended ) )
        return 0;

    /*
        Same flag as T6, and this is the first engine in the chain where
        that was true -- T5 wanted "begin_spawning" and T4
        "all_players_spawned". _zm.gsc flag::init()s it during setup.
    */
    if ( !level flag::exists( "initial_blackscreen_passed" ) )
        return 0;

    if ( !level flag::get( "initial_blackscreen_passed" ) )
        return 0;

    return 1;
}

zp_on_cooldown()
{
    return gettime() - level.zp_last_toggle < level.zp.cooldown * 1000;
}

/*
    The host, or undefined when there is not one.

    Black Ops III ships this test itself, in util_shared, and the engine's
    own answer beats a guess at one: gethostplayer() walks the players
    asking isHost(), where this used to check for entity number 0. That is
    what stock get_host() does on the older engines, and it is why the
    other three ports still do it, but nothing says Black Ops III numbers
    its players the same way.
*/
zp_host_player()
{
    return util::gethostplayer();
}

/*
    True when zp_host_only should turn this request away. Says so once
    rather than failing silently, since a combo that does nothing reads as
    a broken mod.
*/
zp_host_blocked( player )
{
    if ( !level.zp.host_only )
        return 0;

    host = zp_host_player();

    // Nobody is the host, so there is nothing to restrict to.
    if ( !isdefined( host ) )
        return 0;

    if ( isdefined( player ) && player == host )
        return 0;

    if ( isdefined( player ) )
        player zp_say( "MSG_HOST_ONLY" );

    return 1;
}

/*
    Whether this match has spent its zp_max_pauses.
*/
zp_pauses_spent()
{
    return level.zp.max_pauses > 0 && level.zp_pause_count >= level.zp.max_pauses;
}

/*
    Somebody dropping mid-round leaves the rest of the team to be overrun,
    and on these clients they can come back -- so hold the game while they
    do.

    Threaded per player and deliberately outside zp_player_think(), which
    carries endon( "disconnect" ): the whole job of this one is to still be
    running after that has fired.
*/
zp_disconnect_watcher()
{
    level endon( "end_game" );

    self waittill( "disconnect" );

    // Read fresh: this waits for the whole match before it decides.
    zp_load_config();

    /*
        Somebody who paused by opening their menu and then left is not
        going to close it again, so the game is handed back for them.
    */
    /*
        A player who leaves is out of the room's menus whether or not
        theirs is what paused the game.
    */
    if ( zp_menu_synced() && zp_true( self.zp_in_pause_menu ) )
    {
        self.zp_in_pause_menu = undefined;
        self.zp_menu_seen = undefined;
        self.zp_menu_paused = undefined;
        zp_menu_sync_apply();
        return;
    }

    if ( zp_true( self.zp_menu_paused ) )
    {
        self.zp_menu_paused = undefined;
        self.zp_in_pause_menu = undefined;

        if ( zp_true( level.zp_paused ) && !zp_true( level.zp_busy ) )
        {
            level.zp_last_toggle = gettime();
            level thread zp_do_unpause( undefined, "a closed menu" );
        }
    }

    /*
        One fewer player is one fewer ready press needed, and the tally
        is only ever recounted by somebody pressing ready. Everybody left
        having already pressed it meant the count could never be taken
        again and the game stayed paused for good.
    */
    if ( zp_true( level.zp_paused ) && level.zp.ready_check )
        level thread zp_mark_ready( undefined );

    if ( !level.zp.pause_on_disconnect )
        return;

    if ( zp_true( level.zp_paused ) || zp_true( level.zp_busy ) || !zp_game_ready() )
        return;

    players = getplayers();

    // Nobody left to start it again.
    if ( players.size < 1 )
        return;

    zp_say_all( "MSG_DROPPED_PAUSED" );
    level.zp_last_toggle = gettime();
    level thread zp_do_pause( undefined );
}

zp_ready_show( have, needed )
{
    // The sub-line is the natural place: it is otherwise telling people to
    // hold a combo to resume, which is not what the combo does right now.
    if ( have < 1 && needed < 1 )
    {
        level.zp_hud_sub_override = undefined;
        return;
    }

    level.zp_hud_sub_override = "HUD_READY_COUNT";
    level.zp_hud_sub_override_a = have;
    level.zp_hud_sub_override_b = needed;
}

/*
    The last step of a pause request, once whatever had to agree has agreed.
    Either it happens now, or it waits for the round to be over.

    Both the direct path and a vote that passed come through here. A player
    dropping does not: that calls zp_do_pause() itself, since waiting for
    the round to end is the opposite of what is wanted there.
*/
zp_begin_pause( player )
{
    if ( !level.zp.round_pause )
    {
        level thread zp_do_pause( player );
        return;
    }

    level.zp_pending = 1;
    level.zp_pending_by = player;

    zp_say_all( "MSG_ROUND_END_PENDING" );
}

/*
    Fires the held pause at the round boundary.
*/
zp_round_watcher()
{
    level endon( "end_game" );

    for (;;)
    {
        level waittill( "end_of_round" );

        if ( !zp_true( level.zp_pending ) )
            continue;

        level.zp_pending = 0;
        by = level.zp_pending_by;
        level.zp_pending_by = undefined;

        zp_load_config();

        if ( zp_true( level.zp_paused ) || zp_true( level.zp_busy ) || !zp_game_ready() )
            continue;

        level.zp_last_toggle = gettime();
        level thread zp_do_pause( by );
    }
}

zp_ready_clear()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i].zp_ready = undefined;
    }

    zp_ready_show( 0, 0 );
}

zp_ready_count()
{
    players = getplayers();
    c = 0;

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) && zp_true( players[i].zp_ready ) )
            c++;
    }

    return c;
}

zp_ready_needed()
{
    players = getplayers();
    n = players.size;

    if ( n < 1 )
        return 1;

    needed = int( ceil( n * level.zp.ready_percent / 100 ) );

    // Never ask for more people than are here to answer.
    if ( needed > n )
        needed = n;

    if ( needed < 1 )
        needed = 1;

    return needed;
}

/*
    Somebody saying they are back. The resume input marks instead of
    resuming while zp_ready_check is on, so the last one to press it is
    what starts the game again.
*/
zp_mark_ready( player )
{
    if ( isdefined( player ) )
    {
        if ( zp_true( player.zp_ready ) )
            return;

        player.zp_ready = 1;
        player zp_say( "MSG_READY" );
    }

    needed = zp_ready_needed();
    have = zp_ready_count();

    if ( have < needed )
    {
        zp_ready_show( have, needed );
        return;
    }

    zp_ready_show( 0, 0 );
    level.zp_last_toggle = gettime();
    level thread zp_do_unpause( player, "everyone ready" );
}

zp_request_toggle( player )
{
    // A player in a personal pause is always asking to come back, whatever
    // the rest of the game is doing.
    if ( zp_true( level.zp_paused ) || ( isdefined( player ) && zp_true( player.zp_personal ) ) )
        zp_request_unpause( player );
    else
        zp_request_pause( player );
}

zp_request_pause( player )
{
    /*
        Loaded here as well as below so turning zp_host_only on takes
        effect on the next attempt rather than the one after it.
    */
    zp_load_config();

    // Ahead of zp_host_only and the vote: a personal pause holds nobody
    // but the player asking for it.
    if ( level.zp.personal_pause && isdefined( player ) )
    {
        zp_personal_start( player );
        return;
    }

    if ( zp_host_blocked( player ) )
        return;

    if ( zp_true( level.zp_busy ) || zp_true( level.zp_paused ) )
        return;

    // A vote already running turns any further pause input into a yes.
    if ( zp_true( level.zp_vote_active ) )
    {
        zp_cast_vote( player, 1 );
        return;
    }

    if ( !zp_game_ready() )
    {
        if ( isdefined( player ) )
            player zp_say( "MSG_NOT_YET" );

        return;
    }

    /*
        A second ask calls off a pause that is waiting for the round to end,
        so the same input both sets it and takes it back.

        Whoever armed it, or the host. It sits ahead of the vote and the
        host-approval gates, so anybody being allowed to cancel meant one
        player quietly undoing what the room had just voted for.

        The name in the refusal goes over as the player: zp_text_player()
        and the localized zp_loc_player() both fall back to "someone" for
        an armer who has since left.
    */
    if ( zp_true( level.zp_pending ) )
    {
        if ( isdefined( player ) && isdefined( level.zp_pending_by )
             && player != level.zp_pending_by && !zp_player_is_host( player ) )
        {
            player zp_say( "MSG_ROUND_END_NOT_YOURS", level.zp_pending_by );
            return;
        }

        level.zp_pending = 0;
        level.zp_pending_by = undefined;
        zp_say_all( "MSG_ROUND_END_OFF" );
        return;
    }

    if ( zp_pauses_spent() )
    {
        if ( isdefined( player ) )
            player zp_say( "MSG_NO_PAUSES_LEFT" );

        return;
    }

    if ( zp_on_cooldown() )
        return;

    // Read the dvars here rather than in zp_do_pause() alone, so a host
    // turning zp_vote on mid-game does not have to pause once first.
    zp_load_config();

    if ( zp_vote_wanted( player ) )
    {
        if ( zp_vote_locked_out() )
        {
            if ( isdefined( player ) )
                player zp_say( "MSG_VOTE_COOLDOWN" );

            return;
        }

        level.zp_last_toggle = gettime();
        level thread zp_vote_start( player, "pause" );
        return;
    }

    level.zp_last_toggle = gettime();
    zp_begin_pause( player );
}

zp_request_unpause( player )
{
    /*
        Loaded here as well as below so turning zp_host_only on takes
        effect on the next attempt rather than the one after it.
    */
    zp_load_config();

    /*
        Coming back from a personal pause answers to nobody, and it is read
        whether or not zp_personal_pause is still on, so turning it off
        cannot leave somebody held with no way out.

        While the whole game is held because nobody was left playing, it is
        the players who paused who bring it back -- zp_personal_watcher()
        resumes it the moment one of them returns. Anybody else pressing
        resume is told as much rather than ignored.
    */
    if ( isdefined( player ) && zp_true( player.zp_personal ) )
    {
        zp_personal_resume( player );
        return;
    }

    if ( zp_true( level.zp_personal_hold ) )
    {
        if ( isdefined( player ) )
            player zp_say( "MSG_PERSONAL_WAITING" );

        return;
    }

    if ( zp_host_blocked( player ) )
        return;

    if ( zp_true( level.zp_busy ) || !zp_true( level.zp_paused ) )
        return;

    // Same as the pause side: with a vote open, the combo is a ballot.
    if ( zp_true( level.zp_vote_active ) )
    {
        zp_cast_vote( player, 1 );
        return;
    }

    /*
        "thread" starts running immediately in GSC, so two toggles landing
        in the same frame -- two players hitting the combo at once -- would
        otherwise pause and then instantly unpause again.
    */
    if ( zp_on_cooldown() )
        return;

    zp_load_config();

    if ( level.zp.ready_check )
    {
        zp_mark_ready( player );
        return;
    }

    if ( level.zp.vote && level.zp.vote_unpause && !zp_vote_is_moot( player ) )
    {
        if ( zp_vote_locked_out() )
        {
            if ( isdefined( player ) )
                player zp_say( "MSG_VOTE_COOLDOWN" );

            return;
        }

        level.zp_last_toggle = gettime();
        level thread zp_vote_start( player, "unpause" );
        return;
    }

    level.zp_last_toggle = gettime();
    level thread zp_do_unpause( player );
}


/* ==================================================================
    PAUSE
   ================================================================== */

/*
    A quarter speed. Slow enough to read as deliberate, far enough from
    zero that a script wait during the ramp still completes promptly.
*/
zp_ease_scale()
{
    return 0.25;
}

zp_ease_in()
{
    if ( !level.zp.ease || level.zp.ease_time <= 0 )
        return;

    setslowmotion( 1, zp_ease_scale(), level.zp.ease_time );
    wait( level.zp.ease_time );
}

/*
    Called once the world is held. Nothing is moving, so putting time back
    to normal here cannot be seen -- and it means the pause itself runs at
    ordinary speed however long it lasts.
*/
zp_ease_settle()
{
    if ( !level.zp.ease || level.zp.ease_time <= 0 )
        return;

    setslowmotion( zp_ease_scale(), 1, 0 );
}

/*
    The mirror: drop to the eased rate while everything is still held --
    invisible, same as the settle -- so that releasing the world ramps up
    from slow instead of starting at full speed.
*/
zp_ease_out()
{
    if ( !level.zp.ease || level.zp.ease_time <= 0 )
        return;

    setslowmotion( 1, zp_ease_scale(), 0 );
}

zp_ease_release()
{
    if ( !level.zp.ease || level.zp.ease_time <= 0 )
        return;

    setslowmotion( zp_ease_scale(), 1, level.zp.ease_time );
}

zp_do_pause( player, name )
{
    // Pick up any dvar the host changed since the last pause, so config
    // edits do not need a map restart.
    zp_load_config();

    level.zp_busy = 1;
    level.zp_paused = 1;
    level.zp_pause_start = gettime();
    level.zp_held_vars = [];

    /*
        name is who to credit when nobody pressed anything -- the personal
        pauses holding the whole game give "the team". A name cannot go
        through the text table the way a player does -- the Workshop build
        hands a player over for each client to name in its own language --
        so the team has lines of its own, and zp_pauser_team picks them.
    */
    level.zp_pauser_name = "someone";
    level.zp_pauser_team = undefined;
    if ( isdefined( player ) && isdefined( player.name ) )
        level.zp_pauser_name = player.name;
    else if ( isdefined( name ) )
    {
        level.zp_pauser_name = name;
        level.zp_pauser_team = 1;
    }
    level.zp_pauser = player;

    /*
        Only a pause somebody asked for counts against zp_max_pauses. An
        automatic one -- a player dropping -- is not theirs to spend.
    */
    if ( isdefined( player ) )
        level.zp_pause_count = level.zp_pause_count + 1;

    zp_ready_clear();

    level.zp_counting_down = undefined;
    level notify( "zp_paused" );

    // 0. Ease time down, so the stop reads as deliberate rather than as a
    //    hitch. Time is put back at the end of this function, once
    //    everything is held and the change cannot be seen.
    zp_ease_in();

    // 1. Close the spawner gate. This is the flag _zm.gsc's spawn loop
    //    blocks on, and the same one host migration clears.
    /*
        Belt and braces. round_spawning() already blocks on
        "world_is_paused", which zp_engine_zombies() sets -- but closing
        the gate too costs nothing and keeps the behaviour identical to
        the other ports if a map replaces the spawn loop.
    */
    level.zp_spawn_flag_was_set = 0;
    if ( level flag::exists( "spawn_zombies" ) && level flag::get( "spawn_zombies" ) )
    {
        level.zp_spawn_flag_was_set = 1;
        level flag::clear( "spawn_zombies" );
    }

    // 2. Engine-level AI freeze. Threaded on its own so that even an
    //    unexpected failure here cannot wedge the state machine.
    level.zp_engine_held = level.zp.engine_freeze;

    if ( level.zp_engine_held )
        level thread zp_engine_zombies( 0 );

    // 3. Hold every AI in place, including anything that appears later.
    level thread zp_ai_enforcer();

    //    Cosmetic pose swap, after the engine freeze so nothing overwrites it.
    if ( level.zp.freeze_anims )
        level thread zp_anim_freeze_pass();

    // 4. Lock the players, and keep them locked.
    players = getplayers();
    for ( i = 0; i < players.size; i++ )
        players[i] zp_freeze_player();

    if ( level.zp.control_guard )
        level thread zp_player_enforcer();

    // 5. Hold the clocks.
    if ( level.zp.freeze_clock )
        level thread zp_clock_locker();

    if ( level.zp.freeze_powerups || level.zp.freeze_effects )
        level thread zp_powerup_enforcer();

    if ( level.zp.freeze_bleedout )
        level thread zp_bleedout_enforcer();

    /*
        6. Tell everybody -- unless this is zp_vote_hold's provisional
        pause, where the vote HUD is the one on screen. zp_vote_start()
        takes the pause HUD down for that reason, and putting it straight
        back left the banner naming the resume combo while that same
        combo was a yes vote. zp_vote_finish() gives it back if the vote
        carries.
    */
    if ( !zp_true( level.zp_vote_provisional ) )
        level thread zp_hud_show();

    if ( zp_true( level.zp_pauser_team ) )
        zp_say_all( "MSG_PAUSED_BY_TEAM" );
    else
        zp_say_all( "MSG_PAUSED_BY", level.zp_pauser );

    level thread zp_sound_all( level.zp.pause_sound );

    /*
        Not for the whole-game hold the personal pauses make: each of
        those has zp_max_pause_time running on its own, and the first to
        run out brings a player back and the game with them. Timing this
        one as well resumed a game with everybody still away, which the
        watcher paused again straight away, over and over.
    */
    if ( level.zp.max_pause_time > 0 && !zp_true( level.zp_personal_hold ) )
        level thread zp_auto_unpause();

    // Everything is held now, so normal time is invisible from here.
    zp_ease_settle();

    level.zp_busy = 0;
}


/* ==================================================================
    UNPAUSE
   ================================================================== */

zp_do_unpause( player, label )
{
    level endon( "end_game" );

    /*
        Nothing resumes a game that is already running. The auto-resume
        and a vote that passes can both arrive after the game came back
        -- a resume vote still open when zp_max_pause_time expires is the
        way in -- and without this the second one runs the whole thing
        again in live play: the chat line, the countdown with everybody
        held, and the timescale dropping and ramping back.
    */
    if ( !zp_true( level.zp_paused ) )
        return;

    level.zp_busy = 1;

    if ( isdefined( player ) && isdefined( player.name ) )
        zp_say_all( "MSG_RESUMING_BY", player );
    else if ( isdefined( label ) && label == "everyone ready" )
        zp_say_all( "MSG_RESUMING_READY" );
    else if ( isdefined( label ) && label == "vote failed" )
        zp_say_all( "MSG_RESUMING_VOTE_FAILED" );
    else if ( isdefined( label ) && label == "nobody left away" )
        zp_say_all( "MSG_RESUMING_NOBODY_AWAY" );
    else if ( isdefined( label ) && label == "a closed menu" )
        zp_say_all( "MSG_RESUMING_MENU_CLOSED" );
    else if ( !isdefined( player ) )
        zp_say_all( "MSG_RESUMING_AUTO" );
    else
        zp_say_all( "MSG_RESUMING_BY" );

    // Countdown. Everything stays frozen for the whole countdown, so
    // nobody gets to reposition against held zombies.
    cd = level.zp.countdown;

    /*
        A pause the room's menus were holding ends the moment the last one
        closes: that player's own game is running again already, and a
        countdown would hold everybody else behind a client that has gone.
        A combo pause in the same mode still counts down, because nothing
        about it was in step with a client to begin with.
    */
    if ( zp_true( level.zp_menu_sync_held ) )
        cd = 0;

    level.zp_menu_sync_held = undefined;

    // One line for everybody for the duration of the countdown -- the
    // per-player combo hint has nothing to say while nobody may move.
    // Anyone who was roaming is locked for the countdown, so the game
    // comes back from where everybody stands. See zp_hold_controls.
    level.zp_counting_down = 1;
    zp_hold_everyone();

    level.zp_hud_sub_override = "HUD_HOLD_STILL";
    level.zp_hud_sub_override_a = undefined;
    level.zp_hud_sub_override_b = undefined;
    zp_hud_sub_refresh();

    while ( cd > 0 )
    {
        if ( isdefined( level.zp_hud ) )
            zp_show( level.zp_hud, "HUD_RESUMING_IN", cd );

        level thread zp_sound_all( level.zp.countdown_sound );
        wait 1;
        cd = cd - 1;
    }

    // Drop to the eased rate before anything moves, so the world starts
    // slow and ramps up rather than snapping to full speed.
    zp_ease_out();

    // Stop every enforcer thread at once, then reverse the pause.
    level notify( "zp_thaw" );

    // What the pause did, not what the setting says by now: the console
    // or the host's menu can change it in between.
    if ( zp_true( level.zp_engine_held ) )
        level thread zp_engine_zombies( 1 );

    zp_ai_thaw();
    level.zp_engine_held = undefined;

    // Unconditional, keyed on each zombie's own flag, so turning
    // zp_freeze_anims off mid-pause can never strand one in the pose.
    level thread zp_anim_thaw_pass();

    zp_powerups_thaw();
    zp_effects_thaw();
    zp_bleedout_thaw();

    players = getplayers();
    for ( i = 0; i < players.size; i++ )
        players[i] zp_unfreeze_player();

    level thread zp_sound_all( level.zp.resume_sound );
    zp_ease_release();

    if ( zp_true( level.zp_spawn_flag_was_set ) )
    {
        if ( level flag::exists( "spawn_zombies" ) )
            level flag::set( "spawn_zombies" );
    }
    level.zp_spawn_flag_was_set = 0;

    zp_hud_destroy();

    // A resume vote still open when the game comes back has nothing left
    // to decide, and leaving it open turns every pause request into a
    // ballot on a question that has already been answered.
    if ( zp_true( level.zp_vote_active ) )
        zp_vote_stop();

    level.zp_personal_hold = undefined;
    level.zp_paused = 0;
    level.zp_last_toggle = gettime();
    level.zp_busy = 0;

    level notify( "zp_unpaused" );
}

zp_auto_unpause()
{
    level endon( "zp_thaw" );
    level endon( "end_game" );

    wait( level.zp.max_pause_time );

    level thread zp_do_unpause( undefined );
}


/* ==================================================================
    THE GAME'S OWN PAUSE MENU

    zp_pause_menu. Opening it presses pause and closing it presses
    resume, so everything that decides a pause decides this one too.

    Black Ops III tells a script nothing about a player opening a menu, so
    the mod's own Lua sends it: zpausepausemenu.lua wraps
    LUI.createMenu.StartMenu_Main -- the in-game menu itself -- and calls
    Engine.SendMenuResponse() with the menu name "zpause", which arrives
    here as a "menuresponse" notify on that player. The game's own menus
    talk to a running match the same way: the leave-game popup sends
    ( "popup_leavegame", "endround" ) and the restart one sends
    ( "restartgamepopup", "restart_level_zm" ). Nothing in the stock
    scripts reads the menu name "zpause" or either response below --
    _zm_gametype.gsc's handler branches on the response, and none of the
    words it tests is one of these.

    Every route but the t7-compiler's. The Workshop build carries the Lua
    in core_mod, which loads in every mode; BOIII, Ezz BOIII and T7x load
    it from ui_scripts, which the client runs in a match as well as in the
    frontend. An injected script reaches a stock client that loads no Lua
    at all, so that route has the combo and the chat commands and not this.

    Each player's own game reports their own menu, so a player without
    ZPause opening theirs pauses nothing -- and a solo game is left alone,
    because Black Ops III pauses one by itself when that menu opens.
   ================================================================== */

zp_pause_menu_watcher()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for (;;)
    {
        self waittill( "menuresponse", menu, response );

        if ( !isdefined( menu ) || menu != "zpause" || !isdefined( response ) )
            continue;

        if ( response == "pause_menu_open" )
            self zp_pause_menu_opened();
        else if ( response == "pause_menu_closed" )
            self zp_pause_menu_closed();
        else if ( response == "pause_menu_alive" )
            self zp_pause_menu_alive();
        else
            self zp_api_menu_request( response );
    }
}

/*
    Still open. The beat also stands in for an open the script never got:
    a response dropped, or this build starting while a menu was already
    on screen.
*/
zp_pause_menu_alive()
{
    self.zp_menu_seen = gettime();

    if ( !zp_true( self.zp_in_pause_menu ) )
        self zp_pause_menu_opened();
}

zp_pause_menu_opened()
{
    zp_load_config();

    if ( !zp_menu_on() || zp_true( self.zp_in_pause_menu ) )
        return;

    // Who may pause at all is still zp_host_only's to say.
    if ( zp_menu_synced() && !zp_menu_sync_allowed( self ) )
        return;

    self.zp_in_pause_menu = 1;

    if ( zp_menu_synced() )
    {
        zp_menu_sync_apply();
        return;
    }

    was_paused = zp_true( level.zp_paused ) || zp_true( level.zp_pending );
    was_away = zp_true( self.zp_personal );

    /*
        The same request the combo makes, so a vote, the host's approval,
        the cooldown and zp_max_pauses all have their say -- and with
        zp_personal_pause on it is a personal pause, since that is what
        the pause input is then.
    */
    zp_request_pause( self );

    /*
        Whether that press is what paused the game. Only then does closing
        the menu resume it: a pause somebody else called is not this
        player's to end by walking out of a menu.
    */
    if ( zp_true( self.zp_personal ) && !was_away )
        self.zp_menu_paused = 1;
    else if ( zp_true( level.zp_paused ) && !was_paused )
        self.zp_menu_paused = 1;
}

zp_pause_menu_closed()
{
    if ( !zp_true( self.zp_in_pause_menu ) )
        return;

    self.zp_in_pause_menu = undefined;
    self.zp_menu_seen = undefined;

    if ( zp_menu_synced() )
    {
        zp_menu_sync_apply();
        return;
    }

    if ( !zp_true( self.zp_menu_paused ) )
        return;

    self.zp_menu_paused = undefined;

    // The resume input, with everything that decides one: a resume vote,
    // the ready check, the cooldown. A personal pause is simply theirs.
    zp_request_unpause( self );
}

/* ==================================================================
    THE ROOM'S MENUS

    zp_pause_menu 2. One pause menu open anywhere pauses for everybody,
    and the game comes back when the last one closes, so the vanilla
    pause works in a co-op game the way it does in solo.

    Mode 1 is one player's menu pressing pause the usual way, with
    everything that decides a pause having its say. Mode 2 is a mirror of
    what the clients are doing, and anything that can refuse or defer a
    press is what breaks a mirror: the vote, the cooldown, zp_max_pauses,
    zp_round_pause and the resume countdown all stand down for it, and a
    personal pause would hold the asker rather than the room. zp_host_only
    is the one that still has a say, because it decides who may pause at
    all rather than how often -- a player it blocks opens their menu
    without the room noticing.

    What does not arrive is the problem. Mode 1 can live with a close it
    never hears, since only the player who paused can resume and leaving
    the game hands it back for them; mode 2 would hold the match for the
    rest of its life. So the menu's own Lua beats twice a second from the
    timer it already runs, a player whose beat has stopped is dropped, and
    zp_menu_sync_watcher() reconciles the whole set once a second rather
    than trusting any single message. A beat from a menu the script does
    not have open is taken as an open it missed.

    A client whose Lua predates the beat is never dropped for silence --
    its open and close are all there is, and dropping it would be worse
    than trusting it. On this engine that is every route without the
    menu's Lua at all, which is the same set that has never had
    zp_pause_menu.
   ================================================================== */

/*
    Three named modes rather than three numbers: "off", "own" for your own
    menu pressing pause the usual way, and "room" for the game following
    everybody's. zp_cfg_str() reads "none" as empty on every port, and an
    empty one is off like any other unset setting.
*/
zp_menu_on()
{
    return level.zp.pause_menu != "" && level.zp.pause_menu != "off";
}

zp_menu_synced()
{
    return level.zp.pause_menu == "room";
}

/*
    zp_host_blocked() without the line it prints: this is asked every
    time a menu opens, and a blocked player does not need telling twice a
    match that they are not the host.
*/
zp_menu_sync_allowed( player )
{
    if ( !level.zp.host_only )
        return 1;

    host = zp_host_player();

    // Nobody is the host, so there is nothing to restrict to.
    if ( !isdefined( host ) )
        return 1;

    return isdefined( player ) && player == host;
}

/*
    Everybody with their pause menu open, in the order getplayers()
    gives them -- the same room always writes the same line, which is one
    configstring per set rather than one per press.
*/
zp_menu_open_players()
{
    out = [];
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( zp_true( players[i].zp_in_pause_menu ) )
            out[out.size] = players[i];
    }

    return out;
}

zp_menu_sync_names()
{
    open = zp_menu_open_players();
    names = "";

    for ( i = 0; i < open.size; i++ )
    {
        if ( !isdefined( open[i].name ) )
            continue;

        if ( names != "" )
            names = names + ", ";

        names = names + open[i].name;
    }

    if ( names == "" )
        names = "someone";

    return names;
}

/*
    The name line while the room's menus are what is holding the game.
    HUD_PAUSED_BY is "paused by &&1" in every language the mod ships, so
    the list goes in as its one argument and nothing new is translated.
*/
zp_menu_sync_hud()
{
    if ( !isdefined( level.zp_hud_meta ) )
        return;

    zp_show( level.zp_hud_meta, "HUD_PAUSED_BY", zp_menu_sync_names() );
}

/*
    Put the game where the room's menus say it should be. Called on every
    open and close and once a second besides, so a pause that could not
    start because the last one was still easing out is simply tried again
    rather than lost.
*/
zp_menu_sync_apply()
{
    if ( !zp_menu_synced() )
        return;

    open = zp_menu_open_players();

    if ( open.size > 0 )
    {
        /*
            Already held, and not by us: a combo, a vote, a disconnect.
            That pause stands and is nobody else's to narrate -- the name
            line belongs to whoever called it. If it ends while menus are
            still open, the next pass takes the game back.
        */
        if ( zp_true( level.zp_paused ) )
        {
            if ( zp_true( level.zp_menu_sync_held ) )
                zp_menu_sync_hud();

            return;
        }

        if ( zp_true( level.zp_busy ) || zp_true( level.zp_pending ) || !zp_game_ready() )
            return;

        level.zp_menu_sync_held = 1;
        level.zp_last_toggle = gettime();
        level thread zp_do_pause( open[0] );
        return;
    }

    /*
        Only what the menus are holding is handed back when they close.
        Every pause in the mod passes this test once a second, so without
        it a combo pause, a vote or zp_pause_on_disconnect lasted about a
        second while zp_pause_menu was "room" -- nobody had a menu open,
        so the reconciler resumed a pause it had never called.
    */
    if ( !zp_true( level.zp_menu_sync_held ) )
        return;

    if ( !zp_true( level.zp_paused ) || zp_true( level.zp_busy ) )
        return;

    level.zp_last_toggle = gettime();
    level thread zp_do_unpause( undefined, "the last menu closing" );
}

zp_menu_sync_watcher()
{
    level endon( "end_game" );

    for (;;)
    {
        wait 1;

        if ( !zp_menu_synced() )
            continue;

        players = getplayers();

        for ( i = 0; i < players.size; i++ )
        {
            if ( !zp_true( players[i].zp_in_pause_menu ) )
                continue;

            /*
                Never heard a beat from this one: its menu Lua is older
                than this build, so its open and close are all there is.
            */
            if ( !isdefined( players[i].zp_menu_seen ) )
                continue;

            if ( gettime() - players[i].zp_menu_seen < 4000 )
                continue;

            players[i].zp_in_pause_menu = undefined;
            players[i].zp_menu_seen = undefined;
            players[i].zp_menu_paused = undefined;
        }

        zp_menu_sync_apply();
    }
}


/* ==================================================================
    PERSONAL PAUSE

    zp_personal_pause. One player steps out of a game that carries on
    without them: frozen, protected, and ignored by every zombie -- the
    same hold a pause puts on everybody, put on one. The rest play on.

    The whole game pauses by itself once nobody is left playing, which is
    everybody else paused as well, or everybody still in it down -- a team
    that went down around somebody who had stepped away is held for them
    rather than lost. zp_personal_watcher() decides that, and resumes it
    the moment a player who paused comes back.
   ================================================================== */

/*
    Whether a player is in the game right now: on their feet, not
    spectating, and not personally paused. The whole game is held when
    this is nobody.

    .laststand and .revivetrigger are both _zm_laststand.gsc's own, set
    as a player goes down and cleared as they get up.
*/
zp_playable( p )
{
    if ( !isdefined( p ) || zp_true( p.zp_personal ) )
        return 0;

    if ( zp_player_is_spectating( p ) )
        return 0;

    if ( zp_true( p.laststand ) || isdefined( p.revivetrigger ) )
        return 0;

    return 1;
}

zp_personal_start( player )
{
    if ( zp_true( player.zp_personal ) )
        return;

    if ( !zp_game_ready() )
    {
        player zp_say( "MSG_NOT_YET" );
        return;
    }

    /*
        Not from the floor. Down, the pause would hold the bleedout while
        the team fought on -- a way to never bleed out rather than a way to
        step away. A team that is all down is held anyway, by the watcher.
    */
    if ( !zp_playable( player ) )
    {
        player zp_say( "MSG_PERSONAL_DOWN" );
        return;
    }

    if ( zp_pauses_spent() )
    {
        player zp_say( "MSG_NO_PAUSES_LEFT" );
        return;
    }

    // One press, one pause: the combo is still held on the next frame.
    if ( isdefined( player.zp_personal_last ) && gettime() - player.zp_personal_last < 1000 )
        return;

    player.zp_personal_last = gettime();
    level.zp_pause_count = level.zp_pause_count + 1;

    // Ends a countdown back in that is still running: they are staying.
    player notify( "zp_personal_on" );
    player zp_personal_hud_off();

    player.zp_personal = 1;
    player zp_freeze_player();
    player thread zp_personal_enforcer();

    // Under a whole-game pause the pause banner is the one on screen;
    // zp_personal_watcher() puts this back when it ends.
    if ( !zp_true( level.zp_paused ) )
        player zp_personal_hud_on();

    if ( level.zp.max_pause_time > 0 )
        player thread zp_personal_timeout();

    if ( level.zp.pause_sound != "" )
        player playlocalsound( level.zp.pause_sound );

    zp_say_all( "MSG_PERSONAL_AWAY", player );
}

/*
    Back from a personal pause. With the game running, they are counted
    in on their own, the same countdown a pause gives everybody. With the
    whole game held, they simply stop being away -- and that is what the
    watcher is waiting for, so the game comes back with them.

    why is a text key, told to them alone.
*/
zp_personal_resume( player, why )
{
    if ( !zp_true( player.zp_personal ) )
        return;

    player.zp_personal_last = gettime();
    player notify( "zp_personal_off" );
    player.zp_personal = undefined;
    player zp_personal_hud_off();

    if ( isdefined( why ) )
        player zp_say( why );

    if ( zp_true( level.zp_paused ) )
    {
        level.zp_personal_back = player;
        return;
    }

    zp_say_all( "MSG_PERSONAL_BACK", player );
    player thread zp_personal_countdown();
}

/*
    The count back in, drawn where their banner was. This file has no
    bold print to reach for, and a HUD element takes the same keyed line
    the whole-game countdown draws, so it reads in the player's own
    language on the Workshop build as well.
*/
zp_personal_countdown()
{
    self endon( "disconnect" );
    self endon( "zp_personal_on" );
    level endon( "end_game" );

    count = self zp_personal_text( "objective", 2.5, -20 );
    count.color = ( 0.35, 1, 0.35 );
    self.zp_personal_count = count;

    for ( i = level.zp.countdown; i > 0; i-- )
    {
        // A whole-game pause that began during the count owns them now,
        // and lets them go with everybody else.
        if ( zp_true( level.zp_paused ) )
            break;

        zp_show( count, "HUD_RESUMING_IN", i );

        if ( level.zp.countdown_sound != "" )
            self playlocalsound( level.zp.countdown_sound );

        wait 1;
    }

    self zp_personal_hud_off();

    if ( zp_true( level.zp_paused ) || zp_true( self.zp_personal ) )
        return;

    if ( level.zp.resume_sound != "" )
        self playlocalsound( level.zp.resume_sound );

    self zp_unfreeze_player();
}

/*
    zp_player_enforcer() for one player, for as long as their pause lasts:
    it runs only while the whole game is paused, and a map script that
    lets go of a player mid-pause would otherwise let go of this one too.
*/
zp_personal_enforcer()
{
    self endon( "disconnect" );
    self endon( "zp_personal_off" );
    level endon( "end_game" );

    for (;;)
    {
        self zp_hold_controls();
        self.ignoreme = 1;

        if ( level.zp.godmode )
            self zp_invulnerable();

        wait 0.1;
    }
}

zp_personal_timeout()
{
    self endon( "disconnect" );
    self endon( "zp_personal_off" );
    level endon( "end_game" );

    wait( level.zp.max_pause_time );

    zp_personal_resume( self, "MSG_PERSONAL_TIME_UP" );
}

/*
    What a personally paused player sees, over their own blackout: that
    they are paused and how to come back.

    Bare client elements, the way the settings menu's are, with no parent.
    hud::createFontString() parents its element to level.uiparent, and one
    still up when its player leaves keeps that slot for good; an element
    with no parent goes with the player. Both lines are fixed strings,
    which keeps them to a handful of configstrings however many players
    use them.
*/
zp_personal_hud_on()
{
    self zp_personal_hud_off();

    title = self zp_personal_text( "objective", 2.5, -20 );
    title.color = ( 1, 0.82, 0.15 );
    zp_show( title, "HUD_PERSONAL_TITLE" );
    self.zp_personal_title = title;

    hint = self zp_personal_text( "default", 1.25, 12 );

    if ( level.zp.button_combo && level.zp.combo != "" )
        zp_show( hint, "HUD_PERSONAL_BACK_CHAT_OR", level.zp.combo );
    else
        zp_show( hint, "HUD_PERSONAL_TYPE_UNPAUSE" );

    self.zp_personal_hint = hint;
}

zp_personal_text( font, scale, y )
{
    e = newclienthudelem( self );
    e.font = font;
    e.fontscale = scale;
    e.alignx = "center";
    e.aligny = "middle";
    e.horzalign = "center";
    e.vertalign = "middle";
    e.x = 0;
    e.y = y;
    e.hidewheninmenu = 1;
    e.color = ( 0.85, 0.85, 0.85 );
    zp_hud_style( e, 1 );

    return e;
}

zp_personal_hud_off()
{
    zp_hud_free( self.zp_personal_title );
    zp_hud_free( self.zp_personal_hint );
    zp_hud_free( self.zp_personal_count );

    self.zp_personal_title = undefined;
    self.zp_personal_hint = undefined;
    self.zp_personal_count = undefined;
}

/*
    The whole game, held while nobody is left playing and let go the
    moment somebody is. Runs all match; it only ever acts on a pause it
    made itself, which zp_personal_hold marks, so a player dropping or
    anything else that pauses the game is left to end the usual way.
*/
zp_personal_watcher()
{
    level endon( "end_game" );

    for (;;)
    {
        wait 0.25;

        players = getplayers();

        /*
            A personally paused player's own banner stands down while the
            whole game is paused -- the pause banner sits in the same
            place and says the same thing -- and comes back after. Only on
            a change, so nothing is made or destroyed on a tick.
        */
        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];

            if ( !isdefined( p ) )
                continue;

            show = zp_true( p.zp_personal ) && !zp_true( level.zp_paused );

            if ( show && !isdefined( p.zp_personal_title ) )
                p zp_personal_hud_on();
            else if ( !show && isdefined( p.zp_personal_title ) )
                p zp_personal_hud_off();
        }

        if ( zp_true( level.zp_busy ) )
            continue;

        away = 0;
        playing = 0;

        for ( i = 0; i < players.size; i++ )
        {
            if ( !isdefined( players[i] ) )
                continue;

            if ( zp_true( players[i].zp_personal ) )
                away++;
            else if ( zp_playable( players[i] ) )
                playing++;
        }

        if ( !zp_true( level.zp_paused ) )
        {
            if ( away > 0 && playing == 0 && zp_game_ready() )
            {
                // Whoever came back during some other pause is not who
                // ends this one.
                level.zp_personal_back = undefined;
                level.zp_personal_hold = 1;
                level.zp_last_toggle = gettime();
                zp_say_all( "MSG_PERSONAL_HOLD" );
                level thread zp_do_pause( undefined, "the team" );
            }

            continue;
        }

        if ( zp_true( level.zp_personal_hold ) && ( playing > 0 || away == 0 ) )
        {
            back = level.zp_personal_back;
            level.zp_personal_back = undefined;
            level.zp_personal_hold = undefined;
            level.zp_last_toggle = gettime();

            if ( isdefined( back ) )
                level thread zp_do_unpause( back );
            else
                level thread zp_do_unpause( undefined, "nobody left away" );
        }
    }
}


/* ==================================================================
    AI

    disablezombies()/enablezombies() are engine builtins -- they are what
    maps\mp\gametypes_zm\_hostmigration.gsc calls to hold and release the
    AI. The enforcer below is a safety net around them: it stops AI from
    re-acquiring a target, catches anything that spawns mid-pause, and
    snaps back anything that still manages to move.
   ================================================================== */

/*
    The world freeze, and the flag that makes stock script cooperate with
    it. Both are set together and cleared together, because a great deal
    of zombies script keys off the flag rather than off the builtin.

    Ownership is tracked. Killing Time uses the same pair, and a GobbleGum
    popped during a pause -- or a pause called during a GobbleGum -- must
    not have one of them clear the other's freeze. If the world was already
    paused when we arrived, we leave it exactly as we found it.
*/
zp_engine_zombies( benable )
{
    if ( !benable )
    {
        level.zp_world_was_paused = zp_true( level.bzm_worldpaused );

        if ( level.zp_world_was_paused )
            return;

        level.bzm_worldpaused = 1;

        if ( level flag::exists( "world_is_paused" ) )
            level flag::set( "world_is_paused" );

        setpauseworld( 1 );

        // Players must keep being simulated or their button state stops
        // reaching the server, and nobody could ever unpause.
        players = getplayers();
        for ( i = 0; i < players.size; i++ )
        {
            if ( isdefined( players[i] ) )
                players[i] setignorepauseworld( 1 );
        }

        return;
    }

    if ( zp_true( level.zp_world_was_paused ) )
    {
        level.zp_world_was_paused = 0;
        return;
    }

    setpauseworld( 0 );
    level.bzm_worldpaused = 0;

    if ( level flag::exists( "world_is_paused" ) )
        level flag::clear( "world_is_paused" );
}

/*
    Zombies are the axis team on this engine, and getaiteamarray() is a
    builtin rather than a utility, so it needs no include.
*/
zp_get_ai()
{
    return getaiteamarray( "axis" );
}

zp_ai_enforcer()
{
    level endon( "zp_thaw" );
    level endon( "end_game" );

    for (;;)
    {
        ai = zp_get_ai();

        for ( i = 0; i < ai.size; i++ )
        {
            z = ai[i];

            if ( !isdefined( z ) || !isalive( z ) )
                continue;

            /*
                Stop the game culling zombies for standing still.

                _zm.gsc::round_spawn_failsafe() kills any zombie that has not
                moved 24 units in 30 seconds, assuming it is stuck outside the
                playspace; Origins and Mob of the Dead ship variants on a 15
                second timer. A paused zombie trips it every time, and the
                "put it back in the spawn queue" compensation is skipped for
                anything with ignoreall set -- which is what freezes them. So
                they are gone for good, counted as killed, and the round
                advances by itself while everyone is away.

                All three variants skip the kill for a zombie that tore a
                barrier chunk in the last 8 seconds. Keeping that stamp fresh
                makes the watchdog loop around harmlessly instead of firing.
                Nothing else reads lastchunk_destroy_time outside a dev block.

                Deliberately NOT ignore_round_spawn_failsafe: that makes the
                watchdog thread return for good, so a zombie that got
                genuinely stuck later would hang the round forever.
            */
            z.lastchunk_destroy_time = gettime();

            if ( !isdefined( z.zp_anchor ) )
            {
                // First time we have seen this one -- could be an AI
                // that was already alive, or one that slipped through
                // a spawn that was already in flight.
                z.zp_anchor = z.origin;
                z.zp_had_ignoreall = zp_true( z.ignoreall );
                z.ignoreall = 1;

                if ( !zp_keeps_goal( z ) )
                    z setgoalpos( z.origin );

                if ( level.zp.silence_zombies )
                {
                    z.zp_had_inert = zp_true( z.is_inert );
                    z.is_inert = 1;
                    z stopsounds();
                    z stoploopsound();
                }

                continue;
            }

            if ( !zp_true( z.ignoreall ) )
                z.ignoreall = 1;

            if ( level.zp.drift_guard && distancesquared( z.origin, z.zp_anchor ) > level.zp.drift_tolerance )
            {
                z setorigin( z.zp_anchor );

                if ( !zp_keeps_goal( z ) )
                    z setgoalpos( z.zp_anchor );
            }
        }

        wait 0.1;
    }
}

/*
    Does this zombie keep its own goal through the pause?

    The goal pinned above is a second hold behind the world freeze, and at
    a window it does harm. A zombie on its way in is run by the behaviour
    tree in _zm_behavior.gsc: its walk to the attack spot ends the moment
    it is at its goal, zombiemovetoattackspotactionterminate() sets
    at_entrance_tear_spot on the way out whatever the reason, and what the
    tree plays next -- the board tear, or the climb through once the boards
    are gone -- is aligned to the window. A goal at the zombie's own feet
    reads as arrival, so the resume snapped it to the window and into the
    tear from wherever it had been walking.

    Killing Time pauses the world with setpauseworld() and pins no goal,
    and a zombie on its way in resumes the walk. So while the world freeze
    is what holds it, one that is not through its window yet keeps the goal
    stock gave it. first_node is set on the way to a window and
    completed_emerging_into_playable_area once through it, both by stock;
    anything else is pinned as before. With zp_engine_freeze off the pin is
    the only hold there is, and it stays.
*/
zp_keeps_goal( z )
{
    if ( !zp_true( level.zp_engine_held ) )
        return false;

    return isdefined( z.first_node ) && !zp_true( z.completed_emerging_into_playable_area );
}

zp_ai_thaw()
{
    ai = zp_get_ai();

    for ( i = 0; i < ai.size; i++ )
    {
        z = ai[i];

        if ( !isdefined( z ) || !isdefined( z.zp_anchor ) )
            continue;

        z.zp_anchor = undefined;

        // Only clear ignoreall if we were the ones who set it. Nuked,
        // marked-for-death and screecher zombies set it themselves.
        if ( !zp_true( z.zp_had_ignoreall ) )
            z.ignoreall = 0;

        z.zp_had_ignoreall = undefined;

        // Same rule for the inert flag: a zombie that was genuinely inert
        // before the pause -- Tranzit spawns them that way -- keeps it.
        if ( isdefined( z.zp_had_inert ) )
        {
            if ( !zp_true( z.zp_had_inert ) )
                z.is_inert = undefined;

            z.zp_had_inert = undefined;
        }
    }
}

/*
    Called AFTER disablezombies(). The ordering matters: while the AI think is
    live the zombie's animation state is re-derived from its movement every
    update, and that would immediately overwrite the pose.

    Zombies do not spawn while paused, so a single pass is enough. Runs in its
    own thread, so a map whose animset has no zm_inert state cannot affect the
    pause itself.
*/
/*
    Nothing to do on this engine, and that is the point.

    setpauseworld() freezes animation outright, so a zombie holds the pose
    it was in mid-stride. T6 has to swap in a dormant idle because its
    engine freeze stops the AI but leaves the animation looping; T5 and T4
    have to cancel scripted animations outright to stop a barrier teardown
    finishing through the pause. Neither problem exists here.

    The pass is kept as a no-op rather than removed so that zp_freeze_anims
    still exists, with the same name and default as every other port, and
    one config works everywhere.
*/
zp_anim_freeze_pass()
{
}

zp_anim_thaw_pass()
{
}


/* ==================================================================
    PLAYERS
   ================================================================== */

zp_connect_watcher()
{
    level endon( "end_game" );

    // Catch anybody who was already in before this script initialised.
    players = getplayers();
    for ( i = 0; i < players.size; i++ )
        players[i] thread zp_player_think();

    for (;;)
    {
        level waittill( "connected", player );
        player thread zp_player_think();
    }
}

zp_player_think()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    /*
        A player's watchers belong to the copy that set the level up. With
        two copies loaded -- a bundle's and a loose script -- both register
        the player callbacks, and whichever reached a player first used to
        take them: the level set up by one copy and every combo, pause and
        HUD line served by the other. Two builds of different versions then
        disagree about the fields they share, which is how a pause came up
        "paused by someone". So a player waits for the level, and only the
        copy that owns it starts anything.
    */
    while ( !zp_true( level.zp_loaded ) )
        wait 0.05;

    if ( isdefined( level.zp_copy ) && level.zp_copy != zp_copy_id() )
        return;

    if ( zp_true( self.zp_thinking ) )
        return;

    self.zp_thinking = 1;
    self thread zp_disconnect_watcher();
    self thread zp_button_watcher();
    self thread zp_pause_menu_watcher();
    self thread zp_vote_no_watcher();
    self thread zp_input_debug_watcher();
    self thread zp_menu_watcher();

    // The "say" notify is raised on the player on this engine, so the chat
    // listener hangs off them rather than off level as it does on T6.
    self thread zp_chat_listener();

    for (;;)
    {
        self waittill( "spawned_player" );

        if ( zp_true( level.zp_paused ) )
        {
            // Joined or respawned into a paused game -- freeze them too.
            self zp_freeze_player();
        }
        else if ( level.zp.show_hint && !zp_true( self.zp_hinted ) )
        {
            self.zp_hinted = 1;
            self thread zp_hint();
        }
    }
}

zp_hint()
{
    self endon( "disconnect" );
    wait 8;

    if ( !level.zp.button_combo )
        return;

    // A personal pause never goes to a vote, so the vote line has nothing
    // to add to this one.
    if ( level.zp.personal_pause )
    {
        self zp_say( "MSG_JOIN_HINT_PERSONAL", level.zp.combo );
        return;
    }

    self zp_say( "MSG_JOIN_HINT", level.zp.combo );

    if ( level.zp.vote )
        self zp_say( "MSG_JOIN_VOTE" );
}

zp_freeze_player()
{
    if ( zp_true( self.zp_frozen ) )
        return;

    self.zp_frozen = 1;
    self.zp_had_ignoreme = zp_true( self.ignoreme );
    self.ignoreme = 1;
    self zp_hold_controls();

    if ( level.zp.godmode )
        self zp_invulnerable();

    if ( level.zp.blackout )
        self zp_blackout_on();

    if ( level.zp.blur )
        self zp_blur_on();
}

/*
    What the pause does to a player's controls. Locked in place -- unless
    zp_freeze_players is off, and then they keep moving and looking and
    only their weapons go down, so nobody fights a held zombie. Everybody
    is locked again for the countdown, so the game comes back from where
    they all stand, and the host is locked while the settings menu is open.

    zp_locked records a lock this set, so switching to roaming lets go of
    that and nothing else: a map script's own freezecontrols() -- a ride,
    a cutscene -- is left where it was.
*/
zp_hold_controls()
{
    /*
        A personal pause is always locked, whatever zp_freeze_players says:
        roaming a game that is still running, protected and ignored by
        every zombie, is a way to walk through a round rather than a pause.
    */
    if ( level.zp.freeze_players || zp_true( level.zp_counting_down ) || zp_true( self.zp_menu_open )
         || zp_true( self.zp_personal ) )
    {
        self freezecontrols( 1 );
        self.zp_locked = 1;
        return;
    }

    if ( zp_true( self.zp_locked ) )
    {
        self freezecontrols( 0 );
        self.zp_locked = undefined;
    }

    self disableweapons();
    self.zp_weapons_down = 1;
}

zp_release_weapons()
{
    self.zp_locked = undefined;

    if ( !zp_true( self.zp_weapons_down ) )
        return;

    self.zp_weapons_down = undefined;
    self enableweapons();
}

zp_hold_everyone()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) && zp_true( players[i].zp_frozen ) )
            players[i] zp_hold_controls();
    }
}

zp_unfreeze_player()
{
    if ( !zp_true( self.zp_frozen ) )
        return;

    // A whole-game resume thaws everybody, and somebody still in a personal
    // pause is not coming back with them. zp_personal_resume() clears the
    // flag before it lets them go.
    if ( zp_true( self.zp_personal ) )
        return;

    self.zp_frozen = undefined;
    self freezecontrols( 0 );
    self zp_release_weapons();

    if ( !zp_true( self.zp_had_ignoreme ) )
        self.ignoreme = 0;

    self.zp_had_ignoreme = undefined;
    self zp_blackout_off();
    self zp_blur_off();

    // By what the pause did: zp_godmode can be changed in between.
    if ( zp_true( self.zp_invulnerable ) )
        self thread zp_grace();
}

zp_grace()
{
    self endon( "disconnect" );

    if ( level.zp.grace > 0 )
        wait( level.zp.grace );

    // If the game was paused again while we were waiting out the grace
    // period, leave the player invulnerable -- the new pause owns them now.
    if ( zp_true( level.zp_paused ) || zp_true( self.zp_frozen ) )
        return;

    self.zp_invulnerable = undefined;
    self disableinvulnerability();
}

/*
    Invulnerability the pause gave, recorded on the player, so that taking
    it away again goes by what was done rather than by zp_godmode.
*/
zp_invulnerable()
{
    self.zp_invulnerable = 1;
    self enableinvulnerability();
}

/*
    The players' half of zp_ai_enforcer(): everything the pause did to a
    player, re-applied on a tick. freezecontrols() has no getter, so this
    cannot check first -- but re-applying a flag that is already set is
    free, and it is the only way to win against a map script that releases
    a player mid-pause (see zp_control_guard in the config).

    Keyed on zp_frozen, which zp_unfreeze_player() clears before it lets
    go, so a tick landing during the thaw cannot re-freeze anybody.
*/
zp_player_enforcer()
{
    level endon( "zp_thaw" );
    level endon( "end_game" );

    for (;;)
    {
        players = getplayers();

        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];

            if ( !isdefined( p ) || !zp_true( p.zp_frozen ) )
                continue;

            p zp_hold_controls();
            p.ignoreme = 1;

            if ( level.zp.godmode )
                p zp_invulnerable();
        }

        wait 0.1;
    }
}

/*
    A screen fade rather than a black HUD element. Black Ops III has no
    precacheshader(), so a material cannot be pulled in from an injected
    script -- but lui::screen_fade_out() takes "black" and is used from
    zombies script already (zm_island_main_ee_quest.gsc), which makes it
    both reachable and certain to be loaded.

    Per player, so a spectator sees what the player it is watching sees.
*/
zp_blackout_on()
{
    if ( zp_true( self.zp_black ) )
        return;

    self.zp_black = 1;
    /*
        screen_fade rather than screen_fade_out: the wrapper hard-codes a
        target alpha of 1, and carries a wait( n_time ) with it -- which
        this paid once per player, inside the loop that freezes them all.
    */
    self lui::screen_fade( 0.4, level.zp.blackout_alpha, 0, "black" );
}

zp_blackout_off()
{
    if ( !zp_true( self.zp_black ) )
        return;

    self.zp_black = undefined;
    /*
        Back from the alpha it actually went to. screen_fade_in starts at
        1, so clearing a partial blackout with it would snap the screen to
        full black first and then fade that away.
    */
    self lui::screen_fade( 0.4, 0, level.zp.blackout_alpha, "black", 1 );
}

/*
    setblur() is a post-process on the client, not a HUD element, so
    there is nothing to destroy -- it has to be zeroed on the way out.
    Anything else driving the blur (the low-health pain blur) is zeroed
    with it, and re-applies itself afterwards.
*/
zp_blur_on()
{
    if ( zp_true( self.zp_blurred ) || level.zp.blur_amount <= 0 )
        return;

    self.zp_blurred = 1;
    self setblur( level.zp.blur_amount, 0.4 );
}

zp_blur_off()
{
    if ( !zp_true( self.zp_blurred ) )
        return;

    self.zp_blurred = undefined;
    self setblur( 0, 0.25 );
}


/* ==================================================================
    CLOCK

    Straight out of _hostmigration.gsc::locktimer(). level.discardtime is
    subtracted from the match clock, so pushing it forward by exactly the
    elapsed time holds the timer still.
   ================================================================== */

zp_clock_locker()
{
    level endon( "zp_thaw" );
    level endon( "end_game" );

    for (;;)
    {
        currtime = gettime();
        wait 0.05;

        if ( isdefined( level.discardtime ) && !zp_true( level.timerstopped ) )
            level.discardtime = level.discardtime + ( gettime() - currtime );
    }
}


/* ==================================================================
    POWERUPS

    Two separate problems:

    a) A powerup lying on the ground runs powerup_timeout(), which is a
       plain wait(). It cannot be paused, so we cut the thread instead
       ("powerup_reset" is its endon) and restart it on resume.

    b) Insta-kill and double points count down through level.zombie_vars,
       so we can simply hold those values still. The 30s wait() driving
       the actual effect keeps running underneath, so on resume we hold
       the effect on until the (frozen) HUD timer has really run out.
   ================================================================== */

zp_powerup_enforcer()
{
    level endon( "zp_thaw" );
    level endon( "end_game" );

    for (;;)
    {
        if ( level.zp.freeze_powerups )
            zp_powerups_hold();

        if ( level.zp.freeze_effects )
            zp_effects_hold();

        wait 0.05;
    }
}

zp_powerups_hold()
{
    if ( !isdefined( level.active_powerups ) )
        return;

    for ( i = 0; i < level.active_powerups.size; i++ )
    {
        p = level.active_powerups[i];

        if ( !isdefined( p ) || zp_true( p.zp_held ) )
            continue;

        p.zp_held = 1;
        p notify( "powerup_reset" );  // ends zm_powerups::powerup_timeout
        p show();
    }
}

zp_powerups_thaw()
{
    if ( !isdefined( level.active_powerups ) )
        return;

    for ( i = 0; i < level.active_powerups.size; i++ )
    {
        p = level.active_powerups[i];

        if ( !isdefined( p ) || !zp_true( p.zp_held ) )
            continue;

        p.zp_held = undefined;
        p thread zm_powerups::powerup_timeout();
    }
}

/*
    Double points is named differently here. Black Ops II calls the pair
    zombie_powerup_point_doubler_time / _on, Black Ops III calls them
    zombie_powerup_double_points_time / _on. Both T6 names came over with
    the port, and a zombie_vars key that does not exist reads as undefined
    rather than failing, so the hold below skipped it and the restore in
    zp_effects_thaw() bailed out -- double points drained through every
    pause and never came back afterwards.
*/
zp_effects_hold()
{
    if ( !isdefined( level.zombie_vars ) || !isdefined( level.teams ) )
        return;

    foreach ( team in level.teams )
    {
        if ( !isdefined( level.zombie_vars[team] ) )
            continue;

        zp_hold_var( team, "zombie_powerup_insta_kill_time" );
        zp_hold_var( team, "zombie_powerup_double_points_time" );
        zp_hold_var( team, "zombie_insta_kill" );
        zp_hold_var( team, "zombie_point_scalar" );
    }
}

zp_hold_var( team, key )
{
    if ( !isdefined( level.zombie_vars[team][key] ) )
        return;

    id = team + "|" + key;

    if ( !isdefined( level.zp_held_vars[id] ) )
        level.zp_held_vars[id] = level.zombie_vars[team][key];
    else
        level.zombie_vars[team][key] = level.zp_held_vars[id];
}

/*
    Releasing the effect vars needs care. insta_kill_powerup() is a plain
    "wait 30" that we cannot pause, so on a long pause it has already run
    its cleanup line -- and our hold quietly put the value back. If we
    just stopped holding, insta-kill or double points would stay on for
    the rest of the game.

    So on resume we hand the effect over to a bounded thread that keeps it
    on only until the HUD countdown (which we did freeze correctly, and
    which is still ticking down in _zm_powerups) actually reaches zero,
    then forces it off. Net result: the player gets exactly the time they
    earned, and the effect always terminates.
*/
zp_effects_thaw()
{
    if ( !isdefined( level.zombie_vars ) || !isdefined( level.teams ) )
    {
        level.zp_held_vars = [];
        return;
    }

    foreach ( team in level.teams )
    {
        if ( !isdefined( level.zombie_vars[team] ) )
            continue;

        ik = level.zp_held_vars[team + "|zombie_insta_kill"];
        if ( isdefined( ik ) && ik == 1 )
        {
            level thread zp_effect_extender( team, "zombie_insta_kill", 1, 0,
                "zombie_powerup_insta_kill_time", "zombie_powerup_insta_kill_on" );
        }

        dp = level.zp_held_vars[team + "|zombie_point_scalar"];
        if ( isdefined( dp ) && dp > 1 )
        {
            level thread zp_effect_extender( team, "zombie_point_scalar", dp, 1,
                "zombie_powerup_double_points_time", "zombie_powerup_double_points_on" );
        }
    }

    level.zp_held_vars = [];
}

zp_effect_extender( team, effect_key, on_value, off_value, timer_key, on_key )
{
    level endon( "end_game" );
    level endon( "zp_paused" );  // a new pause takes the hold back over

    if ( !isdefined( level.zombie_vars[team] ) || !isdefined( level.zombie_vars[team][timer_key] ) )
        return;

    /*
        The effect can never need longer than whatever is still on its own
        HUD countdown -- which is the value we froze, so it is exactly the
        time the player has left to be given back. Bounding the thread by
        that (plus a small buffer) means it always terminates, and never
        terminates early.
    */
    remaining = level.zombie_vars[team][timer_key];
    if ( remaining > 35 )
        remaining = 35;

    deadline = gettime() + int( remaining * 1000 ) + 2000;

    for (;;)
    {
        if ( !isdefined( level.zombie_vars[team] ) || !isdefined( level.zombie_vars[team][timer_key] ) )
            return;

        if ( gettime() > deadline )
            break;

        // The HUD countdown reaching zero, or _zm_powerups clearing its
        // "powerup is running" flag, both mean the player's time is up.
        if ( level.zombie_vars[team][timer_key] <= 0 )
            break;

        if ( isdefined( level.zombie_vars[team][on_key] ) && !level.zombie_vars[team][on_key] )
            break;

        level.zombie_vars[team][effect_key] = on_value;
        wait 0.05;
    }

    level.zombie_vars[team][effect_key] = off_value;
}


/* ==================================================================
    BLEEDOUT

    _zm_laststand.gsc::laststand_bleedout() decrements self.bleedout_time
    once a second. Pinning the value holds a downed player where they are
    instead of letting them bleed out during the pause.
   ================================================================== */

zp_bleedout_enforcer()
{
    level endon( "zp_thaw" );
    level endon( "end_game" );

    for (;;)
    {
        players = getplayers();

        for ( i = 0; i < players.size; i++ )
        {
            p = players[i];

            if ( !isdefined( p ) || !isdefined( p.bleedout_time ) )
                continue;

            if ( !isdefined( p.revivetrigger ) && !zp_true( p.laststand ) )
                continue;

            if ( !isdefined( p.zp_bleedout ) )
                p.zp_bleedout = p.bleedout_time;
            else
                p.bleedout_time = p.zp_bleedout;
        }

        wait 0.05;
    }
}

zp_bleedout_thaw()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i].zp_bleedout = undefined;
    }
}


/* ==================================================================
    HUD / FEEDBACK
   ================================================================== */

/*
    Place one line of a stacked block. yoff is the line's offset inside the
    block, so a caller lays its lines out once and the slot decides where
    the whole thing lands.

    hud::setPoint()'s first argument is the element's own anchor, and that is
    what sets the text alignment -- "LEFT" hangs the string off its left
    edge so it grows rightward. The left and right slots use that to sit
    flush against their edge instead of staying centred.
*/
/*
    Applied to every element the script makes. The glow is what carries
    the text over a bright skybox, and the fade stops each line snapping
    into place the instant it is created.
*/
/*
    _hud_util's setparent() files every element it creates into
    level.uiparent.children, and destroy() does not take it back out --
    only hud::removeChild() does, and nothing calls that for you. Destroying an
    element without detaching it first leaves its slot behind for good, so
    a script that builds and tears down a HUD on every pause and every vote
    walks the server into "exceeded maximum number of parent server script
    variables" and drops it.

    Everything this script makes goes out through here.
*/
zp_hud_free( elem )
{
    if ( !isdefined( elem ) )
        return;

    if ( isdefined( elem.parent ) )
        elem.parent hud::removeChild( elem );

    elem destroy();
}

zp_hud_style( elem, alpha )
{
    if ( !isdefined( elem ) )
        return;

    elem.sort = 1000;
    elem.foreground = 1;

    if ( level.zp.hud_glow )
    {
        elem.glowcolor = ( 0, 0, 0 );
        elem.glowalpha = 0.55;
    }

    /*
        Set, not faded in.

        fadeovertime() animates on the game's own clock, and a pause is the
        one moment that clock is not running: zp_ease_in() has already taken
        the world down to a quarter speed before any of this is drawn, and
        the freeze holds it there. A quarter-second fade then arrives late,
        or not at all -- the element exists, carries its text and is alive a
        frame later, and draws at the alpha the fade got to, which is near
        enough to nothing.

        That is what the zp_hud_debug trace showed on T6 on 1 October 2026:
        banner, clock, name and hint all created, written and still there a
        frame later, with only the banner on screen. T5 and T4 set alpha
        outright and have never had it.
    */
    elem.alpha = alpha;
}

/*
    The backing panel anchors its own top edge, unlike the text lines,
    which anchor differently per slot. Doing it separately keeps the slab
    lined up with the block instead of straddling it.
*/
zp_panel_place( elem, position, pad )
{
    if ( position == "top" )
    {
        elem hud::setPoint( "TOP", "TOP", 0, 12 - pad );
        return;
    }

    if ( position == "bottom" )
    {
        elem hud::setPoint( "TOP", "BOTTOM", 0, -124 - pad );
        return;
    }

    if ( position == "middle" )
    {
        elem hud::setPoint( "TOP", "CENTER", 0, -40 - pad );
        return;
    }

    if ( position == "left" )
    {
        elem hud::setPoint( "TOPLEFT", "LEFT", 24 - pad, -46 - pad );
        return;
    }

    if ( position == "right" )
    {
        elem hud::setPoint( "TOPRIGHT", "RIGHT", -24 + pad, -46 - pad );
        return;
    }

    elem hud::setPoint( "TOP", "TOP", 0, 56 - pad );
}

zp_panel_show( position, height )
{
    if ( !level.zp.hud_panel || height <= 0 )
    {
        zp_panel_destroy();
        return;
    }

    // A shader element is sized when it is made, so a block that grew or
    // shrank -- a voter joining, the down line appearing -- rebuilds it
    // rather than resizing.
    if ( isdefined( level.zp_panel ) && level.zp_panel.zp_h == height )
        return;

    zp_panel_destroy();

    /*
        A line's offset is to its middle, not its top, so the slab needs
        more clearance above the block than below it or it clips the top
        of the title.
    */
    pad_top = 20;
    pad_bottom = 10;

    level.zp_panel = hud::createServerIcon( "black", level.zp.hud_panel_width, int( height + pad_top + pad_bottom ) );
    zp_panel_place( level.zp_panel, position, pad_top );

    // Under the text, which sorts at 1000.
    level.zp_panel.sort = 999;
    level.zp_panel.foreground = 1;
    level.zp_panel.zp_h = height;
    // Set rather than faded, for the reason zp_hud_style() gives: the world
    // is already slowing when this is drawn, and a fade on its clock does
    // not finish.
    level.zp_panel.alpha = level.zp.hud_panel_alpha;
}

zp_panel_destroy()
{
    if ( isdefined( level.zp_panel ) )
    {
        zp_hud_free( level.zp_panel );
        level.zp_panel = undefined;
    }
}

zp_hud_place( elem, position, yoff )
{
    if ( !isdefined( elem ) )
        return;

    if ( position == "top" )
    {
        elem hud::setPoint( "CENTER", "TOP", 0, 12 + yoff );
        return;
    }

    if ( position == "bottom" )
    {
        elem hud::setPoint( "CENTER", "BOTTOM", 0, -124 + yoff );
        return;
    }

    if ( position == "middle" )
    {
        elem hud::setPoint( "CENTER", "CENTER", 0, -40 + yoff );
        return;
    }

    if ( position == "left" )
    {
        elem hud::setPoint( "LEFT", "LEFT", 24, -46 + yoff );
        return;
    }

    if ( position == "right" )
    {
        elem hud::setPoint( "RIGHT", "RIGHT", -24, -46 + yoff );
        return;
    }

    // center -- the classic banner spot, where the pause HUD has always sat.
    elem hud::setPoint( "CENTER", "TOP", 0, 56 + yoff );
}

/*
    Where each line of the pause banner sits. Every line is centred in its
    own right -- nothing in GSC can measure a rendered string, so two
    elements sharing a line can only be centred on their join, and that
    throws the pair off centre as soon as one side is wider than the other.
    Stacking is the only arrangement that holds in all six slots and for
    any length of name.

    The lines under the clock shift up when zp_hud_timer is off, rather
    than leaving a hole where it would have been.
*/
zp_pause_yoff( line )
{
    if ( line == "clock" )
        return 34;

    if ( line == "name" )
        return 58;

    if ( line == "hint" )
    {
        if ( level.zp.hud_timer )
            return 80;

        return 34;
    }

    // "down"
    if ( level.zp.hud_timer )
        return 104;

    return 58;
}

/*
    Elapsed time, in minutes. Bounded to about sixty distinct strings, all
    reused, where a live second counter would burn a configstring a second.
*/
zp_elapsed_show( elem )
{
    secs = int( ( gettime() - level.zp_pause_start ) / 1000 );

    if ( secs < 0 )
        secs = 0;

    mins = int( secs / 60 );

    if ( mins > 60 )
        zp_show( elem, "HUD_CLOCK_OVER_HOUR" );
    else if ( mins < 1 )
        zp_show( elem, "HUD_CLOCK_UNDER_MINUTE" );
    else if ( mins == 1 )
        zp_show( elem, "HUD_CLOCK_ONE_MINUTE" );
    else
        zp_show( elem, "HUD_CLOCK_MINUTES", mins );
}

/*
    Only runs when the clock is a text line rather than a timer element --
    a timer counts down on the client for free and needs nothing from here.
*/
zp_clock_text_updater()
{
    level endon( "zp_hud_stop" );
    level endon( "zp_thaw" );
    level endon( "end_game" );

    for (;;)
    {
        if ( !isdefined( level.zp_hud_clock ) )
            return;

        zp_elapsed_show( level.zp_hud_clock );
        wait 5;
    }
}

/*
    The pause HUD, a line at a time and each on its own thread.

    One thread for all of it was fine while ZPause was the only mod drawing
    on screen. It is not fine beside three others: these elements come out
    of pools the whole server shares -- hudelems, the parent script
    variables hud:: keeps its bookkeeping in, and the 488 configstrings a
    distinct settext() costs -- and a game that has run dry does not hand
    back an element, it stops the thread asking for one. Everything after
    that line then never ran, which is how a pause banner came to stand
    there with no clock, no name and no hint under it.

    A line of its own means one that cannot be made costs that line and
    nothing else. zp_hud_missing() says so once, in a dvar, because println
    is a devblock call on this engine and there is nowhere else to say it.
*/
zp_hud_show()
{
    if ( !level.zp.hud )
        return;

    zp_hud_destroy();

    level thread zp_hud_banner_show();

    if ( level.zp.hud_timer )
    {
        level thread zp_hud_clock_show();
        level thread zp_hud_meta_show();
    }

    // The result of a vote stands in its own slot; only pull it early if
    // this banner is about to land on top of it.
    if ( level.zp.hud_position == level.zp.vote_hud_position )
        zp_vote_outcome_clear();

    level thread zp_hud_sub_updater();
}

zp_hud_banner_show()
{
    level.zp_hud = hud::createServerFontString( "objective", 1.9 );

    if ( !isdefined( level.zp_hud ) )
    {
        zp_hud_missing( "banner" );
        return;
    }

    zp_hud_place( level.zp_hud, level.zp.hud_position, 0 );
    level.zp_hud.color = ( 1, 0.82, 0.15 );
    zp_hud_style( level.zp_hud, 1 );
    zp_show( level.zp_hud, "HUD_GAME_PAUSED" );
}

/*
    The clock is a timer element where it counts down, and text where it
    does not, because this engine only counts down.

    settimer() is what T6 uses and it works the same way here, so an
    auto-resume gets a real timer element ticking towards zero. Counting
    elapsed time UP has no equivalent -- T6 reaches for settenthstimerup(),
    which Black Ops III does not have -- so without an auto-resume the clock
    is drawn as text instead, in minutes, refreshed on a tick.

    Minutes rather than mm:ss for the reason T5 and T4 report in minutes:
    every distinct string handed to settext() costs a configstring out of
    488, and a live second counter burns one a second until the pool runs
    dry and drops the server. Minutes bound the whole set to about sixty
    strings, all reused.
*/
zp_hud_clock_show()
{
    if ( level.zp.max_pause_time > 0 )
        level.zp_hud_clock = hud::createServerTimer( "objective", 1.3 );
    else
        level.zp_hud_clock = hud::createServerFontString( "objective", 1.3 );

    if ( !isdefined( level.zp_hud_clock ) )
    {
        zp_hud_missing( "clock" );
        return;
    }

    elapsed = int( ( gettime() - level.zp_pause_start ) / 1000 );

    zp_hud_place( level.zp_hud_clock, level.zp.hud_position, zp_pause_yoff( "clock" ) );
    level.zp_hud_clock.color = ( 0.85, 0.85, 0.85 );
    zp_hud_style( level.zp_hud_clock, 0.85 );

    if ( level.zp.max_pause_time > 0 )
    {
        level.zp_hud_clock settimer( level.zp.max_pause_time - elapsed );
        return;
    }

    zp_elapsed_show( level.zp_hud_clock );
    level thread zp_clock_text_updater();
}

zp_hud_meta_show()
{
    level.zp_hud_meta = hud::createServerFontString( "default", 1.0 );

    if ( !isdefined( level.zp_hud_meta ) )
    {
        zp_hud_missing( "name line" );
        return;
    }

    zp_hud_place( level.zp_hud_meta, level.zp.hud_position, zp_pause_yoff( "name" ) );
    level.zp_hud_meta.color = ( 0.7, 0.7, 0.7 );
    zp_hud_style( level.zp_hud_meta, 0.7 );

    // One string per person who has ever paused, rather than one a second.
    if ( zp_menu_synced() )
        zp_menu_sync_hud();
    else if ( zp_true( level.zp_pauser_team ) )
        zp_show( level.zp_hud_meta, "HUD_PAUSED_BY_TEAM" );
    else
        zp_show( level.zp_hud_meta, "HUD_PAUSED_BY", level.zp_pauser );
}




/*
    The hint line is the one thing on screen that is not the same for
    everybody: a player who is down is on a different combo, so their line
    has to say so. hud::createFontString() on a player makes a client element
    rather than a server one, which is what lets each of them read
    differently.
*/
zp_subline_create( position, yoff, scale, alpha )
{
    e = self hud::createFontString( "default", scale );

    // A client element the engine would not make is undefined, and styling
    // one is what stops the thread that was drawing the rest.
    if ( !isdefined( e ) )
    {
        zp_hud_missing( "hint line" );
        return undefined;
    }

    zp_hud_place( e, position, yoff );
    e.color = ( 0.85, 0.85, 0.85 );
    zp_hud_style( e, alpha );

    return e;
}

/*
    What the banner tells a player to do to get out of it. It names
    !unpause beside the combo, the same as the T6 build: the game raises
    "say" on the player, and BOIII and T7x raise it themselves, so the
    line people were never told about works on every route.
*/
zp_pause_hint_show( elem, player )
{
    if ( isdefined( level.zp_hud_sub_override ) )
    {
        zp_show( elem, level.zp_hud_sub_override, level.zp_hud_sub_override_a, level.zp_hud_sub_override_b );
        return;
    }

    if ( !level.zp.button_combo )
    {
        zp_show( elem, "HUD_TYPE_UNPAUSE" );
        return;
    }

    combo = level.zp.combo;

    if ( isdefined( player ) && zp_player_input_limited( player ) )
        combo = level.zp.button_combo_dead;

    if ( combo == "" )
        zp_show( elem, "HUD_TYPE_UNPAUSE" );
    else
        zp_show( elem, "HUD_RESUME_CHAT_OR", combo );
}

zp_hud_sub_show( player )
{
    if ( !isdefined( player ) )
        return;

    if ( !isdefined( player.zp_hud_sub ) )
        player.zp_hud_sub = player zp_subline_create( level.zp.hud_position, zp_pause_yoff( "hint" ), 1.25, 1 );

    zp_pause_hint_show( player.zp_hud_sub, player );
}

/*
    Picks up players who joined into a paused game, and anyone whose state
    changed under them. zp_hud_text() only touches an element when the
    string actually differs, so the idle cost is a string compare.
*/
zp_hud_sub_updater()
{
    level endon( "zp_hud_sub_stop" );
    level endon( "zp_thaw" );
    level endon( "end_game" );

    for (;;)
    {
        players = getplayers();

        for ( i = 0; i < players.size; i++ )
            zp_hud_sub_show( players[i] );

        zp_down_line_show( level.zp.hud_position, zp_pause_yoff( "down" ), "pause" );

        h = zp_pause_yoff( "hint" ) + 12;

        if ( isdefined( level.zp_down_line ) )
            h = zp_pause_yoff( "down" ) + 10;

        zp_panel_show( level.zp.hud_position, h );

        wait 0.25;
    }
}

/*
    A spectating player's client draws the HUD of whoever it is watching,
    not its own -- so the per-client hint line above never reaches them.
    They read the live player's line instead, which correctly says crouch
    + melee, because that player is alive.

    This line is a server element, which everybody sees including
    spectators, and it only appears while somebody is actually down. That
    makes it redundant for a player in last stand, who can already read
    their own line; reaching the spectators is worth the repetition.
*/
zp_anyone_down()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) && zp_player_input_limited( players[i] ) )
            return 1;
    }

    return 0;
}

zp_down_hint_show( elem, kind )
{
    yes_combo = level.zp.button_combo_dead;
    no_combo = level.zp.vote_no_combo_dead;

    if ( kind == "vote" )
    {
        // A down combo left unbound puts !yes or !no in its place, the
        // same as the T6 build: chat reaches this engine after all.
        if ( yes_combo == "" && no_combo == "" )
            zp_show( elem, "HUD_DOWN_VOTE_CHAT" );
        else if ( yes_combo == "" )
            zp_show( elem, "HUD_DOWN_VOTE_CHAT_NO", no_combo );
        else if ( no_combo == "" )
            zp_show( elem, "HUD_DOWN_VOTE_YES_CHAT", yes_combo );
        else
            zp_show( elem, "HUD_DOWN_VOTE_YES_NO", yes_combo, no_combo );

        return;
    }

    if ( yes_combo == "" )
        zp_show( elem, "HUD_DOWN_TYPE_UNPAUSE" );
    else
        zp_show( elem, "HUD_DOWN_PAUSE", yes_combo );
}

zp_down_line_show( position, yoff, kind )
{
    if ( !level.zp.button_combo || isdefined( level.zp_hud_sub_override ) || !zp_anyone_down() )
    {
        zp_down_line_destroy();
        return;
    }

    if ( !isdefined( level.zp_down_line ) )
    {
        level.zp_down_line = hud::createServerFontString( "default", 1.0 );
        zp_hud_place( level.zp_down_line, position, yoff );
        level.zp_down_line.color = ( 0.85, 0.85, 0.85 );
        zp_hud_style( level.zp_down_line, 0.7 );
    }

    zp_down_hint_show( level.zp_down_line, kind );
}

zp_down_line_destroy()
{
    if ( isdefined( level.zp_down_line ) )
    {
        zp_hud_free( level.zp_down_line );
        level.zp_down_line = undefined;
    }
}

zp_hud_sub_refresh()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
        zp_hud_sub_show( players[i] );
}

zp_hud_sub_destroy()
{
    level notify( "zp_hud_sub_stop" );
    level.zp_hud_sub_override = undefined;
    zp_down_line_destroy();
    zp_panel_destroy();

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( isdefined( p ) && isdefined( p.zp_hud_sub ) )
        {
            zp_hud_free( p.zp_hud_sub );
            p.zp_hud_sub = undefined;
        }
    }
}

zp_hud_destroy()
{
    // The clock text thread reads level.zp_hud_clock, which is about to
    // go. It declared this endon and nothing ever raised it, so every
    // vote that took the HUD down and gave it back left the old thread
    // running against the new element until its next tick. T5 and T4
    // raise it in the same place.
    level notify( "zp_hud_stop" );

    if ( isdefined( level.zp_hud ) )
    {
        zp_hud_free( level.zp_hud );
        level.zp_hud = undefined;
    }

    if ( isdefined( level.zp_hud_meta ) )
    {
        zp_hud_free( level.zp_hud_meta );
        level.zp_hud_meta = undefined;
    }

    if ( isdefined( level.zp_hud_clock ) )
    {
        zp_hud_free( level.zp_hud_clock );
        level.zp_hud_clock = undefined;
    }

    zp_hud_sub_destroy();
}

// ZP_TEXT_BEGIN
/*
    Generated by tools/mk_t7_text.py from zpause-text.json. Never edit
    by hand -- change the table and build.

    Every line a player reads comes through here by key. This is the
    English one, which the loose-script builds draw. The Workshop build
    carries the same functions over localized strings instead, so each
    player there reads their own language.
*/
zp_say( key, a, b )
{
    txt = zp_text( key, a, b );

    if ( txt != "" )
        self iprintln( txt );
}

zp_say_all( key, a, b )
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i] zp_say( key, a, b );
    }
}

zp_show( elem, key, a, b )
{
    zp_hud_text( elem, zp_text( key, a, b ) );
}

zp_text_player( player )
{
    // A name already worked out -- the room's list of open menus -- goes
    // through as it is; only a player is asked for its name.
    if ( isdefined( player ) && isstring( player ) )
        return player;

    if ( isdefined( player ) && isdefined( player.name ) )
        return player.name;

    return "someone";
}

zp_text( key, a, b )
{
    if ( key == "" )
        return "";

    if ( key == "MSG_HOST_ONLY" )
        return "^1[Pause]^7 only the host can pause";
    if ( key == "MSG_DROPPED_PAUSED" )
        return "^3[Pause]^7 somebody dropped -- paused";
    if ( key == "MSG_ROUND_END_PENDING" )
        return "^3[Pause]^7 pausing at the end of the round -- ask again to call it off";
    if ( key == "MSG_READY" )
        return "^2[Pause]^7 you are ready";
    if ( key == "MSG_NOT_YET" )
        return "^1[Pause]^7 not available yet";
    if ( key == "MSG_ROUND_END_OFF" )
        return "^3[Pause]^7 the pause at the end of the round is off";
    if ( key == "MSG_ROUND_END_NOT_YOURS" )
        return "^1[Pause]^7 only ^3" + zp_text_player( a ) + "^7 or the host can call that off";
    if ( key == "MSG_NO_PAUSES_LEFT" )
        return "^1[Pause]^7 no pauses left this match";
    if ( key == "MSG_VOTE_COOLDOWN" )
        return "^1[Pause]^7 a vote just failed -- wait a moment";
    if ( key == "MSG_PAUSED_BY" )
        return "^3[Pause]^7 game paused by ^3" + zp_text_player( a );
    if ( key == "MSG_RESUMING_BY" )
        return "^2[Pause]^7 resuming -- requested by ^2" + zp_text_player( a );
    if ( key == "MSG_RESUMING_READY" )
        return "^2[Pause]^7 resuming -- requested by ^2everyone ready";
    if ( key == "MSG_RESUMING_VOTE_FAILED" )
        return "^2[Pause]^7 resuming -- requested by ^2vote failed";
    if ( key == "MSG_RESUMING_AUTO" )
        return "^2[Pause]^7 resuming -- requested by ^2auto-resume";
    if ( key == "MSG_JOIN_HINT" )
        return "^3[Pause]^7 hold ^3" + zp_combo_label( a ) + "^7 to pause or resume";
    if ( key == "MSG_JOIN_VOTE" )
        return "^3[Pause]^7 pauses go to a vote -- the same combo votes yes";
    if ( key == "MSG_VOTED_YES" )
        return "^2[Pause]^7 your vote: ^2yes";
    if ( key == "MSG_VOTED_NO" )
        return "^1[Pause]^7 your vote: ^1no";
    if ( key == "MSG_ASKS_HOST" )
        return "^3[Pause]^7 ^3" + zp_text_player( a ) + "^7 is asking the host to pause";
    if ( key == "MSG_VOTE_CALLED_PAUSE" )
        return "^3[Pause]^7 ^3" + zp_text_player( a ) + "^7 called a vote to pause";
    if ( key == "MSG_VOTE_CALLED_RESUME" )
        return "^3[Pause]^7 ^3" + zp_text_player( a ) + "^7 called a vote to resume";
    if ( key == "MSG_VOTE_PASSED" )
        return "^2[Pause]^7 vote passed ^2" + a + "^7/" + b;
    if ( key == "MSG_VOTE_FAILED" )
        return "^1[Pause]^7 vote failed ^1" + a + "^7/" + b;
    if ( key == "MSG_VOTE_WAITING_HOST" )
        return "^3[Pause]^7 waiting for the host";
    if ( key == "MSG_VOTE_HINT_NO" )
        return "^3[Pause]^7 ^1" + zp_combo_label( a ) + "^7 = no";
    if ( key == "MSG_VOTE_HINT_YES" )
        return "^3[Pause]^7 ^2" + zp_combo_label( a ) + "^7 = yes";
    if ( key == "MSG_VOTE_HINT_YES_NO" )
        return "^3[Pause]^7 ^2" + zp_combo_label( a ) + "^7 = yes     ^1" + zp_combo_label( b ) + "^7 = no";
    if ( key == "MSG_JOIN_HINT_PERSONAL" )
        return "^3[Pause]^7 hold ^3" + zp_combo_label( a ) + "^7 to pause yourself -- the game stops once everybody has";
    if ( key == "MSG_PERSONAL_DOWN" )
        return "^1[Pause]^7 not while you are down";
    if ( key == "MSG_PERSONAL_AWAY" )
        return "^3[Pause]^7 ^3" + zp_text_player( a ) + "^7 has stepped away -- zombies will leave them be";
    if ( key == "MSG_PERSONAL_BACK" )
        return "^2[Pause]^7 ^2" + zp_text_player( a ) + "^7 is back";
    if ( key == "MSG_PERSONAL_TIME_UP" )
        return "^3[Pause]^7 time's up -- you're back in";
    if ( key == "MSG_PERSONAL_WAITING" )
        return "^3[Pause]^7 the game comes back when somebody who paused does";
    if ( key == "MSG_PERSONAL_HOLD" )
        return "^3[Pause]^7 nobody is left playing -- the game waits for whoever comes back first";
    if ( key == "MSG_PAUSED_BY_TEAM" )
        return "^3[Pause]^7 game paused by ^3the team";
    if ( key == "MSG_RESUMING_NOBODY_AWAY" )
        return "^2[Pause]^7 resuming -- requested by ^2nobody left away";
    if ( key == "MSG_RESUMING_MENU_CLOSED" )
        return "^2[Pause]^7 resuming -- requested by ^2a closed menu";
    if ( key == "HUD_GAME_PAUSED" )
        return "GAME PAUSED";
    if ( key == "HUD_RESUMING_IN" )
        return "RESUMING IN " + a;
    if ( key == "HUD_PAUSED_BY" )
        return "paused by " + zp_text_player( a );
    if ( key == "HUD_CLOCK_UNDER_MINUTE" )
        return "under a minute";
    if ( key == "HUD_CLOCK_ONE_MINUTE" )
        return "1 minute";
    if ( key == "HUD_CLOCK_MINUTES" )
        return "" + a + " minutes";
    if ( key == "HUD_CLOCK_OVER_HOUR" )
        return "over an hour";
    if ( key == "HUD_HOLD_STILL" )
        return "hold still";
    if ( key == "HUD_READY_COUNT" )
        return "READY  " + a + " / " + b;
    if ( key == "HUD_TYPE_UNPAUSE" )
        return "type !unpause to resume";
    if ( key == "HUD_PAUSED_BY_TEAM" )
        return "paused by the team";
    if ( key == "HUD_PERSONAL_TITLE" )
        return "YOU ARE PAUSED";
    if ( key == "HUD_PERSONAL_BACK_CHAT_OR" )
        return "!unpause  or  " + zp_combo_label( a, level.zp.hud_binds ) + "  to come back";
    if ( key == "HUD_PERSONAL_TYPE_UNPAUSE" )
        return "type !unpause to come back";
    if ( key == "HUD_RESUME_CHAT_OR" )
        return "!unpause  or  " + zp_combo_label( a, level.zp.hud_binds );
    if ( key == "HUD_DOWN_VOTE_CHAT" )
        return "while down:  ^2!yes^7  /  ^1!no";
    if ( key == "HUD_DOWN_VOTE_CHAT_NO" )
        return "while down:  ^2!yes^7  /  ^1" + zp_combo_label( a, level.zp.hud_binds ) + "^7 = no";
    if ( key == "HUD_DOWN_VOTE_YES_CHAT" )
        return "while down:  ^2" + zp_combo_label( a, level.zp.hud_binds ) + "^7 = yes  /  ^1!no";
    if ( key == "HUD_DOWN_VOTE_YES_NO" )
        return "while down:  ^2" + zp_combo_label( a, level.zp.hud_binds ) + "^7 = yes  /  ^1" + zp_combo_label( b, level.zp.hud_binds ) + "^7 = no";
    if ( key == "HUD_DOWN_PAUSE" )
        return "while down:  !unpause  or  " + zp_combo_label( a, level.zp.hud_binds );
    if ( key == "HUD_DOWN_TYPE_UNPAUSE" )
        return "while down:  type !unpause";
    if ( key == "HUD_VOTE_WAITING_HOST" )
        return "waiting for the host";
    if ( key == "HUD_VOTE_HINT_NO" )
        return "^1" + zp_combo_label( a, level.zp.hud_binds ) + "^7 = no";
    if ( key == "HUD_VOTE_HINT_YES" )
        return "^2" + zp_combo_label( a, level.zp.hud_binds ) + "^7 = yes";
    if ( key == "HUD_VOTE_HINT_YES_NO" )
        return "^2" + zp_combo_label( a, level.zp.hud_binds ) + "^7 = yes     ^1" + zp_combo_label( b, level.zp.hud_binds ) + "^7 = no";
    if ( key == "HUD_VOTE_TITLE_REQUEST" )
        return "PAUSE REQUEST";
    if ( key == "HUD_VOTE_TITLE_RESUME" )
        return "RESUME VOTE   ^2" + a + "^7 / " + b;
    if ( key == "HUD_VOTE_TITLE_PAUSE" )
        return "PAUSE VOTE   ^2" + a + "^7 / " + b;
    if ( key == "HUD_VOTE_PASSED" )
        return "^2VOTE PASSED   " + a + "^7 / " + b;
    if ( key == "HUD_VOTE_FAILED" )
        return "^1VOTE FAILED   " + a + "^7 / " + b;
    if ( key == "HUD_ROW_SPECTATING" )
        return "^7" + zp_text_player( a ) + "   ^3spectating";
    if ( key == "HUD_ROW_NONE" )
        return "^7" + zp_text_player( a ) + "   ^3-";
    if ( key == "HUD_ROW_YES" )
        return "^7" + zp_text_player( a ) + "   ^2yes";
    if ( key == "HUD_ROW_NO" )
        return "^7" + zp_text_player( a ) + "   ^1no";
    if ( key == "HUD_MENU_TITLE" )
        return "ZPAUSE SETTINGS";
    if ( key == "HUD_MENU_HINT" )
        return "aim / fire  move     grenade  change     melee  close";
    if ( key == "HUD_MENU_HINT_BINDS" )
        return "[{+speed_throw}] [{+attack}]  move     [{+frag}]  change     [{+melee}]  close";
    if ( key == "HUD_MENU_ON" )
        return "on";
    if ( key == "HUD_MENU_OFF" )
        return "off";
    if ( key == "HUD_MENU_NONE" )
        return "none";
    if ( key == "HUD_MENU_DEBUG" )
        return "debug";
    if ( key == "HUD_MENU_INPUT" )
        return "input";
    if ( key == "HUD_MENU_VOTING" )
        return "voting";
    if ( key == "HUD_MENU_TIMING" )
        return "timing";
    if ( key == "HUD_MENU_FROZEN" )
        return "what gets frozen";
    if ( key == "HUD_MENU_PRESENTATION" )
        return "presentation";

    return key;
}
// ZP_TEXT_END

zp_sound_all( alias )
{
    if ( !isdefined( alias ) || alias == "" )
        return;

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i] playlocalsound( alias );
    }
}


/* ==================================================================
    VOTING

    Ballots live on the players as .zp_vote -- 1 yes, 0 no, undefined for
    not voted yet -- so a disconnect takes its vote with it and every
    tally is recomputed from whoever is actually in the game.

    The watcher owns the lifecycle. It is keyed on a serial rather than an
    endon, because zp_vote_finish() runs inside it and ending the vote
    from in there would kill the thread halfway through its own cleanup.
   ================================================================== */

/*
    Who the maths is done over. Last stand still counts -- a downed player
    is alive and can still vote from chat; only someone bled out and
    spectating drops out of the electorate, and only with vote_alive_only.
*/
/*
    Approval mode, and somebody is actually holding the host slot. With no
    host there is nobody to ask, so it stays out of the way rather than
    opening a request that nothing can answer.
*/
zp_host_approving()
{
    return level.zp.host_approve && isdefined( zp_host_player() );
}

zp_player_is_host( player )
{
    host = zp_host_player();

    return isdefined( host ) && isdefined( player ) && player == host;
}

/*
    Whether a pause has to be put to somebody rather than simply done. In
    approval mode everybody but the host is put to the host, whatever
    zp_vote says, and the host's own pause never waits on anyone.
*/
zp_vote_wanted( player )
{
    if ( zp_host_approving() )
        return !zp_player_is_host( player );

    return level.zp.vote && !zp_vote_is_moot( player );
}

zp_vote_eligible( player )
{
    if ( !isdefined( player ) )
        return 0;

    // An approval is a vote of one. See zp_host_approve.
    if ( zp_true( level.zp_vote_approval ) )
        return zp_player_is_host( player );

    if ( !level.zp.vote_alive_only )
        return 1;

    return !zp_player_is_spectating( player );
}

zp_vote_electorate()
{
    players = getplayers();
    n = 0;

    for ( i = 0; i < players.size; i++ )
    {
        if ( zp_vote_eligible( players[i] ) )
            n++;
    }

    return n;
}

zp_vote_needed()
{
    n = zp_vote_electorate();

    if ( n < 1 )
        return 1;

    needed = level.zp.vote_min;
    pct = int( ceil( n * level.zp.vote_percent / 100 ) );

    if ( pct > needed )
        needed = pct;

    // Never ask for more votes than there are people to cast them.
    if ( needed > n )
        needed = n;

    if ( needed < 1 )
        needed = 1;

    return needed;
}

/*
    A vote the initiator alone already carries is a pause with extra steps
    -- solo play, or any lobby whose threshold lands on one.
*/
zp_vote_is_moot( player )
{
    /*
        With zp_host_only on the host is the only player who can act on a
        pause, so there is nobody to put it to.
    */
    if ( level.zp.host_only && isdefined( zp_host_player() ) )
        return 1;

    if ( !level.zp.vote_initiator_yes )
        return 0;

    // A spectator's automatic yes does not count, so it cannot carry a
    // vote on its own however small the room is.
    if ( !zp_vote_eligible( player ) )
        return 0;

    return zp_vote_needed() <= 1;
}

zp_vote_locked_out()
{
    if ( level.zp.vote_lockout <= 0 )
        return 0;

    if ( level.zp_vote_last_fail == 0 )
        return 0;

    return gettime() - level.zp_vote_last_fail < level.zp.vote_lockout * 1000;
}

zp_vote_count( want )
{
    players = getplayers();
    c = 0;

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( isdefined( p ) && isdefined( p.zp_vote ) && p.zp_vote == want && zp_vote_eligible( p ) )
            c++;
    }

    return c;
}

zp_vote_clear_ballots()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i].zp_vote = undefined;
    }
}

zp_cast_vote( player, want )
{
    if ( !zp_true( level.zp_vote_active ) || !isdefined( player ) )
        return;

    if ( isdefined( player.zp_vote ) && player.zp_vote == want )
        return;

    player.zp_vote = want;

    if ( want )
        player zp_say( "MSG_VOTED_YES" );
    else
        player zp_say( "MSG_VOTED_NO" );
}

zp_vote_start( player, kind )
{
    level.zp_vote_serial = level.zp_vote_serial + 1;
    level.zp_vote_active = 1;
    level.zp_vote_kind = kind;

    /*
        Recorded on the vote rather than read from the dvar while it runs,
        so an ordinary vote opened later cannot inherit an electorate of
        one. Cleared again in zp_vote_stop().
    */
    level.zp_vote_approval = 0;

    if ( kind == "pause" && zp_host_approving() && !zp_player_is_host( player ) )
        level.zp_vote_approval = 1;
    level.zp_vote_end_time = gettime() + int( level.zp.vote_time * 1000 );
    level.zp_vote_initiator = player;
    level.zp_vote_provisional = 0;

    level.zp_vote_name = "someone";
    if ( isdefined( player ) && isdefined( player.name ) )
        level.zp_vote_name = player.name;

    zp_vote_clear_ballots();

    /*
        The vote HUD stands in for the pause HUD while it is open. They
        would otherwise overlap in any shared slot, and the pause HUD's
        "crouch + melee to resume" contradicts the vote, where that same
        combo is a yes.
    */
    zp_vote_outcome_clear();
    zp_hud_destroy();

    if ( level.zp.vote_initiator_yes && isdefined( player ) )
        player.zp_vote = 1;

    if ( zp_true( level.zp_vote_approval ) )
        zp_say_all( "MSG_ASKS_HOST", player );
    else if ( kind == "unpause" )
        zp_say_all( "MSG_VOTE_CALLED_RESUME", player );
    else
        zp_say_all( "MSG_VOTE_CALLED_PAUSE", player );

    // The HUD spells out how to vote; only repeat it in chat without one.
    if ( !level.zp.vote_hud )
    {
        voters = getplayers();

        for ( i = 0; i < voters.size; i++ )
        {
            if ( !isdefined( voters[i] ) )
                continue;

            key = zp_vote_hint_key( voters[i] );

            if ( key != "" )
                voters[i] zp_say( "MSG_" + key, level.zp_hint_a, level.zp_hint_b );
        }
    }

    /*
        Not with zp_round_pause: holding the game the moment the vote
        opens is the one thing that setting exists to prevent, and the
        pause the vote is asking for is meant to land at the round
        boundary. The vote runs without the hold and arms it on the way
        out, the same as a pause nobody voted on.
    */
    if ( level.zp.vote_hold && kind == "pause" && !level.zp.round_pause
         && !zp_true( level.zp_paused ) )
    {
        level.zp_vote_provisional = 1;
        level thread zp_do_pause( player );
    }

    level thread zp_vote_watcher( level.zp_vote_serial );
}

zp_vote_watcher( serial )
{
    level endon( "end_game" );

    for (;;)
    {
        if ( !zp_true( level.zp_vote_active ) || level.zp_vote_serial != serial )
            return;

        needed = zp_vote_needed();
        yes = zp_vote_count( 1 );
        no = zp_vote_count( 0 );
        n = zp_vote_electorate();

        left = level.zp_vote_end_time - gettime();
        secs = int( left / 1000 );

        if ( secs < 0 )
            secs = 0;

        zp_vote_hud_update( yes, needed, secs );

        if ( yes >= needed )
        {
            zp_vote_finish( 1, yes, needed );
            return;
        }

        // Enough noes that everyone left saying yes still would not carry it.
        if ( n - no < needed )
        {
            zp_vote_finish( 0, yes, needed );
            return;
        }

        if ( left <= 0 )
        {
            zp_vote_finish( 0, yes, needed );
            return;
        }

        wait 0.1;
    }
}

zp_vote_finish( passed, yes, needed )
{
    kind = level.zp_vote_kind;
    initiator = level.zp_vote_initiator;
    provisional = zp_true( level.zp_vote_provisional );

    zp_vote_stop( 1 );

    if ( passed )
    {
        zp_say_all( "MSG_VOTE_PASSED", yes, needed );
        zp_vote_outcome( "HUD_VOTE_PASSED", yes, needed );

        if ( kind == "unpause" )
        {
            level.zp_last_toggle = gettime();
            level thread zp_do_unpause( initiator );
        }
        else if ( !zp_true( level.zp_paused ) )
        {
            level.zp_last_toggle = gettime();
            zp_begin_pause( initiator );
        }
        else
        {
            // zp_vote_hold already paused us on the way in; all that is
            // left is to give the pause HUD back.
            level thread zp_hud_show();
        }

        return;
    }

    level.zp_vote_last_fail = gettime();
    zp_say_all( "MSG_VOTE_FAILED", yes, needed );
    zp_vote_outcome( "HUD_VOTE_FAILED", yes, needed );

    // zp_vote_hold pauses on the way in, so a failed vote has to hand the
    // game back -- and hand back the allowance it spent with it. The room
    // voted the pause down; it never had one.
    if ( provisional && zp_true( level.zp_paused ) )
    {
        if ( level.zp_pause_count > 0 )
            level.zp_pause_count = level.zp_pause_count - 1;

        level.zp_last_toggle = gettime();
        level thread zp_do_unpause( undefined, "vote failed" );
        return;
    }

    // A resume vote that failed leaves the game paused, so the pause HUD
    // comes back.
    if ( zp_true( level.zp_paused ) )
        level thread zp_hud_show();
}

zp_vote_stop( keep_title )
{
    level.zp_vote_approval = 0;
    level.zp_vote_serial = level.zp_vote_serial + 1;
    level.zp_vote_active = 0;
    level.zp_vote_provisional = 0;
    level.zp_vote_initiator = undefined;

    zp_vote_clear_ballots();

    // Keeping the title is what lets zp_vote_finish() leave the result
    // standing on it for a moment. Everything under it goes either way.
    if ( zp_true( keep_title ) )
    {
        zp_vote_sub_destroy();
        zp_down_line_destroy();
        zp_vote_rows_destroy();
        return;
    }

    zp_vote_hud_destroy();
}

/*
    A vote that just vanishes leaves the result in the chat feed, which is
    the one place nobody is looking during a round. This holds it on the
    tally instead, where their eyes already are.
*/
zp_vote_outcome( key, a, b )
{
    if ( !isdefined( level.zp_vote_hud ) || level.zp.vote_result_time <= 0 )
    {
        zp_vote_hud_destroy();
        return;
    }

    // The clock has nothing left to count.
    if ( isdefined( level.zp_vote_clock ) )
    {
        zp_hud_free( level.zp_vote_clock );
        level.zp_vote_clock = undefined;
    }

    zp_show( level.zp_vote_hud, key, a, b );
    level thread zp_vote_outcome_hold();
}

zp_vote_outcome_hold()
{
    level endon( "end_game" );
    level endon( "zp_vote_outcome_clear" );

    wait( level.zp.vote_result_time );

    zp_vote_hud_destroy();
}

zp_vote_outcome_clear()
{
    level notify( "zp_vote_outcome_clear" );
    zp_vote_hud_destroy();
}


/* ==================================================================
    SETTINGS MENU

    The host changes settings while the game is paused, without a console.
    Only while paused, and not while a vote is open -- the host needs these
    buttons back to vote. The host is held in place while it is open, so
    none of them does anything in the game at the same time.

    Hold fire + melee to open it. Aim and fire move through the list,
    grenade changes the setting, melee closes it.

    Never use. Use is how a player buys, opens and picks up, and World at
    War has no script call that keeps it off a trigger; the same menu on
    every port means none of them reads it. Fire + melee is the one pair of
    what is left that no port offers as a pause combo. With one button to
    change a setting, every change goes forward and wraps: a switch flips,
    a list moves on, a number steps up through a few common values and back
    round to the lowest. Exact values are the console's.

    A change is a setdvar(), the same as typing it into the console, and
    it lands the same way: when play resumes. The pause is built from the
    settings it started with -- the HUD, what is frozen -- and nothing
    rebuilds those in place.

    Its own words go through zp_show() like every other line, so the
    Workshop build draws them in each player's language. The setting names
    and their values stay as the console spells them.

    The rows come from zp_menu_table(), which tools/mk_menu_table.py writes
    from this script's own zp_cfg calls.

    Text costs configstrings (see the HUD notes): every setting name shown
    is one, for the rest of the match. Numbers go through setvalue(), which
    costs none, so the bill is the names and a handful of words -- bounded,
    and paid once. The elements are the host's own, with no parent, so
    there is nothing to take apart if the host drops with it open.
   ================================================================== */

zp_menu_watcher()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for (;;)
    {
        wait 0.05;

        if ( zp_true( self.zp_menu_open ) || !zp_menu_allowed() || !zp_player_is_host( self ) )
            continue;

        if ( !( self attackbuttonpressed() && self meleebuttonpressed() ) )
            continue;

        held = 0;
        while ( self attackbuttonpressed() && self meleebuttonpressed() && held < level.zp.button_hold_time )
        {
            held = held + 0.05;
            wait 0.05;
        }

        if ( held < level.zp.button_hold_time || !zp_menu_allowed() )
            continue;

        self zp_menu_run();
    }
}

zp_menu_allowed()
{
    if ( !level.zp.menu || !zp_true( level.zp_paused ) || zp_true( level.zp_busy ) )
        return 0;

    return !zp_true( level.zp_vote_active );
}

/*
    Fire + melee, held by the host where the menu could open. The pause
    combo gives way to it: on T5 and T4 the default combo is melee while
    crouched, read from the stance rather than a button, so a crouched host
    opening the menu would resume the game at the same time.
*/
zp_menu_combo_held()
{
    if ( !zp_menu_allowed() || !zp_player_is_host( self ) )
        return 0;

    return self attackbuttonpressed() && self meleebuttonpressed();
}

zp_menu_run()
{
    zp_menu_table();

    if ( level.zp_menu_names.size == 0 )
        return;

    self.zp_menu_open = 1;

    // Nothing happens until the buttons that opened it are let go.
    self.zp_menu_last = "held";

    // Roaming or not, the host stands still while it is open.
    if ( zp_true( self.zp_frozen ) )
        self zp_hold_controls();

    if ( !isdefined( self.zp_menu_row ) || self.zp_menu_row >= level.zp_menu_names.size )
        self.zp_menu_row = 0;

    self zp_menu_draw_create();
    self zp_menu_draw();

    for (;;)
    {
        wait 0.05;

        if ( !zp_menu_allowed() )
            break;

        input = self zp_menu_input();

        if ( input == "close" )
            break;

        if ( input == "up" )
            self zp_menu_move( -1 );
        else if ( input == "down" )
            self zp_menu_move( 1 );
        else if ( input == "change" )
            self zp_menu_change();
    }

    self zp_menu_draw_destroy();

    // Grenade on its own is a pause combo, and melee is half of the default
    // one: everything the menu reads is let go before the combos are read.
    while ( self zp_menu_button() != "" )
        wait 0.05;

    self.zp_menu_open = undefined;

    if ( zp_true( self.zp_frozen ) )
        self zp_hold_controls();
}

/*
    One action per press. Moving repeats while the button is held, so a
    long list can be run through without tapping; changing and closing
    never repeat.
*/
zp_menu_input()
{
    b = self zp_menu_button();

    if ( b == "" )
    {
        self.zp_menu_last = "";
        return "";
    }

    if ( self.zp_menu_last == "held" )
        return "";

    now = gettime();

    if ( self.zp_menu_last != b )
    {
        self.zp_menu_last = b;
        self.zp_menu_repeat = now + 400;
        return b;
    }

    if ( b != "up" && b != "down" )
        return "";

    if ( now < self.zp_menu_repeat )
        return "";

    self.zp_menu_repeat = now + 120;
    return b;
}

zp_menu_button()
{
    if ( self meleebuttonpressed() )
        return "close";

    if ( self fragbuttonpressed() )
        return "change";

    if ( self adsbuttonpressed() )
        return "up";

    if ( self attackbuttonpressed() )
        return "down";

    return "";
}

zp_menu_move( dir )
{
    n = level.zp_menu_names.size;
    self.zp_menu_row = self.zp_menu_row + dir;

    if ( self.zp_menu_row < 0 )
        self.zp_menu_row = n - 1;

    if ( self.zp_menu_row >= n )
        self.zp_menu_row = 0;

    self zp_menu_draw();
}

/*
    Forwards, and round again. A number goes to the next value up from
    wherever it is now, so one set by hand to something in between still
    moves the right way.
*/
zp_menu_change()
{
    i = self.zp_menu_row;
    name = level.zp_menu_names[i];
    kind = level.zp_menu_kinds[i];

    if ( kind == "flag" )
    {
        value = "1";

        if ( getdvarint( name ) != 0 )
            value = "0";
    }
    else if ( kind == "choice" )
    {
        list = strtok( level.zp_menu_values[i], "|" );
        current = zp_menu_word( getdvarstring( name ) );
        value = list[0];

        for ( c = 0; c < list.size - 1; c++ )
        {
            if ( list[c] == current )
                value = list[c + 1];
        }
    }
    else
    {
        // Literals in the table, not text to parse: World at War has no
        // float(), and the menu is the same on every port.
        current = getdvarfloat( name );
        first = level.zp_menu_firsts[i];
        value = level.zp_menu_nums[first];

        for ( c = first + level.zp_menu_counts[i] - 1; c >= first; c-- )
        {
            if ( level.zp_menu_nums[c] > current + 0.001 )
                value = level.zp_menu_nums[c];
        }

        value = "" + value;
    }

    setdvar( name, value );
    self zp_menu_draw();
}

// Nothing is "none", which zp_cfg_str() reads back as nothing.
zp_menu_word( value )
{
    if ( value == "" )
        return "none";

    return value;
}

zp_menu_draw_create()
{
    self zp_menu_draw_destroy();

    bg = newclienthudelem( self );
    bg.alignx = "center";
    bg.aligny = "middle";
    bg.horzalign = "center";
    bg.vertalign = "middle";
    bg.x = 0;
    bg.y = 5;

    // Over the pause HUD, whose text sorts at 1000.
    bg.sort = 1001;
    bg.foreground = 1;
    bg.color = ( 0, 0, 0 );
    bg setshader( "black", 470, 290 );
    bg.alpha = 0.8;
    self.zp_menu_bg = bg;

    self.zp_menu_title = self zp_menu_text( "objective", 1.5, "center", 0, -120 );
    self.zp_menu_title.color = ( 1, 0.82, 0.15 );
    zp_show( self.zp_menu_title, "HUD_MENU_TITLE" );

    self.zp_menu_section = self zp_menu_text( "default", 1.2, "center", 0, -95 );

    // What the setting under the cursor does, in the README's own words --
    // the menu table carries the line, cut to the width of the panel. The
    // headings are localized; this line and the setting names are not, the
    // same as the values, which are what the console takes in any language.
    self.zp_menu_desc = self zp_menu_text( "default", 1, "center", 0, 100 );
    self.zp_menu_desc.color = ( 0.72, 0.72, 0.72 );

    self.zp_menu_hint = self zp_menu_text( "default", 1.1, "center", 0, 130 );

    self.zp_menu_names_e = [];
    self.zp_menu_values_e = [];

    /*
        Seven rows, not nine. A player is only sent so many HUD elements at
        once -- the pause HUD, the blackout, the build stamp and whatever
        else is on screen come out of the same allowance -- and past it the
        newest are silently not drawn, which cut the bottom rows off on
        Black Ops II. Moving the menu to the unarchived list (archived = 0)
        only made it worse there: four rows rather than eight.
    */
    for ( j = 0; j < 7; j++ )
    {
        self.zp_menu_names_e[j] = self zp_menu_text( "default", 1.2, "left", -215, -65 + j * 22 );
        self.zp_menu_values_e[j] = self zp_menu_text( "default", 1.2, "right", 215, -65 + j * 22 );
    }
}

zp_menu_text( font, scale, alignx, x, y )
{
    e = newclienthudelem( self );
    e.font = font;
    e.fontscale = scale;
    e.alignx = alignx;
    e.aligny = "middle";
    e.horzalign = "center";
    e.vertalign = "middle";
    e.x = x;
    e.y = y;
    e.color = ( 0.85, 0.85, 0.85 );
    zp_hud_style( e, 1 );

    // Above the menu's backing, which is over the pause HUD.
    e.sort = 1002;

    return e;
}

zp_menu_draw()
{
    if ( !isdefined( self.zp_menu_names_e ) )
        return;

    n = level.zp_menu_names.size;
    row = self.zp_menu_row;

    // Keep the chosen row on screen.
    if ( !isdefined( self.zp_menu_top ) )
        self.zp_menu_top = 0;

    if ( row < self.zp_menu_top )
        self.zp_menu_top = row;

    if ( row > self.zp_menu_top + 6 )
        self.zp_menu_top = row - 6;

    zp_menu_section_show( self.zp_menu_section, level.zp_menu_sections[row] );
    zp_hud_text( self.zp_menu_desc, level.zp_menu_descs[row] );

    if ( level.zp.hud_binds )
        zp_show( self.zp_menu_hint, "HUD_MENU_HINT_BINDS" );
    else
        zp_show( self.zp_menu_hint, "HUD_MENU_HINT" );

    for ( j = 0; j < 7; j++ )
    {
        i = self.zp_menu_top + j;
        name_e = self.zp_menu_names_e[j];
        value_e = self.zp_menu_values_e[j];

        if ( i >= n )
        {
            zp_hud_text( name_e, "" );
            zp_hud_text( value_e, "" );
            continue;
        }

        colour = ( 0.85, 0.85, 0.85 );

        if ( i == row )
            colour = ( 1, 0.82, 0.15 );

        name_e.color = colour;
        value_e.color = colour;

        zp_hud_text( name_e, level.zp_menu_names[i] );
        zp_menu_value( value_e, i );
    }
}

zp_menu_value( e, i )
{
    name = level.zp_menu_names[i];
    kind = level.zp_menu_kinds[i];

    if ( kind == "number" )
    {
        // A number costs no configstring. The text cache has to forget, or
        // the next word written to this element would look unchanged.
        e.zp_txt = undefined;
        e setvalue( getdvarfloat( name ) );
        return;
    }

    if ( kind == "choice" )
    {
        value = zp_menu_word( getdvarstring( name ) );

        if ( value == "none" )
            zp_show( e, "HUD_MENU_NONE" );
        else
            zp_hud_text( e, value );

        return;
    }

    if ( getdvarint( name ) != 0 )
        zp_show( e, "HUD_MENU_ON" );
    else
        zp_show( e, "HUD_MENU_OFF" );
}

// The section headings are the script's own, so each one has a line.
zp_menu_section_show( elem, section )
{
    if ( section == "debug" )
        zp_show( elem, "HUD_MENU_DEBUG" );
    else if ( section == "input" )
        zp_show( elem, "HUD_MENU_INPUT" );
    else if ( section == "voting" )
        zp_show( elem, "HUD_MENU_VOTING" );
    else if ( section == "timing" )
        zp_show( elem, "HUD_MENU_TIMING" );
    else if ( section == "what gets frozen" )
        zp_show( elem, "HUD_MENU_FROZEN" );
    else if ( section == "presentation" )
        zp_show( elem, "HUD_MENU_PRESENTATION" );
    else
        zp_hud_text( elem, section );
}

zp_menu_draw_destroy()
{
    if ( isdefined( self.zp_menu_bg ) )
    {
        self.zp_menu_bg destroy();
        self.zp_menu_bg = undefined;
    }

    zp_hud_free( self.zp_menu_title );
    zp_hud_free( self.zp_menu_section );
    zp_hud_free( self.zp_menu_desc );
    zp_hud_free( self.zp_menu_hint );
    self.zp_menu_title = undefined;
    self.zp_menu_section = undefined;
    self.zp_menu_desc = undefined;
    self.zp_menu_hint = undefined;

    if ( isdefined( self.zp_menu_names_e ) )
    {
        for ( j = 0; j < self.zp_menu_names_e.size; j++ )
        {
            zp_hud_free( self.zp_menu_names_e[j] );
            zp_hud_free( self.zp_menu_values_e[j] );
        }
    }

    self.zp_menu_names_e = undefined;
    self.zp_menu_values_e = undefined;
    self.zp_menu_top = undefined;
}

// ZP_MENU_BEGIN
/*
    Generated by tools/mk_menu_table.py from this script's zp_cfg calls.
    Never edit by hand. One row per setting the host's menu offers: how
    it changes -- flag, number or choice -- and what it steps through.
*/
zp_menu_table()
{
    if ( isdefined( level.zp_menu_names ) )
        return;

    level.zp_menu_names = [];
    level.zp_menu_kinds = [];
    level.zp_menu_values = [];
    level.zp_menu_sections = [];
    level.zp_menu_descs = [];
    level.zp_menu_firsts = [];
    level.zp_menu_counts = [];
    level.zp_menu_nums = [];

    zp_menu_row( "zp_host_only", "flag", "", "input", "Only the host can pause or resume. Everyone else's chat command and combo are ignored, and a pause never goes..." );
    zp_menu_row( "zp_personal_pause", "flag", "", "input", "The pause input pauses only you, and the game carries on for everyone else; it pauses in full once nobody is..." );
    zp_menu_row( "zp_pause_menu", "choice", "off|own|room", "input", "Opening the game's own pause menu pauses, and closing it resumes. own follows your own menu, room the whole..." );
    zp_menu_row( "zp_allow_short_words", "flag", "", "input", "Also accept bare p / u / pause in chat. Off by default so normal conversation can't pause the game." );
    zp_menu_row( "zp_button_combo", "flag", "", "input", "Enable the button combos." );
    zp_menu_row( "zp_combo", "choice", "crouch_melee|crouch_use|crouch_frag|crouch_ads|jump_melee|use_frag|frag_only|use_ads|use_attack|attack_ads", "input", "Which combo pauses." );
    zp_menu_row( "zp_button_hold_time", "number", "", "input", "How long the combo must be held." );
    zp_menu_num( 0.1 ); zp_menu_num( 0.2 ); zp_menu_num( 0.3 ); zp_menu_num( 0.5 ); zp_menu_num( 0.75 ); zp_menu_num( 1 ); zp_menu_num( 1.5 ); zp_menu_num( 2 );
    zp_menu_row( "zp_button_combo_dead", "choice", "use_ads|use_attack|attack_ads|use_frag|frag_only|none|crouch_use|crouch_frag|crouch_ads|crouch_melee", "input", "Combo used while downed or spectating, when stance and melee stop registering. none = chat only." );
    zp_menu_row( "zp_vote_no_combo_dead", "choice", "use_attack|crouch_use|crouch_frag|crouch_ads|crouch_melee|use_frag|frag_only|use_ads|attack_ads", "input", "The same, for a no vote." );
    zp_menu_row( "zp_input_debug", "flag", "", "input", "Print each player which buttons the server receives from them, for picking the two above." );
    zp_menu_row( "zp_ready_check", "flag", "", "voting", "Resuming waits for the players to say they're back. Not a vote - nobody says no and it can't fail, so it..." );
    zp_menu_row( "zp_ready_percent", "number", "", "voting", "How much of the room has to be ready. 100 is everybody." );
    zp_menu_num( 25 ); zp_menu_num( 50 ); zp_menu_num( 75 ); zp_menu_num( 100 );
    zp_menu_row( "zp_host_approve", "flag", "", "voting", "The host pauses at once; anyone else has to ask and the host answers yes or no. It runs as a vote only the..." );
    zp_menu_row( "zp_vote", "flag", "", "voting", "Put pauses to a vote. See Voting." );
    zp_menu_row( "zp_vote_min", "number", "", "voting", "Minimum yes votes, whatever the player count." );
    zp_menu_num( 1 ); zp_menu_num( 2 ); zp_menu_num( 3 ); zp_menu_num( 4 ); zp_menu_num( 6 ); zp_menu_num( 8 );
    zp_menu_row( "zp_vote_percent", "number", "", "voting", "Percent of players who must vote yes." );
    zp_menu_num( 25 ); zp_menu_num( 34 ); zp_menu_num( 50 ); zp_menu_num( 51 ); zp_menu_num( 67 ); zp_menu_num( 75 ); zp_menu_num( 100 );
    zp_menu_row( "zp_vote_time", "number", "", "voting", "Seconds a vote stays open." );
    zp_menu_num( 10 ); zp_menu_num( 15 ); zp_menu_num( 20 ); zp_menu_num( 30 ); zp_menu_num( 45 ); zp_menu_num( 60 ); zp_menu_num( 90 ); zp_menu_num( 120 );
    zp_menu_row( "zp_vote_unpause", "flag", "", "voting", "Resuming needs a vote too." );
    zp_menu_row( "zp_vote_hold", "flag", "", "voting", "Freeze the game while the vote runs, and resume it if the vote fails." );
    zp_menu_row( "zp_vote_initiator_yes", "flag", "", "voting", "Whoever called the vote counts as a yes." );
    zp_menu_row( "zp_vote_lockout", "number", "", "voting", "Seconds before another vote can be called after one fails." );
    zp_menu_num( 0 ); zp_menu_num( 5 ); zp_menu_num( 10 ); zp_menu_num( 20 ); zp_menu_num( 30 ); zp_menu_num( 60 ); zp_menu_num( 120 );
    zp_menu_row( "zp_vote_hud", "flag", "", "voting", "Show the vote tally on screen." );
    zp_menu_row( "zp_vote_show_voters", "flag", "", "voting", "List each player and how they voted." );
    zp_menu_row( "zp_vote_hud_position", "choice", "top|bottom|middle|left|right|center", "voting", "Where the vote tally sits. See Where the HUD sits." );
    zp_menu_row( "zp_vote_alive_only", "flag", "", "voting", "Leave bled-out spectators out of the threshold and the count." );
    zp_menu_row( "zp_vote_result_time", "number", "", "voting", "Seconds the result stands on the tally after a vote resolves. 0 = clear at once." );
    zp_menu_num( 0 ); zp_menu_num( 1 ); zp_menu_num( 2 ); zp_menu_num( 3 ); zp_menu_num( 5 ); zp_menu_num( 10 );
    zp_menu_row( "zp_vote_no_combo", "choice", "jump_melee|crouch_use|crouch_frag|crouch_ads|crouch_melee|use_frag|frag_only|use_ads|use_attack|attack_ads", "voting", "Combo for a no vote." );
    zp_menu_row( "zp_round_pause", "flag", "", "timing", "Hold a pause until the round is over instead of freezing the game mid-horde. Asking again calls it off." );
    zp_menu_row( "zp_max_pauses", "number", "", "timing", "How many times one match can be paused. 0 is no cap. Only a pause somebody asked for spends one - an..." );
    zp_menu_num( 0 ); zp_menu_num( 1 ); zp_menu_num( 2 ); zp_menu_num( 3 ); zp_menu_num( 5 ); zp_menu_num( 10 ); zp_menu_num( 20 );
    zp_menu_row( "zp_pause_on_disconnect", "flag", "", "timing", "Pause when somebody drops, so whoever is left isn't overrun while they rejoin. Nothing un-pauses on its own..." );
    zp_menu_row( "zp_countdown", "number", "", "timing", "Seconds of 3-2-1 before play resumes." );
    zp_menu_num( 0 ); zp_menu_num( 1 ); zp_menu_num( 2 ); zp_menu_num( 3 ); zp_menu_num( 5 ); zp_menu_num( 10 );
    zp_menu_row( "zp_ease", "flag", "", "timing", "Ease time down into the pause and back out, instead of cutting to a stop." );
    zp_menu_row( "zp_ease_time", "number", "", "timing", "Seconds of ramp at each end." );
    zp_menu_num( 0 ); zp_menu_num( 0.1 ); zp_menu_num( 0.2 ); zp_menu_num( 0.35 ); zp_menu_num( 0.5 ); zp_menu_num( 0.75 ); zp_menu_num( 1 );
    zp_menu_row( "zp_grace", "number", "", "timing", "Seconds of invulnerability after resuming." );
    zp_menu_num( 0 ); zp_menu_num( 1 ); zp_menu_num( 2 ); zp_menu_num( 3 ); zp_menu_num( 5 ); zp_menu_num( 10 );
    zp_menu_row( "zp_cooldown", "number", "", "timing", "Minimum seconds between toggles." );
    zp_menu_num( 0 ); zp_menu_num( 1 ); zp_menu_num( 2 ); zp_menu_num( 3 ); zp_menu_num( 5 ); zp_menu_num( 10 ); zp_menu_num( 30 );
    zp_menu_row( "zp_max_pause_time", "number", "", "timing", "Auto-resume after N seconds. 0 = unlimited." );
    zp_menu_num( 0 ); zp_menu_num( 60 ); zp_menu_num( 120 ); zp_menu_num( 300 ); zp_menu_num( 600 ); zp_menu_num( 900 ); zp_menu_num( 1800 ); zp_menu_num( 3600 );
    zp_menu_row( "zp_engine_freeze", "flag", "", "what gets frozen", "Use setpauseworld() and the world_is_paused flag." );
    zp_menu_row( "zp_drift_guard", "flag", "", "what gets frozen", "Snap back any AI that still manages to move." );
    zp_menu_row( "zp_freeze_anims", "flag", "", "what gets frozen", "No effect on this engine - the world freeze already stops animation." );
    zp_menu_row( "zp_silence_zombies", "flag", "", "what gets frozen", "Stop zombies growling while paused." );
    zp_menu_row( "zp_godmode", "flag", "", "what gets frozen", "Make players invulnerable while paused." );
    zp_menu_row( "zp_freeze_players", "flag", "", "what gets frozen", "Lock players in place while paused. 0 lets them walk around with their weapons down, locked again for the..." );
    zp_menu_row( "zp_control_guard", "flag", "", "what gets frozen", "Re-apply the player freeze every tick, so a map script can't hand controls back mid-pause." );
    zp_menu_row( "zp_freeze_clock", "flag", "", "what gets frozen", "Hold the match timer." );
    zp_menu_row( "zp_freeze_powerups", "flag", "", "what gets frozen", "Stop ground powerups timing out." );
    zp_menu_row( "zp_freeze_effects", "flag", "", "what gets frozen", "Hold insta-kill / double-points countdowns." );
    zp_menu_row( "zp_freeze_bleedout", "flag", "", "what gets frozen", "Stop downed players bleeding out." );
    zp_menu_row( "zp_hud", "flag", "", "presentation", "Draw the pause block at all. The vote HUD is separate and still draws." );
    zp_menu_row( "zp_blackout", "flag", "", "presentation", "Dim everyone's screen while paused, which keeps the pause text readable over a bright skybox. Raise..." );
    zp_menu_row( "zp_blackout_alpha", "number", "", "presentation", "How far it dims. 0.2 is a light darkening; 1 is fully black." );
    zp_menu_num( 0.1 ); zp_menu_num( 0.2 ); zp_menu_num( 0.35 ); zp_menu_num( 0.5 ); zp_menu_num( 0.65 ); zp_menu_num( 0.8 ); zp_menu_num( 1 );
    zp_menu_row( "zp_show_hint", "flag", "", "presentation", "Tell players how to pause when they spawn." );
    zp_menu_row( "zp_hud_position", "choice", "center|top|bottom|middle|left|right", "presentation", "Where the pause banner sits. See Where the HUD sits." );
    zp_menu_row( "zp_hud_binds", "flag", "", "presentation", "Draw combos as each player's bound buttons instead of words." );
    zp_menu_row( "zp_hud_glow", "flag", "", "presentation", "Black glow behind the HUD text, to carry it over a bright skybox." );
    zp_menu_row( "zp_hud_panel", "flag", "", "presentation", "Black slab behind the whole block. Heavier than the glow." );
    zp_menu_row( "zp_hud_panel_alpha", "number", "", "presentation", "How opaque that slab is. 1 is solid black." );
    zp_menu_num( 0.2 ); zp_menu_num( 0.35 ); zp_menu_num( 0.45 ); zp_menu_num( 0.6 ); zp_menu_num( 0.8 ); zp_menu_num( 1 );
    zp_menu_row( "zp_hud_panel_width", "number", "", "presentation", "How wide it is, in HUD units." );
    zp_menu_num( 240 ); zp_menu_num( 300 ); zp_menu_num( 340 ); zp_menu_num( 400 ); zp_menu_num( 480 ); zp_menu_num( 560 ); zp_menu_num( 640 );
    zp_menu_row( "zp_hud_timer", "flag", "", "presentation", "Show who paused and how long it has been. Minutes, not mm:ss - see below." );
    zp_menu_row( "zp_blur", "flag", "", "presentation", "Blur everyone's screen while paused. Clears when play resumes." );
    zp_menu_row( "zp_blur_amount", "number", "", "presentation", "Blur strength. 4 is the blur the game runs when you buy a perk." );
    zp_menu_num( 0.5 ); zp_menu_num( 1 ); zp_menu_num( 1.5 ); zp_menu_num( 2 ); zp_menu_num( 3 ); zp_menu_num( 4 ); zp_menu_num( 6 );
    zp_menu_row( "zp_pause_sound", "choice", "zmb_bgb_killingtime_start|none", "presentation", "Played when the game is paused. none = silent." );
    zp_menu_row( "zp_countdown_sound", "choice", "zmb_finalcountdown_timer_marker|none", "presentation", "Played on each countdown tick. none = silent." );
    zp_menu_row( "zp_resume_sound", "choice", "zmb_bgb_killingtime_end|none", "presentation", "Played when play resumes. none = silent." );
}

zp_menu_row( name, kind, values, section, desc )
{
    i = level.zp_menu_names.size;

    level.zp_menu_names[i] = name;
    level.zp_menu_kinds[i] = kind;
    level.zp_menu_values[i] = values;
    level.zp_menu_sections[i] = section;
    level.zp_menu_descs[i] = desc;
    level.zp_menu_firsts[i] = level.zp_menu_nums.size;
    level.zp_menu_counts[i] = 0;
}

// One of the values the row just added steps through.
zp_menu_num( value )
{
    i = level.zp_menu_names.size - 1;

    level.zp_menu_nums[level.zp_menu_nums.size] = value;
    level.zp_menu_counts[i] = level.zp_menu_counts[i] + 1;
}
// ZP_MENU_END

/* ==================================================================
    VOTE HUD

    Server hud elements, the same as the pause HUD: created host-side and
    replicated, so a player running no scripts at all still sees the tally
    and which buttons to hold.
   ================================================================== */

/*
    A HUD element the engine would not make, kept where somebody can read
    it: zp_hud_missing names the last line that could not be drawn, and the
    console shows it with zp_hud_missing on its own.

    Nothing of ours can fix it -- these come out of pools the whole server
    shares, and several mods drawing at once is how one runs dry -- but a
    pause banner missing half its text looks exactly like a mod that forgot
    to draw, and this is the difference. println() is inside a devblock on
    this engine, so a dvar is where it goes.
*/
zp_hud_missing( what )
{
    setdvar( "zp_hud_missing", what );
}

zp_hud_text( elem, txt )
{
    if ( !isdefined( elem ) )
        return;

    // settext every tick would be pointless network traffic.
    if ( isdefined( elem.zp_txt ) && elem.zp_txt == txt )
        return;

    elem.zp_txt = txt;
    elem settext( txt );
}

/*
    No clock in here. The seconds live on their own timer element -- every
    distinct string handed to settext() takes a configstring, and a line
    rewritten once a second burns the pool.
*/
/*
    Which vote hint this player gets, as a key the HUD draws with HUD_ in
    front and chat prints with MSG_ in front. The combos it needs are left
    in level.zp_hint_a and level.zp_hint_b for the caller to hand on.
*/
zp_vote_hint_key( player )
{
    level.zp_hint_a = undefined;
    level.zp_hint_b = undefined;

    // Only the host can answer an approval, so nobody else is told how.
    if ( zp_true( level.zp_vote_approval ) && !zp_player_is_host( player ) )
        return "VOTE_WAITING_HOST";

    if ( !level.zp.button_combo )
        return "";

    yes_combo = level.zp.combo;
    no_combo = level.zp.vote_no_combo;

    // Down on the floor or spectating: show the combo that still works
    // for this player rather than the one everybody else is using.
    if ( isdefined( player ) && zp_player_input_limited( player ) )
    {
        yes_combo = level.zp.button_combo_dead;
        no_combo = level.zp.vote_no_combo_dead;
    }

    if ( yes_combo == "" && no_combo == "" )
        return "";

    if ( yes_combo == "" )
    {
        level.zp_hint_a = no_combo;
        return "VOTE_HINT_NO";
    }

    if ( no_combo == "" )
    {
        level.zp_hint_a = yes_combo;
        return "VOTE_HINT_YES";
    }

    level.zp_hint_a = yes_combo;
    level.zp_hint_b = no_combo;
    return "VOTE_HINT_YES_NO";
}

zp_vote_sub_show( player )
{
    if ( !isdefined( player ) )
        return;

    if ( !isdefined( player.zp_vote_sub ) )
        player.zp_vote_sub = player zp_subline_create( level.zp.vote_hud_position, 52, 1.1, 0.75 );

    key = zp_vote_hint_key( player );

    if ( key != "" )
        key = "HUD_" + key;

    zp_show( player.zp_vote_sub, key, level.zp_hint_a, level.zp_hint_b );
}

zp_vote_sub_destroy()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( isdefined( p ) && isdefined( p.zp_vote_sub ) )
        {
            zp_hud_free( p.zp_vote_sub );
            p.zp_vote_sub = undefined;
        }
    }
}

zp_vote_hud_update( yes, needed, secs )
{
    if ( !level.zp.vote_hud )
        return;

    if ( !isdefined( level.zp_vote_hud ) )
    {
        // The pause HUD is taken down for the duration of a vote, so these
        // two blocks never share the screen and can both use any slot.
        level.zp_vote_hud = hud::createServerFontString( "objective", 1.5 );
        zp_hud_place( level.zp_vote_hud, level.zp.vote_hud_position, 0 );
        level.zp_vote_hud.color = ( 1, 0.82, 0.15 );
        zp_hud_style( level.zp_vote_hud, 0.9 );

        // Handed the remaining seconds once; it counts down on the client.
        level.zp_vote_clock = hud::createServerTimer( "objective", 1.2 );
        zp_hud_place( level.zp_vote_clock, level.zp.vote_hud_position, 28 );
        level.zp_vote_clock.color = ( 1, 0.82, 0.15 );
        zp_hud_style( level.zp_vote_clock, 0.9 );
        level.zp_vote_clock settimer( secs );
    }

    if ( zp_true( level.zp_vote_approval ) )
        zp_show( level.zp_vote_hud, "HUD_VOTE_TITLE_REQUEST" );
    else if ( level.zp_vote_kind == "unpause" )
        zp_show( level.zp_vote_hud, "HUD_VOTE_TITLE_RESUME", yes, needed );
    else
        zp_show( level.zp_vote_hud, "HUD_VOTE_TITLE_PAUSE", yes, needed );

    // Recolouring an element costs nothing, unlike rewriting its text.
    if ( isdefined( level.zp_vote_clock ) )
    {
        if ( secs <= 5 )
            level.zp_vote_clock.color = ( 1, 0.3, 0.3 );
        else
            level.zp_vote_clock.color = ( 1, 0.82, 0.15 );
    }

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
        zp_vote_sub_show( players[i] );

    zp_down_line_show( level.zp.vote_hud_position, 74, "vote" );

    zp_vote_hud_rows();

    h = 64;

    if ( isdefined( level.zp_down_line ) )
        h = 84;

    if ( level.zp.vote_show_voters && players.size > 0 )
        h = 94 + players.size * 15;

    zp_panel_show( level.zp.vote_hud_position, h );
}

zp_vote_hud_rows()
{
    if ( !isdefined( level.zp_vote_rows ) )
        level.zp_vote_rows = [];

    if ( !level.zp.vote_show_voters )
    {
        zp_vote_rows_destroy();
        return;
    }

    players = getplayers();

    // Somebody left: rebuild rather than leave a stale row on screen.
    if ( level.zp_vote_rows.size > players.size )
        zp_vote_rows_destroy();

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( !isdefined( p ) )
            continue;

        if ( !isdefined( level.zp_vote_rows[i] ) )
        {
            e = hud::createServerFontString( "default", 1.0 );
            zp_hud_place( e, level.zp.vote_hud_position, 94 + i * 15 );
            zp_hud_style( e, 0.7 );
            level.zp_vote_rows[i] = e;
        }

        if ( !zp_vote_eligible( p ) )
            zp_show( level.zp_vote_rows[i], "HUD_ROW_SPECTATING", p );
        else if ( !isdefined( p.zp_vote ) )
            zp_show( level.zp_vote_rows[i], "HUD_ROW_NONE", p );
        else if ( p.zp_vote == 1 )
            zp_show( level.zp_vote_rows[i], "HUD_ROW_YES", p );
        else
            zp_show( level.zp_vote_rows[i], "HUD_ROW_NO", p );
    }
}

zp_vote_rows_destroy()
{
    if ( !isdefined( level.zp_vote_rows ) )
    {
        level.zp_vote_rows = [];
        return;
    }

    // Same reasoning as the config struct: an array is a parent variable,
    // and this is reached on a tick whenever the voter list is off.
    if ( level.zp_vote_rows.size == 0 )
        return;

    keys = getarraykeys( level.zp_vote_rows );

    for ( i = 0; i < keys.size; i++ )
    {
        if ( isdefined( level.zp_vote_rows[ keys[i] ] ) )
            zp_hud_free( level.zp_vote_rows[ keys[i] ] );
    }

    level.zp_vote_rows = [];
}

zp_vote_hud_destroy()
{
    if ( isdefined( level.zp_vote_hud ) )
    {
        zp_hud_free( level.zp_vote_hud );
        level.zp_vote_hud = undefined;
    }

    if ( isdefined( level.zp_vote_clock ) )
    {
        zp_hud_free( level.zp_vote_clock );
        level.zp_vote_clock = undefined;
    }

    zp_vote_sub_destroy();
    zp_down_line_destroy();
    zp_panel_destroy();
    zp_vote_rows_destroy();
}


/* ==================================================================
    THE SHARED MOD API

    Xep's mods find each other on level.zmods: an array keyed by mod id,
    each key a struct saying what that mod is and handing over the few
    things another mod may ask it to do. ZPause's goes up as the script
    finishes loading, and again -- saying enabled 0 -- when zp_enabled is
    off, since "not installed" and "installed and switched off" are
    different answers.

    Nothing outside calls zp_do_pause() or zp_do_unpause(). The requests
    below go in at the same door the chat words, the button combo and the
    game's own pause menu use, so a pause
    another mod asks for still answers to zp_host_only, the vote, the
    cooldown and zp_max_pauses, and cannot arrive while the game is
    already busy putting one up or taking one down.

    ZPause's public API handoff is the contract. api_version 1 is this.
   ================================================================== */

/*
    The descriptor. Written into whatever registry is already there --
    another mod may have made it first, and replacing the array would be
    that mod's entry gone.
*/
zp_api_register( benabled )
{
    if ( !isdefined( level.zmods ) )
        level.zmods = [];

    if ( !isdefined( level.zmods[ "zpause" ] ) )
        level.zmods[ "zpause" ] = spawnstruct();

    mod = level.zmods[ "zpause" ];

    mod.id = "zpause";
    mod.display_name = "ZPause";
    mod.version = zp_version();
    mod.api_version = 1;
    mod.settings_manifest_version = 1;
    mod.enabled = benabled;

    mod.reload_config = &zp_api_reload_config;
    mod.request_toggle = &zp_api_request_toggle;
    mod.request_pause = &zp_api_request_pause;
    mod.request_unpause = &zp_api_request_unpause;
    mod.is_paused = &zp_api_is_paused;
}

/*
    Read the settings again -- for a mod that has just written one of
    ZPause's dvars and wants it to count now rather than at the next
    pause. 1 when there was something to read.
*/
zp_api_reload_config()
{
    if ( !zp_true( level.zp_loaded ) || !isdefined( level.zp ) || !level.zp.enabled )
        return 0;

    zp_load_config();
    return 1;
}

/*
    Whether the game is paused. level.zp_paused is ZPause's own field and
    not the contract: this is.
*/
zp_api_is_paused()
{
    if ( zp_true( level.zp_paused ) )
        return 1;

    return 0;
}

/*
    Who a request with no initiator of its own belongs to. The host, and
    where the engine will not say who that is -- some clients answer
    ishost() for nobody, and a dedicated server has no host at all -- the
    player who is alone in the game, since there is no one else it could
    be. A menu press is the host's by construction: the row is only drawn
    on the host's own screen.
*/
zp_api_initiator()
{
    host = zp_host_player();

    if ( isdefined( host ) )
        return host;

    players = getplayers();

    if ( players.size == 1 )
        return players[0];

    return undefined;
}

zp_api_request_toggle( player )
{
    return zp_api_request( player, "toggle" );
}

zp_api_request_pause( player )
{
    return zp_api_request( player, "pause" );
}

zp_api_request_unpause( player )
{
    return zp_api_request( player, "unpause" );
}

/*
    One door for the three above. An undefined initiator is the host
    asking, which is what a press on a menu row is.
*/
zp_api_request( player, what )
{
    if ( !zp_true( level.zp_loaded ) || !isdefined( level.zp ) || !level.zp.enabled )
        return 0;

    if ( !isdefined( player ) )
        player = zp_api_initiator();

    if ( !isdefined( player ) )
        return 0;

    /*
        Threaded, the same as the chat word and the button combo: a request can end up
        waiting on a vote, and a caller is not made to wait with it.
    */
    if ( what == "pause" )
        level thread zp_request_pause( player );
    else if ( what == "unpause" )
        level thread zp_request_unpause( player );
    else
        level thread zp_request_toggle( player );

    return 1;
}

/*
    The menu's own press, arriving the way the pause menu reports itself:
    Engine.SendMenuResponse() under the menu name "zpause". Anybody's
    press is taken: the row is every player's, and a press goes through
    the same gates a combo does.
*/
zp_api_menu_request( response )
{
    if ( !isdefined( response ) )
        return;

    if ( response != "request_toggle" && response != "request_pause"
         && response != "request_unpause" )
        return;

    /*
        Anybody's press, since 1.7 (Xep, 11 October 2026): the pause menu's
        row is everybody's, on the combo's rules, and it goes in at the same
        door the combo does. zp_host_only, the vote, the host's approval and
        a personal pause all still decide inside the request - a press
        zp_host_only would turn away is turned away there, with the same line
        a combo gets.
    */

    /*
        A resume asked for from inside the pause menu is not the pause
        menu's own resume as well: without this, closing the menu
        afterwards would ask for a second one.
    */
    self.zp_menu_paused = undefined;

    if ( zp_ui_press_seen( self ) )
        return;

    level.zp_ui_pressed_at = gettime();

    if ( response == "request_pause" )
        zp_api_request_pause( self );
    else if ( response == "request_unpause" )
        zp_api_request_unpause( self );
    else
        zp_api_request_toggle( self );
}

/*
    What the menu needs and cannot work out for itself: whether ZPause is
    running in this match, and whether the game is paused right now --
    which is what decides between PAUSE GAME and UNPAUSE GAME on the row.

    Published from one place rather than from every path that could move
    either, so no path can forget. The menu is the host's own screen, in
    the host's own game, so a dvar reaches it.
*/
/*
    The other road a menu press takes. zp_ui_request is written by the
    settings page and by whatever shell a bundle draws, and read and
    cleared here: one word, no serial, because clearing it is what makes
    the next press a new one.

    Two roads rather than one because only one of them is proven on every
    client. The menu response is the road the pause menu already reports
    itself on, and a dvar is the road every setting on that screen already
    travels -- a press that arrives twice is a press that arrives, since
    the first one to be served clears the other.
*/
/*
    One press, two roads, one serve. The host's own page writes
    zp_ui_request and sends the menu response as well, so the same press can
    arrive twice a tenth of a second apart. Served twice, a second press calls
    off the round-end pause the first one armed, ends the personal pause it
    started, and with zp_cooldown 0 resumes the pause it made. Whichever road
    is served first stamps the time; the other road, for the host, within half
    a second, is the same press and is dropped. A client's press only ever
    arrives as a menu response -- their dvar is their own game's -- so nothing
    of theirs is ever dropped.
*/
zp_ui_press_seen( player )
{
    if ( !isdefined( level.zp_ui_pressed_at ) )
        return 0;

    if ( gettime() - level.zp_ui_pressed_at > 500 )
        return 0;

    host = zp_host_player();

    return !isdefined( player ) || ( isdefined( host ) && player == host );
}

zp_api_request_watcher()
{
    level endon( "end_game" );

    setdvar( "zp_ui_request", "" );

    for (;;)
    {
        wait 0.1;

        asked = getdvarstring( "zp_ui_request" );

        if ( asked == "" )
            continue;

        // Cleared before it is served: a request that cannot be served is
        // still one that has been answered, and a dvar left set would be
        // acted on again a tenth of a second later.
        setdvar( "zp_ui_request", "" );

        if ( zp_ui_press_seen( undefined ) )
            continue;

        level.zp_ui_pressed_at = gettime();

        if ( asked == "pause" )
            zp_api_request_pause( undefined );
        else if ( asked == "unpause" )
            zp_api_request_unpause( undefined );
        else if ( asked == "toggle" )
            zp_api_request_toggle( undefined );
    }
}

zp_ui_publisher()
{
    level endon( "end_game" );

    level thread zp_ui_clear();
    level thread zp_api_request_watcher();

    setdvar( "zp_ui_active", "1" );
    setdvar( "zp_ui_paused", "0" );
    setdvar( "zp_ui_menu_pause", "0" );

    last = "0";
    last_menu = "0";
    tick = 0;

    for (;;)
    {
        wait 0.5;

        tick++;

        /*
            Whether opening the pause menu is itself the pause. It is what
            takes the menu's own PAUSE GAME row away: with zp_pause_menu on
            the menu has already pressed pause by the time the row could be
            read, and a row that says the opposite of what just happened is
            worse than no row.
        */
        menu = "0";

        if ( zp_menu_on() )
            menu = "1";

        if ( menu != last_menu )
        {
            last_menu = menu;
            setdvar( "zp_ui_menu_pause", menu );
        }

        now = "0";

        if ( zp_true( level.zp_paused ) || zp_true( level.zp_pending ) )
        {
            now = "1";
        }
        else
        {
            host = zp_host_player();

            if ( isdefined( host ) && zp_true( host.zp_personal ) )
                now = "1";
        }

        if ( now != last )
        {
            last = now;
            setdvar( "zp_ui_paused", now );
        }

        // And every player's own menu, the host's included: every fourth
        // pass is a heartbeat, so two seconds is the most one can be behind.
        zp_ui_tell_all( int( menu ), tick % 4 == 0 );
    }
}

zp_ui_clear()
{
    level waittill( "end_game" );

    setdvar( "zp_ui_active", "0" );
    setdvar( "zp_ui_paused", "0" );
    setdvar( "zp_ui_menu_pause", "0" );
    setdvar( "zp_ui_request", "" );

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
        players[ i ] zp_ui_tell( 0, 0, 0, 0, 1 );
}

/*
    One player's view of the pause, for their own pause menu. A client's game
    is not the server, so the dvars the publisher writes are the host's alone:
    a player who is not the host learns the state from this instead, which is
    what lets their pause menu carry PAUSE GAME too (1.7, Xep: the row is
    everybody's, on the combo's rules). Four numbers: whether ZPause is
    running, whether the game is paused for them - a personal pause included -
    whether opening the menu is itself the pause, and whether zp_host_only
    leaves them a pause to ask for at all.

    **The name is declared with #precache( "eventstring", "zpause_state" )**
    at the top of the file, as the stock scripts declare theirs. An event name
    nothing has precached throws "LUI event name (string) is not precached" when
    it is sent, whether it is built with istring() or written as the literal,
    and the exception takes down the thread it is in: the publisher, so the
    host's own PAUSE GAME label and the room's state would stop updating a
    second into the match. The declaration is what ZStats' loose scripts carry.
*/
zp_ui_tell_all( menu, again )
{
    host = zp_host_player();
    held = zp_true( level.zp_paused ) || zp_true( level.zp_pending );
    only = isdefined( level.zp ) && zp_true( level.zp.host_only );
    personal = isdefined( level.zp ) && zp_true( level.zp.personal_pause );
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        player = players[ i ];

        mine = 0;

        if ( held || zp_true( player.zp_personal ) )
            mine = 1;

        allowed = 1;

        // As the combo decides it: a personal pause is every player's even
        // with zp_host_only on, since it pauses nobody but them.
        if ( only && !personal && isdefined( host ) && player != host )
            allowed = 0;

        player zp_ui_tell( 1, mine, menu, allowed, again );
    }
}

/*
    Sent when it changes for this player, and when asked to say it again: a
    menu that missed one is never more than a heartbeat out of date.
*/
zp_ui_tell( active, paused, menu, allowed, again )
{
    said = "" + active + paused + menu + allowed;

    if ( !again && isdefined( self.zp_ui_said ) && self.zp_ui_said == said )
        return;

    self.zp_ui_said = said;

    self luinotifyevent( &"zpause_state", 4, active, paused, menu, allowed );
}


/* ==================================================================
    SAFETY

    If the game ends while paused, tear everything down so nobody is
    left frozen, blacked out, or staring at a stale HUD element.
   ================================================================== */

/* ==================================================================
    BUILD STAMP

    A development build says so on screen: its version and the time it was
    built, top right, under Plutonium's own watermark. Two hours into a
    test session that is the difference between knowing which build you
    are looking at and guessing.

    Release builds carry an empty stamp and draw nothing, so this costs a
    released mod one function call at startup and no HUD element.
   ================================================================== */

/*
    Written by tools/build.py. The line between the markers is generated --
    a version and a build time on a development build, an empty string on
    a release. Do not edit it by hand; the next build will overwrite it.
*/
/*
    The version on its own, without the build time or the word ZPause:
    what level.zmods says ZPause is. Written by tools/build.py between the
    markers, the same as the stamp below, and never by hand.
*/
zp_version()
{
    // ZP_VERSION_BEGIN
    return "1.8";
    // ZP_VERSION_END
}

zp_build()
{
    // ZP_BUILD_BEGIN
    return "";
    // ZP_BUILD_END
}

/*
    Hands the value straight back, so it can wrap a return. Silent unless
    zp_config_printer() has the echo on.
*/
zp_cfg_echo( dvar, value, def )
{
    if ( !zp_true( level.zp_cfg_echo ) )
        return value;

    /#
        println( "  " + dvar + "  " + value );
    #/

    // On screen, only what somebody actually changed. All fifty would
    // scroll off, and the defaults are in the README.
    if ( isdefined( level.zp_cfg_host ) && value != ( "" + def ) )
        level.zp_cfg_host iprintln( "^3" + dvar + "^7  " + value );

    return value;
}

/*
    "set zp_config_print 1" in the console prints every setting and the
    value it is currently holding.

    Black Ops III completes the dvars its engine registered and not the
    ones a script creates, so the zp_ names never show up in its console
    suggestions and there is no GSC call that would add them. This is the
    part that is in reach, and it is worth having on every port.

    The echo rides on zp_cfg_int/float/str rather than a list kept here,
    so a setting added later prints without anyone having to remember it.

    println is a dev-only call on this engine and the game refuses to load
    a script that makes one outside a devblock -- "Dev only calls must be
    wrapped in a devblock". Stock does the same with 768 of its 806. So
    the dump needs a client running developer mode, which is the same
    thing that gets you the console it prints to.
*/
/*
    Picks up a dvar changed mid-game.

    zp_load_config() runs on every pause request already, so pausing has
    always used current settings. This is for the ones the input watchers
    read continuously -- zp_combo above all, which without the chat
    commands could not be changed by hand at all, because changing it
    needed a pause and the combo is what asks for one.

    Not while paused or busy: the HUD is built from these when the pause
    starts and nothing rebuilds it in place, so moving them underneath
    would leave elements where the old values put them. It lands as soon
    as play resumes.

    A few dozen dvar reads every five seconds, and no writes once they all
    exist. The tick is only for a setting changed by hand mid-game --
    pausing and resuming both re-read the config themselves, so neither
    ever waits on it.
*/
zp_config_watcher()
{
    level endon( "end_game" );

    for (;;)
    {
        wait 5;

        if ( zp_true( level.zp_paused ) || zp_true( level.zp_busy ) )
            continue;

        zp_load_config();
    }
}

zp_config_printer()
{
    level endon( "end_game" );

    // Create it, so there is something to set.
    if ( getdvarstring( "zp_config_print" ) == "" )
        setdvar( "zp_config_print", "0" );

    for ( ;; )
    {
        wait 1;

        if ( getdvarstring( "zp_config_print" ) != "1" )
            continue;

        setdvar( "zp_config_print", "0" );

        /# println( "---- ZPause settings ----" ); #/
        /*
            The header and footer are unconditional: they are what
            says the switch was read at all, which is the question
            being asked when somebody reaches for this.
        */
        level.zp_cfg_host = zp_host_player();

        /*
            Any player will do if there is no host to be found. A
            dump nobody can see is the same as no dump, and this is
            reached for precisely when something is already unclear.
        */
        if ( !isdefined( level.zp_cfg_host ) )
        {
            zp_cfg_players = getplayers();

            if ( zp_cfg_players.size > 0 )
                level.zp_cfg_host = zp_cfg_players[0];
        }

        if ( isdefined( level.zp_cfg_host ) )
            level.zp_cfg_host iprintln( "^3[ZPause]^7 settings changed from default:" );

        level.zp_cfg_echo = 1;
        zp_load_config();
        level.zp_cfg_echo = 0;

        if ( isdefined( level.zp_cfg_host ) )
            level.zp_cfg_host iprintln( "^3[ZPause]^7 end of settings" );

        level.zp_cfg_host = undefined;
        /# println( "---- end ----" ); #/
    }
}

zp_build_watermark()
{
    level endon( "end_game" );

    stamp = zp_build();

    if ( stamp == "" )
        return;

    // Nothing can be drawn before the game is actually up.
    while ( !zp_game_ready() )
        wait 0.5;

    if ( isdefined( level.zp_build_hud ) )
        return;

    /*
        Scale 1.1, and not the 0.9 a watermark looks like it wants: a font
        scale below 1 does not shrink the text on any of these engines, it
        falls back to something several times larger. Every other element
        here asks for 1.0 or more, and release_check.py enforces it.

        Offsets are measured from inside the safe area and anything past it
        is clipped, by a different amount per engine and per aspect ratio
        -- which is how this went off screen on three ports and not the
        fourth. 0, 8 is the corner itself.
    */
    e = hud::createServerFontString( "objective", 1.1 );
    e hud::setPoint( "TOPRIGHT", "TOPRIGHT", 0, 8 );
    e.color = ( 1, 0.82, 0.15 );
    zp_hud_style( e, 0.7 );
    /*
        The origin rides along with the stamp. Only the copy that won the
        zp_origin_wanted() gate ever gets here, so whatever this says is
        the copy actually running -- which is the whole question
        zp_only_script and zp_only_mod are for, and it cannot be answered
        by looking at two identical-looking games.
    */
    e settext( stamp + "  [" + zp_origin() + "]" );

    level.zp_build_hud = e;
}

zp_endgame_safety()
{
    level waittill( "end_game" );

    level notify( "zp_thaw" );

    zp_vote_stop();
    zp_hud_destroy();
    zp_ai_thaw();

    players = getplayers();
    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( !isdefined( p ) )
            continue;

        p zp_blackout_off();
        p zp_blur_off();
        p zp_menu_draw_destroy();
        p.zp_menu_open = undefined;

        // Personal pauses end with the game, the same as the rest of it.
        p notify( "zp_personal_off" );
        p.zp_personal = undefined;
        p zp_personal_hud_off();

        if ( zp_true( p.zp_frozen ) )
        {
            p.zp_frozen = undefined;
            p freezecontrols( 0 );
            p zp_release_weapons();

            if ( zp_true( p.zp_invulnerable ) )
            {
                p.zp_invulnerable = undefined;
                p disableinvulnerability();
            }
        }
    }

    if ( zp_true( level.zp_engine_held ) )
        level thread zp_engine_zombies( 1 );

    level.zp_engine_held = undefined;

    level.zp_paused = 0;
    level.zp_busy = 0;
}
