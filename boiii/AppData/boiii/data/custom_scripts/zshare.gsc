/*
======================================================================
    ZSHARE T7 v1.4  --  Weapon sharing for Black Ops III Zombies

    by Xep

======================================================================

    A port of ZShare (Plutonium T6) to Black Ops III. A fork of the T6
    build rather than the older two: this engine has the same unitrigger
    system, the same box states, the same validation hooks and the same
    perk limit hook, so what a player does is identical.

        Weapons   Look at a teammate and press use. They see the gun in
                  your hands, look back at you and press use, and the
                  two weapons change hands -- ammo, attachments, camo
                  and the Alternate Ammo Type with them.
        Points    Crouch first, then use: 1000 points go across.
        Box hits  Paid for a box weapon you do not want? Crouch and
                  press use at the box, and it is anyone's to take. The
                  same at the Pack-a-Punch.
        Paying    Crouch and press use at a perk machine, or at the box
                  or the Pack-a-Punch while nobody is using it, and the
                  next teammate to use that machine pays nothing.

    Everything runs on the host. Nobody else needs this file.

----------------------------------------------------------------------
    HOW IT DIFFERS FROM THE T6 BUILD

    One rule shapes this port: **hooks and displacement, never detour.**
    Black Ops III has four ways to run a script -- the injected route,
    BOIII, T7x and the Steam Workshop -- and only two of them can replace
    a stock function at all. A port built on detours would be a different
    mod on each route, so ZShare uses what every route has:

      Hooks the game already offers. level.custom_perk_validation before
      a drink, level.pack_a_punch.custom_validation before a pack,
      level.get_player_perk_purchase_limit for the limit, and the magic
      box's own unitrigger stub for the press.

      Displacement for the two loops T6 replaces. A stock loop that ends
      older copies of itself with a notify can be ended from outside, and
      ZShare's copy of it started in the same frame. The Pack-a-Punch
      trigger loop ends on "pack_a_punch_trigger_think"; the perk loops
      end on "death".

    The chat word is the other difference. Black Ops III raises its chat
    notify on the player who typed rather than on the level, so the
    listener is per player.

    And the words themselves. Every line a player reads goes by key --
    zs_say( "MSG_GAVE", to, amount ) -- through the TEXT block at the
    bottom, which is generated from zshare-text.json. The loose builds
    carry it in English; the Workshop build carries the same keys over
    localized strings, so each player reads their own language.

----------------------------------------------------------------------
    VERIFICATION

    gsc-tool answers "not implemented" for both Black Ops III dialects,
    so this gets the T5 and T4 treatment: every call, field, notify and
    flag is checked against the stock script dump. See audit.py and
    deep_check.py. The t7-compiler is a real compiler, so the injected
    build is rejected at build time if the script is bad.

----------------------------------------------------------------------
    CREDITS

        Xep           author
        Treyarch      _zm_magicbox.gsc, _zm_perks.gsc, _zm_pack_a_punch.gsc
        Serious       t7-source, and the compiler this builds with

----------------------------------------------------------------------
    LICENSE

        MIT -- see LICENSE. Keep this header on copies.

======================================================================
*/

#include scripts\codescripts\struct;
#include scripts\shared\aat_shared;
#include scripts\shared\array_shared;
#include scripts\shared\callbacks_shared;
#include scripts\shared\flag_shared;
#include scripts\shared\laststand_shared;
#include scripts\shared\system_shared;
#include scripts\shared\util_shared;
#include scripts\zm\_zm_equipment;
#include scripts\zm\_zm_magicbox;
#include scripts\zm\_zm_pack_a_punch_util;
#include scripts\zm\_zm_perks;
#include scripts\zm\_zm_score;
#include scripts\zm\_zm_unitrigger;
#include scripts\zm\_zm_utility;
#include scripts\zm\_zm_weapons;

#namespace zshare;


/* ==================================================================
    ENTRY POINT

    Black Ops III registers a script with the system manager and hangs
    its work off the shared callbacks, rather than exposing an init()
    the loader happens to call. The typo in the autoexec's name is the
    game's own.
   ================================================================== */

autoexec __init__sytem__()
{
    system::register( "zshare", ::__init__, undefined, undefined );
}

__init__()
{
    /*
        The gate belongs here as well as in init(). Both copies register
        their own callbacks -- under different system names, so neither
        displaces the other -- and the losing copy's on_spawned would
        otherwise still fire and could win the self.zs_thinking race.
        Nothing would misbehave, since both are the same code, but the
        level would be set up by one copy and the player watchers by the
        other, which is not the test zs_only_script and zs_only_mod exist
        to run.
    */
    if ( !zs_origin_allowed() )
        return;

    callback::on_start_gametype( ::init );

    /*
        The player callbacks are the other half of what installs ZShare,
        and they are registered before init() has read anything, so they
        get the switch read straight -- the way zs_origin_allowed() reads
        its two. One nobody has set comes back "", which is on.

        on_start_gametype stays registered either way: init() is what
        puts the descriptor on level.zmods, saying enabled 0, and "not
        installed" and "installed and switched off" are different answers.
    */
    if ( getdvarstring( "zs_enabled" ) == "0" )
        return;

    callback::on_connect( ::zs_on_connect );
    callback::on_spawned( ::zs_on_spawned );
}

/*
    Which copy of the script this is: "script" for the loose ones a
    client reads out of custom_scripts, "mod" for the one inside the
    Workshop build.

    With both installed each reaches init(), and the first one there
    wins. zs_only_script and zs_only_mod pick the winner instead, which
    is worth having only while testing one against the other.

    Written by mk_t7_variants.py when it generates the Workshop copy,
    the same way build.py writes the version stamp. Never edit by hand.
*/
zs_origin()
{
    // ZS_ORIGIN_BEGIN
    return "script";
    // ZS_ORIGIN_END
}

/*
    zs_origin_wanted() reads level.zs, which zs_load_config() fills.
    This runs before the gametype starts, so it reads the dvars straight
    instead -- one nobody has set comes back "", which carries on, and
    that is the default.
*/
zs_origin_allowed()
{
    origin = zs_origin();

    if ( getdvarstring( "zs_only_script" ) == "1" && origin != "script" )
        return 0;

    if ( getdvarstring( "zs_only_mod" ) == "1" && origin != "mod" )
        return 0;

    return 1;
}

/*
    Whether this copy is the one that was asked for. Neither setting on
    -- which is the default -- means whichever loads first, as before.
*/
zs_origin_wanted()
{
    origin = zs_origin();

    if ( level.zs.only_script && origin != "script" )
        return 0;

    if ( level.zs.only_mod && origin != "mod" )
        return 0;

    return 1;
}

init()
{
    if ( zs_true( level.zs_loaded ) )
        return;

    /*
        Config first, and the gate after: zs_only_script and zs_only_mod
        are read from it, and a copy that is not the one being asked for
        has to leave level.zs_loaded alone so the other one can still
        take it.
    */
    zs_load_config();

    if ( !zs_origin_wanted() )
        return;

    level.zs_loaded = 1;

    /*
        Switched off. The descriptor still goes up, because "not
        installed" and "installed and switched off" are different answers
        to a mod asking what ZShare is doing in this match.
    */
    if ( !level.zs.enabled )
    {
        zs_api_register( 0 );
        return;
    }

    level.zs_triggers = [];
    level.zs_machine_triggers = [];

    zs_box_paid_clear();

    level thread zs_trigger_updater();
    level thread zs_box_hook();
    level thread zs_late_hooks();
    level thread zs_machine_updater();
    level thread zs_config_watcher();
    level thread zs_config_printer();
    level thread zs_build_watermark();

    // Last, so the first thing that reads it finds a mod already up.
    zs_api_register( 1 );

}

zs_on_connect()
{
    self thread zs_player_think();
    self thread zs_chat_listener();
    self thread zs_perk_watch();
    self thread zs_pap_taken_watch();
}

zs_on_spawned()
{
    // zs_player_think() waits on "spawned_player" itself; this is only
    // here so a player who connected before the script was up still gets
    // a watcher.
    if ( !zs_true( self.zs_thinking ) )
        self thread zs_player_think();
}

/*
    is_true() is not reachable on this engine -- it appears in the dump
    as a parameter name and never as a function a script can call -- so
    it is carried here, as the T4 and T8 ports carry theirs.
*/
zs_true( v )
{
    return isdefined( v ) && v;
}


/* ==================================================================
    CONFIG

    Every value below is also a dvar of the same name, created with its
    default on load so the console can reach it. Re-read every five
    seconds and on every press, so a change applies without a restart.
   ================================================================== */

zs_load_config()
{
    if ( !isdefined( level.zs ) )
        level.zs = spawnstruct();

    // --- general ---------------------------------------------------

    /*
        ZShare itself. On by default. Off, the script still loads, still
        says so on level.zmods -- with enabled 0 -- and does nothing else:
        no prompts, no hooks over the stock scripts, no chat words and no
        threads. The match runs as it would with the file gone.

        Read once, as the match loads. Taking prompts off players and
        handing replaced stock functions back is not something a switch
        can do safely in the middle of a game, so this one lands on the
        next match -- which is what a bundle's MODS page says about it.
    */
    level.zs.enabled = zs_cfg_int( "zs_enabled", 1 );

    // --- origin ----------------------------------------------------

    /*
        Which copy of ZShare runs when both are installed: the loose
        script a client reads out of custom_scripts, or the one inside
        the Workshop build. Both off is whichever gets there first,
        which is the normal case.

        For testing one against the other. Setting both leaves nothing
        running at all. Read once, when the script loads: init() runs a
        single time per game, so changing either mid-match cannot move
        which copy is already running. End the game and start a new one.
    */
    level.zs.only_script      = zs_cfg_int( "zs_only_script", 0 );
    level.zs.only_mod         = zs_cfg_int( "zs_only_mod", 0 );

    // --- debug -----------------------------------------------------

    // Print what the script decides and why, to the console and the host.
    level.zs.debug            = zs_cfg_int( "zs_debug", 0 );

    // --- trading ---------------------------------------------------

    // Trade weapons with a teammate: use on them to offer, use back to accept.
    level.zs.trade            = zs_cfg_int( "zs_trade", 1 );

    // How long an offer stays open before it lapses on its own.
    level.zs.trade_offer_time = zs_cfg_float( "zs_trade_offer_time", 10 );

    // Whether a Pack-a-Punched weapon can be traded.
    level.zs.trade_upgraded   = zs_cfg_int( "zs_trade_upgraded", 1 );

    /*
        How close you have to be for the prompt to appear, in units. An
        offer lapses on its own once the two of you are more than twice
        this apart.
    */
    level.zs.range            = zs_cfg_int( "zs_range", 64 );

    // --- points ----------------------------------------------------

    // Crouch, look at a teammate and press use to give them points.
    level.zs.points           = zs_cfg_int( "zs_points", 1 );
    level.zs.points_amount    = zs_cfg_int( "zs_points_amount", 1000 );

    // Seconds between gifts from one player.
    level.zs.points_cooldown  = zs_cfg_float( "zs_points_cooldown", 1 );

    // --- thanks ----------------------------------------------------

    /*
        Thank somebody who paid for you, gave up a box hit or handed you
        points: for a while the crouched prompt on them offers a small
        thank instead of the full gift, and !thank does the same from
        anywhere. !tip sends any amount to anybody, favour or not. The
        points come out of the thanker either way, so nothing is minted.
    */
    level.zs.thank            = zs_cfg_int( "zs_thank", 1 );
    level.zs.thank_amount     = zs_cfg_int( "zs_thank_amount", 100 );

    // How long a good turn stays thankable, in seconds.
    level.zs.thank_time       = zs_cfg_float( "zs_thank_time", 30 );

    // --- sharing ---------------------------------------------------

    // Share a box hit: crouch and press use at the box while the weapon
    // you paid for is up, and anybody can take it.
    level.zs.box_share        = zs_cfg_int( "zs_box_share", 1 );

    // The same at the Pack-a-Punch, for the upgraded weapon waiting there.
    level.zs.pap_share        = zs_cfg_int( "zs_pap_share", 1 );

    // --- paying ----------------------------------------------------

    /*
        Pay for a teammate. Crouch and press use at a perk machine, or at
        the box or the Pack-a-Punch while nobody is using it, and the next
        teammate to use that machine pays nothing. One payment waits at a
        machine at a time, and a crouched press from whoever paid takes it
        back.
    */
    level.zs.perk_pay         = zs_cfg_int( "zs_perk_pay", 1 );
    level.zs.box_pay          = zs_cfg_int( "zs_box_pay", 1 );
    level.zs.pap_pay          = zs_cfg_int( "zs_pap_pay", 1 );

    // --- perks -----------------------------------------------------

    /*
        How many perks one player can hold. 0 is the game's own limit,
        four. Any other number replaces it, and -1 is no limit at all.
        A map that gives a player extra slots of its own keeps them on
        top of this.
    */
    level.zs.perk_limit       = zs_cfg_int( "zs_perk_limit", 0 );

    // --- presentation ----------------------------------------------

    // Tell players what the prompts do, once, shortly after they spawn.
    level.zs.show_hint        = zs_cfg_int( "zs_show_hint", 1 );

    // The one-line messages. Off leaves the prompts and the sounds.
    level.zs.messages         = zs_cfg_int( "zs_messages", 1 );

    // --- sounds ----------------------------------------------------

    /*
        Stock aliases, so the script stays one drop-in file. Set any to
        none for silence.
    */
    level.zs.offer_sound      = zs_cfg_str( "zs_offer_sound", "zmb_perks_packa_ready" );
    level.zs.trade_sound      = zs_cfg_str( "zs_trade_sound", "zmb_perks_packa_ready" );
    level.zs.share_sound      = zs_cfg_str( "zs_share_sound", "zmb_perks_packa_ready" );
    level.zs.points_sound     = zs_cfg_str( "zs_points_sound", "zmb_cha_ching" );
    level.zs.deny_sound       = zs_cfg_str( "zs_deny_sound", "zmb_no_cha_ching" );

    // Height of the prompt volume, in units. Not a setting.
    level.zs.height = 72;
}

