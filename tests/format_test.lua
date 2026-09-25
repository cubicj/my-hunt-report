local Format = require("MyHuntReport.Format")

local T = {}

function T.integerGroupsThousands()
    assert(Format.integer(0) == "0")
    assert(Format.integer(999) == "999")
    assert(Format.integer(12345) == "12,345", Format.integer(12345))
    assert(Format.integer(1234567.8) == "1,234,568")
end

function T.percentOneDecimal()
    assert(Format.percent(0.4567) == "45.7%", Format.percent(0.4567))
    assert(Format.percent(1) == "100.0%")
    assert(Format.percent(0) == "0.0%")
    assert(Format.percent(nil) == "0.0%")
end

function T.tinyPositiveSharesRemainVisible()
    for _, share in ipairs({ 0.0004, 0.000015, 0.0004999 }) do
        assert(Format.percent(share) == "<0.1%", Format.percent(share))
    end
    assert(Format.percent(0.0005) == "0.1%")
    assert(Format.percent(0.001) == "0.1%")
    assert(Format.percent(0.002) == "0.2%")
end

function T.durationMinutesAndHours()
    assert(Format.duration(754) == "12:34", Format.duration(754))
    assert(Format.duration(3723) == "1:02:03", Format.duration(3723))
    assert(Format.duration(5) == "0:05")
    assert(Format.duration(-3) == "0:00")
end

function T.clockFormatsEpoch()
    local text = Format.clock(os.time({ year = 2026, month = 9, day = 23, hour = 21, min = 5 }))
    assert(text == "2026-09-23 21:05", text)
end

function T.decimalAndRateHandleNil()
    assert(Format.decimal(nil, 1) == "-")
    assert(Format.decimal(12.345, 1) == "12.3")
    assert(Format.decimal(7, 0) == "7")
    assert(Format.rate(nil) == "-")
    assert(Format.rate(0.256) == "25.6%")
end

return T
