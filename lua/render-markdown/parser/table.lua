local Indent = require('render-markdown.lib.indent')
local display = require('render-markdown.lib.display')
local env = require('render-markdown.lib.env')
local log = require('render-markdown.core.log')
local str = require('render-markdown.lib.str')

---@class render.md.table.Data
---@field layout render.md.table.Layout
---@field delim render.md.Node
---@field cols render.md.table.Col[]
---@field rows render.md.table.Row[]
---@field prefixes table<integer, render.md.mark.Line>

---@class render.md.table.Layout
---@field col integer
---@field valid boolean
---@field wrap boolean

---@class render.md.table.Col
---@field width integer
---@field alignment render.md.table.col.Alignment

---@class render.md.table.Row
---@field node render.md.Node
---@field pipes render.md.Node[]
---@field cells render.md.table.row.Cell[]

---@class render.md.table.row.Cell
---@field node render.md.Node
---@field width integer
---@field space render.md.table.cell.Space
---@field units? render.md.table.Unit[]

---@class render.md.table.cell.Space
---@field left integer
---@field right integer

---@class render.md.table.row.Parts
---@field pipes render.md.Node[]
---@field cells render.md.Node[]

---@class render.md.table.Unit
---@field text string
---@field highlight render.md.mark.Hl
---@field width integer

---@class render.md.parser.Table
---@field private context render.md.request.Context
---@field private config render.md.table.Config
local Parser = {}
Parser.__index = Parser

---@enum render.md.table.col.Alignment
Parser.Alignment = {
    left = 'left',
    right = 'right',
    center = 'center',
    default = 'default',
}

---@param context render.md.request.Context
---@param config render.md.table.Config
---@return render.md.parser.Table
function Parser.new(context, config)
    local self = setmetatable({}, Parser)
    self.context = context
    self.config = config
    return self
end

