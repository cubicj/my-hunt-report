package.path = "./reframework/autorun/?.lua;./tests/?.lua;" .. package.path

local stubs = require("stubs")
stubs.install()

local SUITES = {
    "log_test",
    "game_test",
    "settings_test",
    "hotkey_test",
    "locale_test",
    "format_test",
    "theme_test",
    "draw_test",
    "fonts_test",
    "history_test",
    "session_test",
    "skillstate_test",
    "skillextras_test",
    "healtracker_test",
    "procs_test",
    "shelltracker_test",
    "hitcapture_test",
    "quest_test",
    "motionnames_test",
    "names_test",
    "pulse_test",
    "reportwindow_test",
    "settingspanel_test",
    "entry_test",
}

local passed, failed = 0, 0

for _, suiteName in ipairs(SUITES) do
    local okLoad, suite = pcall(require, suiteName)
    if not okLoad then
        failed = failed + 1
        print("LOAD FAIL " .. suiteName .. ": " .. tostring(suite))
    else
        local names = {}
        for name in pairs(suite) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            stubs.reset()
            local okTest, err = pcall(suite[name])
            if okTest then
                passed = passed + 1
            else
                failed = failed + 1
                print("FAIL " .. suiteName .. "." .. name .. ": " .. tostring(err))
            end
        end
    end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
