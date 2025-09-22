import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SaveLocationService {
  static const String _saveLocationsKey = 'zipline_save_locations';
  static const String _defaultLocationKey = 'zipline_default_save_location';
  
  SharedPreferences? _prefs;
  
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Save a preferred location for a specific peer
  Future<void> savePeerLocation(String peerSignature, String location) async {
    if (_prefs == null) await initialize();
    
    final existingData = _prefs!.getString(_saveLocationsKey);
    Map<String, String> locations = {};
    
    if (existingData != null) {
      try {
        locations = Map<String, String>.from(json.decode(existingData));
      } catch (e) {
        // If decoding fails, start with empty map
      }
    }
    
    locations[peerSignature] = location;
    await _prefs!.setString(_saveLocationsKey, json.encode(locations));
  }

  /// Get the preferred location for a specific peer
  Future<String?> getPeerLocation(String peerSignature) async {
    if (_prefs == null) await initialize();
    
    final existingData = _prefs!.getString(_saveLocationsKey);
    if (existingData == null) return null;
    
    try {
      final locations = Map<String, String>.from(json.decode(existingData));
      return locations[peerSignature];
    } catch (e) {
      return null;
    }
  }

  /// Set the default save location
  Future<void> setDefaultLocation(String location) async {
    if (_prefs == null) await initialize();
    await _prefs!.setString(_defaultLocationKey, location);
  }

  /// Get the default save location
  Future<String?> getDefaultLocation() async {
    if (_prefs == null) await initialize();
    return _prefs!.getString(_defaultLocationKey);
  }

  /// Get all saved peer locations
  Future<Map<String, String>> getAllPeerLocations() async {
    if (_prefs == null) await initialize();
    
    final existingData = _prefs!.getString(_saveLocationsKey);
    if (existingData == null) return {};
    
    try {
      return Map<String, String>.from(json.decode(existingData));
    } catch (e) {
      return {};
    }
  }

  /// Remove a peer's saved location
  Future<void> removePeerLocation(String peerSignature) async {
    if (_prefs == null) await initialize();
    
    final existingData = _prefs!.getString(_saveLocationsKey);
    if (existingData == null) return;
    
    try {
      final locations = Map<String, String>.from(json.decode(existingData));
      locations.remove(peerSignature);
      await _prefs!.setString(_saveLocationsKey, json.encode(locations));
    } catch (e) {
      // Ignore error
    }
  }

  /// Clear all saved locations
  Future<void> clearAllLocations() async {
    if (_prefs == null) await initialize();
    await _prefs!.remove(_saveLocationsKey);
  }

  /// Get the most appropriate save location for a transfer
  /// Returns peer-specific location if available, otherwise default location
  Future<String?> getBestLocationForPeer(String peerSignature) async {
    String? peerLocation = await getPeerLocation(peerSignature);
    if (peerLocation != null) return peerLocation;
    
    return await getDefaultLocation();
  }
}