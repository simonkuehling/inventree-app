import "dart:ui";
import "dart:io";

import "package:font_awesome_flutter/font_awesome_flutter.dart";
import "package:dropdown_search/dropdown_search.dart";
import "package:date_field/date_field.dart";

import "package:inventree/api.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/inventree/part.dart";
import "package:inventree/inventree/sentry.dart";
import "package:inventree/inventree/stock.dart";
import "package:inventree/widget/dialogs.dart";
import "package:inventree/widget/fields.dart";
import "package:inventree/l10.dart";

import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:inventree/widget/snacks.dart";



/*
 * Class that represents a single "form field",
 * defined by the InvenTree API
 */
class APIFormField {

  // Constructor
  APIFormField(this.name, this.data);

  // File to be uploaded for this filed
  File? attachedfile;

  // Name of this field
  final String name;

  // JSON data which defines the field
  final Map<String, dynamic> data;

  dynamic initial_data;

  // Get the "api_url" associated with a related field
  String get api_url => (data["api_url"] ?? "") as String;

  // Get the "model" associated with a related field
  String get model => (data["model"] ?? "") as String;

  // Is this field hidden?
  bool get hidden => (data["hidden"] ?? false) as bool;

  // Is this field read only?
  bool get readOnly => (data["read_only"] ?? false) as bool;

  bool get multiline => (data["multiline"] ?? false) as bool;

  // Get the "value" as a string (look for "default" if not available)
  dynamic get value => data["value"] ?? data["default"];

  // Get the "default" as a string
  dynamic get defaultValue => data["default"];

  Map<String, String> get filters {

    Map<String, String> _filters = {};

    // Start with the provided "model" filters
    if (data.containsKey("filters")) {

      dynamic f = data["filters"];

      if (f is Map) {
        f.forEach((key, value) {
          _filters[key as String] = value.toString();
        });
      }
    }

    // Now, look at the provided "instance_filters"
    if (data.containsKey("instance_filters")) {

      dynamic f = data["instance_filters"];

      if (f is Map) {
        f.forEach((key, value) {
          _filters[key as String] = value.toString();
        });
      }
    }

    return _filters;

  }

  bool hasErrors() => errorMessages().isNotEmpty;

  // Return the error message associated with this field
  List<String> errorMessages() {
    List<dynamic> errors = (data["errors"] ?? []) as List<dynamic>;

    List<String> messages = [];

    for (dynamic error in errors) {
      messages.add(error.toString());
    }

    return messages;
  }

  // Is this field required?
  bool get required => (data["required"] ?? false) as bool;

  String get type => (data["type"] ?? "").toString();

  String get label => (data["label"] ?? "").toString();

  String get helpText => (data["help_text"] ?? "").toString();

  String get placeholderText => (data["placeholder"] ?? "").toString();

  List<dynamic> get choices => (data["choices"] ?? []) as List<dynamic>;

  Future<void> loadInitialData() async {

    // Only for "related fields"
    if (type != "related field") {
      return;
    }

    // Null value? No point!
    if (value == null) {
      return;
    }

    int? pk = int.tryParse(value.toString());

    if (pk == null) {
      return;
    }

    String url = api_url + "/" + pk.toString() + "/";

    final APIResponse response = await InvenTreeAPI().get(
      url,
      params: filters,
    );

    if (response.successful()) {
      initial_data = response.data;
    }
  }

  // Construct a widget for this input
  Widget constructField() {
    switch (type) {
      case "string":
      case "url":
        return _constructString();
      case "boolean":
        return _constructBoolean();
      case "related field":
        return _constructRelatedField();
      case "float":
      case "decimal":
        return _constructFloatField();
      case "choice":
        return _constructChoiceField();
      case "file upload":
      case "image upload":
        return _constructFileField();
      case "date":
        return _constructDateField();
      default:
        return ListTile(
          title: Text(
            "Unsupported field type: '${type}'",
            style: TextStyle(
                color: COLOR_DANGER,
                fontStyle: FontStyle.italic),
          )
        );
    }
  }

