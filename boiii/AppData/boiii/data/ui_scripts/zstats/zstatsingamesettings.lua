-- ZStats settings from BO3's in-game pause menu.
--
-- Both entry points intentionally use the shared builder in
-- zstatssettings.lua so the two menus always have feature parity. Define the
-- page even in the frontend: T7x can retain Lua modules across the transition
-- into a match, so a frontend-only early return permanently hid this popup.

local Z = CoD.ZStatsSettings

LUI.createMenu.ZStatsInGameSettings = function ( controller )
	Z.Startup( controller )
	return Z.CreateMenu( controller, "ZStatsInGameSettings" )
end
