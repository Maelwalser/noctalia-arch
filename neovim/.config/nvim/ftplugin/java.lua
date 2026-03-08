-- Get the jdtls module
local status_ok, jdtls = pcall(require, "jdtls")
if not status_ok then
    vim.notify("nvim-jdtls not found", vim.log.levels.ERROR)
    return
end

-- Define paths (Linux-specific)
local home = os.getenv('HOME')
if not home then
    vim.notify("HOME environment variable not set.", vim.log.levels.ERROR)
    return
end

local mason_path = vim.fn.stdpath('data') .. '/mason'

local capabilities = vim.lsp.protocol.make_client_capabilities()
local cmp_lsp_status_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if cmp_lsp_status_ok then
    capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

-- Function to find root directory
local function get_root_dir()
    local root_markers = { '.git', 'mvnw', 'gradlew', 'pom.xml', 'build.gradle', 'build.gradle.kts','settings.gradle' }
    local root_dir = jdtls.setup.find_root(root_markers)

    if not root_dir then
        vim.notify("Could not find Java project root. Using current directory.", vim.log.levels.WARN)
        root_dir = vim.fn.getcwd()
    end

    return root_dir
end

local root_dir = get_root_dir()

-- All the paths we need for jdtls
local project_name = vim.fn.fnamemodify(root_dir, ':p:h:t')
local workspace_dir = home .. '/.cache/jdtls-workspace/' .. project_name
local jdtls_path = mason_path .. '/packages/jdtls'

local java_debug_path = mason_path ..
    '/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar'
local java_test_path = mason_path .. '/packages/java-test/extension/server'

local bundles = {}

-- Add java-debug-adapter jar if it exists
local debug_jar = vim.fn.glob(java_debug_path .. '/extension/server/com.microsoft.java.debug.plugin-*.jar', true)
if debug_jar ~= '' then
    table.insert(bundles, debug_jar)
end

-- Add java-test jars if they exist
local test_jars = vim.split(vim.fn.glob(java_test_path .. '/extension/server/*.jar', true), '\n')
for _, jar in ipairs(test_jars) do
    if jar ~= '' then
        table.insert(bundles, jar)
    end
end

-- jdtls configuration
local config = {
    cmd = {
        'java',
        '-Declipse.application=org.eclipse.jdt.ls.core.id1',
        '-Dosgi.bundles.defaultStartLevel=4',
        '-Declipse.product=org.eclipse.jdt.ls.core.product',
        '-Dlog.protocol=true',
        '-Dlog.level=WARN',
        '-Xmx1g',
        '-javaagent:' .. jdtls_path .. '/lombok.jar',
        '-jar',
        vim.fn.glob(jdtls_path .. '/plugins/org.eclipse.equinox.launcher_*.jar'),
        '-configuration',
        jdtls_path .. '/config_linux',
        '-data',
        workspace_dir
    },
    root_dir = root_dir,
    capabilities = capabilities,
    settings = {
        java = {
            eclipse = {
                downloadSources = true,
            },
            maven = {
                downloadSources = true,
            },
            implementationsCodeLens = {
                enabled = true,
            },
            referencesCodeLens = {
                enabled = true,
            },
            references = {
                includeDecompiledSources = true,
            },
            signatureHelp = { enabled = true },
            contentProvider = { preferred = 'fernflower' },
            completion = {
                favoriteStaticMembers = {
                    "org.hamcrest.MatcherAssert.assertThat",
                    "org.hamcrest.Matchers.*",
                    "org.junit.jupiter.api.Assertions.*",
                    "java.util.Objects.requireNonNull",
                    "java.util.Objects.requireNonNullElse",
                    "org.mockito.Mockito.*"
                }
            },
            sources = {
                organizeImports = {
                    starThreshold = 9999,
                    staticStarThreshold = 9999,
                },
            },
            codeGeneration = {
                toString = {
                    template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
                },
                useBlocks = true,
            },
            -- Spring Boot support
            ['spring-boot'] = {
                support = true,
            },
        }
    },
    flags = {
        allow_incremental_sync = true,
    },
    init_options = {
        bundles = bundles,
    },
    on_attach = function(client, bufnr)
        -- Keymaps for LSP actions
        local opts = { buffer = bufnr, noremap = true, silent = true }
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
        vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
        vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
        vim.keymap.set('n', '<leader>wl', function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, opts)
        vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format { async = true } end, opts)

        -- This is where your code actions are enabled!
        vim.keymap.set('n', '<leader>ga', vim.lsp.buf.code_action, opts)
        vim.keymap.set('v', '<leader>ga', vim.lsp.buf.code_action, opts)

        vim.keymap.set('n', '<leader>gr', vim.lsp.buf.references, opts)
        vim.keymap.set('n', '<leader>rr', vim.lsp.buf.rename, opts)

        -- Setup DAP for debugging
        jdtls.setup_dap({ hotcodereplace = 'auto' })
    end,
}

-- Start jdtls with the configuration
jdtls.start_or_attach(config)
