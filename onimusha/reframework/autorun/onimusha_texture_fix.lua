-- Onimusha: Way of the Sword - texture budget fix 0.2.0
--
-- Two settings of the game's texture streamer (via.render.StreamingManager) are held:
--
--  * VramBudgetLimitResolution, a limit on texture resolution. The game raises it when it
--    runs short of VRAM (3, 4 and 5 were seen; 5 came with blurry textures on a spoofed
--    4 GB card). The script does not let it go above your maximum (default 3).
--  * UsableVRAMSize, the texture budget. It is raised to your minimum when the game's own
--    value is lower. This alone did not fix the blur on low-VRAM cards.
--
-- Panel: REFramework menu (Insert) -> "Texture budget fix".
-- Settings: reframework/data/OnimushaTextureFix.json
-- Report:   reframework/data/OnimushaTextureReport.txt

local VERSION = "0.2.0"
local CONFIG = "OnimushaTextureFix.json"
local REPORT = "OnimushaTextureReport.txt"
local MIB = 1048576
local RESERVE_MIB = 1536 -- never push the budget closer than this to the VRAM the renderer reports

local SM = "via.render.StreamingManager"
local SRM = "via.render.StreamingResourceManager"
local RENDERER = "via.render.Renderer"

local cfg = { enabled = true, floor_mb = 2048, exact = false, res_fix = true, res_max = 3 }
do
    local ok, loaded = pcall(json.load_file, CONFIG)
    if ok and type(loaded) == "table" then
        if type(loaded.enabled) == "boolean" then cfg.enabled = loaded.enabled end
        if type(loaded.floor_mb) == "number" then cfg.floor_mb = math.max(64, math.min(16384, loaded.floor_mb)) end
        if type(loaded.exact) == "boolean" then cfg.exact = loaded.exact end
        if type(loaded.res_fix) == "boolean" then cfg.res_fix = loaded.res_fix end
        if type(loaded.res_max) == "number" then cfg.res_max = math.max(0, math.min(8, math.floor(loaded.res_max))) end
    end
end
local function save() pcall(json.dump_file, CONFIG, cfg) end

local cache = {}
local function resolve(name)
    local c = cache[name]
    if c and c.inst then return c end
    local td = sdk.find_type_definition(name)
    local ok, inst = pcall(sdk.get_native_singleton, name)
    c = { td = td, inst = ok and inst or nil }
    cache[name] = c
    return c
end

local function call(name, m, ...)
    local c = resolve(name)
    if not (c.td and c.inst) then return false, "no instance" end
    return pcall(sdk.call_native_func, c.inst, c.td, m, ...)
end

local function num(name, m)
    local ok, v = call(name, m)
    if ok and type(v) == "number" then return v end
    return nil
end

-- RenderConfig is left out on purpose: reading it caused access violations in the game.
local diag_list = {
    { SM, "get_UsableVRAMSize" }, { SM, "get_UsedVRAMSize" }, { SM, "get_VramBudgetLimitResolution" },
    { SM, "get_StreamingBufferMarginSize" }, { SM, "get_UsedTextureCount" },
    { SM, "get_RegisteredStreamingTextureCount" },
    { SRM, "get_VRAMGuardSize" }, { SRM, "get_MeshStreamingBudgetSize" }, { SRM, "get_UsedMeshStreamingSize" },
    { RENDERER, "get_VramSize64" }, { RENDERER, "get_UsedVramSize64" },
}

