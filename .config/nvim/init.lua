-- FIX: Auto-create undo directory to prevent E828 error
local undodir = vim.fn.stdpath("state") .. "/undo"
if vim.fn.isdirectory(undodir) == 0 then
  vim.fn.mkdir(undodir, "p")
end
vim.opt.undodir = undodir
vim.opt.undofile = true

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = 'a'
vim.opt.clipboard = 'unnamedplus'
vim.opt.breakindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.signcolumn = 'yes'

-- Leaders must be set BEFORE lazy.nvim loads
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ==========================================================================
-- PLUGIN MANAGER (LAZY.NVIM) BOOTSTRAP
-- ==========================================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Define all plugins required by this configuration
require("lazy").setup({
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  "nvim-lualine/lualine.nvim",
  "nvim-tree/nvim-web-devicons",
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  { "lukas-reineke/indent-blankline.nvim", main = "ibl" },
  "lewis6991/gitsigns.nvim",
  "windwp/nvim-autopairs",
  "numToStr/Comment.nvim",
  "folke/which-key.nvim",
  "nvim-tree/nvim-tree.lua",
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
  "nvim-telescope/telescope-ui-select.nvim",
  "akinsho/bufferline.nvim",
  "hrsh7th/nvim-cmp",
  "hrsh7th/cmp-nvim-lsp",
  "hrsh7th/cmp-buffer",
  "hrsh7th/cmp-path",
  "L3MON4D3/LuaSnip",
  "saadparwaiz1/cmp_luasnip",
  "rafamadriz/friendly-snippets",
  "neovim/nvim-lspconfig",
})

-- ==========================================================================
-- DYNAMIC THEME LOGIC
-- ==========================================================================
_G.reload_matugen_colors = function()
  -- vim.schedule ensures this massive UI update runs safely on the main event loop
  vim.schedule(function()
    -- FIX: Prevent warning on first lazy.nvim run before Catppuccin is downloaded
    local check_cat_installed = pcall(require, "catppuccin")
    if not check_cat_installed then
      return
    end

    local matugen_path = vim.fn.stdpath("config") .. "/matugen_colors.lua"
    local overrides = {}
    
    if vim.fn.filereadable(matugen_path) == 1 then
      local chunk = loadfile(matugen_path)
      if chunk then
        local colors = chunk()
        if type(colors) == "table" then
          overrides = { all = colors, mocha = colors }
        end
      end
    end

    -- FIX: Only clear catppuccin. Do NOT clear lualine, or it will leak highlight groups!
    for k, _ in pairs(package.loaded) do
      if k:match("^catppuccin") then
        package.loaded[k] = nil
      end
    end

    -- Nuke Neovim's existing highlights
    vim.cmd("hi clear")
    if vim.fn.exists("syntax_on") then
      vim.cmd("syntax reset")
    end
    vim.g.colors_name = nil

    local ok_cat, cat = pcall(require, "catppuccin")
    if ok_cat then
      cat.setup({
        flavour = "mocha",
        compile = { enabled = false }, -- MUST be false for dynamic overrides
        color_overrides = overrides,
        integrations = {
          cmp = true,
          gitsigns = true,
          nvimtree = true,
          treesitter = true,
          bufferline = true, 
          telescope = { enabled = true },
          indent_blankline = { enabled = true },
          native_lsp = {
            enabled = true,
            underlines = {
              errors = { "undercurl" },
              hints = { "undercurl" },
              warnings = { "undercurl" },
              information = { "undercurl" },
            },
          },
        },
      })
      vim.cmd("colorscheme catppuccin")
    end
    
    -- Reload lualine dynamically safely
    local ok_lualine, lualine = pcall(require, "lualine")
    if ok_lualine then
      lualine.setup { options = { theme = 'catppuccin' } }
    end
    
    -- Force Neovim to redraw
    vim.cmd("redraw!")

    -- Provide visual confirmation
    vim.notify("Matugen colors reloaded!", vim.log.levels.INFO)
  end)
end

-- Initialize the colors immediately on startup
_G.reload_matugen_colors()

-- ==========================================================================
-- PLUGIN CONFIGURATIONS (Wrapped in pcall to prevent hard crashes)
-- ==========================================================================
local ok_ts, ts_configs = pcall(require, 'nvim-treesitter.configs')
if ok_ts then
  ts_configs.setup {
    highlight = { enable = true },
    indent = { enable = true },
  }
end

local ok_ibl, ibl = pcall(require, "ibl")
if ok_ibl then ibl.setup() end

local ok_git, gitsigns = pcall(require, 'gitsigns')
if ok_git then gitsigns.setup() end

local ok_pairs, autopairs = pcall(require, 'nvim-autopairs')
if ok_pairs then autopairs.setup({}) end

