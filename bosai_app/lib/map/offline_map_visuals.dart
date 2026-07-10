import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

const offlineMapHomeRadiusM = 3000.0;
const offlineMapInitialZoom = 14.2;

vtr.Theme buildOfflineMapVisualTheme() {
  final layers = <Map<String, dynamic>>[
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#f4f1eb'},
    },
    _lineLayer(
      'all-lines-base',
      '#d2c8b8',
      width: 1.1,
      minzoom: 10,
    ),
    _lineLayer(
      'waterway-line',
      '#8fc3d8',
      width: 1.8,
      filter: [
        'in',
        'waterway',
        'river',
        'canal',
        'stream',
        'drain',
        'ditch',
      ],
    ),
    _lineLayer(
      'railway-line',
      '#9e9e9e',
      width: 1.2,
      minzoom: 12,
      filter: [
        'in',
        'railway',
        'rail',
        'subway',
        'tram',
        'light_rail',
        'monorail',
      ],
    ),
    _lineLayer(
      'major-road-casing',
      '#fff8ec',
      width: 6.2,
      minzoom: 10,
      filter: [
        'in',
        'highway',
        'motorway',
        'trunk',
        'primary',
        'secondary',
        'tertiary',
      ],
    ),
    _lineLayer(
      'minor-road-casing',
      '#ffffff',
      width: 4.0,
      minzoom: 12,
      filter: [
        'in',
        'highway',
        'residential',
        'unclassified',
        'service',
        'living_street',
        'road',
      ],
    ),
    _lineLayer(
      'path-line',
      '#c9b79c',
      width: 1.4,
      minzoom: 13,
      filter: [
        'in',
        'highway',
        'footway',
        'path',
        'cycleway',
        'pedestrian',
        'steps',
      ],
    ),
    _lineLayer(
      'major-road-line',
      '#d88b55',
      width: 2.8,
      minzoom: 10,
      filter: [
        'in',
        'highway',
        'motorway',
        'trunk',
        'primary',
        'secondary',
        'tertiary',
      ],
    ),
    _lineLayer(
      'minor-road-line',
      '#c8b89f',
      width: 1.8,
      minzoom: 12,
      filter: [
        'in',
        'highway',
        'residential',
        'unclassified',
        'service',
        'living_street',
        'road',
      ],
    ),
    _roadLabelLayer(
      'road-label',
      minzoom: 13,
    ),
  ];

  return vtr.ThemeReader().read({
    'id': 'bosai-offline-map',
    'version': 8,
    'metadata': {
      'version': 'roads-only-v3',
    },
    'sources': {
      'pmtiles': {'type': 'vector', 'url': 'pmtiles'},
    },
    'layers': layers,
  });
}

VectorTileLayer buildOfflineBaseMapLayer(
  PmTilesVectorTileProvider tileProvider,
) {
  return VectorTileLayer(
    theme: buildOfflineMapVisualTheme(),
    tileProviders: TileProviders({'pmtiles': tileProvider}),
    fileCacheTtl: Duration.zero,
    memoryTileDataCacheMaxSize: 0,
  );
}

CircleLayer buildHomeRadiusLayer(LatLng home) {
  return CircleLayer(
    circles: [
      CircleMarker(
        point: home,
        radius: offlineMapHomeRadiusM,
        useRadiusInMeter: true,
        color: const Color(0x163C8D5A),
        borderColor: const Color(0xAA2E7D32),
        borderStrokeWidth: 2,
      ),
    ],
  );
}

LatLngBounds boundsForHomeRadius(LatLng center) {
  const latDelta = offlineMapHomeRadiusM / 111320.0;
  final lonDelta =
      offlineMapHomeRadiusM / (111320.0 * math.cos(center.latitudeInRad));
  return LatLngBounds(
    LatLng(center.latitude - latDelta, center.longitude - lonDelta),
    LatLng(center.latitude + latDelta, center.longitude + lonDelta),
  );
}

Map<String, dynamic> _lineLayer(
  String id,
  String color, {
  required double width,
  double? minzoom,
  List<Object>? filter,
}) {
  return {
    'id': id,
    'type': 'line',
    'source': 'pmtiles',
    'source-layer': 'roads',
    if (minzoom != null) 'minzoom': minzoom,
    if (filter != null) 'filter': filter,
    'paint': {
      'line-color': color,
      'line-width': width,
    },
  };
}

Map<String, dynamic> _roadLabelLayer(
  String id, {
  required double minzoom,
}) {
  return {
    'id': id,
    'type': 'symbol',
    'source': 'pmtiles',
    'source-layer': 'roads',
    'minzoom': minzoom,
    'layout': {
      'symbol-placement': 'line',
      'text-field': ['get', 'name'],
      'text-size': 11,
      'text-max-width': 8,
    },
    'paint': {
      'text-color': '#6f5b4a',
      'text-halo-color': '#fffaf2',
      'text-halo-width': 2,
    },
  };
}
