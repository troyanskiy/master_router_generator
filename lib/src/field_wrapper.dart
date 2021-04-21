import 'package:analyzer/dart/element/element.dart';
import 'package:master_router_annotation/master_router_annotation.dart';

class FieldWrapper {
  final MasterRouteParam param;
  final FieldElement field;

  FieldWrapper({
    required this.param,
    required this.field,
  });
}
