local PLUGIN_NAME = "konnect-plugin-configuration-validation"

local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end

describe(PLUGIN_NAME .. ": (schema)", function()
  it("accepts an empty configuration", function()
    local ok, err = validate({})
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("fails when there is a configuration", function()
    local ok, err = validate({
      configuration = "configuration"
    })
    assert.is_same({
      ["config"] = {
        ["configuration"] = "unknown field"
      }
    }, err)
    assert.is_falsy(ok)
  end)
end)
