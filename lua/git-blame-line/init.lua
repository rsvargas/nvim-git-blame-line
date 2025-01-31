-- Basically a translation of the original plugin to lua
-- original one: https://github.com/tveskag/nvim-blame-line/
--
--

local api = vim.api

local M = {}

local did_init = false
M.enabled = false

M.git_format = "%an(%ar) %s"
M.not_yet_committed_message = "Not yet committed"
M.highlight = "Comment"
M.debounce_time = 200

local function git_toplevel()
  if vim.bo.buftype ~= "" then -- not a file
    return nil
  end
  if vim.b.blame_line_toplevel ~= nil then -- cache
    return vim.b.blame_line_toplevel
  end
  local this_path = vim.fn.expand("%:p:h")
  local val = vim.fn.systemlist("cd " .. this_path .. "&& git rev-parse --show-toplevel")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  vim.b.blame_line_toplevel = val[1]
  return val[1]
end

local function git_file_path()
  if vim.b.blame_line_file ~= nil then -- cache
    return vim.b.blame_line_file
  end
  local toplevel = git_toplevel()
  if toplevel == nil then
    return nil
  end
  local escaped_toplevel = vim.fn.escape(toplevel .. "/", ".")
  local full_file = vim.fn.expand("%:p")
  local relative_file = vim.fn.substitute(full_file, escaped_toplevel, "", "")
  local cmd = "cd " .. git_toplevel() .. "; git cat-file -e HEAD:" .. relative_file

  local _ = vim.fn.system(cmd) -- file exists?
  if vim.v.shell_error ~= 0 then
    -- TODO: disable for this buffer?
    return nil
  end
  vim.b.blame_line_file = relative_file
  return relative_file
end

local function get_formatted_commit(commit)
  local cmd = "cd " .. git_toplevel() .. "; git show -s --format='" .. M.git_format .. "' " .. commit
  local val = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return val[1]
end

local function get_current_pos_data()
  local line = vim.fn.line(".")
  local file = git_file_path()
  if file == nil or (#file == 0) then
    return nil
  end
  local bufnr = api.nvim_get_current_buf()
  local cmd = "cd "
    .. git_toplevel()
    .. "; git annotate -L "
    .. line
    .. ","
    .. line
    .. " -M --porcelain --contents - "
    .. file
  local blame = vim.fn.systemlist(cmd, bufnr)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local commit = blame[1]:sub(1, 40)
  local annotation
  if commit == "0000000000000000000000000000000000000000" then
    annotation = M.not_yet_committed_message
  else
    annotation = get_formatted_commit(commit)
  end

  local result = {
    commit = commit,
    repo = git_toplevel(),
    file = file,
    line = line,
    bufnr = bufnr,
    annotation = annotation
  }

  return result
end

local function annotate_line(bufnr, line, annotation)
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, 0, -1)
  vim.api.nvim_buf_set_extmark(
    bufnr,
    M.namespace_id,
    line - 1,
    0,
    { hl_mode = "combine", virt_text = { { annotation, M.highlight } } }
  )
end

local function debounce_func(func, ms)
  ms = ms or 200
  local timer = vim.loop.new_timer()
  return function()
    timer:stop()
    timer:start(
      ms,
      0,
      vim.schedule_wrap(function()
        func()
      end)
    )
  end
end

function M.setup()
  -- TODO: handle config (enable, git_format, not_yet_committed_message, highlight)
  if did_init then
    return
  end
  api.nvim_create_user_command("BlameLineEnable", M.enable, {})
  api.nvim_create_user_command("BlameLineDisable", M.disable, {})
  api.nvim_create_user_command("BlameLineToggle", M.toggle, {})
  api.nvim_create_user_command("BlameLineReload", M.reload, {})

  M.namespace_id = api.nvim_create_namespace("git-blame-line")

  did_init = true

  M.enable()
end

function M.do_blame_line()
  local data = get_current_pos_data()
  if data == nil then
    return
  end
  -- vim.print(data)
  annotate_line(data.bufnr, data.line, data.annotation)
end

function M.enable()
  if M.enabled then
    return
  end
  M.au_group = api.nvim_create_augroup("git-blame-line", { clear = true })
  api.nvim_create_autocmd("CursorMoved", {
    group = M.au_group,
    callback = debounce_func(M.do_blame_line, M.debounce_time),
  })

  M.enabled = true
end

function M.disable()
  if not M.enabled then
    return
  end
  api.nvim_del_augroup_by_id(M.au_group)

  M.enabled = false
end

function M.toggle()
  if M.enabled then
    M.disable()
  else
    M.enable()
  end
  vim.notify("git-blame-line is " .. (M.enabled and "enabled" or "disabled"))
end

function M.reload()
  did_init = false
  package.loaded["git-blame-line"] = nil
  print(require("git-blame-line").setup())
end

return M

-- vim: ts=2 sts=2 sw=2 et
