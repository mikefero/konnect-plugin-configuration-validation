[![Unix build](https://img.shields.io/github/actions/workflow/status/mikefero/konnect-plugin-configuration-validation/test.yml?branch=main&label=Test&logo=lua)](https://github.com/mikefero/konnect-plugin-configuration-validation/actions/workflows/test.yml)
[![Luacheck](https://github.com/mikefero/konnect-plugin-configuration-validation/workflows/Lint/badge.svg)](https://github.com/mikefero/konnect-plugin-configuration-validation/actions/workflows/lint.yml)

# Konnect Plugin Configuration Validation

Validate Kong Gateway plugin configuration against a supplied plugin schema
using the Konnect Plugin Configuration Validation plugin. This plugin, when
attached to a route, will only accept a JSON payload which must contain a field
`schema` with a string representation of a Kong Gateway plugin schema to and a
field `configuration` with a string representation of a Kong Gateway
configuration for the supplied plugin schema to validate.

```
{
  "schema": "<kong-gateway-plugin-schema>"
  "configuration": "<kong-gateway-configuration-schema>"
}
```

## Configuration

While this plugin can be configured globally, it will have no effect and will
not perform plugin configuration validation; ensure this plugin is configured on a
route.

### Enabling the Plugin on a Route

Configure this plugin on a
[Route](https://docs.konghq.com/latest/admin-api/#Route-object) by using the
Kong Gateway admin API:

```
curl -X POST http://kong:8001/routes \
  --data 'name=konnect-plugin-configuration-validation' \
  --data 'paths[]=/konnect/plugin/configuration/validation'

curl -X POST http://kong:8001/routes/konnect-plugin-configuration-validation/plugins \
  --data 'name=konnect-plugin-configuration-validation'
```

## Validation of a Kong Gateway Plugin Configuration

In order to properly validate a Kong Gateway plugin configuration the string
representation must be properly escaped before adding it to the `schema` and
`configuration` field in the JSON body of the request. To validate a Kong
Gateway plugin configuration use the proxy/client API using a `POST` method:

```
curl -X POST http://kong:8000/konnect/plugin/configuration/validation \
  --header "content-type:application/json" \
  --data '{"schema": "local typedefs = require \"kong.db.schema.typedefs\"\nlocal PLUGIN_NAME = \"konnect-plugin-configuration-validation\"\nlocal schema = {\nname = PLUGIN_NAME,\nfields = {\n{ consumer = typedefs.no_consumer },\n{ service = typedefs.no_service },\n{ protocols = typedefs.protocols_http },\n{ config = { type = \"record\", fields = {} } }\n}\n}\nreturn schema\n", "configuration": "{\"name\": \"konnect-plugin-configuration-validation\"}"}'
```

### Required Fields

Only the `name` field of the configuration is required. If it does not match
the name of the plugin for the associated schema and error will occur.

### Optional Fields

All other entity fields are optional and if supplied will be used during the
validation of the plugin configuration.

| Field | Info |
| --- | --- |
| id | The unique identifier of the Plugin. |
| route | If set, the plugin will only activate when receiving requests via the specified route. Leave unset for the plugin to activate regardless of the Route being used. Default: null. |
| service | If set, the plugin will only activate when receiving requests via one of the routes belonging to the specified Service. Leave unset for the plugin to activate regardless of the Service being matched. Default: null. |
| consumer | If set, the plugin will activate only for requests where the specified has been authenticated. (Note that some plugins can not be restricted to consumers this way.). Leave unset for the plugin to activate regardless of the authenticated Consumer. Default: null. |
| instance_name | The Plugin instance name. |
| config | The configuration properties for the Plugin defined by the schema |
| protocols | A list of the request protocols that will trigger this plugin. The default value, as well as the possible values allowed on this field, may change depending on the plugin type. |
| enabled | Whether the plugin is applied. Default: true. |
| tags | An optional set of strings associated with the Plugin for grouping and filtering. |
| ordering | Describes a dependency to another plugin to determine plugin ordering during the access phase. |
| updated_at | Timestamp the plugin was updated at. |
| created_at | Timestamp the plugin was created at. |

## Example

Validate a configuration for the third party
[Moesif custom plugin](https://docs.konghq.com/hub/moesif/kong-plugin-moesif/)
which captures and logs Kong Gateway traffic for
[Moesif API Analytics](https://www.moesif.com).

- `schema`: [schema.lua](https://github.com/Moesif/kong-plugin-moesif/blob/master/kong/plugins/moesif/schema.lua)
- `configuration`: `application_id` field is required; will use `konnect` as ID

### Request

```
curl -X POST http://kong:8000/konnect/plugin/configuration/validation \
  --header "content-type:application/json" \
  --data '{"schema": "local typedefs = require \"kong.db.schema.typedefs\"\n\nreturn {\n  name = \"moesif\",\n  fields = {\n    {\n      consumer = typedefs.no_consumer\n    },\n    {\n      protocols = typedefs.protocols_http\n    },\n    {\n      config = {\n        type = \"record\",\n        fields = {\n          {\n            api_endpoint = {required = true, type = \"string\", default = \"https://api.moesif.net\"}\n          },\n          {\n            timeout = {default = 1000, type = \"number\"}\n          },\n          {\n            connect_timeout = {default = 1000, type = \"number\"}\n          },\n          {\n            send_timeout = {default = 2000, type = \"number\"}\n          },\n          {\n            keepalive = {default = 5000, type = \"number\"}\n          },\n          {\n            event_queue_size = {default = 1000, type = \"number\"}\n          },\n          {\n            api_version = {default = \"1.0\", type = \"string\"}\n          },\n          {\n            application_id = {required = true, default = nil, type=\"string\"}\n          },\n          {\n            disable_capture_request_body = {default = false, type = \"boolean\"}\n          },\n          {\n            disable_capture_response_body = {default = false, type = \"boolean\"}\n          },\n          {\n            request_masks = {default = {}, type = \"array\", elements = typedefs.header_name}\n          },\n          {\n            request_body_masks = {default = {}, type = \"array\", elements = typedefs.header_name}\n          },\n          {\n            request_header_masks = {default = {}, type = \"array\", elements = typedefs.header_name}\n          },\n          {\n            response_masks = {default = {}, type = \"array\", elements = typedefs.header_name}\n          },\n          {\n            response_body_masks = {default = {}, type = \"array\", elements = typedefs.header_name}\n          },\n          {\n            response_header_masks = {default = {}, type = \"array\", elements = typedefs.header_name}\n          },\n          {\n            batch_size = {default = 200, type = \"number\", elements = typedefs.header_name}\n          },\n          {\n            disable_transaction_id = {default = false, type = \"boolean\"}\n          },\n          {\n            debug = {default = false, type = \"boolean\"}\n          },\n          {\n            disable_gzip_payload_decompression = {default = false, type = \"boolean\"}\n          },\n          {\n            user_id_header = {default = nil, type = \"string\"}\n          },\n          {\n            authorization_header_name = {default = \"authorization\", type = \"string\"}\n          },\n          {\n            authorization_user_id_field = {default = \"sub\", type = \"string\"}\n          },\n          {\n            authorization_company_id_field = {default = nil, type = \"string\"}\n          },\n          {\n            company_id_header = {default = nil, type = \"string\"}\n          },\n          {\n            max_callback_time_spent = {default = 750, type = \"number\"}\n          },\n          {\n            request_max_body_size_limit = {default = 100000, type = \"number\"}\n          },\n          {\n            response_max_body_size_limit = {default = 100000, type = \"number\"}\n          },\n          {\n            request_query_masks = {default = {}, type = \"array\", elements = typedefs.header_name}\n          },\n          {\n            enable_reading_send_event_response = {default = false, type = \"boolean\"}\n          },\n          {\n            disable_moesif_payload_compression = {default = false, type = \"boolean\"}\n          },\n        },\n      },\n    },\n  },\n  entity_checks = {}\n}", "configuration": "{\"name\": \"moesif\", \"config\": {\"application_id\": \"konnect\"}}"}'
```

### Response

```
{
  "enabled": true,
  "ordering": null,
  "instance_name": null,
  "config": {
    "connect_timeout": 1000,
    "send_timeout": 2000,
    "disable_moesif_payload_compression": false,
    "batch_size": 200,
    "enable_reading_send_event_response": false,
    "debug": false,
    "api_endpoint": "https://api.moesif.net",
    "response_max_body_size_limit": 100000,
    "event_queue_size": 1000,
    "disable_capture_request_body": false,
    "disable_capture_response_body": false,
    "request_masks": [],
    "request_body_masks": [],
    "request_header_masks": [],
    "response_masks": [],
    "response_body_masks": [],
    "response_header_masks": [],
    "disable_transaction_id": false,
    "disable_gzip_payload_decompression": false,
    "user_id_header": null,
    "authorization_header_name": "authorization",
    "authorization_user_id_field": "sub",
    "authorization_company_id_field": null,
    "company_id_header": null,
    "max_callback_time_spent": 750,
    "request_max_body_size_limit": 100000,
    "timeout": 1000,
    "request_query_masks": [],
    "application_id": "konnect",
    "keepalive": 5000,
    "api_version": "1.0"
  },
  "updated_at": 1685303931,
  "route": null,
  "id": "44b2617f-087f-46cc-98e1-da9e772aec1a",
  "protocols": [
    "grpc",
    "grpcs",
    "http",
    "https"
  ],
  "created_at": 1685303931,
  "service": null,
  "name": "moesif",
  "tags": null,
  "consumer": null
}
```