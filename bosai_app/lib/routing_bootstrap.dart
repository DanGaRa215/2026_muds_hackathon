import 'routing/precompute_service.dart';
import 'routing/route_service.dart';

class RoutingBootstrap {
  RoutingBootstrap._();

  static RouteService? _routeService;
  static Future<RouteService>? _routeServiceFuture;

  static Future<RouteService> routeService() {
    final service = _routeService;
    if (service != null) {
      return Future.value(service);
    }

    final future = _routeServiceFuture;
    if (future != null) {
      return future;
    }

    final created = RouteService.create().then((service) {
      _routeService = service;
      return service;
    });
    _routeServiceFuture = created.whenComplete(() {
      if (_routeService == null) {
        _routeServiceFuture = null;
      }
    });
    return _routeServiceFuture!;
  }

  static Future<PrecomputeService> precomputeService() async {
    return PrecomputeService(await routeService());
  }
}
