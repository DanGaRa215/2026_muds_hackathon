import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../db/database_helper.dart';
import '../routing/models.dart';
import '../routing/precompute_service.dart';
import '../routing/route_service.dart';
import '../routing_bootstrap.dart';
import 'prepare_screen.dart';

class NaviScreen extends StatefulWidget {
  const NaviScreen({
    super.key,
    required this.shelter,
    required this.mode,
  });

  final ShelterInfo shelter;
  final DisasterMode mode;

  @override
  State<NaviScreen> createState() => _NaviScreenState();
}

class _NaviScreenState extends State<NaviScreen> {
  static const _homeLocationSeparator = '||home=';
  static const _defaultCenter = LatLng(35.7068, 139.8683);
  static const _floodGuidance = '大規模水害時は、時間に余裕がある場合は浸水しない地域への広域避難、'
      '余裕がない場合は近くの建物の3階以上への避難(垂直避難)が基本です。'
      'この経路は参考情報です';

  PmTilesVectorTileProvider? _tileProvider;
  LatLng? _currentPosition;
  LatLng? _homeLocation;
  final Map<WeightProfile, RouteResult> _routesByProfile = {};
  final Map<WeightProfile, String> _routeSourceLabelsByProfile = {};
  WeightProfile _selectedProfile = WeightProfile.balanced;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isRouteLoading = false;
  bool _needsHomeRegistration = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final localPath = await _copyAssetToLocal('tokyo23_buffered.pmtiles');
      final provider = await PmTilesVectorTileProvider.fromSource(localPath);
      final routeService = await RoutingBootstrap.routeService();
      final precomputeService = PrecomputeService(routeService);
      final homeLocation = await _loadHomeLocation();

      LatLng? currentPosition;
      try {
        currentPosition = await _getCurrentLocation();
      } catch (e) {
        debugPrint('Location unavailable: $e');
      }

      _RouteLoadResult? loadedRoute;
      if (homeLocation != null) {
        loadedRoute = await _resolveRoute(
          routeService: routeService,
          precomputeService: precomputeService,
          homeLocation: homeLocation,
          currentPosition: currentPosition,
          profile: _selectedProfile,
        );
      }

      if (!mounted) return;
      setState(() {
        _tileProvider = provider;
        _currentPosition = currentPosition;
        _homeLocation = homeLocation;
        final route = loadedRoute?.route;
        if (route != null) {
          _routesByProfile[_selectedProfile] = route;
          _routeSourceLabelsByProfile[_selectedProfile] =
              loadedRoute!.sourceLabel!;
        }
        _needsHomeRegistration = homeLocation == null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<String> _copyAssetToLocal(String assetName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$assetName');

    if (!file.existsSync()) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    return file.path;
  }

  Future<LatLng?> _loadHomeLocation() async {
    final info = await DatabaseHelper.instance.getHomeInfo();
    final rawStructure = info?['structure'] as String?;
    if (rawStructure == null) {
      return null;
    }

    final separatorIndex = rawStructure.indexOf(_homeLocationSeparator);
    if (separatorIndex < 0) {
      return null;
    }

    final values =
        rawStructure.substring(separatorIndex + _homeLocationSeparator.length);
    final parts = values.split(',');
    if (parts.length != 2) {
      return null;
    }

    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) {
      return null;
    }
    return LatLng(lat, lon);
  }

  Future<RouteResult?> _loadPrecomputedRoute(
    PrecomputeService precomputeService,
    WeightProfile profile,
  ) async {
    final routes = await precomputeService.loadPrecomputed(
      mode: widget.mode,
      profile: profile,
    );
    for (final route in routes) {
      if (route.shelterId == widget.shelter.shelterId) {
        return route;
      }
    }
    return null;
  }

  Future<_RouteLoadResult> _resolveRoute({
    required RouteService routeService,
    required PrecomputeService precomputeService,
    required LatLng homeLocation,
    required LatLng? currentPosition,
    required WeightProfile profile,
  }) async {
    RouteResult? route;
    String? routeSourceLabel;

    if (currentPosition != null &&
        _distanceM(currentPosition, homeLocation) >= 300) {
      route = await routeService.findRoute(
        from: currentPosition,
        shelterId: widget.shelter.shelterId,
        mode: widget.mode,
        profile: profile,
      );
      if (route != null) {
        routeSourceLabel = '現在地から計算';
      }
    }

    route ??= await _loadPrecomputedRoute(precomputeService, profile);
    routeSourceLabel ??= route == null ? null : '自宅からの保存ルート';

    return _RouteLoadResult(route: route, sourceLabel: routeSourceLabel);
  }

  Future<void> _loadRouteForProfile(WeightProfile profile) async {
    final homeLocation = _homeLocation;
    if (homeLocation == null ||
        _isRouteLoading ||
        _routesByProfile.containsKey(profile)) {
      return;
    }

    setState(() => _isRouteLoading = true);
    try {
      final routeService = await RoutingBootstrap.routeService();
      final result = await _resolveRoute(
        routeService: routeService,
        precomputeService: PrecomputeService(routeService),
        homeLocation: homeLocation,
        currentPosition: _currentPosition,
        profile: profile,
      );
      if (!mounted) return;
      setState(() {
        final route = result.route;
        if (route != null) {
          _routesByProfile[profile] = route;
          _routeSourceLabelsByProfile[profile] = result.sourceLabel!;
        }
        _isRouteLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isRouteLoading = false;
      });
    }
  }

  void _onProfileSelectionChanged(Set<WeightProfile> selection) {
    if (_isRouteLoading) {
      return;
    }
    final profile = selection.single;
    if (profile == _selectedProfile) {
      return;
    }
    setState(() => _selectedProfile = profile);
    _loadRouteForProfile(profile);
  }

  RouteResult? get _selectedRoute => _routesByProfile[_selectedProfile];

  String? get _selectedRouteSourceLabel =>
      _routeSourceLabelsByProfile[_selectedProfile];

  Future<LatLng?> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    return LatLng(position.latitude, position.longitude);
  }