local ok_com, comment = pcall(require, 'Comment')
if ok_com then comment.setup() end

local ok_wk, whichkey = pcall(require, 'which-key')
if ok_wk then whichkey.setup() end

local ok_tree, nvim_tree = pcall(require, "nvim-tree")
if ok_tree then
  nvim_tree.setup({
    filters = { dotfiles = false },
    view = { width = 30 }
  })
end
vim.keymap.set('n', '<C-n>', ':NvimTreeToggle<CR>', { desc = 'Toggle File Explorer' })

local ok_telescope, telescope = pcall(require, 'telescope')
if ok_telescope then
  telescope.setup {
    extensions = {
      ["ui-select"] = { require("telescope.themes").get_dropdown {} }
    }
  }
  pcall(telescope.load_extension, 'ui-select')

  local ok_builtin, builtin = pcall(require, 'telescope.builtin')
  if ok_builtin then
    vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find Files' })
    vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Live Grep' })
    vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Find Buffers' })
  end
end

local ok_bufferline, bufferline = pcall(require, "bufferline")
if ok_bufferline then
  bufferline.setup{
    options = {
      mode = "buffers",
      diagnostics = "nvim_lsp",
      separator_style = "slant",
      offsets = {
        {
          filetype = "NvimTree",
          text = "File Explorer",
          text_align = "left",
          separator = true
        }
      },
    }
  }
end
vim.keymap.set("n", "<Tab>", ":BufferLineCycleNext<CR>", { silent = true })
vim.keymap.set("n", "<S-Tab>", ":BufferLineCyclePrev<CR>", { silent = true })
vim.keymap.set("n", "<leader>x", ":bdelete<CR>", { silent = true, desc = "Close Buffer" })

local ok_cmp, cmp = pcall(require, 'cmp')
local ok_luasnip, luasnip = pcall(require, 'luasnip')
if ok_cmp and ok_luasnip then
  pcall(function() require("luasnip.loaders.from_vscode").lazy_load() end)

  cmp.setup {
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
    mapping = cmp.mapping.preset.insert {
      ['<C-n>'] = cmp.mapping.select_next_item(),
      ['<C-p>'] = cmp.mapping.select_prev_item(),
      ['<C-d>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<CR>'] = cmp.mapping.confirm {
        behavior = cmp.ConfirmBehavior.Replace,
        select = true,
      },
      ['<Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        else
          fallback()
        end
      end, { 'i', 's' }),
    },
    sources = {
      { name = 'nvim_lsp' },
      { name = 'luasnip' },
      { name = 'buffer' },
      { name = 'path' },
    },
  }
end

-- ==========================================================================
-- LSP NATIVE SETUP
-- ==========================================================================
local capabilities = vim.lsp.protocol.make_client_capabilities()
local ok_cmp_lsp, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
if ok_cmp_lsp then
  capabilities = cmp_nvim_lsp.default_capabilities()
end
 
local function setup_server(server_name, config)
  local ok, server_config = pcall(require, "lspconfig.server_configurations." .. server_name)
  if not ok then return end
  
  local default_config = server_config.default_config
  local final_config = vim.tbl_deep_extend("force", default_config, config or {})
  final_config.capabilities = vim.tbl_deep_extend("force", final_config.capabilities or {}, capabilities)

  vim.api.nvim_create_autocmd("FileType", {
     pattern = final_config.filetypes,
     callback = function(args)
    local instance_config = vim.tbl_deep_extend("force", {}, final_config)
    local root_dir = final_config.root_dir
    if type(root_dir) == "function" then
        root_dir = root_dir(args.file)
        end
        instance_config.root_dir = root_dir or vim.fs.dirname(args.file)

        vim.lsp.start(instance_config)
     end,
  })
end

setup_server("pyright", {})
setup_server("nil_ls", {})
setup_server("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = 'LuaJIT' },
      globals = { 'vim' },
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  }
})

-- ==========================================================================
-- ASYNC DIRECTORY WATCHER FOR DYNAMIC RELOADING
-- ==========================================================================
local uv = vim.uv or vim.loop
local config_dir = vim.fn.stdpath("config")
local reload_timer = uv.new_timer()

local watcher = uv.new_fs_event()
if watcher then
  -- We watch the entire config directory to avoid inode replacement breaking the watcher
  watcher:start(config_dir, {}, vim.schedule_wrap(function(err, filename, events)
    if not err and filename == "matugen_colors.lua" then
      
      -- Debounce the events to catch both Matugen's write and our sed modification
      reload_timer:stop()
      reload_timer:start(250, 0, vim.schedule_wrap(function()
        _G.reload_matugen_colors()
      end))
      
    end
  end))
end
