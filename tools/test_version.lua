-- The version the addon reports (2026-09-25: "we need to be tracking
-- versioning somehow").
--
-- The TOC says `## Version: @project-version@` and the release packager
-- rewrites that to the tag it builds, which starts with a "v". The addon shows
-- the version with its own "v" in front, so it must drop the tag's or players
-- read "vv0.2.0". Straight from the repository the keyword arrives untouched,
-- and that is a dev build, not a version.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("version")

--- Load the addon with the TOC's Version field reading `value`.
local function LoadWith(value)
    _G.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            if field == "Version" then return value end
        end,
    }
    local ns = env.Load()
    _G.C_AddOns = nil
    return ns
end

local ns = LoadWith("v0.2.0")
suite.check("a tag loses its v", ns.VERSION == "0.2.0", ns.VERSION)
suite.check("and is shown with one", ns.VersionLabel() == "v0.2.0", ns.VersionLabel())

ns = LoadWith("v0.3.0-beta1")
suite.check("a beta tag keeps its suffix", ns.VERSION == "0.3.0-beta1", ns.VERSION)

ns = LoadWith("0.2.1")
suite.check("a bare version is kept", ns.VERSION == "0.2.1", ns.VERSION)

ns = LoadWith("@project-version@")
suite.check("an unpackaged checkout is a dev build", ns.VERSION == "dev", ns.VERSION)
suite.check("and says so", ns.VersionLabel() == "dev build", ns.VersionLabel())

ns = LoadWith(nil)
suite.check("no version at all", ns.VERSION == "0.0.0", ns.VERSION)

suite.done()
