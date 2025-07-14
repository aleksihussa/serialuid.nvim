-- serialuid.lua
-- Generate official serialVersionUID for Java classes via serialver

local M = {}

local function run_command(cmd)
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(result, "\n")
  end
  return result, nil
end

local function detect_build_tool(root)
  if vim.fn.filereadable(root .. "/pom.xml") == 1 then return "maven" end
  if vim.fn.filereadable(root .. "/build.gradle") == 1 or vim.fn.filereadable(root .. "/build.gradle.kts") == 1 then return "gradle" end
  return nil
end

local function get_fqcn_and_classpath(filepath, content)
  local parts = vim.split(filepath, "/")
  local java_index = nil
  for i, part in ipairs(parts) do
    if part == "java" then
      java_index = i
      break
    end
  end
  if not java_index or java_index >= #parts then return nil, nil end

  local root = table.concat(vim.list_slice(parts, 1, java_index - 2), "/")
  local build_tool = detect_build_tool(root)

  if build_tool == "maven" then
    run_command("mvn -f " .. root .. "/pom.xml compile")
  elseif build_tool == "gradle" then
    run_command("cd " .. root .. " && ./gradlew classes")
  end

  local class_parts = vim.list_slice(parts, java_index + 1)
  local class_file = class_parts[#class_parts]
  class_parts[#class_parts] = class_file:gsub(".java$", "")
  local declared_pkg = content:match("package%s+([%w%._]+)%s*;")
  local fqcn = declared_pkg and (declared_pkg .. "." .. class_parts[#class_parts]) or table.concat(class_parts, ".")

  local candidate_classpaths = {
    root .. "/target/classes",
    root .. "/build/classes/java/main",
  }

  for _, cp in ipairs(candidate_classpaths) do
    if vim.fn.isdirectory(cp) == 1 then
      return fqcn, cp
    end
  end

  return fqcn, nil
end

local function get_package(content)
  return content:match("package%s+([%w%._]+)%s*;")
end

function M.generate()
  local bufname = vim.api.nvim_buf_get_name(0)
  if not bufname or bufname == "" then
    print("Buffer has no name. Save the file first.")
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")

  local fqcn, classpath = get_fqcn_and_classpath(bufname, content)
  if fqcn and classpath then
    local serialver_cmd = "serialver -classpath " .. vim.fn.shellescape(classpath) .. " " .. fqcn
    local output, serr = run_command(serialver_cmd)
    if serr then
      print("serialver failed (project-aware):\n" .. serr)
    else
      M.insert_uid(lines, output)
    end
  else
    local tmp_dir = vim.fn.stdpath("data") .. "/serialuid_fallback"
    vim.fn.mkdir(tmp_dir, "p")
    local compile_cmd = "javac -d " .. tmp_dir .. " " .. vim.fn.shellescape(bufname)
    local _, err = run_command(compile_cmd)
    if err then
      print("Compilation failed (fallback):\n" .. err)
      return
    end

    local class_name = bufname:match("([^/]+)%.java$") or "TempClass"
    local pkg = get_package(content)
    local fallback_fqcn = pkg and (pkg .. "." .. class_name) or class_name

    local serialver_cmd = "serialver -classpath " .. vim.fn.shellescape(tmp_dir) .. " " .. fallback_fqcn
    local output, serr = run_command(serialver_cmd)
    if serr then
      print("serialver failed (fallback):\n" .. serr)
      return
    end

    M.insert_uid(lines, output)
    vim.fn.delete(tmp_dir, "rf")
  end
end

function M.insert_uid(lines, output)
  local uid = output[1] and output[1]:match("serialVersionUID%s*=%s*(%d+)L;")
  if not uid then
    print("Could not parse UID.")
    return
  end

  local insert_line = "    private static final long serialVersionUID = " .. uid .. "L;"
  local replaced = false

  for i, l in ipairs(lines) do
    if l:match("serialVersionUID") then
      lines[i] = insert_line
      replaced = true
      break
    end
  end

  if not replaced then
    for i, l in ipairs(lines) do
      if l:match("class%s+") then
        table.insert(lines, i + 1, insert_line)
        replaced = true
        break
      end
    end
  end

  if replaced then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    print("serialVersionUID inserted/updated: " .. uid)
  else
    print("Could not insert UID.")
  end
end

return M

