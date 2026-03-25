local t = require("tests.test_helper")
local generators = require("nx.generators")

-- Sample `nx list` text output
local sample_nx_list_text = [[

>  NX   Local workspace plugins:

   my-plugin (generators)

>  NX   Installed plugins:

   @nx/react (executors,generators)
   @nx/node (executors,generators)
   @nx/eslint (executors)
   @nx/jest (executors)

]]

-- Sample `nx list @nx/react` text output
local sample_plugin_detail = [[

>  NX   Capabilities in @nx/react:

  GENERATORS

  application : Create a React application
  component : Create a React component
  library : Create a React library
  hook : Create a React hook

  EXECUTORS

  build : Build a React application
  serve : Serve a React application

]]

-- Sample `nx list my-plugin` text output (local plugin)
local sample_local_plugin_detail = [[

>  NX   Capabilities in my-plugin:

  GENERATORS

  my-generator : Generate a custom thing
  util-lib : Create a utility library

]]

-- Sample JSON format (fallback)
local sample_list_json = [[{
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

t.describe("generators.parse_plugin_names", function()
  t.it("extracts plugin names that have generators", function()
    local names = generators.parse_plugin_names(sample_nx_list_text)
    t.assert_eq(3, #names)
    t.assert_eq("my-plugin", names[1])
    t.assert_eq("@nx/react", names[2])
    t.assert_eq("@nx/node", names[3])
  end)

  t.it("excludes plugins without generators", function()
    local names = generators.parse_plugin_names(sample_nx_list_text)
    for _, name in ipairs(names) do
      t.assert_true(name ~= "@nx/eslint", "should not include @nx/eslint")
      t.assert_true(name ~= "@nx/jest", "should not include @nx/jest")
    end
  end)
end)

t.describe("generators.parse_plugin_generators", function()
  t.it("extracts generators from plugin detail text", function()
    local gens = generators.parse_plugin_generators(sample_plugin_detail, "@nx/react")
    t.assert_eq(4, #gens)
    t.assert_eq("application", gens[1].name)
    t.assert_eq("Create a React application", gens[1].description)
    t.assert_eq("@nx/react", gens[1].collection)
  end)

  t.it("extracts local plugin generators", function()
    local gens = generators.parse_plugin_generators(sample_local_plugin_detail, "my-plugin")
    t.assert_eq(2, #gens)
    t.assert_eq("my-generator", gens[1].name)
    t.assert_eq("Generate a custom thing", gens[1].description)
    t.assert_eq("my-plugin", gens[1].collection)
  end)

  t.it("does not include executors", function()
    local gens = generators.parse_plugin_generators(sample_plugin_detail, "@nx/react")
    for _, g in ipairs(gens) do
      t.assert_true(g.name ~= "build", "should not include executor 'build'")
      t.assert_true(g.name ~= "serve", "should not include executor 'serve'")
    end
  end)
end)

t.describe("generators.parse_collections (JSON fallback)", function()
  t.it("extracts collections from JSON format", function()
    local result = generators.parse_collections(sample_list_json)
    t.assert_eq(2, #result)
    t.assert_eq("@nx/react", result[1].name)
    t.assert_eq(3, #result[1].generators)
  end)

  t.it("handles array-of-strings format", function()
    local real_format = [[{
      "plugins": [
        {
          "name": "@nx/angular",
          "capabilities": {
            "generators": ["application", "library"],
            "executors": ["build"]
          }
        }
      ]
    }]]
    local result = generators.parse_collections(real_format)
    t.assert_eq(1, #result)
    t.assert_eq(2, #result[1].generators)
  end)

  t.it("returns empty table on invalid JSON", function()
    local result = generators.parse_collections("not json")
    t.assert_eq(0, #result)
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
