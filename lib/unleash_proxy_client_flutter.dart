library unleash_proxy_client_flutter;

import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:events_emitter/events_emitter.dart';
import 'package:unleash_proxy_client_flutter/storage_provider.dart';

import 'in_memory_storage_provider.dart';

class ToggleConfig {
  final bool enabled;
  final bool impressionData;

  ToggleConfig({required this.enabled, required this.impressionData});

  factory ToggleConfig.fromJson(Map<String, dynamic> json) {
    return ToggleConfig(
        enabled: json["enabled"], impressionData: json["impressionData"]);
  }

  bool operator ==(Object other) {
    return other is ToggleConfig && (other.enabled == enabled && other.impressionData == impressionData) ;
  }
}

Future<http.Response> get(Uri url, String clientKey) async {
  var response = await http.get(url, headers: {
    'Accept': 'application/json',
    'Cache': 'no-cache',
    'Authorization': clientKey,
  });

  if (response.statusCode != 200) {
    // Do something else
    // Remember: check 304 also
    // Handle: 400 errors
  }

  return response;
}

Map<String, ToggleConfig> parseToggleResponse(String body) {
  var data = jsonDecode(body)['toggles'];
  // Check if there is anything to map over? Otherwise map might cause an error
  // Write a test that checks if the
  return Map.fromIterable(data,
      key: (toggle) => toggle['name'],
      value: (toggle) => ToggleConfig.fromJson(toggle));
}

class UnleashContext {
   String? userId;
   String? sessionId;
   String? remoteAddress;
   Map<String, String> properties = {};

  UnleashContext({this.userId, this.sessionId, this.remoteAddress, this.properties = const {}});

  Map<String, String> toSnapshot() {
    final params = <String, String>{};

    if (userId != null) {
      params.putIfAbsent('userId', () => userId!);
    }

    if (remoteAddress != null) {
      params.putIfAbsent('remoteAddress', () => remoteAddress!);
    }

    if (sessionId != null) {
      params.putIfAbsent('sessionId', () => sessionId!);
    }


    params.addAll(properties ?? {});

    return params;
  }
}

StorageProvider defaultProvider = InMemoryStorageProvider();

class UnleashClient extends EventEmitter {
  String url;
  final String clientKey;
  final String appName;
  final int refreshInterval;
  final Future<http.Response> Function(Uri, String) fetcher;
  Timer? timer;
  Map<String, ToggleConfig> toggles = {};
  StorageProvider storageProvider;

  UnleashClient(
      {required this.url,
      required this.clientKey,
      required this.appName,
      this.refreshInterval = 30,
      this.fetcher = get,
      storageProvider
      }): storageProvider = storageProvider ?? InMemoryStorageProvider();

  Future<Map<String, ToggleConfig>> fetchToggles() async {
    var response = await fetcher(Uri.parse(url), clientKey);
    await storageProvider.save('unleash_repo', response.body);

    return parseToggleResponse(response.body);
  }

  Future<void> updateContext(UnleashContext unleashContext) async {
    var contextSnapshot = unleashContext.toSnapshot();
    var queryParams = Uri(queryParameters: contextSnapshot).query;
    url = url+'?'+queryParams;
    await fetchToggles();
  }

  Future<void> start() async {
    toggles = await fetchToggles();

    emit('ready', 'feature toggle ready');
    timer = Timer.periodic(Duration(seconds: refreshInterval), (timer) {
      fetchToggles();
    });
  }

   stop() {
    final Timer? localTimer = timer;
    if(localTimer != null && localTimer.isActive) {
      localTimer.cancel();
    }
  }

  bool isEnabled(String featureName) {
    return toggles[featureName]?.enabled ?? false;
  }
}
