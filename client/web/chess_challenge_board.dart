/* Copyright (c) 2014, Anders Forsell (aforsell1971@gmail.com)
 */

import 'dart:html';
import 'dart:async';
import 'dart:math';
import 'dart:convert' show JSON;
import 'package:polymer/polymer.dart';
import 'package:chessboard/chess_board.dart';
import 'package:client/shared.dart';

/**
 * The Chess Challenge Board component
 */
@CustomTag('chess-challenge-board')
class ChessChallengeBoard extends PolymerElement {
  @published User user;

  @observable List<User> leaderBoard = [];

  @observable List<User> startChallengeUsers = [];

  @observable String winnerTime;

  @observable String challengeTime = '';

  @observable String startChallengeStatus = '';

  @observable String startChallengeBtnLabel = 'Start';

  Stopwatch _stopWatch = new Stopwatch();

  Timer _challengeTimer;

  Timer _updateStatusTimer;

  ChessBoard _chessBoard;

  WebSocket _webSocket;

  ChessChallengeBoard.created() : super.created();

  @override
  void domReady() {
    var navicon = $['navicon'];
    var drawerPanel = $['drawerPanel'];
    _chessBoard = $['chess_board'];

    resize();

    window.onResize.listen((e) {
      resize();
    });

    navicon.onClick.listen((e) => drawerPanel.togglePanel());
  }

  void userChanged(User oldValue, User newValue) {
    _connect();
  }

  void _connect() {
    Uri uri = Uri.parse(window.location.href);
    var port = uri.port != 8080 ? 80 : 9090;

    _webSocket = new WebSocket('ws://${uri.host}:${port}/ws');
    _webSocket.onMessage.listen(_receive);
    _webSocket.onOpen.listen((event) {
      print('Connected to server');
      _webSocket.send(Messages.LOGIN + JSON.encode(user));

      showStartChallengeDialog();
    });
    _webSocket.onError.listen((event) {
      async((_) => $['connection_error'].toggle());
    });
  }

  void connectionRetryClicked(Event event, var detail, Node target) {
    async((_) => _connect());
  }

  void showStartChallengeDialog() {
    $['start_challenge'].toggle();
    _updateStatusTimer = new Timer.periodic(
        new Duration(milliseconds: 1000),
        updateStartChallengeStatus);
  }

  void updateStartChallengeStatus(Timer timer) {
    _webSocket.send(Messages.GETSTATUS);
  }

  void _receive(MessageEvent event) {
    String message = event.data;
    if (message.startsWith(Messages.PGN)) {
      var pgn = message.substring(Messages.PGN.length);
      print('PGN received: ' + pgn);
      ChessBoard chessBoard = $['chess_board']..position = pgn;
      async((_) {
        chessBoard.undo();
        chessBoard.reversed = chessBoard.turn == ChessBoard.BLACK;
        async((_) => chessBoard.refresh());
      });
    } else if (message == Messages.STARTCHALLENGE) {
      $['challenge_pending'].dismiss();
      $['stop_challenge'].style.display = 'block';
      _stopWatch
          ..reset()
          ..start();
      _challengeTimer =
          new Timer.periodic(new Duration(seconds: 1), updateChallengeTime);
    } else if (message.startsWith(Messages.LEADERBOARD)) {
      List leaders =
          JSON.decode(message.substring(Messages.LEADERBOARD.length));
      leaderBoard = leaders.map((u) => new User.fromMap(u)).toList();
    } else if (message.startsWith(Messages.GAMEOVER)) {
      int time = int.parse(message.substring(Messages.GAMEOVER.length));
      showResultsDialog(time);
    } else if (message.startsWith(Messages.PENDINGCHALLENGE)) {
      String msg = message.substring(Messages.PENDINGCHALLENGE.length);
      int index = msg.indexOf(":");
      var time = msg.substring(0, index);

      _updateChallengeUsers(msg.substring(index + 1));

      startChallengeStatus = 'A new challenge starts in ${time} seconds:';
      startChallengeBtnLabel = 'Join';
    } else if (message.startsWith(Messages.AVAILABLEUSERS)) {
      _updateChallengeUsers(message.substring(Messages.AVAILABLEUSERS.length));

      if (startChallengeUsers.length > 0) {
        startChallengeStatus = 'Challenge the following users:';
      } else {
        startChallengeStatus = 'No users online, challenge yourself!';
      }
      startChallengeBtnLabel = 'Start';
    }
  }

