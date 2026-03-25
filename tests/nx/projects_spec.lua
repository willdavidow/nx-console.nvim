local t = require("tests.test_helper")
local projects = require("nx.projects")

local sample_project_list = '["my-app","ui-components","data-access-users"]'

local sample_project_detail = [[{
  "name": "my-app",
  "root": "apps/my-app",
  "projectType": "application",
  "targets": {
    "build": { "executor": "@nx/webpack:webpack" },
    "serve": { "executor": "@nx/webpack:dev-server" },
    "test": { "executor": "@nx/jest:jest" },
    "lint": { "executor": "@nx/eslint:lint" }
  }
}]]

t.describe("projects.parse_project_list", function()
  t.it("parses JSON array of project names", function()
    local result = projects.parse_project_list(sample_project_list)
    t.assert_eq(3, #result)
    t.assert_eq("my-app", result[1])
    t.assert_eq("ui-components", result[2])
  end)

  t.it("returns empty table on invalid JSON", function()
    local result = projects.parse_project_list("not json")
    t.assert_eq(0, #result)
  end)
end)

t.describe("projects.parse_project_detail", function()
  t.it("parses project detail JSON", function()
    local detail = projects.parse_project_detail(sample_project_detail)
    t.assert_eq("my-app", detail.name)
    t.assert_eq("apps/my-app", detail.root)
    t.assert_eq("application", detail.type)
    t.assert_eq(4, #detail.targets)
  end)

  t.it("extracts target names and executors", function()
    local detail = projects.parse_project_detail(sample_project_detail)
    local build = nil
    for _, tgt in ipairs(detail.targets) do
      if tgt.name == "build" then build = tgt end
    end
    t.assert_true(build ~= nil, "expected to find build target")
    t.assert_eq("@nx/webpack:webpack", build.executor)
  end)

  t.it("classifies project type correctly", function()
    local detail = projects.parse_project_detail(sample_project_detail)
    t.assert_eq("application", detail.type)
  end)
end)

t.done()
