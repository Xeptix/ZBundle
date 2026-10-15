/*
======================================================================
    ZSHARE v1.5  --  Weapon sharing for Black Ops II Zombies
    Plutonium T6

    by Xep

======================================================================

    Everything you can hand a teammate, all from the button you buy
    everything else with:

        Weapons   Look at a teammate and press use. They see the gun in
                  your hands, look back at you and press use, and the
                  two weapons change hands -- ammo, Pack-a-Punch,
                  attachments and camo travel with them.
        Points    Crouch first, then use: 1000 points go across.
        Box hits  Paid for a box weapon you do not want? Crouch and
                  press use at the box, and it is anyone's to take. The
                  same at the Pack-a-Punch machine.
        Paying    Crouch and press use at a perk machine, or at the box
                  or the Pack-a-Punch while nobody is using it, and the
                  next teammate to use that machine pays nothing.

    There is nothing new to learn. Use is the button, crouching is what
    changes what it does, and the prompt on screen says which.

    Everything runs on the host. Nobody else needs this file or any mod:
    the prompts, the swap, the box, the machines and the points all
    execute server-side and replicate to stock clients.

    Settings live in zs_load_config() below. Each one is also a dvar of
    the same name, and the config is re-read every few seconds and on
    every press, so changes apply without a map restart.

----------------------------------------------------------------------
    HOW IT WORKS

    The prompts on players are the game's own use triggers. Each player
    carries one per teammate, linked to them the way _zm_laststand.gsc
    links the revive prompt to a downed player, so it follows them and
    only lights up when that teammate is looking at them.

    A weapon changes hands the way the game's own weapon locker moves
    one: _zm_weapons.gsc reads everything about a weapon into a record
    with get_player_weapondata() and gives it back with weapondata_give().
    ZShare takes the two records, takes the two weapons, and gives each
    record to the other player.

    The box already knows how to let anybody take a weapon somebody else
    paid for -- box_rerespun, the state the hacker's re-spin leaves it in
    -- and how to open for nothing: auto_open and no_charge, the state
    the hacker's summon leaves it in. Sharing a hit sets the first.
    Paying for a spin sets the second.

    The Pack-a-Punch reads its price off its trigger on every press, so
    a paid pack is that price held at zero until somebody uses it. Its
    take loop is replaced with itself plus a share branch.

    A perk machine asks custom_perk_validation before it looks at the
    price, and that is where a paid drink is handed out, through the
    stock drinking code. Mob of the Dead and Origins use the same hook,
    and theirs are asked first.

    A perk machine and the Pack-a-Punch each show one prompt to every
    player, but a payer needs different words. So the payer's words are
    a second prompt at the machine, and the two stock loops that decide
    who sees a machine are replaced with copies that hide it from anyone
    reading the second one.

----------------------------------------------------------------------
    CREDITS

        Xep           author
        Treyarch      _zm_magicbox.gsc, _zm_perks.gsc, _zm_weapons.gsc,
                      _zm_laststand.gsc -- everything this stands on
        plutoniummod  t6-scripts, the stock script reference

----------------------------------------------------------------------
    LICENSE

        MIT -- see LICENSE. Keep this header on copies.

======================================================================
*/

#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\gametypes_zm\_hud_util;


/* ==================================================================
    ENTRY POINT
   ================================================================== */

init()
{
    // Plutonium may call init() and/or main() depending on how this file
    // is loaded (scripts folder vs mods folder). Only ever set up once.
    if ( is_true( level.zs_loaded ) )
        return;

    /*
        Config first, and the flag after: zs_only_script and zs_only_mod
        are read from it, and a copy that is not the one being asked for
        has to leave level.zs_loaded alone so the other one can still take
        it.
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
    level.zs_perk_machines = [];
    level.zs_pap_machines = [];
    level.zs_pay_team_ok = 0;
    level.zs_late_hooked = 0;
    level.zs_box_paid = 0;

    /*
        Replaced now, while the level is still loading. All three are
        started later -- the take loop each time a weapon comes out of the
        Pack-a-Punch, and both visibility loops when a machine powers on,
        which every stock map does after the intro or at the power switch
        -- so each one is ZShare's from the first time it runs. A power
        cycle starts them again through the same names.
    */
    zs_replace_stock();

    level thread zs_connect_watcher();
    level thread zs_chat_listener();
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

main()
{
    init();
}


/* ==================================================================
    CONFIG

    Every value below can also be overridden with a dvar of the same
    name (set it in your config before the map loads), so server hosts
    do not have to edit this file.
   ================================================================== */

/*
    Which copy of the script this is: "script" for the two loose paths
    Plutonium reads, "mod" for the copy inside mods\zm_share.

    With the mod selected both reach init(), and the first one there wins.
    zs_only_script and zs_only_mod pick the winner instead, which is worth
    having only while testing one against the other.

    Written by mk_t6_mod.py when it generates the mod copy, the same way
    build.py writes the version stamp. Never edit it by hand.
*/
zs_origin()
{
    // ZS_ORIGIN_BEGIN
    return "mod";
    // ZS_ORIGIN_END
}

/*
    Whether this copy is the one that was asked for. Neither setting on --
    which is the default -- means whichever loads first, as before.
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

zs_load_config()
{
    /*
        Reuse the struct rather than making a new one. spawnstruct() takes
        a parent script variable, and this runs on every press -- so
        allocating each time would walk a long session into "exceeded
        maximum number of parent server script variables" and drop it.
        The fields below are all overwritten on every pass, so there is
        nothing stale to clear.
    */
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

    // --- debug -----------------------------------------------------
    /*
        Which copy of the script runs when more than one is installed --
        the loose ones Plutonium reads, or the copy in mods\zm_share.
        Both off is whichever gets there first, which is the normal case.

        For testing one against the other. Setting both leaves nothing
        running at all. Read once, when the script loads: init() runs a
        single time per game, so changing either of these mid-match cannot
        move which copy is already running. End the game and start a new
        one.
    */
    level.zs.only_script = zs_cfg_int( "zs_only_script", 0 );
    level.zs.only_mod    = zs_cfg_int( "zs_only_mod", 0 );

    // Print what the script decides and why, to the console and the host.
    level.zs.debug       = zs_cfg_int( "zs_debug", 0 );

    // --- trading ---------------------------------------------------

    // Trade weapons with a teammate: use on them to offer, use back to accept.
    level.zs.trade            = zs_cfg_int( "zs_trade", 1 );

    // How long an offer stays open before it lapses on its own.
    level.zs.trade_offer_time = zs_cfg_float( "zs_trade_offer_time", 10 );

    /*
        Whether a Pack-a-Punched weapon can be traded. On by default --
        handing a friend the upgraded gun is most of the point -- but a
        server that wants every player to pay their own 5000 can turn it
        off, and the prompt then says so.
    */
    level.zs.trade_upgraded   = zs_cfg_int( "zs_trade_upgraded", 1 );

    /*
        How close you have to be for the prompt to appear, in units. 64 is
        about arm's length in this engine; the revive prompt uses 75. An
        offer lapses on its own once the two of you are more than twice
        this apart. Read when a prompt is built, so a change reaches the
        prompts within a second.
    */
    level.zs.range            = zs_cfg_int( "zs_range", 64 );

    // --- points ----------------------------------------------------

    // Crouch, look at a teammate and press use to give them points.
    level.zs.points           = zs_cfg_int( "zs_points", 1 );
    level.zs.points_amount    = zs_cfg_int( "zs_points_amount", 1000 );

    /*
        Seconds between gifts from one player. Each press is one gift, so
        three presses is 3000 points; this is only so a held button does
        not empty a bank in a second.
    */
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

    /*
        Share a box hit: crouch and press use at the box while the weapon
        you paid for is up, and anybody can take it. The box weapon stays
        up for the same twelve seconds either way.
    */
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

        Off stops new payments only. One already waiting still works and
        can still be taken back, so switching these off never keeps
        anybody's points.
    */
    level.zs.perk_pay         = zs_cfg_int( "zs_perk_pay", 1 );
    level.zs.box_pay          = zs_cfg_int( "zs_box_pay", 1 );
    level.zs.pap_pay          = zs_cfg_int( "zs_pap_pay", 1 );

    // --- perks -----------------------------------------------------

    /*
        How many perks one player can hold. 0 is the map's own limit:
        four on every stock map, plus the extra slots Origins' digging
        hands out. Any other number replaces the four, and Origins' extra
        slots still count on top of it. -1 is no limit at all.

        One limit however the perk is had -- bought, paid for by a
        teammate, or out of Origins' Der Wunderfizz -- because every one
        of those asks the game the same question.
    */
    level.zs.perk_limit       = zs_cfg_int( "zs_perk_limit", 0 );

    // --- presentation ----------------------------------------------

    // Tell players what the prompts do, once, shortly after they spawn.
    level.zs.show_hint        = zs_cfg_int( "zs_show_hint", 1 );

    /*
        The one-line messages -- "Xep gave you 1000 points", "Xep paid for
        the next box spin". Off leaves the prompts and the sounds, which is
        what a quiet server wants.
    */
    level.zs.messages         = zs_cfg_int( "zs_messages", 1 );

    // --- sounds ----------------------------------------------------

    /*
        Stock aliases, so both packagings stay one drop-in file -- a
        custom sound would have to be installed by every player rather
        than just the host. packa_ready is the chime the Pack-a-Punch
        plays when your weapon is ready, cha_ching is the game's own
        points sound and no_cha_ching is its refusal. Set any to "" for
        silence.
    */
    level.zs.offer_sound      = zs_cfg_str( "zs_offer_sound", "zmb_perks_packa_ready" );
    level.zs.trade_sound      = zs_cfg_str( "zs_trade_sound", "zmb_whoosh" );
    level.zs.share_sound      = zs_cfg_str( "zs_share_sound", "zmb_perks_packa_ready" );
    level.zs.points_sound     = zs_cfg_str( "zs_points_sound", "zmb_cha_ching" );
    level.zs.deny_sound       = zs_cfg_str( "zs_deny_sound", "zmb_no_cha_ching" );

    // Height of the prompt volume, in units. Not a setting: it is the
    // hacker's 72, which reaches a standing player from the floor.
    level.zs.height = 72;
}

/*
    set_dvar_if_unset() (maps\mp\_utility) creates the dvar with our default
    the first time the config is read, and leaves alone anything already set
    in config.cfg. Creating it is the point: the console can only assign to a
    dvar that already exists, so a read-only getdvar would leave every setting
    unreachable from in game.
*/
zs_cfg_int( dvar, def )
{
    return int( zs_cfg_echo( dvar, set_dvar_if_unset( dvar, "" + def ), def ) );
}

zs_cfg_float( dvar, def )
{
    return float( zs_cfg_echo( dvar, set_dvar_if_unset( dvar, "" + def ), def ) );
}

/*
    "none" is how a string setting is emptied in game. An empty dvar reads
    as one that was never set, and set_dvar_if_unset() writes the default
    straight back, so "" typed into the console lasted only until the next
    read -- five seconds at most.
*/
zs_cfg_str( dvar, def )
{
    value = zs_cfg_echo( dvar, set_dvar_if_unset( dvar, def ), def );

    if ( value == "none" )
        return "";

    return value;
}


/* ==================================================================
    HOOKS

    What ZShare changes in the stock scripts, in one place.
   ================================================================== */

/*
    replaceFunc() redirects every call to a stock function, including the
    calls _zm_perks.gsc makes to its own functions by name. It does not
    reach into a copy already running, which is why this happens during
    load, before any of the three has been started.
*/
zs_replace_stock()
{
    level.zs_pap_take_hooked = zs_replace( "wait_for_player_to_take", ::zs_pap_take );
    level.zs_pap_vis_hooked  = zs_replace( "vending_machine_trigger_think", ::zs_pap_visibility );
    level.zs_perk_vis_hooked = zs_replace( "check_player_has_perk", ::zs_perk_visibility );
}

zs_replace( name, replacement )
{
    fn = getfunction( "maps/mp/zombies/_zm_perks", name );

    if ( !isdefined( fn ) )
    {
        println( "ZShare: _zm_perks::" + name + " not found -- left as it is" );
        return 0;
    }

    replacefunc( fn, replacement, -1 );
    return 1;
}

/*
    Two hooks the maps set themselves, which have to be wrapped rather
    than replaced. Mob of the Dead's Brutus locks and Origins' generators
    both answer "can this machine be used" through custom_perk_validation,
    and Origins keeps its own per-player perk limit. Origins installs them
    once the round logic starts, so ZShare waits for that and a beat more,
    takes whatever is there, and asks it first.

    Nobody can pay for a drink until this has run, so no paid drink can
    ever meet a machine that does not know about it.
*/
zs_late_hooks()
{
    level endon( "end_game" );

    while ( !zs_flag( "start_zombie_round_logic" ) )
        wait 0.25;

    wait 1;

    level.zs_perk_validation_prev = level.custom_perk_validation;
    level.custom_perk_validation = ::zs_perk_validation;

    level.zs_perk_limit_prev = level.get_player_perk_purchase_limit;
    level.get_player_perk_purchase_limit = ::zs_perk_limit_get;

    level.zs_late_hooked = 1;
    zs_debug( "perk validation and perk limit wrapped" );

    // Buried builds its time bomb during load. See THE TIME BOMB.
    zs_time_bomb_hook();
}

