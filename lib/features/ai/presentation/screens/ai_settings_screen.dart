import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../providers/ai_provider.dart';

/// Screen allowing the user to configure and validate their Google Gemini API Key.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _keyController = TextEditingController();
  bool _obscureKey = true;
  bool _isValidating = false;
  String? _errorMessage;
  String? _successMessage;

  // Test Module state
  final _testPromptController = TextEditingController(text: 'Why is the sky blue? Explain in one sentence.');
  String? _testResult;
  bool _isTesting = false;
  String? _testError;

  @override
  void initState() {
    super.initState();
    _loadCurrentKey();
  }

  Future<void> _loadCurrentKey() async {
    final activeKey = ref.read(apiKeyProvider);
    if (activeKey != null) {
      _keyController.text = activeKey;
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _testPromptController.dispose();
    super.dispose();
  }

  /// Opens Google AI Studio in the default system browser.
  Future<void> _openAiStudio() async {
    final url = Uri.parse('https://aistudio.google.com/');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google AI Studio in browser.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  /// Pastes plain text from the clipboard.
  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      setState(() {
        _keyController.text = clipboardData!.text!.trim();
        _errorMessage = null;
        _successMessage = null;
      });
    }
  }

  /// Validates the API key and saves it to secure storage if valid.
  Future<void> _validateAndSave() async {
    final keyStr = _keyController.text.trim();
    if (keyStr.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter or paste an API key first.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isValidating = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final settings = ref.read(aiSettingsProvider);
    final repository = ref.read(aiRepositoryProvider);

    final validationResult = await repository.validateApiKey(keyStr, settings.model);

    if (!mounted) return;

    if (validationResult.isSuccess) {
      // Save API Key securely and update settings model
      await ref.read(apiKeyProvider.notifier).saveKey(keyStr);
      await ref.read(aiSettingsProvider.notifier).updateSettings(
            isEnabled: true,
            apiKeyExists: true,
            lastValidatedAt: DateTime.now(),
          );

      setState(() {
        _isValidating = false;
        _successMessage = 'API key verified successfully. AI features are now enabled!';
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isValidating = false;
        _errorMessage = validationResult.error ?? 'Invalid API key. Please check and try again.';
        _successMessage = null;
      });
    }
  }

  /// Removes the saved API Key and deletes settings.
  Future<void> _removeKey() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove API Key?'),
        content: const Text(
            'This will disable all AI features and delete your API key from this device\'s secure storage. Your notes and flashcards will remain completely intact.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(apiKeyProvider.notifier).removeKey();
      await ref.read(aiSettingsProvider.notifier).clearSettings();
      _keyController.clear();
      setState(() {
        _successMessage = 'API key removed successfully. AI features disabled.';
        _errorMessage = null;
        _testResult = null;
        _testError = null;
      });
    }
  }

  /// Sends a test prompt using the saved API key to verify end-to-end functionality.
  Future<void> _testAi() async {
    final prompt = _testPromptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testError = null;
    });

    final repository = ref.read(aiRepositoryProvider);
    final response = await repository.explainConcept(prompt);

    if (!mounted) return;

    setState(() {
      _isTesting = false;
      if (response.isSuccess) {
        _testResult = response.data;
      } else {
        _testError = response.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final status = ref.watch(aiStatusProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ────────────────────────── SECTION: HEADER STATUS ──────────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            color: status.isReady 
                ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: status.isReady 
                              ? colorScheme.primary.withValues(alpha: 0.1)
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          status.isReady ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                          color: status.isReady ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.isReady ? 'AI Features Enabled' : 'AI Features Disabled',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: status.isReady ? colorScheme.primary : colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              status.isReady 
                                  ? 'Using your custom Gemini API key.'
                                  : 'To use AI features, generate your own API key from Google AI Studio.',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (status.isReady) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('API Key Status', style: textTheme.bodyMedium),
                        Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (settings.lastValidatedAt != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Last Validated', style: textTheme.bodyMedium),
                          Text(
                            DateFormat('yMMMd – kk:mm').format(settings.lastValidatedAt!),
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ────────────────────────── SECTION: MODEL SELECTION ──────────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gemini Model Configuration',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose the Gemini model version. Flash is faster; Pro is better for complex queries.',
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: settings.model,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'gemini-2.5-flash',
                        child: Text('gemini-2.5-flash (Recommended)'),
                      ),
                      DropdownMenuItem(
                        value: 'gemini-2.5-pro',
                        child: Text('gemini-2.5-pro'),
                      ),
                    ],
                    onChanged: (val) async {
                      if (val != null) {
                        await ref.read(aiSettingsProvider.notifier).updateSettings(model: val);
                        if (status.isReady) {
                          // Re-validate key for this model
                          _validateAndSave();
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ────────────────────────── SECTION: SETUP INSTRUCTIONS ──────────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to get a Gemini API Key',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildStep(1, 'Tap "Open Google AI Studio" below to visit the key page.'),
                  _buildStep(2, 'Sign in with your Google account.'),
                  _buildStep(3, 'Tap "Create API key" and copy the generated key string.'),
                  _buildStep(4, 'Return to MindVault, paste the key below, and tap "Validate & Save Key".'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _openAiStudio,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Google AI Studio'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ────────────────────────── SECTION: API KEY PASTE ──────────────────────────
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configure API Key',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Gemini API Key',
                      hintText: 'AIzaSy...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscureKey ? Icons.visibility : Icons.visibility_off,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureKey = !_obscureKey;
                              });
                            },
                          ),
                          if (_keyController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _keyController.clear();
                                setState(() {
                                  _errorMessage = null;
                                  _successMessage = null;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    onChanged: (_) {
                      setState(() {
                        _errorMessage = null;
                        _successMessage = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.paste_rounded, size: 18),
                          label: const Text('Paste Key'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: colorScheme.error),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_successMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isValidating ? null : _validateAndSave,
                          icon: _isValidating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(_isValidating ? 'Verifying...' : 'Validate & Save Key'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (status.hasKey) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _isValidating ? null : _removeKey,
                            icon: Icon(Icons.delete_outline, color: colorScheme.error),
                            label: Text(
                              'Remove Key',
                              style: TextStyle(color: colorScheme.error),
                            ),
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ────────────────────────── SECTION: AI PLAYGROUND TEST ──────────────────────────
          if (status.isReady)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Custom AI Key',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Run a test query to confirm your key generates content correctly.',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _testPromptController,
                      decoration: InputDecoration(
                        labelText: 'Prompt',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isTesting ? null : _testAi,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(_isTesting ? 'Generating...' : 'Send Test Request'),
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.secondary,
                              foregroundColor: colorScheme.onSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_testError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Test Error: $_testError',
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Gemini Response:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Text(_testResult!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStep(int stepNumber, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: colorScheme.secondary.withValues(alpha: 0.1),
            child: Text(
              '$stepNumber',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