  // Field for displaying and selecting dates
  Widget _constructDateField() {

    return DateTimeFormField(
      mode: DateTimeFieldPickerMode.date,
      decoration: InputDecoration(
        helperText: helpText,
        helperStyle: _helperStyle(),
        labelText: label,
        labelStyle: _labelStyle(),
      ),
      initialValue: DateTime.tryParse((value ?? "") as String),
      autovalidateMode: AutovalidateMode.disabled,
      validator: (e) {
        // TODO
      },
      onDateSelected: (DateTime dt) {
        data["value"] = dt.toString().split(" ").first;
      },
    );

  }


  // Field for selecting and uploading files
  Widget _constructFileField() {

    TextEditingController controller = TextEditingController();

    controller.text = (attachedfile?.path ?? L10().attachmentSelect).split("/").last;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      child: ListTile(
        title: TextField(
          readOnly: true,
          controller: controller,
        ),
        trailing: IconButton(
          icon: FaIcon(FontAwesomeIcons.plusCircle),
          onPressed: () async {
            FilePickerDialog.pickFile(
              message: L10().attachmentSelect,
              onPicked: (file) {
                print("${file.path}");
                // Display the filename
                controller.text = file.path.split("/").last;

                // Save the file
                attachedfile = file;
              }
            );
          },
        )
      )
    );
  }

  // Field for selecting from multiple choice options
  Widget _constructChoiceField() {

    dynamic _initial;

    // Check if the current value is within the allowed values
    for (var opt in choices) {
      if (opt["value"] == value) {
        _initial = opt;
        break;
      }
    }

    return DropdownSearch<dynamic>(
      mode: Mode.BOTTOM_SHEET,
      showSelectedItem: false,
      selectedItem: _initial,
      items: choices,
      label: label,
      hint: helpText,
      onChanged: null,
      autoFocusSearchBox: true,
      showClearButton: !required,
      itemAsString: (dynamic item) {
        return (item["display_name"] ?? "") as String;
      },
      onSaved: (item) {
        if (item == null) {
          data["value"] = null;
        } else {
          data["value"] = item["value"];
        }
      }
    );
  }

  // Construct a floating point numerical input field
  Widget _constructFloatField() {

    return TextFormField(
      decoration: InputDecoration(
        labelText: required ? label + "*" : label,
        labelStyle: _labelStyle(),
        helperText: helpText,
        helperStyle: _helperStyle(),
        hintText: placeholderText,
      ),
      initialValue: (value ?? 0).toString(),
      keyboardType: TextInputType.numberWithOptions(signed: true, decimal: true),
      validator: (value) {

        double? quantity = double.tryParse(value.toString());

        if (quantity == null) {
          return L10().numberInvalid;
        }
      },
      onSaved: (val) {
        data["value"] = val;
      },
    );

  }

  // Construct an input for a related field
  Widget _constructRelatedField() {

    return DropdownSearch<dynamic>(
      mode: Mode.BOTTOM_SHEET,
      showSelectedItem: true,
      selectedItem: initial_data,
      onFind: (String filter) async {

        Map<String, String> _filters = {};

        filters.forEach((key, value) {
          _filters[key] = value;
        });

        _filters["search"] = filter;
        _filters["offset"] = "0";
        _filters["limit"] = "25";

        final APIResponse response = await InvenTreeAPI().get(
          api_url,
          params: _filters
        );

        if (response.isValid()) {

          List<dynamic> results = [];

          for (var result in response.data["results"] ?? []) {
            results.add(result);
          }

          return results;
        } else {
          return [];
        }
      },
      label: label,
      hint: helpText,
      onChanged: null,
      showClearButton: !required,
      itemAsString: (dynamic item) {

        Map<String, dynamic> data = item as Map<String, dynamic>;

        switch (model) {
          case "part":
            return InvenTreePart.fromJson(data).fullname;
          case "partcategory":
            return InvenTreePartCategory.fromJson(data).pathstring;
          case "stocklocation":
            return InvenTreeStockLocation.fromJson(data).pathstring;
          default:
            return "itemAsString not implemented for '${model}'";
        }
      },
      dropdownBuilder: (context, item, itemAsString) {
        return _renderRelatedField(item, true, false);
      },
      popupItemBuilder: (context, item, isSelected) {
        return _renderRelatedField(item, isSelected, true);
      },
      onSaved: (item) {
        if (item != null) {
          data["value"] = item["pk"];
        } else {
          data["value"] = null;
        }
      },
      isFilteredOnline: true,
      showSearchBox: true,
      autoFocusSearchBox: true,
      compareFn: (dynamic item, dynamic selectedItem) {
        // Comparison is based on the PK value

        if (item == null || selectedItem == null) {
          return false;
        }

        return item["pk"] == selectedItem["pk"];
      }
    );
  }

  Widget _renderRelatedField(dynamic item, bool selected, bool extended) {
    // Render a "related field" based on the "model" type

    // Convert to JSON
    var data = Map<String, dynamic>.from((item ?? {}) as Map);

    switch (model) {
      case "part":

        var part = InvenTreePart.fromJson(data);

        return ListTile(
          title: Text(
            part.fullname,
              style: TextStyle(fontWeight: selected && extended ? FontWeight.bold : FontWeight.normal)
          ),
          subtitle: extended ? Text(
            part.description,
            style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal),
          ) : null,
          leading: extended ? InvenTreeAPI().getImage(part.thumbnail, width: 40, height: 40) : null,
        );

      case "partcategory":

        var cat = InvenTreePartCategory.fromJson(data);

        return ListTile(
          title: Text(
            cat.pathstring,
            style: TextStyle(fontWeight: selected && extended ? FontWeight.bold : FontWeight.normal)
          ),
          subtitle: extended ? Text(
            cat.description,
            style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal),
          ) : null,
        );
      case "stocklocation":

        var loc = InvenTreeStockLocation.fromJson(data);

        return ListTile(
          title: Text(
            loc.pathstring,
              style: TextStyle(fontWeight: selected && extended ? FontWeight.bold : FontWeight.normal)
          ),
          subtitle: extended ? Text(
            loc.description,
            style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal),
          ) : null,
        );
      case "owner":
        String name = (data["name"] ?? "") as String;
        bool isGroup = (data["label"] ?? "") == "group";
        return ListTile(
          title: Text(name),
          leading: FaIcon(isGroup ? FontAwesomeIcons.users : FontAwesomeIcons.user),
        );
      default:
        return ListTile(
          title: Text(
            "Unsupported model",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: COLOR_DANGER
            )
          ),
          subtitle: Text("Model '${model}' rendering not supported"),
        );
    }

  }

  // Construct a string input element
  Widget _constructString() {

    return TextFormField(
      decoration: InputDecoration(
        labelText: required ? label + "*" : label,
        labelStyle: _labelStyle(),
        helperText: helpText,
        helperStyle: _helperStyle(),
        hintText: placeholderText,
      ),
      readOnly: readOnly,
      maxLines: multiline ? null : 1,
      expands: false,
      initialValue: (value ?? "") as String,
      onSaved: (val) {
        data["value"] = val;
      },
      validator: (value) {
        if (required && (value == null || value.isEmpty)) {
          // return L10().valueCannotBeEmpty;
        }
      },
    );
  }

  // Construct a boolean input element
  Widget _constructBoolean() {

    return CheckBoxField(
      label: label,
      labelStyle: _labelStyle(),
      helperText: helpText,
      helperStyle: _helperStyle(),
      initial: value as bool,
      onSaved: (val) {
        data["value"] = val;
      },
    );
  }

  TextStyle _labelStyle() {
    return TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 18,
      fontFamily: "arial",
      color: hasErrors() ? COLOR_DANGER : COLOR_GRAY,
      fontStyle: FontStyle.normal,
    );
  }

  TextStyle _helperStyle() {
    return TextStyle(
      fontStyle: FontStyle.italic,
      color: hasErrors() ? COLOR_DANGER : COLOR_GRAY,
    );
  }

}