/*
    flag() asserts on a flag that was never initialised, and the assert
    is compiled out of a release build -- so what is left would read an
    undefined value. This answers "not set" instead.
*/
zs_flag( name )
{
    if ( !isdefined( level.flag ) || !isdefined( level.flag[name] ) )
        return 0;

    return level.flag[name];
}

zs_fire_sale_on()
{
    if ( !isdefined( level.zombie_vars ) )
        return 0;

    return is_true( level.zombie_vars["zombie_powerup_fire_sale_on"] );
}

zs_bonfire_on()
{
    if ( !isdefined( level.zombie_vars ) )
        return 0;

    return is_true( level.zombie_vars["zombie_powerup_bonfire_sale_on"] );
}


/* ==================================================================
    INPUT -- CHAT

    One word. Everything else is a prompt, and a prompt is better than
    a word for an action aimed at a person or a machine -- but a box hit
    can be shared without walking back to the box.
   ================================================================== */

zs_chat_listener()
{
    level endon( "end_game" );

    for (;;)
    {
        level waittill( "say", message, player );

        if ( !isdefined( message ) || !isdefined( player ) )
            continue;

        msg = tolower( message );

        if ( zs_word_is( msg, "!share" ) )
        {
            level thread zs_chat_share( player );
            continue;
        }

        if ( zs_word_is( msg, "!thank" ) || zs_word_is( msg, "!t" ) )
        {
            level thread zs_chat_thank( player );
            continue;
        }

        rest = zs_word_after( msg, "!tip" );

        if ( isdefined( rest ) )
            level thread zs_chat_tip( player, rest );
    }
}

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

zs_chat_thank( player )
{
    zs_load_config();

    if ( !isdefined( player ) || !level.zs.thank )
        return;

    to = player zs_favour_who();

    if ( !isdefined( to ) )
    {
        player zs_say( "Nobody has done you a good turn just now" );
        return;
    }

    player zs_thank( to );
}

zs_chat_tip( player, rest )
{
    zs_load_config();

    if ( isdefined( player ) )
        player zs_tip( rest );
}

/*
    Plutonium's "say" notify hands us the message with a stray control
    character at index 0 on T6. It is not reliably testable, so every
    comparison is done twice: once on the raw string and once on the
    string with its first character removed.
*/
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
    one at the Pack-a-Punch. Walks the same state the prompts read.
*/
zs_chat_share( player )
{
    zs_load_config();

    if ( !isdefined( player ) )
        return;

    if ( zs_whos_who( player ) )
    {
        player zs_say( "Revive yourself first -- your Who's Who copy can't share" );
        return;
    }

    if ( level.zs.box_share && isdefined( level.chests ) )
    {
        for ( i = 0; i < level.chests.size; i++ )
        {
            chest = level.chests[i];

            if ( !isdefined( chest ) || !zs_box_shareable( chest, player ) )
                continue;

            chest zs_box_share( player );
            return;
        }
    }

    if ( level.zs.pap_share )
    {
        zs_machines_refresh();

        for ( i = 0; i < level.zs_pap_machines.size; i++ )
        {
            trig = level.zs_pap_machines[i];

            if ( !isdefined( trig ) || !zs_pap_shareable( trig, player ) )
                continue;

            trig zs_pap_share( player );
            return;
        }
    }

    player zs_say( "Nothing of yours is waiting at the box or the Pack-a-Punch" );
}


/* ==================================================================
    PLAYERS
   ================================================================== */

zs_connect_watcher()
{
    level endon( "end_game" );

    // Catch anybody who was already in before this script initialised.
    players = get_players();
    for ( i = 0; i < players.size; i++ )
        players[i] thread zs_player_think();

    for (;;)
    {
        level waittill( "connected", player );
        player thread zs_player_think();
    }
}

zs_player_think()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    if ( is_true( self.zs_thinking ) )
        return;

    self.zs_thinking = 1;

    for (;;)
    {
        self waittill( "spawned_player" );

        /*
            A prompt is linked to the player it belongs to, and a respawn
            puts that player back into the world. Re-linking is cheap and
            saves finding out the hard way whether a link survives it.
        */
        zs_relink_prompts( self );

        if ( level.zs.show_hint && !is_true( self.zs_hinted ) )
        {
            self.zs_hinted = 1;
            self thread zs_hint();
        }
    }
}

zs_hint()
{
    self endon( "disconnect" );
    wait 8;

    if ( level.zs.trade && level.zs.points )
        self iprintln( "^3[ZShare]^7 look at a teammate and press ^3use^7 to trade weapons, or crouch first to give them " + level.zs.points_amount + " points" );
    else if ( level.zs.trade )
        self iprintln( "^3[ZShare]^7 look at a teammate and press ^3use^7 to trade weapons" );
    else if ( level.zs.points )
        self iprintln( "^3[ZShare]^7 crouch, look at a teammate and press ^3use^7 to give them " + level.zs.points_amount + " points" );

    if ( level.zs.box_share && level.zs.pap_share )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at the box or the Pack-a-Punch to share your hit" );
    else if ( level.zs.box_share )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at the box to share your hit" );
    else if ( level.zs.pap_share )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at the Pack-a-Punch to share your upgrade" );

    places = zs_pay_places();

    if ( places != "" )
        self iprintln( "^3[ZShare]^7 crouch and press ^3use^7 at " + places + " to pay for a teammate" );
}

zs_pay_places()
{
    places = [];

    if ( level.zs.perk_pay )
        places[places.size] = "a perk machine";

    if ( level.zs.box_pay )
        places[places.size] = "the box";

    if ( level.zs.pap_pay )
        places[places.size] = "the Pack-a-Punch";

    if ( places.size == 0 )
        return "";

    if ( places.size == 1 )
        return places[0];

    if ( places.size == 2 )
        return places[0] + " or " + places[1];

    return places[0] + ", " + places[1] + " or " + places[2];
}

/*
    Whether a player can take part in anything right now. The same list
    the box uses before it takes your money: alive and on their feet, not
    mid-perk, not spectating, and not with the hacker out.
*/
zs_player_ok( player )
{
    if ( !isdefined( player ) )
        return 0;

    if ( !is_player_valid( player ) )
        return 0;

    if ( isdefined( player.is_drinking ) && player.is_drinking > 0 )
        return 0;

    if ( player hacker_active() )
        return 0;

    return 1;
}

/*
    Whether a player can pay at a machine, or take a payment back.
    Everything above, and not standing over a downed teammate -- a crouch
    next to somebody on the floor is a revive, and the stock machines step
    aside for it the same way -- and not a Mob of the Dead ghost. A new
    payment also needs a player who is not a Who's Who copy.
*/
zs_payer_ok( player )
{
    if ( !zs_player_ok( player ) )
        return 0;

    if ( player in_revive_trigger() )
        return 0;

    if ( is_true( player.afterlife ) )
        return 0;

    if ( is_true( level.intermission ) )
        return 0;

    return 1;
}

/*
    Both of them, and on the same side. In Grief the teams are opponents,
    and there is no such thing as trading with an opponent. Classic
    zombies puts everybody on one team, so this is always true there.
*/
zs_pair_ok( a, b )
{
    if ( !zs_player_ok( a ) || !zs_player_ok( b ) )
        return 0;

    if ( a == b )
        return 0;

    if ( isdefined( a.team ) && isdefined( b.team ) && a.team != b.team )
        return 0;

    if ( is_true( level.intermission ) )
        return 0;

    return 1;
}

/*
    Die Rise's Who's Who. Going down with it leaves your body on the
    floor and puts you back on your feet as a copy with a pistol, and
    reviving the body hands back the guns and the points you went down
    with: whatever the copy picked up or spent is undone. That would undo
    one side of a trade, a gift, a payment or a share and leave the other
    standing, so a copy does none of them. It can still be given points
    and take a payment back -- see zs_saved_score_add().

    The body is set on the player before the copy can move, and cleared
    only once the revive has handed everything back.
*/
zs_whos_who( player )
{
    return isdefined( player ) && isdefined( player.e_chugabud_corpse );
}

/*
    Who's Who and Mob of the Dead's afterlife both keep the score a player
    went down with in player.loadout, and write it back over their score
    when they are revived. Points that reach the player in between go into
    the kept score too, or the revive would take them away again. A body
    that is never revived never has its kept score read, and the points
    are already on the score.
*/
zs_saved_score_add( player, amount )
{
    if ( !isdefined( player ) || !isdefined( amount ) || amount <= 0 )
        return;

    if ( isdefined( player.loadout ) && isdefined( player.loadout.score ) )
        player.loadout.score = player.loadout.score + amount;
}

/*
    Points going back to a player who paid, the way the box refunds a
    teddy bear: add_to_player_score( n, 0 ). That adds nothing during the
    intermission, so the kept score gets what the score actually got.
*/
zs_refund( player, amount )
{
    if ( !isdefined( player ) || !isdefined( amount ) || amount <= 0 )
        return;

    before = player.score;
    player maps\mp\zombies\_zm_score::add_to_player_score( amount, 0 );
    zs_saved_score_add( player, player.score - before );
}

/*
    Paying needs somebody to pay for, and they have to be on your side.
    Grief puts two teams at the same machines, where a drink paid for one
    team would be drunk by the other, so paying is off whenever the
    players span more than one team.
*/
zs_pay_team_check()
{
    players = get_players();

    if ( players.size < 2 )
        return 0;

    team = undefined;

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) || !isdefined( players[i].team ) )
            continue;

        if ( !isdefined( team ) )
            team = players[i].team;
        else if ( players[i].team != team )
            return 0;
    }

    return 1;
}

/*
    The stance itself rather than the button, so toggle-crouch and
    hold-crouch read the same. Prone counts: it is further down than
    crouched, and nobody goes prone to trade a gun.
*/
zs_crouched( player )
{
    if ( !isdefined( player ) )
        return 0;

    stance = player getstance();
    return stance == "crouch" || stance == "prone";
}


/* ==================================================================
    PROMPTS ON PLAYERS

    One use trigger per (teammate, viewer) pair, linked to the teammate
    and visible only to the viewer. Two per pair, one each way, so four
    players carry twelve between them.

    Per pair rather than per teammate because the words on the prompt
    depend on who is reading it: "accept the trade" is only true for the
    one player the offer was made to, and "give 1000 points" only for a
    viewer who is crouched. A shared prompt could only ever say the
    generic thing.

    Every string on a prompt is one of a fixed handful. Hint strings are
    configstrings -- the same pool a HUD element's settext() draws from,
    the pool that a ticking clock drawn as text once exhausted -- so a
    weapon or player name never goes into one. Names go in the chat
    line, which is not a configstring.

    The use key is written [{+activate}], the form every localized stock
    prompt uses and the client swaps for each player's own binding. &&1
    is not it: in a stock prompt &&1 is where the cost goes.
   ================================================================== */

zs_prompt_make( target, viewer )
{
    /*
        The recipe is _zm_laststand.gsc's revive trigger with the hacker's
        use-trigger pieces on top: a radius trigger, moving-platform aware,
        linked to the player so it rides along, hidden from everybody but
        the one it is for, and requiring the viewer to actually look at
        it -- otherwise standing next to a teammate would show the prompt
        all night.

        Origin 36 up from the feet. The look-at test aims at the trigger's
        origin, and the torso is where a player looks at another player.
        The volume reaches the floor either way; the hacker's own prompts
        sit 24 up with the same height and take a standing player.
    */
    t = spawn( "trigger_radius_use", target.origin + ( 0, 0, 36 ), 0, level.zs.range, level.zs.height );
    t setcursorhint( "HINT_NOICON" );
    t triggerignoreteam();
    t usetriggerrequirelookat();
    t setmovingplatformenabled( 1 );
    t enablelinkto();
    t linkto( target );
    t setinvisibletoall();

    t.zs_target = target;
    t.zs_viewer = viewer;
    t.zs_radius = level.zs.range;
    t.zs_hint = "";
    t.zs_shown = 0;

    t thread zs_prompt_think();

    level.zs_triggers[level.zs_triggers.size] = t;

    zs_debug( "prompt built: " + target.name + " for " + viewer.name );

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
    on connect, so a late joiner, a rebuilt prompt and a changed range all
    heal the same way without a special case each.
*/
zs_prompts_ensure()
{
    players = get_players();

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

    // Deleting an entity ends the threads waiting on it; the notify is
    // the same belt and braces the unitrigger system uses before it
    // deletes one of its own.
    t notify( "zs_kill" );
    t unlink();
    t delete();
}

/*
    The one loop behind every prompt on a player: who can see it, and
    what it says. Ten times a second, which is what the revive prompt
    runs at, and the hint string is only written when it changes.
*/
zs_trigger_updater()
{
    level endon( "end_game" );

    tick = 0;

    for (;;)
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

            // A player on either side has gone, or the range moved
            // underneath it: drop it, and the ensure pass rebuilds any
            // pair that still exists.
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
            self setinvisibletoplayer( viewer );
            self.zs_shown = 0;
        }

        return;
    }

    if ( want != self.zs_hint )
    {
        self sethintstring( want );
        self.zs_hint = want;
    }

    if ( !self.zs_shown )
    {
        self setvisibletoplayer( viewer );
        self.zs_shown = 1;
    }
}

