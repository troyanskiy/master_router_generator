import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:master_router_annotation/master_router_annotation.dart';
import 'package:master_router_generator/src/field_wrapper.dart';
import 'package:source_gen/source_gen.dart';

import 'utils.dart';

const _paramChecker = TypeChecker.fromRuntime(MasterRouteParam);

class MasterRouterGenerator extends GeneratorForAnnotation<MasterRouteParams> {
  BuilderOptions options;

  MasterRouterGenerator(this.options);

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      final name = element.displayName;
      throw InvalidGenerationSourceError(
        'Generator cannot target `$name`.',
        todo: 'Remove the [RestApi] annotation from `$name`.',
      );
    }

    return _implement(element, annotation, GeneratorStore());
  }

  ///
  /// Main IMPLEMENT
  ///
  String _implement(
    ClassElement element,
    ConstantReader annotation,
    GeneratorStore store,
  ) {
    final fields = _getAllFieldsOfClass(element);

    final buffer = _generateFactory(element, fields, store);
    _generateToPathQueryParams(element, fields, buffer, store);
    store._stringToEnumHelpers.values.forEach((element) {
      buffer.write('\n\n$element');
    });

    return buffer.toString();
  }

  ///
  /// Get all fields
  ///
  List<FieldWrapper> _getAllFieldsOfClass(
    ClassElement element, {
    List<FieldWrapper>? fields,
  }) {
    fields ??= [];

    element.fields
        .where((f) {
          if (f.isPublic && !f.isStatic && !f.isAbstract && !f.isSynthetic) {
            return fields!.indexWhere((f2) => f2.field.name == f.name) == -1;
          }

          return false;
        })
        .forEach((FieldElement fieldElement) {

          final field = _mapField(fieldElement);

          if (field != null) {
            fields!.add(field);
          }
        });

    final superElement = element.supertype?.element;

    if (superElement != null) {
      _getAllFieldsOfClass(superElement, fields: fields);
    }

    return fields;
  }

  ///
  /// Map field to wrapper
  ///
  FieldWrapper? _mapField(FieldElement field) {
    final dObj = _paramChecker.firstAnnotationOf(field);

    final cr = ConstantReader(dObj);

    MasterRouteParam? param;

    if (!cr.isNull) {
      EnumTransform? enumTransform;

      if (!cr.read('enumTransform').isNull) {
        int? intValue = cr
            .read('enumTransform')
            .objectValue
            .getField('index')
            ?.toIntValue();

        if (intValue != null) {
          enumTransform = EnumTransform.values[intValue];
        }
      }

      param = MasterRouteParam(
        ignore: (cr.read('ignore').literalValue as bool?) ?? false,
        isQueryParam: (cr.read('isQueryParam').literalValue as bool?) ?? false,
        isPathParam: (cr.read('isPathParam').literalValue as bool?) ?? false,
        name: cr.read('name').literalValue as String?,
        enumTransform: enumTransform,
      );
    }

    if (param != null && param.ignore) {
      return null;
    }

    param ??= const MasterRouteParam(isQueryParam: true);

    return FieldWrapper(
      param: param,
      field: field,
    );
  }

  ///
  /// Generate params factory
  ///
  StringBuffer _generateFactory(
    ClassElement element,
    List<FieldWrapper> fields,
    GeneratorStore store, {
    StringBuffer? buffer,
  }) {
    ConstructorElement constructor = element.constructors.firstWhere(
      (c) => c.name.isEmpty,
    );

    Map<String, FieldWrapper> fieldsMap = {};

    fields.forEach((field) {
      fieldsMap[field.field.name] = field;
    });

    buffer ??= StringBuffer();

    buffer.write(
      '${element.name} \$${element.name}Builder(Map<String, String> pathParams, Map<String, String> queryParams,) {',
    );

    buffer.write('return ${element.name}(');

    constructor.parameters.forEach((constructorParam) {
      final field = fieldsMap[constructorParam.name];

      final fieldLine = _getFieldValue(
        field,
        store,
      );

      final isRequired = constructorParam.isRequiredNamed ||
          constructorParam.isRequiredPositional;

      if (fieldLine == null) {
        if (constructorParam.isPositional) {
          if (isRequired) {
            throw Exception(
                'No field provided for required field ${constructorParam.name}');
          }

          buffer!.write('null,');
        }

        return;
      }

      if (constructorParam.isNamed) {
        buffer!.write('${constructorParam.name}: ');
      }

      if (isRequired) {
        buffer!.write('${_getEnsureNotNullFunction(fieldLine, store)},');
      } else {
        buffer!.write('$fieldLine,');
      }
    });

    buffer.write(');');
    buffer.write('}');

    return buffer;
  }

  ///
  /// Get Field Value
  ///
  String? _getFieldValue(FieldWrapper? field, GeneratorStore store) {
    if (field == null) {
      return null;
    }

    final theMap = field.param.isPathParam ? 'pathParams' : 'queryParams';

    final type = field.field.type;

    final mapField = '${theMap}[\'${field.field.name}\']';

    return _getTypeCast(type, mapField, field, store);
  }

  ///
  /// Get Type Cast
  ///
  String? _getTypeCast(
    DartType type,
    String value,
    FieldWrapper field,
    GeneratorStore store,
  ) {
    if (type.isDartCoreList) {
      if (type is ParameterizedType && type.typeArguments.isNotEmpty) {
        return _getValueListCast(type.typeArguments.first, value, field, store);
      }
      return null;
    }

    if (type.isDartCoreSet) {
      if (type is ParameterizedType && type.typeArguments.isNotEmpty) {
        return '$value == null ? null : Set.of(${_getValueListCast(type.typeArguments.first, value, field, store)})';
      }
      return null;
    }

    if (type.isDartCoreMap) {
      if (type is ParameterizedType &&
          type.typeArguments.isNotEmpty &&
          type.typeArguments.first.isDartCoreString) {
        return '$value == null ? null : Map.fromEntries($value.split(\',\').map((v) => v.split(\':\').map(Uri.decodeQueryComponent)).where((v) => v.length == 2).map((v) => MapEntry(v.first, ${_getTypeCast(type.typeArguments.last, 'v.last', field, store)})))';
      }
      return null;
    }

    if (type.isDartCoreString) {
      return value;
    }

    if (type.isDartCoreDouble) {
      return '$value != null ? double.tryParse($value) : null';
    }

    if (type.isDartCoreInt) {
      return '$value != null ? int.tryParse($value, radix: 10) : null';
    }

    if (type.isDartCoreBool) {
      return '$value != null ? $value == \'true\' : null';
    }

    if (type is InterfaceType &&
        type.element.isEnum &&
        field.param.enumTransform != null) {
      final functionName = _getFunctionNameStringToEnum(
        type,
        field.param.enumTransform!,
        store,
      );

      return '$functionName($value)';
    }

    return null;
  }

  ///
  /// Get Value List cast
  ///
  String _getValueListCast(
    DartType type,
    String value,
    FieldWrapper field,
    GeneratorStore store,
  ) {
    return '$value?.split(\',\')?.map(Uri.decodeQueryComponent)?.map((v) => ${_getTypeCast(type, 'v', field, store)})?.toList()';
  }

  ///
  /// Get ensure not null function
  ///
  String _getEnsureNotNullFunction(
    String value,
    GeneratorStore store,
  ) {
    const functionName = '_\$ensureNotNull';

    final hasEnsureFunction =
        store._stringToEnumHelpers.containsKey(functionName);

    if (!hasEnsureFunction) {
      final functionBuffer = StringBuffer();

      functionBuffer.writeAll([
        'T $functionName<T>(T? value) {',
        'assert(value != null);',
        'return value!;'
            '}',
      ]);

      store._stringToEnumHelpers[functionName] = functionBuffer.toString();
    }

    return '$functionName($value)';
  }

  ///
  /// Get function name to cast string to enum
  /// And test if exists
  ///
  String _getFunctionNameStringToEnum(
    InterfaceType type,
    EnumTransform enumTransform,
    GeneratorStore store,
  ) {
    _generateEnumHelpersFor(type, enumTransform, store);

    return __getFunctionNameStringToEnum(type);
  }

  ///
  /// Get function name to cast enum to string
  /// And test if exists
  ///
  String _getFunctionNameEnumToString(
    InterfaceType type,
    EnumTransform enumTransform,
    GeneratorStore store,
  ) {
    _generateEnumHelpersFor(type, enumTransform, store);

    return __getFunctionNameEnumToString(type);
  }

  ///
  /// Get function name to cast string to enum
  ///
  String __getFunctionNameStringToEnum(InterfaceType type) =>
      '_\$StringToEnum${type.element.name}';

  ///
  /// Get function name to cast enum to string
  ///
  String __getFunctionNameEnumToString(InterfaceType type) =>
      '_\$Enum${type.element.name}ToString';

  ///
  /// Generate cast enum helpers
  ///
  void _generateEnumHelpersFor(
    InterfaceType type,
    EnumTransform enumTransform,
    GeneratorStore store,
  ) {
    final functionNameToEnum = __getFunctionNameStringToEnum(type);
    final functionNameToString = __getFunctionNameEnumToString(type);

    if (store._stringToEnumHelpers.containsKey(functionNameToEnum) &&
        store._stringToEnumHelpers.containsKey(functionNameToString)) {
      return;
    }

    final enumName = type.element.name;

    final functionBufferToEnum = StringBuffer();
    final functionBufferToString = StringBuffer();

    functionBufferToEnum.writeAll([
      '$enumName? $functionNameToEnum(String? value) {',
      'switch (value) {'
    ]);

    functionBufferToString.writeAll([
      'String? $functionNameToString($enumName? value) {',
      'switch (value) {'
    ]);

    for (final field in type.element.fields) {
      String name = field.name;

      if (name != 'index' && name != 'values') {
        String nameTransformed = stringTransform(
          name,
          enumTransform,
        );

        functionBufferToEnum.writeAll(
            ['case \'$nameTransformed\':', 'return $enumName.$name;']);

        functionBufferToString.writeAll(
            ['case $enumName.$name:', 'return \'$nameTransformed\';']);
      }
    }

    functionBufferToEnum.writeAll(['}', 'return null;', '}']);
    functionBufferToString.writeAll(['}', 'return null;', '}']);

    store._stringToEnumHelpers[functionNameToEnum] =
        functionBufferToEnum.toString();
    store._stringToEnumHelpers[functionNameToString] =
        functionBufferToString.toString();
  }

  ///
  /// Generator to path/query params
  ///
  void _generateToPathQueryParams(
    ClassElement element,
    List<FieldWrapper> fields,
    StringBuffer buffer,
    GeneratorStore store,
  ) {
    final List<String> forPath = [];
    final List<String> forQuery = [];

    fields.forEach((field) {
      final forList = field.param.isPathParam ? forPath : forQuery;

      forList.addAll([
        'tmp = ${_getValueCastString(field, store)};',
        'if (tmp != null) {',
        'res[\'${field.param.name ?? field.field.name}\'] = tmp;',
        '}'
      ]);
    });

    buffer.writeAll([
      '\n\n\nMap<String, String> _\$${element.name}ToPathParams(${element.name} instance) {',
      'final Map<String, String> res = {};\n',
      'String? tmp;\n',
      ...forPath,
      'return res;',
      '}',
      '\n\n\nMap<String, String> _\$${element.name}ToQueryParams(${element.name} instance) {',
      'final Map<String, String> res = {};\n',
      'String? tmp;\n',
      ...forQuery,
      'return res;',
      '}',
    ]);
  }

  ///
  /// Cast value to string
  ///
  String? _getValueCastString(
    FieldWrapper field,
    GeneratorStore store, {
    String? mainPart,
    DartType? type,
  }) {
    mainPart ??= 'instance.${field.field.name}';
    type ??= field.field.type;

    if (type.isDartCoreString) {
      return 'Uri.encodeQueryComponent($mainPart)';
    }

    if (type.isDartCoreInt || type.isDartCoreDouble || type.isDartCoreBool) {
      return '$mainPart?.toString()';
    }

    if (type.isDartCoreList || type.isDartCoreSet) {
      if (type is ParameterizedType && type.typeArguments.isNotEmpty) {
        final casterString = _getValueCastString(
          field,
          store,
          mainPart: 'v',
          type: type.typeArguments.first,
        );

        if (casterString == null) {
          return null;
        }

        return '$mainPart?.map((v) => $casterString)?.join(\',\')';
      }
      return null;
    }

    if (type.isDartCoreMap) {
      if (type is ParameterizedType &&
          type.typeArguments.isNotEmpty &&
          type.typeArguments.first.isDartCoreString) {
        final casterString = _getValueCastString(
          field,
          store,
          mainPart: 'e.value',
          type: type.typeArguments.last,
        );

        if (casterString == null) {
          return null;
        }

        return '$mainPart?.entries?.map((e) => \'\${Uri.encodeQueryComponent(e.key)}:\${$casterString}\')?.join(\',\')';
      }
      return null;
    }

    if (type is InterfaceType &&
        type.element.isEnum &&
        field.param.enumTransform != null) {
      final functionName = _getFunctionNameEnumToString(
        type,
        field.param.enumTransform!,
        store,
      );

      return '$functionName($mainPart)';
    }

    return null;
  }
}

class GeneratorStore {
  Map<String, String> _stringToEnumHelpers = {};
}