/*
    set_dvar_if_unset() has no equivalent a zombies script can reach
    here, so the same thing is done by hand: create the dvar with its
    default the first time, because the console can only assign to one
    that already exists.

    An empty dvar reads as one that was never set, so "" typed into the
    console would be overwritten on the next read. "none" is how a string
    setting is emptied instead.
*/
zs_cfg_str( dvar, def )
{
    if ( getdvarstring( dvar ) == "" )
        setdvar( dvar, def );

    value = zs_cfg_echo( dvar, getdvarstring( dvar ), def );

    if ( value == "none" )
        return "";

    return value;
}

zs_cfg_int( dvar, def )
{
    return int( zs_cfg_str( dvar, "" + def ) );
}

zs_cfg_float( dvar, def )
{
    return float( zs_cfg_str( dvar, "" + def ) );
}


/* ==================================================================
    PLAYERS
   ================================================================== */

zs_player_think()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    if ( zs_true( self.zs_thinking ) )
        return;

    self.zs_thinking = 1;

    for ( ;; )
    {
        self waittill( "spawned_player" );

        // A prompt is linked to the player it belongs to, and a respawn
        // puts that player back into the world.
        zs_relink_prompts( self );

        if ( level.zs.show_hint && !zs_true( self.zs_hinted ) )
        {
            self.zs_hinted = 1;
            self thread zs_hint();
        }
    }
}

zs_hint()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    wait 12;

    if ( !isdefined( self ) )
        return;

    // zs_show_hint is these two lines' own switch, so zs_messages does
    // not silence them.
    self zs_tell( "MSG_INTRO_TRADE" );

    wait 4;

    if ( !isdefined( self ) )
        return;

    self zs_tell( "MSG_INTRO_PAY" );
}

zs_player_ok( player )
{
    if ( !isdefined( player ) || !isplayer( player ) || !isalive( player ) )
        return 0;

    if ( !zm_utility::is_player_valid( player ) )
        return 0;

    if ( player laststand::player_is_in_laststand() )
        return 0;

    return 1;
}

/*
    Everything above, and not standing over a downed teammate: a crouch
    there is a revive, and the revive wins.
*/
zs_payer_ok( player )
{
    if ( !zs_player_ok( player ) )
        return 0;

    if ( zs_over_downed( player ) )
        return 0;

    return 1;
}

/*
    Whether this player is standing in a downed teammate's revive
    trigger -- .revivetrigger belongs to the player who is down, so
    reading it on the presser only ever asked whether they were down
    themselves, which zs_player_ok() has already refused.

    Worked out here rather than through zm_utility::in_revive_trigger(),
    because zs_machine_prompt_hold() writes that function's own cache to
    take the machine's prompt away, and asking it would read ZShare's
    answer back.
*/
zs_over_downed( player )
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        other = players[i];

        if ( !isdefined( other ) || other == player )
            continue;

        if ( !isdefined( other.revivetrigger ) )
            continue;

        if ( player istouching( other.revivetrigger ) )
            return 1;
    }

    return 0;
}

zs_pair_ok( a, b )
{
    if ( !isdefined( a ) || !isdefined( b ) || a == b )
        return 0;

    if ( !zs_player_ok( a ) || !zs_player_ok( b ) )
        return 0;

    return zs_game_ready();
}

zs_crouched( player )
{
    if ( !isdefined( player ) )
        return 0;

    stance = player getstance();

    return stance == "crouch" || stance == "prone";
}

// Nobody to pay for in solo.
zs_pay_team_check()
{
    return getplayers().size > 1;
}


/* ==================================================================
    PROMPTS ON PLAYERS

    One use trigger per ordered pair of players, linked to the target
    the way the revive prompt is linked to a downed player, visible only
    to the viewer and requiring look-at. The words depend on who is
    reading them, which is why there is one per pair rather than one per
    player.

    Every string on a prompt is one of a fixed handful. Hint strings are
    configstrings -- a finite pool that does not recycle -- so a weapon
    or player name never goes into one. Names go in the chat line.

    What a prompt wants to say is a key and its number in one string,
    "HINT_GIVE_POINTS=1000", so it can be compared with what the trigger
    already shows and only sent when it changes.
   ================================================================== */

zs_prompt_make( target, viewer )
{
    t = spawn( "trigger_radius_use", target.origin + ( 0, 0, 36 ), 0, level.zs.range, level.zs.height );
    t setcursorhint( "HINT_NOICON" );
    t usetriggerrequirelookat();
    t triggerignoreteam();
    t sethintstring( "" );

    t setinvisibletoall();

    // Once only: stock notes that enabling it twice is an error.
    t setmovingplatformenabled( 1 );
    t enablelinkto();
    t linkto( target );

    t.zs_target = target;
    t.zs_viewer = viewer;
    t.zs_radius = level.zs.range;
    t.zs_hint = "";
    t.zs_shown = 0;

    t thread zs_prompt_think();

    level.zs_triggers[level.zs_triggers.size] = t;

    return t;
}

zs_prompt_find( target, viewer )
{
    for ( i = 0; i < level.zs_triggers.size; i++ )
    {
        t = level.zs_triggers[i];

        if ( !isdefined( t ) || !isdefined( t.zs_target ) || !isdefined( t.zs_viewer ) )
            continue;

        if ( t.zs_target == target && t.zs_viewer == viewer )
            return t;
    }

    return undefined;
}

/*
    Every ordered pair of players has a prompt. Run on a tick rather than
    on connect, so a late joiner, a rebuilt prompt and a changed range
    all heal the same way.
*/
zs_prompts_ensure()
{
    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        for ( j = 0; j < players.size; j++ )
        {
            if ( i == j )
                continue;

            if ( !isdefined( players[i] ) || !isdefined( players[j] ) )
                continue;

            if ( !isdefined( zs_prompt_find( players[i], players[j] ) ) )
                zs_prompt_make( players[i], players[j] );
        }
    }
}

zs_relink_prompts( target )
{
    for ( i = 0; i < level.zs_triggers.size; i++ )
    {
        t = level.zs_triggers[i];

        if ( !isdefined( t ) || !isdefined( t.zs_target ) || t.zs_target != target )
            continue;

        t unlink();
        t.origin = target.origin + ( 0, 0, 36 );
        t linkto( target );
    }
}

zs_prompt_free( t )
{
    if ( !isdefined( t ) )
        return;

    t notify( "zs_kill" );
    t unlink();
    t delete();
}

/*
    The one loop behind every prompt on a player: who can see it, and
    what it says. Ten times a second, and the hint string is only written
    when it changes.
*/
zs_trigger_updater()
{
    level endon( "end_game" );

    tick = 0;

    for ( ;; )
    {
        wait 0.1;

        tick++;

        if ( tick % 10 == 0 )
            zs_prompts_ensure();

        keep = [];

        for ( i = 0; i < level.zs_triggers.size; i++ )
        {
            t = level.zs_triggers[i];

            if ( !isdefined( t ) )
                continue;

            if ( !isdefined( t.zs_target ) || !isdefined( t.zs_viewer ) || t.zs_radius != level.zs.range )
            {
                zs_prompt_free( t );
                continue;
            }

            t zs_prompt_update();
            keep[keep.size] = t;
        }

        level.zs_triggers = keep;
    }
}

zs_prompt_update()
{
    target = self.zs_target;
    viewer = self.zs_viewer;

    want = zs_prompt_text( target, viewer );

    if ( want == "" )
    {
        if ( self.zs_shown )
        {
            self setinvisibletoplayer( viewer, 1 );
            self.zs_shown = 0;
        }

        return;
    }

    if ( want != self.zs_hint )
    {
        zs_hint_set( self, want );
        self.zs_hint = want;
    }

    if ( !self.zs_shown )
    {
        self setvisibletoplayer( viewer );
        self setinvisibletoplayer( viewer, 0 );
        self.zs_shown = 1;
    }
}

zs_prompt_text( target, viewer )
{
    if ( !zs_pair_ok( target, viewer ) )
        return "";

    if ( level.zs.points && zs_crouched( viewer ) )
    {
        /*
            A thank takes the crouched press while one is owed, because
            crouch already means "give them something" and a thank is a
            smaller one with a reason.
        */
        if ( viewer zs_owes_thanks( target ) )
            return "HINT_THANK=" + level.zs.thank_amount;

        return "HINT_GIVE_POINTS=" + level.zs.points_amount;
    }

    if ( !level.zs.trade )
        return "";

    if ( zs_offer_is( target, viewer ) )
        return "HINT_TRADE_ACCEPT";

    if ( zs_offer_is( viewer, target ) )
        return "HINT_TRADE_CANCEL";

    return "HINT_TRADE";
}

zs_prompt_think()
{
    self endon( "zs_kill" );
    self endon( "death" );
    level endon( "end_game" );

    for ( ;; )
    {
        self waittill( "trigger", user );

        if ( !isdefined( user ) || !isdefined( self.zs_target ) || !isdefined( self.zs_viewer ) )
            continue;

        // Hidden from everybody else, so this is belt and braces.
        if ( user != self.zs_viewer )
            continue;

        zs_load_config();
        user zs_use_on( self.zs_target );

        // One press, one action.
        wait 0.3;
    }
}

zs_use_on( target )
{
    if ( !zs_pair_ok( self, target ) )
        return;

    if ( level.zs.points && zs_crouched( self ) )
    {
        if ( self zs_owes_thanks( target ) )
            self zs_thank( target );
        else
            self zs_points_give( target );

        return;
    }

    if ( !level.zs.trade )
        return;

    if ( zs_offer_is( target, self ) )
    {
        zs_trade_do( target, self );
        return;
    }

    if ( zs_offer_is( self, target ) )
    {
        self zs_offer_cancel( "withdrawn" );
        return;
    }

    self zs_offer_make( target );
}


/* ==================================================================
    TRADING

    What you offer is the weapon in your hands; what you get back is
    whatever they hold when they accept. The weapon travels through the
    game's own weapondata pair -- what the weapon locker uses -- with the
    Alternate Ammo Type carried across by hand, the way Zetsubou's clone
    plant carries it.
   ================================================================== */

zs_offer_is( from, to )
{
    if ( !isdefined( from ) || !isdefined( to ) )
        return 0;

    return isdefined( from.zs_offer_to ) && from.zs_offer_to == to;
}

zs_offer_make( to )
{
    weapon = self getcurrentweapon();
    why = self zs_untradeable( weapon );

    if ( why != "" )
    {
        self zs_deny( why );
        return;
    }

    if ( isdefined( self.zs_offer_to ) )
        self zs_offer_cancel( "replaced" );

    self.zs_offer_to = to;
    self.zs_offer_weapon = weapon;
    // Counted up, not read as a yes/no: zs_true() makes every serial
    // after the first the same number, and a watcher that cannot tell
    // its offer from the one before never lapses or cancels it.
    if ( !isdefined( self.zs_offer_serial ) )
        self.zs_offer_serial = 0;

    self.zs_offer_serial++;

    self zs_say( "MSG_OFFER_SENT", to, int( level.zs.trade_offer_time ) );
    to zs_say( "MSG_OFFER_RECEIVED", self );
    to zs_sound( level.zs.offer_sound );

    self thread zs_offer_watcher( self.zs_offer_serial );
}

