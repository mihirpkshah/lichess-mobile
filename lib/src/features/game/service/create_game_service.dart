import 'package:logging/logging.dart';
import 'package:dartchess/dartchess.dart' hide Tuple2;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import 'package:lichess_mobile/src/common/errors.dart';
import 'package:lichess_mobile/src/features/user/model/user.dart';
import '../data/play_preferences.dart';
import '../data/challenge_repository.dart';
import '../data/game_repository.dart';
import '../data/api_event.dart';
import '../model/computer_opponent.dart';
import '../model/game.dart';

class CreateGameService {
  const CreateGameService(this._log, {required this.ref});

  final Ref ref;
  final Logger _log;

  TaskEither<IOError, Game> aiGameTask(User account, {Side? side}) {
    final challengeRepo = ref.read(challengeRepositoryProvider);
    final opponent = ref.read(computerOpponentPrefProvider);
    final timeControl = ref.read(timeControlPrefProvider).value;
    final level = ref.read(stockfishLevelProvider);

    final createChallengeTask = opponent == ComputerOpponent.stockfish
        ? challengeRepo.challengeAITask(AiChallengeRequest(
            time: Duration(minutes: timeControl.time),
            increment: Duration(seconds: timeControl.increment),
            side: side,
            level: level))
        : challengeRepo.createChallengeTask(
            opponent.name,
            ChallengeRequest(
                time: Duration(minutes: timeControl.time),
                side: side,
                increment: Duration(seconds: timeControl.increment)));

    return createChallengeTask.andThen(() => _waitForGameStart(account));
  }

  TaskEither<IOError, Game> _waitForGameStart(User account) {
    return TaskEither<IOError, Game>.tryCatch(
      () async {
        final gameRepo = ref.read(gameRepositoryProvider);
        final stream = gameRepo.events().timeout(const Duration(seconds: 15),
            onTimeout: (sink) => sink.close());

        await for (ApiEvent event in stream) {
          if (event.type == GameEventLifecycle.start && event.boardCompat) {
            final player = Player(
              id: account.id,
              name: account.username,
              rating: account.perfs[event.perf]!.rating,
            );
            final opponent = Player(
                id: event.opponent.id,
                name: event.opponent.username,
                rating: event.opponent.rating);
            return Game(
              id: event.gameId,
              initialFen: event.fen,
              speed: event.speed,
              orientation: event.side,
              rated: event.rated,
              white: event.side == Side.white ? player : opponent,
              black: event.side == Side.white ? opponent : player,
            );
          }
        }
        throw Exception('Could not create game.');
      },
      (error, trace) {
        _log.severe('Request error', error, trace);
        return GenericError(trace);
      },
    );
  }
}

final createGameServiceProvider = Provider<CreateGameService>((ref) {
  return CreateGameService(Logger('CreateGameService'), ref: ref);
});