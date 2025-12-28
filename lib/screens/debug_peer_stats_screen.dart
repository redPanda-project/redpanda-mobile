
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart'; 
import 'package:drift/drift.dart' hide Column; // collision

class DebugPeerStatsScreen extends ConsumerWidget {
  const DebugPeerStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    // Watch all peers from DB
    final allPeersStream = db.select(db.peers).watch();
    
    // Watch currently connected peers from RAM
    final activePeersAsync = ref.watch(activePeersProvider);
    final activePeers = activePeersAsync.value ?? [];
    final connectingPeersAsync = ref.watch(connectingPeersProvider);
    final connectingPeers = connectingPeersAsync.value ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Peer Network Status')),
      body: StreamBuilder<List<Peer>>(
        stream: allPeersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final peers = snapshot.data!;
          final peerStatsList = peers.map((p) => PeerStats(
             address: p.address,
             nodeId: p.nodeId,
             averageLatencyMs: p.averageLatencyMs,
             successCount: p.successCount,
             failureCount: p.failureCount,
             lastSeen: p.lastSeen,
          )).toList();

          // 1. Identify Top 3 Primary Candidates based on clean Score sort
          peerStatsList.sort((a, b) => b.score.compareTo(a.score)); 
          final top3Addresses = peerStatsList.take(3).map((p) => p.address).toSet();
          
          // 2. Re-sort for display: Connected -> Connecting -> Primary -> Score
          peerStatsList.sort((a, b) {
            final aConnected = activePeers.contains(a.address) ? 2 : (connectingPeers.contains(a.address) ? 1 : 0);
            final bConnected = activePeers.contains(b.address) ? 2 : (connectingPeers.contains(b.address) ? 1 : 0);
            if (aConnected != bConnected) return bConnected.compareTo(aConnected);

            final aPrimary = top3Addresses.contains(a.address) ? 1 : 0;
            final bPrimary = top3Addresses.contains(b.address) ? 1 : 0;
            if (aPrimary != bPrimary) return bPrimary.compareTo(aPrimary);

            return b.score.compareTo(a.score);
          });

          if (peerStatsList.isEmpty) {
             return const Center(child: Text('No peers known yet.'));
          }

          return ListView.builder(
            itemCount: peerStatsList.length,
            itemBuilder: (context, index) {
              final p = peerStatsList[index];
              final isConnected = activePeers.contains(p.address);
              final isConnecting = connectingPeers.contains(p.address);
              final isPrimary = top3Addresses.contains(p.address);
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isConnected 
                        ? (isPrimary ? Colors.amber[100] : Colors.blue[100])
                        : (isConnecting ? Colors.orange[100] : Colors.grey[200]),
                    child: Icon(
                        isConnecting ? Icons.hourglass_empty : (isPrimary ? Icons.star : Icons.public),
                        color: isConnected 
                            ? (isPrimary ? Colors.orange : Colors.blue) 
                            : (isConnecting ? Colors.orange : Colors.grey),
                        size: 20,
                    ),
                  ),
                  title: Text(
                      p.nodeId != null 
                         ? NodeId.fromHex(p.nodeId!).toBase58().substring(0, 10) 
                         : 'Unknown Id',
                      style: const TextStyle(fontWeight: FontWeight.bold)
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(p.address, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Row(
                           children: [
                              _StatBadge(
                                 icon: Icons.timer, 
                                 text: '${p.averageLatencyMs}ms', 
                                 color: p.averageLatencyMs < 200 ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              _StatBadge(
                                 icon: Icons.check_circle, 
                                 text: '${p.successCount}', 
                                 color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              _StatBadge(
                                 icon: Icons.error, 
                                 text: '${p.failureCount}', 
                                 color: Colors.red,
                              ),
                           ],
                        ),
                    ],
                  ),
                  trailing: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     crossAxisAlignment: CrossAxisAlignment.end,
                     mainAxisSize: MainAxisSize.min, // Fix Check: overflow
                     children: [
                        Text('Score', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        Text(
                           p.score.toStringAsFixed(2), 
                           style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                        ),
                     ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _StatBadge({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
      return Row(
         children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            Text(text, style: TextStyle(color: color, fontSize: 12)),
         ],
      );
  }
}
