-- gardener.nvim: manages tree-sitter parsers on nvim-treesitter's main branch.
--
-- Installs the parsers in ensure_installed and, if auto_install is set, the
-- parser of any filetype that is opened; registers custom parsers and keeps
-- them registered across nvim-treesitter updates; maps filetypes to
-- languages; and starts highlighting, and optionally folds and indentation,
-- in every buffer whose parser is installed. See README.md for the options.
--
-- ensure_installed forms:
-- 1) list: { "lua", "python", "json" }
-- 2) map from language to filetypes: { qmljs = { "qml", "qmljs" } }

local M = {}

---@class GardenerOpts
local default_opts = {
	ensure_installed = {},
	custom_parsers = {},
	never_install = {},
	ignore_filetypes = {},
	auto_install = true,
	manage_folds = false,
	manage_indent = false,
	silent = false,
}

---@class GardenerCustomInstallInfo
---@field url string?
---@field path string?
---@field revision string?
---@field branch string?
---@field location string?
---@field files string[]?
---@field generate boolean?
---@field generate_from_json boolean?
---@field queries string?

---@class GardenerCustomParser
---@field install_info GardenerCustomInstallInfo?
---@field filetypes string[]?
---@field files string[]?
---@field url string?
---@field path string?
---@field revision string?
---@field branch string?
---@field location string?
---@field generate boolean?
---@field generate_from_json boolean?
---@field queries string?

---@class GardenerOpts
---@field ensure_installed table<string, string[]|nil>|string[]
---@field custom_parsers table<string, GardenerCustomParser>
---@field never_install string[]|table<string, boolean>
---@field ignore_filetypes string[]
---@field auto_install boolean
---@field manage_folds boolean
---@field manage_indent boolean
---@field silent boolean

---@class GardenerState
---@field treesitter table
---@field ts_config table
---@field ensure_langs string[]
---@field filetype_to_lang table<string, string>
---@field never_install table<string, boolean>
---@field ignore_filetypes table<string, boolean>
---@field auto_install boolean
---@field manage_folds boolean
---@field manage_indent boolean
---@field silent boolean
---@field installing table<string, any>
---@field pending table<string, table<integer, boolean>>

---@class GardenerCustomParserState
---@field install_info GardenerCustomInstallInfo
---@field filetypes string[]

---@param state GardenerState|nil
---@param msg string
---@param level integer|nil
local function log(state, msg, level)
	if state and state.silent then
		return
	end
	vim.notify(msg, level or vim.log.levels.INFO, { title = "gardener.nvim" })
end

---@param values string[]|nil
---@return table<string, boolean>
local function to_string_set(values)
	local set = {}
	if type(values) ~= "table" then
		return set
	end

	for _, value in ipairs(values) do
		if type(value) == "string" and value ~= "" then
			set[value] = true
		end
	end

	return set
end

---@param values string[]|table<string, boolean>|nil
---@return table<string, boolean>
local function to_set(values)
	local set = {}
	if type(values) ~= "table" then
		return set
	end

	for key, value in pairs(values) do
		if type(key) == "number" and type(value) == "string" then
			set[value] = true
		elseif type(key) == "string" and value then
			set[key] = true
		end
	end

	return set
end

