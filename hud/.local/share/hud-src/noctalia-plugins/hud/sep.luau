--!nonstrict
-- Hairline divider between readouts inside a bar panel.
function update()
  noctalia.setUpdateInterval(600000)
  barWidget.render(ui.box({ width = 1, height = 12, fill = "outline_variant" }))
end