zs_offer_clear()
{
    self.zs_offer_to = undefined;
    self.zs_offer_weapon = undefined;
}

zs_offer_cancel( why )
{
    to = self.zs_offer_to;

    self zs_offer_clear();

    if ( why == "withdrawn" )
    {
        self zs_say( "MSG_TRADE_CANCELLED" );

        if ( isdefined( to ) )
            to zs_say( "MSG_TRADE_CANCELLED_BY", self );
    }
    else if ( why == "expired" )
    {
        self zs_say( "MSG_OFFER_LAPSED" );

        if ( isdefined( to ) )
            to zs_say( "MSG_OFFER_LAPSED_BY", self );
    }
    else if ( why == "switched" || why == "lost" )
    {
        self zs_say( "MSG_TRADE_PUT_AWAY" );

        if ( isdefined( to ) )
            to zs_say( "MSG_TRADE_PUT_AWAY_BY", self );
    }
    else if ( why == "distance" )
    {
        self zs_say( "MSG_TRADE_TOO_FAR" );

        if ( isdefined( to ) )
            to zs_say( "MSG_TRADE_TOO_FAR_BY", self );
    }
    else if ( why == "replaced" )
    {
        if ( isdefined( to ) )
            to zs_say( "MSG_TRADE_WITHDRAWN_BY", self );
    }

    zs_debug( "offer cancelled: " + why );
}

zs_offer_watcher( serial )
{
    self endon( "disconnect" );
    level endon( "end_game" );

    started = gettime();

    for ( ;; )
    {
        wait 0.25;

        if ( !isdefined( self ) || !isdefined( self.zs_offer_to ) )
            return;

        if ( !isdefined( self.zs_offer_serial ) || self.zs_offer_serial != serial )
            return;

        to = self.zs_offer_to;

        if ( !isdefined( to ) )
            return;

        if ( gettime() - started > level.zs.trade_offer_time * 1000 )
        {
            self zs_offer_cancel( "expired" );
            return;
        }

        if ( !zs_player_ok( self ) || !zs_player_ok( to ) )
        {
            self zs_offer_cancel( "lost" );
            return;
        }

        if ( self getcurrentweapon() != self.zs_offer_weapon )
        {
            self zs_offer_cancel( "switched" );
            return;
        }

        if ( distance( self.origin, to.origin ) > level.zs.range * 2 )
        {
            self zs_offer_cancel( "distance" );
            return;
        }
    }
}

zs_trade_do( a, b )
{
    if ( !zs_pair_ok( a, b ) )
        return;

    a_weapon = a getcurrentweapon();
    b_weapon = b getcurrentweapon();

    if ( a_weapon != a.zs_offer_weapon )
    {
        a zs_offer_cancel( "switched" );
        return;
    }

    why = a zs_untradeable( a_weapon );

    if ( why != "" )
    {
        a zs_deny( why );
        a zs_offer_cancel( "lost" );
        return;
    }

    why = b zs_untradeable( b_weapon );

    if ( why != "" )
    {
        b zs_deny( why );
        return;
    }

    // The same gun both ways would trade nothing, and Black Ops II refuses
    // it before anything else. zs_carries_same_family() lets the outgoing
    // gun through on purpose, so it never catches this one.
    if ( a_weapon == b_weapon )
    {
        b zs_deny( "MSG_ALREADY_HAVE" );
        return;
    }

    if ( b zs_carries_same_family( a_weapon, b_weapon ) )
    {
        b zs_deny( "MSG_ALREADY_HAVE" );
        return;
    }

    if ( a zs_carries_same_family( b_weapon, a_weapon ) )
    {
        b zs_deny( "MSG_ALREADY_CARRIES", a );
        return;
    }

    a zs_offer_clear();

    a_record = zs_weapon_record( a, a_weapon );
    b_record = zs_weapon_record( b, b_weapon );

    a zs_weapon_take( a_weapon );
    b zs_weapon_take( b_weapon );

    b zs_weapon_give( a_record );
    a zs_weapon_give( b_record );

    a zs_say( "MSG_TRADED_WITH", b );
    b zs_say( "MSG_TRADED_WITH", a );

    a zs_sound( level.zs.trade_sound );
    b zs_sound( level.zs.trade_sound );
}

/*
    Everything that has to travel with the gun: the weapondata the locker
    reads, and the Alternate Ammo Type, which lives on the player rather
    than on the weapon.
*/
zs_weapon_record( player, weapon )
{
    r = spawnstruct();
    r.weapon = weapon;
    r.data = zm_weapons::get_player_weapondata( player, weapon );

    /*
        On the player who owns the gun, and the *name* of what it has:
        getaatonweapon() hands back the level struct
        (aat_shared.gsc:695), and acquire() wants the name it is keyed
        by (:731). Called unqualified this read self, which through
        zs_trade_do() is always the accepter, so the offerer's Alternate
        Ammo Type was lost and the accepter's struct was written into the
        receiver's table, where every later read of it indexes level.aat
        with a struct.
    */
    theirs = player aat::getaatonweapon( weapon );

    if ( isdefined( theirs ) )
        r.aat = theirs.name;

    return r;
}

zs_weapon_take( weapon )
{
    if ( isdefined( self aat::getaatonweapon( weapon ) ) )
        self aat::remove( weapon );

    self zm_weapons::weapon_take( weapon );
}

zs_weapon_give( r )
{
    self zm_weapons::weapondata_give( r.data );

    if ( isdefined( r.aat ) )
        self aat::acquire( r.weapon, r.aat );

    self switchtoweapon( r.weapon );
}

/*
    Why a weapon cannot change hands, as the key of the line that says
    so, or "" when it can. Primaries only:
    grenades, the knife, mines, equipment, shields and a hero weapon all
    have their own slots and their own rules, and the box will not take
    your money for one either.
*/
zs_untradeable( weapon )
{
    if ( !isdefined( weapon ) || weapon == level.weaponnone )
        return "MSG_HOLD_WEAPON";

    if ( zm_utility::is_offhand_weapon( weapon ) || zm_utility::is_melee_weapon( weapon ) )
        return "MSG_NOT_TRADEABLE";

    if ( zm_utility::is_placeable_mine( weapon ) || zm_equipment::is_equipment( weapon ) )
        return "MSG_NOT_TRADEABLE";

    if ( zm_utility::is_hero_weapon( weapon ) )
        return "MSG_NOT_TRADEABLE";

    if ( !zm_weapons::is_weapon_included( weapon ) )
        return "MSG_NOT_TRADEABLE";

    if ( !level.zs.trade_upgraded && zm_weapons::is_weapon_upgraded( weapon ) )
        return "MSG_NO_TRADE_UPGRADED";

    return "";
}

/*
    Whether the receiver already carries the incoming weapon or its other
    half -- the plain gun or the Pack-a-Punched one. The weapon they are
    giving away does not count, since it leaves in the same trade.
*/
zs_carries_same_family( incoming, outgoing )
{
    if ( incoming == outgoing )
        return 0;

    same = self zm_weapons::get_player_weapon_with_same_base( incoming );

    if ( !isdefined( same ) || same == level.weaponnone )
        return 0;

    return same != outgoing;
}


/* ==================================================================
    POINTS

    Straight onto .score and .pers["score"], not through the score
    helpers: one of those counts the points as earned and the other
    fires the spent notify. A gift is neither. A spawn reloads score from
    pers, so both are written.
   ================================================================== */

/* ==================================================================
    THANKS

    Somebody paid for your perk, gave up the box hit they paid for, or
    handed you points. ZShare already knows -- it says so at the time --
    so it remembers who, and for a while the crouched prompt on them
    offers a small thank instead of the full gift.

    The points come out of the thanker, so nothing is minted and there
    is nothing to farm: a thank is a gift with a reason attached, and
    what it buys is that the prompt tells you a favour is owed and takes
    one press to answer.

    One thank per favour, so the prompt stays meaningful. To give more,
    tip.
   ================================================================== */

/*
    Remember that `from` did `self` a good turn. The most recent one is
    the one that is owed; an older unthanked favour is simply replaced,
    because thanking is about the moment rather than a ledger.
*/
zs_favour_note( from )
{
    if ( !isdefined( from ) || !isdefined( self ) || from == self )
        return;

    if ( !isplayer( from ) || !isplayer( self ) )
        return;

    self.zs_favour_from = from;
    self.zs_favour_at = gettime();
}

zs_owes_thanks( to )
{
    if ( !level.zs.thank || !isdefined( to ) )
        return 0;

    if ( !isdefined( self.zs_favour_from ) || self.zs_favour_from != to )
        return 0;

    if ( level.zs.thank_amount <= 0 || self.score < level.zs.thank_amount )
        return 0;

    return gettime() - self.zs_favour_at < int( level.zs.thank_time * 1000 );
}

// Whoever is owed a thank right now, for the chat word.
zs_favour_who()
{
    if ( !isdefined( self.zs_favour_from ) )
        return undefined;

    if ( !self zs_owes_thanks( self.zs_favour_from ) )
        return undefined;

    return self.zs_favour_from;
}

zs_thank( to )
{
    if ( !zs_pair_ok( self, to ) )
        return;

    amount = level.zs.thank_amount;

    if ( self.score < amount )
    {
        self zs_deny( "MSG_THANK_NEED", amount );
        return;
    }

    self.zs_favour_from = undefined;

    zs_score_set( self, self.score - amount );
    zs_score_set( to, to.score + amount );

    self zs_say( "MSG_THANKED", to, amount );
    to zs_say( "MSG_THANKED_YOU", self, amount );

    self zs_sound( level.zs.points_sound );
    to zs_sound( level.zs.points_sound );

    zs_debug( "thanks: " + self.name + " -> " + to.name );
}

/*
    Any amount, to anybody, with no favour needed. The name is optional
    and the amount is always the last word, so a name with spaces in it
    still parses.
*/
zs_tip( rest )
{
    if ( !level.zs.thank )
        return;

    parts = strtok( rest, " " );

    if ( parts.size == 0 )
    {
        self zs_say( "MSG_TIP_USAGE" );
        return;
    }

    amount = int( parts[parts.size - 1] );

    if ( amount <= 0 )
    {
        self zs_say( "MSG_TIP_USAGE" );
        return;
    }

    if ( parts.size > 1 )
    {
        name = "";

        for ( i = 0; i < parts.size - 1; i++ )
            if ( name == "" )
                name = parts[i];
            else
                name = name + " " + parts[i];

        to = zs_player_named( name, self );

        if ( !isdefined( to ) )
            return;
    }
    else
    {
        to = self zs_favour_who();

        if ( !isdefined( to ) )
        {
            self zs_say( "MSG_TIP_NOBODY", amount );
            return;
        }
    }

    if ( !zs_pair_ok( self, to ) )
        return;

    if ( self.score < amount )
    {
        self zs_deny( "MSG_TIP_ONLY_HAVE", self.score );
        return;
    }

    zs_score_set( self, self.score - amount );
    zs_score_set( to, to.score + amount );

    self zs_say( "MSG_TIPPED", to, amount );
    to zs_say( "MSG_TIPPED_YOU", self, amount );

    self zs_sound( level.zs.points_sound );
    to zs_sound( level.zs.points_sound );

    zs_debug( "tip: " + self.name + " -> " + to.name + " " + amount );
}

/*
    The player a typed name means. Case and color codes are ignored and
    a prefix is enough, but a name that matches nobody -- or more than
    one -- is refused rather than guessed at: somebody typing a name
    means that player, and sending their points to another is worse than
    doing nothing.
*/
zs_player_named( name, asker )
{
    want = tolower( name );
    found = undefined;
    several = 0;

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        p = players[i];

        if ( !isdefined( p ) || p == asker )
            continue;

        theirs = tolower( zs_plain_name( p.name ) );

        if ( theirs == want )
            return p;

        if ( getsubstr( theirs, 0, want.size ) != want )
            continue;

        if ( isdefined( found ) )
            several = 1;
        else
            found = p;
    }

    if ( several )
    {
        asker zs_say( "MSG_NAME_SEVERAL", name );
        return undefined;
    }

    if ( !isdefined( found ) )
        asker zs_say( "MSG_NAME_NOBODY", name );

    return found;
}

// A name with the color codes taken out, so typing it plainly matches.
zs_plain_name( name )
{
    out = "";

    for ( i = 0; i < name.size; i++ )
    {
        if ( name[i] == "^" && i + 1 < name.size )
        {
            i++;
            continue;
        }

        out = out + name[i];
    }

    return out;
}

