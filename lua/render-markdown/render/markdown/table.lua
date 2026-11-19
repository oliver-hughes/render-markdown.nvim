local Base = require('render-markdown.render.base')
local Parser = require('render-markdown.parser.table')
local compat = require('render-markdown.lib.compat')
local env = require('render-markdown.lib.env')
local iter = require('render-markdown.lib.iter')
local list = require('render-markdown.lib.list')
local scope = require('render-markdown.lib.scope')
local str = require('render-markdown.lib.str')
local ui = require('render-markdown.core.ui')

---@class render.md.render.Table: render.md.Render
---@field private config render.md.table.Config
---@field private data render.md.table.Data
local Render = setmetatable({}, Base)
Render.__index = Render

---Rows are drawn over where a window wraps them, which differs between
---windows of different widths. When the context lists windows the table is
---drawn for each of them, into marks that only that window shows.
---@param context render.md.request.Context
---@param marks render.md.Marks
---@param node render.md.Node
---@return boolean
function Render:execute(context, marks, node)
    local wins = context.wins
    if not wins then
        return Base.execute(self, context, marks, node)
    end
    local result = false
    local used = context.used
    for _, win in ipairs(wins) do
        local window = context:window(win)
        marks:scope(win)
        result = Base.execute(self, window, marks, node) or result
        -- borders take the same rows in every window
        used = window.used
    end
    marks:scope(nil)
    context.used = used
    return result
end

---@protected
---@return boolean
function Render:setup()
    self.config = self.context.config.pipe_table
    if not self.config.enabled then
        return false
    end
    local parser = Parser.new(self.context, self.config)
    local data = parser:parse(self.node, self.marks)
    if not data then
        return false
    end
    self.data = data
    return true
end

---@protected
function Render:run()
    local overlay = self:overlay()

    self:delimiter(overlay)

    for i, row in ipairs(self.data.rows) do
        local lines = nil ---@type render.md.mark.Line[]?
        if overlay then
            self:cover(row.node, function(height)
                return self:wrapped_row(row, height)
            end)
        elseif self.data.layout.wrap and not self:row_fits(row) then
            lines = self:wrapped_row(row)
        else
            self:row(row)
        end

        if self.data.layout.valid and self:border_equal(row) then
            if i == 1 and self.config.border_enabled then
                self:border_row(row, 'above', lines, overlay)
            elseif i == #self.data.rows and self.config.border_enabled then
                self:border_row(row, 'below', lines, overlay)
            elseif i > 1 and i < #self.data.rows and self.config.grid then
                self:border_row(row, 'body', lines, overlay)
            end
        end

        if lines then
            self.marks:replace(self.config, row.node, lines)
        end
    end
end

---Every row is covered once any row needs wrapping, so all of them behave
---the same when the cursor is on them.
---@private
---@return boolean
function Render:overlay()
    if not self.data.layout.wrap or self.config.wrap_mode ~= 'overlay' then
        return false
    end
    -- measuring screen lines needs nvim_win_text_height max_height
    if not compat.has_11 then
        return false
    end
    if self:delimiter_wraps() then
        return true
    end
    for _, row in ipairs(self.data.rows) do
        if not self:row_fits(row) then
            return true
        end
    end
    return false
end

---@private
---@return boolean
function Render:delimiter_wraps()
    if
        not self.data.layout.wrap or not env.win.get(self.context.win, 'wrap')
    then
        return false
    end
    local _, source = self.data.delim:line('first', 0)
    local width = str.width(source) + self:indent():size()
    return width > env.win.width(self.context.win)
end

