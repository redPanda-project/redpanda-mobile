import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:redpanda/screens/onboarding/onboarding_screen.dart';
import 'package:redpanda/screens/home/home_screen.dart';
import 'package:redpanda/screens/chat/chat_screen.dart';
import 'package:redpanda/screens/debug_peer_stats_screen.dart';
import 'package:redpanda/screens/channels/channel_status_screen.dart';
import 'package:redpanda/screens/channels/connection_doctor_screen.dart';
import 'package:redpanda/screens/channels/create_channel_screen.dart';
import 'package:redpanda/screens/channels/join_channel_screen.dart';
import 'package:redpanda/screens/group/create_group_screen.dart';
import 'package:redpanda/screens/group/group_info_screen.dart';
import 'package:redpanda/shared/providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/chat/:uuid',
        builder: (context, state) {
          final uuid = state.pathParameters['uuid']!;
          return ChatScreen(peerUuid: uuid);
        },
      ),
      GoRoute(
        path: '/debug-stats',
        builder: (context, state) => const DebugPeerStatsScreen(),
      ),
      GoRoute(
        path: '/channels/create',
        builder: (context, state) => const CreateChannelScreen(),
      ),
      GoRoute(
        path: '/channels/join',
        builder: (context, state) => const JoinChannelScreen(),
      ),
      GoRoute(
        path: '/channels/:uuid/status',
        builder: (context, state) {
          final uuid = state.pathParameters['uuid']!;
          return ChannelStatusScreen(channelUuid: uuid);
        },
      ),
      GoRoute(
        path: '/channels/:uuid/doctor',
        builder: (context, state) {
          final uuid = state.pathParameters['uuid']!;
          return ConnectionDoctorScreen(channelUuid: uuid);
        },
      ),
      GoRoute(
        path: '/groups/create',
        builder: (context, state) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '/groups/:groupId/info',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return GroupInfoScreen(groupId: groupId);
        },
      ),
    ],
    redirect: (context, state) async {
      // Check if user exists
      final db = ref.read(dbProvider);
      final users = await db.select(db.users).get();
      final userCount = users.length;

      final loggingIn = state.uri.toString() == '/onboarding';
      if (userCount == 0) {
        return '/onboarding';
      }

      if (loggingIn) {
        return '/';
      }
      return null;
    },
  );
});
