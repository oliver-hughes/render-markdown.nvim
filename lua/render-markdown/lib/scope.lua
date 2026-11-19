---Namespaces scoped to a single window, for marks that depend on where that
---window wraps lines. Scoping a namespace to windows is an experimental
---Neovim API (nvim__ns_set), without it everything stays in the shared
---namespace.
---@class render.md.Scope
local M = {}

M.enabled = type(vim.api.nvim__ns_set) == 'function'

---@private
---@type table<integer, integer>
M.wins = {}

---@private
---@type integer[]
M.free = {}

---@private
---@type integer
M.count = 0

---@param win integer
---@return integer
function M.get(win)
    local ns = M.wins[win]
    if not ns then
        ns = table.remove(M.free)
        if not ns then
            M.count = M.count + 1
            local name = ('render-markdown.nvim.win.%d'):format(M.count)
            ns = vim.api.nvim_create_namespace(name)
        end
        vim.api.nvim__ns_set(ns, { wins = { win } })
        M.wins[win] = ns
    end
    return ns
end

---@param win integer
---@return integer?
function M.find(win)
    return M.wins[win]
end

---@param buf integer
function M.clear(buf)
    for _, ns in pairs(M.wins) do
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
end

---Frees the namespace of a window that is closing. Extmark ids start again
---once a namespace is cleared, so any ids still held for it must already be
---forgotten.
---@param win integer
function M.release(win)
    local ns = M.wins[win]
    if not ns then
        return
    end
    M.wins[win] = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
    M.free[#M.free + 1] = ns
end

return M
