-- Onimusha: Way of the Sword - texture budget fix 0.1.0
--
-- The game gives its texture streamer a fixed budget (StreamingManager.UsableVRAMSize)
-- that depends on the Texture Quality preset. When the textures in view need more than
-- that, the engine drops detail and they turn blurry. This script keeps the budget at or
-- above a minimum you choose. The game's own value is only ever raised, never lowered
-- (unless you tick "Set exactly").
--
-- Panel: REFramework menu (Insert) -> "Texture budget fix".
-- Settings are saved to reframework/data/OnimushaTextureFix.json.

local CONFIG = "OnimushaTextureFix.json"
local MIB = 1048576
local RESERVE_MIB = 1536 -- never push the budget closer than this to the VRAM the renderer reports

local SM = "via.render.StreamingManager"
local RENDERER = "via.render.Renderer"

local cfg = { enabled = true, floor_mb = 2048, exact = false }
do
    local ok, loaded = pcall(json.load_file, CONFIG)
    if ok and type(loaded) == "table" then
        if type(loaded.enabled) == "boolean" then cfg.enabled = loaded.enabled end
        if type(loaded.floor_mb) == "number" then cfg.floor_mb = math.max(64, math.min(16384, loaded.floor_mb)) end
        if type(loaded.exact) == "boolean" then cfg.exact = loaded.exact end
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

local raises, last_raise = 0, ""
local last_t, shown = 0, {}
local capped = false

re.on_frame(function()
    if cfg.enabled then
        local cur = num(SM, "get_UsableVRAMSize")
        if cur then
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
    end

    local now = os.clock()
    if now - last_t < 1.0 then return end
    last_t = now
    shown = {
        usable = num(SM, "get_UsableVRAMSize"),
        used = num(SM, "get_UsedVRAMSize"),
        tex = num(SM, "get_UsedTextureCount"),
        total = num(RENDERER, "get_VramSize64"),
    }
end)

local function mib(v) return v and string.format("%.0f MiB", v / MIB) or "?" end

re.on_draw_ui(function()
    if imgui.tree_node("Texture budget fix") then
        local ch, v = imgui.checkbox("Enabled", cfg.enabled)
        if ch then cfg.enabled = v; save() end
        imgui.text("Minimum texture budget (MiB)")
        local c2, nv = imgui.slider_int("##floor", cfg.floor_mb, 64, 8192)
        if c2 then cfg.floor_mb = nv; save() end
        local c3, ev = imgui.checkbox("Set exactly (can lower)", cfg.exact)
        if c3 then cfg.exact = ev; save() end
        imgui.text("Off: only raises the game's budget.")
        imgui.text("On: forces this value, up or down.")
        imgui.separator()
        imgui.text("Budget now:  " .. mib(shown.usable))
        imgui.text("Used:  " .. mib(shown.used))
        imgui.text("Textures loaded:  " .. tostring(shown.tex))
        imgui.text("Renderer VRAM:  " .. mib(shown.total))
        if capped then imgui.text("Limited by your VRAM (keeps " .. RESERVE_MIB .. " MiB free)") end
        imgui.text("Times raised:  " .. raises)
        if last_raise ~= "" then imgui.text("Last:  " .. last_raise) end
        imgui.tree_pop()
    end
end)
