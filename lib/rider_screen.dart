import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RiderApp extends StatefulWidget {
  final String riderId;

  const RiderApp({Key? key, required this.riderId}) : super(key: key);

  @override
  _RiderAppState createState() => _RiderAppState();
}

class _RiderAppState extends State<RiderApp> {
  final String _googleApiKey = 'AIzaSyBRnEko4bCvcNYb7sO9BgxT4T6Uzq8ol4c';
  late WebSocketChannel channel;
  String? orderId;
  LatLng _currentLocation = LatLng(11.5564, 104.9282);
  LatLng _destinationLocation = LatLng(11.5431, 104.9383);
  GoogleMapController? _mapController;
  late Marker _riderMarker;
  late Polyline _routePolyline;
  final Location _location = Location();
  bool _isSendingUpdates = false;

  @override
  void initState() {
    super.initState();
    _riderMarker = Marker(
      markerId: MarkerId('rider'),
      position: _currentLocation,
    );
    _routePolyline = Polyline(
      polylineId: PolylineId('route'),
      points: [],
      color: Colors.blue,
      width: 5,
    );
    _initializeWebSocket();
    _startRealTimeLocationUpdates();
  }

  Future<void> _fetchDirections() async {
    String url = 'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${_currentLocation.latitude},${_currentLocation.longitude}'
        '&destination=${_destinationLocation.latitude},${_destinationLocation.longitude}'
        '&key=$_googleApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final points = PolylinePoints().decodePolyline(
            data['routes'][0]['overview_polyline']['points']);

        setState(() {
          _routePolyline = Polyline(
            polylineId: PolylineId('route'),
            points: points.map((point) => LatLng(point.latitude, point.longitude)).toList(),
            color: Colors.blue,
            width: 5,
          );
        });

        log('Route updated with directions');
      } else {
        log('Failed to fetch directions: ${data['status']}');
      }
    } else {
      log('Error fetching directions');
    }
  }

  void _initializeWebSocket() {
    channel = WebSocketChannel.connect(
      Uri.parse('ws://192.168.146.1:8080'),
    );

    channel.stream.listen((message) {
      final data = json.decode(message);
      if (data['type'] == 'orderAssigned') {
        setState(() {
          orderId = data['orderId'];
        });
        log('New Order Assigned: $orderId');
        _fetchOrderDetails();
      }
    });
  }

  Future<void> _fetchOrderDetails() async {
    if (orderId == null) return;

    final response = await http.get(Uri.parse('http://192.168.137.26:3000/api/orders/$orderId'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final lat = data['destination']['latitude'];
      final lon = data['destination']['longitude'];

      setState(() {
        _destinationLocation = LatLng(lat, lon);
      });
      _fetchDirections();
    } else {
      log('Failed to fetch order details');
    }
  }

  void _startRealTimeLocationUpdates() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    _location.onLocationChanged.listen((LocationData locationData) {
      final newLocation = LatLng(locationData.latitude!, locationData.longitude!);

      setState(() {
        _currentLocation = newLocation;
        _riderMarker = Marker(
          markerId: MarkerId('rider'),
          position: newLocation,
        );

        if (orderId != null) {
          _routePolyline = Polyline(
            polylineId: PolylineId('route'),
            points: [newLocation, _destinationLocation],
            color: Colors.blue,
            width: 5,
          );
        }
      });

      if (!_isSendingUpdates) {
        _isSendingUpdates = true;
        channel.sink.add(
          json.encode({
            'type': 'locationUpdate',
            'orderId': orderId,
            'riderId': widget.riderId,
            'latitude': locationData.latitude,
            'longitude': locationData.longitude,
          }),
        );
        _isSendingUpdates = false;
      }

      if (_mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(newLocation));
      }
    });
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rider App')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _currentLocation, zoom: 20),
        markers: {_riderMarker},
        polylines: {_routePolyline},
        onMapCreated: (controller) => _mapController = controller,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}
