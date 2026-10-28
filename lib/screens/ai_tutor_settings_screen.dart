import 'package:flutter/material.dart';

import '../features/ai_tutor/domain/ai_tutor_contracts.dart';
import '../runtime/app_dependencies.dart';

class AiTutorSettingsScreen extends StatefulWidget {
  const AiTutorSettingsScreen({super.key, this.aiTutor, this.aiUsage});

  final AiTutorController? aiTutor;
  final AiUsageRepository? aiUsage;

  @override
  State<AiTutorSettingsScreen> createState() => _AiTutorSettingsScreenState();
}

class _AiTutorSettingsScreenState extends State<AiTutorSettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  AiTutorController? _tutor;
  AiUsageRepository? _usage;
  AiCancellation? _cancellation;
  AiProviderId _providerId = AiProviderId.gemini;
  List<AiModel> _models = const [];
  String? _model;
  bool _loading = true;
  bool _saving = false;
  bool _hasKey = false;
  bool _providerConsent = false;
  bool _summaryConsent = false;
  String? _error;
  String? _notice;
  List<AiUsageSummary> _usageSummaries = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final resolvedTutor = widget.aiTutor ?? dependencies?.aiTutor;
    final resolvedUsage = widget.aiUsage ?? dependencies?.aiUsage;
    if (identical(resolvedTutor, _tutor) && identical(resolvedUsage, _usage)) {
      return;
    }
    _tutor = resolvedTutor;
    _usage = resolvedUsage;
    _load();
  }

  Future<void> _load() async {
    final tutor = _tutor;
    if (tutor == null) {
      setState(() {
        _loading = false;
        _error = 'AI Tutor is unavailable in this build.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await tutor.loadSettings();
      final usageSummaries = await _usage?.summarize() ?? const [];
      if (!mounted) return;
      setState(() {
        _hasKey = status.hasKey;
        _providerConsent = status.providerConsent;
        _summaryConsent = status.shareLearningSummary;
        _providerId = status.providerId;
        _model = status.model;
        _models = status.model == null
            ? const []
            : [AiModel(id: status.model!)];
        _baseUrlController.text = status.customBaseUrl ?? '';
        _usageSummaries = usageSummaries;
      });
    } on AiTutorException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadModels() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    if (!_providerConsent) {
      setState(() => _error = 'Provider consent is required.');
      return;
    }
    final key = _keyController.text.trim();
    // When an active key is already stored and no new key is typed, use the
    // stored-key path so the participant never needs to re-enter a secret.
    if (key.isEmpty && _hasKey) {
      return _loadModelsFromStoredKey();
    }
    if (key.isEmpty) {
      setState(() => _error = 'Enter an API key.');
      return;
    }
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final models = await tutor.listModels(
        providerId: _providerId,
        key: key,
        customBaseUrl: _providerId == AiProviderId.customOpenAi
            ? _baseUrlController.text.trim()
            : null,
        cancellation: cancellation,
      );
      if (!mounted) return;
      if (models.isEmpty && _providerId != AiProviderId.customOpenAi) {
        setState(() => _error = 'No compatible models were returned.');
        return;
      }
      setState(() {
        _models = models;
        // Discovery never chooses on the participant's behalf.
        _model = null;
        _notice = models.isEmpty
            ? 'Enter the model ID supported by your custom endpoint.'
            : 'Choose a model, then save the active provider.';
      });
    } on AiTutorException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  /// Loads the model list using the credential already in secure storage.
  /// Called when the participant has an active key but has not typed a new one.
  Future<void> _loadModelsFromStoredKey() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final models = await tutor.listModelsForActiveCredential(
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() {
        _models = models;
        // Discovery never chooses on the participant's behalf.
        _model = null;
        _notice = models.isEmpty
            ? 'Enter the model ID supported by your custom endpoint.'
            : 'Choose a model, then save the active provider.';
      });
    } on AiTutorException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  Future<void> _validateAndSave() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final key = _keyController.text.trim();
    final model = _model?.trim() ?? '';
    if (!_providerConsent) {
      setState(() => _error = 'Provider consent is required.');
      return;
    }
    if (model.isEmpty) {
      setState(() => _error = 'Select or enter a model.');
      return;
    }
    // If the participant has an active stored key and has not typed a new one,
    // use configureActiveModel so the key never travels back to the UI layer.
    if (key.isEmpty && _hasKey) {
      return _configureActiveModel(model: model);
    }
    if (key.isEmpty) {
      setState(() => _error = 'Enter an API key.');
      return;
    }
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await tutor.configure(
        key: key,
        providerConsent: true,
        shareLearningSummary: _summaryConsent,
        providerId: _providerId,
        model: model,
        customBaseUrl: _providerId == AiProviderId.customOpenAi
            ? _baseUrlController.text.trim()
            : null,
        cancellation: cancellation,
      );
      if (!mounted) return;
      _keyController.clear();
      setState(() {
        _hasKey = true;
        _notice = 'Key validated and stored securely.';
      });
    } on AiTutorException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  /// Saves only the model and summary-consent flag using the credential
  /// already in secure storage. Called when the participant has an active key
  /// and has not typed a replacement key.
  Future<void> _configureActiveModel({required String model}) async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await tutor.configureActiveModel(
        model: model,
        shareLearningSummary: _summaryConsent,
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() => _notice = 'Model updated and stored securely.');
    } on AiTutorException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  Future<void> _saveConsents() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await tutor.updateConsents(
        providerConsent: _providerConsent,
        shareLearningSummary: _summaryConsent,
      );
      if (mounted) setState(() => _notice = 'Consent settings saved.');
    } on AiTutorException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    final tutor = _tutor;
    if (tutor == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete API key?'),
        content: const Text(
          'AI Tutor will stop calling the selected provider until a new key '
          'and model are validated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete key'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await tutor.removeKey();
      if (!mounted) return;
      _keyController.clear();
      setState(() {
        _hasKey = false;
        _providerConsent = false;
        _summaryConsent = false;
        _models = const [];
        _model = null;
        _notice = 'API key and provider consent removed.';
      });
    } on AiTutorException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearUsage() async {
    final usage = _usage;
    if (usage == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear local API usage?'),
        content: const Text(
          'This permanently deletes local provider, model, token, latency, '
          'and outcome totals. API keys and tutor messages are not part of '
          'this ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear usage'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await usage.clear();
      final summaries = await usage.summarize();
      if (mounted) {
        setState(() {
          _usageSummaries = summaries;
          _notice = 'Local API usage deleted.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _keyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Provider BYOK')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _hasKey ? 'Status: active key' : 'Status: no key',
                    key: const ValueKey('ai-key-status'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your key is stored in secure device storage. Requests go '
                    'directly to the provider you select. There is no automatic '
                    'fallback or retry.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AiProviderId>(
                    key: const ValueKey('ai-provider-select'),
                    initialValue: _providerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final config in AiProviderConfig.all)
                        DropdownMenuItem(
                          value: config.id,
                          child: Text(
                            config.isExperimental
                                ? '${config.displayName} (experimental)'
                                : config.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _providerId = value;
                              _models = const [];
                              _model = null;
                              _error = null;
                              _notice = null;
                            });
                          },
                  ),
                  if (_providerId == AiProviderId.customOpenAi) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('ai-custom-base-url'),
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'HTTPS base URL',
                        helperText:
                            'The API key and tutor text will be sent to this host.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('ai-key-input'),
                    controller: _keyController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _providerConsent,
                    title: const Text(
                      'Allow tutor text to be sent to the selected provider',
                    ),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _providerConsent = value ?? false;
                            if (!_providerConsent) _summaryConsent = false;
                          }),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _summaryConsent,
                    title: const Text('Share a bounded learning summary'),
                    subtitle: const Text(
                      'Only aggregate accuracy and up to three weaknesses are '
                      'sent; account identifiers and raw history are excluded.',
                    ),
                    onChanged: !_providerConsent || _saving
                        ? null
                        : (value) =>
                              setState(() => _summaryConsent = value ?? false),
                  ),
                  OutlinedButton(
                    key: const ValueKey('ai-load-models'),
                    onPressed: _saving ? null : _loadModels,
                    child: const Text('Validate key and load models'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Saving runs one small validation request and may use a '
                    'small amount of provider quota. The previous active '
                    'configuration remains unchanged if validation fails.',
                  ),
                  if (_providerId == AiProviderId.customOpenAi &&
                      _models.isEmpty) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('ai-custom-model'),
                      decoration: const InputDecoration(
                        labelText: 'Model ID',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => _model = value.trim(),
                    ),
                  ] else if (_models.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('ai-model-select'),
                      initialValue: _model,
                      isExpanded: true,
                      hint: const Text('Select a model'),
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final model in _models)
                          DropdownMenuItem(
                            value: model.id,
                            child: Text(
                              model.displayName ?? model.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _model = value),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      key: const ValueKey('ai-settings-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Text(_notice!, key: const ValueKey('ai-settings-notice')),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('ai-save-key'),
                    onPressed: _saving ? null : _validateAndSave,
                    child: const Text('Save active provider'),
                  ),
                  if (_saving)
                    TextButton(
                      onPressed: () => _cancellation?.cancel(),
                      child: const Text('Cancel request'),
                    ),
                  if (_hasKey) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _saving ? null : _saveConsents,
                      child: const Text('Save consent settings'),
                    ),
                    TextButton(
                      key: const ValueKey('ai-remove-key'),
                      onPressed: _saving ? null : _removeKey,
                      child: const Text('Delete API key'),
                    ),
                  ],
                  if (_usage != null) ...[
                    const Divider(height: 32),
                    Text(
                      'Local API usage (90 days)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_usageSummaries.isEmpty)
                      const Text('No local API usage recorded.')
                    else
                      for (final summary in _usageSummaries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${summary.providerId.name} / ${summary.model}',
                          ),
                          subtitle: Text(
                            '${summary.requestCount} requests · '
                            '${summary.totalTokens} tokens · cost: '
                            '${summary.providerReportedCostMicrosUsd == null ? 'unknown' : '${summary.providerReportedCostMicrosUsd} µUSD'}',
                          ),
                        ),
                    TextButton(
                      key: const ValueKey('ai-clear-usage'),
                      onPressed: _saving ? null : _clearUsage,
                      child: const Text('Clear local usage'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  String _failureText(AiFailureCode code) => switch (code) {
    AiFailureCode.invalidKey => 'Invalid API key.',
    AiFailureCode.requestRejected =>
      'The provider rejected this model or request. Choose another listed '
          'model or check provider restrictions. Your previous configuration '
          'is still active.',
    AiFailureCode.quota => 'Provider quota is exhausted.',
    AiFailureCode.rateLimited => 'Provider rate limit reached.',
    AiFailureCode.offline => 'The device is offline.',
    AiFailureCode.timeout => 'The provider request timed out.',
    AiFailureCode.providerUnavailable =>
      'The selected provider is temporarily unavailable.',
    AiFailureCode.malformedResponse =>
      'The provider returned an unsupported response.',
    AiFailureCode.consentRequired => 'Provider consent is required.',
    AiFailureCode.cancelled => 'The provider request was cancelled.',
    AiFailureCode.secureStorage => 'Secure device storage is unavailable.',
    AiFailureCode.missingKey => 'Enter an API key.',
    AiFailureCode.missingModel => 'Select or enter a model.',
    AiFailureCode.blocked => 'The provider blocked this request.',
    AiFailureCode.validation => 'The entered value is invalid.',
    AiFailureCode.unsafeEndpoint =>
      'Use a public HTTPS endpoint; local and private network hosts are blocked.',
  };
}
