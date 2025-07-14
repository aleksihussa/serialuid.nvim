# serialuid.nvim

A lightweight Neovim plugin to generate and insert official `serialVersionUID` values for Java classes, using the JDK's `serialver` tool.

## ✨ Features

- Uses `javac` + `serialver` to generate the correct UID
- Inserts or updates the `serialVersionUID` line
- Minimal dependencies, works offline
- MIT licensed

## 🔧 Requirements

- JDK (`javac` and `serialver`) in your PATH

## 📦 Installation (lazy.nvim)
TODO
```lua
{
  "aleksihussa/serialuid.nvim",
  config = function()
    vim.api.nvim_create_user_command(\"GenerateSerialUID\", function()
      require(\"serialuid\").generate()
    end, {})

    vim.keymap.set(\"n\", \"<leader>gs\", function()
      require(\"serialuid\").generate()
    end, { desc = \"Generate serialVersionUID\" })
  end
}

