import 'package:master_router_annotation/master_router_annotation.dart';
import 'package:recase/recase.dart';

String stringTransform(String str, EnumTransform enumTransform) {
  switch (enumTransform) {
    case EnumTransform.None:
      break;
    case EnumTransform.KebabCase:
      return str.paramCase;
    case EnumTransform.LowerCase:
      return str.toLowerCase();
    case EnumTransform.UpperCase:
      return str.toUpperCase();
    case EnumTransform.SnakeCase:
      return str.snakeCase;
    case EnumTransform.DotCase:
      return str.dotCase;
    case EnumTransform.PascalCase:
      return str.pascalCase;
    case EnumTransform.CamelCase:
      return str.camelCase;
  }

  return str;
}