---@private
---@param overlay boolean
function Render:delimiter(overlay)
    local delim = self.data.delim

    local replace = self:delimiter_wraps()

    local delimiter = self:border_line('body', { delimiter = true })

    local line = self:line()
    if replace and overlay then
        line:extend(self.data.prefixes[delim.start_row])
        line:extend(delimiter)
        self:cover(delim, function(height)
            local lines = { line:get() }
            for _ = 2, height do
                lines[#lines + 1] = self:empty_row(delim, self.config.head)
            end
            return lines
        end)
    elseif replace then
        line:extend(self.data.prefixes[delim.start_row])
        line:extend(delimiter)
        self.marks:replace(self.config, delim, { line:get() })
    else
        line:pad(str.spaces('start', delim.text))
        line:extend(delimiter)
        line:pad(str.width(delim.text) - line:width())
        self.marks:over(self.config, 'table_border', delim, {
            virt_text = line:get(),
            virt_text_pos = 'overlay',
        })
    end
end

---@private
---@param row render.md.table.Row
---@return boolean
function Render:row_fits(row)
    local added = self.context.inline:width(row.node)
    for i, cell in ipairs(row.cells) do
        local col = self.data.cols[i]
        local units = assert(cell.units, 'missing cell units')
        local width = Parser.measure(units)
        if width + 2 * self.config.padding > col.width then
            return false
        end
        local left, right = self:shifts(col, cell)
        if width ~= cell.width - cell.space.left - cell.space.right then
            return false
        end
        added = added + math.max(left, 0) + math.max(right, 0) ---@type integer
    end
    if env.win.get(self.context.win, 'wrap') then
        local _, source = row.node:line('first', 0)
        local width = str.width(source) + self:indent():size() + added
        return width <= env.win.width(self.context.win)
    end
    return true
end

---@private
---@param row render.md.table.Row
function Render:row(row)
    local icon = self.config.border[10]
    local header = row.node.type == 'pipe_table_header'
    local highlight = header and self.config.head or self.config.row

    if vim.tbl_contains({ 'trimmed', 'padded', 'raw' }, self.config.cell) then
        for _, pipe in ipairs(row.pipes) do
            self.marks:over(self.config, 'table_border', pipe, {
                virt_text = { { icon, highlight } },
                virt_text_pos = 'overlay',
            })
        end
    end

    if vim.tbl_contains({ 'trimmed', 'padded' }, self.config.cell) then
        for i, cell in ipairs(row.cells) do
            local left, right = self:shifts(self.data.cols[i], cell)
            self:shift(cell.node, 'left', left)
            self:shift(cell.node, 'right', right)
        end
    elseif self.config.cell == 'overlay' then
        self.marks:over(self.config, 'table_border', row.node, {
            virt_text = { { row.node.text:gsub('|', icon), highlight } },
            virt_text_pos = 'overlay',
        })
    end
end

---@private
---@param row render.md.table.Row
---@param height? integer minimum number of lines
---@return render.md.mark.Line[]
function Render:wrapped_row(row, height)
    local prefixes = self.data.prefixes
    local padding = self.config.padding
    local icon = self.config.border[10]
    local header = row.node.type == 'pipe_table_header'
    local highlight = header and self.config.head or self.config.row

    local cells = {} ---@type render.md.mark.Line[][]
    height = height or 1
    for i, cell in ipairs(row.cells) do
        local col = self.data.cols[i]
        local units = assert(cell.units, 'missing cell units')
        cells[i] = Parser.wrap(units, col.width - 2 * padding)
        height = math.max(height, #cells[i])
    end

    local lines = {} ---@type render.md.mark.Line[]
    for fragment = 1, height do
        local line = self:line()
            :extend(prefixes[row.node.start_row])
            :text(icon, highlight)
        for i, col in ipairs(self.data.cols) do
            local cell = Parser.align(
                cells[i][fragment] or {},
                col.width,
                col.alignment,
                padding,
                highlight
            )
            line:extend(cell)
            line:text(icon, highlight)
        end
        lines[#lines + 1] = line:get()
    end
    return lines
end

---@private
---@param node render.md.Node
---@param highlight string
---@return render.md.mark.Line
function Render:empty_row(node, highlight)
    local padding = self.config.padding
    local icon = self.config.border[10]
    local line = self:line()
        :extend(self.data.prefixes[node.start_row])
        :text(icon, highlight)
    for _, col in ipairs(self.data.cols) do
        local cell =
            Parser.align({}, col.width, col.alignment, padding, highlight)
        line:extend(cell)
        line:text(icon, highlight)
    end
    return line:get()
end

---Draw over the screen lines a soft wrapped row takes up instead of hiding
---it, so the cursor and scrolling stay on real text. Lines past the height of
---the text are added as virtual lines below, which an empty spacer replaces
---while the row is concealed so nothing below it moves.
---@private
---@param node render.md.Node
---@param get fun(height: integer): render.md.mark.Line[]
function Render:cover(node, get)
    local buf, win = self.context.buf, self.context.win
    local row = node.start_row
    -- marks from the previous render would move where the row wraps, every
    -- mark on it is replaced by this render
    vim.api.nvim_buf_clear_namespace(buf, ui.ns, row, row + 1)
    local ns = scope.find(win)
    if ns then
        vim.api.nvim_buf_clear_namespace(buf, ns, row, row + 1)
    end
    local starts = env.row.starts(win, row)

    local width = env.win.width(win)
    local lines = iter.list.map(get(#starts), function(line)
        -- cover all of the text on each screen line
        local result = self:line():extend(line)
        return result:pad(width - result:width()):get()
    end)
    local extra = vim.list_slice(lines, #starts + 1)

    -- overlays hide the cursor line highlight, so the row gets a copy with it
    local overlays = { 'text' } ---@type render.md.mark.Overlay[]
    local opt = env.win.get(win, 'cursorlineopt')
    local cursorline = opt:find('line', 1, true) or opt:find('both', 1, true)
    if env.win.get(win, 'cursorline') and cursorline then
        overlays = { 'away', 'cursor' }
    end
    for _, overlay in ipairs(overlays) do
        ---@param line render.md.mark.Line
        ---@return render.md.mark.Line
        local function highlight(line)
            if overlay ~= 'cursor' then
                return line
            end
            return iter.list.map(line, function(text)
                local hl = vim.list_extend({}, list.ensure(text[2]))
                hl[#hl + 1] = 'CursorLine'
                return { text[1], hl }
            end)
        end
        for i, col in ipairs(starts) do
            self.marks:overlay(self.config, 'table_border', row, col, {
                virt_text = highlight(lines[i]),
                virt_text_pos = 'overlay',
                virt_text_win_col = 0,
            }, overlay)
        end
        if #extra > 0 then
            self.marks:overlay(self.config, 'table_border', row, 0, {
                virt_lines = iter.list.map(extra, highlight),
            }, overlay)
        end
    end
    if #extra > 0 then
        local spacer = iter.list.map(extra, function()
            return self:line():pad(1):get()
        end)
        self.marks:overlay(self.config, 'table_border', row, 0, {
            virt_lines = spacer,
        }, 'spacer')
    end
end

---@private
---@param col render.md.table.Col
---@param cell render.md.table.row.Cell
---@return integer, integer
function Render:shifts(col, cell)
    local space = cell.space
    local fill = col.width - cell.width
    -- delim(20) : --------------------
    -- col(4,7,2): ----XXXXXXX--
    -- fill(7)   :              _______
    if not self.context.conceal:enabled() then
        -- result: ----XXXXXXX--_______
        -- without concealing it is impossible to do full alignment
        return 0, fill
    elseif col.alignment == Parser.Alignment.center then
        -- (7 + 2 - 4) // 2 = 5 // 2 = 2 -> move two spaces to the right
        -- result: __----XXXXXXX--_____
        local shift = math.floor((fill + space.right - space.left) / 2)
        return shift, fill - shift
    elseif col.alignment == Parser.Alignment.right then
        -- 2 - 1 = 1 -> conceal one space on right side
        -- result: -_______----XXXXXXX-
        local shift = space.right - self.config.padding
        return fill + shift, -shift
    else
        -- 4 - 1 = 3 -> conceal three spaces on left side
        -- result: -XXXXXXX--_______---
        local shift = space.left - self.config.padding
        return -shift, fill + shift
    end
end

---Use low priority to include pipe marks
---@private
---@param node render.md.Node
---@param side 'left'|'right'
---@param amount integer
function Render:shift(node, side, amount)
    local col = side == 'left' and node.start_col or node.end_col
    if amount > 0 then
        self.marks:add(self.config, true, node.start_row, col, {
            priority = 0,
            virt_text = self:line():pad(amount):get(),
            virt_text_pos = 'inline',
        })
    elseif amount < 0 then
        amount = amount - self.context.conceal:width('', 1)
        self.marks:add(self.config, true, node.start_row, col + amount, {
            priority = 0,
            end_col = col,
            conceal = '',
        })
    end
end

---@private
---@param row render.md.table.Row
---@param position 'above'|'body'|'below'
---@param lines? render.md.mark.Line[]
---@param overlay boolean
function Render:border_row(row, position, lines, overlay)
    local virtual = true
    local start_row = row.node.start_row
    local line = self:line()

    if position == 'body' then
        line:extend(self.data.prefixes[start_row])
    else
        -- needed for type narrowing
        position = position == 'above' and 'above' or 'below'
        local target_row, target = row.node:line(position, 1)
        virtual = self.config.border_virtual
            or not (target and str.width(target) == 0)
            or not self.context.used:take(target_row)
        start_row = virtual and start_row or target_row
        line:pad(self.data.layout.col)
    end

    line:extend(self:border_line(position, {}))

    if not virtual then
        self.marks:add(self.config, 'table_border', start_row, 0, {
            priority = self.config.border_priority,
            virt_text = line:get(),
            virt_text_pos = 'overlay',
        })
        return
    end

    local output = self:indent():line(true):extend(line):get()
    if lines then
        local index = position == 'above' and 1 or #lines + 1
        table.insert(lines, index, output)
    else
        -- virtual lines on a row are ordered by column, an overlay adds its
        -- own at the start of the row which need to come first
        local col = 0
        if overlay and position ~= 'above' then
            local _, source = row.node:line('first', 0)
            col = #(source or '')
        end
        self.marks:add(self.config, 'virtual_lines', start_row, col, {
            virt_lines = { output },
            virt_lines_above = position == 'above',
        })
    end
end

---@private
---@param position 'above'|'body'|'below'
---@param opts { delimiter?: boolean }
---@return render.md.mark.Line
function Render:border_line(position, opts)
    local border = self.config.border
    local indicator = self.config.alignment_indicator
    local base = border[11]

    local parts = iter.list.map(self.data.cols, function(col)
        if
            -- must be on delimiter node
            not opts.delimiter
            -- must have enough space to put the alignment indicator
            or col.width < 3
            -- alignment indicator must be exactly one character wide
            or str.width(indicator) ~= 1
            -- default alignment does not include an indicator
            or col.alignment == Parser.Alignment.default
        then
            return base:rep(col.width)
        elseif col.alignment == Parser.Alignment.left then
            return indicator .. base:rep(col.width - 1)
        elseif col.alignment == Parser.Alignment.right then
            return base:rep(col.width - 1) .. indicator
        else
            return indicator .. base:rep(col.width - 2) .. indicator
        end
    end)

    local index = ({ above = 1, body = 4, below = 7 })[position]

    local text = border[index]
        .. table.concat(parts, border[index + 1])
        .. border[index + 2]

    local highlight = (position == 'above' or opts.delimiter)
            and self.config.head
        or self.config.row

    return self:line():text(text, highlight):get()
end

---@private
---@param row render.md.table.Row
---@return boolean
function Render:border_equal(row)
    if vim.tbl_contains({ 'trimmed', 'padded' }, self.config.cell) then
        -- assume table was modified to match
        return true
    elseif self.config.cell == 'raw' then
        -- want the computed widths to match
        for i, cell in ipairs(row.cells) do
            if cell.width ~= self.data.cols[i].width then
                return false
            end
        end
        return true
    elseif self.config.cell == 'overlay' then
        -- want the underlying text widths to match
        return str.width(row.node.text) == str.width(self.data.delim.text)
    else
        return false
    end
end

return Render