zs_points_give( to )
{
    amount = level.zs.points_amount;

    if ( amount <= 0 || !zs_pair_ok( self, to ) )
        return;

    if ( zs_true( self.zs_points_next ) && gettime() < self.zs_points_next )
        return;

    if ( self.score < amount )
    {
        self zs_deny( "MSG_POINTS_NEED", amount );
        return;
    }

    self.zs_points_next = gettime() + int( level.zs.points_cooldown * 1000 );

    zs_score_set( self, self.score - amount );
    zs_score_set( to, to.score + amount );

    to zs_favour_note( self );

    self zs_say( "MSG_GAVE", to, amount );
    to zs_say( "MSG_GAVE_YOU", self, amount );

    self zs_sound( level.zs.points_sound );
    to zs_sound( level.zs.points_sound );
}

zs_score_set( player, value )
{
    if ( value < 0 )
        value = 0;

    player.score = value;
    player.pers["score"] = value;
}


/* ==================================================================
    INPUT -- CHAT

    One word, for when the machine is behind you. Black Ops III raises
    its chat notify on the player who typed rather than on the level, so
    every player carries a listener of their own -- the one shape
    difference from the Plutonium ports, where one listener on the level
    hears everybody.
   ================================================================== */

zs_chat_listener()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    /*
        One listener a player, however many copies of ZShare loaded. A
        ZBundle fastfile and a loose copy both register on_connect, and
        two listeners would answer every chat word twice.
    */
    if ( zs_true( self.zs_chat_listening ) )
        return;

    self.zs_chat_listening = 1;

    for ( ;; )
    {
        self waittill( "say", message );

        if ( !isdefined( message ) || !isstring( message ) )
            continue;

        msg = tolower( message );

        if ( zs_word_is( msg, "!thank" ) || zs_word_is( msg, "!t" ) )
        {
            self thread zs_chat_thank();
            continue;
        }

        rest = zs_word_after( msg, "!tip" );

        if ( isdefined( rest ) )
        {
            self thread zs_chat_tip( rest );
            continue;
        }

        if ( zs_word_is( msg, "!share" ) )
            self thread zs_chat_share();
    }
}

/*
    A client hands the message over with its own leading character on
    some routes and without on others, so every comparison is made
    twice: on the message, and on the message less its first character.
*/
/*
    What follows a word, or undefined when the message is not that word.
    The same two comparisons zs_word_is makes, for the same reason.
*/
zs_word_after( msg, token )
{
    /*
        getsubstr()'s third argument is where to stop, not how many
        characters to take -- stock reads a map name with
        getsubstr( mapname, 3, mapname.size ) and chops three characters
        with getsubstr( weapon, 0, weapon.size - 3 ). Given token.size
        there, the skipped-character form compared one character too few
        and never matched, so !tip was dead on any client that puts a
        character in front of the message.

        And the word has to end where the token does: "!tipsy" is not
        "!tip", and reading its "sy" as an amount is how a chat line
        nobody meant for ZShare reached the tip code.
    */
    if ( zs_word_starts( msg, 0, token ) )
        return zs_trim( getsubstr( msg, token.size ) );

    if ( msg.size > 1 && zs_word_starts( msg, 1, token ) )
        return zs_trim( getsubstr( msg, 1 + token.size ) );

    return undefined;
}

zs_word_starts( msg, at, token )
{
    end = at + token.size;

    if ( msg.size < end )
        return 0;

    if ( getsubstr( msg, at, end ) != token )
        return 0;

    // The whole message, or a space after it.
    return msg.size == end || getsubstr( msg, end, end + 1 ) == " ";
}

zs_trim( s )
{
    while ( s.size > 0 && s[0] == " " )
        s = getsubstr( s, 1 );

    while ( s.size > 0 && s[s.size - 1] == " " )
        s = getsubstr( s, 0, s.size - 1 );

    return s;
}

// self is the player who typed, because this engine raises say on them.
zs_chat_thank()
{
    zs_load_config();

    if ( !level.zs.thank )
        return;

    to = self zs_favour_who();

    if ( !isdefined( to ) )
    {
        self zs_say( "MSG_THANK_NOBODY" );
        return;
    }

    self zs_thank( to );
}

zs_chat_tip( rest )
{
    zs_load_config();
    self zs_tip( rest );
}

zs_word_is( msg, token )
{
    if ( msg == token )
        return 1;

    if ( msg.size > 1 && getsubstr( msg, 1 ) == token )
        return 1;

    return 0;
}

/*
    Share whatever of yours is waiting -- a box weapon, or an upgraded
    one at the Pack-a-Punch. It asks what the crouched press asks, less
    the crouch.
*/
zs_chat_share()
{
    zs_load_config();

    if ( !zs_player_ok( self ) )
        return;

    if ( level.zs.box_share && isdefined( level.chests ) )
    {
        for ( i = 0; i < level.chests.size; i++ )
        {
            chest = level.chests[i];

            if ( !zs_box_shareable( chest, self ) )
                continue;

            chest zs_box_share( self );
            return;
        }
    }

    if ( level.zs.pap_share && isdefined( level.zs_pap_machines ) )
    {
        for ( i = 0; i < level.zs_pap_machines.size; i++ )
        {
            trig = level.zs_pap_machines[i];

            if ( !zs_pap_shareable( trig, self ) )
                continue;

            trig zs_pap_share( self );
            return;
        }
    }

    self zs_say( "MSG_NOTHING_WAITING" );
}


/* ==================================================================
    THE MAGIC BOX

    The box already knows how to do both of these things. After the
    hacker re-spins one, box_rerespun makes the prompt visible to
    everybody and hands the weapon to whoever presses; after the hacker
    summons one, auto_open and no_charge open it for the next player
    without taking their points. Sharing sets the first, a paid spin sets
    the other two, and the box does the rest of the work itself.

    Nothing stock is replaced. The stub's own two function pointers are
    taken over -- the prompt, so the words match the press, and the
    relay, so ZShare sees a press before the chest does -- and the stock
    prompt function is kept and called.
   ================================================================== */

// Every chest has its stub once treasure_chest_init() has run.
zs_box_ready()
{
    if ( !isdefined( level.chests ) )
        return 0;

    for ( i = 0; i < level.chests.size; i++ )
    {
        if ( !isdefined( level.chests[i] ) )
            continue;

        if ( !isdefined( level.chests[i].unitrigger_stub ) )
            return 0;
    }

    return 1;
}

zs_box_hook()
{
    level endon( "end_game" );

    while ( !zs_box_ready() )
        wait 0.5;

    for ( i = 0; i < level.chests.size; i++ )
    {
        chest = level.chests[i];

        if ( !isdefined( chest ) )
            continue;

        stub = chest.unitrigger_stub;
        stub.zs_prompt_stock = stub.prompt_and_visibility_func;
        stub.prompt_and_visibility_func = ::zs_box_prompt;
        stub.onspawnfunc = ::zs_box_trigger_spawned;

        /*
            A trigger built before the hook went in is still running the
            stock relay. Ending that thread the way the unitrigger system
            ends its own, and starting ours in its place, means nobody has
            to walk away and back for the box to hear them.
        */
        if ( isdefined( stub.playertrigger ) )
        {
            keys = getarraykeys( stub.playertrigger );

            for ( k = 0; k < keys.size; k++ )
            {
                t = stub.playertrigger[keys[k]];

                if ( !isdefined( t ) )
                    continue;

                t notify( "kill_trigger" );
                t thread zs_box_relay();
            }
        }

        chest thread zs_box_watcher();
    }

    zs_debug( "box: hooked " + level.chests.size + " chest(s)" );
}

/*
    self is the stub, and the trigger has just been spawned from it. The
    stock registration wrote its own relay into trigger_func a moment
    ago; the think thread is started from this field right after this
    returns, so writing ours here is exact.
*/
zs_box_trigger_spawned( trigger )
{
    self.trigger_func = ::zs_box_relay;
}

/*
    The stock relay, magicbox_unitrigger_think(), with ZShare's presses
    taken out before it forwards the rest. self is the per-player
    trigger.
*/
zs_box_relay()
{
    self endon( "kill_trigger" );

    for ( ;; )
    {
        self waittill( "trigger", player );

        chest = self.stub.trigger_target;

        if ( isdefined( chest ) && isplayer( player ) && zs_box_press( chest, player ) )
            continue;

        self.stub.trigger_target notify( "trigger", player );
    }
}

/*
    A press ZShare answers itself, or 0 to pass it to the box. The words
    on the prompt come from the same function, so what a player reads is
    always what the press does.
*/
zs_box_press( chest, player )
{
    zs_load_config();

    mode = zs_box_mode( chest, player );

    if ( mode == "share" )
    {
        chest zs_box_share( player );
        return 1;
    }

    if ( mode == "pay" )
    {
        chest zs_box_pay( player );
        return 1;
    }

    if ( mode == "take_back" )
    {
        zs_box_take_back( player );
        return 1;
    }

    return 0;
}

/*
    What a press at this box means for this player right now:

        take_shared  somebody shared the weapon that is up
        share        the weapon up is yours, and you are crouched
        take_back    you paid for the next spin, and you are crouched
        free         a paid spin is waiting at this box
        pay          the box is idle, and you are crouched
        stock        anything else, which the box handles itself
*/
zs_box_mode( chest, player )
{
    if ( !isdefined( chest ) || !isdefined( player ) )
        return "stock";

    crouched = zs_crouched( player );

    if ( zs_true( chest.grab_weapon_hint ) )
    {
        if ( zs_true( chest.zs_shared ) )
            return "take_shared";

        if ( level.zs.box_share && crouched && zs_box_shareable( chest, player ) )
            return "share";

        return "stock";
    }

    if ( zs_true( chest._box_open ) )
        return "stock";

    if ( zs_true( level.zs_box_paid ) )
    {
        if ( crouched && isdefined( level.zs_box_paid_by ) && level.zs_box_paid_by == player )
            return "take_back";

        if ( zs_true( chest.zs_free ) )
            return "free";

        return "stock";
    }

    if ( crouched && zs_box_pay_allowed( chest, player ) )
        return "pay";

    return "stock";
}

zs_box_shareable( chest, player )
{
    if ( !isdefined( chest ) || !isdefined( player ) )
        return 0;

    if ( !zs_true( chest.grab_weapon_hint ) || zs_true( chest.zs_shared ) )
        return 0;

    return isdefined( chest.chest_user ) && chest.chest_user == player;
}

zs_box_share( player )
{
    self.box_rerespun = 1;
    self.zs_shared = 1;
    self.zs_shared_by = player;

    // Everybody's prompt is rebuilt at once rather than as each of them
    // wanders in, which is what the stock code does after unlocking.
    self.unitrigger_stub zm_unitrigger::run_visibility_function_for_all_triggers();

    zs_say_all( "MSG_BOX_SHARED", player );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "box shared by " + player.name );
}

// The box that is actually in play, as opposed to a location it has left.
zs_box_is_active( chest )
{
    if ( !isdefined( level.chests ) || !isdefined( level.chest_index ) )
        return 0;

    if ( !isdefined( level.chests[level.chest_index] ) )
        return 0;

    return level.chests[level.chest_index] == chest;
}

zs_fire_sale_on()
{
    if ( !isdefined( level.zombie_vars ) )
        return 0;

    return zs_true( level.zombie_vars["zombie_powerup_fire_sale_on"] );
}

zs_box_pay_allowed( chest, player )
{
    if ( !level.zs.box_pay || !zs_pay_team_check() )
        return 0;

    if ( zs_fire_sale_on() || level flag::get( "moving_chest_now" ) )
        return 0;

    if ( zs_true( chest.hidden ) || !zs_box_is_active( chest ) )
        return 0;

    // The hacker's summon borrows the same free-spin fields.
    if ( isdefined( chest.forced_user ) )
        return 0;

    if ( isdefined( chest.auto_open ) && !zs_true( chest.zs_free ) )
        return 0;

    if ( !isdefined( chest.zombie_cost ) )
        return 0;

    return zs_payer_ok( player );
}

