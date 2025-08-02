-- serialuid.lua
-- Neovim plugin to generate serialVersionUID via JDT LS (no serialver, no shell hacks)

-- serialuid.lua
-- Neovim plugin to generate serialVersionUID using JDT LS-resolved classpath and serialver

local M = {}

local function run_command(cmd)
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(result, "\n")
  end
  return result, nil
end

-- Request JDT LS to resolve the classpath for current workspace
local function get_jdtls_classpath(callback)
  local params = {
    command = "java.project.resolveClasspath",
    arguments = { vim.fn.getcwd() }
  }
  vim.lsp.buf_request(0, "workspace/executeCommand", params, function(err, result)
    if err then
      print("Error resolving classpath: " .. err.message)
      return
    end

    if not result or vim.tbl_isempty(result) then
      print("No classpath returned by JDT LS.")
      return
    end

    callback(result)
  end)
end

local function extract_fqcn()
  local bufname = vim.api.nvim_buf_get_name(0)
  if not bufname or bufname == "" then
    print("Buffer has no name.")
    return nil
  end

  local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local pkg = content:match("package%s+([%w%.]+)%s*;")
  local classname = content:match("class%s+(%w+)")
  if not classname then
    print("Could not find class name.")
    return nil
  end

  if pkg then
    return pkg .. "." .. classname
  else
    return classname
  end
end

function M.generate()
  local fqcn = extract_fqcn()
  if not fqcn then return end

  get_jdtls_classpath(function(classpath_entries)
    local classpath = table.concat(classpath_entries, ":")

    -- Ensure project is compiled
    local _, compile_err = run_command("mvn compile")
    if compile_err then
      print("Compilation failed:\n" .. compile_err)
      return
    end

    local serialver_cmd = "serialver -classpath " .. vim.fn.shellescape(classpath) .. " " .. fqcn
    local output, err = run_command(serialver_cmd)
    if err then
      print("serialver failed:\n" .. err)
      return
    end

    for _, line in ipairs(output) do
      local uid = line:match("serialVersionUID%s*=%s*(%d+)L;")
      if uid then
        local insert_line = "    private static final long serialVersionUID = " .. uid .. "L;"
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for i, l in ipairs(lines) do
          if l:match("class%s+") then
            table.insert(lines, i + 1, insert_line)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            print("serialVersionUID inserted: " .. uid)
            return
          end
        end
      end
    end
    print("Could not parse UID from serialver output.")
  end)
end

return M
