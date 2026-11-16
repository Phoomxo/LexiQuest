import 'package:flutter/material.dart';

/// A retired control never regains its old admission when its route/tab returns.
abstract class ReviewMutationState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  int mutationGeneration = 0;
  bool _foreground = true;

  bool get mutationVisible =>
      mounted &&
      _foreground &&
      TickerMode.of(context) &&
      ModalRoute.of(context)?.isCurrent != false;

  bool mutationCurrent(int generation) =>
      mounted && generation == mutationGeneration && mutationVisible;

  void retireMutation() {
    mutationGeneration++;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!mutationVisible) retireMutation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) retireMutation();
    });
  }

  @override
  void dispose() {
    retireMutation();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
