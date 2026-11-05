--!nonstrict
local common = require("./common.luau")

function update()
  noctalia.setUpdateInterval(60000)
  local path = common.dir .. "/barcode.png"
  if not noctalia.fileExists(path) then
    common.missing()
    return
  end
  barWidget.render(ui.image({ path = path, width = 46, height = 12, fit = "stretch" }))
end
