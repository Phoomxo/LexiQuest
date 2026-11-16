import 'package:flutter/scheduler.dart';
import 'vocabulary_browse_lifetime.dart';
import 'package:flutter/material.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_category.dart';
import '../features/vocabulary/domain/vocabulary_failure.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import '../navigation/app_routes.dart';
import 'vocab_list_screen.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, this.vocabulary, this.featureRegistry});

  final VocabularyUseCases? vocabulary;

  final FeatureRegistry? featureRegistry;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage>
    with WidgetsBindingObserver, VocabularyBrowseLifetime<CategoriesPage> {
  VocabularyUseCases? _vocabulary;
  VocabularyBrowseRead<VocabularyCategory>? _categories;
  FeatureRegistry? _boundFeatures;
  final _actionChanges = ChangeNotifier();
  Listenable? _actionFeatures;
  Route<void>? _actionDialog;
  int _actionEpoch = 0;
  bool _actionForeground = true;
  bool _actionExited = false;

  void _retireAction() {
    _actionEpoch++;
    _actionChanges.notifyListeners();
  }

  bool get _actionVisible =>
      mounted &&
      !_actionExited &&
      _actionForeground &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent != false ||
          _actionDialog?.isCurrent == true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _actionForeground = state == AppLifecycleState.resumed;
    _retireAction();
  }

  void _bindVocabulary() {
    final next =
        widget.vocabulary ?? AppDependenciesScope.maybeOf(context)?.vocabulary;
    final features = _features;
    if (!identical(features, _boundFeatures)) {
      browseGeneration++;
      _retireAction();
      _actionFeatures?.removeListener(_retireAction);
      _actionFeatures = features is Listenable ? features as Listenable : null;
      _actionFeatures?.addListener(_retireAction);
    }
    _boundFeatures = features;
    bindBrowseFeatures(features);
    if (identical(next, _vocabulary)) return;
    browseGeneration++;
    _retireAction();
    _categories?.dispose();
    _vocabulary = next;
    _categories = next == null
        ? null
        : VocabularyBrowseRead(next, next.vocabulary.watchCategories);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindVocabulary();
    if (_actionDialog != null && !_actionVisible) _retireAction();
  }

  @override
  void didUpdateWidget(CategoriesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindVocabulary();
  }

  void _retry(int generation, int revision) {
    final read = _categories;
    if (!browseCurrent(generation) ||
        browseOpening ||
        !_admitted ||
        read == null ||
        revision != read.revision ||
        read.pending)
      return;
    read.refresh();
  }

  Future<void> _openCategory(
    VocabularyCategory category,
    int generation,
    int revision,
  ) async {
    final read = _categories;
    if (!browseCurrent(generation) ||
        browseOpening ||
        !_admitted ||
        read == null ||
        read.revision != revision)
      return;
    browseOpening = true;
    try {
      if (!await read.admit() ||
          !browseCurrent(generation) ||
          read.revision != revision ||
          !_admitted)
        return;
      final explicitVocabulary = widget.vocabulary;
      final explicitFeatures = widget.featureRegistry;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'vocabulary/category',
          builder: (_) => VocabListScreen(
            vocabulary: explicitVocabulary,
            featureRegistry: explicitFeatures,
            categoryId: category.id,
            categoryName: category.name,
          ),
        ),
      );
    } finally {
      browseOpening = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _actionExited = true;
    _retireAction();
    _actionFeatures?.removeListener(_retireAction);
    _actionChanges.dispose();
    _categories?.dispose();
    super.dispose();
  }

  FeatureRegistry? get _features =>
      widget.featureRegistry ?? AppDependenciesScope.maybeOf(context)?.features;

  bool get _admitted =>
      mounted && _features?.isEnabled(Feature.vocabulary) == true;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        browseExit();
        _actionExited = true;
        _retireAction();
      }
    },
    child: ProductionFeatureGate(
      feature: Feature.vocabulary,
      registry: _features,
      builder: _buildContent,
    ),
  );

  Widget _buildContent(BuildContext context) {
    final useCases = _vocabulary;
    final actionGeneration = browseGeneration;
    return Scaffold(
      appBar: AppBar(title: const Text('คลังคำศัพท์')),
      body: useCases == null
          ? const _LocalDataUnavailable()
          : ListenableBuilder(
              listenable: _categories!,
              builder: (context, _) {
                final read = _categories!;
                final generation = browseGeneration;
                final revision = read.revision;
                if (read.failed) {
                  return _FailureState(
                    onRetry: () => _retry(generation, revision),
                  );
                }
                if (read.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final categories = read.data!;
                if (categories.isEmpty) {
                  return const Center(
                    child: Text(
                      'ยังไม่มีหมวดหมู่\nเพิ่มหมวดหมู่เพื่อเริ่มเก็บคำศัพท์',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    void openCategory() {
                      _openCategory(category, generation, revision);
                    }

                    return Card(
                      child: MenuActionBinding(
                        key: ValueKey(category.id),
                        ownerId: category.isReadOnly ? null : category.ownerId,
                        id: 'vocabulary/category/$index',
                        label: category.isReadOnly
                            ? 'เปิดหมวดอ่านอย่างเดียว ${category.name}'
                            : 'เปิดหมวดส่วนตัว ${category.name}',
                        onInvoke: openCategory,
                        child: ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(category.name),
                          subtitle: const Text('แตะเพื่อดูคำศัพท์'),
                          trailing: category.isReadOnly
                              ? null
                              : IconButton(
                                  tooltip: 'ลบหมวดหมู่',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _confirmDelete(
                                    context,
                                    useCases,
                                    category,
                                    generation,
                                    revision,
                                  ),
                                ),
                          onTap: openCategory,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: useCases == null
          ? null
          : MenuActionBinding(
              id: 'vocabulary/add-category',
              label: 'เพิ่มหมวดหมู่',
              onInvoke: () =>
                  _showAddCategory(context, useCases, actionGeneration),
              child: FloatingActionButton.extended(
                key: const ValueKey('add-category'),
                heroTag: 'categories-add',
                onPressed: () =>
                    _showAddCategory(context, useCases, actionGeneration),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มหมวดหมู่'),
              ),
            ),
    );
  }

  Future<void> _showAddCategory(
    BuildContext context,
    VocabularyUseCases useCases,
    int generation,
  ) => _showCategoryAction(useCases, generation);

  Future<void> _confirmDelete(
    BuildContext context,
    VocabularyUseCases useCases,
    VocabularyCategory category,
    int generation,
    int revision,
  ) async {
    if (_categories?.revision != revision) return;
    await _showCategoryAction(useCases, generation, category: category);
  }

  Future<void> _showCategoryAction(
    VocabularyUseCases useCases,
    int generation, {
    VocabularyCategory? category,
  }) async {
    if (!browseCurrent(generation) ||
        browseOpening ||
        !_admitted ||
        !identical(useCases, _vocabulary))
      return;
    browseOpening = true;
    final epoch = ++_actionEpoch;
    final read = _categories!;
    bool allowed() =>
        _actionVisible &&
        epoch == _actionEpoch &&
        _admitted &&
        identical(useCases, _vocabulary);
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => _AddCategoryDialog(
        vocabulary: useCases,
        admitted: allowed,
        reconcileAdmitted: () =>
            _actionVisible && _admitted && identical(useCases, _vocabulary),
        changes: _actionChanges,
        read: read,
        category: category,
      ),
    );
    _actionDialog = route;
    try {
      await Navigator.of(context).push(route);
    } finally {
      _actionDialog = null;
      browseOpening = false;
      if (mounted) setState(() {});
    }
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({
    required this.vocabulary,
    required this.admitted,
    required this.reconcileAdmitted,
    required this.changes,
    required this.read,
    this.category,
  });
  final VocabularyUseCases vocabulary;
  final bool Function() admitted;
  final bool Function() reconcileAdmitted;
  final Listenable changes;
  final VocabularyBrowseRead<VocabularyCategory> read;
  final VocabularyCategory? category;
  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  String? _formOwner;
  bool _saving = false;
  bool _filling = false;
  bool _ownerRetired = false;
  bool _reading = false;
  Future<void>? _ownerReady;
  bool _closed = false;
  bool _retired = false;
  int _generation = 0;
  int _viewEpoch = 0;
  String? _error;
  VocabularyCategory? _committedCategory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _formOwner = widget.category?.ownerId ?? widget.read.ownerId;
    widget.changes.addListener(_changed);
    widget.read.addListener(_changed);
    _ownerReady = _bindLocalOwner();
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (_formOwner != null &&
        widget.read.ownerId != null &&
        _formOwner != widget.read.ownerId) {
      _ownerRetired = true;
    }
    if (!widget.admitted() ||
        (_formOwner != null &&
            widget.read.ownerId != null &&
            _formOwner != widget.read.ownerId) ||
        (widget.category != null &&
            !_saving &&
            widget.read.data != null &&
            !widget.read.data!.any(
              (c) =>
                  c.id == widget.category!.id &&
                  c.ownerId == widget.category!.ownerId &&
                  c.localRevision == widget.category!.localRevision,
            ))) {
      _retired = true;
      _viewEpoch++;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false ||
        !TickerMode.valuesOf(context).enabled) {
      _retired = true;
      _viewEpoch++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted)
      setState(() {
        _retired = true;
        _viewEpoch++;
      });
  }

  bool get _current =>
      mounted &&
      !_closed &&
      !_retired &&
      widget.admitted() &&
      ModalRoute.of(context)?.isCurrent == true &&
      TickerMode.valuesOf(context).enabled;
  bool _displayed(int generation) => generation == _generation && _current;

  bool get _readCurrent =>
      mounted &&
      !_closed &&
      !_ownerRetired &&
      widget.read.ownerId == _formOwner &&
      widget.reconcileAdmitted() &&
      ModalRoute.of(context)?.isCurrent == true &&
      TickerMode.valuesOf(context).enabled;

  Future<bool> _ownerCurrent({bool readOnly = false}) async {
    bool current() => readOnly ? _readCurrent : _current;
    if (!current()) return false;
    final owner = await widget.vocabulary.owners.getOrCreateActiveOwner();
    if (!current()) return false;
    if (_formOwner != null && owner.id != _formOwner) {
      setState(() {
        _retired = true;
        _ownerRetired = true;
      });
      return false;
    }
    _formOwner = owner.id;
    return true;
  }

  Future<void> _bindLocalOwner() async {
    if (_reading || _closed || _retired) return;
    _reading = true;
    try {
      // The future is observed immediately, including synchronous read failures.
      final owner = await widget.vocabulary.owners.getOrCreateActiveOwner();
      if (!mounted || _closed || _retired) return;
      if (_formOwner != null && owner.id != _formOwner) {
        _retired = true;
        _ownerRetired = true;
      } else {
        _formOwner = owner.id;
        _error = null;
      }
    } catch (_) {
      if (mounted && !_closed)
        _error = 'ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่';
    } finally {
      _reading = false;
      if (mounted && !_closed) setState(() {});
    }
  }

  void _message(String message) {
    if (_current) setState(() => _error = message);
  }

  void _close(int generation) {
    // A retired dialog may still be explicitly closed, but never pop a cover.
    if (!mounted ||
        _closed ||
        generation != _generation ||
        ModalRoute.of(context)?.isCurrent != true)
      return;
    _closed = true;
    Navigator.pop(context);
  }

  Future<Map<String, Object?>> _save(
    int generation, {
    String? expectedOwnerId,
  }) async {
    final pending = _committedCategory;
    if (generation != _generation ||
        _filling ||
        _saving ||
        (pending == null ? !_current : !_readCurrent))
      return {'status': 'busy'};
    final registry = MenuActionScope.maybeOf(context);
    final revision = registry?.snapshot()['revision'];
    final sessionGeneration = registry?.sessionGeneration;
    final viewEpoch = _viewEpoch;
    bool allowed() =>
        _current &&
        (expectedOwnerId == null ||
            registry?.currentOwner() == expectedOwnerId &&
                registry?.snapshot()['revision'] == revision);
    bool verificationAllowed() =>
        _current &&
        (expectedOwnerId == null ||
            registry?.currentOwner() == expectedOwnerId &&
                registry?.sessionGeneration == sessionGeneration);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _ownerReady;
      if (_formOwner == null) {
        _message('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่');
        return {'status': 'failed'};
      }
      if (pending != null) {
        return await _verifySaved(
          pending,
          () =>
              _readCurrent &&
              viewEpoch == _viewEpoch &&
              (expectedOwnerId == null ||
                  registry?.currentOwner() == expectedOwnerId &&
                      registry?.sessionGeneration == sessionGeneration),
        );
      }
      if (!await _ownerCurrent() || !allowed()) return {'status': 'stale'};
      if (widget.category case final category?) {
        final categories = await widget.vocabulary.vocabulary
            .watchCategories(_formOwner!)
            .first;
        if (!await _ownerCurrent() || !allowed()) return {'status': 'stale'};
        if (!categories.any(
          (c) =>
              c.id == category.id &&
              c.ownerId == _formOwner &&
              c.localRevision == category.localRevision &&
              !c.isDeleted &&
              !c.isReadOnly,
        )) {
          setState(() => _retired = true);
          return {'status': 'stale'};
        }
        await widget.vocabulary.deleteCategory(
          category.id,
          expectedOwnerId: _formOwner,
          mutationAllowed: allowed,
        );
        if (await _ownerCurrent() && verificationAllowed()) _close(_generation);
        return {'status': 'invoked'};
      }
      final saved = await widget.vocabulary.createCategory(
        _controller.text,
        expectedOwnerId: _formOwner,
        mutationAllowed: allowed,
      );
      if (expectedOwnerId != null) _committedCategory = saved;
      if (!await _ownerCurrent() || !verificationAllowed())
        return {'status': 'stale'};
      if (expectedOwnerId == null) {
        _close(_generation);
        return {'status': 'invoked'};
      }
      _committedCategory = saved;
      return await _verifySaved(saved, verificationAllowed);
    } on InvalidVocabularyFailure catch (failure) {
      if (failure.field == 'owner') {
        if (mounted && !_closed) {
          setState(() {
            _retired = true;
            _ownerRetired = true;
          });
        }
        return {'status': 'stale'};
      }
      _message('กรุณากรอกชื่อหมวดหมู่ให้ถูกต้อง');
      return {'status': 'invalid'};
    } on DuplicateVocabularyFailure {
      _message('มีหมวดหมู่นี้แล้ว');
      return {'status': 'duplicate'};
    } catch (_) {
      try {
        if (await _ownerCurrent()) {
          _message(
            widget.category == null
                ? 'ยังยืนยันผลการบันทึกไม่ได้ กรุณาตรวจหมวดหมู่ก่อนลองใหม่'
                : 'ยังยืนยันผลการลบไม่ได้ กรุณาตรวจหมวดหมู่ก่อนลองใหม่',
          );
        }
      } catch (_) {
        _message('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่');
      }
      return {'status': 'outcome_unknown'};
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, Object?>> _verifySaved(
    VocabularyCategory saved,
    bool Function() allowed,
  ) async {
    try {
      if (!await _ownerCurrent(readOnly: true) || !allowed())
        return {'status': 'stale'};
      final records = await widget.vocabulary.vocabulary
          .watchCategories(saved.ownerId)
          .first;
      final persisted = records
          .where(
            (record) =>
                record.id == saved.id &&
                record.ownerId == saved.ownerId &&
                record.name == saved.name &&
                record.normalizedName == saved.normalizedName &&
                record.localRevision == saved.localRevision &&
                !record.isDeleted,
          )
          .firstOrNull;
      if (persisted == null) return {'status': 'outcome_unknown'};
      if (!await _ownerCurrent(readOnly: true) || !allowed())
        return {'status': 'stale'};
      _committedCategory = null;
      _close(_generation);
      return {
        'status': 'saved',
        'record': {
          'categoryId': persisted.id,
          'name': persisted.name,
          'revision': persisted.localRevision,
        },
      };
    } catch (_) {
      _message('บันทึกแล้ว แต่ยังตรวจสอบผลไม่ได้ กรุณาปิดแล้วตรวจหมวดหมู่');
      return {'status': 'outcome_unknown'};
    }
  }

  @override
  void dispose() {
    _closed = true;
    widget.changes.removeListener(_changed);
    widget.read.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = ++_generation;
    final retired = _committedCategory != null
        ? !_readCurrent
        : _retired || !widget.admitted();
    final category = widget.category;
    final dialog = PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closed = true;
      },
      child: AlertDialog(
        title: Text(category == null ? 'เพิ่มหมวดหมู่' : 'ลบหมวดหมู่'),
        scrollable: true,
        content: retired
            ? const Text('ข้อมูลหรือหน้าจอเปลี่ยนไปแล้ว กรุณาปิดและเปิดใหม่')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category != null)
                    Text(
                      'ลบ “${category.name}” และซ่อนคำศัพท์ในหมวดนี้หรือไม่',
                    ),
                  if (category == null)
                    TextField(
                      key: const ValueKey('category-name-field'),
                      controller: _controller,
                      enabled: !_saving && _committedCategory == null,
                      autofocus: true,
                      maxLength: maxCategoryNameLength,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อหมวดหมู่',
                      ),
                      onChanged: (_) {
                        if (_displayed(generation)) setState(() {});
                      },
                      onSubmitted: (_) => _save(generation),
                    ),
                  if (_error != null) Text(_error!),
                  if (_error != null && !_saving)
                    TextButton(
                      onPressed: _reading
                          ? null
                          : () {
                              if (_displayed(generation))
                                _ownerReady = _bindLocalOwner();
                            },
                      child: const Text('ลองใหม่'),
                    ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => _close(generation),
            child: const Text('ยกเลิก'),
          ),
          if (!retired)
            FilledButton(
              key: const ValueKey('save-category'),
              onPressed: _saving || _committedCategory != null
                  ? null
                  : () => _save(generation),
              child: Text(category == null ? 'บันทึก' : 'ลบ'),
            ),
        ],
      ),
    );
    if (category != null) return dialog;
    return MenuActionBinding(
      id: 'vocabulary/category-fill',
      label: 'กรอกชื่อหมวดหมู่ (ยังไม่บันทึก)',
      ownerId: _formOwner,
      onInvoke: null,
      fields: const {'name': maxCategoryNameLength},
      onForm: _formOwner == null || retired
          ? null
          : (values) async {
              if (!_displayed(generation) ||
                  _saving ||
                  _filling ||
                  _committedCategory != null) {
                return {'status': 'busy'};
              }
              _filling = true;
              try {
                if (!await _ownerCurrent() ||
                    !_displayed(generation) ||
                    _saving)
                  return {'status': 'stale'};
                setState(() => _controller.text = values['name']!);
                return {'status': 'filled', 'values': values};
              } catch (_) {
                _message('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่');
                return {'status': 'failed'};
              } finally {
                _filling = false;
              }
            },
      child: MenuActionBinding(
        id: 'vocabulary/category-save',
        label: 'บันทึกหมวดหมู่และตรวจผล',
        ownerId: _formOwner,
        revisionKey: _controller.text,
        onInvoke: null,
        onForm: _formOwner == null || retired
            ? null
            : (_) => _save(generation, expectedOwnerId: _formOwner),
        child: dialog,
      ),
    );
  }
}

class _LocalDataUnavailable extends StatelessWidget {
  const _LocalDataUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'เปิดฐานข้อมูลในเครื่องไม่สำเร็จ\nกรุณาปิดและเปิดแอปใหม่',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('อ่านหมวดหมู่ไม่สำเร็จ'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
          ],
        ),
      ),
    );
  }
}
