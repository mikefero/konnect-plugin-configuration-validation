local ngx = ngx

local helpers = require "spec.helpers"
local PLUGIN_NAME = "konnect-plugin-configuration-validation"

for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })
      local route = bp.routes:insert({
        paths = { "/konnect/plugin/configuration/validation" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("request", function()
      describe("validation")
        local acl_plugin_schema = [[
          local typedefs = require "kong.db.schema.typedefs"
          return {
            name = "acl",
            fields = {
              { consumer = typedefs.no_consumer },
              { protocols = typedefs.protocols_http },
              { config = {
                  type = "record",
                  fields = {
                    { allow = { type = "array", elements = { type = "string" } } },
                    { deny = { type = "array", elements = { type = "string" } } },
                    { hide_groups_header = { type = "boolean", required = true, default = false } }
                  }
                }
              }
            },
            entity_checks = {
              { only_one_of = { "config.allow", "config.deny" } },
              { at_least_one_of = { "config.allow", "config.deny" } }
            }
          }
        ]]
        local rate_limiting_plugin_schema = [[
          local typedefs = require "kong.db.schema.typedefs"
          local ORDERED_PERIODS = { "second", "minute", "hour", "day", "month", "year"}
          local function validate_periods_order(config)
            for i, lower_period in ipairs(ORDERED_PERIODS) do
              local v1 = config[lower_period]
              if type(v1) == "number" then
                for j = i + 1, #ORDERED_PERIODS do
                  local upper_period = ORDERED_PERIODS[j]
                  local v2 = config[upper_period]
                  if type(v2) == "number" and v2 < v1 then
                    return nil, string.format("The limit for %s(%.1f) cannot be lower than the limit for %s(%.1f)",
                                              upper_period, v2, lower_period, v1)
                  end
                end
              end
            end
            return true
          end
          local function is_dbless()
            local _, database, role = pcall(function()
              return kong.configuration.database,
                    kong.configuration.role
            end)
            return database == "off" or role == "control_plane"
          end
          local policy
          if is_dbless() then
            policy = {
              type = "string",
              default = "local",
              len_min = 0,
              one_of = {
                "local",
                "redis",
              },
            }
          else
            policy = {
              type = "string",
              default = "local",
              len_min = 0,
              one_of = {
                "local",
                "cluster",
                "redis",
              },
            }
          end
          return {
            name = "rate-limiting",
            fields = {
              { protocols = typedefs.protocols_http },
              { config = {
                  type = "record",
                  fields = {
                    { second = { type = "number", gt = 0 }, },
                    { minute = { type = "number", gt = 0 }, },
                    { hour = { type = "number", gt = 0 }, },
                    { day = { type = "number", gt = 0 }, },
                    { month = { type = "number", gt = 0 }, },
                    { year = { type = "number", gt = 0 }, },
                    { limit_by = {
                        type = "string",
                        default = "consumer",
                        one_of = { "consumer", "credential", "ip", "service", "header", "path" },
                    }, },
                    { header_name = typedefs.header_name },
                    { path = typedefs.path },
                    { policy = policy },
                    { fault_tolerant = { type = "boolean", required = true, default = true }, },
                    { redis_host = typedefs.host },
                    { redis_port = typedefs.port({ default = 6379 }), },
                    { redis_password = { type = "string", len_min = 0, referenceable = true }, },
                    { redis_username = { type = "string", referenceable = true }, },
                    { redis_ssl = { type = "boolean", required = true, default = false, }, },
                    { redis_ssl_verify = { type = "boolean", required = true, default = false }, },
                    { redis_server_name = typedefs.sni },
                    { redis_timeout = { type = "number", default = 2000, }, },
                    { redis_database = { type = "integer", default = 0 }, },
                    { hide_client_headers = { type = "boolean", required = true, default = false }, },
                    { error_code = {type = "number", default = 429, gt = 0 }, },
                    { error_message = {type = "string", default = "API rate limit exceeded" }, },
                  },
                  custom_validator = validate_periods_order,
                },
              },
            },
            entity_checks = {
              { at_least_one_of = { "config.second", "config.minute", "config.hour", "config.day", "config.month", "config.year" } },
              { conditional = {
                if_field = "config.policy", if_match = { eq = "redis" },
                then_field = "config.redis_host", then_match = { required = true },
              } },
              { conditional = {
                if_field = "config.policy", if_match = { eq = "redis" },
                then_field = "config.redis_port", then_match = { required = true },
              } },
              { conditional = {
                if_field = "config.limit_by", if_match = { eq = "header" },
                then_field = "config.header_name", then_match = { required = true },
              } },
              { conditional = {
                if_field = "config.limit_by", if_match = { eq = "path" },
                then_field = "config.path", then_match = { required = true },
              } },
              { conditional = {
                if_field = "config.policy", if_match = { eq = "redis" },
                then_field = "config.redis_timeout", then_match = { required = true },
              } },
            },
          }
        ]]

        local acl_configuration = [[
          {
            "name": "acl",
            "config": {
              "allow": [
                "konghq.com"
              ]
            }
          }
        ]]
        local rate_limiting_configuration = [[
          {
            "name": "rate-limiting",
            "config": {
              "second": 5,
              "policy": "local"
            }
          }
        ]]

        it("accepts schema and configuration definition using ACL plugin schema using defaults", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration
            }
          })
          assert.response(r).has.status(200)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            allow = {
              'konghq.com'
            },
            deny = ngx.null,
            hide_groups_header = false
          }, json.config)
        end)

        it("accepts schema and configuration definition using ACL plugin schema with ID", function()
          local acl_configuration_with_id = [[
            {
              "id": "cdc70b55-69f8-4cc2-a3c7-78f418964429",
              "name": "acl",
              "config": {
                "allow": [
                  "konghq.com"
                ]
              }
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration_with_id
            }
          })
          assert.response(r).has.status(200)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            allow = {
              'konghq.com'
            },
            deny = ngx.null,
            hide_groups_header = false
          }, json.config)
          assert.equal("cdc70b55-69f8-4cc2-a3c7-78f418964429", json.id)
        end)

        it("accepts schema and configuration definition using ACL plugin schema with ID and protocols", function()
          local acl_configuration_with_id_and_protocol = [[
            {
              "id": "cdc70b55-69f8-4cc2-a3c7-78f418964429",
              "protocols": [
                "https"
              ],
              "name": "acl",
              "config": {
                "allow": [
                  "konghq.com"
                ]
              }
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration_with_id_and_protocol
            }
          })
          assert.response(r).has.status(200)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            allow = {
              'konghq.com'
            },
            deny = ngx.null,
            hide_groups_header = false
          }, json.config)
          assert.equal("cdc70b55-69f8-4cc2-a3c7-78f418964429", json.id)
          assert.same({
            "https"
          }, json.protocols)
        end)

        it("accepts schema and configuration definition using ACL plugin schema with service", function()
          local acl_configuration_with_service_id = [[
            {
              "service": {
                "id": "cdc70b55-69f8-4cc2-a3c7-78f418964429"
              },
              "name": "acl",
              "config": {
                "allow": [
                  "konghq.com"
                ]
              }
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration_with_service_id
            }
          })
          assert.response(r).has.status(200)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            allow = {
              'konghq.com'
            },
            deny = ngx.null,
            hide_groups_header = false
          }, json.config)
          assert.equal("cdc70b55-69f8-4cc2-a3c7-78f418964429", json.service.id)
        end)

        it("accepts schema and configuration definition using ACL plugin schema with route", function()
          local acl_configuration_with_route_id = [[
            {
              "route": {
                "id": "cdc70b55-69f8-4cc2-a3c7-78f418964429"
              },
              "name": "acl",
              "config": {
                "allow": [
                  "konghq.com"
                ]
              }
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration_with_route_id
            }
          })
          assert.response(r).has.status(200)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            allow = {
              'konghq.com'
            },
            deny = ngx.null,
            hide_groups_header = false
          }, json.config)
          assert.equal("cdc70b55-69f8-4cc2-a3c7-78f418964429", json.route.id)
        end)

        it("accepts schema and configuration definition using rate-limiting plugin schema", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = rate_limiting_plugin_schema,
              configuration = rate_limiting_configuration
            }
          })
          assert.response(r).has.status(200)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            day = ngx.null,
            error_code = 429,
            error_message = 'API rate limit exceeded',
            fault_tolerant = true,
            header_name = ngx.null,
            hide_client_headers = false,
            hour = ngx.null,
            limit_by = 'consumer',
            minute = ngx.null,
            month = ngx.null,
            path = ngx.null,
            policy = 'local',
            redis_database = 0,
            redis_host = ngx.null,
            redis_password = ngx.null,
            redis_port = 6379,
            redis_server_name = ngx.null,
            redis_ssl = false,
            redis_ssl_verify = false,
            redis_timeout = 2000,
            redis_username = ngx.null,
            second = 5,
            year = ngx.null
          }, json.config)
        end)

        it("accepts schema and configuration definition for an already validated configuration using ACL plugin schema", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration
            }
          })
          assert.response(r).has.status(200)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            allow = {
              'konghq.com'
            },
            deny = ngx.null,
            hide_groups_header = false
          }, json.config)
        end)

        it("fails when configuration for schema is not valid", function()
          local configuration = [[
            {
              "name": "acl",
              "config": {
                "invalid": "configuration"
              }
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = configuration
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            code = 2,
            fields = {
              config = {
                invalid = "unknown field",
              },
              ["@entity"] = {
                "exactly one of these fields must be non-empty: 'config.allow', 'config.deny'",
                "at least one of these fields must be non-empty: 'config.allow', 'config.deny'"
              }
            },
            message = "3 schema violations (exactly one of these fields must be non-empty: 'config.allow', " ..
            "'config.deny'; at least one of these fields must be non-empty: 'config.allow', " ..
            "'config.deny'; config.invalid: unknown field)",
            name = "schema violation"
          }, json)
        end)

        it("fails when configuration for unmatched schema", function()
          local configuration = [[
            {
              "name": "acl",
              "config": {}
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = rate_limiting_plugin_schema,
              configuration = configuration
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            code = 2,
            fields = {
              name = "plugin 'acl' not enabled; add it to the 'plugins' configuration property",
            },
            message = "schema violation (name: plugin 'acl' not enabled; add it to the 'plugins' configuration property)",
            name = "schema violation"
          }, json)
        end)

        it("fails when configuration for schema is using invalid protocol", function()
          local acl_configuration_with_invalid_protocol = [[
            {
              "protocols": [
                "ws"
              ],
              "name": "acl",
              "config": {
                "allow": [
                  "konghq.com"
                ]
              }
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration_with_invalid_protocol
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            code = 2,
            fields = {
              protocols = {
                "expected one of: grpc, grpcs, http, https"
              }
            },
            message = "schema violation (protocols.1: expected one of: grpc, grpcs, http, https)",
            name = "schema violation"
          }, json)
        end)

        it("fails when configuration for schema is using consumer and isn't allowed", function()
          local acl_configuration_with_invalid_protocol = [[
            {
              "consumer": {
                "id": "cdc70b55-69f8-4cc2-a3c7-78f418964429"
              },
              "name": "acl",
              "config": {
                "allow": [
                  "konghq.com"
                ]
              }
            }
          ]]
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = acl_configuration_with_invalid_protocol
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            code = 2,
            fields = {
              consumer = "value must be null"
            },
            message = "schema violation (consumer: value must be null)",
            name = "schema violation"
          }, json)
        end)

        it("fails when schema definition is invalid - missing fields", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = [[
                return {
                  name = "invalid-schema-missing-fields",
                  missing_fields = {}
                }
              ]],
              configuration = "{ not, empty }"
            }
          })
          assert.response(r).has.status(400)
        end)

        it("fails when schema definition is invalid - nil function", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = "return schema",
              configuration = "{ not, empty }"
            }
          })
          assert.response(r).has.status(400)
        end)

        it("fails when schema definition is invalid - missing plugin name", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = [[
                return {
                  fields = {
                    { config = { type = "record", fields = {} } }
                  }
                }
              ]],
              configuration = "{ not, empty }"
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            message = "invalid schema for plugin: missing plugin name"
          }, json)
        end)

        it("fails when using invalid method", function()
          local r = client:get("/konnect/plugin/configuration/validation", {})
          assert.response(r).has.status(405)
        end)

        it("fails when using invalid content-type", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "text/html; charset=utf-8"
            },
          })
          assert.response(r).has.status(415)
        end)

        it("fails when body is missing", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
          })
          assert.response(r).has.status(400)
        end)

        it("fails when schema definition is missing", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              configuration = "{ not, empty }"
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            message = "missing schema field"
          }, json)
        end)

        it("fails when schema definition is empty", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = "return",
              configuration = "{ not, empty }"
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            message = "invalid schema for plugin: cannot be empty"
          }, json)
        end)

        it("fails when configuration definition is missing", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = "schema" -- not valid, but isn't loaded before configuration error
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            message = "missing configuration field"
          }, json)
        end)

        it("fails when configuration definition is empty", function()
          local r = client:post("/konnect/plugin/configuration/validation", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              schema = acl_plugin_schema,
              configuration = "{}"
            }
          })
          assert.response(r).has.status(400)
          local json = assert.response(r).has.jsonbody()
          assert.same({
            message = "invalid configuration for plugin: cannot be empty"
          }, json)
        end)
      end)
    end)
  end
end
