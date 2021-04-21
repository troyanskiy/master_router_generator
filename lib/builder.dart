import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/master_router_generator.dart';

Builder masterRouter(BuilderOptions options) =>
    SharedPartBuilder([MasterRouterGenerator(options)], 'master_router');
