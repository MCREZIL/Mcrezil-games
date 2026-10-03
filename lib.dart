import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';

void main() => runApp(McrezilApp());

class McrezilApp extends StatelessWidget {
  @override Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MCREZIL GAME LABS',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Color(0xFF0A0A0A)),
      home: HomeScreen(),
    );
  }
}

enum Role { hunter, runner }

class PlayerModel {
  String id; String name; Role role; bool isHost; bool isLateJoin;
  PlayerModel({required this.id, required this.name, this.role = Role.runner, this.isHost = false, this.isLateJoin = false});
}

class HomeScreen extends StatelessWidget {
  @override Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text("MCREZIL", style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
        Text("GAME LABS", style: TextStyle(fontSize: 20, letterSpacing: 6, color: Colors.white70)),
        SizedBox(height: 40),
        ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyScreen(isHost: true))), child: Text("CREATE LOBBY (HOST)"), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFFD700), foregroundColor: Colors.black, minimumSize: Size(250,50))),
        SizedBox(height: 20),
        ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LobbyScreen(isHost: false))), child: Text("JOIN LOBBY (SCAN QR)"), style: ElevatedButton.styleFrom(minimumSize: Size(250,50))),
      ])),
    );
  }
}

class LobbyScreen extends StatefulWidget {
  final bool isHost;
  LobbyScreen({required this.isHost});
  @override State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  List<PlayerModel> players = [];
  bool gameStarted = false;
  String roomCode = "";
  Strategy strategy = Strategy.P2P_STAR;

  @override void initState() {
    super.initState();
    _requestPerms();
    roomCode = _genCode();
    if(widget.isHost) {
      players.add(PlayerModel(id: "host", name: "YOU • HOST", role: Role.hunter, isHost: true));
      _startAdvertising();
    } else {
      _startDiscovery();
    }
  }

  String _genCode() {
    var rnd = Random(); const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _requestPerms() async {
    await [Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location, Permission.nearbyWifiDevices].request();
  }

  void _startAdvertising() async {
    await Nearby().startAdvertising("MCREZIL-$roomCode", strategy,
      onConnectionInitiated: (id, info) {
        if(players.length >= 10) { Nearby().rejectConnection(id); return; }
        Nearby().acceptConnection(id, onPayLoadRecieved: (a,p) {});
      },
      onConnectionResult: (id, status) {
        if(status == Status.CONNECTED) {
          setState(() {
            if(gameStarted) {
              players.add(PlayerModel(id: id, name: "RUNNER ${players.length+1}", role: Role.runner, isLateJoin: true));
              Nearby().sendBytesPayload(id, "SPAWN_AS_RUNNER_WITH_SHIELD_3SEC".codeUnits);
            } else {
              players.add(PlayerModel(id: id, name: "PLAYER ${players.length+1}", role: Role.runner));
            }
          });
        }
      },
      onDisconnected: (id) => setState(()=> players.removeWhere((p)=>p.id==id))
    );
  }

  void _startDiscovery() async {
    await Nearby().startDiscovery("MCREZIL", strategy,
      onEndpointFound: (id, name, serviceId) {
        if(name.contains("MCREZIL")) Nearby().requestConnection(name, id, onConnectionInitiated: (a,b){ Nearby().acceptConnection(a, onPayLoadRecieved: (x,y){}); });
      },
      onEndpointLost: (id){},
    );
  }

  void setRole(int index, Role role) {
    if(gameStarted) return;
    if(!widget.isHost &&!players[index].isHost) return; // only host can set
    setState(()=> players[index].role = role);
  }

  void startGame() {
    if(players.length < 2) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Need at least 2 players"))); return; }
    if(players.where((p)=>p.role==Role.hunter).isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pick at least 1 Hunter!"))); return; }
    setState(()=> gameStarted = true);
    Nearby().sendBytesPayloadToAll("GAME_STARTED_ROLES_LOCKED".codeUnits);
    Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(players: players, roomCode: roomCode)));
  }

  @override Widget build(BuildContext context) {
    int hunters = players.where((p)=>p.role==Role.hunter).length;
    int runners = players.where((p)=>p.role==Role.runner).length;
    return Scaffold(
      appBar: AppBar(title: Text("MCREZIL GAME LABS • $roomCode"), backgroundColor: Colors.black, actions: [Icon(Icons.bluetooth), SizedBox(width:10), Icon(Icons.wifi)]),
      body: Column(children: [
        Container(padding: EdgeInsets.all(12), color: Color(0xFF1A1A1A), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("PLAYERS ${players.length}/10 JOINED", style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          Text("Bluetooth • WiFi Direct • Ready", style: TextStyle(color: Colors.green, fontSize: 12))
        ])),
        if(widget.isHost) QrImageView(data: "MCREZIL://JOIN?room=$roomCode", version: QrVersions.auto, size: 120, backgroundColor: Colors.white),
        Expanded(child: ListView.builder(itemCount: players.length, itemBuilder: (c,i) => Container(margin: EdgeInsets.all(6), padding: EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: Color(0xFFFFD700)), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(players[i].name, style: TextStyle(color: Colors.white)),
          Row(children: [
            ChoiceChip(label: Text("HUNTER"), selected: players[i].role==Role.hunter, onSelected: (v)=> setRole(i, Role.hunter), selectedColor: Color(0xFFFFD700)),
            SizedBox(width: 8),
            ChoiceChip(label: Text("RUNNER"), selected: players[i].role==Role.runner, onSelected: (v)=> setRole(i, Role.runner), selectedColor: Color(0xFFFFD700)),
          ]),
          if(players[i].isHost) Icon(Icons.star, color: Color(0xFFFFD700)),
          if(players[i].isLateJoin) Text("LATE", style: TextStyle(color: Colors.orange, fontSize: 10))
        ])))),
        Container(padding: EdgeInsets.all(10), child: Text("Current: $hunters HUNTER • $runners RUNNER • Role lock after START", style: TextStyle(color: Colors.white70))),
        if(widget.isHost) Padding(padding: EdgeInsets.all(10), child: ElevatedButton(onPressed: startGame, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFFD700), foregroundColor: Colors.black, minimumSize: Size(double.infinity, 55)), child: Text("READY • START (${players.length}/10)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
        if(gameStarted) Padding(padding: EdgeInsets.all(8), child: Text("Game Started - Late joiners become RUNNERS only", style: TextStyle(color: Colors.green)))
      ]),
    );
  }
}

class GameScreen extends StatelessWidget {
  final List<PlayerModel> players; final String roomCode;
  GameScreen({required this.players, required this.roomCode});
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text("MCREZIL CHASE • $roomCode")), body: Center(child: Text("Game Started: ${players.length} players\nHunters: ${players.where((p)=>p.role==Role.hunter).length}\nRunners: ${players.where((p)=>p.role==Role.runner).length}\n\nLate join QR still active → New players = RUNNER", textAlign: TextAlign.center)));
  }
}