/*
 * Extract field options from a returned OPTIONS request
 */
Map<String, dynamic> extractFields(APIResponse response) {

  if (!response.isValid()) {
    return {};
  }

  var data = response.asMap();

  if (!data.containsKey("actions")) {
    return {};
  }

  var actions = response.data["actions"] as Map<String, dynamic>;

  dynamic result = actions["POST"] ?? actions["PUT"] ?? actions["PATCH"] ?? {};

  return result as Map<String, dynamic>;
}

/*
 * Launch an API-driven form,
 * which uses the OPTIONS metadata (at the provided URL)
 * to determine how the form elements should be rendered!
 *
 * @param title is the title text to display on the form
 * @param url is the API URl to make the OPTIONS request to
 * @param fields is a map of fields to display (with optional overrides)
 * @param modelData is the (optional) existing modelData
 * @param method is the HTTP method to use to send the form data to the server (e.g. POST / PATCH)
 */

Future<void> launchApiForm(BuildContext context, String title, String url, Map<String, dynamic> fields, {String fileField = "", Map<String, dynamic> modelData = const {}, String method = "PATCH", Function(Map<String, dynamic>)? onSuccess, Function? onCancel}) async {

  var options = await InvenTreeAPI().options(url);

  // Invalid response from server
  if (!options.isValid()) {
    return;
  }

  var availableFields = extractFields(options);

  if (availableFields.isEmpty) {
    // User does not have permission to perform this action
    showSnackIcon(
      L10().response403,
      icon: FontAwesomeIcons.userTimes,
    );

    return;
  }

  // Construct a list of APIFormField objects
  List<APIFormField> formFields = [];

  // Iterate through the provided fields we wish to display
  for (String fieldName in fields.keys) {

    // Check that the field is actually available at the API endpoint
    if (!availableFields.containsKey(fieldName)) {
      print("Field '${fieldName}' not available at '${url}'");

      sentryReportMessage(
        "API form called with unknown field '${fieldName}'",
        context: {
          "url": url.toString(),
        }
      );

      continue;
    }

    final remoteField = Map<String, dynamic>.from(availableFields[fieldName] as Map);
    final localField = Map<String, dynamic>.from(fields[fieldName] as Map);

    // Override defined field parameters, if provided
    for (String key in localField.keys) {
      // Special consideration must be taken here!
      if (key == "filters") {

        if (!remoteField.containsKey("filters")) {
          remoteField["filters"] = {};
        }

        var filters = localField["filters"];

        if (filters is Map) {
          filters.forEach((key, value) {
            remoteField["filters"][key] = value;
          });
        }

      } else {
        remoteField[key] = localField[key];
      }
    }

    if (modelData.containsKey(fieldName)) {
      remoteField["value"] = modelData[fieldName];
    }

    formFields.add(APIFormField(fieldName, remoteField));
  }

  // Grab existing data for each form field
  for (var field in formFields) {
    await field.loadInitialData();
  }

  // Now, launch a new widget!
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => APIFormWidget(
        title,
        url,
        formFields,
        method,
        onSuccess: onSuccess,
        fileField: fileField,
    ))
  );
}


