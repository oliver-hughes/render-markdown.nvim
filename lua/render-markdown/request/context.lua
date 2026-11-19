local env = require('render-markdown.lib.env')
local scope = require('render-markdown.lib.scope')
local str = require('render-markdown.lib.str')

---@class render.md.request.Context
---@field buf integer
---@field win integer
---@field wins? integer[] windows that tables are drawn for one at a time
---@field config render.md.buf.Config
---@field view render.md.request.View
---@field callout render.md.request.Callout
---@field checkbox render.md.request.Checkbox
---@field conceal render.md.request.Conceal
---@field highlights render.md.request.Highlights
---@field inline render.md.request.Inline
---@field latex render.md.request.Latex
---@field used render.md.request.Used
local Context = {}
Context.__index = Context

---@param buf integer
---@param win integer
---@param config render.md.buf.Config
---@param view render.md.request.View
---@return render.md.request.Context
function Context.new(buf, win, config, view)
    local self = setmetatable({}, Context)
    self.buf = buf
    self.win = win
    self.config = config
    self.view = view
    self.callout = require('render-markdown.request.callout').new()
    self.checkbox = require('render-markdown.request.checkbox').new()
    self.conceal = require('render-markdown.request.conceal').new(self)
    self.highlights =
        require('render-markdown.request.highlights').new(buf, view)
    self.inline = require('render-markdown.request.inline').new()
    self.latex = require('render-markdown.request.latex').new()
    self.used = require('render-markdown.request.used').new()
    return self
end

---The same request for drawing into one window. Everything is shared except
---the rows taken by borders, which each window takes for itself.
---@param win integer
---@return render.md.request.Context
function Context:window(win)
    ---@type render.md.request.Context
    local result = setmetatable({}, { __index = self })
    result.win = win
    result.used = self.used:copy()
    return result
end

---@param body? render.md.node.Body
---@return integer
function Context:width(body)
    if not body then
        return 0
    end
    return str.width(body.text)
        + self.inline:width(body)
        - self.conceal:get(body)
end

---@class render.md.request.context.Manager
local M = {}

---@private
---@type table<integer, render.md.request.Context>
M.cache = {}

---@param buf integer
---@param win integer
---@return boolean
function M.contains(buf, win)
    local context = M.cache[buf]
    if not context then
        return false
    end
    -- tables are drawn for each window, a window opened or closed on the
    -- buffer is not always resized so may not have been drawn yet
    if context.wins and not vim.deep_equal(context.wins, M.wins(buf)) then
        return false
    end
    return context.view:contains(win)
end

---@param buf integer
---@param win integer
---@param config render.md.buf.Config
---@return render.md.request.Context?
function M.new(buf, win, config)
    local pipe_table = config.pipe_table
    local tables = pipe_table.enabled
        and pipe_table.wrap
        and pipe_table.wrap_mode == 'overlay'
    local view = require('render-markdown.request.view').new(buf, tables)
    local context = Context.new(buf, win, config, view)
    -- rows drawn over are measured where a window wraps them, with marks
    -- scoped to a window each window can be drawn for its own width
    if tables and scope.enabled then
        context.wins = M.wins(buf)
    end
    M.cache[buf] = context
    return context
end

---@private
---@param buf integer
---@return integer[]
function M.wins(buf)
    local wins = env.buf.wins(buf)
    table.sort(wins)
    return wins
end

---@param buf integer
---@return render.md.request.Context
function M.get(buf)
    return assert(M.cache[buf], 'missing request context')
end

return M