/*
    What the viewer reads on the target, or "" for no prompt at all.
    Every branch returns one of a fixed set of strings; see the note at
    the top of this section for why.
*/
zs_prompt_text( target, viewer )
{
    if ( !zs_pair_ok( target, viewer ) )
        return "";

    // A Who's Who copy can be given points, and gives and trades nothing.
    if ( level.zs.points && zs_crouched( viewer ) )
    {
        if ( zs_whos_who( viewer ) )
            return "";

        /*
            A thank takes the crouched press while one is owed, because
            crouch already means "give them something" and a thank is a
            smaller one with a reason. It reverts on its own when the
            window closes, and the full gift is still a chat word away.
        */
        if ( viewer zs_owes_thanks( target ) )
            return "Hold ^3[{+activate}]^7 to thank them (" + level.zs.thank_amount + " points)";

        return "Hold ^3[{+activate}]^7 to give " + level.zs.points_amount + " points";
    }

    if ( !level.zs.trade || zs_whos_who( viewer ) || zs_whos_who( target ) )
        return "";

    if ( zs_offer_is( target, viewer ) )
        return "Hold ^3[{+activate}]^7 to accept the trade";

    if ( zs_offer_is( viewer, target ) )
        return "Hold ^3[{+activate}]^7 to cancel the trade";

    return "Hold ^3[{+activate}]^7 to trade weapons";
}

zs_prompt_think()
{
    self endon( "zs_kill" );
    level endon( "end_game" );

    for (;;)
    {
        self waittill( "trigger", user );

        if ( !isdefined( user ) || !isdefined( self.zs_target ) || !isdefined( self.zs_viewer ) )
            continue;

        // Hidden from everybody else, so this is belt and braces.
        if ( user != self.zs_viewer )
            continue;

        zs_load_config();
        user zs_use_on( self.zs_target );

        // One press, one action. The engine reports a press once, but a
        // beat here costs nothing and a double action would cost a gun.
        wait 0.3;
    }
}

/*
    What a press means, in the order the prompt promised it: crouched is
    points, otherwise it is whichever step of a trade comes next.
*/
zs_use_on( target )
{
    if ( !zs_pair_ok( self, target ) )
        return;

    if ( level.zs.points && zs_crouched( self ) )
    {
        if ( zs_whos_who( self ) )
            return;

        if ( self zs_owes_thanks( target ) )
            self zs_thank( target );
        else
            self zs_points_give( target );

        return;
    }

    if ( !level.zs.trade || zs_whos_who( self ) || zs_whos_who( target ) )
        return;

    // They offered to me: this press is the acceptance.
    if ( zs_offer_is( target, self ) )
    {
        zs_trade_do( target, self );
        return;
    }

    // I already offered to them: this press takes it back.
    if ( zs_offer_is( self, target ) )
    {
        self zs_offer_cancel( "withdrawn" );
        return;
    }

    self zs_offer_make( target );
}


/* ==================================================================
    TRADING

    An offer lives on the player who made it: who it is to, which weapon,
    and when it lapses. One at a time -- a new offer replaces the old --
    and it is spent the moment it is accepted, cancelled or times out. A
    serial number keeps a lapsed offer's watcher from ever touching a
    newer one.

    What is offered is the weapon in your hands when you press, and what
    comes back is the weapon in theirs when they accept. Nothing has to
    be named: they can see what you are holding.
   ================================================================== */

zs_offer_is( from, to )
{
    if ( !isdefined( from ) || !isdefined( to ) )
        return 0;

    return isdefined( from.zs_offer_to ) && from.zs_offer_to == to;
}

zs_offer_make( to )
{
    weapon = self zs_held_weapon();
    why = self zs_untradeable( weapon );

    if ( why != "" )
    {
        self zs_deny( why );
        return;
    }

    if ( isdefined( self.zs_offer_to ) )
        self zs_offer_cancel( "replaced" );

    if ( !isdefined( self.zs_offer_serial ) )
        self.zs_offer_serial = 0;

    self.zs_offer_serial++;
    self.zs_offer_to = to;
    self.zs_offer_weapon = weapon;
    self.zs_offer_until = gettime() + int( level.zs.trade_offer_time * 1000 );

    self thread zs_offer_watcher( self.zs_offer_serial );

    self zs_say( "Offered your weapon to ^3" + to.name + "^7 -- they have " + int( level.zs.trade_offer_time ) + " seconds to accept" );
    to zs_say( "^3" + self.name + "^7 wants to trade weapons -- look at them and press ^3use^7 to accept" );
    to zs_sound( level.zs.offer_sound );

    zs_debug( self.name + " offers " + weapon + " to " + to.name );
}

zs_offer_clear()
{
    self.zs_offer_to = undefined;
    self.zs_offer_weapon = undefined;
    self.zs_offer_until = undefined;

    if ( isdefined( self.zs_offer_serial ) )
        self.zs_offer_serial++;
}

zs_offer_cancel( why )
{
    to = self.zs_offer_to;

    self zs_offer_clear();

    if ( why == "withdrawn" )
    {
        self zs_say( "Trade cancelled" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7 cancelled the trade" );
    }
    else if ( why == "expired" )
    {
        self zs_say( "Your trade offer lapsed" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7's trade offer lapsed" );
    }
    else if ( why == "switched" || why == "lost" )
    {
        self zs_say( "Trade cancelled -- you put the weapon away" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7 put the weapon away -- trade cancelled" );
    }
    else if ( why == "distance" )
    {
        self zs_say( "Trade cancelled -- too far apart" );

        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7's trade offer lapsed -- too far apart" );
    }
    else if ( why == "replaced" )
    {
        if ( isdefined( to ) )
            to zs_say( "^3" + self.name + "^7 withdrew the trade" );
    }

    zs_debug( "offer cancelled: " + why );
}

/*
    Everything that ends an offer short of accepting it. Keyed on the
    serial so a watcher outlived by its offer does nothing.
*/
zs_offer_watcher( serial )
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for (;;)
    {
        wait 0.1;

        if ( !isdefined( self.zs_offer_serial ) || self.zs_offer_serial != serial )
            return;

        to = self.zs_offer_to;

        if ( !isdefined( to ) )
        {
            self zs_offer_clear();
            self zs_say( "Trade cancelled -- they left" );
            return;
        }

        if ( gettime() > self.zs_offer_until )
        {
            self zs_offer_cancel( "expired" );
            return;
        }

        if ( !self hasweapon( self.zs_offer_weapon ) )
        {
            self zs_offer_cancel( "lost" );
            return;
        }

        /*
            Switching to your other gun withdraws the offer, since what is
            on offer is what they can see in your hands. A grenade throw
            or a knife lunge passes through here as a non-primary and is
            left alone.
        */
        held = self zs_held_weapon();

        if ( held != self.zs_offer_weapon && zs_is_primary( self, held ) )
        {
            self zs_offer_cancel( "switched" );
            return;
        }

        if ( distance( self.origin, to.origin ) > level.zs.range * 2 )
        {
            self zs_offer_cancel( "distance" );
            return;
        }

        if ( !zs_pair_ok( self, to ) || zs_whos_who( self ) || zs_whos_who( to ) )
        {
            self zs_offer_cancel( "expired" );
            return;
        }
    }
}

/*
    The swap. a offered, b accepted; a's offered weapon goes to b, and
    whatever b is holding goes to a.
*/
zs_trade_do( a, b )
{
    wa = a.zs_offer_weapon;
    wb = b zs_held_weapon();

    if ( !isdefined( wa ) || !a hasweapon( wa ) )
    {
        a zs_offer_cancel( "lost" );
        return;
    }

    why = b zs_untradeable( wb );

    if ( why != "" )
    {
        b zs_deny( why );
        return;
    }

    if ( wa == wb )
    {
        b zs_deny( "You already have that weapon" );
        return;
    }

    /*
        weapondata_give() folds a weapon into one of the same family the
        receiver already carries -- the plain gun and its upgrade count as
        one -- and the trade would then take a gun from them and give back
        only ammo. So a trade like that is refused, the way a wall buy
        refuses to sell you a second copy.
    */
    if ( zs_carries_same_family( b, wa, wb ) )
    {
        b zs_deny( "You already carry that weapon" );
        return;
    }

    if ( zs_carries_same_family( a, wb, wa ) )
    {
        b zs_deny( "^3" + a.name + "^7 already carries that weapon" );
        return;
    }

    if ( zs_staff_blocked( b, wa, wb ) )
    {
        b zs_deny( "You already carry a staff" );
        return;
    }

    if ( zs_staff_blocked( a, wb, wa ) )
    {
        b zs_deny( "^3" + a.name + "^7 already carries a staff" );
        return;
    }

    // Mid-switch or mid-throw, the same beat the Pack-a-Punch gives.
    if ( a isswitchingweapons() || b isswitchingweapons() || a isthrowinggrenade() || b isthrowinggrenade() )
    {
        wait 0.1;

        if ( a isswitchingweapons() || b isswitchingweapons() || a isthrowinggrenade() || b isthrowinggrenade() )
            return;
    }

    // Spent from here, whatever happens below.
    a zs_offer_clear();

    da = maps\mp\zombies\_zm_weapons::get_player_weapondata( a, wa );
    db = maps\mp\zombies\_zm_weapons::get_player_weapondata( b, wb );

    /*
        A Pack-a-Punched weapon's lens and reticle are rolled once per
        player per weapon and cached; giving it to somebody else would
        roll again. Copy the cache across first, so the gun that arrives
        is the gun that left.
    */
    zs_carry_options( a, b, wa );
    zs_carry_options( b, a, wb );

    a zs_take( wa );
    b zs_take( wb );

    b maps\mp\zombies\_zm_weapons::weapondata_give( da );
    a maps\mp\zombies\_zm_weapons::weapondata_give( db );

    a zs_say( "Traded weapons with ^3" + b.name );
    b zs_say( "Traded weapons with ^3" + a.name );
    a zs_sound( level.zs.trade_sound );
    b zs_sound( level.zs.trade_sound );

    zs_debug( a.name + " " + wa + " <-> " + b.name + " " + wb );
}

/*
    Whether the receiver already has a weapon of the same family as the
    one coming in. The weapon they are giving away does not count, since
    it leaves in the same trade.
*/
zs_carries_same_family( receiver, incoming, outgoing )
{
    have = receiver maps\mp\zombies\_zm_weapons::get_player_weapon_with_same_base( incoming );

    if ( !isdefined( have ) )
        return 0;

    return have != outgoing;
}

/*
    Take a weapon the way _zm_weapons.gsc takes one it is buying over:
    the ballistic knife has a watcher that wants telling, and a limited
    weapon has a wall toggle to put back.
*/
zs_take( weapon )
{
    if ( issubstr( weapon, "knife_ballistic_" ) )
        self notify( "zmb_lost_knife" );

    self takeweapon( weapon );
    maps\mp\zombies\_zm_weapons::unacquire_weapon_toggle( weapon );
}

zs_carry_options( from, to, weapon )
{
    if ( !isdefined( from.pack_a_punch_weapon_options ) )
        return;

    if ( !isdefined( from.pack_a_punch_weapon_options[weapon] ) )
        return;

    if ( !isdefined( to.pack_a_punch_weapon_options ) )
        to.pack_a_punch_weapon_options = [];

    to.pack_a_punch_weapon_options[weapon] = from.pack_a_punch_weapon_options[weapon];
}

/*
    What you are holding, as the primary it belongs to. Holding the
    grenade launcher under an M16 is holding the M16.
*/
zs_held_weapon()
{
    weapon = self getcurrentweapon();

    if ( !isdefined( weapon ) )
        return "none";

    if ( is_alt_weapon( weapon ) )
        weapon = self maps\mp\zombies\_zm_weapons::get_nonalternate_weapon( weapon );

    if ( !isdefined( weapon ) )
        return "none";

    return weapon;
}

zs_is_primary( player, weapon )
{
    if ( !isdefined( weapon ) || weapon == "none" )
        return 0;

    primaries = player getweaponslistprimaries();

    for ( i = 0; i < primaries.size; i++ )
    {
        if ( primaries[i] == weapon )
            return 1;
    }

    return 0;
}

/*
    Why a weapon cannot change hands, or "" when it can. Primaries only:
    grenades, mines, the knife, equipment and the shield all have their
    own slots and their own rules, and the box will not take your money
    for one either.
*/
zs_untradeable( weapon )
{
    if ( !isdefined( weapon ) || weapon == "none" || weapon == "" || weapon == "zombie_fists_zm" )
        return "Hold the weapon you want to trade";

    if ( isdefined( level.revive_tool ) && weapon == level.revive_tool )
        return "Hold the weapon you want to trade";

    if ( is_offhand_weapon( weapon ) || issubstr( weapon, "shield" ) )
        return "That isn't a weapon you can trade";

    if ( !zs_is_primary( self, weapon ) )
        return "Hold the weapon you want to trade";

    if ( !level.zs.trade_upgraded && maps\mp\zombies\_zm_weapons::is_weapon_upgraded( weapon ) )
        return "Pack-a-Punched weapons can't be traded here";

    /*
        Buried's time bomb carries a snapshot of the whole game inside
        it. It belongs to the round it was armed in, not to a player.
    */
    if ( weapon == "time_bomb_zm" || weapon == "time_bomb_detonator_zm" )
        return "That weapon can't be traded";

    return "";
}

/*
    Origins lets each player carry one staff, and its own pickup code
    refuses a second. Trading a staff for a staff is fine; trading one
    to somebody who keeps theirs is not.
*/
zs_staff_blocked( receiver, incoming, outgoing )
{
    if ( !issubstr( incoming, "staff" ) )
        return 0;

    if ( issubstr( outgoing, "staff" ) )
        return 0;

    primaries = receiver getweaponslistprimaries();

    for ( i = 0; i < primaries.size; i++ )
    {
        if ( issubstr( primaries[i], "staff" ) )
            return 1;
    }

    return 0;
}


/* ==================================================================
    POINTS

    Straight onto the score fields, the way _zm_score.gsc's own helpers
    end up doing it, but without going through them: add_to_player_score
    counts towards the giver's career stats, and minus_to_player_score
    announces a purchase to anything listening -- Origins' challenges
    among them. A gift is neither.

    Paying at a machine is the opposite case. It is a purchase, so it
    goes through the same helpers the machine itself would have used.
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

    One thank per favour, so the prompt stays meaningful and "X thanked
    you" means something. To give more, tip.
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

    /*
        Not from a Who's Who copy. The copy's score is put back on the
        revive from loadout.score, so points sent from one are minted:
        the teammate keeps them and the copy gets them back. Every
        prompt path already refuses it; the chat words reach here too.
    */
    if ( zs_whos_who( self ) )
    {
        self zs_deny( "Revive yourself first -- your Who's Who copy can't share" );
        return;
    }

    amount = level.zs.thank_amount;

    if ( self.score < amount )
    {
        self zs_deny( "You need " + amount + " points to thank them" );
        return;
    }

    self.zs_favour_from = undefined;

    self.score = self.score - amount;
    self.pers["score"] = self.score;
    to.score = to.score + amount;
    to.pers["score"] = to.score;
    zs_saved_score_add( to, amount );

    self zs_say( "Thanked ^3" + to.name + "^7 -- " + amount + " points" );
    to zs_say( "^3" + self.name + "^7 thanked you -- " + amount + " points" );

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

    // Not from a Who's Who copy -- see zs_thank().
    if ( zs_whos_who( self ) )
    {
        self zs_deny( "Revive yourself first -- your Who's Who copy can't share" );
        return;
    }

    parts = strtok( rest, " " );

    if ( parts.size == 0 )
    {
        self zs_say( "Say ^3!tip 500^7, or ^3!tip <name> 500^7" );
        return;
    }

    amount = int( parts[parts.size - 1] );

    if ( amount <= 0 )
    {
        self zs_say( "Say ^3!tip 500^7, or ^3!tip <name> 500^7" );
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
            self zs_say( "Nobody owed a thank -- say ^3!tip <name> " + amount + "^7 instead" );
            return;
        }
    }

    if ( !zs_pair_ok( self, to ) )
        return;

    if ( self.score < amount )
    {
        self zs_deny( "You only have " + self.score + " points" );
        return;
    }

    self.score = self.score - amount;
    self.pers["score"] = self.score;
    to.score = to.score + amount;
    to.pers["score"] = to.score;
    zs_saved_score_add( to, amount );

    self zs_say( "Tipped ^3" + to.name + "^7 " + amount + " points" );
    to zs_say( "^3" + self.name + "^7 tipped you " + amount + " points" );

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

    players = get_players();

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
        asker zs_say( "More than one player starts with ^3" + name + "^7" );
        return undefined;
    }

    if ( !isdefined( found ) )
        asker zs_say( "No player here called ^3" + name );

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

    if ( amount <= 0 || is_true( level.intermission ) )
        return;

    if ( isdefined( self.zs_points_last ) && gettime() - self.zs_points_last < level.zs.points_cooldown * 1000 )
        return;

    if ( self.score < amount )
    {
        self zs_deny( "You need " + amount + " points to give" );
        return;
    }

    self.zs_points_last = gettime();

    self.score = self.score - amount;
    self.pers["score"] = self.score;
    to.score = to.score + amount;
    to.pers["score"] = to.score;
    zs_saved_score_add( to, amount );

    to zs_favour_note( self );

    self zs_say( "Gave ^3" + to.name + "^7 " + amount + " points" );
    to zs_say( "^3" + self.name + "^7 gave you " + amount + " points" );
    self zs_sound( level.zs.points_sound );
    to zs_sound( level.zs.points_sound );

    zs_debug( self.name + " gave " + amount + " to " + to.name );
}


