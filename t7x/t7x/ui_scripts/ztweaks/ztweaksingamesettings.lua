-- ZTweaks settings from BO3's in-game pause menu.
--
-- Both entry points intentionally use the shared builder in
-- ztweakssettings.lua so the two menus always have feature parity. Define the
-- page even in the frontend: T7x can retain Lua modules across the transition
-- into a match, so a frontend-only early return permanently hid this popup.

local Z = CoD.ZTweaksSettings

LUI.createMenu.ZTweaksInGameSettings = function ( controller )
	Z.Startup( controller )
	return Z.CreateMenu( controller, "ZTweaksInGameSettings" )
end
