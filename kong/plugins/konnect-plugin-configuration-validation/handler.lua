local kong = kong
local ngx = ngx

local cjson = require "cjson.safe"
local entity = require "kong.db.schema.entity"
local errors = require "kong.db.errors"
local metaschema = require "kong.db.schema.metaschema"
local plugins_definition = require "kong.db.schema.entities.plugins"

local content_type_json = "application/json"

local konnect_plugin_configuration_validation = {
  PRIORITY = 1000,
  VERSION = "0.1"
}

--- Checking the content type of the request to ensure it is valid for the
-- schema validation.
-- @param content_type Content type of the request.
-- @return True if content type is valid; false otherwise.
local function is_valid_content_type(content_type)
  if type(content_type) ~= "string" then
    return false
  end

  if string.find(content_type, content_type_json, 1, true) ~= nil then
    return true
  end
  return false
end

--- Determine if "a thing" is empty or not.
-- @param value Any value; e.g. "a thing".
-- @return True if value is empty; false otherwise.
local function is_empty(value)
  if value == nil
     or value == ngx.null
     or (type(value) == "table" and not next(value))
     or (type(value) == "string" and value == "") then
    return true
  end

  return false
end

--- Check the contents of a plugin schema string representation and ensure that
-- it is valid metaschema. All fields and attributes are validated
-- while executing checks against the entire plugin schema.
-- @param input The string representation of the plugin schema.
-- @return Instantiated plugins subschema entity and loaded plugin schema;
--         otherwise nil with error if validation fails.
local function validate_plugin_schema(input)
  -- Load the input into a compiled Lua function which will represent the
  -- plugin schema for further validations.
  --
  -- Note: "pcall" is used for this operation to ensure proper error handling
  -- for "assert" calls performed in the "load" function.
  local plugin_schema
  local pok, perr = pcall(function()
    local err
    plugin_schema, err = load(input)()
    if err then
      return nil, nil, "error processing load for plugin schema: " .. err
    end
  end)
  if not pok then
    return nil, nil, "error processing load for plugin schema: " .. perr
  end
  if is_empty(plugin_schema) then
    return nil, nil, "invalid schema for plugin: cannot be empty"
  end

  -- Complete the validation of the plugin schema.
  --
  -- Note: "pcall" is used for this operation to ensure proper error handling
  -- for "assert" calls performed in the "MetaSubSchema:validate" function.
  -- When validating the fields of the plugin schema an "assert" is possible.
  local pok, perr = pcall(function()
    local ok, err = metaschema.MetaSubSchema:validate(plugin_schema)
    if not ok then
      return nil, nil, tostring(errors:schema_violation(err))
    end
  end)
  if not pok then
    return nil, nil, "error calling MetaSubSchema:validate: " .. perr
  end

  -- Load the plugin schema for use in configuration validation when
  -- associated with a plugins subschema entity
  local plugins_subschema_entity, err = entity.new(plugins_definition)
  if err then
    return nil, nil, "unable to create plugin entity: " .. err
  end
  local plugin_name = plugin_schema.name
  if is_empty(plugin_name) then
    return nil, nil, "invalid schema for plugin: missing plugin name"
  end
  -- Note: "pcall" is used for this operation to ensure proper error handling
  -- for "assert" calls performed in the "entity:new_subschema" function. When
  -- iterating the arrays/fields of the plugin schema an "assert" is possible.
  pok, perr = pcall(function()
    local ok, err = plugins_subschema_entity:new_subschema(plugin_name, plugin_schema)
    if not ok then
      return nil, nil, "error loading schema for plugin " .. plugin_name .. ": " .. err
    end
  end)
  if not pok then
    return nil, nil, "error validating plugin schema: " .. perr
  end

  return plugins_subschema_entity, plugin_schema
end

--- Check the contents of a plugin schema string representation and ensure that
-- it is valid metaschema along with the validation of the associated
-- configuration. All fields and attributes are validated whiel executing
-- checks against the entire plugin schema and configuraton.
-- @param schema_input The string representation of the plugin schema.
-- @param configuration_input The string representation of the plugin
--                            configuration.
-- @retrun The plugin entity if plugin configuration validation succeeds; error
--         otherwise.
local function validate_plugin_configuration(schema_input, configuration_input)
  -- Validate the plugin schema and create the plugins entity
  local plugins_subschema_entity, plugin_schema, err = validate_plugin_schema(schema_input)
  if err then
    return nil, err
  end

  -- Convert the JSON configuration into a Lua table for validation
  local configuration, err = cjson.decode(configuration_input)
  if err then
    return nil, "unable to json decode configuration: " .. err
  end
  if is_empty(configuration) then
    return nil, "invalid configuration for plugin: cannot be empty"
  end

  -- Process the auto fields; ensuring the entire plugin configuration is
  -- returned when being validated.
  --
  -- Note: A base configuration of the entity is applied as we are not
  --       validating the base entity only the configuration of the plugin
  --       schema.
  local plugin_name = plugin_schema.name
  local plugin_entity, err = plugins_subschema_entity:process_auto_fields(configuration, "insert")
  if err then
    return nil, "unable to process auto fields for plugin " .. plugin_name .. ": " .. err
  end

  -- Valdate the configuration
  local _, err = plugins_subschema_entity:validate_insert(plugin_entity)
  if err then
    local schema_violation_error = errors:schema_violation(err)
    local flat_message, err = cjson.encode(schema_violation_error)
    if err then
      return nil, "unable to validate plugin " .. plugin_name .. ": " .. schema_violation_error
    else
      return nil, flat_message
    end
  end

  return plugin_entity, nil
end

--- Access handler for the Konnect Plugin Configuration Validation plugin. This
-- handler will validate plugin schema and associated configuration via a POST
-- method and process the JSON body utilizing the "schema" and "configuration"
-- fields. On sucessful plugin configurationvalidation the JSON of the plugin
-- configuration will be returned; otherwise the JSON body will contain an error
-- message along with an appropriate status code.
function konnect_plugin_configuration_validation:access(conf)
  if kong.request.get_method() ~= "POST" then
    return kong.response.error(405) -- Method not allowed
  end
  if not is_valid_content_type(kong.request.get_header("Content-Type")) then
    return kong.response.error(415) -- Unsupported media type
  end

  local body, err = kong.request.get_body()
  if err then
    return kong.response.error(400, "unable to get request body: " .. err) -- Bad request
  end
  if is_empty(body.schema) then
    return kong.response.error(400, "missing schema field") -- Bad request
  end
  if is_empty(body.configuration) then
    return kong.response.error(400, "missing configuration field") -- Bad request
  end
  local plugin_schema = body.schema
  local plugin_configuration = body.configuration
  local plugin_entity, err = validate_plugin_configuration(plugin_schema, plugin_configuration)
  if err then
    -- Determine if err is a JSON object or a regular string
    local _, derr = cjson.decode(err)
    if derr then
      return kong.response.error(400, err) -- Bad request  
    end

    -- Ensure the error response is at the root of the JSON object
    return kong.response.exit(400, err) -- Bad request
  end

  -- Return the plugin entity
  return kong.response.exit(200, plugin_entity) -- OK
end

return konnect_plugin_configuration_validation
