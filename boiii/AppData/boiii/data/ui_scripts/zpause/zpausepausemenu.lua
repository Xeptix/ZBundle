-- ZPause: the game's own pause menu, told to the server.
--
-- zp_pause_menu. Opening Black Ops III's in-game menu presses pause, and
-- closing it presses resume -- so stepping into the menu stops the game for
-- everybody, or, with zp_personal_pause on, takes only that player out of it.
--
-- Black Ops III does not tell a script when a player opens a menu, so this
-- sends it: Engine.SendMenuResponse() is how the game's own menus already talk
-- to a running match -- the leave-game popup sends ( "popup_leavegame",
-- "endround" ) and the restart one ( "restartgamepopup", "restart_level_zm" ).
-- ZPause sends its own under the menu name "zpause", which nothing in the
-- game's scripts reads, and zpause.gsc waits on "menuresponse" for it.
--
-- Unlike the settings menu beside this file, this one belongs to a match
-- rather than to the frontend, which is why zpausesettings.lua asks for it
-- above its own frontend guard: the in-game HUD loads the same require list
-- the frontend does (ui_mp/t6/hud.lua requires ui.T7.Utility.CoDUtilityRequire
-- as it loads), and on BOIII and T7x the settings file *is* the ui_script.
--
-- Every route but the t7-compiler's carries it. The Workshop build has it in
-- core_mod, which loads in every mode; BOIII, Ezz BOIII and T7x load it from
-- ui_scripts, which the client runs in a match as well as in the frontend. An
-- injected script reaches a stock client that loads no Lua at all.
--
-- The menu wrapped is LUI.createMenu.StartMenu_Main, which does not exist yet
-- when this file is read -- the HUD requires its menus a moment later -- so
-- the wrap is tried from a timer until it takes, the way Z.Hook() does for the
-- lobby button.

CoD.ZPausePauseMenu = {}

local Z = CoD.ZPausePauseMenu

-- The menu name the responses arrive under, and what they say.
Z.MENU = "zpause"
Z.OPENED = "pause_menu_open"
Z.CLOSED = "pause_menu_closed"
Z.ALIVE = "pause_menu_alive"

-- Whether this controller has an open reported, so a close is only sent
-- against one and a second open changes nothing.
Z.open = {}

-- The menu itself, while it is up. Kept because something else has to be able
-- to close it: the shared PAUSE GAME row leaves the game's own pause before
-- ZPause takes over, and that row is drawn by whichever mod owns the list --
-- which hands its action a controller and nothing else.
Z.menus = {}

Z.Send = function ( controller, what )
	if controller == nil or controller < 0 then
		return
	end
	Engine.SendMenuResponse( controller, Z.MENU, what )
end

-- A game the engine pauses by itself -- a solo one -- is left alone. Pausing
-- on top of that would leave the player a countdown every time they closed the
-- menu. Engine.CanPauseGame() is the test the game's own code uses before it
-- touches cl_paused, and it answers before the menu is built, where reading
-- cl_paused would still be false.
Z.EnginePauses = function ()
	local ok, can = pcall( Engine.CanPauseGame )
	return ok and can == true
end

Z.Opened = function ( controller )
	if Z.open[controller + 1] then
		return
	end
	if Z.EnginePauses() then
		return
	end

	Z.open[controller + 1] = true
	Z.Send( controller, Z.OPENED )
end

-- Out of the game's own pause, which is what RESUME GAME does, asked for
-- from somewhere else. StartMenuGoBack is the game's own: it clears cl_paused
-- where the engine pauses the game at all, takes the menu down and forgets
-- its saved state. The list's own resume row hands it the menu, which is why
-- the menu is what is kept above.
Z.Close = function ( controller )
	if controller == nil or controller < 0 then
		return false
	end
	local menu = Z.menus[controller + 1]
	if menu == nil then
		return false
	end
	return pcall( StartMenuGoBack, menu, controller ) == true
end

Z.Closed = function ( controller )
	Z.menus[controller + 1] = nil
	if not Z.open[controller + 1] then
		return
	end

	Z.open[controller + 1] = nil
	Z.Send( controller, Z.CLOSED )
end

-- zp_pause_menu 2 follows the room's menus: the game is paused while any of
-- them is open and comes back when the last one closes. A close the script
-- never hears would hold the match for the rest of its life, so the menu
-- says it is still there and the script drops a player whose beat stopped.
-- Half a second is well inside the few seconds the script waits, and is
-- nothing beside what the menu already sends.
--
-- The timer goes on the menu, so it stops being when the menu does and
-- there is nothing to take down by hand. It is not disposable, so it
-- resets itself rather than leaving an element behind on every pass. A
-- solo game never gets here: Z.Opened leaves the engine's own pause alone
-- and never sets Z.open.
Z.Beat = function ( menu, controller )
	local ok, timer = pcall( LUI.UITimer.newElementTimer, 500, false, function ()
		if Z.open[controller + 1] then
			Z.Send( controller, Z.ALIVE )
		end
	end )
	if ok and timer ~= nil then
		pcall( menu.addElement, menu, timer )
	end
end

-- StartMenu_Main is the in-game pause menu, and the frontend's start menu as
-- well, so the match is what is tested rather than the menu's name. Its own
-- pages -- options, the tabs, the social popup -- open over it and leave it
-- open, so its close is the player going back to the game and nothing else.
--
-- The close override wraps the one startmenu_main.lua puts on the menu itself,
-- which is why it goes on the instance the menu function hands back rather
-- than on the class.
Z.Hook = function ()
	if Z.hooked then
		return true
	end
	if LUI.createMenu == nil or LUI.createMenu.StartMenu_Main == nil then
		return false
	end
	Z.hooked = true

	local startMenu = LUI.createMenu.StartMenu_Main
	LUI.createMenu.StartMenu_Main = function ( controller )
		local menu = startMenu( controller )
		if menu ~= nil and CoD.isZombie == true and Engine.IsInGame() then
			Z.menus[controller + 1] = menu
			Z.Opened( controller )
			Z.Beat( menu, controller )
			LUI.OverrideFunction_CallOriginalSecond( menu, "close", function ( element )
				Z.Closed( controller )
			end )
		end
		return menu
	end
	return true
end

-- Once a second until the menu exists, and then no more: each timer is
-- disposable and only a pass that found nothing asks for another, so nothing
-- accumulates. A minute is far longer than the HUD takes to require its menus
-- -- three seconds on the maps that wait at all -- and gives up rather than
-- looking for the rest of the match.
Z.Wait = function ( parent, tries )
	parent:addElement( LUI.UITimer.newElementTimer( 1000, true, function ()
		if Z.Hook() or tries >= 60 then
			return
		end
		Z.Wait( parent, tries + 1 )
	end ) )
end

Z.Hook()
if not Z.hooked and LUI.roots ~= nil and LUI.roots.UIRootFull ~= nil then
	Z.Wait( LUI.roots.UIRootFull, 0 )
end
