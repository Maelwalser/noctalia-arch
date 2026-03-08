return {
  "vinnymeller/swagger-preview.nvim",
  run = "npm install -g swagger-ui-watcher",
  lazy = true,
  config = function ()
    require("swagger-preview").setup({
    -- The port to run the preview server on
    port = 8000,
    -- The host to run the preview server on
    host = "localhost",
    })
  end
}