class APIFormWidget extends StatefulWidget {

  const APIFormWidget(
      this.title,
      this.url,
      this.fields,
      this.method,
      {
        Key? key,
        this.onSuccess,
        this.fileField = "",
      }
      ) : super(key: key);

  //! Form title to display
  final String title;

  //! API URL
  final String url;

  //! API method
  final String method;

  final String fileField;

  final List<APIFormField> fields;

  final Function(Map<String, dynamic>)? onSuccess;

  @override
  _APIFormWidgetState createState() => _APIFormWidgetState(title, url, fields, method, onSuccess, fileField);

}


class _APIFormWidgetState extends State<APIFormWidget> {

  _APIFormWidgetState(this.title, this.url, this.fields, this.method, this.onSuccess, this.fileField) : super();

  final _formKey = GlobalKey<FormState>();

  String title;

  String url;

  String method;

  String fileField;

  List<APIFormField> fields;

  Function(Map<String, dynamic>)? onSuccess;

  bool spacerRequired = false;

  List<Widget> _buildForm() {

    List<Widget> widgets = [];

    for (var field in fields) {

      if (field.hidden) {
        continue;
      }

      // Add divider before some widgets
      if (spacerRequired) {
        switch (field.type) {
          case "related field":
          case "choice":
            widgets.add(Divider(height: 15));
            break;
          default:
            break;
        }
      }

      widgets.add(field.constructField());

      if (field.hasErrors()) {
        for (String error in field.errorMessages()) {
          widgets.add(
            ListTile(
              title: Text(
                error,
                style: TextStyle(
                  color: COLOR_DANGER,
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                ),
              )
            )
          );
        }
      }

      // Add divider after some widgets
      switch (field.type) {
        case "related field":
        case "choice":
          widgets.add(Divider(height: 15));
          spacerRequired = false;
          break;
        default:
          spacerRequired = true;
          break;
      }

    }

    return widgets;
  }

