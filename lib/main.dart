import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_map_polyline/google_map_polyline.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

void main() => runApp(Main());

class Main extends StatefulWidget {
  @override
  _MainState createState() => _MainState();
}

class _MainState extends State<Main> {

  BitmapDescriptor bikeIcon;

  @override
  void initState() {
    BitmapDescriptor.fromAssetImage(
        ImageConfiguration(size: Size(.5, .5)), 'assets/bike.jpg')
        .then((onValue) {
      this.bikeIcon = onValue;
    });

    getMyLocation();
    super.initState();
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png)).buffer.asUint8List();
  }

  /// Recebe a google API Directions
  GoogleMapPolyline _googleMapPolyline = GoogleMapPolyline(apiKey: "INSIRA SUA API KEY");

  int _polylineCount = 1;

  /// Map das polynines que serão registradas
  Map<PolylineId, Polyline> _polylines = <PolylineId, Polyline>{};

  /// Polyline patterns
  List<List<PatternItem>> patterns = <List<PatternItem>>[
    <PatternItem>[], //line
    <PatternItem>[PatternItem.dash(30.0), PatternItem.gap(20.0)], //dash
    <PatternItem>[PatternItem.dot, PatternItem.gap(10.0)], //dot
    <PatternItem>[
      //dash-dot
      PatternItem.dash(30.0),
      PatternItem.gap(20.0),
      PatternItem.dot,
      PatternItem.gap(20.0)
    ],
  ];

  //Variável que recebe os dados da localização do usuário
  LocationData currentLocation;

  /// Variável de localização
  Location location = Location();

  /// Recupera a posição do usuário
  getMyLocation() async {

    /// Mensagens da plataforma podem falhar, então é usado um try/catch PlatformException.
    try {
      this.currentLocation = await this.location.getLocation();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        String error = 'Permission denied';
      }
      this.currentLocation = null;
    }

    /// Atualiza constantemente a ultima posição do usuário
    this.location.onLocationChanged().listen((LocationData currentLocation) {
      this._lastUserPosition = LatLng(currentLocation.latitude, currentLocation.longitude);
    });
  }

  /// Controlador do google maps
  Completer<GoogleMapController> _controller = Completer();

  /// Centro da cidade de SP em coordenadas de latitude e longitude
  static const LatLng _center = const LatLng(-23.550897, -46.633149);

  /// Conjunto de markers
  Set<Marker> _markers = {};

  /// Definindo a primeira posição da variável
  LatLng _lastMapPosition = _center;

  LatLng _lastUserPosition;

  /// Os tipos de mapa são: normal, hybrid, terrain, satellite e none
  MapType _currentMapType = MapType.normal;

  /// Verifica o tipo da variável atual e altera para um novo valor de tipo de mapa
  void _onMapTypeButtonPressed() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.satellite
          : MapType.normal;
    });
  }

  /// Adiciona um marker ao Set de marcadores
  void _onAddMarkerButtonPressed() async {
    final Uint8List markerIcon = await getBytesFromAsset('assets/bike.jpg', 70);
    setState(() {

      /// Limpa o set de marcadores e então adiciona um novo, fazendo com que só se tenha um marcador
      /// de _markers no mapa

      this._markers = {};
      getAddress(this._lastMapPosition.latitude, this._lastMapPosition.longitude);
      this._markers.add(Marker(

        /// Este id de marcador pode ser qualquer coisa que identifica únicamente cada marcador
        markerId: MarkerId(this._lastMapPosition.toString()),

        /// Posição do marcador será a coordenada atual do mapa
        /// Pode-se tambem adicionar manualmente um marcador em uma posição específica, por ex:
        /// LatLng(-23.550897, -46.633149)
        position: this._lastMapPosition,
        infoWindow: InfoWindow(
          
          // Janela com título e descrição do marcador
          title: 'Really cool place',
          snippet: this._address,
        ),
        icon: BitmapDescriptor.defaultMarker,
      ));

      /// Marker da localização do usuário
      this._markers.add(Marker(

        /// Este id de marcador pode ser qualquer coisa que identifica únicamente cada marcador
        markerId: MarkerId(this._lastUserPosition.toString()),

        /// Posição do marcador será a coordenada atual do mapa
        /// Pode-se tambem adicionar manualmente um marcador em uma posição específica, por ex:
        /// LatLng(-23.550897, -46.633149)
        position: this._lastUserPosition,
        infoWindow: InfoWindow(

          // Janela com título e descrição do marcador
          title: 'Really cool biker',
          snippet: '5 Star Rating',
        ),
        icon: BitmapDescriptor.fromBytes(markerIcon),
      ));
    });
    await _getPolylinesWithLocation();
    getTravelDistance();
  }

  /// Recupera o ponto central do mapa (centro da camera)
  CameraPosition _onCameraMove(CameraPosition position) {
    this._lastMapPosition = position.target;
  }


  GoogleMapController _onMapCreated(GoogleMapController controller) {
    this._controller.complete(controller);
  }

  _getPolylinesWithLocation() async {
    List<LatLng> _coordinates =
    await _googleMapPolyline.getCoordinatesWithLocation(
        origin: _lastUserPosition,
        destination: _markers.elementAt(0).position,
        mode: RouteMode.driving);

    setState(() {
      this._polylines.clear();
    });
    _addPolyline(_coordinates);
  }

  /// Cria a rota do maps com dados de endereço
  _addPolyline(List<LatLng> _coordinates) {
    PolylineId id = PolylineId("poly$_polylineCount");
    Polyline polyline = Polyline(
        polylineId: id,
        patterns: this.patterns[0],
        color: Colors.deepOrange,
        points: _coordinates,
        width: 5,
        onTap: () {});

    setState(() {
      this._polylines[id] = polyline;
      this._polylineCount++;
    });
  }

  /// http client
  Dio dio = Dio();

  getTravelDistance() async {
    Response response = await dio.get(
        /// Realizando um http request no google cloud para obter o endereco atravez das coordenadas
        "https://maps.googleapis.com/maps/api/distancematrix/json?units=metric&origins=${_lastUserPosition
            .latitude},${_lastUserPosition.longitude}&destinations=${_markers
            .elementAt(0)
            .position
            .latitude}%2C${_markers
            .elementAt(0)
            .position
            .longitude}%7C&key=INSIRA SUA API KEY"
    );
    print('TRAVEL DISTANCE--------------------');
    print(response.data);
    print('TRAVEL DISTANCE--------------------');
  }

  List<Placemark> placemark;
  String _address;
  Future<String> getAddress(double lat, double lng) async {
    placemark = await Geolocator().placemarkFromCoordinates(lat, lng);
    _address = placemark[0].thoroughfare.toString() + ", " + placemark[0].name.toString();
    print('>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<');
    print(placemark[0].position);
    print(placemark[0].administrativeArea);
    print(placemark[0].country);
    print(placemark[0].name);
    print(placemark[0].postalCode);
    print(placemark[0].thoroughfare);
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Center(child: Text('Veloo')),
          backgroundColor: Colors.deepOrange[700],
        ),
        body: Stack(
          children: <Widget>[
            GoogleMap(

              /// Exibe o transito
              trafficEnabled: false,

              /// Exibe uma bússola no canto superior esquerdo ao rotacionar o mapa
              compassEnabled: true,

              /// Habilita o Google Maps Indoor, para ambientes internos
              indoorViewEnabled: false,

              /// Habilita rotação de mapa
              rotateGesturesEnabled: true,

              /// Habilita a toolbar no canto inferios direito
              mapToolbarEnabled: true,

              /// Habilite o scroll do mapa
              scrollGesturesEnabled: true,

              /// Habilita a inclinação do mapa
              /// Como reproduzir: deslize verticalmente dois dedos na tela
              tiltGesturesEnabled: true,

              /// Habilita zoom no mapa
              zoomGesturesEnabled: true,

              /// Habilita a localização do usuário, dadas as devidas permissões configuradas no nativo
              myLocationEnabled: true,


              /// Habilita o botão de centralizar a posição do usuário
              myLocationButtonEnabled: true,
              onMapCreated: _onMapCreated,

              /// Recebe a posição inicial do mapa ao ser carregado
              initialCameraPosition: CameraPosition(
                target: this._lastMapPosition,
                zoom: 15.0,
              ),

              /// Define o tipo de mapa
              mapType: this._currentMapType,

              /// Set de marcadores que serão adicionados ao mapa
              markers: this._markers,

              /// Atualiza a posição de camera
              onCameraMove: _onCameraMove,

              /// Rotas do maps
              polylines: Set<Polyline>.of(this._polylines.values),

            ),
            Padding(
              padding: const EdgeInsets.all(5.0),
              child: Align(
                alignment: Alignment.topRight,
                child: Column(
                  children: <Widget> [
                    SizedBox(height: 60,),
                    FloatingActionButton(
                      onPressed: _onMapTypeButtonPressed,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      backgroundColor: Colors.deepOrange,
                      child: const Icon(Icons.map, size: 36.0),
                    ),
                    SizedBox(height: 16.0),
                    FloatingActionButton(
                      onPressed: _onAddMarkerButtonPressed,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      backgroundColor: Colors.deepOrange,
                      child: const Icon(Icons.add_location, size: 36.0),
                    ),

                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}