/*
    Charged through the game's own purchase, so the points leave the way
    they would at any other buy. What was taken is what comes back.
*/
zs_box_pay( player )
{
    cost = self.zombie_cost;

    if ( !player zm_score::can_player_purchase( cost ) )
    {
        player zs_deny( "MSG_NEED_POINTS", cost );
        return;
    }

    before = player.score;
    player zm_score::minus_to_player_score( cost );

    /*
        Nothing was actually taken: Shopping Free makes a purchase cost
        nothing and is spent doing it, so the gobblegum would have gone
        on somebody else's turn and left a payment worth nothing to take
        back.
    */
    if ( before - player.score <= 0 )
    {
        player zs_deny( "MSG_PAY_NOTHING_TAKEN" );
        return;
    }

    level.zs_box_paid = 1;
    level.zs_box_paid_by = player;
    level.zs_box_paid_amount = before - player.score;

    self zs_box_free_apply();
    self.unitrigger_stub zm_unitrigger::run_visibility_function_for_all_triggers();

    player zs_say( "MSG_BOX_PAID" );
    zs_say_others( player, "MSG_BOX_PAID_BY", player );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "box paid by " + player.name + ": " + level.zs_box_paid_amount );
}

zs_box_take_back( player )
{
    amount = level.zs_box_paid_amount;

    zs_box_paid_reset();

    zs_refund( player, amount );

    player zs_say( "MSG_BOX_TAKEN_BACK" );
    zs_say_others( player, "MSG_BOX_TAKEN_BACK_BY", player );
    player zs_sound( level.zs.points_sound );

    zs_debug( "box payment taken back" );
}

/*
    Points that are being given back rather than earned, so they go onto
    the score directly and count towards nothing.
*/
zs_refund( player, amount )
{
    if ( !isdefined( player ) || !isdefined( amount ) || amount <= 0 )
        return;

    zs_score_set( player, player.score + amount );
}

zs_box_paid_reset()
{
    zs_box_paid_clear();

    if ( !isdefined( level.chests ) )
        return;

    for ( i = 0; i < level.chests.size; i++ )
    {
        chest = level.chests[i];

        if ( !isdefined( chest ) )
            continue;

        chest zs_box_free_remove();

        if ( isdefined( chest.unitrigger_stub ) )
            chest.unitrigger_stub zm_unitrigger::run_visibility_function_for_all_triggers();
    }
}

/*
    Only ever sets fields nobody else is using, and only ever clears the
    ones it set. The hacker's summon leaves its own there while it runs.
*/
zs_box_free_apply()
{
    if ( zs_true( self.zs_free ) )
        return;

    if ( isdefined( self.auto_open ) || isdefined( self.no_charge ) || isdefined( self.forced_user ) )
        return;

    self.auto_open = 1;
    self.no_charge = 1;
    self.zs_free = 1;
}

zs_box_free_remove()
{
    if ( !zs_true( self.zs_free ) )
        return;

    self.auto_open = undefined;
    self.no_charge = undefined;
    self.zs_free = 0;
}

zs_box_can_be_free( chest )
{
    if ( zs_fire_sale_on() || level flag::get( "moving_chest_now" ) )
        return 0;

    if ( zs_true( chest.hidden ) || zs_true( chest._box_open ) )
        return 0;

    return zs_box_is_active( chest );
}

/*
    Runs for the life of the game, one per box location:

        - clears a share once the weapon is gone
        - notices a paid spin being used, which is the box opening while
          the free fields are on
        - puts the free fields on the live location, and takes them off
          everywhere else and for the length of a fire sale
        - re-runs everybody's prompt when anything they read changes.
          The stock system only re-runs a prompt when a player walks up,
          so a player crouching where they stand would otherwise keep
          reading the old words.
*/
zs_box_watcher()
{
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.1;

        if ( !zs_true( self.grab_weapon_hint ) && zs_true( self.zs_shared ) )
        {
            self.zs_shared = 0;
            self.zs_shared_by = undefined;
        }

        if ( zs_true( self.zs_free ) && zs_true( self._box_open ) )
        {
            self zs_box_free_remove();
            self thread zs_box_paid_spun();
        }
        else if ( zs_true( level.zs_box_paid ) && zs_box_can_be_free( self ) )
            self zs_box_free_apply();
        else
            self zs_box_free_remove();

        sig = zs_box_signature( self );

        if ( !isdefined( self.zs_sig ) || self.zs_sig != sig )
        {
            self.zs_sig = sig;

            if ( isdefined( self.unitrigger_stub ) )
                self.unitrigger_stub zm_unitrigger::run_visibility_function_for_all_triggers();
        }
    }
}

/*
    Everything a player near this box could be reading off it, as one
    string: the box's own state, and who nearby is crouched.
*/
zs_box_signature( chest )
{
    sig = "" + zs_true( level.zs_box_paid ) + zs_true( chest.zs_free ) + zs_true( chest.zs_shared ) + zs_true( chest.grab_weapon_hint ) + zs_fire_sale_on();

    if ( !isdefined( chest.unitrigger_stub ) || !isdefined( chest.unitrigger_stub.playertrigger ) )
        return sig;

    if ( chest.unitrigger_stub.playertrigger.size == 0 )
        return sig;

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( distancesquared( players[i].origin, chest.origin ) > 40000 )
            continue;

        if ( zs_crouched( players[i] ) )
            sig = sig + "c" + players[i] getentitynumber();
    }

    return sig;
}

/*
    A paid spin has just been used. self is the box.
*/
zs_box_paid_spun()
{
    level endon( "end_game" );

    payer = level.zs_box_paid_by;
    amount = level.zs_box_paid_amount;
    user = self.chest_user;

    zs_box_paid_clear();

    if ( isdefined( user ) && isdefined( payer ) && user != payer )
    {
        user zs_say( "MSG_BOX_PAID_FOR_YOU", payer );
        user zs_favour_note( payer );
        payer zs_say( "MSG_BOX_USED_YOURS", user );
    }

    zs_debug( "paid box spin used" );

    if ( !isdefined( self.zbarrier ) )
        return;

    /*
        The stock refund for a teddy bear gives back what the spin
        charged, and this spin charged nothing -- so the refund is ours to
        give, to whoever paid. The move flag is set before the notify goes
        out, so it is already true by the time this wakes.
    */
    evt = self.zbarrier util::waittill_any_return( "randomization_done", "box_hacked_respin" );

    if ( evt != "randomization_done" )
        return;

    if ( level flag::get( "moving_chest_now" ) && isdefined( payer ) && isdefined( amount ) )
    {
        zs_refund( payer, amount );
        payer zs_say( "MSG_BOX_MOVED_REFUND", amount );
        payer zs_sound( level.zs.points_sound );
    }
}

/*
    self is the per-player trigger; player is who it is for. The stock
    function decides visibility and writes the stock hint; this rewrites
    the words when ZShare has something else to say.
*/
zs_box_prompt( player )
{
    can_use = self [[ self.stub.zs_prompt_stock ]]( player );

    if ( !can_use )
        return can_use;

    chest = self.stub.trigger_target;
    mode = zs_box_mode( chest, player );

    if ( mode == "take_shared" )
        zs_hint_set( self, "HINT_TAKE_SHARED" );
    else if ( mode == "share" )
        zs_hint_set( self, "HINT_SHARE" );
    else if ( mode == "pay" )
        zs_hint_set( self, "HINT_BOX_PAY=" + chest.zombie_cost );
    else if ( mode == "take_back" )
        zs_hint_set( self, "HINT_TAKE_BACK" );
    else if ( mode == "free" && isdefined( self.hint_string ) )
        self sethintstring( self.hint_string, 0 );

    return can_use;
}


/* ==================================================================
    THE PACK-A-PUNCH

    Every function in the Pack-a-Punch is private, so none of them can be
    called, replaced or re-threaded. Everything below therefore goes
    through what the machine reads rather than what it runs:

        grabbable_by_anyone   hands the waiting gun to whoever presses,
                              which is the share
        cost / aat_cost       the price the machine charges and the
                              number its own prompt prints, which is the
                              payment
        pap_offering_gun      the flag saying a gun is waiting
        pack_player           who the machine is busy with

    The stock hint is rewritten twenty times a second by a private
    monitor, so ZShare cannot hold its own words on that trigger. Its
    prompt is a second trigger beside the machine, and it is shown only
    for the crouched actions -- taking a shared gun and using a paid one
    are the machine's own prompt, saying the machine's own words.
   ================================================================== */

zs_pap_hook()
{
    level.zs_pap_machines = [];

    if ( !isdefined( level.pack_a_punch ) )
        return;

    trigs = zm_pap_util::get_triggers();

    if ( !isdefined( trigs ) )
        return;

    for ( i = 0; i < trigs.size; i++ )
    {
        trig = trigs[i];

        if ( !isdefined( trig ) )
            continue;

        trig zs_pap_paid_clear();
        trig.zs_shared = 0;

        level.zs_pap_machines[level.zs_pap_machines.size] = trig;

        trig.zs_trigger = trig zs_machine_trigger( "pap" );
        trig thread zs_pap_price_maintain();
    }

    zs_debug( "pap: found " + level.zs_pap_machines.size + " machine(s)" );
}

/*
    self is the Pack-a-Punch trigger. What a crouched press means here,
    and the words that go with it, both come from this.
*/
zs_pap_mode( player )
{
    if ( !isdefined( player ) || !zs_crouched( player ) )
        return "none";

    if ( level.zs.pap_share && zs_pap_shareable( self, player ) )
        return "share";

    if ( zs_true( self.zs_paid ) )
    {
        if ( isdefined( self.zs_paid_by ) && self.zs_paid_by == player )
            return "take_back";

        return "none";
    }

    if ( zs_pap_pay_ok( player ) )
        return "pay";

    return "none";
}

zs_pap_press( player )
{
    mode = self zs_pap_mode( player );

    if ( mode == "share" )
        self zs_pap_share( player );
    else if ( mode == "pay" )
        self zs_pap_pay( player );
    else if ( mode == "take_back" )
        self zs_pap_take_back( player );
}

zs_pap_hint( player )
{
    mode = self zs_pap_mode( player );

    if ( mode == "share" )
        return "HINT_SHARE";

    if ( mode == "pay" )
        return "HINT_PAP_PAY=" + self.zs_cost;

    if ( mode == "take_back" )
        return "HINT_TAKE_BACK";

    return "";
}

/*
    A gun is waiting at the machine and it is this player's. The flag is
    the machine's own, set the moment the upgraded weapon is put up and
    cleared the moment the window closes.
*/
zs_pap_shareable( trig, player )
{
    if ( !isdefined( trig ) || !isdefined( player ) )
        return 0;

    if ( !trig flag::get( "pap_offering_gun" ) || zs_true( trig.zs_shared ) )
        return 0;

    return isdefined( trig.pack_player ) && trig.pack_player == player;
}

/*
    Two fields do the whole thing, and both are ones the machine reads
    rather than writes while a gun is waiting:

        grabbable_by_anyone   makes the take loop treat whoever pressed
                              as the player it was holding the gun for
        pack_player           is who the machine's own visibility loop
                              shows the trigger to, and nobody else --
                              so clearing it is what puts the prompt in
                              front of the room

    Clearing it is safe because the take loop holds the packer in a local
    of its own, and because the machine clears the same field itself the
    moment the window closes. Nothing is shown or hidden by hand: the
    machine's loop does that on its next pass, a tenth of a second later,
    which is why there is nothing here to fight with.
*/
zs_pap_share( player )
{
    self.zs_shared = 1;
    self.zs_shared_by = player;

    level.pack_a_punch.grabbable_by_anyone = 1;
    self.pack_player = undefined;

    self thread zs_pap_window_end();

    zs_say_all( "MSG_PAP_SHARED", player );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "pap shared by " + player.name );
}

/*
    The three ways the machine's offer window can close, which are the
    three notifies it raises on the trigger itself.
*/
zs_pap_window_end()
{
    self endon( "death" );
    level endon( "end_game" );

    self util::waittill_any( "pap_taken", "pap_timeout", "pap_player_disconnected" );

    level.pack_a_punch.grabbable_by_anyone = 0;

    // The same press raises this on the trigger and on the taker, and the
    // taker's watcher reads the share to know whose it was. A frame is
    // left for it before the share is cleared.
    wait 0.05;

    self.zs_shared = 0;
    self.zs_shared_by = undefined;
}

/*
    The machine raises this on the player it hands the gun to, which is
    the only place the taker's name can be read: the trigger's own copy
    has been cleared by then, by the share or by the machine.
*/
zs_pap_taken_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    if ( zs_true( self.zs_pap_watching ) )
        return;

    self.zs_pap_watching = 1;

    for ( ;; )
    {
        self waittill( "pap_taken" );

        if ( !isdefined( level.zs_pap_machines ) )
            continue;

        for ( i = 0; i < level.zs_pap_machines.size; i++ )
        {
            trig = level.zs_pap_machines[i];

            if ( !isdefined( trig ) || !zs_true( trig.zs_shared ) )
                continue;

            if ( !isdefined( trig.zs_shared_by ) || trig.zs_shared_by == self )
                continue;

            trig.zs_shared_by zs_say( "MSG_PAP_TOOK_SHARED", self );
            break;
        }
    }
}

