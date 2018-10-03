api_mime_types = %W(
  application/vnd.api+json
  application/json
  text/x-json
)
Mime::Type.register 'application/json', :json, api_mime_types
