local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "konnect-plugin-configuration-validation"


local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { protocols = typedefs.protocols_http },
    { config = { type = "record", fields = {} } }
  }
}

return schema