/* ==================================================================
    THE BOX

    Every box has a unitrigger stub -- the record the game builds a
    per-player use trigger from whenever somebody comes near. Two of its
    hooks are open, and ZShare takes both:

        onspawnfunc              runs as each trigger is built, before
                                 its think thread starts. It puts our
                                 relay in as the thread, in place of the
                                 stock one that only forwards presses.
        prompt_and_visibility    decides what each player reads. Ours
                                 calls the stock one and then rewrites
                                 the words when there is something to
                                 share, to pay for, or to take.

    Because the prompt is built per player, a box never needs a second
    prompt the way a perk machine does: the payer, the player a payment
    is waiting for and everybody else can each read their own words off
    the same box.

    Sharing is one field: box_rerespun, the state the hacker's re-spin
    leaves a box in. Paying is two: auto_open and no_charge, the state the
    hacker's summon leaves it in. treasure_chest_think() then opens the
    box for the next player who presses, and charges nothing.

    A payment belongs to the box, not to where the box is. It sits on
    whichever location is live, follows the box when it moves, and waits
    out a fire sale -- a spin costs 10 then, and a free spin during one
    would count toward the box moving where a normal fire sale spin
    does not.
   ================================================================== */

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

    for (;;)
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

    if ( is_true( chest.grab_weapon_hint ) )
    {
        if ( is_true( chest.zs_shared ) )
            return "take_shared";

        if ( level.zs.box_share && crouched && zs_box_shareable( chest, player ) )
            return "share";

        return "stock";
    }

    if ( is_true( chest.is_locked ) || is_true( chest._box_open ) )
        return "stock";

    if ( is_true( level.zs_box_paid ) )
    {
        if ( crouched && isdefined( level.zs_box_paid_by ) && level.zs_box_paid_by == player )
            return "take_back";

        if ( is_true( chest.zs_free ) )
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

    /*
        Not in Grief, where both teams use the one box: a share shows the
        weapon to everybody the way the hacker's re-spin does, and the
        enemy team would be as welcome to it as your own. Paying is off
        there for the same reason -- zs_pay_team_check() answers both.
    */
    if ( !is_true( level.zs_pay_team_ok ) )
        return 0;

    if ( !is_true( chest.grab_weapon_hint ) || is_true( chest.zs_shared ) )
        return 0;

    if ( !isdefined( chest.chest_user ) || chest.chest_user != player )
        return 0;

    return !zs_whos_who( player );
}

zs_box_share( player )
{
    self.box_rerespun = 1;
    self.zs_shared = 1;
    self.zs_shared_by = player;

    // Everybody's prompt is rebuilt at once rather than as each of them
    // wanders in, which is what the stock code does after unlocking.
    self.unitrigger_stub maps\mp\zombies\_zm_unitrigger::run_visibility_function_for_all_triggers();

    zs_say_all( "^3" + player.name + "^7 shared their box weapon -- anyone can take it" );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "box shared by " + player.name );
}

zs_box_is_active( chest )
{
    if ( !isdefined( level.chests ) || !isdefined( level.chest_index ) )
        return 0;

    if ( !isdefined( level.chests[level.chest_index] ) )
        return 0;

    return level.chests[level.chest_index] == chest;
}

zs_box_pay_allowed( chest, player )
{
    if ( !level.zs.box_pay || !is_true( level.zs_pay_team_ok ) )
        return 0;

    if ( zs_fire_sale_on() || zs_flag( "moving_chest_now" ) )
        return 0;

    if ( is_true( chest.hidden ) || !zs_box_is_active( chest ) )
        return 0;

    // The hacker's summon borrows the same free-spin fields.
    if ( isdefined( chest.forced_user ) || isdefined( chest.auto_open ) && !is_true( chest.zs_free ) )
        return 0;

    if ( !isdefined( chest.zombie_cost ) )
        return 0;

    return zs_payer_ok( player ) && !zs_whos_who( player );
}

/*
    Charged the way treasure_chest_think() charges: the full price when
    the player has it, half with the persistent double points upgrade
    when that is all they have. What was actually taken is what comes
    back, whichever it was.
*/
zs_box_pay( player )
{
    cost = self.zombie_cost;
    charge = undefined;

    if ( player.score >= cost )
        charge = cost;
    else if ( player maps\mp\zombies\_zm_pers_upgrades_functions::is_pers_double_points_active() && player.score >= int( cost / 2 ) )
        charge = int( cost / 2 );

    if ( !isdefined( charge ) )
    {
        player maps\mp\zombies\_zm_audio::create_and_play_dialog( "general", "no_money_box" );
        player zs_deny( "You need " + cost + " points" );
        return;
    }

    before = player.score;
    player maps\mp\zombies\_zm_score::minus_to_player_score( charge );

    level.zs_box_paid = 1;
    level.zs_box_paid_by = player;
    level.zs_box_paid_name = player.name;
    level.zs_box_paid_amount = before - player.score;

    self zs_box_free_apply();
    self.unitrigger_stub maps\mp\zombies\_zm_unitrigger::run_visibility_function_for_all_triggers();

    player zs_say( "Paid for the next box spin -- the next teammate to use the box spins free" );
    zs_say_others( player, "^3" + player.name + "^7 paid for the next box spin -- use the box to spin free" );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "box paid by " + player.name + ": " + level.zs_box_paid_amount );
}

zs_box_take_back( player )
{
    amount = level.zs_box_paid_amount;

    zs_box_paid_reset();

    zs_refund( player, amount );

    player zs_say( "Took back your payment for the box" );
    zs_say_others( player, "^3" + player.name + "^7 took back their payment for the box" );
    player zs_sound( level.zs.points_sound );

    zs_debug( "box payment taken back" );
}

zs_box_paid_reset()
{
    level.zs_box_paid = 0;
    level.zs_box_paid_by = undefined;
    level.zs_box_paid_name = undefined;
    level.zs_box_paid_amount = undefined;

    if ( !isdefined( level.chests ) )
        return;

    for ( i = 0; i < level.chests.size; i++ )
    {
        chest = level.chests[i];

        if ( !isdefined( chest ) )
            continue;

        chest zs_box_free_remove();

        if ( isdefined( chest.unitrigger_stub ) )
            chest.unitrigger_stub maps\mp\zombies\_zm_unitrigger::run_visibility_function_for_all_triggers();
    }
}

/*
    Only ever sets fields nobody else is using, and only ever clears the
    ones it set. The hacker's summon leaves its own there while it runs.
*/
zs_box_free_apply()
{
    if ( is_true( self.zs_free ) )
        return;

    if ( isdefined( self.auto_open ) || isdefined( self.no_charge ) || isdefined( self.forced_user ) )
        return;

    self.auto_open = 1;
    self.no_charge = 1;
    self.zs_free = 1;
}

zs_box_free_remove()
{
    if ( !is_true( self.zs_free ) )
        return;

    self.auto_open = undefined;
    self.no_charge = undefined;
    self.zs_free = 0;
}

