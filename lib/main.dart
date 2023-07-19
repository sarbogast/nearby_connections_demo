import 'dart:convert';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

const p2pServiceId = 'com.epseelon.nearby_connections_demo';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Nearby Connections Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _messageController = TextEditingController();
  final _nearby = Nearby();
  final List<String> _discoveredEndpoints = [];
  final String userId = const Uuid().v4();
  bool? _advertiser;
  bool _advertising = false;
  bool _discovering = false;

  String? _connectedEndpoint;
  String? _connectingEndpoint;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _startAdvertising() async {
    final locationStatus = await Permission.location.request();
    if (!locationStatus.isGranted) return;
    final locationEnabled = await Permission.location.serviceStatus.isEnabled;
    if (!locationEnabled) return;
    final permissionStatus = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan
    ].request();
    if (!permissionStatus.values.every((element) => element.isGranted)) return;

    bool advertising = await _nearby.startAdvertising(
      userId,
      Strategy.P2P_STAR,
      onConnectionInitiated: (String endpointId, ConnectionInfo info) async {
        debugPrint(
            'Connection initiated with ID $endpointId:\n- Endpoint: ${info.endpointName}\n- Authentication token: ${info.authenticationToken}\n- Incoming connection? ${info.isIncomingConnection ? 'YES' : 'NO'}');
        _nearby.acceptConnection(
          endpointId,
          onPayLoadRecieved: _onPayloadReceived,
          onPayloadTransferUpdate: _onPayloadTransferUpdate,
        );
      },
      onConnectionResult: (String endpointId, Status status) {
        debugPrint(
            'Connection result for connection with ID $endpointId: ${status.name}');
        setState(() {
          _connectedEndpoint = endpointId;
        });
      },
      onDisconnected: (String endpointId) {
        debugPrint('Disconnected from $endpointId');
        setState(() {
          _connectedEndpoint = null;
        });
      },
      serviceId: p2pServiceId,
    );

    setState(() {
      _advertising = advertising;
    });
  }

  Future<void> _stopAdvertising() async {
    await _nearby.stopAdvertising();
    setState(() {
      _advertising = false;
    });
  }

  Future<void> _startDiscovering() async {
    setState(() {
      _discoveredEndpoints.clear();
    });
    final locationStatus = await Permission.location.request();
    if (!locationStatus.isGranted) return;
    final locationEnabled = await Permission.location.serviceStatus.isEnabled;
    if (!locationEnabled) return;
    final permissionStatus = await [
      // Ask
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan
    ].request();
    if (!permissionStatus.values.every((element) => element.isGranted)) return;

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    final apiLevel = androidInfo.version.sdkInt;
    final wifiPermissionGranted = apiLevel >= 33
        ? await Permission.nearbyWifiDevices.request() ==
            PermissionStatus.granted
        : true;
    if (!wifiPermissionGranted) return;

    bool discovering = await Nearby().startDiscovery(
      userId,
      Strategy.P2P_STAR,
      onEndpointFound: (String endpointId, String userName, String serviceId) {
        debugPrint(
            'Endpoint found: $endpointId\n- User name: $userName\n- Service ID: $serviceId');
        setState(() {
          _discoveredEndpoints.add(endpointId);
        });
      },
      onEndpointLost: (String? endpointId) {
        debugPrint('Endpoint lost: $endpointId');
        setState(() {
          _discoveredEndpoints.remove(endpointId);
        });
      },
      serviceId: p2pServiceId,
    );

    setState(() {
      _discovering = discovering;
    });
  }

  Future<void> _stopDiscovering() async {
    await _nearby.stopDiscovery();
    setState(() {
      _discoveredEndpoints.clear();
      _discovering = false;
    });
  }

  void _exit() {
    if (_connectedEndpoint != null) {
      _nearby.disconnectFromEndpoint(_connectedEndpoint!);
    }
    if (_discovering) _stopDiscovering();
    if (_advertising) _stopAdvertising();
    setState(() {
      _advertiser = null;
      _discoveredEndpoints.clear();
    });
    _messageController.clear();
  }

  Future<void> _toggleConnection(String endpoint) async {
    if (_connectedEndpoint == null) {
      //connect to endpoint
      await _connect(endpoint);
    } else {
      if (_connectedEndpoint == endpoint) {
        //disconnect from endpoint
        await _nearby.disconnectFromEndpoint(_connectedEndpoint!);
        setState(() {
          _connectedEndpoint = null;
        });
      } else {
        //disconnect from old endpoint and connect to the new one
        await _nearby.disconnectFromEndpoint(_connectedEndpoint!);
        setState(() {
          _connectedEndpoint = null;
        });

        await _connect(endpoint);
      }
    }
  }

  Future<void> _connect(String endpoint) async {
    final connectionRequested = await _nearby.requestConnection(
      userId,
      endpoint,
      onConnectionInitiated: (endpointId, connectionInfo) {
        debugPrint(
            'Connection initiated with $endpointId:\n- Endpoint name: ${connectionInfo.endpointName}\n- Authentication token: ${connectionInfo.authenticationToken}\n- Is incoming? ${connectionInfo.isIncomingConnection ? 'YES' : 'NO'}');
        _nearby.acceptConnection(
          endpointId,
          onPayLoadRecieved: _onPayloadReceived,
          onPayloadTransferUpdate: _onPayloadTransferUpdate,
        );
        setState(() {
          _connectingEndpoint = endpointId;
          _connectedEndpoint = null;
        });
      },
      onConnectionResult: (endpointId, status) {
        debugPrint('Connection result with $endpointId: $status');
        switch (status) {
          case Status.CONNECTED:
            setState(() {
              _connectingEndpoint = null;
              _connectedEndpoint = endpointId;
            });
            break;
          case Status.REJECTED:
            setState(() {
              _connectingEndpoint = null;
              _connectedEndpoint = null;
            });
            break;
          case Status.ERROR:
            setState(() {
              _connectingEndpoint = null;
              _connectedEndpoint = null;
            });
        }
      },
      onDisconnected: (endpointId) {
        debugPrint('Disconnected from $endpointId');
        if (endpointId == _connectedEndpoint) {
          setState(() {
            _connectedEndpoint = null;
          });
        }
      },
    );

    setState(() {
      _connectingEndpoint = connectionRequested ? endpoint : null;
    });
  }

  Future<void> _onPayloadReceived(String endpointId, Payload payload) async {
    debugPrint('Payload received from $endpointId');
    if (payload.type == PayloadType.BYTES) {
      final message = utf8.decode(payload.bytes!);
      debugPrint('Message: $message');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }
  }

  Future<void> _onPayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate payloadTransferUpdate,
  ) async {
    debugPrint('Payload transfer update from $endpointId');
  }

  Future<void> _sendMessage(String message) async {
    if (_connectedEndpoint == null) return;
    try {
      await _nearby.sendBytesPayload(
        _connectedEndpoint!,
        Uint8List.fromList(utf8.encode(message)),
      );
      _messageController.clear();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_advertiser == null)
              ElevatedButton(
                onPressed: () => setState(() {
                  _advertiser = true;
                }),
                child: const Text("Advertiser"),
              ),
            if (_advertiser == null)
              ElevatedButton(
                onPressed: () => setState(() {
                  _advertiser = false;
                }),
                child: const Text('Discoverer'),
              ),
            if (_advertiser == true && !_advertising)
              ElevatedButton(
                onPressed: () => _startAdvertising(),
                child: const Text('Start Advertising'),
              ),
            if (_advertiser == true && _advertising)
              ElevatedButton(
                onPressed: () => _stopAdvertising(),
                child: const Text('Stop Advertising'),
              ),
            if (_advertiser == false && !_discovering)
              ElevatedButton(
                onPressed: () => _startDiscovering(),
                child: const Text('Start Discovering'),
              ),
            if (_advertiser == false && _discovering)
              ElevatedButton(
                onPressed: () => _stopDiscovering(),
                child: const Text('Stop Discovering'),
              ),
            if (_advertiser != null)
              ElevatedButton(
                onPressed: () => _exit(),
                child: const Text('Exit'),
              ),
            if (_connectedEndpoint != null)
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Message',
                ),
                controller: _messageController,
                onEditingComplete: () => _sendMessage(_messageController.text),
              ),
            if (_discoveredEndpoints.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _discoveredEndpoints.length,
                  itemBuilder: (context, index) {
                    final endpoint = _discoveredEndpoints[index];
                    return Card(
                      child: ListTile(
                        leading: _connectedEndpoint == endpoint
                            ? const Icon(Icons.check)
                            : (_connectingEndpoint == endpoint
                                ? const CircularProgressIndicator()
                                : null),
                        title: Text(endpoint),
                        onTap: _connectingEndpoint == null
                            ? () => _toggleConnection(endpoint)
                            : null,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
