import 'package:apidash/consts.dart';
import 'package:jinja/jinja.dart' as jj;
import 'package:apidash/utils/utils.dart' show getValidRequestUri;
import 'package:apidash/utils/http_utils.dart' show stripUriParams;

import 'package:apidash/models/models.dart' show RequestModel;

// Note that delete is a special case in Faraday as API Dash supports request
// body inside delete reqest, but Faraday does not. Hence we need to manually
// setup request body for delete request and add that to request.
//
// Refer https://lostisland.github.io/faraday/#/getting-started/quick-start?id=get-head-delete-trace
class RubyFaradayCodeGen {

  final String kStringFaradayRequireStatement = """
require 'uri'
require 'faraday'
""";

  final String kStringFaradayMultipartRequireStatement = '''
require 'faraday/multipart'
''';

  final String kTemplateRequestUrl = """
\nREQUEST_URL = URI("{{ url }}")\n\n
""";

  final String kTemplateBody = """
PAYLOAD = <<-{{ boundary }}
{{ body }}
{{ boundary }}\n\n
""";

  final String kTemplateFormParamsWithFile = """
PAYLOAD = {
{% for param in params %}{% if param.type == "text" %}  "{{ param.name }}" => Faraday::Multipart::ParamPart.new("{{ param.value }}", "text/plain"),
{% elif param.type == "file" %}  "{{ param.name }}" => Faraday::Multipart::FilePart.new("{{ param.value }}", "application/octet-stream"),{% endif %}{% endfor %}
}\n\n
""";

  final String kTemplateFormParamsWithoutFile = """
PAYLOAD = URI.encode_www_form({\n{% for param in params %}  "{{ param.name }}" => "{{ param.value }}",\n{% endfor %}})\n\n
""";

  final String kTemplateConnection = """
conn = Faraday.new do |faraday|
  faraday.adapter Faraday.default_adapter{% if hasFile %}\n  faraday.request :multipart{% endif %}
end\n\n
""";

  final String kTemplateRequestStart = """
response = conn.{{ method|lower }}(REQUEST_URL{% if doesMethodAcceptBody and containsBody %}, PAYLOAD{% endif %}) do |req|\n
""";

  final String kTemplateRequestOptionsBoundary = """
  req.options.boundary = "{{ boundary }}"\n
""";

  final String kTemplateRequestParams = """
  req.params = {\n{% for key, val in params %}    "{{ key }}" => "{{ val }}",\n{% endfor %}  }\n
""";

  final String kTemplateRequestHeaders = """
  req.headers = {\n{% for key, val in headers %}    "{{ key }}" => "{{ val }}",\n{% endfor %}  }\n
""";

  final String kStringDeleteRequestBody = """
  req.body = PAYLOAD
""";

  final String kStringRequestEnd = """
end\n
""";

  final String kStringResponse = """
puts "Status Code: #{response.status}"
puts "Response Body: #{response.body}"
""";

  String? getCode(
    RequestModel requestModel, {
    String? boundary,
  }) {
    try {
      String result = "";

      if (boundary != null) {
        // boundary needs to start with a character, hence we append apidash
        // and remove hyphen characters from the existing boundary
        boundary = "apidash_${boundary.replaceAll(RegExp("-"), "")}";
      }

      var rec = getValidRequestUri(
        requestModel.url,
        requestModel.enabledRequestParams,
      );

      Uri? uri = rec.$1;

      if (uri == null) {
        return "";
      }

      var url = stripUriParams(uri);

      result += kStringFaradayRequireStatement;
      if (requestModel.hasFormDataContentType && requestModel.hasFileInFormData) {
        result += kStringFaradayMultipartRequireStatement;
      }

      var templateRequestUrl = jj.Template(kTemplateRequestUrl);
      result += templateRequestUrl.render({"url": url});

      if (requestModel.hasFormData) {
        jj.Template payload;
        if (requestModel.hasFileInFormData) {
          payload = jj.Template(kTemplateFormParamsWithFile);
        } else {
          payload = jj.Template(kTemplateFormParamsWithoutFile);
        }
        result += payload.render({"params": requestModel.formDataMapList});
      } else if (requestModel.hasJsonData || requestModel.hasTextData) {
        var templateBody = jj.Template(kTemplateBody);
        result += templateBody.render({
          "body": requestModel.requestBody, //
          "boundary": boundary,
        });
      }

      // crreating faraday connection for request
      var templateConnection = jj.Template(kTemplateConnection);
      result += templateConnection.render({
        "hasFile": requestModel.hasFormDataContentType && requestModel.hasFileInFormData //
      });

      // start of the request sending
      var templateRequestStart = jj.Template(kTemplateRequestStart);
      result += templateRequestStart.render({
        "method": requestModel.method.name, //
        "doesMethodAcceptBody":
            kMethodsWithBody.contains(requestModel.method) && requestModel.method != HTTPVerb.delete, //
        "containsBody": requestModel.hasBody, //
      });

      if (requestModel.hasFormDataContentType && requestModel.hasFileInFormData) {
        var templateRequestOptionsBoundary = jj.Template(kTemplateRequestOptionsBoundary);
        result += templateRequestOptionsBoundary.render({"boundary": boundary});
      }

      var headers = requestModel.enabledHeadersMap;
      if (requestModel.hasBody && !requestModel.hasContentTypeHeader) {
        if (requestModel.hasJsonData || requestModel.hasTextData) {
          headers["Content-Type"] = requestModel.requestBodyContentType.header;
        } else if (requestModel.hasFormData) {
          headers["Content-Type"] =
              (requestModel.hasFileInFormData) ? "multipart/form-data" : "application/x-www-form-urlencoded";
        }
      }

      if (headers.isNotEmpty) {
        var templateRequestHeaders = jj.Template(kTemplateRequestHeaders);
        result += templateRequestHeaders.render({"headers": headers});
      }

    } catch (e) {
      return null;
    }
  }
}
