import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'data/local/session_storage.dart';
import 'data/local/settings_storage.dart';
import 'data/local/credentials_storage.dart';
import 'data/remote/api_logger.dart';
import 'data/remote/sems_api.dart';
import 'data/local/tapo_storage.dart';
import 'data/repositories/tapo_local_repository.dart';
import 'features/consumption/consumption_provider.dart';
import 'repositories/auth_repository.dart';
import 'repositories/station_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load Tapo account + device list before the UI builds
  final tapoRepo = TapoLocalRepository(storage: TapoStorage());
  await tapoRepo.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiCallLogger>(create: (_) => ApiCallLogger()),
        Provider<SemsApi>(
          create: (ctx) => SemsApi(logger: ctx.read<ApiCallLogger>()),
        ),
        Provider<SessionStorage>(create: (_) => SessionStorage()),
        Provider<SettingsStorage>(create: (_) => SettingsStorage()),
        Provider<CredentialsStorage>(create: (_) => CredentialsStorage()),
        ProxyProvider3<SemsApi, SessionStorage, CredentialsStorage, AuthRepository>(
          update: (_, api, storage, creds, prev) =>
              AuthRepository(api, storage, creds),
        ),
        ProxyProvider<SemsApi, StationRepository>(
          update: (_, api, prev) => StationRepository(api),
        ),
        // ── Tapo P110 consumption tracking (local KLAP, multi-device) ───────
        Provider<TapoLocalRepository>.value(value: tapoRepo),
        ChangeNotifierProvider<ConsumptionProvider>(
          create: (_) => ConsumptionProvider(tapoRepo),
        ),
      ],
      child: const GoodWeApp(),
    ),
  );
}
