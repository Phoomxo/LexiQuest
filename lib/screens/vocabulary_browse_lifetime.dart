import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/data/drift_vocabulary_repository.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../runtime/registries/feature_registry.dart';

/// Read-only binding for the existing private vocabulary browser. The canonical
/// repository remains responsible for private and packaged content access.
class VocabularyBrowseRead<T> extends ChangeNotifier {
  VocabularyBrowseRead(this.useCases, this.read, {this.categoryId}) {
    final repository = useCases.vocabulary;
    if (repository is DriftVocabularyRepository) {
      final database = repository.database;
      _ownerChanges = database
          .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
          .listen((_) => refresh(), onError: _fail);
    }
    refresh();
  }

  final VocabularyUseCases useCases;
  final Stream<List<T>> Function(String ownerId) read;
  final String? categoryId;
  StreamSubscription<List<T>>? _subscription;
  StreamSubscription<List<VocabularyCategory>>? _category;
  StreamSubscription<Object?>? _ownerChanges;
  int revision = 0;
  int _epoch = 0;
  bool _disposed = false;
  bool pending = true;
  bool failed = false;
  bool available = true;
  String? ownerId;
  List<T>? data;

  void _fail(Object error, [StackTrace? stack]) {
    if (_disposed) return;
    revision++;
    pending = false;
    failed = true;
    data = null;
    notifyListeners();
  }

  void refresh() {
    if (_disposed) return;
    final epoch = ++_epoch;
    revision++;
    pending = true;
    failed = false;
    available = true;
    data = null;
    _subscription?.cancel();
    _category?.cancel();
    _subscription = null;
    _category = null;
    notifyListeners();
    // Observe synchronous and asynchronous owner/read failures immediately.
    Future<void>.sync(() async {
      final owner = await useCases.owners.getOrCreateActiveOwner();
      if (!_current(epoch)) return;
      ownerId = owner.id;
      final repository = useCases.vocabulary;
      if (categoryId != null && repository is DriftVocabularyRepository) {
        _category = repository
            .watchCategories(owner.id)
            .listen(
              (categories) {
                if (!_current(epoch)) return;
                final exists = categories.any((c) => c.id == categoryId);
                if (!exists) {
                  available = false;
                  pending = false;
                  data = null;
                  revision++;
                  _subscription?.cancel();
                  _subscription = null;
                  notifyListeners();
                } else if (_subscription == null) {
                  available = true;
                  _listen(epoch, owner.id);
                }
              },
              onError: (Object e, StackTrace s) {
                if (_current(epoch)) _fail(e, s);
              },
            );
      } else {
        _listen(epoch, owner.id);
      }
    }).catchError((Object e, StackTrace s) {
      if (_current(epoch)) _fail(e, s);
    });
  }

  void _listen(int epoch, String owner) {
    try {
      _subscription = read(owner).listen(
        (value) {
          if (!_current(epoch)) return;
          revision++;
          pending = false;
          failed = false;
          data = List.unmodifiable(value);
          notifyListeners();
        },
        onError: (Object e, StackTrace s) {
          if (_current(epoch)) _fail(e, s);
        },
      );
    } catch (e, s) {
      if (_current(epoch)) _fail(e, s);
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  Future<bool> admit() async {
    final epoch = _epoch;
    final owner = ownerId;
    try {
      final current = await useCases.owners.getOrCreateActiveOwner();
      if (!_current(epoch) || !available || failed || pending) return false;
      if (current.id != owner) {
        refresh();
        return false;
      }
      return true;
    } catch (e, s) {
      if (_current(epoch)) _fail(e, s);
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _subscription?.cancel();
    _category?.cancel();
    _ownerChanges?.cancel();
    super.dispose();
  }
}

/// Displayed callbacks never regain authority after a visibility transition.
mixin VocabularyBrowseLifetime<W extends StatefulWidget>
    on State<W>, WidgetsBindingObserver {
  int browseGeneration = 0;
  bool browseOpening = false;
  bool _foreground = true;
  bool _visible = false;
  bool _exited = false;
  Listenable? _featureChanges;

  void bindBrowseFeatures(FeatureRegistry? features) {
    final changes = features is Listenable ? features as Listenable : null;
    if (identical(changes, _featureChanges)) return;
    _featureChanges?.removeListener(_featuresChanged);
    _featureChanges = changes;
    _featureChanges?.addListener(_featuresChanged);
  }

  void _featuresChanged() {
    if (mounted) setState(() => browseGeneration++);
  }

  bool get browseVisible =>
      mounted &&
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;
  bool browseCurrent(int generation) =>
      generation == browseGeneration && browseVisible;

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
    final visible = browseVisible;
    if (visible != _visible) browseGeneration++;
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      browseGeneration++;
    });
  }

  void browseExit() {
    _exited = true;
    browseGeneration++;
  }

  @override
  void dispose() {
    browseExit();
    _featureChanges?.removeListener(_featuresChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
