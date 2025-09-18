import 'dart:io';
import 'dart:typed_data';
import '../services/profile_image_service.dart';

class AvatarWebServer {
  static AvatarWebServer? _instance;
  static AvatarWebServer get instance => _instance ??= AvatarWebServer._();
  
  AvatarWebServer._();

  HttpServer? _server;
  Uint8List? _cachedAvatar;
  int _avatarPort = 0;

  /// Start the avatar web server on the specified port
  Future<bool> start(int tcpPort) async {
    try {
      // Use TCP port + 1 for avatar server
      _avatarPort = tcpPort + 1;
      
      // Stop existing server if running
      await stop();
      
      // Load and cache the avatar image
      _cachedAvatar = await ProfileImageService.instance.getProfileImage();
      
      // Start HTTP server
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _avatarPort);
      _server!.listen(_handleRequest);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stop the avatar web server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
    }
  }

  /// Get the avatar server port
  int get port => _avatarPort;

  /// Handle HTTP requests for avatar
  void _handleRequest(HttpRequest request) {
    final response = request.response;
    
    try {
      // Only handle GET requests to /avatar
      if (request.method == 'GET' && 
          (request.uri.path == '/' || 
           request.uri.path == '/avatar' || 
           request.uri.path.startsWith('/avatar'))) {
        
        // Set HTTP headers
        response.headers.set('Content-Type', 'image/png');
        response.headers.set('Content-Length', _cachedAvatar?.length ?? 0);
        response.headers.set('Cache-Control', 'no-cache');
        
        // Write avatar data
        if (_cachedAvatar != null) {
          response.add(_cachedAvatar!);
        }
      } else {
        // Return 404 for other requests
        response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      response.close();
    }
  }

  /// Refresh the cached avatar
  Future<void> refreshAvatar() async {
    _cachedAvatar = await ProfileImageService.instance.getProfileImage();
  }

  /// Get the avatar URL for this peer
  String getAvatarUrl(String localAddress, int tcpPort) {
    return 'http://$localAddress:${tcpPort + 1}/avatar';
  }
}