  double _distanceM(LatLng a, LatLng b) {
    const earthRadiusM = 6371000.0;
    const degToRad = math.pi / 180;
    final dLat = (b.latitude - a.latitude) * degToRad;
    final dLon = (b.longitude - a.longitude) * degToRad;
    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);
    final h = sinLat * sinLat +
        math.cos(a.latitude * degToRad) *
            math.cos(b.latitude * degToRad) *
            sinLon *
            sinLon;
    return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  vtr.Theme _buildRoadsTheme() {
    return vtr.ThemeReader().read({
      'version': 8,
      'sources': {
        'pmtiles': {
          'type': 'vector',
          'url': 'pmtiles',
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {
            'background-color': '#e8e8e8',
          },
        },
        {
          'id': 'roads-line',
          'type': 'line',
          'source': 'pmtiles',
          'source-layer': 'roads',
          'paint': {
            'line-color': '#B8C1CC',
            'line-width': 2.0,
          },
        },
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('避難ナビ'),
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('避難ルートを読み込み中...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Error: $_errorMessage',
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_needsHomeRegistration) {
      return _buildHomeRegistrationPrompt();
    }

    final route = _selectedRoute;
    if (route == null) {
      if (_isRouteLoading) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('選択中のルートを読み込み中...'),
            ],
          ),
        );
      }
      return _buildMissingRoutePrompt();
    }

    return Column(
      children: [
        Expanded(child: _buildMap(route)),
        _buildRouteSummary(route),
      ],
    );
  }

  Widget _buildHomeRegistrationPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.home_work, size: 72, color: Colors.blueGrey),
            const SizedBox(height: 16),
            const Text(
              '自宅を登録してください',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'オフラインで使う避難ルートを表示するには、先に避難準備で自宅位置を登録してください。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrepareScreen()),
                );
              },
              icon: const Icon(Icons.add_location_alt),
              label: const Text('自宅登録へ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingRoutePrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.route, size: 72, color: Colors.blueGrey),
            const SizedBox(height: 16),
            const Text(
              '保存ルートが見つかりません',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '避難準備で自宅位置を登録し、避難ルートを保存してください。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrepareScreen()),
                );
              },
              icon: const Icon(Icons.add_location_alt),
              label: const Text('自宅登録へ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(RouteResult route) {
    final points = route.geometry.isEmpty
        ? [widget.shelter.latLng]
        : [...route.geometry, widget.shelter.latLng];
    final initialCameraFit = points.length >= 2
        ? CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
            maxZoom: 16,
          )
        : null;

    return FlutterMap(
      options: MapOptions(
        initialCenter: initialCameraFit == null ? _defaultCenter : points.first,
        initialZoom: 14,
        initialCameraFit: initialCameraFit,
        minZoom: 10,
        maxZoom: 16,
      ),
      children: [
        VectorTileLayer(
          theme: _buildRoadsTheme(),
          tileProviders: TileProviders({
            'pmtiles': _tileProvider!,
          }),
        ),
        if (route.geometry.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.geometry,
                color: Colors.white,
                strokeWidth: 9,
              ),
              Polyline(
                points: route.geometry,
                color: const Color(0xFFFF6D00),
                strokeWidth: 7,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (_currentPosition != null)
              Marker(
                point: _currentPosition!,
                width: 36,
                height: 36,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 28,
                ),
              ),
            Marker(
              point: widget.shelter.latLng,
              width: 180,
              height: 64,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 32,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 8,
                          color: Color(0x33000000),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        widget.shelter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_selectedRouteSourceLabel != null)
          Positioned(
            top: 12,
            left: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(blurRadius: 8, color: Color(0x22000000)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  _selectedRouteSourceLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRouteSummary(RouteResult route) {
    final walkMinutes = route.estMinutes.ceil();
    final distanceKm = (route.distanceM / 1000).toStringAsFixed(1);
    final safetyScore = route.safetyScore.round().clamp(0, 100);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<WeightProfile>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: WeightProfile.fastest,
                  label: Text('最短'),
                ),
                ButtonSegment(
                  value: WeightProfile.balanced,
                  label: Text('バランス'),
                ),
                ButtonSegment(
                  value: WeightProfile.safest,
                  label: Text('安全重視'),
                ),
              ],
              selected: {_selectedProfile},
              onSelectionChanged:
                  _isRouteLoading ? null : _onProfileSelectionChanged,
            ),
            if (_isRouteLoading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            if (widget.mode == DisasterMode.flood) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    _floodGuidance,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (route.usedFallback) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'この経路は通行危険箇所(アンダーパス等)を含む可能性があります',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '目的地: ${widget.shelter.name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: '徒歩時間',
                    value: '$walkMinutes分',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: '距離',
                    value: '${distanceKm}km',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: '安全度',
                    value: '$safetyScore/100',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () async {
                final navigator = Navigator.of(context);
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('到着を記録しました'),
                    content: const TextField(
                      decoration: InputDecoration(hintText: '安否メモ（任意・デモ）'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                if (mounted) {
                  navigator.popUntil((r) => r.isFirst);
                }
              },
              child: const Text(
                '到着した',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteLoadResult {
  const _RouteLoadResult({
    required this.route,
    required this.sourceLabel,
  });

  final RouteResult? route;
  final String? sourceLabel;
}
