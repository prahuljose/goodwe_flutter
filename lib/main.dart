import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'data/local/session_storage.dart';
import 'data/local/settings_storage.dart';
import 'data/local/credentials_storage.dart';
import 'data/remote/api_logger.dart';
import 'data/remote/sems_api.dart';
import 'repositories/auth_repository.dart';
import 'repositories/station_repository.dart';

void main() {
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
      ],
      child: const GoodWeApp(),
    ),
  );
}
