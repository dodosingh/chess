import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:stockfish/stockfish.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class StockfishAnalysis {
  final String? evaluation;
  final String? pvLine;
  final bool isLoading;
  final String? loadingMessage;

  const StockfishAnalysis({
    this.evaluation,
    this.pvLine,
    this.isLoading = false,
    this.loadingMessage,
  });

  StockfishAnalysis copyWith({
    String? evaluation,
    String? pvLine,
    bool? isLoading,
    String? loadingMessage,
  }) {
    return StockfishAnalysis(
      evaluation: evaluation ?? this.evaluation,
      pvLine: pvLine ?? this.pvLine,
      isLoading: isLoading ?? this.isLoading,
      loadingMessage: loadingMessage ?? this.loadingMessage,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Saumya Chess",
      theme: ThemeData(
        brightness: material.Brightness.dark,
        scaffoldBackgroundColor: material.Color(0xFF232323),
        colorScheme: material.ColorScheme.dark().copyWith(
          primary: material.Color(0xFF388E3C),
          secondary: material.Color(0xFF1976D2),
        ),
        appBarTheme: material.AppBarTheme(
          backgroundColor: material.Color(0xFF232323),
          foregroundColor: material.Colors.white,
        ),
        cardColor: material.Color(0xFF2C2C2C),
        buttonTheme: material.ButtonThemeData(
          buttonColor: material.Color(0xFF388E3C),
        ),
      ),
      home: const SplashScreen(),
      routes: {
        '/game': (context) => const ChessGameScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/game');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: material.Color(0xFF1a1a1a),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assest/image.png', fit: BoxFit.cover),
              ),
            ),
            SizedBox(height: 30),
            Text(
              "Saumya Chess",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Powered by Stockfish",
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
                fontWeight: FontWeight.w300,
              ),
            ),
            SizedBox(height: 40),
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChessGameScreen extends StatefulWidget {
  const ChessGameScreen({super.key});

  @override
  State<ChessGameScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessGameScreen> {
  late ChessBoardController controller;
  late chess_lib.Chess chess;
  late Stockfish stockfish;
  StreamSubscription<String>? stockfishSub;
  List<String> moveHistory = [];
  List<String> redoStack = [];
  String? bestMove;
  Timer? loadingTimer;
  int selectedLevel = 4;
  List<String> possibleMoves = [];
  String? selectedSquare;
  bool stockfishReady = false;
  bool playAsWhite = true;
  final ValueNotifier<StockfishAnalysis> analysisNotifier = ValueNotifier(
    const StockfishAnalysis(),
  );
  bool _pendingFirstMove = false;
  bool stockfishInitializing = true;

  @override
  void initState() {
    super.initState();
    controller = ChessBoardController();
    chess = chess_lib.Chess();
    stockfish = Stockfish();
    _loadSavedLevel();
    _loadPlayAsWhite();
    _initStockfish();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeTriggerStockfishFirstMove(force: true);
    });
  }

  @override
  void dispose() {
    stockfishSub?.cancel();
    stockfish.dispose();
    loadingTimer?.cancel();
    analysisNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadSavedLevel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLevel = prefs.getInt('chess_difficulty_level') ?? 4;
      setState(() {
        selectedLevel = savedLevel;
      });
    } catch (e) {
      setState(() {
        selectedLevel = 4;
      });
    }
  }

  Future<void> _saveLevelToPrefs(int level) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('chess_difficulty_level', level);
    } catch (e) {
      debugPrint('Error saving level preference: $e');
    }
  }

  Future<void> _loadPlayAsWhite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final asWhite = prefs.getBool('play_as_white');
      setState(() {
        playAsWhite = asWhite ?? true;
      });
    } catch (e) {
      setState(() {
        playAsWhite = true;
      });
    }
  }

  Future<void> _initStockfish() async {
    await Future.delayed(const Duration(seconds: 2));
    stockfishSub = stockfish.stdout.listen(_processStockfishOutput);
    stockfish.stdin = 'uci';
    Future.delayed(const Duration(milliseconds: 100), () {
      _maybeTriggerStockfishFirstMove(force: true);
    });
  }

  void _setStockfishSkill(int level) {
    if (!stockfishReady) return;
    final skillMap = [1, 4, 7, 10, 13, 16, 20];
    final skill = skillMap[(level - 1).clamp(0, 6)];
    stockfish.stdin = 'setoption name Skill Level value $skill';
  }

  void _processStockfishOutput(String line) {
    if (line.trim() == 'uciok') {
      setState(() {
        stockfishReady = true;
        stockfishInitializing = false;
      });
      _setStockfishSkill(selectedLevel);
      if (_pendingFirstMove) {
        _maybeTriggerStockfishFirstMove(force: true);
      }
      return;
    }
    if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      bestMove = parts.length > 1 ? parts[1] : null;

      analysisNotifier.value = analysisNotifier.value.copyWith(
        isLoading: false,
        loadingMessage: null,
      );
      loadingTimer?.cancel();

      if (bestMove != null &&
          ((playAsWhite && chess.turn == chess_lib.Color.BLACK) ||
              (!playAsWhite && chess.turn == chess_lib.Color.WHITE))) {
        final from = bestMove!.substring(0, 2);
        final to = bestMove!.substring(2, 4);
        final promotion = bestMove!.length > 4 ? bestMove![4] : null;
        final moveObj = {
          'from': from,
          'to': to,
          if (promotion != null) 'promotion': promotion,
        };
        chess.move(moveObj);
        controller.loadFen(chess.fen);
        moveHistory.add(chess.fen);
        redoStack.clear();
        setState(() {});
      }
    } else if (line.contains('score')) {
      final evalMatch = RegExp(r'score (cp|mate) (-?\d+)').firstMatch(line);
      String? evaluation;
      if (evalMatch != null) {
        if (evalMatch.group(1) == 'cp') {
          evaluation = ((int.parse(evalMatch.group(2)!) / 100.0)
              .toStringAsFixed(2));
        } else {
          evaluation = 'Mate in ${evalMatch.group(2)}';
        }
      }

      final pvMatch = RegExp(
        r'pv ((?:[a-h][1-8][a-h][1-8][qrbn]? ?)+)',
      ).firstMatch(line);
      String? pvLine;
      if (pvMatch != null) {
        final pvMoves = pvMatch.group(1)!.trim().split(' ');
        pvLine = _pvToSan(pvMoves);
      }

      if (evaluation != null || pvLine != null) {
        analysisNotifier.value = analysisNotifier.value.copyWith(
          evaluation: evaluation ?? analysisNotifier.value.evaluation,
          pvLine: pvLine ?? analysisNotifier.value.pvLine,
        );
      }
    }
  }

  String _pvToSan(List<String> pvMoves) {
    final tempChess = chess_lib.Chess();
    tempChess.load(chess.fen);
    List<String> sanMoves = [];
    for (var move in pvMoves) {
      if (move.length < 4) continue;
      final from = move.substring(0, 2);
      final to = move.substring(2, 4);
      final promotion = move.length > 4 ? move[4] : null;
      final moveObj = {
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      };
      if (!tempChess.move(moveObj)) break;
      sanMoves.add(tempChess.getHistory().last);
    }
    String result = '';
    for (int i = 0; i < sanMoves.length; i++) {
      if (i % 2 == 0) {
        result += '\n${1 + (i ~/ 2)}. ';
      }
      result += '${sanMoves[i]} ';
    }
    return result.trim();
  }

  Future<void> _getBestMove() async {
    if (!stockfishReady) return;
    final fen = controller.getFen();

    analysisNotifier.value = analysisNotifier.value.copyWith(
      isLoading: true,
      evaluation: null,
      pvLine: null,
      loadingMessage: null,
    );

    stockfish.stdin = 'position fen $fen';
    stockfish.stdin = 'go movetime 1000';
    loadingTimer?.cancel();
    loadingTimer = Timer(const Duration(seconds: 3), () {
      if (analysisNotifier.value.isLoading) {
        analysisNotifier.value = analysisNotifier.value.copyWith(
          loadingMessage: 'Stockfish is thinking... (taking longer than usual)',
        );
      }
    });
  }

  void _onMove() {
    setState(() {
      chess.load(controller.getFen());
      moveHistory.add(controller.getFen());
      redoStack.clear();
      possibleMoves.clear();
      selectedSquare = null;
    });

    if ((playAsWhite && chess.turn == chess_lib.Color.BLACK) ||
        (!playAsWhite && chess.turn == chess_lib.Color.WHITE)) {
      if (stockfishReady) {
        _getBestMove();
      }
    }
  }

  void _onTapSquare(String square) {
    setState(() {
      if (selectedSquare != null && possibleMoves.contains(square)) {
        final moveObj = {'from': selectedSquare, 'to': square};
        if (chess.move(moveObj)) {
          controller.loadFen(chess.fen);
          moveHistory.add(chess.fen);
          redoStack.clear();
          selectedSquare = null;
          possibleMoves.clear();
          _onMove();
        } else {
          selectedSquare = null;
          possibleMoves.clear();
        }
      } else if (selectedSquare == square) {
        selectedSquare = null;
        possibleMoves.clear();
      } else {
        selectedSquare = square;
        final moves = chess.moves({'square': square, 'verbose': true});
        possibleMoves = moves.map<String>((m) => m['to'] as String).toList();
      }
    });
  }

  void _undoMove() {
    if (moveHistory.isNotEmpty) {
      setState(() {
        redoStack.add(moveHistory.removeLast());
        if (moveHistory.isNotEmpty) {
          controller.loadFen(moveHistory.last);
          chess.load(moveHistory.last);
        } else {
          controller.resetBoard();
          chess.reset();
        }
        possibleMoves.clear();
        selectedSquare = null;
      });

      analysisNotifier.value = const StockfishAnalysis();
      loadingTimer?.cancel();

      if ((playAsWhite && chess.turn == chess_lib.Color.BLACK) ||
          (!playAsWhite && chess.turn == chess_lib.Color.WHITE)) {
        if (stockfishReady) {
          _getBestMove();
        }
      }
    }
  }

  void _redoMove() {
    if (redoStack.isNotEmpty) {
      setState(() {
        final fen = redoStack.removeLast();
        controller.loadFen(fen);
        chess.load(fen);
        moveHistory.add(fen);
        possibleMoves.clear();
        selectedSquare = null;
      });

      analysisNotifier.value = const StockfishAnalysis();
      loadingTimer?.cancel();

      if ((playAsWhite && chess.turn == chess_lib.Color.BLACK) ||
          (!playAsWhite && chess.turn == chess_lib.Color.WHITE)) {
        if (stockfishReady) {
          _getBestMove();
        }
      }
    }
  }

  void _resetGame() {
    setState(() {
      controller.resetBoard();
      chess.reset();
      moveHistory.clear();
      redoStack.clear();
      possibleMoves.clear();
      selectedSquare = null;
    });
    analysisNotifier.value = const StockfishAnalysis();
    loadingTimer?.cancel();
    _maybeTriggerStockfishFirstMove(force: true);
  }

  void _maybeTriggerStockfishFirstMove({bool force = false}) {
    if (!playAsWhite && chess.turn == chess_lib.Color.WHITE) {
      if (stockfishReady) {
        _getBestMove();
        _pendingFirstMove = false;
      } else if (force) {
        _pendingFirstMove = true;
      }
    }
  }

  @override
  void didUpdateWidget(covariant ChessGameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeTriggerStockfishFirstMove(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assest/image.png', fit: BoxFit.cover),
              ),
            ),
            SizedBox(width: 12),
            Text("Saumya Chess"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.pushNamed(
                context,
                '/settings',
                arguments: {'level': selectedLevel, 'playAsWhite': playAsWhite},
              );
              if (result is Map) {
                final level = result['level'] as int?;
                final asWhite = result['playAsWhite'] as bool?;

                if (level != null && level != selectedLevel) {
                  setState(() {
                    selectedLevel = level;
                    _setStockfishSkill(selectedLevel);
                  });
                  await _saveLevelToPrefs(selectedLevel);
                }

                if (asWhite != null && asWhite != playAsWhite) {
                  setState(() {
                    playAsWhite = asWhite;
                  });
                  _resetGame();
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<StockfishAnalysis>(
            valueListenable: analysisNotifier,
            builder: (context, analysis, child) {
              return SizedBox(
                width: double.infinity,
                height: 3,
                child: (stockfishInitializing || analysis.isLoading)
                    ? LinearProgressIndicator(backgroundColor: Colors.grey[800])
                    : Container(color: Colors.grey[700]),
              );
            },
          ),

          ValueListenableBuilder<StockfishAnalysis>(
            valueListenable: analysisNotifier,
            builder: (context, analysis, child) {
              if (analysis.evaluation == null) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    Text(
                      analysis.evaluation!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey[600]!,
                            width: 1,
                          ),
                        ),
                        child: _buildEvaluationBar(analysis.evaluation!),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          Container(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      ChessBoard(
                        controller: controller,
                        boardColor: BoardColor.brown,
                        boardOrientation: playAsWhite
                            ? PlayerColor.white
                            : PlayerColor.black,
                        enableUserMoves: true,
                        onMove: _onMove,
                      ),
                      IgnorePointer(
                        ignoring: false,
                        child: Stack(
                          children: [
                            for (int file = 0; file < 8; file++)
                              for (int rank = 0; rank < 8; rank++)
                                Positioned(
                                  left: (playAsWhite ? file : 7 - file) * 45.0,
                                  top: (playAsWhite ? rank : 7 - rank) * 45.0,
                                  width: 45.0,
                                  height: 45.0,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: () {
                                      final square =
                                          String.fromCharCode(
                                            'a'.codeUnitAt(0) +
                                                (playAsWhite ? file : 7 - file),
                                          ) +
                                          (8 - (playAsWhite ? rank : 7 - rank))
                                              .toString();
                                      _onTapSquare(square);
                                    },
                                  ),
                                ),
                          ],
                        ),
                      ),
                      if (selectedSquare != null && possibleMoves.isNotEmpty)
                        IgnorePointer(
                          child: Stack(
                            children: [
                              for (final move in possibleMoves)
                                Positioned(
                                  left:
                                      ((playAsWhite
                                              ? (move.codeUnitAt(0) -
                                                    'a'.codeUnitAt(0))
                                              : (7 -
                                                    (move.codeUnitAt(0) -
                                                        'a'.codeUnitAt(0)))) *
                                          45.0 +
                                      22.5 -
                                      8),
                                  top:
                                      ((playAsWhite
                                              ? (8 - int.parse(move[1]))
                                              : (int.parse(move[1]) - 1)) *
                                          45.0 +
                                      22.5 -
                                      8),
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Expanded(
            child: StockfishAnalysisCard(analysisNotifier: analysisNotifier),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(
                top: BorderSide(color: Colors.grey[700]!, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.undo, size: 20),
                    label: const Text('Undo'),
                    onPressed: moveHistory.isNotEmpty ? _undoMove : null,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.redo, size: 20),
                    label: const Text('Redo'),
                    onPressed: redoStack.isNotEmpty ? _redoMove : null,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Reset'),
                    onPressed: _resetGame,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvaluationBar(String evaluation) {
    double evalValue = 0.0;
    bool isMate = evaluation.contains('Mate');

    if (isMate) {
      int mateIn = int.parse(evaluation.split(' ')[2]);
      evalValue = mateIn > 0 ? 41.0 : -41.0;
    } else {
      evalValue = double.parse(evaluation);
    }

    double clampedEval = evalValue.clamp(-41.0, 41.0);
    double percentage = (clampedEval + 41.0) / 82.0;

    return Row(
      children: [
        Expanded(
          flex: (percentage * 100).round(),
          child: Container(height: 16, color: Colors.white),
        ),
        Expanded(
          flex: ((1.0 - percentage) * 100).round(),
          child: Container(height: 16, color: Colors.grey[800]),
        ),
      ],
    );
  }
}

class StockfishAnalysisCard extends StatefulWidget {
  final ValueNotifier<StockfishAnalysis> analysisNotifier;

  const StockfishAnalysisCard({super.key, required this.analysisNotifier});

  @override
  State<StockfishAnalysisCard> createState() => _StockfishAnalysisCardState();
}

class _StockfishAnalysisCardState extends State<StockfishAnalysisCard> {
  String _formatPvLine(String pvLine) {
    if (pvLine.isEmpty) return pvLine;
    final moves = pvLine.trim().split(RegExp(r'\s+'));
    final formattedMoves = <String>[];
    for (int i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (move.contains('.')) {
        formattedMoves.add(move);
      } else {
        formattedMoves.add(move);
      }
    }
    String result = '';
    for (int i = 0; i < formattedMoves.length; i++) {
      result += formattedMoves[i];
      if (i < formattedMoves.length - 1) {
        if ((i + 1) % 6 == 0) {
          result += '\n';
        } else {
          result += ' ';
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text(
                  'Stockfish Analysis',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<StockfishAnalysis>(
              valueListenable: widget.analysisNotifier,
              builder: (context, analysis, child) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(6.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (analysis.pvLine != null) ...[
                        Text(
                          'Best Line:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.grey[300],
                          ),
                        ),
                        SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          constraints: BoxConstraints(minHeight: 40),
                          padding: const EdgeInsets.all(6.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey[700]!),
                          ),
                          child: Text(
                            _formatPvLine(analysis.pvLine!),
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              height: 1.4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                      if (analysis.loadingMessage != null) ...[
                        SizedBox(height: 8),
                        Text(
                          analysis.loadingMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[300],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (analysis.pvLine == null &&
                          analysis.evaluation == null &&
                          !analysis.isLoading)
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.psychology_outlined,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Analysis will appear here during gameplay',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? selectedLevel;
  bool? playAsWhite;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    selectedLevel = args?['level'] ?? 1;
    playAsWhite = args?['playAsWhite'] ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Player Color',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Play as White'),
                  leading: Radio<bool>(
                    value: true,
                    groupValue: playAsWhite,
                    onChanged: (value) {
                      setState(() {
                        playAsWhite = value;
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Play as Black'),
                  leading: Radio<bool>(
                    value: false,
                    groupValue: playAsWhite,
                    onChanged: (value) {
                      setState(() {
                        playAsWhite = value;
                      });
                    },
                  ),
                ),
                Divider(color: Colors.grey[700]),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Difficulty Level',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                ...List.generate(7, (index) {
                  final level = index + 1;
                  return ListTile(
                    title: Text(
                      'Level $level${level == 7 ? " (Grandmaster)" : ""}',
                    ),
                    trailing: selectedLevel == level
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      setState(() {
                        selectedLevel = level;
                      });
                    },
                  );
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save, size: 20),
                    label: const Text('Save Settings'),
                    onPressed: () async {
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt(
                          'chess_difficulty_level',
                          selectedLevel!,
                        );
                        await prefs.setBool('play_as_white', playAsWhite!);
                      } catch (e) {
                        debugPrint('Error saving preferences: $e');
                      }
                      if (mounted) {
                        Navigator.pop(context, {
                          'level': selectedLevel,
                          'playAsWhite': playAsWhite,
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
