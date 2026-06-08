class AppConfig {

  //main server
  // static const String serverHost = "187.127.170.86";


  //joshusa
  //  static const String serverHost = "192.168.42.83";



//helll
  //thangu
   static const String serverHost = "192.168.137.188";




  static const String httpBase = "http://$serverHost:8001";
  static const String wsBase = "ws://$serverHost:8001";

  static const Map<String, dynamic> iceServers = {
    "iceServers": [
      {
        "urls": "stun:stun.l.google.com:19302",
      },
      {
        "urls": "turn:joshuastar.metered.live:80",
        "username": "ef0c9c93e9200df0ff93e4a0",
        "credential": "rZKQllGSj+d4dzyV",
      },
      {
        "urls": "turn:joshuastar.metered.live:443",
        "username": "ef0c9c93e9200df0ff93e4a0",
        "credential": "rZKQllGSj+d4dzyV",
      },
      {
        "urls": "turns:joshuastar.metered.live:443",
        "username": "ef0c9c93e9200df0ff93e4a0",
        "credential": "rZKQllGSj+d4dzyV",
      },
    ],
  };

  //   static const Map<String, dynamic> iceServers = {
  //   "iceServers": [
  //     {"urls": "stun:stun.l.google.com:19302"},
  //     {"urls": "stun:$serverHost:3478"},
  //     {
  //       "urls": "turn:$serverHost:3478",
  //       "username": "test",
  //       "credential": "test123",
  //     },
  //   ],
  // };


  
}