zs_pap_pay_ok( player )
{
    if ( !level.zs.pap_pay || !zs_pay_team_check() )
        return 0;

    // Busy with somebody, or holding a gun for them.
    if ( isdefined( self.pack_player ) || self flag::get( "pap_offering_gun" ) )
        return 0;

    if ( !isdefined( self.zs_cost ) || self.zs_cost <= 0 )
        return 0;

    return zs_payer_ok( player );
}

/*
    Paying sets the machine's own price to nothing, so the machine
    charges nothing and its own prompt prints the nothing it charges.
    zs_cost is what the price was, kept so it can be put back.
*/
zs_pap_pay( player )
{
    cost = self.zs_cost;

    if ( !player zm_score::can_player_purchase( cost ) )
    {
        player zs_deny( "MSG_NEED_POINTS", cost );
        return;
    }

    before = player.score;
    player zm_score::minus_to_player_score( cost );

    /*
        Nothing was actually taken: Shopping Free makes a purchase cost
        nothing and is spent doing it, so the gobblegum would have gone
        on somebody else's turn and left a payment worth nothing to take
        back.
    */
    if ( before - player.score <= 0 )
    {
        player zs_deny( "MSG_PAY_NOTHING_TAKEN" );
        return;
    }

    self.zs_paid = 1;
    self.zs_paid_by = player;
    self.zs_paid_amount = before - player.score;

    self.cost = 0;
    self.aat_cost = 0;

    self thread zs_pap_paid_watch();

    player zs_say( "MSG_PAP_PAID" );
    zs_say_others( player, "MSG_PAP_PAID_BY", player );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "pap paid by " + player.name + ": " + self.zs_paid_amount );
}

zs_pap_take_back( player )
{
    amount = self.zs_paid_amount;

    self notify( "zs_pap_paid_end" );
    self zs_pap_paid_clear();
    self zs_pap_price_restore();

    zs_refund( player, amount );

    player zs_say( "MSG_PAP_TAKEN_BACK" );
    zs_say_others( player, "MSG_PAP_TAKEN_BACK_BY", player );
    player zs_sound( level.zs.points_sound );

    zs_debug( "pap payment taken back" );
}

/*
    A paid pack has been used the moment the machine takes somebody on,
    which is pack_player being set to them.
*/
zs_pap_paid_watch()
{
    self endon( "death" );
    self endon( "zs_pap_paid_end" );
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.1;

        if ( !zs_true( self.zs_paid ) )
            return;

        if ( !isdefined( self.pack_player ) )
            continue;

        self zs_pap_paid_used( self.pack_player );
        return;
    }
}

zs_pap_paid_used( taker )
{
    payer = self.zs_paid_by;

    self zs_pap_paid_clear();
    self zs_pap_price_restore();

    if ( isdefined( taker ) && isdefined( payer ) && taker != payer )
    {
        taker zs_say( "MSG_PAP_PAID_FOR_YOU", payer );
        taker zs_favour_note( payer );
        payer zs_say( "MSG_PAP_USED_YOURS", taker );
    }

    zs_debug( "paid pack used" );
}

zs_pap_paid_clear()
{
    self.zs_paid = 0;
    self.zs_paid_by = undefined;
    self.zs_paid_amount = 0;
}

/*
    The machine sets its own price when it starts and again at both ends
    of a bonfire sale, and nowhere else. zs_cost follows the real price
    while nobody has paid, so a sale that starts or ends mid-payment is
    still put back to the right number.
*/
zs_pap_price_maintain()
{
    self endon( "death" );
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.5;

        if ( !isdefined( self.cost ) )
            continue;

        if ( !zs_true( self.zs_paid ) )
        {
            self.zs_cost = self.cost;
            self.zs_aat_cost = self.aat_cost;
            continue;
        }

        // A sale moved the price while a payment was waiting.
        if ( self.cost != 0 )
        {
            self.zs_cost = self.cost;
            self.zs_aat_cost = self.aat_cost;
            self.cost = 0;
            self.aat_cost = 0;
        }
    }
}

zs_pap_price_restore()
{
    if ( isdefined( self.zs_cost ) )
        self.cost = self.zs_cost;

    if ( isdefined( self.zs_aat_cost ) )
        self.aat_cost = self.zs_aat_cost;
}


/* ==================================================================
    MACHINE PROMPTS

    A machine's own trigger carries one hint for everybody, so a payer
    and a taker standing at the same machine would read the same words.
    Each machine gets a second trigger of ZShare's own, in the same
    place, shown to one player at a time.
   ================================================================== */

zs_machine_trigger( kind )
{
    t = spawn( "trigger_radius_use", self.origin, 0, 72, 96 );
    t setcursorhint( "HINT_NOICON" );
    t usetriggerrequirelookat();
    t triggerignoreteam();
    t sethintstring( "" );
    t setinvisibletoall();

    t.zs_machine = self;
    t.zs_kind = kind;
    t.zs_hint = "";
    t.zs_viewer = undefined;

    t thread zs_machine_trigger_think();

    if ( !isdefined( level.zs_machine_triggers ) )
        level.zs_machine_triggers = [];

    level.zs_machine_triggers[level.zs_machine_triggers.size] = t;

    return t;
}

/*
    Shown to one player, with one line of words, or to nobody.
*/
zs_trigger_show( t, player, want )
{
    if ( !isdefined( t ) )
        return;

    if ( !isdefined( player ) || want == "" )
    {
        if ( isdefined( t.zs_viewer ) )
        {
            t setinvisibletoplayer( t.zs_viewer, 1 );
            t.zs_viewer = undefined;
        }

        return;
    }

    if ( want != t.zs_hint )
    {
        zs_hint_set( t, want );
        t.zs_hint = want;
    }

    if ( !isdefined( t.zs_viewer ) || t.zs_viewer != player )
    {
        if ( isdefined( t.zs_viewer ) )
            t setinvisibletoplayer( t.zs_viewer, 1 );

        t setvisibletoplayer( player );
        t setinvisibletoplayer( player, 0 );
        t.zs_viewer = player;
    }
}

zs_machine_trigger_think()
{
    self endon( "death" );
    level endon( "end_game" );

    for ( ;; )
    {
        self waittill( "trigger", player );

        if ( !isdefined( player ) || !isdefined( self.zs_machine ) )
            continue;

        if ( !isdefined( self.zs_viewer ) || player != self.zs_viewer )
            continue;

        zs_load_config();

        machine = self.zs_machine;

        switch ( self.zs_kind )
        {
            case "pap":
                machine zs_pap_press( player );
                break;

            case "perk":
                machine zs_perk_press( player );
                break;
        }

        wait 0.3;
    }
}


/* ==================================================================
    PAYMENTS

    One payment waits at a machine at a time. The box's is level-wide,
    because there is one box; a perk machine and the Pack-a-Punch each
    keep their own on the trigger.
   ================================================================== */

zs_box_paid_clear()
{
    level.zs_box_paid = 0;
    level.zs_box_paid_by = undefined;
    level.zs_box_paid_amount = 0;
}


/* ==================================================================
    PERK MACHINES

    A perk machine charges what its trigger's cost field says and prints
    the same number on its own prompt, so a paid drink is the price set
    to nothing and the machine's own prompt saying so. The drink, the
    animation and the perk are the machine's own work start to finish.

    The crouched pay prompt is a second trigger beside the machine, as
    at the Pack-a-Punch. Taking a paid drink is the machine's own prompt.
   ================================================================== */

zs_perk_hook()
{
    level.zs_perk_machines = [];

    trigs = getentarray( "zombie_vending", "targetname" );

    for ( i = 0; i < trigs.size; i++ )
    {
        trig = trigs[i];

        if ( !isdefined( trig ) || !isdefined( trig.script_noteworthy ) )
            continue;

        trig zs_perk_paid_clear();

        level.zs_perk_machines[level.zs_perk_machines.size] = trig;

        trig.zs_trigger = trig zs_machine_trigger( "perk" );
        trig thread zs_perk_price_maintain();
    }

    zs_debug( "perks: found " + level.zs_perk_machines.size + " machine(s)" );
}

/*
    self is the perk machine's use trigger. script_noteworthy is the perk
    id everywhere in the perk system.
*/
zs_perk_mode( player )
{
    if ( !isdefined( player ) || !zs_crouched( player ) )
        return "none";

    if ( zs_true( self.zs_paid ) )
    {
        if ( isdefined( self.zs_paid_by ) && self.zs_paid_by == player )
            return "take_back";

        return "none";
    }

    if ( self zs_perk_pay_ok( player ) )
        return "pay";

    return "none";
}

zs_perk_press( player )
{
    mode = self zs_perk_mode( player );

    if ( mode == "pay" )
        self zs_perk_pay( player );
    else if ( mode == "take_back" )
        self zs_perk_take_back( player );
}

zs_perk_hint( player )
{
    mode = self zs_perk_mode( player );

    if ( mode == "pay" )
        return "HINT_PERK_PAY=" + self.zs_cost;

    if ( mode == "take_back" )
        return "HINT_TAKE_BACK";

    return "";
}

zs_perk_pay_ok( player )
{
    if ( !level.zs.perk_pay || !zs_pay_team_check() )
        return 0;

    /*
        An unpowered machine sells nothing, so there is nothing to pay for.
        Only a machine known to be off, though: power_on is written by
        perk_machine_think() alone, and a map that powers its machines
        through a power override thread never writes it at all -- read as
        "off", no machine on that map would ever offer to be paid for.
    */
    if ( isdefined( self.power_on ) && !self.power_on )
        return 0;

    if ( !isdefined( self.zs_cost ) || self.zs_cost <= 0 )
        return 0;

    /*
        Crouching over a downed teammate revives them, and that prompt
        comes first.
    */
    return zs_payer_ok( player );
}

zs_perk_pay( player )
{
    cost = self.zs_cost;

    if ( !player zm_score::can_player_purchase( cost ) )
    {
        player zs_deny( "MSG_NEED_POINTS", cost );
        return;
    }

    before = player.score;
    player zm_score::minus_to_player_score( cost );

    /*
        Nothing was actually taken: Shopping Free makes a purchase cost
        nothing and is spent doing it, so the gobblegum would have gone
        on somebody else's turn and left a payment worth nothing to take
        back.
    */
    if ( before - player.score <= 0 )
    {
        player zs_deny( "MSG_PAY_NOTHING_TAKEN" );
        return;
    }

    self.zs_paid = 1;
    self.zs_paid_by = player;
    self.zs_paid_amount = before - player.score;

    self.cost = 0;
    self zs_perk_hint_price( 0 );

    player zs_say( "MSG_PERK_PAID", self.script_noteworthy );
    zs_say_others( player, "MSG_PERK_PAID_BY", player, self.script_noteworthy );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "perk paid by " + player.name + ": " + self.zs_paid_amount );
}

zs_perk_take_back( player )
{
    amount = self.zs_paid_amount;

    self zs_perk_paid_clear();
    self zs_perk_price_restore();

    zs_refund( player, amount );

    player zs_say( "MSG_PERK_TAKEN_BACK", self.script_noteworthy );
    zs_say_others( player, "MSG_PERK_TAKEN_BACK_BY", player, self.script_noteworthy );
    player zs_sound( level.zs.points_sound );

    zs_debug( "perk payment taken back" );
}

/*
    The machine raises this on the player it just sold to, right after it
    takes their points -- so a drink that was refused for any of the
    machine's own reasons never gets here, and the payment stays where it
    is. Started per player, because that is where the notify lands.
*/
zs_perk_watch()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    if ( zs_true( self.zs_perk_watching ) )
        return;

    self.zs_perk_watching = 1;

    for ( ;; )
    {
        self waittill( "perk_purchased", perk );

        if ( !isdefined( perk ) || !isdefined( level.zs_perk_machines ) )
            continue;

        for ( i = 0; i < level.zs_perk_machines.size; i++ )
        {
            trig = level.zs_perk_machines[i];

            if ( !isdefined( trig ) || !zs_true( trig.zs_paid ) )
                continue;

            if ( trig.script_noteworthy != perk )
                continue;

            /*
                And the drinker has to be at that machine. Stock raises
                perk_purchased for perks that never touched one -- Der
                Wunderfizz (_zm_perk_random.gsc), Zetsubou's fruit and the
                spider quest's free Widow's Wine -- and a payment waiting
                at the machine across the map was spent on those.
            */
            if ( distancesquared( self.origin, trig.origin ) > 10000 )
                continue;

            trig zs_perk_paid_used( self );
            break;
        }
    }
}

