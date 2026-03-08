return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  lazy = true,
  dependencies = { { "nvim-lua/plenary.nvim" } },


  config = function()
    local harpoon = require("harpoon")
    harpoon:setup({})

    -- basic telescope configuration
    local conf = require("telescope.config").values
    local function toggle_telescope(harpoon_files)
      local file_paths = {}
      for _, item in ipairs(harpoon_files.items) do
        table.insert(file_paths, item.value)
      end

      require("telescope.pickers")
          .new({}, {
            prompt_title = "Harpoon",
            finder = require("telescope.finders").new_table({
              results = file_paths,
            }),
            previewer = false,
            sorter = conf.generic_sorter({}),
            layout_strategy = "center",
            layout_config = {
              preview_cutoff = 1,
              width = function(_, max_columns, _)
                return math.min(max_columns, 80)
              end,
              height = function(_, _, max_lines)
                return math.min(max_lines, 15)
              end,
            },
            borderchars = {
              prompt = { "─", "│", " ", "│", "╭", "╮", "│", "│" },
              results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
              preview = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
            },
            attach_mappings = function(prompt_buffer_number, map)
              -- The keymap you need
              map("i", "<c-d>", function()
                local state = require("telescope.actions.state")
                local selected_entry = state.get_selected_entry()
                local current_picker = state.get_current_picker(prompt_buffer_number)

                -- This is the line you need to remove the entry
                harpoon:list():remove(selected_entry)
                current_picker:refresh(make_finder())
              end)

              return true
            end,
          })
          :find()
    end

    vim.keymap.set("n", "<C-e>", function() toggle_telescope(harpoon:list()) end,
      { desc = "Open harpoon window" })

    vim.keymap.set("n", "<leader>h", function() harpoon:list():add() end)


    -- Toggle previous & next buffers stored within Harpoon list
    vim.keymap.set("n", "<C-S-O>", function() harpoon:list():prev() end)
    vim.keymap.set("n", "<C-S-P>", function() harpoon:list():next() end)
  end
}
