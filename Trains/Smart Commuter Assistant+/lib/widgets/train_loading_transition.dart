import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class TrainLoadingTransition extends StatefulWidget {
  final bool isLoading;
  final Widget child;
  final String loadingLabel;
  final String arrivalLabel;
  final Duration fadeDuration;
  final Color backgroundColor;

  const TrainLoadingTransition({
    super.key,
    required this.isLoading,
    required this.child,
    this.loadingLabel = 'Loading your journey...',
    this.arrivalLabel = 'Arriving at station...',
    this.fadeDuration = const Duration(milliseconds: 420),
    this.backgroundColor = const Color(0xFFF3F4F6),
  });

  @override
  State<TrainLoadingTransition> createState() => _TrainLoadingTransitionState();
}

enum _LoaderPhase {
  loading,
  stopping,
  done,
}

class _TrainLoadingTransitionState extends State<TrainLoadingTransition>
    with TickerProviderStateMixin {
  static const Duration _runDuration = Duration(milliseconds: 1700);
  static const Duration _stopDuration = Duration(milliseconds: 900);
  static const Duration _stationPauseDuration = Duration(milliseconds: 260);
  static const double _loopStart = -0.24;
  static const double _loopEnd = 1.24;
  static const double _stationStop = 0.5;

  late final AnimationController _runController;
  late final AnimationController _stopController;

  _LoaderPhase _phase = _LoaderPhase.loading;
  bool _showChild = false;
  double _stopStart = 0;

  @override
  void initState() {
    super.initState();
    _runController = AnimationController(vsync: this, duration: _runDuration);
    _stopController = AnimationController(vsync: this, duration: _stopDuration);

    if (widget.isLoading) {
      _phase = _LoaderPhase.loading;
      _showChild = false;
      _runController.repeat();
    } else {
      _phase = _LoaderPhase.done;
      _showChild = true;
      _runController.value = 0.5;
    }
  }

  @override
  void didUpdateWidget(covariant TrainLoadingTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading == widget.isLoading) {
      return;
    }

    if (widget.isLoading) {
      _resetToLoading();
    } else {
      _startStopSequence();
    }
  }

  void _resetToLoading() {
    _stopController.stop();
    _stopController.value = 0;
    _runController.repeat();
    if (!mounted) return;
    setState(() {
      _phase = _LoaderPhase.loading;
      _showChild = false;
    });
  }

  Future<void> _startStopSequence() async {
    if (!mounted) return;
    _stopStart = _runController.value;
    _runController.stop();
    setState(() {
      _phase = _LoaderPhase.stopping;
      _showChild = false;
    });

    try {
      await _stopController.forward(from: 0);
    } catch (_) {
      return;
    }

    if (!mounted || widget.isLoading) {
      return;
    }

    await Future<void>.delayed(_stationPauseDuration);
    if (!mounted || widget.isLoading) {
      return;
    }

    setState(() {
      _phase = _LoaderPhase.done;
      _showChild = true;
    });
  }

  @override
  void dispose() {
    _runController.dispose();
    _stopController.dispose();
    super.dispose();
  }

  double _trainProgress() {
    switch (_phase) {
      case _LoaderPhase.loading:
        return lerpDouble(_loopStart, _loopEnd, _runController.value)!;
      case _LoaderPhase.stopping:
        final start = lerpDouble(_loopStart, _loopEnd, _stopStart)!;
        final eased = Curves.easeOutCubic.transform(_stopController.value);
        return lerpDouble(start, _stationStop, eased)!;
      case _LoaderPhase.done:
        return _stationStop;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _showChild ? 1 : 0,
          duration: widget.fadeDuration,
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
        IgnorePointer(
          ignoring: _showChild,
          child: AnimatedOpacity(
            opacity: _showChild ? 0 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: Container(
              color: widget.backgroundColor,
              alignment: Alignment.center,
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[
                  _runController,
                  _stopController,
                ]),
                builder: (context, _) {
                  return _TrainLoadingScene(
                    phase: _phase,
                    loadingLabel: widget.loadingLabel,
                    arrivalLabel: widget.arrivalLabel,
                    trainProgress: _trainProgress(),
                    runProgress: _runController.value,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrainLoadingScene extends StatelessWidget {
  final _LoaderPhase phase;
  final String loadingLabel;
  final String arrivalLabel;
  final double trainProgress;
  final double runProgress;

  const _TrainLoadingScene({
    required this.phase,
    required this.loadingLabel,
    required this.arrivalLabel,
    required this.trainProgress,
    required this.runProgress,
  });

  @override
  Widget build(BuildContext context) {
    final bool isStopping = phase == _LoaderPhase.stopping;
    final String label = isStopping ? arrivalLabel : loadingLabel;
    final double bobOffset = phase == _LoaderPhase.loading
        ? math.sin(runProgress * math.pi * 10) * 1.8
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AspectRatio(
              aspectRatio: 3.4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double width = constraints.maxWidth;
                  final double height = constraints.maxHeight;
                  final double trainWidth = width * 0.24;
                  final double trainHeight = height * 0.24;
                  final double maxLeft = width - trainWidth;
                  final double left =
                      (maxLeft * trainProgress).clamp(0, maxLeft).toDouble();

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: height * 0.66,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Positioned(
                        left: width * 0.47,
                        top: height * 0.42,
                        child: const _StationMarker(),
                      ),
                      Positioned(
                        left: left,
                        top: (height * 0.48) + bobOffset,
                        child: _TrainBody(
                          width: trainWidth,
                          height: trainHeight,
                          isStopping: isStopping,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationMarker extends StatelessWidget {
  const _StationMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF0EA5E9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x300EA5E9),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.train_rounded,
            size: 10,
            color: Colors.white,
          ),
        ),
        Container(
          width: 3,
          height: 22,
          color: const Color(0xFF94A3B8),
        ),
      ],
    );
  }
}

class _TrainBody extends StatelessWidget {
  final double width;
  final double height;
  final bool isStopping;

  const _TrainBody({
    required this.width,
    required this.height,
    required this.isStopping,
  });

  @override
  Widget build(BuildContext context) {
    final double wheelSize = height * 0.18;

    return Column(
      children: [
        Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: width * 0.12),
          decoration: BoxDecoration(
            color:
                isStopping ? const Color(0xFF0EA5E9) : const Color(0xFFE34262),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF9F1239), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x280F172A),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.directions_transit_filled_rounded,
                size: 15,
                color: Colors.white,
              ),
              SizedBox(width: width * 0.06),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List<Widget>.generate(2, (index) {
                    return Container(
                      width: width * 0.13,
                      height: height * 0.40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: height * 0.06),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: wheelSize,
              height: wheelSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF475569),
              ),
            ),
            SizedBox(width: width - (wheelSize * 2)),
            Container(
              width: wheelSize,
              height: wheelSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