---@param defaults string[]
---@param user_values string[]|nil
---@return string[]
local function merge_string_lists(defaults, user_values)
	local merged = {}
	local seen = {}

	for _, value in ipairs(defaults) do
		if type(value) == "string" and value ~= "" and not seen[value] then
			seen[value] = true
			merged[#merged + 1] = value
		end
	end

	if type(user_values) == "table" then
		for _, value in ipairs(user_values) do
			if type(value) == "string" and value ~= "" and not seen[value] then
				seen[value] = true
				merged[#merged + 1] = value
			end
		end
	end

	return merged
end

---@param values string[]|string|nil
---@return string[]
local function normalize_string_list(values)
	if type(values) == "string" and values ~= "" then
		return { values }
	end

	local normalized = {}
	if type(values) ~= "table" then
		return normalized
	end

	local seen = {}
	for _, value in ipairs(values) do
		if type(value) == "string" and value ~= "" and not seen[value] then
			seen[value] = true
			normalized[#normalized + 1] = value
		end
	end

	return normalized
end

---@param raw_install_info GardenerCustomInstallInfo
---@return GardenerCustomInstallInfo
local function normalize_custom_install_info(raw_install_info)
	local install_info = vim.deepcopy(raw_install_info)
	install_info.files = normalize_string_list(install_info.files)

	if type(install_info.path) == "string" and install_info.path ~= "" then
		install_info.path = vim.fs.normalize(vim.fn.expand(install_info.path))
	end

	return install_info
end

---@param lang string
---@param install_info GardenerCustomInstallInfo
---@param state GardenerState|nil
---@return nil
local function warn_missing_highlights_query(lang, install_info, state)
	if type(install_info.path) ~= "string" or install_info.path == "" then
		return
	end

	if type(install_info.queries) ~= "string" or install_info.queries == "" then
		return
	end

	local highlights = vim.fs.joinpath(install_info.path, install_info.queries, "highlights.scm")
	if not vim.uv.fs_stat(highlights) then
		log(
			state,
			"Custom parser '" .. lang .. "' queries path has no highlights.scm: " .. highlights,
			vim.log.levels.WARN
		)
	end
end

---@param custom_parsers table<string, GardenerCustomParser>|nil
---@param state GardenerState|nil
---@return table<string, GardenerCustomParserState>
---@return table<string, string>
local function normalize_custom_parsers(custom_parsers, state)
	local normalized = {}
	local aliases = {}

	if type(custom_parsers) ~= "table" then
		return normalized, aliases
	end

	for lang, spec in pairs(custom_parsers) do
		if type(lang) == "string" and lang ~= "" and type(spec) == "table" then
			local install_info = spec.install_info
			if type(install_info) ~= "table" then
				install_info = {
					url = spec.url,
					path = spec.path,
					revision = spec.revision,
					branch = spec.branch,
					location = spec.location,
					files = spec.files,
					generate = spec.generate,
					generate_from_json = spec.generate_from_json,
					queries = spec.queries,
				}
			end

			install_info = normalize_custom_install_info(install_info)
			if type(install_info.url) ~= "string" and type(install_info.path) ~= "string" then
				log(
					state,
					"Custom parser '" .. lang .. "' must define install_info.url or install_info.path",
					vim.log.levels.WARN
				)
			else
				warn_missing_highlights_query(lang, install_info, state)
				local filetypes = normalize_string_list(spec.filetypes)
				normalized[lang] = {
					install_info = install_info,
					filetypes = filetypes,
				}
				for _, ft in ipairs(filetypes) do
					aliases[ft] = lang
				end
			end
		end
	end

	return normalized, aliases
end

---@param custom_parsers table<string, GardenerCustomParserState>
---@return nil
local function register_custom_parsers(custom_parsers)
	local parser_registry = require("nvim-treesitter.parsers")
	for lang, spec in pairs(custom_parsers) do
		local current = parser_registry[lang] or {}
		local current_install = current.install_info or {}
		local spec_install = spec.install_info or {}

		local merged_install
		if spec_install.url and current_install.url and spec_install.url ~= current_install.url then
			merged_install = spec_install
		else
			merged_install = vim.tbl_deep_extend("force", current_install, spec_install)
		end

		local res = vim.tbl_deep_extend("force", current, {})
		res.install_info = merged_install
		parser_registry[lang] = res
	end
end

---@param ensure_installed table<string, string[]|nil>|string[]|nil
---@return string[] ensure_langs
---@return table<string, string> filetype_to_lang
local function normalize_ensure_installed(ensure_installed)
	local langs = {}
	local seen = {}
	local aliases = {}

	if type(ensure_installed) ~= "table" then
		return langs, aliases
	end

	local function add_lang(lang)
		if type(lang) ~= "string" or lang == "" or seen[lang] then
			return
		end
		seen[lang] = true
		langs[#langs + 1] = lang
	end

	for key, value in pairs(ensure_installed) do
		if type(key) == "number" then
			if type(value) == "string" then
				add_lang(value)
			end
		elseif type(key) == "string" then
			add_lang(key)
			if type(value) == "table" then
				for _, ft in ipairs(value) do
					if type(ft) == "string" and ft ~= "" then
						aliases[ft] = key
					end
				end
			end
		end
	end

	return langs, aliases
end

---@param buf integer
---@param lang string
---@param state GardenerState|nil
---@return boolean
local function attach_treesitter(buf, lang, state)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	pcall(vim.treesitter.language.add, lang)
	pcall(vim.treesitter.stop, buf)

	local ok = pcall(vim.treesitter.start, buf, lang)
	if not ok then
		return false
	end

	if state and state.manage_folds then
		for _, win in ipairs(vim.fn.win_findbuf(buf)) do
			if vim.api.nvim_win_is_valid(win) then
				vim.wo[win].foldmethod = "expr"
				vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
			end
		end
	end

	if state and state.manage_indent then
		vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end

	return true
end

---@param state GardenerState
---@param lang string
---@param buf integer
local function queue_pending_buffer(state, lang, buf)
	if not state.pending[lang] then
		state.pending[lang] = {}
	end
	state.pending[lang][buf] = true
end

---@param state GardenerState
---@param lang string
---@return integer[]
local function consume_pending_buffers(state, lang)
	local pending = state.pending[lang]
	state.pending[lang] = nil
	if not pending then
		return {}
	end

	local bufs = {}
	for buf, _ in pairs(pending) do
		bufs[#bufs + 1] = buf
	end
	return bufs
end

---@param state GardenerState
---@param buf integer
---@return nil
local function ensure_treesitter(state, buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	if vim.bo[buf].buftype ~= "" then
		return
	end

	local ft = vim.bo[buf].filetype
	if ft == "" or state.ignore_filetypes[ft] then
		return
	end

	local lang = state.filetype_to_lang[ft] or vim.treesitter.language.get_lang(ft) or ft
	if state.never_install[lang] then
		attach_treesitter(buf, lang, state)
		return
	end

	local parser_registry = require("nvim-treesitter.parsers")
	if parser_registry[lang] == nil then
		attach_treesitter(buf, lang, state)
		return
	end

	local managed_installed = vim.list_contains(state.ts_config.get_installed("parsers"), lang)
	if managed_installed then
		attach_treesitter(buf, lang, state)
		return
	end

	if not state.auto_install then
		return
	end

	queue_pending_buffer(state, lang, buf)

	if state.installing[lang] then
		return
	end

	local ok, task = pcall(state.treesitter.install, { lang }, { summary = true })
	if not ok or not task or type(task.await) ~= "function" then
		state.pending[lang] = nil
		log(state, "Treesitter install failed for " .. lang, vim.log.levels.WARN)
		return
	end

	state.installing[lang] = task
	task:await(function(err, success)
		vim.schedule(function()
			state.installing[lang] = nil
			local pending = consume_pending_buffers(state, lang)

			if err or not success then
				log(state, "Treesitter install failed for " .. lang, vim.log.levels.WARN)
				return
			end

			-- Neovim caches the directories of 'runtimepath'. On the first
			-- install, the parser directory did not exist at startup, so the
			-- new parser cannot be found until the cache is refreshed.
			vim.o.runtimepath = vim.o.runtimepath
			pcall(vim.treesitter.query.invalidate, lang)
			for _, pending_buf in ipairs(pending) do
				attach_treesitter(pending_buf, lang, state)
			end
		end)
	end)
end

---@param input GardenerOpts|nil
---@return GardenerOpts
local function normalize_setup_opts(input)
	local raw = input
	if type(raw) ~= "table" then
		raw = {}
	end

	---@type GardenerOpts
	local opts = vim.tbl_deep_extend("force", vim.deepcopy(default_opts), raw)
	opts.ignore_filetypes = merge_string_lists(default_opts.ignore_filetypes, raw.ignore_filetypes)

	return opts
end

---@param input GardenerOpts|nil
---@return nil
function M.setup(input)
	local opts = normalize_setup_opts(input)
	local treesitter = require("nvim-treesitter")
	local ts_config = require("nvim-treesitter.config")
	local ensure_langs, filetype_to_lang = normalize_ensure_installed(opts.ensure_installed)
	local ignore_filetypes = to_string_set(opts.ignore_filetypes)

	local state = {
		treesitter = treesitter,
		ts_config = ts_config,
		ensure_langs = ensure_langs,
		filetype_to_lang = filetype_to_lang,
		never_install = to_set(opts.never_install),
		ignore_filetypes = ignore_filetypes,
		auto_install = opts.auto_install,
		manage_folds = opts.manage_folds,
		manage_indent = opts.manage_indent,
		silent = opts.silent,
		installing = {},
		pending = {},
	}

	local custom_parsers, custom_aliases = normalize_custom_parsers(opts.custom_parsers, state)
	register_custom_parsers(custom_parsers)
	for ft, lang in pairs(custom_aliases) do
		filetype_to_lang[ft] = lang
	end

	for ft, lang in pairs(filetype_to_lang) do
		pcall(vim.treesitter.language.register, lang, ft)
	end

	local group = vim.api.nvim_create_augroup("gardener_auto_install", { clear = true })

	-- nvim-treesitter's install()/update() reload the parsers module (dropping
	-- our registrations) and then fire User TSUpdate. Hook it before the first
	-- install below so custom parsers survive the ensure_installed pass.
	if next(custom_parsers) then
		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "TSUpdate",
			callback = function()
				register_custom_parsers(custom_parsers)
			end,
		})
	end

	if #ensure_langs > 0 then
		local parser_registry = require("nvim-treesitter.parsers")
		local supported_langs = vim.tbl_filter(function(lang)
			return parser_registry[lang] ~= nil
		end, ensure_langs)

		if #supported_langs > 0 then
			treesitter.install(supported_langs, { summary = false })
		end
	end

	vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufNewFile", "BufEnter" }, {
		group = group,
		---@param args { buf: integer }
		callback = function(args)
			vim.schedule(function()
				ensure_treesitter(state, args.buf)
			end)
		end,
	})
end

return M
