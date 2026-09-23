import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearby_connections/nearby_connections.dart';
import '../models/chat_message.dart';
import '../repositories/chat_repository.dart';
import 'chat_active_tracker.dart';
import 'notification_service.dart';
import 'user_cache_service.dart';

class MeshNetworkState {
  final bool isMeshActive;
  final int connectedPeersCount;
  final String? activeTourId;
  final String? statusMessage;

  const MeshNetworkState({
    this.isMeshActive = false,
    this.connectedPeersCount = 0,
    this.activeTourId,
    this.statusMessage,
  });

  MeshNetworkState copyWith({
    bool? isMeshActive,
    int? connectedPeersCount,
    String? activeTourId,
    String? statusMessage,
  }) {
    return MeshNetworkState(
      isMeshActive: isMeshActive ?? this.isMeshActive,
      connectedPeersCount: connectedPeersCount ?? this.connectedPeersCount,
      activeTourId: activeTourId ?? this.activeTourId,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

final meshNetworkServiceProvider =
    NotifierProvider<MeshNetworkService, MeshNetworkState>(MeshNetworkService.new);

class MeshNetworkService extends Notifier<MeshNetworkState> {
  ChatRepository get _chatRepo => ref.read(chatRepositoryProvider);
  final Nearby _nearby = Nearby();
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  final Set<String> _connectedEndpoints = <String>{};
  final Set<String> _connectingEndpoints = <String>{};

  String? _currentTourId;
  String? _currentUserId;

  @override
  MeshNetworkState build() {
    ref.onDispose(() {
      stopMesh();
    });
    return const MeshNetworkState();
  }

  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  /// Start P2P Mesh Network with Strategy.P2P_CLUSTER for active tour
  Future<bool> startMesh({
    required String tourId,
    required String userId,
    required String displayName,
  }) async {
    if (state.isMeshActive && _currentTourId == tourId) {
      return true;
    }

    // ALWAYS perform pre-cleanup to prevent STATUS_ALREADY_ADVERTISING / DISCOVERING
    // which previously locked Google Play Services radio and forced manual app restarts.
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (_) {}
    _connectedEndpoints.clear();
    _connectingEndpoints.clear();

    await Future.delayed(const Duration(milliseconds: 250));

    _currentTourId = tourId;
    _currentUserId = userId;

    state = state.copyWith(
      isMeshActive: true,
      activeTourId: tourId,
      statusMessage: 'Starting P2P Mesh Cluster...',
      connectedPeersCount: 0,
    );

    final cleanName = displayName.replaceAll(':', '_');
    final endpointIdentifier = 'TS:$tourId:$userId:$cleanName';
    final serviceId = 'com.toursplit.chat';

    try {
      // 1. Start Advertising
      final adSuccess = await _nearby.startAdvertising(
        endpointIdentifier,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );

      // 2. Start Discovery
      final discSuccess = await _nearby.startDiscovery(
        endpointIdentifier,
        _strategy,
        onEndpointFound: (endpointId, endpointName, sid) =>
            _onEndpointFound(endpointId, endpointName, endpointIdentifier),
        onEndpointLost: _onEndpointLost,
        serviceId: serviceId,
      );

      debugPrint('[MESH] Advertising: $adSuccess, Discovery: $discSuccess');

      state = state.copyWith(
        statusMessage: (adSuccess && discSuccess)
            ? 'Mesh active. Searching for tour peers...'
            : 'Mesh initialized with partial radio state.',
      );
      return adSuccess || discSuccess;
    } catch (e) {
      debugPrint('[MESH] startMesh error: $e');
      // On failure, immediately stop dangling state so future attempts don't require restarting app
      try {
        await _nearby.stopAdvertising();
        await _nearby.stopDiscovery();
        await _nearby.stopAllEndpoints();
      } catch (_) {}
      state = state.copyWith(
        isMeshActive: false,
        statusMessage: 'Mesh error: $e',
      );
      return false;
    }
  }

  /// Stop P2P Mesh Network
  Future<void> stopMesh() async {
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (e) {
      debugPrint('[MESH] stopMesh error: $e');
    }

    _connectedEndpoints.clear();
    _connectingEndpoints.clear();
    _currentTourId = null;

    state = const MeshNetworkState(
      isMeshActive: false,
      connectedPeersCount: 0,
      activeTourId: null,
      statusMessage: 'Mesh stopped',
    );
  }

  /// Check incoming endpoint: strictly pair only with members of the same tour
  void _onEndpointFound(
      String endpointId, String endpointName, String myEndpointName) async {
    if (_currentTourId == null) return;
    final prefix = 'TS:$_currentTourId:';

    // Must match tourId prefix
    if (!endpointName.startsWith(prefix)) {
      debugPrint('[MESH] Ignored endpoint from another tour: $endpointName');
      return;
    }

    if (_connectedEndpoints.contains(endpointId) ||
        _connectingEndpoints.contains(endpointId)) {
      return;
    }

    _connectingEndpoints.add(endpointId);
    debugPrint('[MESH] Found peer from same tour ($endpointName), requesting connection...');

    try {
      await _nearby.requestConnection(
        myEndpointName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _connectingEndpoints.remove(endpointId);
      debugPrint('[MESH] requestConnection error: $e');
    }
  }

  void _onEndpointLost(String? endpointId) {
    if (endpointId != null) {
      _connectingEndpoints.remove(endpointId);
    }
  }

  void _onConnectionInitiated(
      String endpointId, ConnectionInfo connectionInfo) async {
    if (_currentTourId == null) {
      await _nearby.rejectConnection(endpointId);
      return;
    }

    final prefix = 'TS:$_currentTourId:';
    // Validate that device belongs to the exact same tour
    if (connectionInfo.endpointName.startsWith(prefix)) {
      debugPrint('[MESH] Accepting connection from tour peer: ${connectionInfo.endpointName}');
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (epId, payload) => _onPayloadReceived(epId, payload),
        onPayloadTransferUpdate: (epId, update) {},
      );
    } else {
      debugPrint('[MESH] Rejecting connection from outsider: ${connectionInfo.endpointName}');
      await _nearby.rejectConnection(endpointId);
    }
  }

  void _onConnectionResult(String endpointId, Status status) {
    _connectingEndpoints.remove(endpointId);
    if (status == Status.CONNECTED) {
      _connectedEndpoints.add(endpointId);
      debugPrint('[MESH] Peer connected: $endpointId. Total peers: ${_connectedEndpoints.length}');
      state = state.copyWith(
        connectedPeersCount: _connectedEndpoints.length,
        statusMessage: '${_connectedEndpoints.length} peer(s) connected in mesh',
      );
    } else {
      _connectedEndpoints.remove(endpointId);
      state = state.copyWith(
        connectedPeersCount: _connectedEndpoints.length,
      );
    }
  }

  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    _connectingEndpoints.remove(endpointId);
    debugPrint('[MESH] Peer disconnected: $endpointId. Remaining: ${_connectedEndpoints.length}');
    state = state.copyWith(
      connectedPeersCount: _connectedEndpoints.length,
      statusMessage: _connectedEndpoints.isEmpty
          ? 'Searching for tour peers...'
          : '${_connectedEndpoints.length} peer(s) connected in mesh',
    );
  }

  /// Phase 5.3 & 5.4: Payload Handling & Gossip Protocol
  void _onPayloadReceived(String senderEndpointId, Payload payload) async {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    try {
      final jsonString = utf8.decode(payload.bytes!);
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      final msg = ChatMessage.fromMap(map, fallbackTourId: _currentTourId);

      if (msg.id.isEmpty || msg.tourId.isEmpty) return;

      final alreadyExists = _chatRepo.hasMessage(msg.tourId, msg.id);

      // Save locally to Hive
      await _chatRepo.saveMessage(msg);

      // Phase 5.4: Gossip Protocol
      // If the received message is new, immediately iterate through all other
      // connected endpoint IDs and rebroadcast the byte payload.
      if (!alreadyExists) {
        if (msg.authorId != _currentUserId &&
            !msg.isDeleted &&
            ChatActiveTracker.activeTourChatId != msg.tourId) {
          final authorName =
              UserCacheService.getUser(msg.authorId)?.displayName ??
                  'Tour Member';
          NotificationService.showChatMessageNotification(
            tourId: msg.tourId,
            tourName: 'Tour Offline Mesh',
            senderName: authorName,
            messageText: msg.text ?? '',
            messageId: msg.id,
          );
        }

        debugPrint('[GOSSIP] Rebroadcasting new message ${msg.id} to ${_connectedEndpoints.length - 1} other peers');
        for (final peerId in _connectedEndpoints) {
          if (peerId != senderEndpointId) {
            try {
              await _nearby.sendBytesPayload(peerId, payload.bytes!);
            } catch (e) {
              debugPrint('[GOSSIP] Rebroadcast error to $peerId: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MESH] Payload decode error: $e');
    }
  }

  /// Broadcast a message originating from local user to all mesh peers
  Future<void> broadcastMessage(ChatMessage msg) async {
    if (_connectedEndpoints.isEmpty) return;

    try {
      final jsonString = jsonEncode(msg.toMap());
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      for (final peerId in _connectedEndpoints) {
        try {
          await _nearby.sendBytesPayload(peerId, bytes);
        } catch (e) {
          debugPrint('[MESH] Broadcast error to $peerId: $e');
        }
      }
    } catch (e) {
      debugPrint('[MESH] Serialization error: $e');
    }
  }
}