zs_box_can_be_free( chest )
{
    if ( zs_fire_sale_on() || zs_flag( "moving_chest_now" ) )
        return 0;

    if ( is_true( chest.hidden ) || is_true( chest._box_open ) )
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

    for (;;)
    {
        wait 0.1;

        if ( !is_true( self.grab_weapon_hint ) && is_true( self.zs_shared ) )
        {
            self.zs_shared = 0;
            self.zs_shared_by = undefined;
        }

        if ( is_true( self.zs_free ) && is_true( self._box_open ) )
        {
            self zs_box_free_remove();
            self thread zs_box_paid_spun();
        }
        else if ( is_true( level.zs_box_paid ) && zs_box_can_be_free( self ) )
            self zs_box_free_apply();
        else
            self zs_box_free_remove();

        sig = zs_box_signature( self );

        if ( !isdefined( self.zs_sig ) || self.zs_sig != sig )
        {
            self.zs_sig = sig;

            if ( isdefined( self.unitrigger_stub ) )
                self.unitrigger_stub maps\mp\zombies\_zm_unitrigger::run_visibility_function_for_all_triggers();
        }
    }
}

/*
    Everything a player near this box could be reading off it, as one
    string: the box's own state, and who nearby is crouched.
*/
zs_box_signature( chest )
{
    sig = "" + is_true( level.zs_box_paid ) + is_true( chest.zs_free ) + is_true( chest.zs_shared ) + is_true( chest.grab_weapon_hint ) + zs_fire_sale_on() + is_true( chest.is_locked );

    if ( !isdefined( chest.unitrigger_stub ) || !isdefined( chest.unitrigger_stub.playertrigger ) || chest.unitrigger_stub.playertrigger.size == 0 )
        return sig;

    players = get_players();

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
    name = level.zs_box_paid_name;
    amount = level.zs_box_paid_amount;
    user = self.chest_user;

    level.zs_box_paid = 0;
    level.zs_box_paid_by = undefined;
    level.zs_box_paid_name = undefined;
    level.zs_box_paid_amount = undefined;

    if ( isdefined( user ) && isdefined( payer ) && user != payer )
    {
        user zs_say( "^3" + name + "^7 paid for this spin" );
        user zs_favour_note( payer );
        payer zs_say( "^3" + user.name + "^7 used the spin you paid for" );
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
    evt = self.zbarrier waittill_any_return( "randomization_done", "box_hacked_respin" );

    if ( evt != "randomization_done" )
        return;

    if ( zs_flag( "moving_chest_now" ) && isdefined( payer ) && isdefined( amount ) )
    {
        zs_refund( payer, amount );
        payer zs_say( "The box moved -- your " + amount + " points came back" );
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
        self sethintstring( "Hold ^3[{+activate}]^7 to take the shared weapon" );
    else if ( mode == "share" )
        self sethintstring( "Hold ^3[{+activate}]^7 to share this weapon" );
    else if ( mode == "pay" )
        self sethintstring( "Hold ^3[{+activate}]^7 to buy a spin for a teammate [Cost: " + chest.zombie_cost + "]" );
    else if ( mode == "take_back" )
        self sethintstring( "Hold ^3[{+activate}]^7 to take back your payment" );
    else if ( mode == "free" && isdefined( self.hint_string ) )
        self sethintstring( self.hint_string, 0 );

    return can_use;
}


/* ==================================================================
    MACHINES

    Every perk machine and Pack-a-Punch gets a pay prompt: one extra use
    trigger, sitting on the machine's own, shown only to a player who is
    crouched and able to pay -- or, while a payment is waiting, only to
    the player who made it. The two ZShare visibility loops below show a
    machine's stock prompt to nobody the pay prompt is shown to, so a
    player never has both in front of them.

    The words on a pay prompt are the same for everyone who can see it,
    which is what lets one trigger serve a whole machine.
   ================================================================== */

zs_machine_updater()
{
    level endon( "end_game" );

    tick = 0;

    for (;;)
    {
        wait 0.1;

        tick++;

        if ( tick % 10 == 1 )
            zs_machines_refresh();

        level.zs_pay_team_ok = zs_pay_team_check();

        for ( i = 0; i < level.zs_perk_machines.size; i++ )
        {
            m = level.zs_perk_machines[i];

            if ( !isdefined( m ) )
                continue;

            m zs_pay_trigger_ensure( "perk" );
            m zs_pay_trigger_sync();

            if ( !is_true( m.zs_vis ) )
                m zs_pay_fallback();

            m zs_perk_hint_maintain();
        }

        for ( i = 0; i < level.zs_pap_machines.size; i++ )
        {
            m = level.zs_pap_machines[i];

            if ( !isdefined( m ) )
                continue;

            m zs_pay_trigger_ensure( "pap" );
            m zs_pay_trigger_sync();

            if ( !is_true( m.zs_vis ) )
                m zs_pay_fallback();

            m zs_pap_price_maintain();
        }
    }
}

/*
    Every stock T6 machine trigger is a zombie_vending trigger, the
    Pack-a-Punch the one whose script_noteworthy is specialty_weapupgrade.
    zombie_vending_upgrade is the older name _zm_perks.gsc still looks
    for, and it is looked for here too so an older map is not missed.
*/
zs_machines_refresh()
{
    perks = [];
    paps = [];

    vend = getentarray( "zombie_vending", "targetname" );

    for ( i = 0; i < vend.size; i++ )
    {
        if ( !zs_is_machine_trigger( vend[i] ) )
            continue;

        if ( vend[i].script_noteworthy == "specialty_weapupgrade" )
            paps = zs_add_unique( paps, vend[i] );
        else
            perks = zs_add_unique( perks, vend[i] );
    }

    more = getentarray( "specialty_weapupgrade", "script_noteworthy" );

    for ( i = 0; i < more.size; i++ )
    {
        if ( zs_is_machine_trigger( more[i] ) )
            paps = zs_add_unique( paps, more[i] );
    }

    old = getentarray( "zombie_vending_upgrade", "targetname" );

    for ( i = 0; i < old.size; i++ )
    {
        if ( zs_is_machine_trigger( old[i] ) )
            paps = zs_add_unique( paps, old[i] );
    }

    level.zs_perk_machines = perks;
    level.zs_pap_machines = paps;
}

zs_is_machine_trigger( ent )
{
    if ( !isdefined( ent ) || !isdefined( ent.script_noteworthy ) || !isdefined( ent.classname ) )
        return 0;

    return issubstr( ent.classname, "trigger" );
}

zs_add_unique( arr, ent )
{
    for ( i = 0; i < arr.size; i++ )
    {
        if ( arr[i] == ent )
            return arr;
    }

    arr[arr.size] = ent;
    return arr;
}

zs_index_of( arr, ent )
{
    for ( i = 0; i < arr.size; i++ )
    {
        if ( isdefined( arr[i] ) && arr[i] == ent )
            return i;
    }

    return -1;
}

/*
    The pay prompt's volume is the stock perk trigger's -- radius 40,
    height 70 -- at the stock trigger's own origin, so the two cover the
    same ground.
*/
zs_pay_trigger_ensure( kind )
{
    if ( isdefined( self.zs_pay_trig ) )
        return;

    t = spawn( "trigger_radius_use", self.origin, 0, 40, 70 );
    t setcursorhint( "HINT_NOICON" );
    t triggerignoreteam();
    t usetriggerrequirelookat();
    t setinvisibletoall();
    t sethintstring( "" );

    t.zs_machine = self;
    t.zs_kind = kind;
    t.zs_hint = "";

    self.zs_pay_trig = t;
    self.zs_kind = kind;
    self.zs_pay_all_hidden = 1;

    t thread zs_pay_think();

    // Its words now, not on the next tick: a prompt with no words is
    // still a prompt, and a press on it would still count.
    self zs_pay_trigger_sync();
}

/*
    Machines move. Die Rise carries perks on elevators, Nuketown drops
    them from the sky, and the stock code parks a trigger ten thousand
    units down while a machine is off or busy. The pay prompt goes
    wherever the stock trigger goes.
*/
zs_pay_trigger_sync()
{
    t = self.zs_pay_trig;

    if ( !isdefined( t ) )
        return;

    if ( t.origin != self.origin )
        t.origin = self.origin;

    want = self zs_pay_hint();

    if ( want != t.zs_hint )
    {
        t sethintstring( want );
        t.zs_hint = want;
    }
}

zs_pay_hint()
{
    if ( is_true( self.zs_paid ) )
        return "Hold ^3[{+activate}]^7 to take back your payment";

    if ( !isdefined( self.cost ) )
        return "";

    if ( self.zs_kind == "pap" )
        return "Hold ^3[{+activate}]^7 to buy a Pack-a-Punch for a teammate [Cost: " + self.cost + "]";

    return "Hold ^3[{+activate}]^7 to buy this perk for a teammate [Cost: " + self.cost + "]";
}

zs_pay_show( player, on )
{
    t = self.zs_pay_trig;

    if ( !isdefined( t ) || !isdefined( player ) )
        return;

    if ( on )
        t setvisibletoplayer( player );
    else
        t setinvisibletoplayer( player );
}

zs_pay_hide_all()
{
    if ( isdefined( self.zs_pay_trig ) )
        self.zs_pay_trig setinvisibletoall();

    self.zs_pay_all_hidden = 1;
}

/*
    For a machine whose visibility loop is not ZShare's -- off, or on a
    map that powered it before ZShare loaded. A perk machine then offers
    the pay prompt only to players who already own that perk: the stock
    loop hides the machine from exactly those players, so the two prompts
    never meet. A Pack-a-Punch offers nothing.
*/
zs_pay_fallback()
{
    if ( self.zs_kind != "perk" || !is_true( self.power_on ) )
    {
        if ( !is_true( self.zs_pay_all_hidden ) )
            self zs_pay_hide_all();

        return;
    }

    self.zs_pay_all_hidden = 0;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
        self zs_pay_show( players[i], self zs_perk_pay_fallback_ok( players[i] ) );
}

zs_pay_think()
{
    level endon( "end_game" );

    for (;;)
    {
        self waittill( "trigger", player );

        machine = self.zs_machine;

        if ( !isdefined( machine ) || !isdefined( player ) || !isplayer( player ) )
            continue;

        zs_load_config();

        if ( self.zs_kind == "pap" )
            machine zs_pap_pay_press( player );
        else
            machine zs_perk_pay_press( player );

        wait 0.3;
    }
}

/*
    Clears the machine's "live" mark when its visibility loop ends --
    power off notifies death on the trigger, and the Pack-a-Punch's loop
    also ends on its own off notify.

    waittill_any_return() rather than waittill_any(): waittill_any() ends
    the calling thread on every notify but the first, so nothing after it
    would run when the second one is what arrived.
*/
zs_vis_watch()
{
    self notify( "zs_vis_watch" );
    self endon( "zs_vis_watch" );

    self waittill_any_return( "death", "Pack_A_Punch_off" );

    self.zs_vis = 0;
    self zs_pay_hide_all();
}


/* ==================================================================
    PERK MACHINES
   ================================================================== */

/*
    check_player_has_perk() from _zm_perks.gsc, with the pay prompt
    folded in. self is a perk machine's trigger, and this runs from the
    moment the machine powers on until it loses power.

    Stock hides the machine from anyone who owns the perk, is standing in
    a revive, holds equipment that blocks buying, or has the hacker out.
    That is all still here, plus one more: anyone the pay prompt is shown
    to. Both are decided for each player in the same pass, so there is
    no frame where a player has both prompts or neither.
*/
zs_perk_visibility( perk )
{
    self endon( "death" );

    self zs_pay_trigger_ensure( "perk" );
    self.zs_vis = 1;
    self.zs_pay_all_hidden = 0;
    self thread zs_vis_watch();

    dist = 16384;

    while ( true )
    {
        players = get_players();

        for ( i = 0; i < players.size; i++ )
        {
            player = players[i];
            pay = self zs_perk_pay_ok( player );
            self zs_pay_show( player, pay );

            if ( distancesquared( player.origin, self.origin ) < dist )
            {
                if ( !pay && !player hasperk( perk ) && !player maps\mp\zombies\_zm_perks::has_perk_paused( perk ) && !player in_revive_trigger() && !is_equipment_that_blocks_purchase( player getcurrentweapon() ) && !player hacker_active() )
                {
                    self setinvisibletoplayer( player, 0 );
                    continue;
                }

                self setinvisibletoplayer( player, 1 );
            }
        }

        wait 0.1;
    }
}

/*
    Whether this player sees the pay prompt at this machine. While a
    payment waits, only its payer does, and a press then takes it back.
*/
zs_perk_pay_ok( player )
{
    if ( !isdefined( player ) || !zs_crouched( player ) )
        return 0;

    if ( is_true( self.is_locked ) )
        return 0;

    if ( is_true( self.zs_paid ) )
        return isdefined( self.zs_paid_by ) && self.zs_paid_by == player && zs_payer_ok( player );

    if ( !level.zs.perk_pay || !is_true( level.zs_pay_team_ok ) || !is_true( level.zs_late_hooked ) )
        return 0;

    if ( !isdefined( self.cost ) || !isdefined( self.script_noteworthy ) )
        return 0;

    return zs_payer_ok( player ) && !zs_whos_who( player );
}

zs_perk_pay_fallback_ok( player )
{
    if ( !is_true( self.power_on ) || !isdefined( self.script_noteworthy ) )
        return 0;

    if ( !isdefined( player ) || !player hasperk( self.script_noteworthy ) )
        return 0;

    return self zs_perk_pay_ok( player );
}

/*
    A press on the pay prompt. The price is what this player would pay to
    drink it themselves -- the persistent double points upgrade halves
    it, exactly as the machine does -- and it is taken the same way the
    machine takes it.
*/
zs_perk_pay_press( player )
{
    if ( is_true( self.zs_vis ) )
        allowed = self zs_perk_pay_ok( player );
    else
        allowed = self zs_perk_pay_fallback_ok( player );

    if ( !allowed )
        return;

    if ( is_true( self.zs_paid ) )
    {
        self zs_perk_take_back( player );
        return;
    }

    perk = self.script_noteworthy;
    cost = self.cost;

    if ( player maps\mp\zombies\_zm_pers_upgrades_functions::is_pers_double_points_active() )
        cost = player maps\mp\zombies\_zm_pers_upgrades_functions::pers_upgrade_double_points_cost( cost );

    if ( player.score < cost )
    {
        self playsound( "evt_perk_deny" );
        player maps\mp\zombies\_zm_audio::create_and_play_dialog( "general", "perk_deny", undefined, 0 );
        player zs_say( "You need " + cost + " points" );
        return;
    }

    before = player.score;
    player maps\mp\zombies\_zm_score::minus_to_player_score( cost, 1 );

    self.zs_paid = 1;
    self.zs_paid_by = player;
    self.zs_paid_name = player.name;
    self.zs_paid_amount = before - player.score;

    self zs_perk_hint_free();
    self.zs_hint_time = gettime();
    self thread maps\mp\zombies\_zm_audio::play_jingle_or_stinger( self.script_label );

    what = zs_perk_name( perk );
    player zs_say( "Paid for " + what + " -- the next teammate to use the machine drinks it free" );
    zs_say_others( player, "^3" + player.name + "^7 paid for " + what + " -- use the machine to drink it free" );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( perk + " paid by " + player.name + ": " + self.zs_paid_amount );
}

zs_perk_take_back( player )
{
    amount = self.zs_paid_amount;
    what = zs_perk_name( self.script_noteworthy );

    self zs_perk_paid_clear();

    zs_refund( player, amount );

    player zs_say( "Took back your payment for " + what );
    zs_say_others( player, "^3" + player.name + "^7 took back their payment for " + what );
    player zs_sound( level.zs.points_sound );
}

zs_perk_paid_clear()
{
    self.zs_paid = 0;
    self.zs_paid_by = undefined;
    self.zs_paid_name = undefined;
    self.zs_paid_amount = undefined;

    if ( self zs_perk_usable() )
        self maps\mp\zombies\_zm_perks::reset_vending_hint_string();
}

/*
    Powered and not locked -- the state in which the machine's prompt is
    its price, rather than "needs power" or a lock.
*/
zs_perk_usable()
{
    if ( is_true( self.is_locked ) )
        return 0;

    return is_true( self.zs_vis ) || is_true( self.power_on );
}

/*
    The machine's own prompt, with the price at zero. reset_vending_hint_string()
    is the stock function Mob of the Dead and Origins use to put a machine's
    prompt back, and it reads the price off the trigger, so the price is set
    to zero for exactly the length of that call. Nothing else reads it in
    between: the purchase loop keeps its own copy.

    A map-registered perk takes its prompt from its registration instead,
    so that one is written directly.
*/
zs_perk_hint_free()
{
    if ( !self zs_perk_usable() )
        return;

    saved = self.cost;
    self.cost = 0;
    self maps\mp\zombies\_zm_perks::reset_vending_hint_string();
    self.cost = saved;

    perk = self.script_noteworthy;

    if ( isdefined( perk ) && isdefined( level._custom_perks ) && isdefined( level._custom_perks[perk] ) && isdefined( level._custom_perks[perk].hint_string ) )
        self sethintstring( level._custom_perks[perk].hint_string, 0 );
}

/*
    Map code puts a machine's prompt back whenever it unlocks or regains
    power -- Brutus, Origins' generators, a power switch. So while a
    drink is paid for, the zero-cost prompt goes back up the moment the
    machine becomes usable, and once a second after that.
*/
zs_perk_hint_maintain()
{
    usable = self zs_perk_usable();

    if ( is_true( self.zs_paid ) && usable )
    {
        if ( !is_true( self.zs_was_usable ) || !isdefined( self.zs_hint_time ) || gettime() - self.zs_hint_time > 1000 )
        {
            self zs_perk_hint_free();
            self.zs_hint_time = gettime();
        }
    }

    self.zs_was_usable = usable;
}

/*
    level.custom_perk_validation. The purchase loop in _zm_perks.gsc asks
    this after its own checks -- down, busy, already owns it -- and before
    it looks at the price. self is the machine's trigger.

    With a drink paid for, this is where it is handed out: the stock
    purchase, line for line, without the charge. The loop is then told
    no, so it charges nothing and carries on waiting.
*/
zs_perk_validation( player )
{
    if ( isdefined( level.zs_perk_validation_prev ) )
    {
        if ( !self [[ level.zs_perk_validation_prev ]]( player ) )
            return 0;
    }

    if ( !is_true( self.zs_paid ) )
        return 1;

    /*
        The validation runs before the stock limit check, so the limit is
        checked here -- and refused the way the stock loop refuses, with
        the drink still paid for.
    */
    if ( player.num_perks >= player get_player_perk_purchase_limit() )
    {
        self playsound( "evt_perk_deny" );
        player maps\mp\zombies\_zm_audio::create_and_play_dialog( "general", "sigh" );
        return 0;
    }

    perk = self.script_noteworthy;
    payer = self.zs_paid_by;
    name = self.zs_paid_name;

    self zs_perk_paid_clear();

    if ( isdefined( payer ) && payer != player )
    {
        player zs_say( "^3" + name + "^7 paid for this one" );
        player zs_favour_note( payer );
        payer zs_say( "^3" + player.name + "^7 drank the " + zs_perk_short( perk ) + " you paid for" );
    }

    playsoundatposition( "evt_bottle_dispense", self.origin );
    player.perk_purchased = perk;
    self thread maps\mp\zombies\_zm_audio::play_jingle_or_stinger( self.script_label );
    self thread maps\mp\zombies\_zm_perks::vending_trigger_post_think( player, perk );

    zs_debug( perk + " drunk free by " + player.name );
    return 0;
}

/*
    Chat lines only. A name never goes on a prompt -- see PROMPTS ON
    PLAYERS -- so this table is free to be English.
*/
zs_perk_name( perk )
{
    short = zs_perk_short( perk );

    if ( short == "perk" )
        return "a perk";

    if ( short == "Electric Cherry" )
        return "an Electric Cherry";

    return "a " + short;
}

zs_perk_short( perk )
{
    if ( !isdefined( perk ) )
        return "perk";

    switch ( perk )
    {
        case "specialty_armorvest":
        case "specialty_armorvest_upgrade":
            return "Jugger-Nog";
        case "specialty_quickrevive":
        case "specialty_quickrevive_upgrade":
            return "Quick Revive";
        case "specialty_fastreload":
        case "specialty_fastreload_upgrade":
            return "Speed Cola";
        case "specialty_rof":
        case "specialty_rof_upgrade":
            return "Double Tap";
        case "specialty_longersprint":
        case "specialty_longersprint_upgrade":
            return "Stamin-Up";
        case "specialty_deadshot":
        case "specialty_deadshot_upgrade":
            return "Deadshot Daiquiri";
        case "specialty_additionalprimaryweapon":
        case "specialty_additionalprimaryweapon_upgrade":
            return "Mule Kick";
        case "specialty_scavenger":
        case "specialty_scavenger_upgrade":
            return "Tombstone Soda";
        case "specialty_finalstand":
        case "specialty_finalstand_upgrade":
            return "Who's Who";
        case "specialty_flakjacket":
        case "specialty_flakjacket_upgrade":
            return "PhD Flopper";
        case "specialty_grenadepulldeath":
        case "specialty_grenadepulldeath_upgrade":
            return "Electric Cherry";
        case "specialty_nomotionsensor":
        case "specialty_nomotionsensor_upgrade":
            return "Vulture Aid";
    }

    return "perk";
}


/* ==================================================================
    PERK LIMIT

    level.get_player_perk_purchase_limit, wrapped. Every place a perk can
    be had asks get_player_perk_purchase_limit(), which asks this: the
    machines, a paid drink, and Origins' Der Wunderfizz. Origins sets its
    own function here to hand out extra slots, and that one is asked
    first, so its extra slots stay on top of whatever base is set.
   ================================================================== */

zs_perk_limit_get()
{
    if ( isdefined( level.zs_perk_limit_prev ) )
        stock = self [[ level.zs_perk_limit_prev ]]();
    else
        stock = level.perk_purchase_limit;

    if ( !isdefined( level.zs ) || level.zs.perk_limit == 0 )
        return stock;

    // No limit. Every perk on the biggest map is well under this.
    if ( level.zs.perk_limit < 0 )
        return 99;

    extra = stock - level.perk_purchase_limit;

    if ( extra < 0 )
        extra = 0;

    return level.zs.perk_limit + extra;
}


/* ==================================================================
    THE PACK-A-PUNCH

    The machine's take loop is one function, wait_for_player_to_take()
    in _zm_perks.gsc, threaded by name each time a weapon comes out.
    ZShare's is the stock loop with a share branch, the way the hacker's
    box re-spin is the stock box with a re-spin branch.

    Its visibility loop is replaced too, for the pay prompt: see
    MACHINES. And its price lives on its trigger, read afresh on every
    press, so a paid pack is the price held at zero until it is used.
   ================================================================== */

/*
    wait_for_player_to_take() from _zm_perks.gsc, as shipped, with the
    share branch in the middle. self is the machine's trigger; player is
    who paid. Anything not marked is Treyarch's and stays as they wrote
    it, so a taken weapon is exactly the weapon the stock machine hands
    out.
*/
zs_pap_take( player, weapon, packa_timer, upgrade_as_attachment )
{
    current_weapon = self.current_weapon;
    upgrade_name = self.upgrade_name;
    upgrade_weapon = upgrade_name;
    self endon( "pap_timeout" );
    level endon( "Pack_A_Punch_off" );

    // ZShare: a fresh window, and the words on the machine follow the stance.
    // The stock switch is put back here too, in case the last window ended
    // with the power rather than with a take or a timeout.
    self.zs_pap_shared = 0;
    self.zs_pap_window = 1;
    zs_pap_anyone( 0 );
    self thread zs_pap_hint_watcher( player );
    self thread zs_pap_window_end();

    while ( true )
    {
        packa_timer playloopsound( "zmb_perks_packa_ticktock" );
        self waittill( "trigger", trigger_player );

        if ( isdefined( level.pap_grab_by_anyone ) && level.pap_grab_by_anyone )
            player = trigger_player;

        packa_timer stoploopsound( 0.05 );

        // ZShare: the branch. Crouched, and it is your weapon: share it.
        if ( zs_pap_share_press( trigger_player, player ) )
        {
            wait 0.05;
            continue;
        }

        // ZShare: once shared, whoever pressed is the taker.
        if ( is_true( self.zs_pap_shared ) && isplayer( trigger_player ) )
            player = trigger_player;

        if ( trigger_player == player )
        {
            player maps\mp\zombies\_zm_stats::increment_client_stat( "pap_weapon_grabbed" );
            player maps\mp\zombies\_zm_stats::increment_player_stat( "pap_weapon_grabbed" );
            current_weapon = player getcurrentweapon();

            if ( is_player_valid( player ) && !( player.is_drinking > 0 ) && !is_placeable_mine( current_weapon ) && !is_equipment( current_weapon ) && level.revive_tool != current_weapon && "none" != current_weapon && !player hacker_active() )
            {
                maps\mp\_demo::bookmark( "zm_player_grabbed_packapunch", gettime(), player );
                self notify( "pap_taken" );
                player notify( "pap_taken" );
                player.pap_used = 1;

                if ( !( isdefined( upgrade_as_attachment ) && upgrade_as_attachment ) )
                    player thread do_player_general_vox( "general", "pap_arm", 15, 100 );
                else
                    player thread do_player_general_vox( "general", "pap_arm2", 15, 100 );

                weapon_limit = get_player_weapon_limit( player );
                player maps\mp\zombies\_zm_weapons::take_fallback_weapon();
                primaries = player getweaponslistprimaries();

                if ( isdefined( primaries ) && primaries.size >= weapon_limit )
                    player maps\mp\zombies\_zm_weapons::weapon_give( upgrade_weapon );
                else
                {
                    player giveweapon( upgrade_weapon, 0, player maps\mp\zombies\_zm_weapons::get_pack_a_punch_weapon_options( upgrade_weapon ) );
                    player givestartammo( upgrade_weapon );
                }

                player switchtoweapon( upgrade_weapon );

                if ( isdefined( player.restore_ammo ) && player.restore_ammo )
                {
                    new_clip = player.restore_clip + ( weaponclipsize( upgrade_weapon ) - player.restore_clip_size );
                    new_stock = player.restore_stock + ( weaponmaxammo( upgrade_weapon ) - player.restore_max );
                    player setweaponammostock( upgrade_weapon, new_stock );
                    player setweaponammoclip( upgrade_weapon, new_clip );
                }

                player.restore_ammo = undefined;
                player.restore_clip = undefined;
                player.restore_stock = undefined;
                player.restore_max = undefined;
                player.restore_clip_size = undefined;
                player maps\mp\zombies\_zm_weapons::play_weapon_vo( upgrade_weapon );
                return;
            }
        }

        wait 0.05;
    }
}

zs_pap_share_press( trigger_player, player )
{
    zs_load_config();

    if ( !level.zs.pap_share )
        return 0;

    if ( is_true( self.zs_pap_shared ) )
        return 0;

    if ( !isdefined( trigger_player ) || !isdefined( player ) || trigger_player != player )
        return 0;

    if ( !zs_crouched( trigger_player ) || zs_whos_who( trigger_player ) )
        return 0;

    self zs_pap_share( player );
    return 1;
}

/*
    Whether this machine has a weapon of this player's waiting. Read by
    the chat word, which has no press to go on.

    With the take loop replaced, the window is exact. Without it, the
    stock fields are the tell: the machine is in use, this player paid,
    and the weapon model is out -- which is also true for the first
    third of a second of the animation, and a share then simply comes
    out shared.
*/
zs_pap_shareable( trig, player )
{
    if ( !isdefined( trig ) || !isdefined( player ) )
        return 0;

    if ( is_true( trig.zs_pap_shared ) )
        return 0;

    if ( !isdefined( trig.pack_player ) || trig.pack_player != player || zs_whos_who( player ) )
        return 0;

    // Not in Grief, for the reason zs_box_shareable() gives.
    if ( !is_true( level.zs_pay_team_ok ) )
        return 0;

    if ( is_true( level.zs_pap_take_hooked ) )
        return is_true( trig.zs_pap_window );

    return isdefined( trig.worldgun ) && zs_flag( "pack_machine_in_use" );
}

/*
    self is the machine's trigger. Clearing pack_player is what the
    visibility loop reads to show the machine to everybody again, and
    pap_grab_by_anyone is the stock loop's own switch -- set as well, so
    a share from chat works on a build where the take loop could not be
    replaced.
*/
zs_pap_share( player )
{
    self.zs_pap_shared = 1;
    self.zs_shared_by = player;
    self.pack_player = undefined;
    self setvisibletoall();
    zs_pap_anyone( 1 );

    zs_say_all( "^3" + player.name + "^7 shared their Pack-a-Punched weapon -- anyone can take it" );
    zs_sound_others( player, level.zs.share_sound );

    // Without the hook there is no window thread; the stock notifies
    // still say when it is over.
    if ( !is_true( level.zs_pap_take_hooked ) )
        self thread zs_pap_window_end();

    zs_debug( "pap shared by " + player.name );
}

/*
    The stock grab-by-anyone switch, and a note that it was this script
    that set it -- so it is only ever put back by the hand that turned
    it on, and another script's setting is left alone.
*/
zs_pap_anyone( on )
{
    if ( on )
    {
        level.pap_grab_by_anyone = 1;
        level.zs_pap_anyone = 1;
        return;
    }

    if ( is_true( level.zs_pap_anyone ) )
    {
        level.pap_grab_by_anyone = 0;
        level.zs_pap_anyone = 0;
    }
}

/*
    Runs for the length of one window and ends with it, whichever way it
    ends. The stock switch is put back so the next customer's weapon is
    theirs alone.

    waittill_any_return(), not waittill_any(): waittill_any() ends the
    thread outright on every notify but its first, so this cleanup would
    only ever have run on a timeout.

    death is in the list for a power cut mid-window. The power system
    sends it to the trigger along with Pack_A_Punch_off, and without it
    the window would stay marked open and the machine would never take a
    payment again.
*/
zs_pap_window_end()
{
    self notify( "zs_pap_window_end" );
    self endon( "zs_pap_window_end" );

    self waittill_any_return( "pap_timeout", "pap_taken", "pap_player_disconnected", "death" );

    self.zs_pap_window = 0;
    self.zs_pap_shared = 0;
    self.zs_shared_by = undefined;
    zs_pap_anyone( 0 );
}

/*
    The words on the machine while a weapon is out: the stock line, the
    share offer while the owner is crouched, or the take line once it is
    shared. Written only when they change.
*/
zs_pap_hint_watcher( player )
{
    self endon( "pap_timeout" );
    self endon( "pap_taken" );
    self endon( "pap_player_disconnected" );
    level endon( "Pack_A_Punch_off" );

    last = "";

    for (;;)
    {
        wait 0.1;

        if ( is_true( self.zs_pap_shared ) )
            want = "shared";
        else if ( level.zs.pap_share && isdefined( player ) && zs_crouched( player ) && !zs_whos_who( player ) )
            want = "share";
        else
            want = "stock";

        if ( want == last )
            continue;

        last = want;

        if ( want == "shared" )
            self sethintstring( "Hold ^3[{+activate}]^7 to take the shared weapon" );
        else if ( want == "share" )
            self sethintstring( "Hold ^3[{+activate}]^7 to share this weapon" );
        else
            self sethintstring( &"ZOMBIE_GET_UPGRADED" );
    }
}

/*
    vending_machine_trigger_think() from _zm_perks.gsc, with the pay
    prompt folded in. Stock shows the machine only to players who could
    pack what they are holding, and only to the player whose weapon is
    inside while it is busy; anyone the pay prompt is shown to is left
    out as well.
*/
zs_pap_visibility()
{
    self endon( "death" );
    self endon( "Pack_A_Punch_off" );

    self zs_pay_trigger_ensure( "pap" );
    self.zs_vis = 1;
    self.zs_pay_all_hidden = 0;
    self thread zs_vis_watch();

    while ( true )
    {
        players = get_players();

        for ( i = 0; i < players.size; i++ )
        {
            player = players[i];
            pay = self zs_pap_pay_ok( player );
            self zs_pay_show( player, pay );

            if ( pay || isdefined( self.pack_player ) && self.pack_player != player || !player maps\mp\zombies\_zm_perks::player_use_can_pack_now() )
            {
                self setinvisibletoplayer( player, 1 );
                continue;
            }

            self setinvisibletoplayer( player, 0 );
        }

        wait 0.1;
    }
}

zs_pap_pay_ok( player )
{
    if ( !isdefined( player ) || !zs_crouched( player ) )
        return 0;

    if ( isdefined( self.pack_player ) || is_true( self.zs_pap_window ) || is_true( self.disabled ) || is_true( level.pap_moving ) )
        return 0;

    if ( is_true( self.zs_paid ) )
        return isdefined( self.zs_paid_by ) && self.zs_paid_by == player && zs_payer_ok( player );

    if ( !level.zs.pap_pay || !is_true( level.zs_pay_team_ok ) || zs_bonfire_on() )
        return 0;

    if ( !isdefined( self.cost ) || self.cost <= 0 )
        return 0;

    return zs_payer_ok( player ) && !zs_whos_who( player );
}

zs_pap_pay_press( player )
{
    if ( !self zs_pap_pay_ok( player ) )
        return;

    if ( is_true( self.zs_paid ) )
    {
        self zs_pap_take_back( player );
        return;
    }

    cost = self.cost;

    if ( player maps\mp\zombies\_zm_pers_upgrades_functions::is_pers_double_points_active() )
        cost = player maps\mp\zombies\_zm_pers_upgrades_functions::pers_upgrade_double_points_cost( cost );

    if ( player.score < cost )
    {
        self playsound( "deny" );

        if ( isdefined( level.custom_pap_deny_vo_func ) )
            player [[ level.custom_pap_deny_vo_func ]]();
        else
            player maps\mp\zombies\_zm_audio::create_and_play_dialog( "general", "perk_deny", undefined, 0 );

        player zs_say( "You need " + cost + " points" );
        return;
    }

    before = player.score;
    player maps\mp\zombies\_zm_score::minus_to_player_score( cost, 1 );

    self.zs_paid = 1;
    self.zs_paid_by = player;
    self.zs_paid_name = player.name;
    self.zs_paid_amount = before - player.score;

    self zs_pap_price_maintain();
    self thread maps\mp\zombies\_zm_audio::play_jingle_or_stinger( "mus_perks_packa_sting" );

    player zs_say( "Paid for the next Pack-a-Punch -- the next teammate to use the machine packs free" );
    zs_say_others( player, "^3" + player.name + "^7 paid for the next Pack-a-Punch -- use the machine to pack free" );
    player zs_sound( level.zs.points_sound );
    zs_sound_others( player, level.zs.share_sound );

    zs_debug( "pap paid by " + player.name + ": " + self.zs_paid_amount );
}

zs_pap_take_back( player )
{
    amount = self.zs_paid_amount;

    self zs_pap_paid_clear();

    zs_refund( player, amount );

    player zs_say( "Took back your payment for the Pack-a-Punch" );
    zs_say_others( player, "^3" + player.name + "^7 took back their payment for the Pack-a-Punch" );
    player zs_sound( level.zs.points_sound );
}

zs_pap_paid_clear()
{
    self.zs_paid = 0;
    self.zs_paid_by = undefined;
    self.zs_paid_name = undefined;
    self.zs_paid_amount = undefined;

    self zs_pap_price_restore();
}

/*
    Keeps the price where a payment wants it. Zero while a pack is paid
    for, the machine is idle and powered, and no bonfire sale is on;
    whatever the stock code set the rest of the time. vending_weapon_upgrade_cost()
    rewrites the price when a bonfire sale starts and ends, so a paid pack
    simply waits the sale out and comes back afterwards.

    A purchase with the price at zero is the payment being used: the
    machine sets pack_player in the same frame it charges, and ZShare sees
    that on its next tick, long before the upgrade is done.
*/
zs_pap_price_maintain()
{
    if ( !is_true( self.zs_paid ) )
    {
        self zs_pap_price_restore();
        return;
    }

    if ( is_true( self.zs_zeroed ) && isdefined( self.pack_player ) )
    {
        self zs_pap_paid_used( self.pack_player );
        return;
    }

    free = is_true( self.zs_vis ) && !isdefined( self.pack_player ) && !is_true( self.zs_pap_window ) && !zs_bonfire_on() && isdefined( self.cost ) && isdefined( self.attachment_cost );

    if ( !free )
    {
        self zs_pap_price_restore();
        return;
    }

    if ( is_true( self.zs_zeroed ) && self.cost == 0 && self.attachment_cost == 0 )
        return;

    if ( self.cost != 0 )
        self.zs_cost_saved = self.cost;

    if ( self.attachment_cost != 0 )
        self.zs_att_saved = self.attachment_cost;

    self.cost = 0;
    self.attachment_cost = 0;
    self.zs_zeroed = 1;
    self zs_pap_hint_price();
}

zs_pap_price_restore()
{
    if ( !is_true( self.zs_zeroed ) )
        return;

    self.zs_zeroed = 0;

    // A bonfire sale that started meanwhile has already written its own
    // price, and that one stands.
    if ( isdefined( self.cost ) && self.cost == 0 && isdefined( self.zs_cost_saved ) )
        self.cost = self.zs_cost_saved;

    if ( isdefined( self.attachment_cost ) && self.attachment_cost == 0 && isdefined( self.zs_att_saved ) )
        self.attachment_cost = self.zs_att_saved;

    if ( is_true( self.zs_vis ) && !isdefined( self.pack_player ) && !is_true( self.zs_pap_window ) && !is_true( self.disabled ) )
        self zs_pap_hint_price();
}

zs_pap_hint_price()
{
    if ( is_true( level.zombiemode_reusing_pack_a_punch ) )
        self sethintstring( &"ZOMBIE_PERK_PACKAPUNCH_ATT", self.cost );
    else
        self sethintstring( &"ZOMBIE_PERK_PACKAPUNCH", self.cost );
}

/*
    A paid pack has just been used.

    On the maps that re-pack, a weapon that is already upgraded costs the
    attachment price instead of the full one. The payment was for a pack,
    so the difference goes back to whoever paid, in the share the two
    prices bear to each other -- which is exact whether or not the payer
    had the double points discount.
*/
zs_pap_paid_used( taker )
{
    payer = self.zs_paid_by;
    name = self.zs_paid_name;
    amount = self.zs_paid_amount;
    full = self.zs_cost_saved;
    part = self.zs_att_saved;

    repack = isdefined( self.current_weapon ) && maps\mp\zombies\_zm_weapons::will_upgrade_weapon_as_attachment( self.current_weapon );

    self zs_pap_paid_clear();

    if ( isdefined( taker ) && isdefined( payer ) && taker != payer )
    {
        taker zs_say( "^3" + name + "^7 paid for this Pack-a-Punch" );
        taker zs_favour_note( payer );
        payer zs_say( "^3" + taker.name + "^7 used the Pack-a-Punch you paid for" );
    }

    if ( repack && isdefined( payer ) && isdefined( amount ) && isdefined( full ) && isdefined( part ) && full > part )
    {
        back = amount - int( amount * part / full );

        if ( back > 0 )
        {
            zs_refund( payer, back );
            payer zs_say( "It was a re-pack -- " + back + " of your points came back" );
            payer zs_sound( level.zs.points_sound );
        }
    }

    zs_debug( "paid pack used" );
}


/* ==================================================================
    THE TIME BOMB

    Buried's time bomb puts the game back the way it was when the bomb
    was set: every player's points, guns and perks, the zombies and the
    doors. Scripts with state of their own hang it on two lists the bomb
    keeps, one called when it saves and one when it restores, each on the
    struct the save lives in. Leroy, the ghosts and the side quest use
    them, and so does ZShare, for payments.

    A payment rewinds with the points that paid for it. Left alone, one
    made after the bomb was set would still be waiting after the bomb had
    handed its payer the points back, and one used since would be gone
    although the drink or the gun it bought had been taken away again.
   ================================================================== */

/*
    What time_bomb_add_custom_func_global_save() and its restore twin do,
    written out. Both live in a script only Buried loads, so this file
    does not call into it.
*/
zs_time_bomb_hook()
{
    if ( !isdefined( level._time_bomb ) || is_true( level.zs_time_bomb_hooked ) )
        return;

    if ( !isdefined( level._time_bomb.custom_funcs_save ) )
        level._time_bomb.custom_funcs_save = [];

    if ( !isdefined( level._time_bomb.custom_funcs_restore ) )
        level._time_bomb.custom_funcs_restore = [];

    level._time_bomb.custom_funcs_save[level._time_bomb.custom_funcs_save.size] = ::zs_time_bomb_save;
    level._time_bomb.custom_funcs_restore[level._time_bomb.custom_funcs_restore.size] = ::zs_time_bomb_restore;

    level.zs_time_bomb_hooked = 1;
    zs_debug( "time bomb: payments hooked" );
}

/*
    self is the struct the bomb keeps with its save. Every payment waiting
    right now, and who made it.
*/
zs_time_bomb_save()
{
    self.zs_box_paid = is_true( level.zs_box_paid );
    self.zs_box_paid_by = level.zs_box_paid_by;
    self.zs_box_paid_name = level.zs_box_paid_name;
    self.zs_box_paid_amount = level.zs_box_paid_amount;

    self.zs_machines = [];
    self.zs_paid_by = [];
    self.zs_paid_name = [];
    self.zs_paid_amount = [];

    self zs_time_bomb_save_machines( level.zs_perk_machines );
    self zs_time_bomb_save_machines( level.zs_pap_machines );

    zs_debug( "time bomb: " + self.zs_machines.size + " paid machine(s) saved" );
}

zs_time_bomb_save_machines( list )
{
    for ( i = 0; i < list.size; i++ )
    {
        m = list[i];

        if ( !isdefined( m ) || !is_true( m.zs_paid ) )
            continue;

        n = self.zs_machines.size;
        self.zs_machines[n] = m;
        self.zs_paid_by[n] = m.zs_paid_by;
        self.zs_paid_name[n] = m.zs_paid_name;
        self.zs_paid_amount[n] = m.zs_paid_amount;
    }
}

/*
    The same struct, handed back when the bomb goes off. The bomb puts
    every player's points back itself, so nothing here refunds or charges
    anybody: a payment that was waiting is waiting again, and one made
    since is gone.
*/
zs_time_bomb_restore()
{
    if ( !isdefined( self.zs_machines ) )
        return;

    self zs_time_bomb_restore_machines( level.zs_perk_machines, "perk" );
    self zs_time_bomb_restore_machines( level.zs_pap_machines, "pap" );

    if ( is_true( self.zs_box_paid ) )
    {
        level.zs_box_paid = 1;
        level.zs_box_paid_by = self.zs_box_paid_by;
        level.zs_box_paid_name = self.zs_box_paid_name;
        level.zs_box_paid_amount = self.zs_box_paid_amount;
    }
    else if ( is_true( level.zs_box_paid ) )
        zs_box_paid_reset();

    zs_debug( "time bomb: payments put back" );
}

zs_time_bomb_restore_machines( list, kind )
{
    for ( i = 0; i < list.size; i++ )
    {
        m = list[i];

        if ( !isdefined( m ) )
            continue;

        n = zs_index_of( self.zs_machines, m );

        if ( n < 0 )
        {
            if ( !is_true( m.zs_paid ) )
                continue;

            if ( kind == "pap" )
                m zs_pap_paid_clear();
            else
                m zs_perk_paid_clear();

            continue;
        }

        m.zs_paid = 1;
        m.zs_paid_by = self.zs_paid_by[n];
        m.zs_paid_name = self.zs_paid_name[n];
        m.zs_paid_amount = self.zs_paid_amount[n];

        // The Pack-a-Punch's price follows on the updater's next tick.
        if ( kind == "perk" )
        {
            m zs_perk_hint_free();
            m.zs_hint_time = gettime();
        }
    }
}


/* ==================================================================
    PRESENTATION
   ================================================================== */

zs_say( txt )
{
    if ( !level.zs.messages || !isdefined( self ) )
        return;

    self iprintln( txt );
}

zs_say_all( txt )
{
    if ( !level.zs.messages )
        return;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( isdefined( players[i] ) )
            players[i] iprintln( txt );
    }
}

zs_say_others( except, txt )
{
    if ( !level.zs.messages )
        return;

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( isdefined( except ) && players[i] == except )
            continue;

        players[i] iprintln( txt );
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

    players = get_players();

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( isdefined( except ) && players[i] == except )
            continue;

        players[i] playlocalsound( alias );
    }
}

