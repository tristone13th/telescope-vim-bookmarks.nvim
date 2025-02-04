local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local entry_display = require("telescope.pickers.entry_display")
local conf = require("telescope.config").values

local utils = require("telescope.utils")

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local bookmark_actions = require("telescope._extensions.vim_bookmarks.actions")

local function get_bookmarks(files, opts)
	opts = opts or {}
	local bookmarks = {}

	for _, file in ipairs(files) do
		for _, line in ipairs(vim.fn["bm#all_lines"](file)) do
			local bookmark = vim.fn["bm#get_bookmark_by_line"](file, line)

			local text = bookmark.annotation ~= "" and "Annotation: " .. bookmark.annotation or bookmark.content
			if text == "" then
				text = "(empty line)"
			end

			local only_annotated = opts.only_annotated or false

			if not (only_annotated and bookmark.annotation == "") then
				table.insert(bookmarks, {
					filename = file,
					lnum = tonumber(line),
					col = 1,
					text = text,
					sign_idx = bookmark.sign_idx,
				})
			end
		end
	end

	return bookmarks
end

local function make_entry_from_bookmarks(opts)
	opts = opts or {}
	opts.tail_path = vim.F.if_nil(opts.tail_path, true)

	local displayer = entry_display.create({
		separator = "▏",
		items = {
			{ width = opts.width_text or 20 },
			{ remaining = true },
		},
	})

	local make_display = function(entry)
		local filename
		if not opts.path_display then
			filename = entry.filename
			if opts.tail_path then
				filename = utils.path_tail(filename)
			elseif opts.shorten_path then
				filename = utils.path_shorten(filename)
			end
		end

		return displayer({
			filename,
			entry.text:gsub(".* | ", ""),
		})
	end

	return function(entry)
		return {
			valid = true,

			value = entry,
			ordinal = (not opts.ignore_filename and filename or "") .. " " .. entry.text,
			display = make_display,

			filename = entry.filename,
			lnum = entry.lnum,
			col = 1,
			text = entry.text,
		}
	end
end

local function startswith(str, start)
	return str:sub(1, #start) == start
end

local function trim_filenames(filenames)
	local r = {}
	local cwd = vim.fn.getcwd()
	for _, file in ipairs(filenames) do
		if startswith(file, cwd) then
			table.insert(r, file)
		end
	end
	return r
end

local function make_bookmark_picker(filenames, opts)
	opts = opts or {}
	filenames = trim_filenames(filenames)

	local make_finder = function()
		local bookmarks = get_bookmarks(filenames, opts)

		if vim.tbl_isempty(bookmarks) then
			print("No bookmarks!")
			return
		end

		return finders.new_table({
			results = bookmarks,
			entry_maker = make_entry_from_bookmarks(opts),
		})
	end

	local initial_finder = make_finder()
	if not initial_finder then
		return
	end

	pickers.new(opts, {
		prompt_title = opts.prompt_title or "vim-bookmarks",
		finder = initial_finder,
		previewer = conf.qflist_previewer(opts),
		sorter = conf.generic_sorter(opts),

		attach_mappings = function(prompt_bufnr)
			local refresh_picker = function()
				local new_finder = make_finder()
				if new_finder then
					action_state.get_current_picker(prompt_bufnr):refresh(make_finder())
				else
					actions.close(prompt_bufnr)
				end
			end

			bookmark_actions.delete_selected:enhance({ post = refresh_picker })
			bookmark_actions.delete_at_cursor:enhance({ post = refresh_picker })
			bookmark_actions.delete_all:enhance({ post = refresh_picker })
			bookmark_actions.delete_selected_or_at_cursor:enhance({ post = refresh_picker })

			return true
		end,
	}):find()
end

local all = function(opts)
	make_bookmark_picker(vim.fn["bm#all_files"](), opts)
end

local current_file = function(opts)
	opts = opts or {}
	opts = vim.tbl_extend("keep", opts, { path_display = true })

	make_bookmark_picker({ vim.fn.expand("%:p") }, opts)
end

return require("telescope").register_extension({
	exports = {
		-- Default when to argument is given, i.e. :Telescope vim_bookmarks
		vim_bookmarks = all,
		all = all,
		current_file = current_file,
		actions = bookmark_actions,
	},
})