zs_perk_paid_used( taker )
{
    payer = self.zs_paid_by;

    self zs_perk_paid_clear();
    self zs_perk_price_restore();

    if ( isdefined( taker ) && isdefined( payer ) && taker != payer )
    {
        taker zs_say( "MSG_PERK_PAID_FOR_YOU", payer );
        taker zs_favour_note( payer );
        payer zs_say( "MSG_PERK_USED_YOURS", taker, self.script_noteworthy );
    }

    zs_debug( "paid perk used" );
}

zs_perk_paid_clear()
{
    self.zs_paid = 0;
    self.zs_paid_by = undefined;
    self.zs_paid_amount = 0;
}

/*
    The machine writes its own price once, as it starts, and the perk
    registry is where the words come from. zs_cost shadows the real price
    so a payment can be put back to the number that was actually taken.
*/
zs_perk_price_maintain()
{
    self endon( "death" );
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.5;

        if ( !isdefined( self.cost ) )
            continue;

        if ( !zs_true( self.zs_paid ) )
        {
            self.zs_cost = self.cost;
            continue;
        }

        if ( self.cost != 0 )
        {
            self.zs_cost = self.cost;
            self.cost = 0;
            self zs_perk_hint_price( 0 );
        }
    }
}

zs_perk_price_restore()
{
    if ( !isdefined( self.zs_cost ) )
        return;

    self.cost = self.zs_cost;
    self zs_perk_hint_price( self.zs_cost );
}

/*
    The machine's own words with a different number in them, which is
    what a stock prompt at no charge already looks like.
*/
zs_perk_hint_price( cost )
{
    perk = self.script_noteworthy;

    if ( !isdefined( level._custom_perks ) || !isdefined( level._custom_perks[perk] ) )
        return;

    if ( !isdefined( level._custom_perks[perk].hint_string ) )
        return;

    self sethintstring( level._custom_perks[perk].hint_string, cost );
}


/* ==================================================================
    THE PERK LIMIT

    get_player_perk_purchase_limit is the hook the game asks for the
    number, with the player as self and nothing else. A map that sets its
    own is called first and the slots it adds are kept, so a map that
    hands out a fifth perk still does with zs_perk_limit set.
   ================================================================== */

zs_perk_limit_apply()
{
    if ( level.zs.perk_limit == 0 )
        return;

    if ( isdefined( level.get_player_perk_purchase_limit ) )
        level.zs_perk_limit_stock = level.get_player_perk_purchase_limit;

    level.get_player_perk_purchase_limit = ::zs_perk_limit_get;

    zs_debug( "perk limit: " + level.zs.perk_limit );
}

// self is the player.
zs_perk_limit_get()
{
    want = level.zs.perk_limit;

    if ( want < 0 )
        want = 32;

    // Whatever the map would have given, above or below the stock four,
    // is still given.
    if ( isdefined( level.zs_perk_limit_stock ) )
    {
        theirs = self [[ level.zs_perk_limit_stock ]]();

        if ( isdefined( theirs ) )
            want = want + ( theirs - 4 );
    }

    if ( want < 1 )
        want = 1;

    return want;
}


/* ==================================================================
    MACHINES -- THE REST OF THE WIRING

    The box is hooked as soon as its stubs exist; the machines are found
    once the map has finished building them, and the perk limit is set
    after any map that sets its own has had its turn.
   ================================================================== */

zs_late_hooks()
{
    level endon( "end_game" );

    while ( !zs_game_ready() )
        wait 0.5;

    // The perk machines are built by perk_machine_spawn_init(), and the
    // Pack-a-Punch triggers by its own __main__. Both are done by the
    // time the first round is under way.
    wait 2;

    zs_pap_hook();
    zs_perk_hook();
    zs_perk_limit_apply();
}

/*
    One loop for every ZShare machine prompt. A machine's words depend on
    who is reading them, so each trigger picks the one crouched player
    near it who has something to read and is shown to them alone.
*/
zs_machine_updater()
{
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.05;

        if ( !isdefined( level.zs_machine_triggers ) )
            continue;

        for ( i = 0; i < level.zs_machine_triggers.size; i++ )
        {
            t = level.zs_machine_triggers[i];

            if ( !isdefined( t ) || !isdefined( t.zs_machine ) )
                continue;

            zs_machine_update( t );
        }
    }
}

zs_machine_update( t )
{
    machine = t.zs_machine;
    best = undefined;
    want = "";

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        player = players[i];

        if ( !zs_player_ok( player ) || !zs_crouched( player ) )
            continue;

        if ( distancesquared( player.origin, t.origin ) > 6400 )
            continue;

        if ( t.zs_kind == "pap" )
            txt = machine zs_pap_hint( player );
        else
            txt = machine zs_perk_hint( player );

        if ( txt == "" )
            continue;

        best = player;
        want = txt;
        break;
    }

    zs_trigger_show( t, best, want );

    if ( isdefined( best ) )
        best zs_machine_prompt_hold();
}

/*
    Take the machine's own prompt away from the one player ZShare's prompt
    is showing to, so the engine has only ours to draw.

    Both prompts sit on the machine, and the engine draws whichever it
    likes -- in play it drew the perk machine's, every time. The machine's
    visibility loop, which cannot be stopped or replaced, hides its prompt
    from a player standing in a revive trigger: check_player_has_perk()
    through vending_trigger_can_player_use(), and the Pack-a-Punch's
    through zm_magicbox::can_buy_weapon(). in_revive_trigger() keeps its
    answer on the player for 100ms, in rt_time and in_rt_cached, and this
    runs every 50ms, so for as long as ZShare's prompt is up the answer is
    yes. The moment it is not, the cache runs out and is worked out afresh
    within a tenth of a second.

    Everything that reads in_revive_trigger() refuses a purchase or a use
    while it is true, which is what a crouched press here means anyway: it
    is ZShare's, not the machine's.
*/
zs_machine_prompt_hold()
{
    self.rt_time = gettime();
    self.in_rt_cached = 1;
}


/* ==================================================================
    PRESENTATION
   ================================================================== */

/*
    Every one of these takes a key from zshare-text.json and up to two
    arguments for it, and ends in zs_tell() in the TEXT block, which knows
    what the words are in the build it is part of.
*/
zs_say( key, a, b )
{
    if ( !level.zs.messages || !isdefined( self ) )
        return;

    self zs_tell( key, a, b );
}

zs_say_all( key, a, b )
{
    if ( !level.zs.messages )
        return;

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i] zs_tell( key, a, b );
    }
}

zs_say_others( except, key, a, b )
{
    if ( !level.zs.messages )
        return;

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( isdefined( except ) && players[i] == except )
            continue;

        players[i] zs_tell( key, a, b );
    }
}

zs_sound( alias )
{
    if ( !isdefined( alias ) || alias == "" || !isdefined( self ) )
        return;

    self playlocalsound( alias );
}

zs_sound_others( except, alias )
{
    if ( !isdefined( alias ) || alias == "" )
        return;

    players = getplayers();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( isdefined( except ) && players[i] == except )
            continue;

        players[i] playlocalsound( alias );
    }
}

zs_deny( key, a, b )
{
    self zs_say( key, a, b );
    self zs_sound( level.zs.deny_sound );
}

zs_debug( txt )
{
    if ( !isdefined( level.zs ) || !zs_true( level.zs.debug ) )
        return;

    players = getplayers();

    if ( players.size > 0 && isdefined( players[0] ) )
        players[0] iprintln( "^5[zs]^7 " + txt );
}

zs_game_ready()
{
    return isdefined( level.round_number );
}


/* ==================================================================
    TEXT

    Every word a player reads, by key. Generated from zshare-text.json by
    tools/mk_t7_text.py on every build; the comment inside says how the
    two builds differ.
   ================================================================== */

// ZS_TEXT_BEGIN
/*
    Generated by tools/mk_t7_text.py from zshare-text.json. Never edit
    by hand -- change the table and build.

    Every line a player reads comes through here by key. This is the
    English one, which the loose-script builds draw. The Workshop build
    carries the same functions over localized strings instead, so each
    player there reads their own language.
*/
zs_tell( key, a, b )
{
    txt = zs_text( key, a, b );

    if ( txt != "" )
        self iprintln( txt );
}

/*
    A prompt's key and its number, which travel as one string so a caller
    can compare it with what the trigger already shows before sending it
    again: "HINT_X" or "HINT_X=950".
*/
zs_hint_key( want )
{
    parts = strtok( want, "=" );
    return parts[0];
}

zs_hint_arg( want )
{
    parts = strtok( want, "=" );

    if ( parts.size < 2 )
        return undefined;

    return int( parts[1] );
}

zs_hint_set( trigger, want )
{
    if ( want == "" )
    {
        trigger sethintstring( "" );
        return;
    }

    trigger sethintstring( zs_text( zs_hint_key( want ), zs_hint_arg( want ) ) );
}

zs_text_player( player )
{
    if ( isdefined( player ) && isdefined( player.name ) )
        return player.name;

    return "Someone";
}

zs_text_perk( perk )
{
    if ( !isdefined( perk ) )
        return "a perk";

    if ( perk == "specialty_armorvest" )
        return "Jugger-Nog";

    if ( perk == "specialty_quickrevive" )
        return "Quick Revive";

    if ( perk == "specialty_fastreload" )
        return "Speed Cola";

    if ( perk == "specialty_doubletap2" )
        return "Double Tap";

    if ( perk == "specialty_staminup" )
        return "Stamin-Up";

    if ( perk == "specialty_deadshot" )
        return "Deadshot Daiquiri";

    if ( perk == "specialty_additionalprimaryweapon" )
        return "Mule Kick";

    if ( perk == "specialty_widowswine" )
        return "Widow's Wine";

    if ( perk == "specialty_electriccherry" )
        return "Electric Cherry";

    return "a perk";
}