zs_deny( why )
{
    self zs_say( why );
    self zs_sound( level.zs.deny_sound );
}

zs_debug( txt )
{
    if ( !is_true( level.zs.debug ) )
        return;

    println( "ZShare: " + txt );

    players = get_players();

    if ( players.size > 0 && isdefined( players[0] ) )
        players[0] iprintln( "^5[zs]^7 " + txt );
}

zs_game_ready()
{
    if ( is_true( level.gameended ) )
        return 0;

    if ( is_true( level.intermission ) )
        return 0;

    return isdefined( level.round_number );
}


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
    return "1.5";
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

    mod.reload_config = ::zs_api_reload_config;
    mod.get_stock_perk_limit = ::zs_api_stock_perk_limit;
    mod.get_effective_perk_limit = ::zs_api_effective_perk_limit;
}

/*
    Read the settings again -- for a mod that has just written one of
    ZShare's dvars and wants it to count now rather than at the next
    press. 1 when there was something to read.
*/
zs_api_reload_config()
{
    if ( !is_true( level.zs_loaded ) || !isdefined( level.zs ) || !level.zs.enabled )
        return 0;

    zs_load_config();
    return 1;
}

/*
    The limit the map would give this player if ZShare were not here: the
    callback ZShare kept before installing its own, which on Origins is
    Origins' own and includes the slots the dig hands out.
*/
zs_api_stock_perk_limit( player )
{
    if ( !isdefined( player ) )
        return 0;

    if ( isdefined( level.zs_perk_limit_prev ) )
        return player [[ level.zs_perk_limit_prev ]]();

    if ( isdefined( level.perk_purchase_limit ) )
        return level.perk_purchase_limit;

    return 0;
}