---@param root render.md.Node
---@param marks render.md.Marks
---@return render.md.table.Data?
function Parser:parse(root, marks)
    -- ensure delimiter and rows exist
    local delim = nil ---@type render.md.Node?
    local row_nodes = {} ---@type render.md.Node[]
    local types = {
        delim = 'pipe_table_delimiter_row',
        row = { 'pipe_table_header', 'pipe_table_row' },
        skip = { 'block_continuation' },
    }
    root:for_each_child(function(node)
        if node.type == types.delim then
            delim = node
        elseif self.context.view:overlaps(node:get()) then
            if vim.tbl_contains(types.row, node.type) then
                row_nodes[#row_nodes + 1] = node
            elseif not vim.tbl_contains(types.skip, node.type) then
                log.unhandled(self.context.buf, 'markdown', 'row', node.type)
            end
        end
    end)
    if not delim or #row_nodes == 0 then
        return nil
    end

    ---@type render.md.table.Layout
    local layout = {
        col = delim:col(),
        valid = true,
        wrap = self.config.wrap and self.context.conceal.level > 1,
    }

    local cols = self:cols(delim)
    if not cols then
        return nil
    end

    local rows = {} ---@type render.md.table.Row[]
    table.sort(row_nodes)
    for _, row_node in ipairs(row_nodes) do
        local row = self:row(row_node, #cols)
        if row then
            if row.node:col() ~= layout.col then
                layout.valid = false
                layout.wrap = false
            end
            rows[#rows + 1] = row
        end
    end
    if #rows == 0 then
        return nil
    end

    -- store the max width in cols
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row.cells) do
            local space = cell.space.left + cell.space.right
            local available = space - (2 * self.config.padding)
            -- if we don't have enough space for padding add it to the width
            local width = cell.width
            if available < 0 then
                width = width - available
            end
            if self.config.cell == 'trimmed' then
                width = width - math.max(available, 0)
            end
            cols[i].width = math.max(cols[i].width, width)
        end
    end

    local prefixes = {} ---@type table<integer, render.md.mark.Line>
    local prefix_width = 0
    if layout.wrap or self.config.grid then
        local indent = Indent.new(self.context, root):line(true)

        ---@param node render.md.Node
        local function prefix(node)
            local expanded = self.context.config:line()
            local line = indent:copy():extend(
                display.prefix(self.context, marks:get(), node)
            )
            for _, unit in ipairs(Parser.units(line:get())) do
                expanded:text(unit.text, unit.highlight)
            end
            prefixes[node.start_row] = expanded:get()
            prefix_width = math.max(prefix_width, expanded:width())
        end

        prefix(delim)
        for _, row in ipairs(rows) do
            prefix(row.node)
        end
    end

    if layout.wrap then
        local desired = {} ---@type integer[]
        local minimum = {} ---@type integer[]
        local padding = self.config.padding
        for i, col in ipairs(cols) do
            desired[i] = col.width
            minimum[i] = math.max(self.config.min_width, 2 * padding + 1)
        end

        for _, row in ipairs(rows) do
            for i, cell in ipairs(row.cells) do
                local node = cell.node
                local left = str.spaces('start', node.text)
                local right = str.spaces('end', node.text)
                local line = display.line(self.context, {
                    start_row = node.start_row,
                    end_row = node.end_row,
                    start_col = node.start_col + left,
                    end_col = node.end_col - right,
                    text = node.text:sub(left + 1, #node.text - right),
                })
                cell.units = Parser.units(line)

                local width, smallest = Parser.measure(cell.units)
                desired[i] = math.max(desired[i], 2 * padding + width)
                minimum[i] = math.max(minimum[i], 2 * padding + smallest)
            end
        end

        local budget = env.win.width(self.context.win)
        budget = budget - (prefix_width + #cols + 1)

        local widths = Parser.allocate(desired, minimum, budget)
        if not widths then
            layout.wrap = false
        else
            widths = self:shortest(rows, widths, desired, budget)
            for i, width in ipairs(widths) do
                cols[i].width = width
            end
        end
    end

    ---@type render.md.table.Data
    return {
        layout = layout,
        delim = delim,
        cols = cols,
        rows = rows,
        prefixes = prefixes,
    }
end

---@private
---@param node render.md.Node
---@return render.md.table.Col[]?
function Parser:cols(node)
    local parts = self:row_parts(node, 'pipe_table_delimiter_cell')
    if not parts then
        return nil
    end
    local cols = {} ---@type render.md.table.Col[]
    for i, cell in ipairs(parts.cells) do
        local start_col = parts.pipes[i].end_col
        local end_col = parts.pipes[i + 1].start_col
        local width = end_col - start_col
        assert(width >= 0, 'invalid table layout')
        if self.config.cell == 'padded' then
            width = math.max(width, self.config.min_width)
        elseif self.config.cell == 'trimmed' then
            width = self.config.min_width
        end
        cols[#cols + 1] = {
            width = width,
            alignment = Parser.alignment(cell),
        }
    end
    return cols
end

---@private
---@param node render.md.Node
---@return render.md.table.col.Alignment
function Parser.alignment(node)
    local left = node:child('pipe_table_align_left')
    local right = node:child('pipe_table_align_right')
    if left and right then
        return Parser.Alignment.center
    elseif left then
        return Parser.Alignment.left
    elseif right then
        return Parser.Alignment.right
    else
        return Parser.Alignment.default
    end
end

---@private
---@param node render.md.Node
---@param num_cols integer
---@return render.md.table.Row?
function Parser:row(node, num_cols)
    local parts = self:row_parts(node, 'pipe_table_cell')
    if not parts or #parts.cells ~= num_cols then
        return nil
    end
    local cells = {} ---@type render.md.table.row.Cell[]
    for i, cell in ipairs(parts.cells) do
        -- account for double width glyphs by replacing cell range with width
        local start_col = parts.pipes[i].end_col
        local end_col = parts.pipes[i + 1].start_col
        local width = (end_col - start_col)
            - (cell.end_col - cell.start_col)
            + self.context:width(cell)
            + self.config.cell_offset({ node = cell:get() })
        assert(width >= 0, 'invalid table layout')
        cells[#cells + 1] = {
            node = cell,
            width = width,
            space = {
                -- gap between the cell start and the pipe start
                left = math.max(cell.start_col - start_col, 0),
                -- attached to the end of the cell itself
                right = math.max(str.spaces('end', cell.text), 0),
            },
        }
    end
    ---@type render.md.table.Row
    return { node = node, pipes = parts.pipes, cells = cells }
end

---@private
---@param node render.md.Node
---@param cell_type string
---@return render.md.table.row.Parts?
function Parser:row_parts(node, cell_type)
    local pipes = {} ---@type render.md.Node[]
    local cells = {} ---@type render.md.Node[]
    node:for_each_child(function(child)
        if child.type == '|' then
            pipes[#pipes + 1] = child
        elseif child.type == cell_type then
            cells[#cells + 1] = child
        else
            log.unhandled(self.context.buf, 'markdown', 'cell', child.type)
        end
    end)
    if #pipes == 0 or #cells == 0 or #pipes ~= #cells + 1 then
        return nil
    end
    table.sort(pipes)
    table.sort(cells)
    ---@type render.md.table.row.Parts
    return { pipes = pipes, cells = cells }
end

---@param line render.md.mark.Line
---@return render.md.table.Unit[]
function Parser.units(line)
    local result = {} ---@type render.md.table.Unit[]
    for _, text in ipairs(line) do
        local s = text[1]
        if not s:find('[^\32-\126]') then
            -- printable ascii is one byte and one cell per character, which
            -- avoids splitting and measuring every character with vimscript
            for i = 1, #s do
                result[#result + 1] = {
                    text = s:sub(i, i),
                    highlight = text[2],
                    width = 1,
                }
            end
        else
            for _, char in ipairs(str.chars(s)) do
                result[#result + 1] = {
                    text = char,
                    highlight = text[2],
                    width = str.width(char),
                }
            end
        end
    end
    return result
end

---@param units render.md.table.Unit[]
---@return integer, integer
function Parser.measure(units)
    local width, minimum = 0, 1
    for _, unit in ipairs(units) do
        width = width + unit.width
        minimum = math.max(minimum, unit.width)
    end
    return width, minimum
end

---@param desired integer[]
---@param minimum integer[]
---@param budget integer
---@return integer[]?
function Parser.allocate(desired, minimum, budget)
    local natural = 0
    local floor = 0
    for i, width in ipairs(desired) do
        natural = natural + width ---@type integer
        floor = floor + minimum[i] ---@type integer
    end
    if natural <= budget then
        return desired
    end
    if budget < floor then
        return nil
    end

    local locked = {} ---@type table<integer, true>
    local free = #desired
    local share = math.floor(budget / free)
    local changed = true
    while changed do
        changed = false
        for i = 1, #desired do
            if not locked[i] and desired[i] <= share then
                locked[i] = true
                budget = budget - desired[i]
                free = free - 1
                changed = true
            end
        end
        share = math.floor(budget / free)
    end

    local widths = {} ---@type integer[]
    for i, width in ipairs(desired) do
        widths[i] = locked[i] and width or share
    end

    -- share any leftover budget arbitrarily
    budget = budget - (free * share)
    for i = 1, budget do
        widths[i] = widths[i] + 1
    end

    return widths
end

---Allocate splits space equally between every column that is too wide, so a
---long column gets the same width as a much shorter one and its rows get tall.
---Also try two layouts that give the space to the columns which save the most
---lines, and keep whichever needs the fewest lines in total.
---@private
---@param rows render.md.table.Row[]
---@param widths integer[]
---@param desired integer[]
---@param budget integer
---@return integer[]
function Parser:shortest(rows, widths, desired, budget)
    local padding = self.config.padding
    local win = self.context.win
    local text_width = env.win.width(win)
    -- rows drawn over their own text are never shorter than it
    local overlay = self.config.wrap_mode == 'overlay'
        and env.win.get(win, 'wrap')

    -- columns are kept at least as wide as their longest word
    local minimum = {} ---@type integer[]
    for i = 1, #widths do
        minimum[i] = math.max(self.config.min_width, 2 * padding + 1)
    end
    local floors = {} ---@type integer[]
    local cells = {} ---@type render.md.table.Wrap[][]
    for r, row in ipairs(rows) do
        floors[r] = 1
        if overlay then
            local _, source = row.node:line('first', 0)
            floors[r] = math.ceil(str.width(source or '') / text_width)
        end
        cells[r] = {}
        for i, cell in ipairs(row.cells) do
            local wrap = Parser.wrapper(assert(cell.units, 'missing units'))
            minimum[i] = math.max(minimum[i], 2 * padding + wrap.word)
            cells[r][i] = wrap
        end
    end

    ---@param r integer
    ---@param i integer
    ---@param width integer
    ---@return integer
    local function lines(r, i, width)
        local wrap = cells[r][i]
        if not wrap then
            return 1
        end
        local count = wrap.memo[width]
        if not count then
            count = wrap:lines(width - 2 * padding)
            wrap.memo[width] = count
        end
        return count
    end

    ---@param candidate integer[]
    ---@return integer
    local function height(candidate)
        local result = 0
        for r, floor in ipairs(floors) do
            local row_lines = floor
            for i, width in ipairs(candidate) do
                row_lines = math.max(row_lines, lines(r, i, width))
            end
            result = result + row_lines
        end
        return result
    end

    local result, total = widths, height(widths)
    ---@param candidate? integer[]
    local function try(candidate)
        local candidate_total = candidate and height(candidate)
        if candidate_total and candidate_total < total then
            result, total = candidate, candidate_total
        end
    end
    try(Parser.fit(desired, minimum, budget))
    try(Parser.greedy(desired, minimum, budget, floors, lines))
    return result
end

---@class render.md.table.Wrap
---@field widths integer[]
---@field spaces boolean[]
---@field word integer
---@field memo table<integer, integer>
local Wrap = {}
Wrap.__index = Wrap

---@private
---@param units render.md.table.Unit[]
---@return render.md.table.Wrap
function Parser.wrapper(units)
    local self = setmetatable({}, Wrap)
    self.widths = {}
    self.spaces = {}
    self.word = 0
    self.memo = {}
    local word = 0
    for i, unit in ipairs(units) do
        self.widths[i] = unit.width
        self.spaces[i] = str.whitespace(unit.text)
        word = self.spaces[i] and 0 or word + unit.width
        self.word = math.max(self.word, word)
    end
    return self
end

---Number of lines wrap produces at a width, without building them.
---@param width integer
---@return integer
function Wrap:lines(width)
    local widths, spaces = self.widths, self.spaces
    local result = 0
    local first = 1
    while first <= #widths do
        local last = first - 1
        local used = 0
        local space = nil ---@type integer|nil
        while last < #widths and used + widths[last + 1] <= width do
            last = last + 1
            used = used + widths[last]
            if spaces[last] then
                space = last
            end
        end
        if last < first then
            -- unit wider than the column
            return math.huge
        end
        local next_unit = last + 1
        if
            last < #widths
            and not spaces[last + 1]
            and space
            and space > first
        then
            next_unit = space + 1
        end
        result = result + 1
        first = next_unit
        while first <= #widths and spaces[first] do
            first = first + 1 ---@type integer
        end
    end
    return math.max(result, 1)
end

---Columns that fit in an equal share keep their width, the rest start at their
---minimum and split what is left by how much more they want.
---@param desired integer[]
---@param minimum integer[]
---@param budget integer
---@return integer[]?
function Parser.fit(desired, minimum, budget)
    local locked = {} ---@type table<integer, true>
    local free = #desired
    local changed = true
    while changed and free > 0 do
        changed = false
        local share = math.floor(budget / free)
        for i = 1, #desired do
            if not locked[i] and desired[i] <= share then
                locked[i] = true
                budget = budget - desired[i]
                free = free - 1
                changed = true
            end
        end
    end

    local widths = {} ---@type integer[]
    local want = 0
    for i, width in ipairs(desired) do
        if locked[i] then
            widths[i] = width
        else
            widths[i] = minimum[i]
            budget = budget - minimum[i]
            want = want + width - minimum[i]
        end
    end
    if budget < 0 then
        return nil
    end
    if want > 0 then
        local extra = budget
        for i, width in ipairs(desired) do
            if not locked[i] then
                local share = (width - minimum[i]) / want
                widths[i] = widths[i] + math.floor(extra * share)
            end
        end
    end
    return widths
end

---Every column starts at its minimum, then space keeps going to whichever
---column saves the most lines for each character it is given.
---@param desired integer[]
---@param minimum integer[]
---@param budget integer
---@param floors integer[] minimum number of lines for each row
---@param lines fun(row: integer, col: integer, width: integer): integer
---@return integer[]?
function Parser.greedy(desired, minimum, budget, floors, lines)
    local widths = {} ---@type integer[]
    for i, width in ipairs(minimum) do
        widths[i] = width
        budget = budget - width
    end
    if budget < 0 then
        return nil
    end

    -- lines each cell takes at the current widths
    local counts = {} ---@type integer[][]
    local current = 0
    for r, floor in ipairs(floors) do
        counts[r] = {}
        local height = floor
        for i, width in ipairs(widths) do
            counts[r][i] = lines(r, i, width)
            height = math.max(height, counts[r][i])
        end
        current = current + height
    end

    while budget > 0 do
        local best = nil ---@type { i: integer, step: integer, lines: integer, ratio: number }?
        for i = 1, #widths do
            -- height of each row without this column, only it changes below
            local others = {} ---@type integer[]
            for r, floor in ipairs(floors) do
                local height = floor
                for j, count in ipairs(counts[r]) do
                    if j ~= i then
                        height = math.max(height, count)
                    end
                end
                others[r] = height
            end
            local room = math.min(budget, desired[i] - widths[i])
            -- try +1, +2, +4 ... +room so a column on a plateau is not skipped
            local step = 1
            while room > 0 do
                local amount = math.min(step, room)
                local total = 0
                for r, height in ipairs(others) do
                    total = total
                        + math.max(height, lines(r, i, widths[i] + amount))
                end
                local ratio = (current - total) / amount
                if ratio > 0 and (not best or ratio > best.ratio) then
                    best =
                        { i = i, step = amount, lines = total, ratio = ratio }
                end
                if amount == room then
                    break
                end
                step = step * 2
            end
        end
        if not best then
            break
        end
        widths[best.i] = widths[best.i] + best.step
        budget = budget - best.step
        current = best.lines
        for r = 1, #floors do
            counts[r][best.i] = lines(r, best.i, widths[best.i])
        end
    end

    -- nothing saves a line, split what is left by how much more columns want
    local want = 0
    for i, width in ipairs(desired) do
        want = want + width - widths[i]
    end
    if budget > 0 and want > 0 then
        local extra = budget
        for i, width in ipairs(desired) do
            local share = (width - widths[i]) / want
            widths[i] = widths[i] + math.floor(extra * share)
        end
    end
    return widths
end

---@param units render.md.table.Unit[]
---@param width integer
---@return render.md.mark.Line[]
function Parser.wrap(units, width)
    local result = {} ---@type render.md.mark.Line[]
    local first = 1
    while first <= #units do
        local last = first - 1
        local used = 0
        local space = nil ---@type integer|nil
        while last < #units and used + units[last + 1].width <= width do
            last = last + 1
            used = used + units[last].width
            if str.whitespace(units[last].text) then
                space = last
            end
        end
        assert(last >= first, 'table unit exceeds column width')
        local next_unit = last + 1
        if
            last < #units
            and not str.whitespace(units[last + 1].text)
            and space
            and space > first
        then
            last = space - 1
            next_unit = space + 1
        end
        local line = {} ---@type render.md.mark.Line
        for i = first, last do
            local unit = units[i]
            local previous = line[#line]
            if previous and vim.deep_equal(previous[2], unit.highlight) then
                previous[1] = previous[1] .. unit.text
            else
                line[#line + 1] = { unit.text, unit.highlight }
            end
        end
        result[#result + 1] = line
        first = next_unit
        while first <= #units and str.whitespace(units[first].text) do
            first = first + 1 ---@type integer
        end
    end
    return #result > 0 and result or { {} }
end

---@param line render.md.mark.Line
---@param width integer
---@param alignment render.md.table.col.Alignment
---@param padding integer
---@param highlight string
---@return render.md.mark.Line
function Parser.align(line, width, alignment, padding, highlight)
    local extra = width - 2 * padding - str.line_width(line)
    local left = alignment == Parser.Alignment.right and extra
        or alignment == Parser.Alignment.center and math.floor(extra / 2)
        or 0
    local result = { { str.pad(padding + left), highlight } }
    vim.list_extend(result, line)
    result[#result + 1] = { str.pad(padding + extra - left), highlight }
    return result
end

return Parser
