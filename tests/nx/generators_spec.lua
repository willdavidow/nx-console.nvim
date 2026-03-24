local t = require("tests.test_helper")
local generators = require("nx.generators")

local sample_list = [[{
  "plugins": [
    {
      "name": "@nx/react",
      "capabilities": {
        "generators": {
          "application": { "description": "Create a React application" },
          "component": { "description": "Create a React component" },
          "library": { "description": "Create a React library" }
        }
      }
    },
    {
      "name": "@nx/node",
      "capabilities": {
        "generators": {
          "application": { "description": "Create a Node application" }
        }
      }
    }
  ]
}]]

local sample_schema = [[{
  "name": "component",
  "collection": "@nx/react",
  "description": "Create a React component",
  "schema": {
    "properties": {
      "name": {
        "type": "string",
        "description": "The name of the component",
        "$default": { "$source": "argv", "index": 0 }
      },
      "directory": {
        "type": "string",
        "description": "Directory where the component is placed"
      },
      "style": {
        "type": "string",
        "description": "The file extension for styles",
        "default": "css",
        "enum": ["css", "scss", "less", "none"]
      },
      "export": {
        "type": "boolean",
        "description": "Export the component from the barrel file",
        "default": true
      },
      "flat": {
        "type": "boolean",
        "description": "Create component at directory root"
      }
    },
    "required": ["name"]
  }
}]]

t.describe("generators.parse_collections", function()
  t.it("extracts collection names and generator counts", function()
    local result = generators.parse_collections(sample_list)
    t.assert_eq(2, #result)
    t.assert_eq("@nx/react", result[1].name)
    t.assert_eq(3, #result[1].generators)
    t.assert_eq("@nx/node", result[2].name)
    t.assert_eq(1, #result[2].generators)
  end)

  t.it("extracts generator names and descriptions", function()
    local result = generators.parse_collections(sample_list)
    local react = result[1]
    local found = false
    for _, g in ipairs(react.generators) do
      if g.name == "component" then
        t.assert_eq("Create a React component", g.description)
        found = true
      end
    end
    t.assert_true(found, "expected component generator")
  end)

  t.it("returns empty table on invalid JSON", function()
    local result = generators.parse_collections("not json")
    t.assert_eq(0, #result)
  end)

  t.it("handles array-of-strings format from real nx list --json", function()
    local real_format = [[{
      "plugins": [
        {
          "name": "@nx/angular",
          "version": "18.0.0",
          "capabilities": {
            "generators": ["application", "library", "component"],
            "executors": ["build", "serve"]
          }
        }
      ]
    }]]
    local result = generators.parse_collections(real_format)
    t.assert_eq(1, #result)
    t.assert_eq("@nx/angular", result[1].name)
    t.assert_eq(3, #result[1].generators)
    t.assert_eq("application", result[1].generators[1].name)
  end)
end)

t.describe("generators.parse_schema", function()
  t.it("extracts fields with types and defaults", function()
    local fields = generators.parse_schema(sample_schema)
    t.assert_eq(5, #fields)
  end)

  t.it("marks required fields", function()
    local fields = generators.parse_schema(sample_schema)
    local name_field = nil
    for _, f in ipairs(fields) do
      if f.name == "name" then name_field = f end
    end
    t.assert_true(name_field ~= nil)
    t.assert_true(name_field.required)
  end)

  t.it("extracts enum options", function()
    local fields = generators.parse_schema(sample_schema)
    local style_field = nil
    for _, f in ipairs(fields) do
      if f.name == "style" then style_field = f end
    end
    t.assert_true(style_field ~= nil)
    t.assert_eq("enum", style_field.type)
    t.assert_eq(4, #style_field.options)
    t.assert_eq("css", style_field.default)
  end)

  t.it("extracts boolean fields with defaults", function()
    local fields = generators.parse_schema(sample_schema)
    local export_field = nil
    for _, f in ipairs(fields) do
      if f.name == "export" then export_field = f end
    end
    t.assert_true(export_field ~= nil)
    t.assert_eq("boolean", export_field.type)
    t.assert_eq(true, export_field.default)
  end)
end)

t.done()