/*
    And the limit ZShare is actually holding the map to, map bonuses and
    all -- the same number every machine gets when it asks. Where ZShare's
    override is not installed, which is zs_enabled 0 and the moments before
    the hook goes on, the honest answer is the map's own.
*/
zs_api_effective_perk_limit( player )
{
    if ( !isdefined( player ) )
        return 0;

    if ( !is_true( level.zs_late_hooked ) || !isdefined( level.zs ) )
        return zs_api_stock_perk_limit( player );

    return player zs_perk_limit_get();
}


/* ==================================================================
    BUILD STAMP

    A development build says so on screen: its version and the time it
    was built, top right, under Plutonium's own watermark -- and under
    ZPause's, since the two are built to run side by side. Release
    builds carry an empty stamp and draw nothing.
   ================================================================== */

/*
    Written by tools/build.py. The line between the markers is generated --
    a version and a build time on a development build, an empty string on
    a release. Do not edit it by hand; the next build will overwrite it.
*/
zs_build()
{
    // ZS_BUILD_BEGIN
    return "";
    // ZS_BUILD_END
}

/*
    Hands the value straight back, so it can wrap a return. Silent unless
    zs_config_printer() has the echo on.
*/
zs_cfg_echo( dvar, value, def )
{
    if ( !is_true( level.zs_cfg_echo ) )
        return value;

    println( "  " + dvar + "  " + value );

    // On screen, only what somebody actually changed. The defaults are
    // in the README.
    if ( isdefined( level.zs_cfg_host ) && value != ( "" + def ) )
        level.zs_cfg_host iprintln( "^3" + dvar + "^7  " + value );

    return value;
}