local diag_rows = {}
local function read_diag()
    diag_rows = {}
    for _, e in ipairs(diag_list) do
        local v = num(e[1], e[2])
        diag_rows[#diag_rows + 1] = { e[1]:gsub("^via%.render%.", ""), e[2], v }
    end
end

local res_game, res_written, res_applied = nil, nil, 0

local report_msg = ""
local function save_report()
    read_diag()
    local lines = {
        "Onimusha texture budget fix " .. VERSION,
        os.date("%Y-%m-%d %H:%M:%S"),
        "tdb: " .. tostring(select(2, pcall(function() return sdk.get_tdb_version() end))),
        "settings: enabled=" .. tostring(cfg.enabled) .. " floor_mb=" .. cfg.floor_mb .. " exact=" .. tostring(cfg.exact)
            .. " res_fix=" .. tostring(cfg.res_fix) .. " res_max=" .. cfg.res_max,
        "game's own resolution limit: " .. tostring(res_game),
        "",
    }
    for _, r in ipairs(diag_rows) do
        local n = r[3]
        local extra = (n and n >= 1000000) and string.format("  (%.0f MiB)", n / MIB) or ""
        lines[#lines + 1] = r[1] .. "  " .. r[2] .. " = " .. tostring(n or "n/a") .. extra
    end
    local f = io.open(REPORT, "w")
    if f then
        f:write(table.concat(lines, "\n") .. "\n")
        f:close()
        report_msg = "Saved reframework/data/" .. REPORT .. " (" .. os.date("%H:%M:%S") .. ")"
    else
        report_msg = "Could not write the report file"
    end
end

local raises, last_raise = 0, ""
local last_t, shown = 0, {}
local capped = false

local function hold_budget()
    local cur = num(SM, "get_UsableVRAMSize")
    if not cur then return end
    local want = math.floor(cfg.floor_mb) * MIB
    -- Safety: keep a reserve free on cards with little VRAM. The game's own value always wins.
    local total = num(RENDERER, "get_VramSize64")
    capped = false
    if total and total > 0 then
        local cap = total - RESERVE_MIB * MIB
        if want > cap then want = math.max(cap, cur); capped = true end
    end
    if (cfg.exact and cur ~= want) or cur < want then
        if call(SM, "set_UsableVRAMSize", want) then
            raises = raises + 1
            last_raise = string.format("%s: %.0f -> %.0f MiB", os.date("%H:%M:%S"), cur / MIB, want / MIB)
        end
    end
end

-- Keeps the limit at min(game's value, maximum); gives the game's value back when switched off.
local function hold_resolution()
    local rv = num(SM, "get_VramBudgetLimitResolution")
    if not rv then return nil end
    if rv ~= res_written then res_game, res_written = rv, nil end
    local want = res_game
    if cfg.enabled and cfg.res_fix then want = math.min(res_game, cfg.res_max) end
    if rv ~= want and call(SM, "set_VramBudgetLimitResolution", want) then
        res_written = (want ~= res_game) and want or nil
        res_applied = res_applied + 1
        return want
    end
    return rv
end

re.on_frame(function()
    if cfg.enabled then hold_budget() end
    local res = hold_resolution()

    local now = os.clock()
    if now - last_t < 1.0 then return end
    last_t = now
    shown = {
        usable = num(SM, "get_UsableVRAMSize"),
        used = num(SM, "get_UsedVRAMSize"),
        tex = num(SM, "get_UsedTextureCount"),
        total = num(RENDERER, "get_VramSize64"),
        total_used = num(RENDERER, "get_UsedVramSize64"),
        res = res,
    }
end)

local function mib(v) return v and string.format("%.0f MiB", v / MIB) or "?" end

re.on_draw_ui(function()
    if imgui.tree_node("Texture budget fix") then
        local ch, v = imgui.checkbox("Enabled", cfg.enabled)
        if ch then cfg.enabled = v; save() end
        imgui.separator()

        local c4, rf = imgui.checkbox("Fix blurry textures (limit)", cfg.res_fix)
        if c4 then cfg.res_fix = rf; save() end
        imgui.text("Highest resolution limit allowed")
        local c5, rm = imgui.slider_int("##res", cfg.res_max, 0, 8)
        if c5 then cfg.res_max = rm; save() end
        imgui.text("Lower is sharper. Default 3.")
        imgui.separator()

        imgui.text("Minimum texture budget (MiB)")
        local c2, nv = imgui.slider_int("##floor", cfg.floor_mb, 64, 8192)
        if c2 then cfg.floor_mb = nv; save() end
        local c3, ev = imgui.checkbox("Set exactly (can lower)", cfg.exact)
        if c3 then cfg.exact = ev; save() end
        imgui.text("Testing only. Leave off.")
        imgui.separator()

        imgui.text("Resolution limit now:  " .. tostring(shown.res))
        imgui.text("Game's own limit:  " .. tostring(res_game))
        imgui.text("Budget now:  " .. mib(shown.usable))
        imgui.text("Textures use:  " .. mib(shown.used))
        imgui.text("Textures loaded:  " .. tostring(shown.tex))
        imgui.text("Renderer VRAM:  " .. mib(shown.total))
        imgui.text("Renderer uses:  " .. mib(shown.total_used))
        if capped then imgui.text("Budget limited by your VRAM") end
        imgui.text("Budget raised:  " .. raises .. " times")
        imgui.text("Limit lowered:  " .. res_applied .. " times")
        if last_raise ~= "" then imgui.text("Last:  " .. last_raise) end

        imgui.separator()
        if imgui.button("Save report") then save_report() end
        if report_msg ~= "" then imgui.text(report_msg) end

        if imgui.tree_node("Diagnostics (read-only)") then
            if imgui.button("Refresh") then read_diag() end
            for _, r in ipairs(diag_rows) do imgui.text(r[1] .. "  " .. r[2] .. " = " .. tostring(r[3] or "n/a")) end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
end)
