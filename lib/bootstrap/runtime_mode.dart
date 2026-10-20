import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../config/app_environment.dart';

enum RuntimeMode {
  offline,
  hybrid,
  distributed,
}

extension RuntimeModeX on RuntimeMode {
  String get label {
    switch (this) {
      case RuntimeMode.offline:
        return 'Offline';
      case RuntimeMode.hybrid:
        return 'Hybrid';
      case RuntimeMode.distributed:
        return 'Distributed';
    }
  }

  bool get allowsBackend => this != RuntimeMode.offline;
  bool get allowsDistributed => this == RuntimeMode.distributed;
}

class RuntimeModeResolver {
  static RuntimeMode resolve() {
    final explicit = (dotenv.isInitialized ? dotenv.env['RUNTIME_MODE'] : null)?.trim().toLowerCase();
    switch (explicit) {
      case 'offline':
        return RuntimeMode.offline;
      case 'distributed':
        return RuntimeMode.distributed;
      case 'hybrid':
        return RuntimeMode.hybrid;
    }

    if (!AppEnvironment.enableBackend) {
      return RuntimeMode.offline;
    }

    if ((dotenv.isInitialized ? dotenv.env['HOTSPOT_MODE'] : null)?.toLowerCase() == 'true') {
      return RuntimeMode.distributed;
    }

    return RuntimeMode.hybrid;
  }
}