  Future<APIResponse> _submit(Map<String, String> data) async {


    // If a file upload is required, we have to handle the submission differently
    if (fileField.isNotEmpty) {

      // Pop the "file" field
      data.remove(fileField);

      for (var field in fields) {
        if (field.name == fileField) {

          File? file = field.attachedfile;

          if (file != null) {

            // A valid file has been supplied
            final response = await InvenTreeAPI().uploadFile(
              url,
              file,
              name: fileField,
              fields: data,
            );

            return response;
          }
        }
      }
    }

    if (method == "POST") {
      final response =  await InvenTreeAPI().post(
        url,
        body: data,
        expectedStatusCode: null
      );

      return response;

    } else {
      final response = await InvenTreeAPI().patch(
        url,
        body: data,
        expectedStatusCode: null
      );

      return response;
    }

  }

  Future<void> _save(BuildContext context) async {

    // Package up the form data
    Map<String, String> data = {};

    for (var field in fields) {

      dynamic value = field.value;

      if (value == null) {
        data[field.name] = "";
      } else {
        data[field.name] = value.toString();
      }
    }

    final response = await _submit(data);

    if (!response.isValid()) {
      showServerError(L10().serverError, L10().responseInvalid);
      return;
    }

    switch (response.statusCode) {
      case 200:
      case 201:
        // Form was successfully validated by the server

        // Hide this form
        Navigator.pop(context);

        // TODO: Display a snackBar

        // Run custom onSuccess function
        var successFunc = onSuccess;

        if (successFunc != null) {

          // Ensure the response is a valid JSON structure
          Map<String, dynamic> json = {};

          if (response.data != null && response.data is Map) {
            for (dynamic key in response.data.keys) {
              json[key.toString()] = response.data[key];
            }
          }

          successFunc(json);
        }
        return;
      case 400:
        // Form submission / validation error
        showSnackIcon(
          L10().error,
          success: false
        );

        // Update field errors
        for (var field in fields) {
          field.data["errors"] = response.data[field.name];
        }
        break;
      // TODO: Other status codes?
    }

    setState(() {
      // Refresh the form
    });

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: FaIcon(FontAwesomeIcons.save),
            onPressed: () {

              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();

                _save(context);
              }
            },
          )
        ]
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildForm(),
          ),
          padding: EdgeInsets.all(16),
        )
      )
    );

  }
}