return {
    {
        -- Main LSP Configuration
        "neovim/nvim-lspconfig",
        dependencies = {
            -- Automatically install LSPs and related tools to stdpath for Neovim
            { "williamboman/mason.nvim", config = true }, -- NOTE: Must be loaded before dependants
            "williamboman/mason-lspconfig.nvim",
            "WhoIsSethDaniel/mason-tool-installer.nvim",

            -- Useful status updates for LSP.
            -- LSP and notify updates in the down right corner
            {
                "j-hui/fidget.nvim",
                opts = {
                    notification = {
                        override_vim_notify = true,
                    },
                },
            },

            -- Allows extra capabilities provided by nvim-cmp
            "saghen/blink.cmp",
        },
        config = function()
            -- Brief aside: **What is LSP?**
            --
            -- LSP is an initialism you've probably heard, but might not understand what it is.
            --
            -- LSP stands for Language Server Protocol. It's a protocol that helps editors
            -- and language tooling communicate in a standardized fashion.
            --
            -- In general, you have a "server" which is some tool built to understand a particular
            -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
            -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
            -- processes that communicate with some "client" - in this case, Neovim!
            --
            -- LSP provides Neovim with features like:
            --  - Go to definition
            --  - Find references
            --  - Autocompletion
            --  - Symbol Search
            --  - and more!
            --
            -- Thus, Language Servers are external tools that must be installed separately from
            -- Neovim. This is where `mason` and related plugins come into play.
            --
            -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
            -- and elegantly composed help section, `:help lsp-vs-treesitter`

            --  This function gets run when an LSP attaches to a particular buffer.
            --    That is to say, every time a new file is opened that is associated with
            --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
            --    function will be executed to configure the current buffer
            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
                callback = function(event)
                    -- The following two autocommands are used to highlight references of the
                    -- word under your cursor when your cursor rests there for a little while.
                    --    See `:help CursorHold` for information about when this is executed
                    --
                    -- When you move your cursor, the highlights will be cleared (the second autocommand).
                    local client = vim.lsp.get_client_by_id(event.data.client_id)
                    if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
                        local highlight_augroup = vim.api.nvim_create_augroup("kickstart-lsp-highlight",
                            { clear = false })
                        vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.document_highlight,
                        })

                        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.clear_references,
                        })

                        vim.api.nvim_create_autocmd("LspDetach", {
                            group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
                            callback = function(event2)
                                vim.lsp.buf.clear_references()
                                vim.api.nvim_clear_autocmds({ group = "kickstart-lsp-highlight", buffer = event2.buf })
                            end,
                        })
                    end

                    -- The following code creates a keymap to toggle inlay hints in your
                    -- code, if the language server you are using supports them
                    --
                    -- This may be unwanted, since they displace some of your code
                    if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
                        vim.keymap.set("n", "<leader>uh", function()
                            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
                        end, { desc = "Toggle [U]i Inlay [H]ints" })
                    end
                end,
            })

            -- Make hover window have borders
            local floating_border_style = "rounded"

            vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
                border = floating_border_style,
            })

            vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
                border = floating_border_style,
            })

            vim.diagnostic.config({
                float = { border = floating_border_style },
            })

            -- Show window/showMessage requests using vim.notify instead of logging to messages
            vim.lsp.handlers["window/showMessage"] = function(_, params, ctx)
                local message_type = params.type
                local message = params.message
                local client_id = ctx.client_id
                local client = vim.lsp.get_client_by_id(client_id)
                local client_name = client and client.name or string.format("id=%d", client_id)
                if not client then
                    vim.notify("LSP[" .. client_name .. "] client has shut down after sending " .. message,
                        vim.log.levels.ERROR)
                end
                if message_type == vim.lsp.protocol.MessageType.Error then
                    vim.notify("LSP[" .. client_name .. "] " .. message, vim.log.levels.ERROR)
                else
                    message = ("LSP[%s][%s] %s\n"):format(client_name, vim.lsp.protocol.MessageType[message_type],
                        message)
                    vim.notify(message, vim.log.levels[message_type])
                end
                return params
            end

            -- Change diagnostic symbols in the sign column (gutter)
            local signs = { ERROR = "", WARN = "", INFO = "", HINT = "" }
            local diagnostic_signs = {}
            for type, icon in pairs(signs) do
                diagnostic_signs[vim.diagnostic.severity[type]] = icon
            end
            vim.diagnostic.config({ signs = { text = diagnostic_signs } })

            -- LSP servers and clients are able to communicate to each other what features they support.
            --  By default, Neovim doesn't support everything that is in the LSP specification.
            --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
            --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            local blink_capabilities = require("blink.cmp").get_lsp_capabilities()
            capabilities = vim.tbl_deep_extend("force", capabilities, blink_capabilities)

            -- Enable the following language servers
            --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
            --
            --  Add any additional override configuration in the following tables. Available keys are:
            --  - cmd (table): Override the default command used to start the server
            --  - filetypes (table): Override the default list of associated filetypes for the server
            --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
            --  - settings (table): Override the default settings passed when initializing the server.
            --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
            local servers = {
                -- clangd = {},
                -- gopls = {},
                -- pyright = {},
                -- rust_analyzer = {},
                -- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
                --
                -- Some languages (like typescript) have entire language plugins that can be useful:
                --    https://github.com/pmizio/typescript-tools.nvim
                --
                -- But for many setups, the LSP (`ts_ls`) will work just fine
                -- ts_ls = {},
                --

                lua_ls = {
                    -- cmd = { ... },
                    -- filetypes = { ... },
                    -- capabilities = {},
                    settings = {
                        Lua = {
                            completion = {
                                callSnippet = "Replace",
                            },
                            -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
                            diagnostics = { disable = { "missing-fields" } },
                        },
                    },
                },
                -- Markdown
                marksman = {},
                -- TypeScript, JavaScript
                ts_ls = {},
                -- TOML
                taplo = {},
                -- PHP
                -- intelephense = {},
                phpactor = {},
                -- Bash/Shell
                shellcheck = {},
                bashls = {},
                -- Docker
                dockerls = {},
                docker_compose_language_service = {},
                -- Helm
                helm_ls = {},
                yamlls = {
                    -- FIXME: yamlls produces a lot of false positives for helm files
                    -- due to template syntax at the moment. It is loaded nevertheless.
                    -- Therefore we need to ensure it is not attached for those files
                    filetypes = { "yaml" },
                    on_attach = function(client, bufnr)
                        local patterns = { "*/templates/*.yaml", "*/templates/*.tpl", "values.yaml", "Chart.yaml" }
                        local fname = vim.fn.expand("%:p")
                        for _, pattern in ipairs(patterns) do
                            local lua_pattern = pattern:gsub("*", ".*"):gsub("/", "/.*")
                            if fname:match(lua_pattern) then
                                vim.lsp.buf_detach_client(bufnr, client.id)
                                return
                            end
                        end
                    end,
                },
                tsserver = {
                    on_attach = function(client)
                        -- this is important, otherwise tsserver will format ts/js
                        -- files which we *really* don't want.
                        client.server_capabilities.documentFormattingProvider = false
                    end,
                },
                biome = {},

                -- Rust
                -- Handled by rustacean.vim
                -- rust_analyzer = {},
            }

            -- Ensure the servers and tools above are installed
            --  To check the current status of installed tools and/or manually install
            --  other tools, you can run
            --    :Mason
            --
            --  You can press `g?` for help in this menu.
            require("mason").setup()

            -- You can add other tools here that you want Mason to install
            -- for you, so that they are available from within Neovim.
            local ensure_installed = vim.tbl_keys(servers or {})
            vim.list_extend(ensure_installed, {
                "stylua",    -- Used to format Lua code
                "prettierd", -- Used to format JavaScript/TypeScript code
            })

            require("mason-tool-installer").setup({
                ensure_installed = ensure_installed,
            })

            require("mason-lspconfig").setup({
                handlers = {
                    function(server_name)
                        local server = servers[server_name] or {}
                        -- This handles overriding only values explicitly passed
                        -- by the server configuration above. Useful when disabling
                        -- certain features of an LSP (for example, turning off formatting for ts_ls)
                        server.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
                        require("lspconfig")[server_name].setup(server)
                    end,
                },
                ensure_installed = {},
                automatic_installation = true,
            })
        end,
    },
    -- LSP Plugins
    {
        -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
        -- used for completion, annotations and signatures of Neovim apis
        "folke/lazydev.nvim",
        ft = "lua",
        opts = {
            library = {
                -- Load luvit types when the `vim.uv` word is found
                { path = "luvit-meta/library", words = { "vim%.uv" } },
            },
        },
    },
    {
        "jose-elias-alvarez/null-ls.nvim",
        opts = function(_, opts)
            local nls = require("null-ls").builtins
            opts.sources = vim.list_extend(opts.sources or {}, {
                nls.formatting.biome,

                -- or if you like to live dangerously like me:
                nls.formatting.biome.with({
                    args = {
                        'check',
                        '--apply-unsafe',
                        '--formatter-enabled=true',
                        '--organize-imports-enabled=true',
                        '--skip-errors',
                        '$FILENAME',
                    },
                }),
            })
        end,
    },
    -- Rustacean vim for all our Rust needs
    -- INFO: We can't install rust-analyzer via Mason, as this will conflict with
    -- rustaceanvim. Therefore ensure it is installed manually for example using
    -- rustup and available in the path. This has the added benefit, of having
    -- the rust-analyzer in the version fitting our current rust installation:
    --
    -- ```shell
    -- rustup component add rust-analyzer
    -- ```
    {
        "mrcjkb/rustaceanvim",
        version = "^5", -- Recommended
        lazy = false,   -- This plugin is already lazy
        config = function()
            vim.g.rustaceanvim = {
                tools = {
                    float_win_config = {
                        border = "rounded",
                    },
                },
            }
        end,
    },
}