  // The previous encoded 'users' from the server, used for optimizing
  String _previousUsers;

  void _updateChallengeUsers(String jsonUsers) {
    if (jsonUsers != _previousUsers) {
      List challengeUsers = JSON.decode(jsonUsers);
      startChallengeUsers =
          challengeUsers.map((u) => new User.fromMap(u)).toList();
      _previousUsers = jsonUsers;
    }
  }

  void showResultsDialog(int time) {
    _challengeTimer.cancel();
    _stopWatch.stop();
    challengeTime = '';
    winnerTime = '${(time/1000).toStringAsFixed(1)} s';
    challengeTime = '';
    async((_) {
      $['stop_challenge'].style.display = 'none';
      $['result'].toggle();
    });
  }

  void resize() {
    var mainHeaderPanel = $['main_header_panel'];
    var mainToolbar = $['main_toolbar'];

    ChessBoard chessBoard = $['chess_board'];
    var paddingX2 = 20 * 2;
    int height =
        mainHeaderPanel.clientHeight -
        mainToolbar.clientHeight -
        paddingX2;
    int width = mainHeaderPanel.clientWidth - paddingX2;
    int newWidth = min(height, width);
    if (newWidth > 0) {
      chessBoard.style
          ..width = '${newWidth}px'
          ..height = chessBoard.style.width;
      chessBoard.resize();
    }
  }

  void onMove(CustomEvent event, detail, target) {
    ChessBoard chessBoard = event.target;
    if (chessBoard.gameStatus != 'checkmate') {
      $['try_again'].show();
      chessBoard.undo();
      chessBoard.refresh();
    } else {
      _webSocket.send(Messages.CHECKMATE);
    }
  }

  void stopChallengeClicked(Event event, var detail, Node target) {
    if (_stopWatch.isRunning) {
      $['confirm_stop_challenge'].toggle();
    }
  }

  void startChallengeClicked(Event event, var detail, Node target) {
    if (_updateStatusTimer != null) {
      _updateStatusTimer.cancel();
      _updateStatusTimer = null;
      async((_) {
        $['start_challenge'].opened = false;
      });
    }
    async((_) => startChallenge());
  }

  void startChallenge() {
    _webSocket.send(Messages.CHALLENGE);
    async((_) => $['challenge_pending'].show());
  }

  void stopChallenge() {
    _webSocket.send(Messages.STOPCHALLENGE);
    showStartChallenge();
  }

  void resultOkClicked(Event event, var detail, Node target) {
    showStartChallenge();
  }

  void showStartChallenge() {
    if (_challengeTimer != null) {
      _challengeTimer.cancel();
    }
    _stopWatch.stop();
    leaderBoard = [];
    challengeTime = '';
    async((_) {
      $['stop_challenge'].style.display = 'none';
      showStartChallengeDialog();
    });
  }

  void confirmStopChallengeClicked(Event event, var detail, Node target) {
    stopChallenge();
  }

  void updateChallengeTime(Timer timer) {
    challengeTime =
        '${(_stopWatch.elapsedMilliseconds/1000).toStringAsFixed(0)} s';
  }

  /// Returns the player info for the [side] ('Black' or 'White')
  String getPlayerInfo(String side) {
    if (_chessBoard == null) {
      return '';
    }
    var name = _chessBoard.header[side];
    if (name == null) {
      return '';
    }
    var rating = _chessBoard.header[side + 'Elo'];
    if (rating != null) {
      return '${name} (${rating})';
    }
    return name;
  }
}