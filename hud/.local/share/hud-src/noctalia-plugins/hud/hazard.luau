--!nonstrict
-- Crawling hazard tape: hud-build renders the stripe pattern shifted by one step
-- per frame; cycling them makes the tape scroll. How fast follows the data
-- coming onto the machine: bytes written to disk plus bytes downloaded. It
-- crawls while the machine is quiet and runs during a download or a big copy.
-- On hover the tape glows and the tooltip gives the two rates.
local common = require("./common.luau")

local IDLE_MS = 240 -- frame time with nothing moving
-- Frame time at HIGH or more. Not faster: every frame is a bar redraw for the
-- compositor, and the tape runs fastest just when the machine is busiest.
local FAST_MS = 60
-- The speed follows the rate on a log scale, so a fast copy does not look the
-- same as a ten times slower one. LOW sits above what an idle desktop writes
-- by itself (logs, browser profiles: up to about 1 MB/s measured here).
local LOW = 1024 * 1024 -- bytes/s below which the tape stays at its idle crawl
local HIGH = 128 * 1024 * 1024 -- bytes/s at which it runs flat out
local SAMPLE_MS = 1000 -- how often the disk counters are read
-- Share of the way the speed moves to its target per frame. Writes reach the
-- disk in bursts (page cache flushes), so it falls slower than it rises.
local RISE = 0.25
local FALL = 0.06
local SECTOR = 512 -- /proc/diskstats counts in 512-byte sectors whatever the device

local frame = 0
local frames = common.countFrames("hazard")
local speed = 0 -- 0 idle .. 1 flat out, as drawn
local diskRate = 0 -- bytes/s written, from the last two samples
local written = nil -- sectors written at the last sample
local sinceSample = SAMPLE_MS -- ms, summed from the frame times
local wholeDisk = {} -- device name -> whether it counts
local hovered = false

-- Whole physical disks only: partitions repeat their disk's writes, and so do
-- device-mapper and md volumes stacked on one; zram and loop are not storage.
local function counts(name)
  if wholeDisk[name] == nil then
    local stacked = string.match(name, "^dm%-") or string.match(name, "^md")
      or string.match(name, "^loop") or string.match(name, "^zram") or string.match(name, "^ram")
    wholeDisk[name] = not stacked and noctalia.fileExists("/sys/block/" .. name)
  end
  return wholeDisk[name]
end

local function sectorsWritten()
  local stats = noctalia.readFile("/proc/diskstats")
  if not stats then
    return nil
  end
  local total = 0
  for line in string.gmatch(stats, "[^\n]+") do
    -- major minor name reads merged sectors ms writes merged sectors-written
    local name, sectors = string.match(line, "^%s*%d+%s+%d+%s+(%S+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
    if name and counts(name) then
      total += tonumber(sectors)
    end
  end
  return total
end

local function sampleDisk(elapsedMs)
  local now = sectorsWritten()
  if now and written and now >= written then
    diskRate = (now - written) * SECTOR * 1000 / elapsedMs
  else
    diskRate = 0
  end
  written = now
end

local function human(rate)
  if rate >= 1024 * 1024 * 1024 then
    return string.format("%.1f GB/s", rate / (1024 * 1024 * 1024))
  elseif rate >= 1024 * 1024 then
    return string.format("%.1f MB/s", rate / (1024 * 1024))
  end
  return string.format("%.0f kB/s", rate / 1024)
end

-- Frame time for the current data rate; eases `speed` one step towards it.
local function frameTime()
  local s = noctalia.systemStats() -- nil while [system.monitor] is off
  local netRate = s and s.net and s.net.rxBytesPerSec
  if sinceSample >= SAMPLE_MS then
    sampleDisk(sinceSample)
    sinceSample = 0
    -- Only shown while the pointer is on the tape; a new text every sample
    -- keeps it current for as long as it rests there.
    common.tip(string.format("Disk write %s\nDownload %s", human(diskRate), if netRate then human(netRate) else "--"))
  end
  local rate = diskRate + (netRate or 0)
  local target = math.clamp(math.log(math.max(rate, 1) / LOW) / math.log(HIGH / LOW), 0, 1)
  speed += (target - speed) * (if target > speed then RISE else FALL)
  local ms = math.floor(IDLE_MS * (FAST_MS / IDLE_MS) ^ speed + 0.5)
  sinceSample += ms
  return ms
end

local function draw()
  local path = common.framePath("hazard", frame)
  -- A rebuild swaps the frame directory: skip a tick rather than render a gap.
  if frames == 0 or not noctalia.fileExists(path) then
    return
  end
  local length = noctalia.getConfig("length") or 56
  barWidget.render(common.bare({
    common.glow(hovered, function()
      return ui.image({ path = path, width = length, height = 10, fit = "stretch" })
    end),
  }))
end

function onHover(inside)
  hovered = inside
  common.hover(inside)
  draw()
end

function update()
  local animate = noctalia.getConfig("animate") ~= false
  if frames == 0 then
    -- hud-build may not have run yet when the bar starts: keep checking.
    frames = common.countFrames("hazard")
    if frames == 0 then
      common.missing()
      noctalia.setUpdateInterval(5000)
      return
    end
  end
  if animate then
    noctalia.setUpdateInterval(frameTime())
    frame = (frame + 1) % frames
  else
    noctalia.setUpdateInterval(60000)
  end
  draw()
end