/*
    Picks up a dvar changed mid-game. Every press re-reads the config
    already; this is for the values the prompts read continuously --
    zs_points_amount is on the prompt itself.
*/
zs_config_watcher()
{
    level endon( "end_game" );

    for (;;)
    {
        wait 5;
        zs_load_config();
    }
}

/*
    "set zs_config_print 1" in the console prints every setting and the
    value it is currently holding, then puts the switch back.
*/
zs_config_printer()
{
    level endon( "end_game" );

    if ( getdvar( "zs_config_print" ) == "" )
        setdvar( "zs_config_print", "0" );

    for ( ;; )
    {
        wait 1;

        if ( getdvar( "zs_config_print" ) != "1" )
            continue;

        setdvar( "zs_config_print", "0" );

        println( "---- ZShare settings ----" );

        level.zs_cfg_host = undefined;
        zs_cfg_players = get_players();

        if ( zs_cfg_players.size > 0 )
            level.zs_cfg_host = zs_cfg_players[0];

        if ( isdefined( level.zs_cfg_host ) )
            level.zs_cfg_host iprintln( "^3[ZShare]^7 settings changed from default:" );

        level.zs_cfg_echo = 1;
        zs_load_config();
        level.zs_cfg_echo = 0;

        if ( isdefined( level.zs_cfg_host ) )
            level.zs_cfg_host iprintln( "^3[ZShare]^7 end of settings" );

        level.zs_cfg_host = undefined;
        println( "---- end ----" );
    }
}

zs_build_watermark()
{
    level endon( "end_game" );

    stamp = zs_build();

    if ( stamp == "" )
        return;

    // Nothing can be drawn before the game is actually up.
    while ( !zs_game_ready() )
        wait 0.5;

    if ( isdefined( level.zs_build_hud ) )
        return;

    /*
        Scale 1.1, and not the 0.9 a watermark looks like it wants: a font
        scale below 1 does not shrink the text on this engine, it falls
        back to something several times larger.

        One line below the corner, because ZPause's stamp sits in the
        corner itself and a test session usually has both running.
    */
    e = createserverfontstring( "objective", 1.1 );
    e setpoint( "TOPRIGHT", "TOPRIGHT", 0, 26 );
    e.color = ( 0.55, 0.85, 1 );
    e.sort = 1000;
    e.foreground = 1;
    e.glowcolor = ( 0, 0, 0 );
    e.glowalpha = 0.55;

    /*
        Set outright rather than faded in. fadeovertime() animates on the
        game's own clock, and in a session with ZPause running that clock is
        the one thing another mod can stop: a pause taken in the moments
        after a match starts holds the fade wherever it got to, and nothing
        ever fades it again. T5 and T4 always set it outright and never had
        it. Nothing about a stamp needs an animation.
    */
    e.alpha = 0.7;
    e settext( stamp + "  [" + zs_origin() + "]" );

    level.zs_build_hud = e;
}