zs_text( key, a, b )
{
    if ( key == "" )
        return "";

    if ( key == "MSG_INTRO_TRADE" )
        return "^3[ZShare]^7 look at a teammate and press ^3[{+activate}]^7 to trade weapons, or crouch first to give them points";
    if ( key == "MSG_INTRO_PAY" )
        return "^3[ZShare]^7 crouch and press ^3[{+activate}]^7 at a machine to pay for a teammate, or at the box to share your hit";
    if ( key == "HINT_THANK" )
        return "Hold ^3[{+activate}]^7 to thank them (" + a + " points)";
    if ( key == "HINT_GIVE_POINTS" )
        return "Hold ^3[{+activate}]^7 to give " + a + " points";
    if ( key == "HINT_TRADE_ACCEPT" )
        return "Hold ^3[{+activate}]^7 to accept the trade";
    if ( key == "HINT_TRADE_CANCEL" )
        return "Hold ^3[{+activate}]^7 to cancel the trade";
    if ( key == "HINT_TRADE" )
        return "Hold ^3[{+activate}]^7 to trade weapons";
    if ( key == "MSG_OFFER_SENT" )
        return "Offered your weapon to ^3" + zs_text_player( a ) + "^7 -- they have " + b + " seconds to accept";
    if ( key == "MSG_OFFER_RECEIVED" )
        return "^3" + zs_text_player( a ) + "^7 wants to trade weapons -- look at them and press ^3use^7 to accept";
    if ( key == "MSG_TRADE_CANCELLED" )
        return "Trade cancelled";
    if ( key == "MSG_TRADE_CANCELLED_BY" )
        return "^3" + zs_text_player( a ) + "^7 cancelled the trade";
    if ( key == "MSG_OFFER_LAPSED" )
        return "Your trade offer lapsed";
    if ( key == "MSG_OFFER_LAPSED_BY" )
        return "^3" + zs_text_player( a ) + "^7's trade offer lapsed";
    if ( key == "MSG_TRADE_PUT_AWAY" )
        return "Trade cancelled -- you put the weapon away";
    if ( key == "MSG_TRADE_PUT_AWAY_BY" )
        return "^3" + zs_text_player( a ) + "^7 put the weapon away -- trade cancelled";
    if ( key == "MSG_TRADE_TOO_FAR" )
        return "Trade cancelled -- too far apart";
    if ( key == "MSG_TRADE_TOO_FAR_BY" )
        return "^3" + zs_text_player( a ) + "^7's trade offer lapsed -- too far apart";
    if ( key == "MSG_TRADE_WITHDRAWN_BY" )
        return "^3" + zs_text_player( a ) + "^7 withdrew the trade";
    if ( key == "MSG_ALREADY_HAVE" )
        return "You already have that weapon";
    if ( key == "MSG_ALREADY_CARRIES" )
        return "^3" + zs_text_player( a ) + "^7 already carries that weapon";
    if ( key == "MSG_TRADED_WITH" )
        return "Traded weapons with ^3" + zs_text_player( a );
    if ( key == "MSG_HOLD_WEAPON" )
        return "Hold the weapon you want to trade";
    if ( key == "MSG_NOT_TRADEABLE" )
        return "That isn't a weapon you can trade";
    if ( key == "MSG_NO_TRADE_UPGRADED" )
        return "Pack-a-Punched weapons can't be traded here";
    if ( key == "MSG_THANK_NEED" )
        return "You need " + a + " points to thank them";
    if ( key == "MSG_THANKED" )
        return "Thanked ^3" + zs_text_player( a ) + "^7 -- " + b + " points";
    if ( key == "MSG_THANKED_YOU" )
        return "^3" + zs_text_player( a ) + "^7 thanked you -- " + b + " points";
    if ( key == "MSG_THANK_NOBODY" )
        return "Nobody has done you a good turn just now";
    if ( key == "MSG_TIP_USAGE" )
        return "Say ^3!tip 500^7, or ^3!tip <name> 500^7";
    if ( key == "MSG_TIP_NOBODY" )
        return "Nobody owed a thank -- say ^3!tip <name> " + a + "^7 instead";
    if ( key == "MSG_TIP_ONLY_HAVE" )
        return "You only have " + a + " points";
    if ( key == "MSG_TIPPED" )
        return "Tipped ^3" + zs_text_player( a ) + "^7 " + b + " points";
    if ( key == "MSG_TIPPED_YOU" )
        return "^3" + zs_text_player( a ) + "^7 tipped you " + b + " points";
    if ( key == "MSG_NAME_SEVERAL" )
        return "More than one player starts with ^3" + a + "^7";
    if ( key == "MSG_NAME_NOBODY" )
        return "No player here called ^3" + a;
    if ( key == "MSG_POINTS_NEED" )
        return "You need " + a + " points to give";
    if ( key == "MSG_GAVE" )
        return "Gave ^3" + zs_text_player( a ) + "^7 " + b + " points";
    if ( key == "MSG_GAVE_YOU" )
        return "^3" + zs_text_player( a ) + "^7 gave you " + b + " points";
    if ( key == "MSG_NOTHING_WAITING" )
        return "Nothing of yours is waiting at the box or the Pack-a-Punch";
    if ( key == "MSG_PAY_NOTHING_TAKEN" )
        return "Your points were not taken -- nothing to pay with";
    if ( key == "MSG_NEED_POINTS" )
        return "You need " + a + " points";
    if ( key == "HINT_TAKE_BACK" )
        return "Hold ^3[{+activate}]^7 to take back your payment";
    if ( key == "HINT_SHARE" )
        return "Hold ^3[{+activate}]^7 to share this weapon";
    if ( key == "HINT_TAKE_SHARED" )
        return "Hold ^3[{+activate}]^7 to take the shared weapon";
    if ( key == "HINT_BOX_PAY" )
        return "Hold ^3[{+activate}]^7 to buy a spin for a teammate [Cost: " + a + "]";
    if ( key == "MSG_BOX_SHARED" )
        return "^3" + zs_text_player( a ) + "^7 shared their box weapon -- anyone can take it";
    if ( key == "MSG_BOX_PAID" )
        return "Paid for the next box spin -- the next teammate to use the box spins free";
    if ( key == "MSG_BOX_PAID_BY" )
        return "^3" + zs_text_player( a ) + "^7 paid for the next box spin -- use the box to spin free";
    if ( key == "MSG_BOX_TAKEN_BACK" )
        return "Took back your payment for the box";
    if ( key == "MSG_BOX_TAKEN_BACK_BY" )
        return "^3" + zs_text_player( a ) + "^7 took back their payment for the box";
    if ( key == "MSG_BOX_PAID_FOR_YOU" )
        return "^3" + zs_text_player( a ) + "^7 paid for this spin";
    if ( key == "MSG_BOX_USED_YOURS" )
        return "^3" + zs_text_player( a ) + "^7 used the spin you paid for";
    if ( key == "MSG_BOX_MOVED_REFUND" )
        return "The box moved -- your " + a + " points came back";
    if ( key == "HINT_PAP_PAY" )
        return "Hold ^3[{+activate}]^7 to buy a Pack-a-Punch for a teammate [Cost: " + a + "]";
    if ( key == "MSG_PAP_SHARED" )
        return "^3" + zs_text_player( a ) + "^7 shared their Pack-a-Punched weapon -- anyone can take it";
    if ( key == "MSG_PAP_TOOK_SHARED" )
        return "^3" + zs_text_player( a ) + "^7 took the weapon you shared";
    if ( key == "MSG_PAP_PAID" )
        return "Paid for the next Pack-a-Punch -- the next teammate to use the machine packs free";
    if ( key == "MSG_PAP_PAID_BY" )
        return "^3" + zs_text_player( a ) + "^7 paid for the next Pack-a-Punch -- use the machine to pack free";
    if ( key == "MSG_PAP_TAKEN_BACK" )
        return "Took back your payment for the Pack-a-Punch";
    if ( key == "MSG_PAP_TAKEN_BACK_BY" )
        return "^3" + zs_text_player( a ) + "^7 took back their payment for the Pack-a-Punch";
    if ( key == "MSG_PAP_PAID_FOR_YOU" )
        return "^3" + zs_text_player( a ) + "^7 paid for this Pack-a-Punch";
    if ( key == "MSG_PAP_USED_YOURS" )
        return "^3" + zs_text_player( a ) + "^7 used the Pack-a-Punch you paid for";
    if ( key == "HINT_PERK_PAY" )
        return "Hold ^3[{+activate}]^7 to buy this perk for a teammate [Cost: " + a + "]";
    if ( key == "MSG_PERK_PAID" )
        return "Paid for " + zs_text_perk( a ) + " -- the next teammate to use the machine drinks it free";
    if ( key == "MSG_PERK_PAID_BY" )
        return "^3" + zs_text_player( a ) + "^7 paid for " + zs_text_perk( b ) + " -- use the machine to drink it free";
    if ( key == "MSG_PERK_TAKEN_BACK" )
        return "Took back your payment for " + zs_text_perk( a );
    if ( key == "MSG_PERK_TAKEN_BACK_BY" )
        return "^3" + zs_text_player( a ) + "^7 took back their payment for " + zs_text_perk( b );
    if ( key == "MSG_PERK_PAID_FOR_YOU" )
        return "^3" + zs_text_player( a ) + "^7 paid for this one";
    if ( key == "MSG_PERK_USED_YOURS" )
        return "^3" + zs_text_player( a ) + "^7 used your payment for " + zs_text_perk( b );

    return key;
}
// ZS_TEXT_END


/* ==================================================================
    THE SHARED MOD API

    Xep's mods find each other on level.zmods: an array keyed by mod id,
    each key a struct saying what that mod is and handing over the few
    things another mod may ask it to do. ZShare's goes up as the script
    finishes loading, and again -- saying enabled 0 -- when zs_enabled is
    off, since "not installed" and "installed and switched off" are
    different answers.

    api_version 1 is this. The descriptor is the contract: level.zs is
    ZShare's own struct and may move.
   ================================================================== */

/*
    The version on its own -- no build time, no origin -- because that is
    what the descriptor carries for another mod to read. Written by
    tools/build.py between the markers; never edit it by hand.
*/
zs_version()
{
    // ZS_VERSION_BEGIN
    return "1.4";
    // ZS_VERSION_END
}

/*
    The descriptor. Written into whatever registry is already there --
    another mod may have made it first, and replacing the array would be
    that mod's entry gone.
*/
zs_api_register( benabled )
{
    if ( !isdefined( level.zmods ) )
        level.zmods = [];

    if ( !isdefined( level.zmods[ "zshare" ] ) )
        level.zmods[ "zshare" ] = spawnstruct();

    mod = level.zmods[ "zshare" ];

    mod.id = "zshare";
    mod.display_name = "ZShare";
    mod.version = zs_version();
    mod.api_version = 1;
    mod.settings_manifest_version = 1;
    mod.enabled = benabled;

    mod.reload_config = &zs_api_reload_config;
    mod.get_stock_perk_limit = &zs_api_stock_perk_limit;
    mod.get_effective_perk_limit = &zs_api_effective_perk_limit;
}

/*
    Read the settings again -- for a mod that has just written one of
    ZShare's dvars and wants it to count now rather than at the next
    press. 1 when there was something to read.
*/
zs_api_reload_config()
{
    if ( !zs_true( level.zs_loaded ) || !isdefined( level.zs ) || !level.zs.enabled )
        return 0;

    zs_load_config();
    return 1;
}

/*
    The limit the map would give this player if ZShare were not here: the
    callback ZShare kept before installing its own, which on a map that
    sets one is that map's and includes the slots it adds.
*/
zs_api_stock_perk_limit( player )
{
    if ( !isdefined( player ) )
        return 0;

    if ( isdefined( level.zs_perk_limit_stock ) )
        return player [[ level.zs_perk_limit_stock ]]();

    if ( isdefined( level.perk_purchase_limit ) )
        return level.perk_purchase_limit;

    return 4;
}

/*
    And the limit ZShare is actually holding the map to, map bonuses and
    all -- the same number every machine gets when it asks. ZShare installs
    no override at all while zs_perk_limit is 0, and the honest answer then
    is the map's own.
*/
zs_api_effective_perk_limit( player )
{
    if ( !isdefined( player ) )
        return 0;

    if ( !zs_true( level.zs_loaded ) || !isdefined( level.zs ) || level.zs.perk_limit == 0 )
        return zs_api_stock_perk_limit( player );

    return player zs_perk_limit_get();
}


/* ==================================================================
    BUILD STAMP

    A development build says so on screen: its version and the time it
    was built, top right, one line under ZPause's. Release builds carry
    an empty stamp and draw nothing.
   ================================================================== */

/*
    Written by tools/build.py. The line between the markers is generated;
    do not edit it by hand.
*/
zs_build()
{
    // ZS_BUILD_BEGIN
    return "";
    // ZS_BUILD_END
}

zs_cfg_echo( dvar, value, def )
{
    if ( !zs_true( level.zs_cfg_echo ) )
        return value;

    if ( isdefined( level.zs_cfg_host ) && value != ( "" + def ) )
        level.zs_cfg_host iprintln( "^3" + dvar + "^7  " + value );

    return value;
}

zs_config_watcher()
{
    level endon( "end_game" );

    for ( ;; )
    {
        wait 5;
        zs_load_config();
    }
}

/*
    "set zs_config_print 1" in the console prints every setting that is
    not at its default to the host's screen, then puts the switch back.
*/
zs_config_printer()
{
    level endon( "end_game" );

    if ( getdvarstring( "zs_config_print" ) == "" )
        setdvar( "zs_config_print", "0" );

    for ( ;; )
    {
        wait 1;

        if ( getdvarstring( "zs_config_print" ) != "1" )
            continue;

        setdvar( "zs_config_print", "0" );

        level.zs_cfg_host = undefined;
        players = getplayers();

        if ( players.size > 0 )
            level.zs_cfg_host = players[0];

        if ( isdefined( level.zs_cfg_host ) )
            level.zs_cfg_host iprintln( "^3[ZShare]^7 settings changed from default:" );

        level.zs_cfg_echo = 1;
        zs_load_config();
        level.zs_cfg_echo = 0;

        if ( isdefined( level.zs_cfg_host ) )
            level.zs_cfg_host iprintln( "^3[ZShare]^7 end of settings" );

        level.zs_cfg_host = undefined;
    }
}

zs_build_watermark()
{
    level endon( "end_game" );

    stamp = zs_build();

    if ( stamp == "" )
        return;

    while ( !zs_game_ready() )
        wait 0.5;

    if ( isdefined( level.zs_build_hud ) )
        return;

    e = newhudelem();

    e.horzalign = "right";
    e.vertalign = "top";
    e.alignx = "right";
    e.aligny = "top";
    e.x = 0;
    e.y = 26;
    e.fontscale = 1.1;
    e.color = ( 0.55, 0.85, 1 );
    e.sort = 1000;
    e.foreground = 1;
    e.alpha = 0.7;
    // Which copy drew it, so a test of one against the other can be read
    // off the screen rather than guessed at.
    e settext( stamp + "  [" + zs_origin() + "]" );

    level.zs_build_hud = e;
}
