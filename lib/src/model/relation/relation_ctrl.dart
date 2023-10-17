import 'dart:async';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/auth/auth_socket.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lichess_mobile/src/model/common/socket.dart';

part 'relation_ctrl.freezed.dart';
part 'relation_ctrl.g.dart';

@riverpod
class RelationCtrl extends _$RelationCtrl {
  StreamSubscription<SocketEvent>? _socketSubscription;

  @override
  Future<RelationCtrlState> build() {
    final socket = ref.watch(authSocketProvider);
    final (stream, _) = socket.connect(Uri(path: '/lobby/socket/v5'));

    final state = stream.firstWhere((e) => e.topic == 'following_onlines').then(
      (event) {
        _socketSubscription = stream.listen(_handleSocketTopic);
        return RelationCtrlState(
          followingOnlines:
              _parseFriendsListToLightUserIList(event.data as List<dynamic>),
        );
      },
    );

    ref.onDispose(() {
      _socketSubscription?.cancel();
    });

    return state;
  }

  void getFollowingOnlines() {
    _socket.send('following_onlines', null);
  }

  void _handleSocketTopic(SocketEvent event) {
    if (!state.hasValue) return;

    switch (event.topic) {
      case 'following_onlines':
        state = AsyncValue.data(
          RelationCtrlState(
            followingOnlines:
                _parseFriendsListToLightUserIList(event.data as List<dynamic>),
          ),
        );

      case 'following_enters':
        final data = _parseFriendToLightUser(event.data.toString());
        state = AsyncValue.data(
          (state as AsyncData<RelationCtrlState>).requireValue.copyWith(
                followingOnlines: [
                  ...state.requireValue.followingOnlines,
                  data,
                ].toIList(),
              ),
        );

      case 'following_leaves':
        final data = _parseFriendToLightUser(event.data.toString());
        state = AsyncValue.data(
          (state as AsyncData<RelationCtrlState>).requireValue.copyWith(
                followingOnlines: state.requireValue.followingOnlines
                    .where((e) => e.id != data.id)
                    .toIList(),
              ),
        );
    }
  }

  AuthSocket get _socket => ref.read(authSocketProvider);

  LightUser _parseFriendToLightUser(String friend) {
    final splitted = friend.split(' ');
    final name = splitted.length > 1 ? splitted[1] : splitted[0];
    final title = splitted.length > 1 ? splitted[0] : null;
    return LightUser(
      id: UserId.fromUserName(name),
      name: name,
      title: title,
    );
  }

  IList<LightUser> _parseFriendsListToLightUserIList(List<dynamic> friends) {
    return friends.map((v) => _parseFriendToLightUser(v.toString())).toIList();
  }
}

@freezed
class RelationCtrlState with _$RelationCtrlState {
  const RelationCtrlState._();

  const factory RelationCtrlState({
    required IList<LightUser> followingOnlines,
  }) = _RelationCtrlState;
}
