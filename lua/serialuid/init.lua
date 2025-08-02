-- serialuid.lua
-- Generate official serialVersionUID for Java classes via serialver

local M = {}

local function run_command(cmd, cwd)
  local opts = { cwd = cwd or nil }
  local result = vim.fn.systemlist(cmd, opts.cwd)
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

local function get_maven_classpath(root)
  local cp_file = root .. "/classpath.txt"
  local _, err = run_command("mvn -f pom.xml compile dependency:build-classpath -Dmdep.outputFile=classpath.txt", root)
  if err then
    print("Failed to build Maven classpath:\n" .. err)
    return nil
  end
  local lines = vim.fn.readfile(cp_file)
  vim.fn.delete(cp_file)
  if #lines == 0 then
    print("Classpath file is empty.")
    return nil
  end
  return root .. "/target/classes:" .. lines[1]
end

local function get_gradle_classpath(root)
  if vim.fn.isdirectory(root .. "/build/classes/java/main") == 1 then
    return root .. "/build/classes/java/main"
  end
  return nil
end

local function extract_fqcn_and_paths(filepath)
  local parts = vim.split(filepath, "/")
  local java_dir_index = nil
  for i, part in ipairs(parts) do
    if part == "java" then
      java_dir_index = i
      break
    end
  end
  if not java_dir_index then return nil, nil, nil end

  local src_path = table.concat(vim.list_slice(parts, 1, java_dir_index), "/")
  local package_parts = vim.list_slice(parts, java_dir_index + 1)
  local class_file = package_parts[#package_parts]
  package_parts[#package_parts] = class_file:gsub(".java$", "")
  local fqcn = table.concat(package_parts, ".")
  local class_file_path = table.concat(package_parts, "/") .. ".java"

  return fqcn, class_file_path, src_path
end

function M.generate()
  local bufname = vim.api.nvim_buf_get_name(0)
  if not bufname or bufname == "" then
    print("Buffer has no name. Save the file first.")
    return
  end

  local fqcn, class_file_path, src_path = extract_fqcn_and_paths(bufname)
  if not fqcn then
    print("Could not resolve fully qualified class name.")
    return
  end

  local project_root = vim.fn.getcwd()
  local build_tool = detect_build_tool(project_root)
  local classpath = nil

  if build_tool == "maven" then
    classpath = get_maven_classpath(project_root)
  elseif build_tool == "gradle" then
    classpath = get_gradle_classpath(project_root)
  end

  local serialver_cmd = nil
  if classpath then
    serialver_cmd = "serialver -classpath " .. vim.fn.shellescape(classpath) .. " " .. fqcn
    local output, serr = run_command(serialver_cmd)
    if serr then
      print("serialver failed (project-aware):\n" .. serr)
    else
      M.insert_uid(output)
      return
    end
  end

  -- VSCode-style fallback
  print("Falling back to isolated javac compile...")
  local javac_cmd = "javac " .. vim.fn.fnameescape(class_file_path)
  local _, err = run_command(javac_cmd, src_path)
  if err then
    print("Compilation failed (isolated):\n" .. err)
    return
  end

  serialver_cmd = "serialver " .. fqcn
  local output, serr = run_command(serialver_cmd, src_path)
  if serr then
    print("serialver failed (fallback):\n" .. serr)
    return
  end

  M.insert_uid(output)
end

function M.insert_uid(output)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
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

