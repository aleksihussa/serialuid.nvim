-- serialuid.lua
-- Neovim plugin to generate serialVersionUID via JDT LS (no serialver, no shell hacks)

local M = {}

-- Helper to trigger CodeActions and auto-apply "Add serialVersionUID" if found
function M.generate()
  local params = vim.lsp.util.make_range_params()
  params.context = {
    diagnostics = {},
    only = { "source.generate.serialVersionUID" } -- Explicitly target serialVersionUID generation
  }

  vim.lsp.buf_request(0, "textDocument/codeAction", params, function(err, result, ctx)
    if err then
      print("Error while requesting CodeAction: " .. err.message)
      return
    end

    if not result or vim.tbl_isempty(result) then
      print("No serialVersionUID CodeAction available.")
      return
    end

    for _, action in pairs(result) do
      if action.title:lower():match("serialversionuid") then
        -- Some actions are commands, others have edits
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit, vim.lsp.get_client_by_id(ctx.client_id).offset_encoding)
        elseif action.command then
          vim.lsp.buf.execute_command(action.command)
        end
        print("serialVersionUID generated and inserted.")
        return
      end
    end

    print("serialVersionUID CodeAction not found in available actions.")
  end)
end

return M

