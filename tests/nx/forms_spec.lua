local t = require("tests.test_helper")
local forms = require("nx.forms")

local sample_fields = {
  { name = "name", type = "string", description = "Component name", required = true },
  { name = "style", type = "enum", description = "Style type", default = "css", options = { "css", "scss", "none" } },
  { name = "export", type = "boolean", description = "Export from barrel", default = true },
}

t.describe("forms.build_cli_args", function()
  t.it("builds args from field values", function()
    local args = forms.build_cli_args({
      { name = "name", value = "MyComponent" },
      { name = "style", value = "scss" },
      { name = "export", value = true },
    })
    t.assert_true(vim.tbl_contains(args, "--name=MyComponent"))
    t.assert_true(vim.tbl_contains(args, "--style=scss"))
    t.assert_true(vim.tbl_contains(args, "--export"))
  end)

  t.it("uses --no- prefix for false booleans", function()
    local args = forms.build_cli_args({
      { name = "export", value = false },
    })
    t.assert_true(vim.tbl_contains(args, "--no-export"))
  end)

  t.it("skips empty string values", function()
    local args = forms.build_cli_args({
      { name = "name", value = "" },
      { name = "style", value = "css" },
    })
    t.assert_eq(1, #args)
  end)
end)

t.describe("forms.apply_defaults", function()
  t.it("applies defaults to fields", function()
    local fields = forms.apply_defaults(sample_fields)
    local style = nil
    for _, f in ipairs(fields) do
      if f.name == "style" then style = f end
    end
    t.assert_eq("css", style.value)
  end)

  t.it("leaves required fields without defaults as empty", function()
    local fields = forms.apply_defaults(sample_fields)
    local name = nil
    for _, f in ipairs(fields) do
      if f.name == "name" then name = f end
    end
    t.assert_eq("", name.value)
  end)
end)

t.done()
