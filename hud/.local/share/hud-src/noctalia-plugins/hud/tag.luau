--!nonstrict
-- Panel tag: the acid notch that opens a bar panel, echoing the overlay's
-- section headers.
function update()
  noctalia.setUpdateInterval(600000)
  barWidget.render(ui.box({ width = 3, height = 14, fill = "primary" }))
end
